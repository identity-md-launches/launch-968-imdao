// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Authenticated LOCAL transport. This is not the IdentityMD live oracle protocol.
contract MockDelivery {
    address public immutable responder;

    constructor(address responder_) {
        require(responder_ != address(0), "responder");
        responder = responder_;
    }

    function deliver(MockOracle consumer, bytes calldata envelope) external {
        require(msg.sender == responder, "responder only");
        consumer.onAnswer(envelope);
    }
}

contract MockOracle {
    enum Status {
        Unknown,
        Pending,
        Answered,
        Expired
    }
    enum Answer {
        UNKNOWN,
        NO,
        YES
    }

    struct Request {
        bytes32 questionHash;
        uint256 chainId;
        uint256 expiresAt;
        Status status;
        Answer answer;
        bytes32 evidenceHash;
    }

    struct Envelope {
        bytes32 requestId;
        uint256 chainId;
        address consumer;
        bytes32 questionHash;
        bool answer;
        bytes32 evidenceHash;
    }
    address public immutable timelock;
    MockDelivery public immutable delivery;
    uint256 public constant TIMEOUT = 3600;
    uint256 public constant PAYMENT = 0;
    uint256 public nonce;
    bytes32 public pendingId;
    mapping(bytes32 => Request) public requests;
    event Requested(bytes32 indexed requestId, bytes32 indexed questionHash, uint256 nonce, uint256 expiresAt);
    event Answered(bytes32 indexed requestId, Answer answer, bytes32 evidenceHash);
    event Expired(bytes32 indexed requestId);

    constructor(address timelock_, MockDelivery delivery_) {
        require(timelock_.code.length > 0 && address(delivery_).code.length > 0, "oracle wiring");
        timelock = timelock_;
        delivery = delivery_;
    }

    function request(bytes32 questionHash) external returns (bytes32 id) {
        require(msg.sender == timelock, "timelock only");
        require(questionHash != bytes32(0) && pendingId == bytes32(0), "request unavailable");
        id = keccak256(abi.encode(++nonce, block.chainid, address(this), questionHash));
        uint256 expiresAt = block.timestamp + TIMEOUT;
        requests[id] = Request(questionHash, block.chainid, expiresAt, Status.Pending, Answer.UNKNOWN, bytes32(0));
        pendingId = id;
        emit Requested(id, questionHash, nonce, expiresAt);
    }

    function onAnswer(bytes calldata envelope) external {
        require(msg.sender == address(delivery), "delivery only");
        require(envelope.length == 192, "envelope size");
        Envelope memory a = abi.decode(envelope, (Envelope));
        require(keccak256(envelope) == keccak256(abi.encode(a)), "canonical envelope");
        Request storage r = requests[a.requestId];
        require(r.status == Status.Pending && a.requestId == pendingId, "not pending");
        require(block.timestamp < r.expiresAt, "late answer");
        require(a.chainId == block.chainid && a.chainId == r.chainId && a.consumer == address(this), "domain");
        require(a.questionHash == r.questionHash && a.evidenceHash != bytes32(0), "question evidence");
        r.status = Status.Answered;
        r.answer = a.answer ? Answer.YES : Answer.NO;
        r.evidenceHash = a.evidenceHash;
        pendingId = bytes32(0);
        emit Answered(a.requestId, r.answer, a.evidenceHash);
    }

    function expire(bytes32 id) external {
        Request storage r = requests[id];
        require(r.status == Status.Pending && block.timestamp >= r.expiresAt, "not expired");
        r.status = Status.Expired;
        pendingId = bytes32(0);
        emit Expired(id);
    }
}
