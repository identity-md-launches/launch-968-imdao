// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Treasury} from "../src/Treasury.sol";
import {MockIMD} from "../src/IMDAO.sol";
import {FaultToken, TreasuryHarness} from "./helpers/TreasuryHarness.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AccountingHandler is Test {
    TreasuryHarness public h;
    Treasury public t;
    address[2] public assets;
    address public guardian;
    bytes32[] public ids;
    uint256 private _nonce;

    struct Ghost {
        uint256 fees;
        uint256 returned;
        uint256 proceeds;
        uint256 gross;
        uint256 reserved;
        uint256 surplus;
    }
    mapping(address => Ghost) public ghost;

    constructor(TreasuryHarness harness, address a, address b, address guardian_) {
        h = harness;
        t = harness.treasury();
        assets = [a, b];
        guardian = guardian_;
        IERC20(a).approve(address(t), 1_000_000 ether);
        IERC20(b).approve(address(t), 1_000_000 ether);
    }

    function enroll() public {
        (uint256 version, Treasury.RecipientStatus status,) = t.recipients(address(this));
        if (status == Treasury.RecipientStatus.Active) return;
        h.enroll(address(this), version, true);
        t.accept(version + 1);
    }

    function suspend() external {
        vm.prank(guardian);
        t.suspend(address(this));
    }

    function fee(uint8 assetIndex, uint96 seed, bool v2) external {
        address asset = assets[assetIndex % 2];
        uint256 available = IERC20(asset).balanceOf(h.manager());
        if (available == 0) return;
        uint256 amount = bound(seed, 1, available < 1000 ether ? available : 1000 ether);
        h.accrue(asset, amount, v2 ? 6000 : 8000);
        ghost[asset].fees += amount;
    }

    function queue(uint8 assetIndex, uint8 bucket, uint96 seed) external {
        address asset = assets[assetIndex % 2];
        bucket %= 2;
        (uint256 version, Treasury.RecipientStatus status,) = t.recipients(address(this));
        if (status != Treasury.RecipientStatus.Active) return;
        uint256 available = t.buckets(asset, bucket) - t.bucketReserved(asset, bucket);
        uint256 capacity = 10_000 ether - ghost[asset].gross - ghost[asset].reserved;
        if (available > capacity) available = capacity;
        if (available == 0) return;
        uint256 amount = bound(seed, 1, available);
        bytes32 id = keccak256(abi.encode("payment", ++_nonce));
        Treasury.PayArgs memory a =
            Treasury.PayArgs(id, asset, bucket, address(this), version, amount, keccak256("invariant milestone"));
        h.newReservation(a, keccak256(abi.encode("proposal", id)), vm.getBlockTimestamp() + 3600);
        ids.push(id);
        ghost[asset].reserved += amount;
    }

    function pay(uint256 index) external {
        if (ids.length == 0) return;
        Treasury.Payment memory p = t.payment(ids[index % ids.length]);
        if (
            p.status != Treasury.PaymentStatus.Reserved || !t.active(address(this), p.terms.version)
                || vm.getBlockTimestamp() >= p.expiresAt
        ) return;
        if (vm.getBlockTimestamp() < p.readyAt) vm.warp(p.readyAt);
        h.pay(p.terms);
        ghost[p.terms.asset].reserved -= p.terms.amount;
        ghost[p.terms.asset].gross += p.terms.amount;
    }

    function cancel(uint256 index, bool expireFirst) external {
        if (ids.length == 0) return;
        Treasury.Payment memory p = t.payment(ids[index % ids.length]);
        if (p.status != Treasury.PaymentStatus.Reserved) return;
        if (expireFirst && vm.getBlockTimestamp() < p.expiresAt) vm.warp(p.expiresAt);
        h.cancel(p.terms.paymentId);
        ghost[p.terms.asset].reserved -= p.terms.amount;
    }

    function receipt(uint256 index, uint96 seed, bool isProceeds) external {
        if (ids.length == 0) return;
        Treasury.Payment memory p = t.payment(ids[index % ids.length]);
        if (p.status != Treasury.PaymentStatus.Paid) return;
        uint256 available = IERC20(p.terms.asset).balanceOf(address(this));
        if (!isProceeds && available > p.terms.amount - p.returned) available = p.terms.amount - p.returned;
        if (available == 0) return;
        uint256 amount = bound(seed, 1, available < 1000 ether ? available : 1000 ether);
        bytes32 evidence = keccak256(abi.encode("evidence", ++_nonce));
        if (isProceeds) {
            t.depositProceeds(p.terms.paymentId, amount, evidence);
            ghost[p.terms.asset].proceeds += amount;
        } else {
            t.returnUnspent(p.terms.paymentId, amount, evidence);
            ghost[p.terms.asset].returned += amount;
        }
    }

    function donate(uint8 assetIndex, uint96 seed) external {
        address asset = assets[assetIndex % 2];
        uint256 available = IERC20(asset).balanceOf(address(this));
        if (available == 0) return;
        uint256 amount = bound(seed, 1, available < 10 ether ? available : 10 ether);
        assertTrue(IERC20(asset).transfer(address(t), amount));
        ghost[asset].surplus += amount;
    }

    function count() external view returns (uint256) {
        return ids.length;
    }
}

contract AccountingInvariantTest is StdInvariant, Test {
    AccountingHandler internal handler;
    Treasury internal t;
    FaultToken internal a;
    FaultToken internal b;

    function setUp() public {
        vm.warp(10000);
        a = new FaultToken();
        b = new FaultToken();
        TreasuryHarness h = new TreasuryHarness(
            address(a), address(b), address(new MockIMD(address(this))), address(this), makeAddr("responder")
        );
        h.initialize();
        t = h.treasury();
        a.transfer(h.manager(), 2_000_000 ether);
        b.transfer(h.manager(), 2_000_000 ether);
        handler = new AccountingHandler(h, address(a), address(b), address(this));
        a.transfer(address(handler), 100_000 ether);
        b.transfer(address(handler), 100_000 ether);
        handler.enroll();
        handler.fee(0, 1000 ether, false);
        handler.fee(1, 1000 ether, false);
        // Seed successful lifecycle paths before randomized interleavings.
        handler.queue(0, 0, 100 ether);
        handler.pay(0);
        handler.receipt(0, 10 ether, false);
        handler.receipt(0, 11 ether, true);
        handler.queue(1, 1, 100 ether);
        handler.cancel(1, false);
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = handler.enroll.selector;
        selectors[1] = handler.suspend.selector;
        selectors[2] = handler.fee.selector;
        selectors[3] = handler.queue.selector;
        selectors[4] = handler.pay.selector;
        selectors[5] = handler.cancel.selector;
        selectors[6] = handler.receipt.selector;
        selectors[7] = handler.donate.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
        targetContract(address(handler));
    }

    function invariant_conservationSolvencyReservationsCapsAndSurplus() public view {
        _asset(address(a));
        _asset(address(b));
    }

    function _asset(address asset) private view {
        (uint256 f, uint256 r, uint256 p, uint256 g, uint256 reserved, uint256 surplus) = handler.ghost(asset);
        (uint256 actualF, uint256 actualR, uint256 actualP, uint256 actualG, uint256 actualReserved) = t.ledgers(asset);
        assertEq(actualF, f);
        assertEq(actualR, r);
        assertEq(actualP, p);
        assertEq(actualG, g);
        assertEq(actualReserved, reserved);
        uint256 buckets = t.buckets(asset, 0) + t.buckets(asset, 1);
        assertEq(f + r + p - g, buckets);
        assertEq(IERC20(asset).balanceOf(address(t)), buckets + surplus);
        assertEq(t.surplus(asset), surplus);
        assertLe(g + reserved, 10_000 ether);
        assertLe(g + reserved, 100_000 ether);
        assertEq(t.recipientGrossPaid(asset, address(handler)), g);
        assertEq(t.recipientReserved(asset, address(handler)), reserved);
        assertEq(t.bucketReserved(asset, 0) + t.bucketReserved(asset, 1), reserved);
        assertLe(t.bucketReserved(asset, 0), t.buckets(asset, 0));
        assertLe(t.bucketReserved(asset, 1), t.buckets(asset, 1));
    }

    function invariant_paymentHistoryCannotBeRewrittenOrOverReturned() public view {
        for (uint256 i; i < handler.count(); ++i) {
            bytes32 id = handler.ids(i);
            Treasury.Payment memory p = t.payment(id);
            assertEq(p.terms.paymentId, id);
            assertEq(p.terms.recipient, address(handler));
            assertEq(p.proposalId, keccak256(abi.encode("proposal", id)));
            assertEq(p.expiresAt, p.readyAt + 604800);
            assertLe(p.returned, p.terms.amount);
            assertTrue(p.terms.asset == address(a) || p.terms.asset == address(b));
        }
    }
}
