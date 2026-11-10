// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IDonationLedger
/// @notice Append-only ledger of donation records. The chain never holds funds;
///         it stores a tamper-evident hash of each off-chain donation plus the
///         full fields in an event so indexers can rebuild the whole record.
/// @dev One write per `donationId`. There is no update and no delete. A correction
///      is a *new* record whose `correctsId` points at the record it supersedes.
interface IDonationLedger {
    /// @param donorRef     Privacy-preserving donor identifier (a hash, never PII).
    /// @param amountMinor  Donation amount in minor currency units (e.g. cents).
    /// @param currency     ISO-4217 code, left-aligned ASCII packed into bytes32 ("USD").
    /// @param receivedAt   Unix time the donation was actually received off-chain.
    /// @param metadataHash keccak256 of the off-chain metadata blob (receipts, memo).
    /// @param correctsId   Prior donationId this record corrects, or bytes32(0).
    struct Donation {
        bytes32 donorRef;
        uint64 amountMinor;
        bytes32 currency;
        uint64 receivedAt;
        bytes32 metadataHash;
        bytes32 correctsId;
    }

    /// @notice Emitted once, immutably, for every recorded donation. Carries every
    ///         field so an indexer that only watches logs can reconstruct state.
    event DonationRecorded(
        bytes32 indexed donationId,
        bytes32 indexed donorRef,
        uint64 amountMinor,
        bytes32 currency,
        uint64 receivedAt,
        bytes32 metadataHash,
        bytes32 correctsId,
        bytes32 recordHash,
        uint64 recordedAt
    );

    /// @dev A record already exists for this id; ids are write-once.
    error AlreadyRecorded(bytes32 donationId);
    /// @dev The zero id is reserved as the "no record" sentinel.
    error ZeroDonationId();

    /// @notice Record a donation under `donationId`. Reverts if the id is taken.
    function recordDonation(bytes32 donationId, Donation calldata d) external;

    /// @notice The canonical record hash stored for `donationId` (0 if none).
    function recordHashOf(bytes32 donationId) external view returns (bytes32);

    /// @notice The block timestamp at which `donationId` was recorded (0 if none).
    function recordedAtOf(bytes32 donationId) external view returns (uint64);

    /// @notice Whether a record exists for `donationId`.
    function isRecorded(bytes32 donationId) external view returns (bool);
}
