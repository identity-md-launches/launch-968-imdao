// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IGovernorWiring, IHookWiring, IOracleWiring, IDeliveryWiring, IRouterWiring} from "./Interfaces.sol";

contract Treasury is ReentrancyGuard {
    using SafeERC20 for IERC20;
    uint256 public constant RECIPIENT_CAP = 10_000 ether;
    uint256 public constant GLOBAL_CAP = 100_000 ether;
    uint256 public constant PAYMENT_WINDOW = 604800;
    enum RecipientStatus {
        Unapproved,
        PendingAcceptance,
        Active,
        Disabled,
        Suspended
    }
    enum PaymentStatus {
        Unknown,
        Proposed,
        Reserved,
        Paid,
        Cancelled
    }

    struct Recipient {
        uint256 version;
        RecipientStatus status;
        bytes32 metadataHash;
    }

    struct PayArgs {
        bytes32 paymentId;
        address asset;
        uint8 bucket;
        address recipient;
        uint256 version;
        uint256 amount;
        bytes32 purposeHash;
    }

    struct Payment {
        PayArgs terms;
        bytes32 proposalId;
        PaymentStatus status;
        uint256 readyAt;
        uint256 expiresAt;
        uint256 returned;
        uint256 proceeds;
    }

    struct Ledger {
        uint256 fees;
        uint256 returned;
        uint256 proceeds;
        uint256 grossPaid;
        uint256 reserved;
    }
    address public immutable timelock;
    address public immutable guardian;
    address public immutable manager;
    address public immutable asset0;
    address public immutable asset1;
    address public bootstrap;
    address public governor;
    address public hook;
    bool public frozen;
    mapping(address => bool) public systemAddress;
    mapping(address => Recipient) public recipients;
    mapping(bytes32 => Payment) private _payments;
    mapping(address => Ledger) public ledgers;
    mapping(address => mapping(uint8 => uint256)) public buckets;
    mapping(address => mapping(uint8 => uint256)) public bucketReserved;
    mapping(address => mapping(address => uint256)) public recipientGrossPaid;
    mapping(address => mapping(address => uint256)) public recipientReserved;
    mapping(bytes32 => bool) public evidenceUsed;
    mapping(bytes32 => bool) public receiptExists;
    uint256 public receiptNonce;

    event WiringFrozen(address governor, address hook, address router);
    event RecipientChanged(address indexed recipient, uint256 version, RecipientStatus status, bytes32 metadataHash);
    event PaymentBound(bytes32 indexed paymentId, bytes32 indexed proposalId, PayArgs terms);
    event PaymentReserved(bytes32 indexed paymentId, uint256 readyAt, uint256 expiresAt);
    event PaymentCancelled(bytes32 indexed paymentId);
    event PaymentPaid(bytes32 indexed paymentId, address asset, address recipient, uint256 amount);
    event FeeReceived(address indexed asset, uint256 amount, uint256 development, uint256 reserve);
    event BusinessReceipt(
        bytes32 indexed receiptId,
        bytes32 indexed paymentId,
        bytes32 indexed evidenceHash,
        bool proceeds,
        uint256 amount
    );

    constructor(
        address bootstrap_,
        address timelock_,
        address guardian_,
        address manager_,
        address asset0_,
        address asset1_
    ) {
        require(bootstrap_ != address(0) && timelock_.code.length > 0 && guardian_ != address(0), "authority");
        require(manager_.code.length > 0 && asset0_ != asset1_, "configuration");
        require(asset0_.code.length > 0 && asset1_.code.length > 0, "assets");
        require(IERC20Metadata(asset0_).decimals() == 18 && IERC20Metadata(asset1_).decimals() == 18, "decimals");
        bootstrap = bootstrap_;
        timelock = timelock_;
        guardian = guardian_;
        manager = manager_;
        asset0 = asset0_;
        asset1 = asset1_;
        systemAddress[address(this)] = true;
        systemAddress[bootstrap_] = true;
        systemAddress[timelock_] = true;
        systemAddress[guardian_] = true;
        systemAddress[manager_] = true;
        systemAddress[asset0_] = true;
        systemAddress[asset1_] = true;
    }

    modifier onlyGovernor() {
        require(frozen && msg.sender == governor, "governor only");
        _;
    }
    modifier onlyTimelock() {
        require(frozen && msg.sender == timelock, "timelock only");
        _;
    }

    function freeze(address governor_, address hook_, address router_) external {
        require(!frozen && msg.sender == bootstrap, "bootstrap only");
        require(governor_.code.length > 0 && hook_.code.length > 0 && router_.code.length > 0, "wiring code");
        IGovernorWiring g = IGovernorWiring(governor_);
        require(g.timelock() == timelock && g.treasury() == address(this) && g.hook() == hook_, "governor wiring");
        IHookWiring h = IHookWiring(hook_);
        require(h.treasury() == address(this) && h.timelock() == timelock && h.manager() == manager, "hook wiring");
        require(IRouterWiring(router_).manager() == manager && IRouterWiring(router_).hook() == hook_, "router wiring");
        address oracle = g.oracle();
        require(IOracleWiring(oracle).timelock() == timelock, "oracle wiring");
        address delivery = IOracleWiring(oracle).delivery();
        systemAddress[governor_] = true;
        systemAddress[hook_] = true;
        systemAddress[router_] = true;
        systemAddress[oracle] = true;
        systemAddress[delivery] = true;
        systemAddress[IDeliveryWiring(delivery).responder()] = true;
        systemAddress[g.imd()] = true;
        systemAddress[h.policyV1()] = true;
        systemAddress[h.policyV2()] = true;
        governor = governor_;
        hook = hook_;
        frozen = true;
        bootstrap = address(0);
        emit WiringFrozen(governor_, hook_, router_);
    }

    function supported(address asset) public view returns (bool) {
        return asset == asset0 || asset == asset1;
    }

    function validRecipient(address who) public view returns (bool) {
        return who != address(0) && !systemAddress[who];
    }

    function active(address who, uint256 version) public view returns (bool) {
        Recipient storage r = recipients[who];
        return r.version == version && r.status == RecipientStatus.Active;
    }

    function validateEnrollment(address who, uint256 expectedVersion, bytes32 metadataHash) public view {
        require(validRecipient(who) && metadataHash != bytes32(0), "recipient metadata");
        require(recipients[who].version == expectedVersion, "stale version");
    }

    function setRecipient(address who, uint256 expectedVersion, bool enabled, bytes32 metadataHash)
        external
        onlyTimelock
    {
        validateEnrollment(who, expectedVersion, metadataHash);
        Recipient storage r = recipients[who];
        r.version++;
        r.status = enabled ? RecipientStatus.PendingAcceptance : RecipientStatus.Disabled;
        r.metadataHash = metadataHash;
        emit RecipientChanged(who, r.version, r.status, metadataHash);
    }

    function accept(uint256 version) external {
        Recipient storage r = recipients[msg.sender];
        require(r.status == RecipientStatus.PendingAcceptance && r.version == version, "not pending version");
        r.status = RecipientStatus.Active;
        emit RecipientChanged(msg.sender, version, r.status, r.metadataHash);
    }

    function suspend(address who) external {
        require(frozen && msg.sender == guardian && validRecipient(who), "guardian only");
        Recipient storage r = recipients[who];
        r.version++;
        r.status = RecipientStatus.Suspended;
        emit RecipientChanged(who, r.version, r.status, r.metadataHash);
    }

    function validatePayment(PayArgs memory a) public view {
        require(a.paymentId != bytes32(0) && a.purposeHash != bytes32(0) && a.amount > 0, "payment fields");
        require(supported(a.asset) && a.bucket < 2 && validRecipient(a.recipient), "payment destination");
        require(active(a.recipient, a.version), "recipient inactive");
    }

    function payment(bytes32 id) external view returns (Payment memory) {
        return _payments[id];
    }

    function bind(PayArgs calldata a, bytes32 proposalId) external onlyGovernor {
        validatePayment(a);
        require(proposalId != bytes32(0) && _payments[a.paymentId].status == PaymentStatus.Unknown, "payment id used");
        Payment storage p = _payments[a.paymentId];
        p.terms = a;
        p.proposalId = proposalId;
        p.status = PaymentStatus.Proposed;
        emit PaymentBound(a.paymentId, proposalId, a);
    }

    function reserve(bytes32 id, bytes32 proposalId, uint256 readyAt) external nonReentrant onlyGovernor {
        Payment storage p = _payments[id];
        require(p.status == PaymentStatus.Proposed && p.proposalId == proposalId, "not proposed");
        require(readyAt >= block.timestamp + 3600, "delay");
        PayArgs memory a = p.terms;
        validatePayment(a);
        Ledger storage l = ledgers[a.asset];
        require(bucketReserved[a.asset][a.bucket] + a.amount <= buckets[a.asset][a.bucket], "bucket cash");
        require(l.grossPaid + l.reserved + a.amount <= GLOBAL_CAP, "global cap");
        require(
            recipientGrossPaid[a.asset][a.recipient] + recipientReserved[a.asset][a.recipient] + a.amount
                <= RECIPIENT_CAP,
            "recipient cap"
        );
        p.status = PaymentStatus.Reserved;
        p.readyAt = readyAt;
        p.expiresAt = readyAt + PAYMENT_WINDOW;
        bucketReserved[a.asset][a.bucket] += a.amount;
        l.reserved += a.amount;
        recipientReserved[a.asset][a.recipient] += a.amount;
        _solvent(a.asset);
        emit PaymentReserved(id, readyAt, p.expiresAt);
    }

    function cancel(bytes32 id) external nonReentrant onlyGovernor {
        Payment storage p = _payments[id];
        require(p.status == PaymentStatus.Proposed || p.status == PaymentStatus.Reserved, "cannot cancel");
        if (p.status == PaymentStatus.Reserved) _release(p.terms);
        p.status = PaymentStatus.Cancelled;
        emit PaymentCancelled(id);
    }

    function publiclyCancellable(bytes32 id) external view returns (bool) {
        Payment storage p = _payments[id];
        return p.status == PaymentStatus.Reserved
            && (block.timestamp >= p.expiresAt || !active(p.terms.recipient, p.terms.version));
    }

    function pay(
        bytes32 id,
        address asset,
        uint8 bucket,
        address recipient,
        uint256 version,
        uint256 amount,
        bytes32 purposeHash
    ) external nonReentrant onlyTimelock {
        Payment storage p = _payments[id];
        PayArgs memory a = PayArgs(id, asset, bucket, recipient, version, amount, purposeHash);
        require(
            p.status == PaymentStatus.Reserved && keccak256(abi.encode(p.terms)) == keccak256(abi.encode(a)),
            "not reserved tuple"
        );
        require(block.timestamp >= p.readyAt && block.timestamp < p.expiresAt, "payment window");
        validatePayment(a);
        p.status = PaymentStatus.Paid;
        _release(a);
        buckets[asset][bucket] -= amount;
        ledgers[asset].grossPaid += amount;
        recipientGrossPaid[asset][recipient] += amount;
        IERC20 token = IERC20(asset);
        uint256 senderBefore = token.balanceOf(address(this));
        uint256 receiverBefore = token.balanceOf(recipient);
        token.safeTransfer(recipient, amount);
        require(token.balanceOf(address(this)) + amount == senderBefore, "sender debit");
        require(token.balanceOf(recipient) == receiverBefore + amount, "recipient credit");
        _solvent(asset);
        emit PaymentPaid(id, asset, recipient, amount);
    }

    function _release(PayArgs memory a) private {
        bucketReserved[a.asset][a.bucket] -= a.amount;
        ledgers[a.asset].reserved -= a.amount;
        recipientReserved[a.asset][a.recipient] -= a.amount;
    }

    /// @notice Hook alone requests collection; measure both ends around its manager.take.
    function creditFee(address asset, uint256 amount, uint256 developmentBps) external nonReentrant {
        require(frozen && msg.sender == hook && supported(asset), "hook only");
        require(amount > 0 && developmentBps <= 10000, "fee fields");
        IERC20 token = IERC20(asset);
        uint256 beforeCash = token.balanceOf(address(this));
        uint256 beforeManager = token.balanceOf(manager);
        uint256 development = amount * developmentBps / 10000;
        ledgers[asset].fees += amount;
        buckets[asset][0] += development;
        buckets[asset][1] += amount - development;
        IHookWiring(hook).takeFee(asset, amount);
        require(token.balanceOf(address(this)) == beforeCash + amount, "fee credit");
        require(token.balanceOf(manager) + amount == beforeManager, "fee debit");
        _solvent(asset);
        emit FeeReceived(asset, amount, development, amount - development);
    }

    function returnUnspent(bytes32 id, uint256 amount, bytes32 evidenceHash) external nonReentrant returns (bytes32) {
        return _receipt(id, amount, evidenceHash, false);
    }

    function depositProceeds(bytes32 id, uint256 amount, bytes32 evidenceHash) external nonReentrant returns (bytes32) {
        return _receipt(id, amount, evidenceHash, true);
    }

    function _receipt(bytes32 id, uint256 amount, bytes32 evidenceHash, bool isProceeds)
        private
        returns (bytes32 receiptId)
    {
        Payment storage p = _payments[id];
        require(p.status == PaymentStatus.Paid && msg.sender == p.terms.recipient, "paid recipient only");
        require(amount > 0 && evidenceHash != bytes32(0) && !evidenceUsed[evidenceHash], "receipt fields");
        address asset = p.terms.asset;
        if (isProceeds) {
            p.proceeds += amount;
            ledgers[asset].proceeds += amount;
        } else {
            require(p.returned + amount <= p.terms.amount, "return exceeds payout");
            p.returned += amount;
            ledgers[asset].returned += amount;
        }
        evidenceUsed[evidenceHash] = true;
        receiptId = keccak256(abi.encode(block.chainid, address(this), ++receiptNonce, id, evidenceHash, isProceeds));
        receiptExists[receiptId] = true;
        buckets[asset][p.terms.bucket] += amount;
        IERC20 token = IERC20(asset);
        uint256 senderBefore = token.balanceOf(msg.sender);
        uint256 beforeCash = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        require(token.balanceOf(msg.sender) + amount == senderBefore, "return debit");
        require(token.balanceOf(address(this)) == beforeCash + amount, "return credit");
        _solvent(asset);
        emit BusinessReceipt(receiptId, id, evidenceHash, isProceeds, amount);
    }

    function surplus(address asset) external view returns (uint256) {
        require(supported(asset), "unsupported");
        return IERC20(asset).balanceOf(address(this)) - buckets[asset][0] - buckets[asset][1];
    }

    function _solvent(address asset) private view {
        require(IERC20(asset).balanceOf(address(this)) >= buckets[asset][0] + buckets[asset][1], "insolvent");
    }
}
