// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Treasury} from "../../src/Treasury.sol";
import {MockOracle, MockDelivery} from "../../src/MockOracle.sol";
import {PolicyV1, PolicyV2} from "../../src/Policies.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @dev TEST ONLY. Mode changes deliberately violate the production asset assumptions.
contract FaultToken is ERC20 {
    enum Mode {
        Standard,
        Reject,
        Tax,
        ExtraDebit,
        BonusCredit,
        FalseReturn,
        NoReturn,
        Reenter
    }
    Mode public mode;
    address public callbackTarget;
    bytes public callbackData;
    bool public callbackSucceeded;
    bool private _inside;

    constructor() ERC20("Adversarial test asset", "FAULT") {
        _mint(msg.sender, 10_000_000 ether);
    }

    function configure(Mode mode_, address target, bytes calldata data) external {
        mode = mode_;
        callbackTarget = target;
        callbackData = data;
        callbackSucceeded = false;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (mode == Mode.FalseReturn) return false;
        super.transfer(to, amount);
        if (mode == Mode.NoReturn) {
            assembly ("memory-safe") { return(0, 0) }
        }
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (mode == Mode.FalseReturn) return false;
        super.transferFrom(from, to, amount);
        if (mode == Mode.NoReturn) {
            assembly ("memory-safe") { return(0, 0) }
        }
        return true;
    }

    function _update(address from, address to, uint256 value) internal override {
        require(mode != Mode.Reject, "fault rejection");
        if (mode == Mode.Tax && from != address(0) && to != address(0) && value > 0) {
            super._update(from, to, value - 1);
            super._update(from, address(0), 1);
        } else {
            super._update(from, to, value);
            if (mode == Mode.ExtraDebit && from != address(0)) super._update(from, address(0), 1);
            if (mode == Mode.BonusCredit && to != address(0)) super._update(address(0), to, 1);
        }
        if (mode == Mode.Reenter && !_inside) {
            _inside = true;
            (callbackSucceeded,) = callbackTarget.call(callbackData);
            _inside = false;
        }
    }
}

contract CashVault {
    using SafeERC20 for IERC20;
    address private immutable _hook;

    constructor() {
        _hook = msg.sender;
    }

    function send(address asset, address recipient, uint256 amount) external {
        require(msg.sender == _hook, "test hook only");
        IERC20(asset).safeTransfer(recipient, amount);
    }
}

/// @dev TEST ONLY: isolates treasury accounting; integration suites use the real governor/hook/manager.
contract TreasuryHarness {
    Treasury public treasury;
    address public immutable manager;
    address public immutable imd;
    address public immutable policyV1;
    address public immutable policyV2;
    address public oracle;

    function timelock() external view returns (address) {
        return address(this);
    }

    function hook() external view returns (address) {
        return address(this);
    }

    constructor(address token0, address token1, address imd_, address guardian, address responder) {
        imd = imd_;
        manager = address(new CashVault());
        policyV1 = address(new PolicyV1());
        policyV2 = address(new PolicyV2());
        _responder = responder;
        // address(this) has no runtime yet. Creation requiring code occurs in initialize(), below.
        _token0 = token0;
        _token1 = token1;
        _guardian = guardian;
    }
    address private immutable _token0;
    address private immutable _token1;
    address private immutable _guardian;
    address private immutable _responder;

    function initialize() external {
        require(address(treasury) == address(0), "test initialized");
        oracle = address(new MockOracle(address(this), new MockDelivery(_responder)));
        treasury = new Treasury(address(this), address(this), _guardian, manager, _token0, _token1);
        treasury.freeze(address(this), address(this), address(this));
    }

    function enroll(address who, uint256 version, bool enabled) external {
        treasury.setRecipient(who, version, enabled, keccak256("unit operator"));
    }

    function bind(Treasury.PayArgs calldata a, bytes32 proposalId) external {
        treasury.bind(a, proposalId);
    }

    function reserve(bytes32 id, bytes32 proposalId, uint256 readyAt) external {
        treasury.reserve(id, proposalId, readyAt);
    }

    function newReservation(Treasury.PayArgs calldata a, bytes32 proposalId, uint256 readyAt) external {
        treasury.bind(a, proposalId);
        treasury.reserve(a.paymentId, proposalId, readyAt);
    }

    function cancel(bytes32 id) external {
        treasury.cancel(id);
    }

    function pay(Treasury.PayArgs calldata a) external {
        treasury.pay(a.paymentId, a.asset, a.bucket, a.recipient, a.version, a.amount, a.purposeHash);
    }

    function accrue(address asset, uint256 amount, uint256 development) external {
        treasury.creditFee(asset, amount, development);
    }

    function takeFee(address asset, uint256 amount) external {
        require(msg.sender == address(treasury), "treasury only");
        CashVault(manager).send(asset, address(treasury), amount);
    }
}
