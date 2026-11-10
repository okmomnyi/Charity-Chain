// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {IDonationLedger} from "./interfaces/IDonationLedger.sol";
import {HashLib} from "./libraries/HashLib.sol";
import {Errors} from "./libraries/Errors.sol";

/// @title DonationLedger
/// @notice Append-only, write-once ledger of donation records. Never holds funds.
///         Each id stores a canonical record hash and the time it was recorded; the
///         full fields live in the `DonationRecorded` event so a log-only indexer can
///         rebuild everything. There is no update and no delete — a correction is a
///         new record that references the old id via `Donation.correctsId`.
contract DonationLedger is IDonationLedger, AccessControl, Pausable {
    /// @notice The relayer backend that posts donation records.
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");

    mapping(bytes32 => bytes32) private _recordHash;
    mapping(bytes32 => uint64) private _recordedAt;

    /// @param admin Receives DEFAULT_ADMIN_ROLE (role administration + pause).
    constructor(address admin) {
        if (admin == address(0)) revert Errors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @inheritdoc IDonationLedger
    function recordDonation(bytes32 donationId, Donation calldata d)
        external
        whenNotPaused
        onlyRole(RELAYER_ROLE)
    {
        if (donationId == bytes32(0)) revert ZeroDonationId();
        if (_recordedAt[donationId] != 0) revert AlreadyRecorded(donationId);

        bytes32 h = HashLib.hashDonation(donationId, d);
        uint64 nowTs = uint64(block.timestamp);

        _recordHash[donationId] = h;
        _recordedAt[donationId] = nowTs;

        emit DonationRecorded(
            donationId, d.donorRef, d.amountMinor, d.currency, d.receivedAt, d.metadataHash, d.correctsId, h, nowTs
        );
    }

    /// @inheritdoc IDonationLedger
    function recordHashOf(bytes32 donationId) external view returns (bytes32) {
        return _recordHash[donationId];
    }

    /// @inheritdoc IDonationLedger
    function recordedAtOf(bytes32 donationId) external view returns (uint64) {
        return _recordedAt[donationId];
    }

    /// @inheritdoc IDonationLedger
    function isRecorded(bytes32 donationId) external view returns (bool) {
        return _recordedAt[donationId] != 0;
    }

    /// @notice Halt new records (e.g. during an incident). Admin only.
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Resume records. Admin only.
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
