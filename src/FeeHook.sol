// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Treasury} from "./Treasury.sol";
import {PolicyV1, PolicyV2, PolicyReader} from "./Policies.sol";
import {ILockWiring} from "./Interfaces.sol";

/// @notice A fixed-pool, settled-cash, unspecified-currency surcharge. No LP callbacks.
contract FeeHook is ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    uint256 public constant FEE_BPS = 25;
    uint160 public constant FLAGS = (1 << 13) | (1 << 6) | (1 << 2);
    IPoolManager public immutable manager;
    Treasury public immutable treasury;
    address public immutable timelock;
    PoolId public immutable poolId;
    address public immutable policyV1;
    address public immutable policyV2;
    bytes32 public immutable v1Hash;
    bytes32 public immutable v2Hash;
    address public policy;
    PoolKey private _key;
    address private _feeAsset;
    uint256 private _feeAmount;
    event PolicyActivated(address indexed candidate, bytes32 codeHash);
    event Surcharge(PoolId indexed poolId, address indexed asset, uint256 unspecifiedMagnitude, uint256 fee);

    constructor(IPoolManager manager_, Treasury treasury_, address timelock_, uint24 lpFee, int24 tickSpacing) {
        require(
            address(manager_).code.length > 0 && address(treasury_).code.length > 0 && timelock_.code.length > 0,
            "hook wiring"
        );
        require(treasury_.manager() == address(manager_) && treasury_.timelock() == timelock_, "treasury wiring");
        require(lpFee <= 1_000_000 && tickSpacing > 0, "pool parameters");
        manager = manager_;
        treasury = treasury_;
        timelock = timelock_;
        Hooks.validateHookPermissions(IHooks(address(this)), getHookPermissions());
        address a = treasury_.asset0();
        address b = treasury_.asset1();
        _key = PoolKey(
            Currency.wrap(a < b ? a : b), Currency.wrap(a < b ? b : a), lpFee, tickSpacing, IHooks(address(this))
        );
        poolId = _key.toId();
        policyV1 = address(new PolicyV1());
        policyV2 = address(new PolicyV2());
        v1Hash = keccak256(type(PolicyV1).runtimeCode);
        v2Hash = keccak256(type(PolicyV2).runtimeCode);
        require(policyV1.codehash == v1Hash && policyV2.codehash == v2Hash, "policy runtime");
        policy = policyV1;
    }

    function getHookPermissions() public pure returns (Hooks.Permissions memory p) {
        p.beforeInitialize = true;
        p.afterSwap = true;
        p.afterSwapReturnDelta = true;
    }

    function poolKey() external view returns (PoolKey memory) {
        return _key;
    }

    function _authenticate(PoolKey calldata key) private view {
        require(msg.sender == address(manager) && PoolId.unwrap(key.toId()) == PoolId.unwrap(poolId), "manager/pool");
        require(treasury.frozen() && ILockWiring(timelock).frozen(), "unfrozen");
    }

    function beforeInitialize(address, PoolKey calldata key, uint160) external view returns (bytes4) {
        _authenticate(key);
        return IHooks.beforeInitialize.selector;
    }

    function validatePolicy(address candidate, bytes32 codeHash) public view {
        require(
            (candidate == policyV1 && codeHash == v1Hash) || (candidate == policyV2 && codeHash == v2Hash),
            "not pinned policy"
        );
        require(candidate.code.length > 0 && candidate.codehash == codeHash, "policy code changed");
    }

    function activatePolicy(address candidate, bytes32 codeHash) external {
        require(msg.sender == timelock, "timelock only");
        validatePolicy(candidate, codeHash);
        policy = candidate;
        emit PolicyActivated(candidate, codeHash);
    }

    function weights() public view returns (uint256 development, uint256 reserve) {
        address candidate = policy;
        bytes32 expected = candidate == policyV1 ? v1Hash : v2Hash;
        if (candidate.codehash != expected) return (8000, 2000);
        return PolicyReader.read(candidate);
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) external nonReentrant returns (bytes4, int128) {
        _authenticate(key);
        bool unspecifiedIs1 = (params.amountSpecified < 0) == params.zeroForOne;
        int128 unspecified = unspecifiedIs1 ? delta.amount1() : delta.amount0();
        // Widen before negation: int128.min is a valid input to the magnitude calculation.
        uint256 magnitude = SafeCast.toUint256(unspecified < 0 ? -int256(unspecified) : int256(unspecified));
        uint256 amount = magnitude * FEE_BPS / 10000;
        address asset = Currency.unwrap(unspecifiedIs1 ? key.currency1 : key.currency0);
        if (amount > 0) {
            _feeAsset = asset;
            _feeAmount = amount;
            (uint256 development,) = weights();
            treasury.creditFee(asset, amount, development);
            require(_feeAmount == 0, "fee not taken");
        }
        emit Surcharge(poolId, asset, magnitude, amount);
        return (IHooks.afterSwap.selector, SafeCast.toInt128(SafeCast.toInt256(amount)));
    }

    /// @dev Treasury holds its reentrancy lock and checks exact debit/credit across this call.
    function takeFee(address asset, uint256 amount) external {
        require(msg.sender == address(treasury) && _reentrancyGuardEntered(), "treasury fee callback");
        require(amount > 0 && amount == _feeAmount && asset == _feeAsset, "fee context");
        _feeAmount = 0;
        manager.take(Currency.wrap(asset), address(treasury), amount);
    }
}
