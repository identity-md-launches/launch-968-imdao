// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Treasury} from "./Treasury.sol";
import {FeeHook} from "./FeeHook.sol";
import {RestrictedTimelock} from "./RestrictedTimelock.sol";
import {MockOracle} from "./MockOracle.sol";

contract RestrictedGovernor is ReentrancyGuard {
    uint256 public constant PROPOSAL_THRESHOLD = 10_000 ether;
    uint256 public constant QUORUM = 40_000 ether;
    uint256 public constant VOTING_DELAY = 1;
    uint256 public constant VOTING_PERIOD = 100;
    enum State {
        Unknown,
        Pending,
        Active,
        Defeated,
        Succeeded,
        Queued,
        Executed,
        Cancelled
    }

    struct Proposal {
        address proposer;
        address target;
        bytes data;
        bytes32 descriptionHash;
        bytes32 paymentId;
        uint256 snapshot;
        uint256 deadline;
        bool cancelled;
        uint256[3] baseVotes;
        uint256[3] weightedVotes;
    }
    IVotes public immutable token;
    IVotes public immutable imd;
    Treasury public immutable treasury;
    FeeHook public immutable hook;
    MockOracle public immutable oracle;
    RestrictedTimelock public immutable timelock;
    mapping(bytes32 => Proposal) private _proposals;
    mapping(bytes32 => mapping(address => bool)) public hasVoted;
    event ProposalCreated(
        bytes32 indexed id,
        address indexed proposer,
        address target,
        bytes data,
        bytes32 descriptionHash,
        string purpose,
        string text,
        string sources,
        uint256 snapshot,
        uint256 deadline
    );
    event VoteCast(bytes32 indexed id, address indexed delegate, uint8 support, uint256 base, uint256 weighted);
    event ProposalQueued(bytes32 indexed id, uint256 readyAt);
    event ProposalCancelled(bytes32 indexed id);

    constructor(
        IVotes token_,
        IVotes imd_,
        Treasury treasury_,
        FeeHook hook_,
        MockOracle oracle_,
        RestrictedTimelock timelock_
    ) {
        require(
            address(token_).code.length > 0 && address(imd_).code.length > 0 && address(token_) != address(imd_),
            "voting tokens"
        );
        require(treasury_.supported(address(token_)) && !treasury_.supported(address(imd_)), "asset distinction");
        require(
            treasury_.timelock() == address(timelock_) && hook_.timelock() == address(timelock_)
                && oracle_.timelock() == address(timelock_),
            "authority wiring"
        );
        require(address(hook_.treasury()) == address(treasury_), "treasury wiring");
        token = token_;
        imd = imd_;
        treasury = treasury_;
        hook = hook_;
        oracle = oracle_;
        timelock = timelock_;
    }

    function proposal(bytes32 id) external view returns (Proposal memory) {
        return _proposals[id];
    }

    function hashProposal(address target, bytes calldata data, bytes32 descriptionHash) public view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, address(this), target, uint256(0), data, descriptionHash));
    }

    function validateAction(address target, bytes calldata data) public view {
        require(data.length >= 4 && data.length <= 228, "action length");
        bytes4 selector = bytes4(data[:4]);
        bytes memory canonical;
        if (target == address(hook) && selector == FeeHook.activatePolicy.selector) {
            require(data.length == 68, "policy length");
            (address candidate, bytes32 codeHash) = abi.decode(data[4:], (address, bytes32));
            hook.validatePolicy(candidate, codeHash);
            canonical = abi.encodeCall(FeeHook.activatePolicy, (candidate, codeHash));
        } else if (target == address(treasury) && selector == Treasury.setRecipient.selector) {
            require(data.length == 132, "recipient length");
            (address who, uint256 version, bool enabled, bytes32 metadata) =
                abi.decode(data[4:], (address, uint256, bool, bytes32));
            treasury.validateEnrollment(who, version, metadata);
            canonical = abi.encodeCall(Treasury.setRecipient, (who, version, enabled, metadata));
        } else if (target == address(treasury) && selector == Treasury.pay.selector) {
            require(data.length == 228, "payment length");
            Treasury.PayArgs memory a = abi.decode(data[4:], (Treasury.PayArgs));
            treasury.validatePayment(a);
            canonical = abi.encodeCall(
                Treasury.pay, (a.paymentId, a.asset, a.bucket, a.recipient, a.version, a.amount, a.purposeHash)
            );
        } else if (target == address(oracle) && selector == MockOracle.request.selector) {
            require(data.length == 36, "oracle length");
            bytes32 question = abi.decode(data[4:], (bytes32));
            require(question != bytes32(0), "question");
            canonical = abi.encodeCall(MockOracle.request, (question));
        } else {
            revert("forbidden action");
        }
        require(keccak256(data) == keccak256(canonical), "noncanonical action");
    }

    function propose(
        address target,
        uint256 value,
        bytes calldata data,
        string calldata purpose,
        string calldata text,
        string calldata sources
    ) external nonReentrant returns (bytes32 id) {
        require(timelock.frozen() && treasury.frozen(), "unfrozen");
        require(value == 0 && token.getPastVotes(msg.sender, block.number - 1) >= PROPOSAL_THRESHOLD, "threshold/value");
        require(bytes(purpose).length > 0 && bytes(purpose).length <= 256, "purpose size");
        require(
            bytes(text).length > 0 && bytes(text).length <= 8192 && bytes(sources).length > 0
                && bytes(sources).length <= 2048,
            "description size"
        );
        validateAction(target, data);
        bytes32 descriptionHash = keccak256(abi.encode(purpose, text, sources));
        id = hashProposal(target, data, descriptionHash);
        Proposal storage p = _proposals[id];
        require(p.proposer == address(0), "proposal used");
        p.proposer = msg.sender;
        p.target = target;
        p.data = data;
        p.descriptionHash = descriptionHash;
        p.snapshot = block.number + VOTING_DELAY;
        p.deadline = p.snapshot + VOTING_PERIOD;
        if (bytes4(data[:4]) == Treasury.pay.selector) {
            Treasury.PayArgs memory a = abi.decode(data[4:], (Treasury.PayArgs));
            p.paymentId = a.paymentId;
            treasury.bind(a, id);
        }
        emit ProposalCreated(
            id, msg.sender, target, data, descriptionHash, purpose, text, sources, p.snapshot, p.deadline
        );
    }

    function state(bytes32 id) public view returns (State) {
        Proposal storage p = _proposals[id];
        if (p.proposer == address(0)) return State.Unknown;
        if (p.cancelled) return State.Cancelled;
        RestrictedTimelock.Status s = timelock.status(id);
        if (s == RestrictedTimelock.Status.Done) return State.Executed;
        if (s == RestrictedTimelock.Status.Scheduled) return State.Queued;
        if (block.number <= p.snapshot) return State.Pending;
        if (block.number <= p.deadline) return State.Active;
        if (p.baseVotes[1] + p.baseVotes[2] >= QUORUM && p.weightedVotes[1] > p.weightedVotes[0]) {
            return State.Succeeded;
        }
        return State.Defeated;
    }

    function votingPower(address delegate, uint256 snapshot) public view returns (uint256 base, uint256 weighted) {
        base = token.getPastVotes(delegate, snapshot);
        uint256 bonus = imd.getPastVotes(delegate, snapshot);
        uint256 cap = base / 4;
        weighted = base + (bonus < cap ? bonus : cap);
    }

    function castVote(bytes32 id, uint8 support) external {
        require(state(id) == State.Active && support < 3 && !hasVoted[id][msg.sender], "vote unavailable");
        Proposal storage p = _proposals[id];
        (uint256 base, uint256 weighted) = votingPower(msg.sender, p.snapshot);
        hasVoted[id][msg.sender] = true;
        p.baseVotes[support] += base;
        p.weightedVotes[support] += weighted;
        emit VoteCast(id, msg.sender, support, base, weighted);
    }

    function queue(bytes32 id) external nonReentrant {
        require(state(id) == State.Succeeded, "not succeeded");
        Proposal storage p = _proposals[id];
        this.validateAction(p.target, p.data);
        uint256 readyAt = block.timestamp + timelock.MIN_DELAY();
        if (p.paymentId != bytes32(0)) treasury.reserve(p.paymentId, id, readyAt);
        uint256 scheduledAt = timelock.schedule(id, p.target, p.data);
        require(scheduledAt == readyAt, "schedule mismatch");
        emit ProposalQueued(id, readyAt);
    }

    function execute(bytes32 id) external {
        timelock.execute(id);
    }

    function cancel(bytes32 id) external nonReentrant {
        State s = state(id);
        require(s != State.Unknown && s != State.Executed && s != State.Cancelled, "cannot cancel");
        Proposal storage p = _proposals[id];
        bool publicCancel = s == State.Queued && p.paymentId != bytes32(0) && treasury.publiclyCancellable(p.paymentId);
        require(msg.sender == p.proposer || publicCancel, "cannot cancel caller");
        p.cancelled = true;
        if (s == State.Queued) timelock.cancel(id);
        if (p.paymentId != bytes32(0)) treasury.cancel(p.paymentId);
        emit ProposalCancelled(id);
    }
}
