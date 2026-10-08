// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Fixture} from "./helpers/Fixture.sol";
import {Treasury} from "../src/Treasury.sol";
import {FeeHook} from "../src/FeeHook.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta, toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";

contract FeesTest is Fixture {
    function _case(bool direction, bool exactInput, uint256 amount) internal {
        address input = Currency.unwrap(direction ? key.currency0 : key.currency1);
        address output = Currency.unwrap(direction ? key.currency1 : key.currency0);
        address feeAsset = exactInput ? output : input;
        uint256 inBefore = IERC20(input).balanceOf(address(this));
        uint256 outBefore = IERC20(output).balanceOf(address(this));
        uint256 feeBefore = IERC20(feeAsset).balanceOf(address(treasury));
        uint256 devBefore = treasury.buckets(feeAsset, 0);
        uint256 reserveBefore = treasury.buckets(feeAsset, 1);
        BalanceDelta d = _swap(
            direction,
            exactInput ? -int256(amount) : int256(amount),
            amount * 11 / 10 + 10,
            exactInput ? amount * 9 / 10 : amount
        );
        uint256 inputPaid = uint256(-int256(direction ? d.amount0() : d.amount1()));
        uint256 outputReceived = uint256(int256(direction ? d.amount1() : d.amount0()));
        uint256 fee = IERC20(feeAsset).balanceOf(address(treasury)) - feeBefore;
        uint256 unspecifiedMagnitude = exactInput ? outputReceived + fee : inputPaid - fee;
        assertEq(fee, unspecifiedMagnitude * 25 / 10000);
        assertEq(IERC20(input).balanceOf(address(this)), inBefore - inputPaid);
        assertEq(IERC20(output).balanceOf(address(this)), outBefore + outputReceived);
        if (exactInput) assertEq(inputPaid, amount);
        else assertEq(outputReceived, amount);
        assertEq(treasury.buckets(feeAsset, 0) - devBefore, fee * 8000 / 10000);
        assertEq(treasury.buckets(feeAsset, 1) - reserveBefore, fee - fee * 8000 / 10000);
        assertEq(IERC20(input).balanceOf(address(router)), 0);
        assertEq(IERC20(output).balanceOf(address(router)), 0);
        _conservation(input);
        _conservation(output);
    }

    function test_zeroForOneExactInput() public {
        _case(true, true, 100 ether);
    }

    function test_oneForZeroExactInput() public {
        _case(false, true, 100 ether);
    }

    function test_zeroForOneExactOutput() public {
        _case(true, false, 100 ether);
    }

    function test_oneForZeroExactOutput() public {
        _case(false, false, 100 ether);
    }

    function testFuzz_swapAccounting(bool direction, bool exactInput, uint96 amount) public {
        _case(direction, exactInput, bound(amount, 1000, 2000 ether));
    }

    function test_slippageAtomicityAllFourCases() public {
        for (uint256 i; i < 4; ++i) {
            bool direction = i % 2 == 0;
            bool exactInput = i < 2;
            vm.expectRevert();
            _swap(
                direction,
                exactInput ? -int256(100 ether) : int256(100 ether),
                exactInput ? 100 ether : 99 ether,
                exactInput ? 100 ether : 100 ether
            );
            assertEq(treasury.buckets(address(dao), 0), 0);
            assertEq(treasury.buckets(address(asset), 0), 0);
        }
    }

    function test_hookPermissionsAuthenticationAndPoolFixed() public {
        Hooks.Permissions memory p = hook.getHookPermissions();
        assertTrue(p.beforeInitialize && p.afterSwap && p.afterSwapReturnDelta);
        assertFalse(
            p.beforeRemoveLiquidity || p.afterRemoveLiquidity || p.beforeAddLiquidity || p.afterAddLiquidity
                || p.beforeSwap
        );
        assertEq(uint160(address(hook)) & 0x3fff, hook.FLAGS());
        vm.expectRevert("manager/pool");
        hook.afterSwap(address(this), key, IPoolManager.SwapParams(true, -1, 0), toBalanceDelta(-1, 1), "");
        PoolKey memory wrong = key;
        wrong.fee = 500;
        vm.expectRevert();
        manager.initialize(wrong, uint160(1 << 96));
        vm.prank(address(manager));
        vm.expectRevert("manager/pool");
        hook.afterSwap(address(this), wrong, IPoolManager.SwapParams(true, -1, 0), toBalanceDelta(-1, 1), "");
        vm.expectRevert("treasury fee callback");
        hook.takeFee(address(dao), 1);
        vm.expectRevert("manager callback only");
        router.unlockCallback(abi.encode(address(this)));
    }

    function test_lpOwnershipExitsAndSuspensionDoesNotPauseTrading() public {
        vm.prank(alice);
        vm.expectRevert();
        router.modifyLiquidity(IPoolManager.ModifyLiquidityParams(-600, 600, -int256(1 ether), bytes32(0)), 0, 0);
        vm.prank(guardian);
        treasury.suspend(recipient);
        _case(true, true, 10 ether);
        BalanceDelta d = router.modifyLiquidity(
            IPoolManager.ModifyLiquidityParams(-600, 600, -int256(5_000_000 ether), bytes32(0)), 0, 0
        );
        assertGt(d.amount0(), 0);
        assertGt(d.amount1(), 0);
        _conservation(address(dao));
        _conservation(address(asset));
    }

    function test_insufficientManagerCashRevertsAtomically() public {
        address input = Currency.unwrap(key.currency0);
        deal(input, address(manager), 0);
        uint256 beforeCash = IERC20(input).balanceOf(address(this));
        vm.expectRevert();
        _swap(true, int256(10 ether), 12 ether, 10 ether);
        assertEq(IERC20(input).balanceOf(address(this)), beforeCash);
        assertEq(treasury.buckets(input, 0), 0);
    }

    function test_donationsStaySurplusAndRouterCannotSpendVictimAllowance() public {
        dao.transfer(address(treasury), 100 ether);
        assertEq(treasury.surplus(address(dao)), 100 ether);
        assertEq(treasury.buckets(address(dao), 0), 0);
        vm.prank(alice);
        dao.approve(address(router), 500 ether);
        uint256 balance = dao.balanceOf(alice);
        _swap(true, -10 ether, 10 ether, 9 ether);
        assertEq(dao.balanceOf(alice), balance);
        assertEq(dao.allowance(alice, address(router)), 500 ether);
        dao.transfer(address(router), 7 ether);
        _swap(false, -10 ether, 10 ether, 9 ether);
        assertEq(dao.balanceOf(address(router)), 7 ether);
        assertEq(treasury.surplus(address(dao)), 100 ether);
    }

    function test_policyChangesOnlyFutureFees() public {
        _seedFees();
        uint256 oldDev = treasury.buckets(address(dao), 0);
        uint256 oldReserve = treasury.buckets(address(dao), 1);
        bytes32 id = _queue(address(hook), abi.encodeCall(FeeHook.activatePolicy, (hook.policyV2(), hook.v2Hash())));
        _execute(id);
        assertEq(treasury.buckets(address(dao), 0), oldDev);
        assertEq(treasury.buckets(address(dao), 1), oldReserve);
        uint256 beforeCash = dao.balanceOf(address(treasury));
        _seedFees();
        uint256 receipt = dao.balanceOf(address(treasury)) - beforeCash;
        assertEq(treasury.buckets(address(dao), 0) - oldDev, receipt * 6000 / 10000);
        assertEq(treasury.buckets(address(dao), 1) - oldReserve, receipt - receipt * 6000 / 10000);
    }
}
