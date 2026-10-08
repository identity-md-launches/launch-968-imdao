// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Fixture} from "./helpers/Fixture.sol";
import {Test} from "forge-std/Test.sol";
import {FixtureRouter} from "../src/FixtureRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

contract SwapHandler is Test {
    FixtureRouter internal router;

    constructor(FixtureRouter router_, address a, address b) {
        router = router_;
        IERC20(a).approve(address(router), 20_000 ether);
        IERC20(b).approve(address(router), 20_000 ether);
    }

    function swap(bool direction, bool exactInput, uint96 seed) external {
        uint256 amount = bound(seed, 1 ether, 10 ether);
        router.swap(
            IPoolManager.SwapParams(
                direction,
                exactInput ? -int256(amount) : int256(amount),
                direction ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            ),
            amount * 11 / 10,
            exactInput ? amount * 9 / 10 : amount
        );
    }
}

contract SwapInvariantTest is Fixture {
    SwapHandler internal handler;

    function setUp() public override {
        super.setUp();
        handler = new SwapHandler(router, address(dao), address(asset));
        dao.transfer(address(handler), 20_000 ether);
        asset.transfer(address(handler), 20_000 ether);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = handler.swap.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
        targetContract(address(handler));
    }

    function invariant_realManagerFeesAreSettledCashAndRouterKeepsNoUserFunds() public view {
        _conservation(address(dao));
        _conservation(address(asset));
        assertEq(dao.balanceOf(address(router)), 0);
        assertEq(asset.balanceOf(address(router)), 0);
        assertEq(treasury.surplus(address(dao)), 0);
        assertEq(treasury.surplus(address(asset)), 0);
    }
}
