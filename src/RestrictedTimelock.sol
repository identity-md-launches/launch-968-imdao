// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IGovernorWiring} from "./Interfaces.sol";
import {Treasury} from "./Treasury.sol";
import {FeeHook} from "./FeeHook.sol";
import {MockOracle} from "./MockOracle.sol";

/// @notice No generic call, delegatecall, role grant, delay setter or self-call route exists.
contract RestrictedTimelock is ReentrancyGuard {
    uint256 public constant MIN_DELAY = 3600;
    enum Status {
        Unknown,
        Scheduled,
        Done,
        Cancelled
    }

    struct Operation {
        address target;
        bytes data;
        uint256 readyAt;
        Status status;
    }
    address public bootstrap;
    address public governor;
    bool public frozen;
    mapping(bytes32 => Operation) private _operations;
    event Frozen(address indexed governor);
    event Scheduled(bytes32 indexed id, address target, bytes data, uint256 readyAt);
    event Executed(bytes32 indexed id);
    event Cancelled(bytes32 indexed id);
    event OracleRequestCreated(bytes32 indexed proposalId, bytes32 indexed requestId);

    constructor(address bootstrap_) {
        require(bootstrap_ != address(0), "bootstrap");
        bootstrap = bootstrap_;
    }

    function admin() external view returns (address) {
        return address(this);
    }

    function freeze(address governor_) external {
        require(!frozen && msg.sender == bootstrap && governor_.code.length > 0, "bootstrap only");
        IGovernorWiring g = IGovernorWiring(governor_);
        require(g.timelock() == address(this), "timelock wiring");
        Treasury t = Treasury(g.treasury());
        require(
            t.frozen() && t.governor() == governor_ && t.hook() == g.hook() && t.timelock() == address(this),
            "treasury wiring"
        );
        governor = governor_;
        frozen = true;
        bootstrap = address(0);
        emit Frozen(governor_);
    }
    modifier onlyGovernor() {
        require(frozen && msg.sender == governor, "governor only");
        _;
    }

    function operation(bytes32 id) external view returns (Operation memory) {
        return _operations[id];
    }

    function status(bytes32 id) external view returns (Status) {
        return _operations[id].status;
    }

    function schedule(bytes32 id, address target, bytes calldata data)
        external
        nonReentrant
        onlyGovernor
        returns (uint256 readyAt)
    {
        require(id != bytes32(0) && _operations[id].status == Status.Unknown, "operation used");
        IGovernorWiring(governor).validateAction(target, data);
        readyAt = block.timestamp + MIN_DELAY;
        _operations[id] = Operation(target, data, readyAt, Status.Scheduled);
        emit Scheduled(id, target, data, readyAt);
    }

    function cancel(bytes32 id) external nonReentrant onlyGovernor {
        Operation storage o = _operations[id];
        require(o.status == Status.Scheduled, "not scheduled");
        o.status = Status.Cancelled;
        emit Cancelled(id);
    }

    function execute(bytes32 id) external nonReentrant {
        Operation storage o = _operations[id];
        require(frozen && o.status == Status.Scheduled && block.timestamp >= o.readyAt, "not ready");
        IGovernorWiring(governor).validateAction(o.target, o.data);
        o.status = Status.Done;
        _dispatch(id, o.target, o.data);
        emit Executed(id);
    }

    function _dispatch(bytes32 id, address target, bytes memory data) private {
        // Validation uses exact lengths plus decode/re-encode. Copying here is bounded to 228 bytes.
        bytes4 selector;
        assembly ("memory-safe") { selector := mload(add(data, 32)) }
        bytes memory args = new bytes(data.length - 4);
        for (uint256 i; i < args.length; ++i) {
            args[i] = data[i + 4];
        }
        if (selector == FeeHook.activatePolicy.selector) {
            (address candidate, bytes32 codeHash) = abi.decode(args, (address, bytes32));
            FeeHook(target).activatePolicy(candidate, codeHash);
        } else if (selector == Treasury.setRecipient.selector) {
            (address recipient, uint256 version, bool enabled, bytes32 metadata) =
                abi.decode(args, (address, uint256, bool, bytes32));
            Treasury(target).setRecipient(recipient, version, enabled, metadata);
        } else if (selector == Treasury.pay.selector) {
            Treasury.PayArgs memory a = abi.decode(args, (Treasury.PayArgs));
            Treasury(target).pay(a.paymentId, a.asset, a.bucket, a.recipient, a.version, a.amount, a.purposeHash);
        } else {
            require(selector == MockOracle.request.selector, "action");
            bytes32 requestId = MockOracle(target).request(abi.decode(args, (bytes32)));
            emit OracleRequestCreated(id, requestId);
        }
    }
}
