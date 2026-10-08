// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Fixture} from "./helpers/Fixture.sol";
import {FaultToken} from "./helpers/TreasuryHarness.sol";
import {MockAsset} from "../src/IMDAO.sol";
import {FixtureRouter} from "../src/FixtureRouter.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

contract RouterFaultsTest is Fixture {
    FaultToken internal fault;

    function _newAsset() internal override returns (MockAsset) {
        fault = new FaultToken();
        return MockAsset(address(fault));
    }

    function testFuzz_badPrefundingRejectedAndVictimUntouched(uint8 mode) public {
        mode = uint8(bound(mode, 1, 5));
        bool direction = Currency.unwrap(key.currency0) == address(fault);
        uint256 beforeCash = fault.balanceOf(address(this));
        uint256 managerCash = fault.balanceOf(address(manager));
        fault.configure(FaultToken.Mode(mode), address(router), "");
        vm.expectRevert();
        _swap(direction, -10 ether, 10 ether, 9 ether);
        assertEq(fault.balanceOf(address(this)), beforeCash);
        assertEq(fault.balanceOf(address(manager)), managerCash);
        assertEq(fault.balanceOf(address(router)), 0);
    }

    function test_reentryCannotStartSwapOrForgeManagerCallback() public {
        bool direction = Currency.unwrap(key.currency0) == address(fault);
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams(
            direction, -1 ether, direction ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        );
        fault.configure(
            FaultToken.Mode.Reenter, address(router), abi.encodeCall(FixtureRouter.swap, (params, 1 ether, 0.9 ether))
        );
        _swap(direction, -10 ether, 10 ether, 9 ether);
        assertFalse(fault.callbackSucceeded());
        fault.configure(
            FaultToken.Mode.Reenter, address(router), abi.encodeCall(FixtureRouter.unlockCallback, (abi.encode(params)))
        );
        _swap(direction, -10 ether, 10 ether, 9 ether);
        assertFalse(fault.callbackSucceeded());
        _conservation(address(fault));
        _conservation(address(dao));
    }

    function test_optionalNoReturnAssetWithRealManager() public {
        bool direction = Currency.unwrap(key.currency0) == address(fault);
        fault.configure(FaultToken.Mode.NoReturn, address(router), "");
        _swap(direction, -10 ether, 10 ether, 9 ether);
        _swap(!direction, -10 ether, 10 ether, 9 ether);
        _conservation(address(fault));
        _conservation(address(dao));
    }
}
