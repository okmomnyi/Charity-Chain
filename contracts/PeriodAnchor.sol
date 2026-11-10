// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {IPeriodAnchor} from "./interfaces/IPeriodAnchor.sol";
import {Errors} from "./libraries/Errors.sol";

/// @title PeriodAnchor
/// @notice Commits Merkle roots (daily) and report hashes (quarterly) so inclusion of
///         any record can be proven later. Daily roots are write-once. Reports are
///         versioned: corrections append a new version and every prior version stays
///         readable, so the history of what was reported — and later corrected — is
///         itself tamper-evident.
contract PeriodAnchor is IPeriodAnchor, AccessControl, Pausable {
    /// @notice Permitted to write anchors (the relayer / reporting backend).
    bytes32 public constant ANCHOR_ROLE = keccak256("ANCHOR_ROLE");

    mapping(uint64 => bytes32) private _dailyRoot;
    mapping(uint64 => bool) private _dayAnchored;

    struct Report {
        bytes32 reportHash;
        bytes32 periodRoot;
    }

    // key = keccak256(year, quarter) => append-only list of versions (index 0 = v1)
    mapping(bytes32 => Report[]) private _reports;

    constructor(address admin) {
        if (admin == address(0)) revert Errors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @inheritdoc IPeriodAnchor
    function anchorDaily(uint64 day, bytes32 root) external whenNotPaused onlyRole(ANCHOR_ROLE) {
        if (root == bytes32(0)) revert ZeroRoot();
        if (_dayAnchored[day]) revert DayAlreadyAnchored(day);

        _dayAnchored[day] = true;
        _dailyRoot[day] = root;
        emit DailyAnchored(day, root, msg.sender, uint64(block.timestamp));
    }

    /// @inheritdoc IPeriodAnchor
    function anchorReport(uint16 year, uint8 quarter, bytes32 reportHash, bytes32 periodRoot)
        external
        whenNotPaused
        onlyRole(ANCHOR_ROLE)
        returns (uint32 version)
    {
        if (quarter == 0 || quarter > 4) revert InvalidQuarter(quarter);
        if (reportHash == bytes32(0) || periodRoot == bytes32(0)) revert ZeroRoot();

        Report[] storage versions = _reports[_key(year, quarter)];
        versions.push(Report({reportHash: reportHash, periodRoot: periodRoot}));
        version = uint32(versions.length); // 1-based

        emit ReportAnchored(year, quarter, version, reportHash, periodRoot, msg.sender, uint64(block.timestamp));
    }

    // --- views ---------------------------------------------------------------

    /// @inheritdoc IPeriodAnchor
    function dailyRoot(uint64 day) external view returns (bytes32) {
        return _dailyRoot[day];
    }

    /// @inheritdoc IPeriodAnchor
    function isDayAnchored(uint64 day) external view returns (bool) {
        return _dayAnchored[day];
    }

    /// @inheritdoc IPeriodAnchor
    function reportHash(uint16 year, uint8 quarter, uint32 version) external view returns (bytes32) {
        return _reportAt(year, quarter, version).reportHash;
    }

    /// @inheritdoc IPeriodAnchor
    function reportPeriodRoot(uint16 year, uint8 quarter, uint32 version) external view returns (bytes32) {
        return _reportAt(year, quarter, version).periodRoot;
    }

    /// @inheritdoc IPeriodAnchor
    function latestReportVersion(uint16 year, uint8 quarter) external view returns (uint32) {
        return uint32(_reports[_key(year, quarter)].length);
    }

    function _reportAt(uint16 year, uint8 quarter, uint32 version) internal view returns (Report storage) {
        Report[] storage versions = _reports[_key(year, quarter)];
        // version is 1-based; a missing version reverts (panic 0x32 / 0x11) by indexing.
        return versions[version - 1];
    }

    function _key(uint16 year, uint8 quarter) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(year, quarter));
    }

    // --- admin ---------------------------------------------------------------

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
