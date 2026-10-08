// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {FeeHook} from "./FeeHook.sol";

/// @notice Local real-manager router. Pre-funds ONLY msg.sender; callback never uses transferFrom.
contract FixtureRouter is IUnlockCallback, ReentrancyGuard {
    using SafeERC20 for IERC20;
    IPoolManager public immutable manager;
    FeeHook public immutable hook;
    PoolKey private _key;
    bytes32 private _callbackHash;
    uint256 private _budget0;
    uint256 private _budget1;

    struct Action {
        bool isSwap;
        IPoolManager.SwapParams swapParams;
        IPoolManager.ModifyLiquidityParams liquidityParams;
        uint256 maxInput;
        uint256 minOutput;
    }
    event LiquidityFees(BalanceDelta accrued);

    constructor(IPoolManager manager_, FeeHook hook_) {
        require(address(manager_).code.length > 0 && address(hook_).code.length > 0, "router wiring");
        require(address(hook_.manager()) == address(manager_), "manager wiring");
        manager = manager_;
        hook = hook_;
        _key = hook_.poolKey();
    }

    function swap(IPoolManager.SwapParams calldata params, uint256 maxInput, uint256 minOutput)
        external
        nonReentrant
        returns (BalanceDelta delta)
    {
        require(maxInput > 0 && minOutput > 0 && params.amountSpecified != 0, "swap bounds");
        Action memory a =
            Action(true, params, IPoolManager.ModifyLiquidityParams(0, 0, 0, bytes32(0)), maxInput, minOutput);
        return _run(a, params.zeroForOne ? maxInput : 0, params.zeroForOne ? 0 : maxInput);
    }

    function modifyLiquidity(IPoolManager.ModifyLiquidityParams calldata params, uint256 max0, uint256 max1)
        external
        nonReentrant
        returns (BalanceDelta delta)
    {
        IPoolManager.ModifyLiquidityParams memory lp = params;
        // The same caller can add/remove/collect only its own position namespace.
        lp.salt = keccak256(abi.encode(msg.sender, params.salt));
        Action memory a = Action(false, IPoolManager.SwapParams(false, 0, 0), lp, 0, 0);
        return _run(a, max0, max1);
    }

    function _run(Action memory a, uint256 max0, uint256 max1) private returns (BalanceDelta delta) {
        IERC20 t0 = IERC20(Currency.unwrap(_key.currency0));
        IERC20 t1 = IERC20(Currency.unwrap(_key.currency1));
        uint256 baseline0 = t0.balanceOf(address(this));
        uint256 baseline1 = t1.balanceOf(address(this));
        _budget0 = max0;
        _budget1 = max1;
        _pull(t0, max0);
        _pull(t1, max1);
        bytes memory data = abi.encode(a);
        _callbackHash = keccak256(data);
        delta = abi.decode(manager.unlock(data), (BalanceDelta));
        require(_callbackHash == bytes32(0), "missing callback");
        _budget0 = 0;
        _budget1 = 0;
        _refund(t0, baseline0);
        _refund(t1, baseline1);
    }

    function _pull(IERC20 token, uint256 amount) private {
        if (amount == 0) return;
        uint256 beforeCaller = token.balanceOf(msg.sender);
        uint256 beforeRouter = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        require(token.balanceOf(msg.sender) + amount == beforeCaller, "prefund debit");
        require(token.balanceOf(address(this)) == beforeRouter + amount, "prefund credit");
    }

    function _refund(IERC20 token, uint256 baseline) private {
        uint256 beforeRouter = token.balanceOf(address(this));
        uint256 amount = beforeRouter - baseline;
        if (amount == 0) return;
        uint256 beforeCaller = token.balanceOf(msg.sender);
        token.safeTransfer(msg.sender, amount);
        require(token.balanceOf(address(this)) == baseline, "refund debit");
        require(token.balanceOf(msg.sender) == beforeCaller + amount, "refund credit");
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager) && _reentrancyGuardEntered(), "manager callback only");
        require(_callbackHash != bytes32(0) && _callbackHash == keccak256(data), "callback context");
        _callbackHash = bytes32(0);
        Action memory a = abi.decode(data, (Action));
        BalanceDelta delta;
        if (a.isSwap) {
            delta = manager.swap(_key, a.swapParams, "");
            int128 input = a.swapParams.zeroForOne ? delta.amount0() : delta.amount1();
            int128 output = a.swapParams.zeroForOne ? delta.amount1() : delta.amount0();
            require(input < 0 && output > 0, "swap signs");
            require(
                SafeCast.toUint256(-int256(input)) <= a.maxInput && SafeCast.toUint256(int256(output)) >= a.minOutput,
                "slippage"
            );
            if (a.swapParams.amountSpecified > 0) {
                require(int256(output) >= a.swapParams.amountSpecified, "partial exact output");
            }
        } else {
            BalanceDelta accrued;
            (delta, accrued) = manager.modifyLiquidity(_key, a.liquidityParams, "");
            emit LiquidityFees(accrued);
        }
        _settle(_key.currency0, delta.amount0(), true);
        _settle(_key.currency1, delta.amount1(), false);
        return abi.encode(delta);
    }

    function _settle(Currency currency, int128 delta, bool is0) private {
        IERC20 token = IERC20(Currency.unwrap(currency));
        if (delta < 0) {
            uint256 amount = SafeCast.toUint256(-int256(delta));
            if (is0) {
                require(amount <= _budget0, "token0 budget");
                _budget0 -= amount;
            } else {
                require(amount <= _budget1, "token1 budget");
                _budget1 -= amount;
            }
            // Spend router-owned pre-funding, never any callback-supplied payer's allowance.
            uint256 beforeRouter = token.balanceOf(address(this));
            uint256 beforeManager = token.balanceOf(address(manager));
            manager.sync(currency);
            token.safeTransfer(address(manager), amount);
            require(token.balanceOf(address(this)) + amount == beforeRouter, "settle debit");
            require(token.balanceOf(address(manager)) == beforeManager + amount, "settle credit");
            require(manager.settle() == amount, "settled amount");
        } else if (delta > 0) {
            uint256 amount = SafeCast.toUint256(int256(delta));
            uint256 beforeRouter = token.balanceOf(address(this));
            uint256 beforeManager = token.balanceOf(address(manager));
            manager.take(currency, address(this), amount);
            require(token.balanceOf(address(this)) == beforeRouter + amount, "take credit");
            require(token.balanceOf(address(manager)) + amount == beforeManager, "take debit");
        }
    }
}
