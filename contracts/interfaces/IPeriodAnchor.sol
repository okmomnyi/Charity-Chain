// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IPeriodAnchor
/// @notice Commits Merkle roots and report hashes for periods so anyone can later
///         prove a record was included. Daily roots are write-once. Reports are
///         versioned: a correction appends a new version and old versions stay readable.
interface IPeriodAnchor {
    event DailyAnchored(uint64 indexed day, bytes32 root, address indexed by, uint64 at);
    event ReportAnchored(
        uint16 indexed year,
        uint8 indexed quarter,
        uint32 version,
        bytes32 reportHash,
        bytes32 periodRoot,
        address indexed by,
        uint64 at
    );

    /// @dev This day already has a root; daily anchors are write-once.
    error DayAlreadyAnchored(uint64 day);
    /// @dev A zero root/hash is not meaningful and is rejected.
    error ZeroRoot();
    /// @dev Quarter must be 1..4.
    error InvalidQuarter(uint8 quarter);

    /// @notice Anchor the Merkle root for `day` (days since Unix epoch). Write-once.
    function anchorDaily(uint64 day, bytes32 root) external;

    /// @notice Append a report anchor for (`year`,`quarter`). Returns the new 1-based version.
    function anchorReport(uint16 year, uint8 quarter, bytes32 reportHash, bytes32 periodRoot)
        external
        returns (uint32 version);

    function dailyRoot(uint64 day) external view returns (bytes32);
    function isDayAnchored(uint64 day) external view returns (bool);

    function reportHash(uint16 year, uint8 quarter, uint32 version) external view returns (bytes32);
    function reportPeriodRoot(uint16 year, uint8 quarter, uint32 version) external view returns (bytes32);
    /// @notice Latest version for (year,quarter); 0 means none anchored yet.
    function latestReportVersion(uint16 year, uint8 quarter) external view returns (uint32);
}
