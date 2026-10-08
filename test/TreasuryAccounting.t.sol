// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {Treasury} from "../src/Treasury.sol";
import {MockIMD} from "../src/IMDAO.sol";
import {FaultToken, TreasuryHarness} from "./helpers/TreasuryHarness.sol";

contract TreasuryAccountingTest is Test {
    FaultToken internal a;
    FaultToken internal b;
    TreasuryHarness internal h;
    Treasury internal t;
    address internal recipient;
    uint256 internal nonce;

    function setUp() public {
        vm.warp(10000);
        a = new FaultToken();
        b = new FaultToken();
        MockIMD imd = new MockIMD(address(this));
        recipient = makeAddr("unit recipient");
        h = new TreasuryHarness(address(a), address(b), address(imd), address(this), makeAddr("unit responder"));
        h.initialize();
        t = h.treasury();
        a.transfer(h.manager(), 2_000_000 ether);
        b.transfer(h.manager(), 2_000_000 ether);
        h.accrue(address(a), 1_000_000 ether, 8000);
        h.accrue(address(b), 1_000_000 ether, 8000);
        _enroll(recipient);
    }

    function _enroll(address who) internal returns (uint256 version) {
        (version,,) = t.recipients(who);
        h.enroll(who, version, true);
        ++version;
        vm.prank(who);
        t.accept(version);
    }

    function _terms(address token, address who, uint8 bucket, uint256 amount)
        internal
        returns (Treasury.PayArgs memory)
    {
        (uint256 version,,) = t.recipients(who);
        return Treasury.PayArgs(
            keccak256(abi.encode(++nonce)), token, bucket, who, version, amount, keccak256("unit milestone")
        );
    }

    function _reserve(Treasury.PayArgs memory p) internal {
        bytes32 proposalId = keccak256(abi.encode("proposal", p.paymentId));
        h.newReservation(p, proposalId, vm.getBlockTimestamp() + 3600);
    }

    function _pay(Treasury.PayArgs memory p) internal {
        vm.warp(t.payment(p.paymentId).readyAt);
        h.pay(p);
    }

    function _check(address token) internal view {
        (uint256 fees, uint256 returned, uint256 proceeds, uint256 gross, uint256 reserved) = t.ledgers(token);
        assertEq(fees + returned + proceeds - gross, t.buckets(token, 0) + t.buckets(token, 1));
        assertLe(gross + reserved, 100_000 ether);
        assertLe(t.bucketReserved(token, 0), t.buckets(token, 0));
        assertLe(t.bucketReserved(token, 1), t.buckets(token, 1));
        assertEq(reserved, t.bucketReserved(token, 0) + t.bucketReserved(token, 1));
    }

    function test_crossBucketRecipientCapIncludesReservationsAndPaid() public {
        Treasury.PayArgs memory p = _terms(address(a), recipient, 0, 6000 ether);
        _reserve(p);
        Treasury.PayArgs memory q = _terms(address(a), recipient, 1, 4000 ether);
        _reserve(q);
        Treasury.PayArgs memory r = _terms(address(a), recipient, 1, 1);
        vm.expectRevert("recipient cap");
        _reserve(r);
        _pay(p);
        r.paymentId = keccak256("after paid");
        vm.expectRevert("recipient cap");
        _reserve(r);
        h.cancel(q.paymentId);
        Treasury.PayArgs memory s = _terms(address(a), recipient, 1, 4000 ether);
        _reserve(s);
        _pay(s);
        assertEq(t.recipientGrossPaid(address(a), recipient), 10_000 ether);
        _check(address(a));
    }

    function test_globalCapAcrossRecipientsBucketsAndReservations() public {
        for (uint256 i; i < 10; ++i) {
            address who = address(uint160(uint256(keccak256(abi.encode("cap recipient", i)))));
            _enroll(who);
            Treasury.PayArgs memory p = _terms(address(a), who, uint8(i % 2), 10_000 ether);
            _reserve(p);
            if (i % 2 == 0) _pay(p);
        }
        Treasury.PayArgs memory more = _terms(address(a), recipient, 0, 1);
        vm.expectRevert("global cap");
        _reserve(more);
        Treasury.PayArgs memory otherAsset = _terms(address(b), recipient, 0, 10_000 ether);
        _reserve(otherAsset);
        _pay(otherAsset);
        _check(address(a));
        _check(address(b));
    }

    function test_returnsAndReenrollmentNeverResetLifetimeCaps() public {
        Treasury.PayArgs memory p = _terms(address(a), recipient, 0, 10_000 ether);
        _reserve(p);
        _pay(p);
        vm.startPrank(recipient);
        a.approve(address(t), p.amount);
        t.returnUnspent(p.paymentId, p.amount, keccak256("all returned"));
        vm.stopPrank();
        t.suspend(recipient);
        uint256 version = _enroll(recipient);
        Treasury.PayArgs memory q = _terms(address(a), recipient, 1, 1);
        assertEq(q.version, version);
        vm.expectRevert("recipient cap");
        _reserve(q);
        assertEq(t.recipientGrossPaid(address(a), recipient), 10_000 ether);
        Treasury.PayArgs memory other = _terms(address(b), recipient, 1, 10_000 ether);
        _reserve(other);
        _pay(other);
        _check(address(a));
        _check(address(b));
    }

    function test_reservedTupleCannotChangeAnyField() public {
        Treasury.PayArgs memory p = _terms(address(a), recipient, 0, 10 ether);
        _reserve(p);
        vm.warp(t.payment(p.paymentId).readyAt);
        p.amount += 1;
        vm.expectRevert("not reserved tuple");
        h.pay(p);
        p.amount -= 1;
        p.bucket = 1;
        vm.expectRevert("not reserved tuple");
        h.pay(p);
        p.bucket = 0;
        p.asset = address(b);
        vm.expectRevert("not reserved tuple");
        h.pay(p);
        p.asset = address(a);
        p.purposeHash = keccak256("edited");
        vm.expectRevert("not reserved tuple");
        h.pay(p);
    }

    function test_directTargetEnforcesTimeAndSuspension() public {
        Treasury.PayArgs memory p = _terms(address(a), recipient, 0, 1 ether);
        _reserve(p);
        vm.expectRevert("payment window");
        h.pay(p);
        vm.warp(t.payment(p.paymentId).expiresAt);
        vm.expectRevert("payment window");
        h.pay(p);
        h.cancel(p.paymentId);
        p = _terms(address(a), recipient, 0, 1 ether);
        _reserve(p);
        vm.warp(t.payment(p.paymentId).readyAt);
        t.suspend(recipient);
        vm.expectRevert("recipient inactive");
        h.pay(p);
        assertTrue(t.publiclyCancellable(p.paymentId));
        h.cancel(p.paymentId);
        _check(address(a));
    }

    function testFuzz_exactPayoutRejectsNonstandardMovements(uint8 mode) public {
        mode = uint8(bound(mode, 1, 5)); // reject, tax, extra debit, bonus credit, false return
        Treasury.PayArgs memory p = _terms(address(a), recipient, 0, 10 ether);
        _reserve(p);
        vm.warp(t.payment(p.paymentId).readyAt);
        uint256 cash = a.balanceOf(address(t));
        a.configure(FaultToken.Mode(mode), address(t), "");
        vm.expectRevert();
        h.pay(p);
        assertEq(uint256(t.payment(p.paymentId).status), uint256(Treasury.PaymentStatus.Reserved));
        assertEq(t.recipientGrossPaid(address(a), recipient), 0);
        assertEq(a.balanceOf(address(t)), cash);
        a.configure(FaultToken.Mode.Standard, address(t), "");
        h.pay(p);
        assertEq(a.balanceOf(recipient), 10 ether);
        vm.expectRevert();
        h.pay(p);
        _check(address(a));
    }

    function testFuzz_exactFeesRejectNonstandardMovements(uint8 mode) public {
        mode = uint8(bound(mode, 1, 5));
        uint256 cash = a.balanceOf(address(t));
        uint256 vaultCash = a.balanceOf(h.manager());
        a.configure(FaultToken.Mode(mode), address(t), "");
        vm.expectRevert();
        h.accrue(address(a), 10 ether, 8000);
        assertEq(a.balanceOf(address(t)), cash);
        assertEq(a.balanceOf(h.manager()), vaultCash);
        _check(address(a));
    }

    function testFuzz_exactReturnsRejectNonstandardMovements(uint8 mode) public {
        mode = uint8(bound(mode, 1, 5));
        Treasury.PayArgs memory p = _terms(address(a), recipient, 0, 10 ether);
        _reserve(p);
        _pay(p);
        a.transfer(recipient, 1 ether);
        vm.prank(recipient);
        a.approve(address(t), 10 ether);
        a.configure(FaultToken.Mode(mode), address(t), "");
        vm.prank(recipient);
        vm.expectRevert();
        t.returnUnspent(p.paymentId, 5 ether, keccak256("fault return"));
        assertEq(t.payment(p.paymentId).returned, 0);
        assertFalse(t.evidenceUsed(keccak256("fault return")));
        a.configure(FaultToken.Mode.Standard, address(t), "");
        vm.prank(recipient);
        t.returnUnspent(p.paymentId, 5 ether, keccak256("fault return"));
        _check(address(a));
    }

    function test_optionalNoReturnTokenSafeERC20AndReentrantPayoutBlocked() public {
        Treasury.PayArgs memory p = _terms(address(a), recipient, 0, 10 ether);
        _reserve(p);
        a.configure(FaultToken.Mode.NoReturn, address(t), "");
        _pay(p);
        vm.startPrank(recipient);
        a.approve(address(t), 10 ether);
        t.returnUnspent(p.paymentId, 5 ether, keccak256("no return"));
        vm.stopPrank();
        a.configure(FaultToken.Mode.Standard, address(t), "");
        Treasury.PayArgs memory q = _terms(address(a), recipient, 0, 10 ether);
        _reserve(q);
        a.configure(FaultToken.Mode.Reenter, address(h), abi.encodeCall(TreasuryHarness.pay, (q)));
        _pay(q);
        assertFalse(a.callbackSucceeded());
        assertEq(t.recipientGrossPaid(address(a), recipient), 20 ether);
        _check(address(a));
    }

    function test_rawDonationsProceedsAndNoOutgoingApprovals() public {
        Treasury.PayArgs memory p = _terms(address(a), recipient, 1, 1 ether);
        _reserve(p);
        _pay(p);
        a.transfer(recipient, 20_000 ether);
        vm.startPrank(recipient);
        a.approve(address(t), 20_000 ether);
        t.depositProceeds(p.paymentId, 20_000 ether, keccak256("unaudited proceeds"));
        vm.stopPrank();
        assertEq(t.payment(p.paymentId).proceeds, 20_000 ether);
        assertEq(t.recipientGrossPaid(address(a), recipient), 1 ether);
        a.transfer(address(t), 100 ether);
        assertEq(t.surplus(address(a)), 100 ether);
        assertEq(a.allowance(address(t), address(h)), 0);
        (bool ok,) = address(t).call(abi.encodeWithSignature("approve(address,uint256)", address(h), 1));
        assertFalse(ok);
        _check(address(a));
    }
}
