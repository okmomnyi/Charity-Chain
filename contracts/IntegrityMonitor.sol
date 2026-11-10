// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IIntegrityMonitor} from "./interfaces/IIntegrityMonitor.sol";
import {IPeriodAnchor} from "./interfaces/IPeriodAnchor.sol";
import {Errors} from "./libraries/Errors.sol";

/// @title IntegrityMonitor
/// @notice Watches for divergence between the daily root anchored on-chain and a root
///         independently observed off-chain. A requester opens a check for a day; an
///         oracle later delivers the observed root; the contract compares it to
///         `PeriodAnchor.dailyRoot(day)` and emits `IntegrityAlert` on mismatch.
///
/// @dev This is the self-contained fallback described in ARCHITECTURE 4.4: `ORACLE_ROLE`
///      is the trusted fulfiller. In the production Chainlink Functions deployment, the
///      Functions consumer's `fulfillRequest` callback (which runs the JS in
///      `functions/dailyRootCheck.js`) is what holds `ORACLE_ROLE` and calls
///      `fulfillCheck`. The comparison/alert logic is identical in both; only the
///      transport (who calls `fulfillCheck`) changes, so this contract is a drop-in
///      target for the Chainlink extension without touching its invariants or events.
contract IntegrityMonitor is IIntegrityMonitor, AccessControl {
    /// @notice May open integrity checks.
    bytes32 public constant REQUESTER_ROLE = keccak256("REQUESTER_ROLE");
    /// @notice May deliver an observed root (the oracle / Chainlink callback).
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    IPeriodAnchor public immutable anchor;

    struct Request {
        uint64 day;
        bool exists;
        bool fulfilled;
    }

    mapping(bytes32 => Request) private _requests;
    uint256 private _nonce;

    constructor(address admin, IPeriodAnchor anchor_) {
        if (admin == address(0) || address(anchor_) == address(0)) revert Errors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        anchor = anchor_;
    }

    /// @inheritdoc IIntegrityMonitor
    function requestCheck(uint64 day) external onlyRole(REQUESTER_ROLE) returns (bytes32 requestId) {
        if (!anchor.isDayAnchored(day)) revert DayNotAnchored(day);

        requestId = keccak256(abi.encode(address(this), day, _nonce));
        unchecked {
            ++_nonce;
        }
        _requests[requestId] = Request({day: day, exists: true, fulfilled: false});
        emit CheckRequested(requestId, day, msg.sender);
    }

    /// @notice Deliver the independently-observed root for an open request. Oracle only.
    /// @dev In production this is the Chainlink Functions callback target. Emits
    ///      CheckFulfilled always, and IntegrityAlert iff the roots differ.
    /// @param requestId   The id returned by `requestCheck`.
    /// @param observedRoot The root the off-chain source computed for the request's day.
    function fulfillCheck(bytes32 requestId, bytes32 observedRoot) external onlyRole(ORACLE_ROLE) {
        Request storage r = _requests[requestId];
        if (!r.exists || r.fulfilled) revert UnknownRequest(requestId);

        r.fulfilled = true;
        bytes32 anchored = anchor.dailyRoot(r.day);
        bool matched = (anchored == observedRoot);

        emit CheckFulfilled(requestId, r.day, anchored, observedRoot, matched);
        if (!matched) {
            emit IntegrityAlert(r.day, anchored, observedRoot);
        }
    }

    /// @inheritdoc IIntegrityMonitor
    function anchorOf(uint64 day) external view returns (bytes32) {
        return anchor.dailyRoot(day);
    }

    /// @notice Whether `requestId` is an open (unfulfilled) check.
    function isOpen(bytes32 requestId) external view returns (bool) {
        Request storage r = _requests[requestId];
        return r.exists && !r.fulfilled;
    }

    /// @notice The day a request targets (0 if unknown).
    function dayOf(bytes32 requestId) external view returns (uint64) {
        return _requests[requestId].day;
    }
}
