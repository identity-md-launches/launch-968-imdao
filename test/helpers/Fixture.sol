// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IMDAO, MockIMD, MockAsset} from "../../src/IMDAO.sol";
import {Treasury} from "../../src/Treasury.sol";
import {FeeHook} from "../../src/FeeHook.sol";
import {FixtureRouter} from "../../src/FixtureRouter.sol";
import {RestrictedGovernor} from "../../src/RestrictedGovernor.sol";
import {RestrictedTimelock} from "../../src/RestrictedTimelock.sol";
import {MockOracle, MockDelivery} from "../../src/MockOracle.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

abstract contract Fixture is Test {
    IMDAO internal dao;
    MockIMD internal imd;
    MockAsset internal asset;
    Treasury internal treasury;
    FeeHook internal hook;
    FixtureRouter internal router;
    RestrictedGovernor internal governor;
    RestrictedTimelock internal timelock;
    MockOracle internal oracle;
    MockDelivery internal delivery;
    PoolManager internal manager;
    PoolKey internal key;
    address internal alice;
    address internal bob;
    address internal carol;
    address internal dave;
    address internal imdOnly;
    address internal guardian;
    address internal responder;
    address internal recipient;
    uint256 internal serial;

    function setUp() public virtual {
        vm.roll(10);
        vm.warp(10000);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");
        dave = makeAddr("dave");
        imdOnly = makeAddr("imd-only");
        guardian = makeAddr("guardian");
        responder = makeAddr("responder");
        recipient = makeAddr("recipient");
        dao = new IMDAO(address(this));
        imd = new MockIMD(address(this));
        asset = _newAsset();
        _voter(alice, 60_000 ether, 40_000 ether);
        _voter(bob, 40_000 ether, 1000 ether);
        _voter(carol, 35_000 ether, 30_000 ether);
        _voter(dave, 10_000 ether, 0);
        _voter(imdOnly, 0, 200_000 ether);
        timelock = new RestrictedTimelock(address(this));
        manager = new PoolManager(address(timelock));
        treasury =
            new Treasury(address(this), address(timelock), guardian, address(manager), address(dao), address(asset));
        bytes memory init = abi.encodePacked(
            type(FeeHook).creationCode, abi.encode(manager, treasury, timelock, uint24(3000), int24(60))
        );
        bytes32 initHash = keccak256(init);
        uint256 salt;
        while (
            uint160(
                        address(
                            uint160(
                                uint256(
                                    keccak256(abi.encodePacked(bytes1(0xff), address(this), bytes32(salt), initHash))
                                )
                            )
                        )
                    ) & 0x3fff != 0x2044
        ) ++salt;
        hook = new FeeHook{salt: bytes32(salt)}(manager, treasury, address(timelock), 3000, 60);
        router = new FixtureRouter(manager, hook);
        delivery = new MockDelivery(responder);
        oracle = new MockOracle(address(timelock), delivery);
        governor = new RestrictedGovernor(IVotes(address(dao)), IVotes(address(imd)), treasury, hook, oracle, timelock);
        treasury.freeze(address(governor), address(hook), address(router));
        timelock.freeze(address(governor));
        key = hook.poolKey();
        manager.initialize(key, uint160(1 << 96));
        dao.approve(address(router), 800_000 ether);
        asset.approve(address(router), 1_000_000 ether);
        router.modifyLiquidity(
            IPoolManager.ModifyLiquidityParams(-600, 600, 5_000_000 ether, bytes32(0)), 200_000 ether, 200_000 ether
        );
        vm.roll(vm.getBlockNumber() + 1);
    }

    function _newAsset() internal virtual returns (MockAsset) {
        return new MockAsset(address(this));
    }

    function _voter(address who, uint256 c, uint256 i) internal {
        dao.transfer(who, c);
        imd.transfer(who, i);
        vm.startPrank(who);
        dao.delegate(who);
        imd.delegate(who);
        vm.stopPrank();
    }

    function _propose(address target, bytes memory data) internal returns (bytes32) {
        vm.prank(alice);
        return governor.propose(
            target, 0, data, "Local purpose", string.concat("Fixture action ", vm.toString(++serial)), "local://README"
        );
    }

    function _pass(bytes32 id) internal {
        RestrictedGovernor.Proposal memory p = governor.proposal(id);
        vm.roll(p.snapshot + 1);
        vm.prank(alice);
        governor.castVote(id, 1);
        vm.roll(p.deadline + 1);
    }

    function _queue(address target, bytes memory data) internal returns (bytes32 id) {
        id = _propose(target, data);
        _pass(id);
        governor.queue(id);
    }

    function _execute(bytes32 id) internal {
        vm.warp(timelock.operation(id).readyAt);
        timelock.execute(id);
    }

    function _enroll(address who) internal returns (uint256 version) {
        (uint256 current,,) = treasury.recipients(who);
        bytes32 id = _queue(
            address(treasury),
            abi.encodeCall(Treasury.setRecipient, (who, current, true, keccak256("operator and purpose")))
        );
        _execute(id);
        version = current + 1;
        vm.prank(who);
        treasury.accept(version);
    }

    function _payment(bytes32 id, address token, uint8 bucket, address who, uint256 version, uint256 amount)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeCall(Treasury.pay, (id, token, bucket, who, version, amount, keccak256("milestone")));
    }

    function _swap(bool zeroForOne, int256 amount, uint256 maxInput, uint256 minOutput)
        internal
        returns (BalanceDelta)
    {
        return router.swap(
            IPoolManager.SwapParams(
                zeroForOne, amount, zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            ),
            maxInput,
            minOutput
        );
    }

    function _seedFees() internal {
        _swap(true, -1000 ether, 1000 ether, 900 ether);
        _swap(false, -1000 ether, 1000 ether, 900 ether);
    }

    function _conservation(address token) internal view {
        (uint256 fees, uint256 returned, uint256 proceeds, uint256 gross, uint256 reserved) = treasury.ledgers(token);
        uint256 total = treasury.buckets(token, 0) + treasury.buckets(token, 1);
        assertEq(fees + returned + proceeds - gross, total);
        assertGe(IERC20(token).balanceOf(address(treasury)), total);
        assertEq(reserved, treasury.bucketReserved(token, 0) + treasury.bucketReserved(token, 1));
        assertLe(treasury.bucketReserved(token, 0), treasury.buckets(token, 0));
        assertLe(treasury.bucketReserved(token, 1), treasury.buckets(token, 1));
    }
}
