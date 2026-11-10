// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base} from "./Base.t.sol";
import {IDonationLedger} from "../contracts/interfaces/IDonationLedger.sol";
import {HashLib} from "../contracts/libraries/HashLib.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract DonationLedgerTest is Base {
    function setUp() public {
        _deployCore();
    }

    function _sample() internal pure returns (IDonationLedger.Donation memory d) {
        d = IDonationLedger.Donation({
            donorRef: keccak256("donor:alice"),
            amountMinor: 250_00,
            currency: bytes32("USD"),
            receivedAt: 1_700_000_000,
            metadataHash: keccak256("receipt-7"),
            correctsId: bytes32(0)
        });
    }

    function test_HappyPath_recordsHashAndTime() public {
        bytes32 id = keccak256("donation-1");
        IDonationLedger.Donation memory d = _sample();
        bytes32 expected = HashLib.hashDonation(id, d);

        vm.expectEmit(true, true, false, true, address(ledger));
        emit IDonationLedger.DonationRecorded(
            id, d.donorRef, d.amountMinor, d.currency, d.receivedAt, d.metadataHash, d.correctsId, expected, uint64(block.timestamp)
        );

        vm.prank(relayer);
        ledger.recordDonation(id, d);

        assertEq(ledger.recordHashOf(id), expected, "hash");
        assertEq(ledger.recordedAtOf(id), uint64(block.timestamp), "time");
        assertTrue(ledger.isRecorded(id));
    }

    function test_DuplicateId_reverts() public {
        bytes32 id = keccak256("donation-1");
        IDonationLedger.Donation memory d = _sample();
        vm.prank(relayer);
        ledger.recordDonation(id, d);

        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(IDonationLedger.AlreadyRecorded.selector, id));
        ledger.recordDonation(id, d);
    }

    function test_ZeroId_reverts() public {
        vm.prank(relayer);
        vm.expectRevert(IDonationLedger.ZeroDonationId.selector);
        ledger.recordDonation(bytes32(0), _sample());
    }

    function test_WrongRole_reverts() public {
        vm.prank(outsider);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, outsider, RELAYER_ROLE)
        );
        ledger.recordDonation(keccak256("x"), _sample());
    }

    function test_Paused_reverts() public {
        vm.prank(admin);
        ledger.pause();

        vm.prank(relayer);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        ledger.recordDonation(keccak256("x"), _sample());
    }

    function test_Correction_isNewRecordReferencingOld() public {
        bytes32 oldId = keccak256("donation-1");
        bytes32 newId = keccak256("donation-1-fix");
        IDonationLedger.Donation memory d = _sample();

        vm.prank(relayer);
        ledger.recordDonation(oldId, d);

        d.amountMinor = 300_00; // corrected amount
        d.correctsId = oldId; // points at the superseded record
        vm.prank(relayer);
        ledger.recordDonation(newId, d);

        // Both records survive; neither is mutated or deleted.
        assertTrue(ledger.isRecorded(oldId));
        assertTrue(ledger.isRecorded(newId));
        assertTrue(ledger.recordHashOf(oldId) != ledger.recordHashOf(newId));
    }

    /// @dev Hash must match the canonical library hash (which is pinned to the TS vectors).
    function test_VectorMatch() public {
        bytes32 id = bytes32(uint256(0x01));
        IDonationLedger.Donation memory d = IDonationLedger.Donation({
            donorRef: bytes32(uint256(0x02)),
            amountMinor: 1,
            currency: bytes32("USD"),
            receivedAt: 2,
            metadataHash: bytes32(uint256(0x03)),
            correctsId: bytes32(0)
        });
        bytes32 h = HashLib.hashDonation(id, d);
        vm.prank(relayer);
        ledger.recordDonation(id, d);
        assertEq(ledger.recordHashOf(id), h);
    }

    function testFuzz_recordsAnyFields(
        bytes32 id,
        bytes32 donorRef,
        uint64 amount,
        bytes32 currency,
        uint64 receivedAt,
        bytes32 meta
    ) public {
        vm.assume(id != bytes32(0));
        IDonationLedger.Donation memory d = IDonationLedger.Donation({
            donorRef: donorRef,
            amountMinor: amount,
            currency: currency,
            receivedAt: receivedAt,
            metadataHash: meta,
            correctsId: bytes32(0)
        });
        vm.prank(relayer);
        ledger.recordDonation(id, d);
        assertEq(ledger.recordHashOf(id), HashLib.hashDonation(id, d));
    }
}
