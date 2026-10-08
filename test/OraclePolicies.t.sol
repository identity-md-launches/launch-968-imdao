// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Fixture} from "./helpers/Fixture.sol";
import {FeeHook} from "../src/FeeHook.sol";
import {MockOracle} from "../src/MockOracle.sol";
import {PolicyReader} from "../src/Policies.sol";
import {RestrictedGovernor} from "../src/RestrictedGovernor.sol";
import {Test} from "forge-std/Test.sol";

contract OracleTest is Fixture {
    bytes32 private constant Q = keccak256("fixture question with frozen definitions");

    function _ask() internal returns (bytes32) {
        bytes32 proposalId = _queue(address(oracle), abi.encodeCall(MockOracle.request, (Q)));
        _execute(proposalId);
        return oracle.pendingId();
    }

    function _envelope(bytes32 id, bool answer) internal view returns (bytes memory) {
        return
            abi.encode(
                MockOracle.Envelope(id, block.chainid, address(oracle), Q, answer, keccak256("fixture evidence"))
            );
    }

    function _deliver(bytes memory data) internal {
        vm.prank(responder);
        delivery.deliver(oracle, data);
    }

    function test_pendingUnknownNoPaymentNonceAndFalseAnswer() public {
        uint256 daoCash = dao.balanceOf(address(treasury));
        bytes32 id = _ask();
        assertEq(id, keccak256(abi.encode(uint256(1), block.chainid, address(oracle), Q)));
        (
            bytes32 question,
            uint256 chain,
            uint256 expiry,
            MockOracle.Status status,
            MockOracle.Answer answer,
            bytes32 evidence
        ) = oracle.requests(id);
        assertEq(question, Q);
        assertEq(chain, block.chainid);
        assertEq(expiry, vm.getBlockTimestamp() + 3600);
        assertEq(uint256(status), uint256(MockOracle.Status.Pending));
        assertEq(uint256(answer), uint256(MockOracle.Answer.UNKNOWN));
        assertEq(evidence, bytes32(0));
        _deliver(_envelope(id, false));
        (,,, status, answer, evidence) = oracle.requests(id);
        assertEq(uint256(status), uint256(MockOracle.Status.Answered));
        assertEq(uint256(answer), uint256(MockOracle.Answer.NO));
        assertEq(evidence, keccak256("fixture evidence"));
        assertEq(oracle.pendingId(), bytes32(0));
        assertEq(dao.balanceOf(address(treasury)), daoCash);
        assertEq(oracle.PAYMENT(), 0);
        vm.expectRevert("not pending");
        _deliver(_envelope(id, true));
    }

    function test_authenticationMalformedEnvelopeAndDomainBinding() public {
        bytes32 id = _ask();
        bytes memory good = _envelope(id, true);
        vm.expectRevert("delivery only");
        oracle.onAnswer(good);
        vm.expectRevert("responder only");
        delivery.deliver(oracle, good);
        vm.expectRevert("envelope size");
        _deliver(bytes.concat(good, hex"00"));
        vm.expectRevert("envelope size");
        _deliver(hex"1234");
        MockOracle.Envelope memory a = abi.decode(good, (MockOracle.Envelope));
        a.chainId++;
        vm.expectRevert("domain");
        _deliver(abi.encode(a));
        a.chainId--;
        a.consumer = address(treasury);
        vm.expectRevert("domain");
        _deliver(abi.encode(a));
        a.consumer = address(oracle);
        a.questionHash = keccak256("different question");
        vm.expectRevert("question evidence");
        _deliver(abi.encode(a));
        a.questionHash = Q;
        a.requestId = keccak256("forged id");
        vm.expectRevert("not pending");
        _deliver(abi.encode(a));
        bytes memory badBool = _envelope(id, true);
        assembly ("memory-safe") { mstore(add(badBool, 160), 2) }
        vm.expectRevert();
        _deliver(badBool);
        _deliver(good);
        (,,, MockOracle.Status status, MockOracle.Answer answer,) = oracle.requests(id);
        assertEq(uint256(status), uint256(MockOracle.Status.Answered));
        assertEq(uint256(answer), uint256(MockOracle.Answer.YES));
    }

    function test_onePendingTimeoutBoundaryFreshGovernanceRetry() public {
        bytes32 id = _ask();
        (,, uint256 expiry,,,) = oracle.requests(id);
        bytes32 second = _queue(address(oracle), abi.encodeCall(MockOracle.request, (keccak256("second"))));
        vm.warp(timelock.operation(second).readyAt);
        vm.expectRevert("request unavailable");
        timelock.execute(second);
        vm.warp(expiry - 1);
        vm.expectRevert("not expired");
        oracle.expire(id);
        vm.warp(expiry);
        vm.expectRevert("late answer");
        _deliver(_envelope(id, true));
        vm.prank(bob);
        oracle.expire(id);
        (,,, MockOracle.Status status, MockOracle.Answer answer,) = oracle.requests(id);
        assertEq(uint256(status), uint256(MockOracle.Status.Expired));
        assertEq(uint256(answer), uint256(MockOracle.Answer.UNKNOWN));
        vm.expectRevert("not expired");
        oracle.expire(id);
        vm.expectRevert("not pending");
        _deliver(_envelope(id, true));
        timelock.execute(second);
        bytes32 fresh = oracle.pendingId();
        assertTrue(fresh != id);
        assertEq(oracle.nonce(), 2);
        assertEq(uint256(governor.state(second)), uint256(RestrictedGovernor.State.Executed));
    }

    function test_answerAtLastSecondAndNoVotingAuthority() public {
        bytes32 id = _ask();
        (,, uint256 expiry,,,) = oracle.requests(id);
        vm.warp(expiry - 1);
        _deliver(_envelope(id, true));
        vm.prank(responder);
        vm.expectRevert("threshold/value");
        governor.propose(address(oracle), 0, abi.encodeCall(MockOracle.request, (Q)), "p", "t", "s");
    }
}

contract ReaderHarness {
    function read(address p) external view returns (uint256, uint256) {
        return PolicyReader.read(p);
    }
}

contract RevertingPolicy {
    fallback() external {
        revert("policy fault");
    }
}

contract ShortPolicy {
    fallback() external {
        assembly {
            mstore(0, 6000)
            return(0, 32)
        }
    }
}

contract LongPolicy {
    fallback() external {
        assembly {
            mstore(0, 6000)
            mstore(32, 4000)
            return(0, 96)
        }
    }
}

contract HugePolicy {
    fallback() external {
        assembly { return(0, 65536) }
    }
}

contract GasPolicy {
    fallback() external {
        assembly { for {} 1 {} {} }
    }
}

contract MutatingPolicy {
    uint256 public writes;

    fallback() external {
        writes++;
    }
}

contract ArbitraryWeights {
    uint256 private immutable _a;
    uint256 private immutable _b;

    constructor(uint256 a, uint256 b) {
        _a = a;
        _b = b;
    }

    function weights() external view returns (uint256, uint256) {
        return (_a, _b);
    }
}

contract PolicyFaultsTest is Test {
    ReaderHarness internal reader = new ReaderHarness();

    function _fallback(address p) internal view {
        (uint256 a, uint256 b) = reader.read(p);
        assertEq(a, 8000);
        assertEq(b, 2000);
    }

    function test_boundedCopyStaticAndGasFallbacks() public {
        _fallback(address(new RevertingPolicy()));
        _fallback(address(new ShortPolicy()));
        _fallback(address(new LongPolicy()));
        _fallback(address(new HugePolicy()));
        _fallback(address(new GasPolicy()));
        _fallback(makeAddr("no code"));
        MutatingPolicy mutablePolicy = new MutatingPolicy();
        _fallback(address(mutablePolicy));
        assertEq(mutablePolicy.writes(), 0);
        _fallback(address(new ArbitraryWeights(type(uint256).max, 1)));
    }

    function testFuzz_policyWeightsValidation(uint256 a, uint256 b) public {
        (uint256 x, uint256 y) = reader.read(address(new ArbitraryWeights(a, b)));
        if (a <= 10000 && b <= 10000 && a + b == 10000) {
            assertEq(x, a);
            assertEq(y, b);
        } else {
            assertEq(x, 8000);
            assertEq(y, 2000);
        }
    }
}

contract PolicyPinningTest is Fixture {
    function test_onlyExactPinnedRuntimeAndChangedCodeFallback() public {
        address v2 = hook.policyV2();
        bytes32 hash = hook.v2Hash();
        vm.expectRevert("not pinned policy");
        hook.validatePolicy(v2, bytes32(uint256(1)));
        bytes32 id = _queue(address(hook), abi.encodeCall(FeeHook.activatePolicy, (v2, hash)));
        _execute(id);
        (uint256 a, uint256 b) = hook.weights();
        assertEq(a, 6000);
        assertEq(b, 4000);
        vm.etch(v2, address(new ShortPolicy()).code);
        (a, b) = hook.weights();
        assertEq(a, 8000);
        assertEq(b, 2000);
        vm.expectRevert("policy code changed");
        hook.validatePolicy(v2, hash);
        _seedFees();
        _conservation(address(dao));
    }
}
