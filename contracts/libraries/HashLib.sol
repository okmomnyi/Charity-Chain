// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IDonationLedger} from "../interfaces/IDonationLedger.sol";

/// @title HashLib
/// @notice Canonical hashing functions for CharityChain.
/// @dev All encoding and field ordering must match the backend specification.
///      `hashDonation` is pinned to the TypeScript side via the golden vectors in
///      `scripts/gen-vectors.mjs` / `shared/vectors/donations.json`.
library HashLib {
    /// @dev keccak256 of the donation type string. Field order and types must match
    ///      `IDonationLedger.Donation` and `scripts/gen-vectors.mjs` exactly.
    bytes32 internal constant DONATION_TYPEHASH = keccak256(
        "Donation(bytes32 donationId,bytes32 donorRef,uint64 amountMinor,bytes32 currency,uint64 receivedAt,bytes32 metadataHash,bytes32 correctsId)"
    );

    bytes32 internal constant DOMAIN_CASE_V1 = keccak256("malkia:v1:case");

    /// @notice Generates a deterministic ID from a resource kind and UUID.
    /// @param kind donation, case, disbursement, or report.
    /// @param uuid A lowercase, hyphenated 36-character UUID.
    function idOf(string memory kind, string memory uuid) internal pure returns (bytes32) {
        bytes32 kindHash = keccak256(bytes(kind));

        require(
            kindHash == keccak256("donation") || kindHash == keccak256("case")
                || kindHash == keccak256("disbursement") || kindHash == keccak256("report"),
            "HashLib: invalid kind"
        );

        _validateUuid(bytes(uuid));

        return keccak256(abi.encodePacked("malkia:v1:", kind, ":", uuid));
    }

    /// @notice Calculates the canonical donation record hash over `donationId` and the
    ///         `Donation` struct. Mirrors the TypeScript `hashDonation`; field order and
    ///         types must not be changed without regenerating the golden vectors.
    function hashDonation(bytes32 donationId, IDonationLedger.Donation memory d)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                DONATION_TYPEHASH,
                donationId,
                d.donorRef,
                d.amountMinor,
                d.currency,
                d.receivedAt,
                d.metadataHash,
                d.correctsId
            )
        );
    }

    /// @notice Calculates the canonical case hash.
    function hashCase(
        bytes32 caseId,
        bytes32 subGroupId,
        bytes3 needCategory,
        uint64 requestedAmountMinor,
        uint64 createdAt
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_CASE_V1, caseId, subGroupId, needCategory, requestedAmountMinor, createdAt
            )
        );
    }

    /// @notice Hashes an audit entry with its previous entry hash.
    /// @dev canonicalJson must already be serialized using RFC8785/JCS.
    function hashAuditEntry(bytes32 prevHash, bytes memory canonicalJson)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(prevHash, canonicalJson));
    }

    /// @notice Combines two Merkle nodes in sorted byte order.
    function hashMerklePair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        if (uint256(a) < uint256(b)) {
            return keccak256(abi.encodePacked(a, b));
        }

        return keccak256(abi.encodePacked(b, a));
    }

    /// @notice Creates the canonical root for an empty day.
    /// @param day Date represented as YYYYMMDD, e.g. 20261102.
    function emptyDayRoot(uint32 day) internal pure returns (bytes32) {
        require(day >= 10000000 && day <= 99999999, "HashLib: invalid day");

        return keccak256(abi.encodePacked("malkia:v1:empty-day:", _dayToString(day)));
    }

    /// @dev Checks the lowercase, hyphenated UUID representation.
    function _validateUuid(bytes memory uuid) private pure {
        require(uuid.length == 36, "HashLib: invalid UUID length");

        for (uint256 i = 0; i < 36; i++) {
            if (i == 8 || i == 13 || i == 18 || i == 23) {
                require(uuid[i] == 0x2d, "HashLib: invalid UUID format");
            } else {
                bytes1 c = uuid[i];

                bool isDigit = c >= 0x30 && c <= 0x39;
                bool isLowerHex = c >= 0x61 && c <= 0x66;

                require(isDigit || isLowerHex, "HashLib: UUID must use lowercase hex");
            }
        }
    }

    /// @dev Converts an eight-digit YYYYMMDD number to a string.
    function _dayToString(uint32 day) private pure returns (string memory) {
        bytes memory result = new bytes(8);

        for (uint256 i = 0; i < 8; i++) {
            uint256 divisor = 10 ** (7 - i);
            uint256 digit = (uint256(day) / divisor) % 10;

            result[i] = bytes1(uint8(48 + digit));
        }

        return string(result);
    }
}
