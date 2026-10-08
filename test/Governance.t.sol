// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Fixture} from "./helpers/Fixture.sol";
import {Treasury} from "../src/Treasury.sol";
import {FeeHook} from "../src/FeeHook.sol";
import {RestrictedGovernor} from "../src/RestrictedGovernor.sol";
import {RestrictedTimelock} from "../src/RestrictedTimelock.sol";
import {MockOracle} from "../src/MockOracle.sol";

contract GovernanceTest is Fixture {
    function _oracleAction() internal pure returns (bytes memory) {
        return abi.encodeCall(MockOracle.request, (keccak256("local evidence question")));
    }

    function test_supplyDelegationClockAndNoMint() public {
        assertEq(dao.name(), "IMDAO");
        assertEq(dao.symbol(), "IMDAO");
        assertEq(dao.totalSupply(), 1_000_000 ether);
        assertEq(dao.decimals(), 18);
        assertEq(dao.CLOCK_MODE(), "mode=blocknumber&from=default");
        assertEq(dao.getPastVotes(alice, vm.getBlockNumber() - 1), 60_000 ether);
        (bool ok,) = address(dao).call(abi.encodeWithSignature("mint(address,uint256)", alice, 1));
        assertFalse(ok);
    }

    function test_thresholdPriorBlockAndImdAloneCannotPropose() public {
        vm.prank(imdOnly);
        vm.expectRevert("threshold/value");
        governor.propose(address(oracle), 0, _oracleAction(), "p", "t", "s");
        address newVoter = makeAddr("new voter");
        _voter(newVoter, 10_000 ether, 0);
        vm.prank(newVoter);
        vm.expectRevert("threshold/value");
        governor.propose(address(oracle), 0, _oracleAction(), "p", "t", "s");
        vm.roll(vm.getBlockNumber() + 1);
        vm.prank(newVoter);
        bytes32 id = governor.propose(address(oracle), 0, _oracleAction(), "p", "t", "s");
        assertEq(governor.proposal(id).proposer, newVoter);
    }

    function test_snapshotsRedelegationAndDoubleVotes() public {
        bytes32 id = _propose(address(oracle), _oracleAction());
        RestrictedGovernor.Proposal memory p = governor.proposal(id);
        assertEq(p.snapshot, vm.getBlockNumber() + 1);
        assertEq(p.deadline, p.snapshot + 100);
        vm.roll(p.snapshot);
        vm.prank(alice);
        vm.expectRevert("vote unavailable");
        governor.castVote(id, 1);
        vm.roll(p.snapshot + 1);
        vm.startPrank(alice);
        dao.delegate(bob);
        imd.delegate(bob);
        vm.stopPrank();
        vm.prank(alice);
        governor.castVote(id, 1);
        vm.prank(bob);
        governor.castVote(id, 0);
        vm.prank(imdOnly);
        governor.castVote(id, 1);
        p = governor.proposal(id);
        assertEq(p.baseVotes[1], 60_000 ether);
        assertEq(p.weightedVotes[1], 75_000 ether);
        assertEq(p.baseVotes[0], 40_000 ether);
        assertEq(p.weightedVotes[0], 41_000 ether);
        vm.prank(alice);
        vm.expectRevert("vote unavailable");
        governor.castVote(id, 2);
        vm.roll(p.deadline);
        vm.prank(dave);
        governor.castVote(id, 2);
        vm.roll(p.deadline + 1);
        vm.prank(carol);
        vm.expectRevert("vote unavailable");
        governor.castVote(id, 1);
        assertEq(uint256(governor.state(id)), uint256(RestrictedGovernor.State.Succeeded));
    }

    function test_unboostedQuorumNotWeightedParticipation() public {
        bytes32 id = _propose(address(oracle), _oracleAction());
        RestrictedGovernor.Proposal memory p = governor.proposal(id);
        vm.roll(p.snapshot + 1);
        vm.prank(carol); // 35k base, 43.75k weighted: fails 40k quorum.
        governor.castVote(id, 1);
        vm.roll(p.deadline + 1);
        assertEq(uint256(governor.state(id)), uint256(RestrictedGovernor.State.Defeated));
        vm.expectRevert("not succeeded");
        governor.queue(id);
    }

    function test_againstExcludedAbstainIncludedAndWeightedMajority() public {
        // FOR 35k boosted 43.75k beats AGAINST 40k boosted 41k; 10k abstain makes base quorum.
        bytes32 id = _propose(address(oracle), _oracleAction());
        RestrictedGovernor.Proposal memory p = governor.proposal(id);
        vm.roll(p.snapshot + 1);
        vm.prank(carol);
        governor.castVote(id, 1);
        vm.prank(bob);
        governor.castVote(id, 0);
        vm.prank(dave);
        governor.castVote(id, 2);
        vm.roll(p.deadline + 1);
        assertEq(uint256(governor.state(id)), uint256(RestrictedGovernor.State.Succeeded));
        bytes32 other = _propose(address(oracle), _oracleAction());
        p = governor.proposal(other);
        vm.roll(p.snapshot + 1);
        vm.prank(carol);
        governor.castVote(other, 1);
        vm.prank(bob);
        governor.castVote(other, 0);
        vm.roll(p.deadline + 1);
        assertEq(uint256(governor.state(other)), uint256(RestrictedGovernor.State.Defeated));
    }

    function testFuzz_bonusUses18DecimalFlooredQuarter(uint96 c, uint96 i) public {
        uint256 capital = bound(c, 0, 100_000 ether);
        uint256 identityPower = bound(i, 0, 100_000 ether);
        address voter = makeAddr("fuzz delegate");
        _voter(voter, capital, identityPower);
        vm.roll(vm.getBlockNumber() + 1);
        (uint256 base, uint256 weighted) = governor.votingPower(voter, vm.getBlockNumber() - 1);
        assertEq(base, capital);
        assertEq(weighted, capital + (capital / 4 < identityPower ? capital / 4 : identityPower));
    }

    function test_canonicalActionsNoValueBatchesOrTimelockSelfCalls() public {
        bytes memory data = _oracleAction();
        vm.prank(alice);
        vm.expectRevert("threshold/value");
        governor.propose(address(oracle), 1, data, "p", "t", "s");
        vm.expectRevert();
        _propose(address(timelock), abi.encodeWithSignature("updateDelay(uint256)", 0));
        vm.expectRevert();
        _propose(address(timelock), abi.encodeWithSignature("grantRole(bytes32,address)", bytes32(0), alice));
        vm.expectRevert();
        _propose(address(dao), abi.encodeWithSignature("transfer(address,uint256)", alice, 1));
        vm.expectRevert();
        _propose(address(oracle), bytes.concat(data, hex"00"));
        vm.expectRevert();
        _propose(address(oracle), abi.encode(data, data));
        vm.expectRevert();
        _propose(address(oracle), hex"1234");
        bytes memory dirty = abi.encodeCall(Treasury.setRecipient, (recipient, uint256(0), true, keccak256("meta")));
        assembly ("memory-safe") { mstore(add(dirty, 36), or(mload(add(dirty, 36)), shl(200, 1))) }
        vm.expectRevert();
        _propose(address(treasury), dirty);
        vm.expectRevert();
        _propose(address(hook), abi.encodeCall(FeeHook.activatePolicy, (address(dao), address(dao).codehash)));
    }

    function test_descriptionFrozenAndDuplicateProposalRejected() public {
        vm.prank(alice);
        bytes32 id = governor.propose(address(oracle), 0, _oracleAction(), "purpose", "text", "local://source");
        bytes32 dh = keccak256(abi.encode("purpose", "text", "local://source"));
        assertEq(governor.proposal(id).descriptionHash, dh);
        assertEq(id, governor.hashProposal(address(oracle), _oracleAction(), dh));
        vm.prank(alice);
        vm.expectRevert("proposal used");
        governor.propose(address(oracle), 0, _oracleAction(), "purpose", "text", "local://source");
    }

    function test_bootstrapUnauthorizedAndNoAdminBypass() public {
        assertEq(treasury.bootstrap(), address(0));
        assertEq(timelock.bootstrap(), address(0));
        assertEq(timelock.admin(), address(timelock));
        vm.expectRevert();
        treasury.freeze(address(governor), address(hook), address(router));
        vm.expectRevert();
        timelock.freeze(address(governor));
        vm.expectRevert("governor only");
        timelock.schedule(keccak256("bypass"), address(oracle), _oracleAction());
        vm.expectRevert("governor only");
        timelock.cancel(keccak256("bypass"));
        vm.expectRevert("timelock only");
        treasury.setRecipient(recipient, 0, true, keccak256("meta"));
        vm.expectRevert("timelock only");
        oracle.request(keccak256("q"));
        address candidate = hook.policyV2();
        bytes32 runtimeHash = hook.v2Hash();
        vm.expectRevert("timelock only");
        hook.activatePolicy(candidate, runtimeHash);
        vm.prank(guardian);
        vm.expectRevert("timelock only");
        treasury.setRecipient(recipient, 0, true, keccak256("meta"));
        vm.expectRevert("guardian only");
        treasury.suspend(recipient);
        vm.expectRevert("hook only");
        treasury.creditFee(address(dao), 1, 8000);
    }

    function test_nonpaymentNoExpiryOpenDirectExecutionAndCancellation() public {
        bytes32 id = _queue(address(oracle), _oracleAction());
        vm.warp(timelock.operation(id).readyAt - 1);
        vm.expectRevert("not ready");
        governor.execute(id);
        vm.warp(timelock.operation(id).readyAt + 30 days);
        vm.prank(imdOnly);
        timelock.execute(id);
        assertEq(uint256(governor.state(id)), uint256(RestrictedGovernor.State.Executed));
        vm.expectRevert();
        governor.execute(id);
        vm.prank(alice);
        vm.expectRevert();
        governor.cancel(id);
        bytes32 other = _propose(address(oracle), _oracleAction());
        vm.prank(bob);
        vm.expectRevert("cannot cancel caller");
        governor.cancel(other);
        vm.prank(alice);
        governor.cancel(other);
        assertEq(uint256(governor.state(other)), uint256(RestrictedGovernor.State.Cancelled));
    }

    function test_originalProposerCanCancelEvenAfterLosingVotes() public {
        bytes32 id = _queue(address(oracle), _oracleAction());
        vm.startPrank(alice);
        dao.delegate(bob);
        governor.cancel(id);
        vm.stopPrank();
        assertEq(uint256(timelock.status(id)), uint256(RestrictedTimelock.Status.Cancelled));
        vm.warp(vm.getBlockTimestamp() + 5000);
        vm.expectRevert();
        timelock.execute(id);
    }

    function test_weightedTieFailsAndExactBaseQuorumSucceeds() public {
        address equal = makeAddr("equal weighted voter");
        _voter(equal, 60_000 ether, 15_000 ether);
        bytes32 tie = _propose(address(oracle), _oracleAction());
        RestrictedGovernor.Proposal memory p = governor.proposal(tie);
        vm.roll(p.snapshot + 1);
        vm.prank(alice);
        governor.castVote(tie, 1);
        vm.prank(equal);
        governor.castVote(tie, 0);
        vm.roll(p.deadline + 1);
        assertEq(uint256(governor.state(tie)), uint256(RestrictedGovernor.State.Defeated));
        bytes32 exact = _propose(address(oracle), _oracleAction());
        p = governor.proposal(exact);
        vm.roll(p.snapshot + 1);
        vm.prank(bob);
        governor.castVote(exact, 1);
        vm.roll(p.deadline + 1);
        assertEq(uint256(governor.state(exact)), uint256(RestrictedGovernor.State.Succeeded));
    }
}
