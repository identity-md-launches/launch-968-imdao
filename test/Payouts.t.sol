// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Fixture} from "./helpers/Fixture.sol";
import {Treasury} from "../src/Treasury.sol";
import {RestrictedGovernor} from "../src/RestrictedGovernor.sol";
import {RestrictedTimelock} from "../src/RestrictedTimelock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PayoutsTest is Fixture {
    bytes32 internal constant PAYMENT = keccak256("milestone one");

    function _queued() internal returns (bytes32 id) {
        _seedFees();
        uint256 version = _enroll(recipient);
        id = _queue(address(treasury), _payment(PAYMENT, address(dao), 0, recipient, version, 1 ether));
    }

    function test_enrollBeforeProposalAndOnlyRecipientAcceptsCurrentVersion() public {
        vm.expectRevert("recipient inactive");
        _propose(address(treasury), _payment(PAYMENT, address(dao), 0, recipient, 0, 1));
        bytes32 id = _queue(
            address(treasury),
            abi.encodeCall(Treasury.setRecipient, (recipient, uint256(0), true, keccak256("operator metadata")))
        );
        _execute(id);
        vm.expectRevert("recipient inactive");
        _propose(address(treasury), _payment(PAYMENT, address(dao), 0, recipient, 1, 1));
        vm.prank(alice);
        vm.expectRevert("not pending version");
        treasury.accept(1);
        vm.prank(recipient);
        vm.expectRevert("not pending version");
        treasury.accept(0);
        vm.prank(recipient);
        treasury.accept(1);
        bytes32 p = _propose(address(treasury), _payment(PAYMENT, address(dao), 0, recipient, 1, 1));
        assertEq(treasury.payment(PAYMENT).proposalId, p);
    }

    function test_enrollmentRaceGuardianAndFreshAcceptance() public {
        bytes32 stale = _queue(
            address(treasury),
            abi.encodeCall(Treasury.setRecipient, (recipient, uint256(0), true, keccak256("operator")))
        );
        vm.prank(guardian);
        treasury.suspend(recipient);
        vm.warp(timelock.operation(stale).readyAt);
        vm.expectRevert("stale version");
        timelock.execute(stale);
        assertEq(uint256(timelock.status(stale)), uint256(RestrictedTimelock.Status.Scheduled));
        uint256 version = _enroll(recipient);
        assertEq(version, 2);
        vm.prank(alice);
        governor.cancel(stale);
        bytes32 change = _queue(
            address(treasury),
            abi.encodeCall(Treasury.setRecipient, (recipient, version, true, keccak256("replacement operator")))
        );
        _execute(change);
        assertFalse(treasury.active(recipient, version));
        assertFalse(treasury.active(recipient, version + 1));
        vm.prank(recipient);
        treasury.accept(version + 1);
        assertTrue(treasury.active(recipient, version + 1));
    }

    function test_zeroAndSystemRecipientsUnsupportedAssetBucketAndPurpose() public {
        vm.expectRevert();
        _propose(
            address(treasury), abi.encodeCall(Treasury.setRecipient, (address(0), uint256(0), true, keccak256("meta")))
        );
        vm.expectRevert();
        _propose(
            address(treasury),
            abi.encodeCall(Treasury.setRecipient, (address(timelock), uint256(0), true, keccak256("meta")))
        );
        vm.expectRevert();
        _propose(
            address(treasury),
            abi.encodeCall(Treasury.setRecipient, (address(router), uint256(0), true, keccak256("meta")))
        );
        uint256 version = _enroll(recipient);
        vm.expectRevert();
        _propose(address(treasury), _payment(PAYMENT, address(imd), 0, recipient, version, 1));
        vm.expectRevert();
        _propose(address(treasury), _payment(PAYMENT, address(dao), 2, recipient, version, 1));
        vm.expectRevert();
        _propose(address(treasury), _payment(PAYMENT, address(dao), 0, recipient, version, 0));
        vm.expectRevert();
        _propose(address(treasury), _payment(bytes32(0), address(dao), 0, recipient, version, 1));
        vm.expectRevert();
        _propose(
            address(treasury),
            abi.encodeCall(Treasury.pay, (PAYMENT, address(dao), uint8(0), recipient, version, uint256(1), bytes32(0)))
        );
    }

    function test_queueReservesCashAndCapsAndDirectExecutionAtReady() public {
        bytes32 id = _queued();
        Treasury.Payment memory p = treasury.payment(PAYMENT);
        assertEq(p.readyAt, timelock.operation(id).readyAt);
        assertEq(p.expiresAt, p.readyAt + 604800);
        assertEq(treasury.bucketReserved(address(dao), 0), 1 ether);
        assertEq(treasury.recipientReserved(address(dao), recipient), 1 ether);
        uint256 bucket = treasury.buckets(address(dao), 0);
        vm.warp(p.readyAt - 1);
        vm.expectRevert("not ready");
        timelock.execute(id);
        vm.warp(p.readyAt);
        vm.prank(bob);
        timelock.execute(id);
        assertEq(dao.balanceOf(recipient), 1 ether);
        assertEq(treasury.buckets(address(dao), 0), bucket - 1 ether);
        assertEq(treasury.bucketReserved(address(dao), 0), 0);
        assertEq(treasury.recipientGrossPaid(address(dao), recipient), 1 ether);
        assertEq(uint256(governor.state(id)), uint256(RestrictedGovernor.State.Executed));
        vm.expectRevert();
        governor.execute(id);
        vm.expectRevert();
        treasury.pay(PAYMENT, address(dao), 0, recipient, 1, 1 ether, keccak256("milestone"));
        _conservation(address(dao));
    }

    function test_queueFailureAtomicAndDonationsNotIncome() public {
        _enroll(recipient);
        dao.transfer(address(treasury), 100 ether);
        bytes32 id = _propose(address(treasury), _payment(PAYMENT, address(dao), 0, recipient, 1, 1 ether));
        _pass(id);
        vm.expectRevert("bucket cash");
        governor.queue(id);
        assertEq(uint256(timelock.status(id)), uint256(RestrictedTimelock.Status.Unknown));
        assertEq(uint256(treasury.payment(PAYMENT).status), uint256(Treasury.PaymentStatus.Proposed));
        assertEq(treasury.recipientReserved(address(dao), recipient), 0);
        _seedFees();
        governor.queue(id);
        assertEq(treasury.surplus(address(dao)), 100 ether);
    }

    function test_competingQueuesCannotDoubleReserveCash() public {
        bytes32 first = _queued();
        bytes32 second =
            _propose(address(treasury), _payment(keccak256("second"), address(dao), 0, recipient, 1, 1 ether));
        _pass(second);
        vm.expectRevert("bucket cash");
        governor.queue(second);
        vm.prank(alice);
        governor.cancel(first);
        governor.queue(second);
        assertEq(treasury.bucketReserved(address(dao), 0), 1 ether);
        _conservation(address(dao));
    }

    function test_publicExpiryCancellationAndPaymentIdNeverReusable() public {
        bytes32 id = _queued();
        Treasury.Payment memory p = treasury.payment(PAYMENT);
        vm.prank(bob);
        vm.expectRevert("cannot cancel caller");
        governor.cancel(id);
        vm.warp(p.expiresAt);
        vm.expectRevert("payment window");
        timelock.execute(id);
        vm.prank(bob);
        governor.cancel(id);
        assertEq(treasury.bucketReserved(address(dao), 0), 0);
        assertEq(treasury.recipientReserved(address(dao), recipient), 0);
        assertEq(treasury.recipientGrossPaid(address(dao), recipient), 0);
        vm.expectRevert("payment id used");
        _propose(address(treasury), _payment(PAYMENT, address(dao), 0, recipient, 1, 1 ether));
        vm.expectRevert();
        timelock.execute(id);
    }

    function test_executeAtLastSecondAndProposerCancelsBeforeReady() public {
        bytes32 id = _queued();
        vm.warp(treasury.payment(PAYMENT).expiresAt - 1);
        governor.execute(id);
        assertEq(dao.balanceOf(recipient), 1 ether);
        bytes32 other =
            _queue(address(treasury), _payment(keccak256("reserve bucket"), address(dao), 1, recipient, 1, 0.1 ether));
        vm.prank(alice);
        governor.cancel(other);
        assertEq(treasury.bucketReserved(address(dao), 1), 0);
        _conservation(address(dao));
    }

    function test_suspensionInvalidatesProposalQueueAndExecutionWithPublicRelease() public {
        bytes32 id = _queued();
        bytes32 other =
            _propose(address(treasury), _payment(keccak256("other"), address(dao), 1, recipient, 1, 0.1 ether));
        _pass(other);
        vm.prank(guardian);
        treasury.suspend(recipient);
        vm.expectRevert("recipient inactive");
        governor.queue(other);
        vm.warp(treasury.payment(PAYMENT).readyAt);
        vm.expectRevert("recipient inactive");
        timelock.execute(id);
        vm.prank(bob);
        governor.cancel(id);
        assertEq(treasury.bucketReserved(address(dao), 0), 0);
        _enroll(recipient);
        vm.expectRevert("recipient inactive");
        governor.queue(other);
        vm.prank(alice);
        governor.cancel(other);
    }

    function test_disableTakesEffectAtExecutionAndReenrollNeverEditsPayout() public {
        bytes32 id = _queued();
        bytes32 disable = _queue(
            address(treasury),
            abi.encodeCall(Treasury.setRecipient, (recipient, uint256(1), false, keccak256("disabled")))
        );
        assertTrue(treasury.active(recipient, 1));
        _execute(disable);
        assertFalse(treasury.active(recipient, 1));
        _enroll(recipient);
        vm.expectRevert("recipient inactive");
        timelock.execute(id);
        assertEq(treasury.payment(PAYMENT).terms.version, 1);
        vm.prank(bob);
        governor.cancel(id);
    }

    function test_failedTransferRollsBackForRetryNoReplay() public {
        bytes32 id = _queued();
        vm.warp(treasury.payment(PAYMENT).readyAt);
        vm.mockCall(address(dao), abi.encodeCall(IERC20.transfer, (recipient, 1 ether)), abi.encode(false));
        vm.expectRevert();
        timelock.execute(id);
        assertEq(uint256(timelock.status(id)), uint256(RestrictedTimelock.Status.Scheduled));
        assertEq(uint256(treasury.payment(PAYMENT).status), uint256(Treasury.PaymentStatus.Reserved));
        assertEq(treasury.recipientGrossPaid(address(dao), recipient), 0);
        assertEq(treasury.recipientReserved(address(dao), recipient), 1 ether);
        vm.clearMockedCalls();
        timelock.execute(id);
        vm.expectRevert();
        timelock.execute(id);
        assertEq(dao.balanceOf(recipient), 1 ether);
    }

    function test_returnsProceedsEvidenceAndSuspendedRecipient() public {
        bytes32 id = _queued();
        _execute(id);
        uint256 beforeBucket = treasury.buckets(address(dao), 0);
        vm.prank(guardian);
        treasury.suspend(recipient);
        dao.transfer(recipient, 3 ether);
        vm.startPrank(recipient);
        dao.approve(address(treasury), 4 ether);
        bytes32 receipt = treasury.returnUnspent(PAYMENT, 1 ether, keccak256("return evidence"));
        assertTrue(treasury.receiptExists(receipt));
        vm.expectRevert("return exceeds payout");
        treasury.returnUnspent(PAYMENT, 1, keccak256("extra return"));
        vm.expectRevert("receipt fields");
        treasury.depositProceeds(PAYMENT, 1, keccak256("return evidence"));
        bytes32 proceedsReceipt = treasury.depositProceeds(PAYMENT, 2 ether, keccak256("declared proceeds"));
        assertTrue(proceedsReceipt != receipt);
        vm.stopPrank();
        assertEq(treasury.buckets(address(dao), 0), beforeBucket + 3 ether);
        assertEq(treasury.payment(PAYMENT).returned, 1 ether);
        assertEq(treasury.payment(PAYMENT).proceeds, 2 ether);
        assertEq(treasury.recipientGrossPaid(address(dao), recipient), 1 ether);
        vm.expectRevert("paid recipient only");
        treasury.returnUnspent(PAYMENT, 1, keccak256("wrong caller"));
        uint256 version = _enroll(recipient);
        bytes32 next = _queue(
            address(treasury), _payment(keccak256("new milestone"), address(dao), 0, recipient, version, 1 ether)
        );
        _execute(next);
        assertEq(treasury.recipientGrossPaid(address(dao), recipient), 2 ether);
        _conservation(address(dao));
    }

    function test_failedReceiptAllowanceRollsBackEvidenceForRetry() public {
        bytes32 id = _queued();
        _execute(id);
        bytes32 evidence = keccak256("retry evidence");
        vm.prank(recipient);
        vm.expectRevert();
        treasury.returnUnspent(PAYMENT, 1 ether, evidence);
        assertFalse(treasury.evidenceUsed(evidence));
        assertEq(treasury.payment(PAYMENT).returned, 0);
        vm.startPrank(recipient);
        dao.approve(address(treasury), 1 ether);
        treasury.returnUnspent(PAYMENT, 1 ether, evidence);
        vm.stopPrank();
        assertEq(treasury.payment(PAYMENT).returned, 1 ether);
    }
}
