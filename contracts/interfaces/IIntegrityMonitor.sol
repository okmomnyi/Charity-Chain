// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IIntegrityMonitor
/// @notice Compares an independently-observed daily root against the root anchored
///         in PeriodAnchor and raises an alert on mismatch. The observation is
///         delivered by an oracle callback (Chainlink Functions in production, or a
///         trusted reporter in the documented fallback).
interface IIntegrityMonitor {
    event CheckRequested(bytes32 indexed requestId, uint64 indexed day, address indexed by);
    event CheckFulfilled(
        bytes32 indexed requestId, uint64 indexed day, bytes32 anchored, bytes32 observed, bool matched
    );
    /// @notice Raised only when the observed root differs from the anchored root.
    event IntegrityAlert(uint64 indexed day, bytes32 anchored, bytes32 observed);

    /// @dev No open request exists for this id, or it was already fulfilled.
    error UnknownRequest(bytes32 requestId);
    /// @dev The day has no anchored root to check against.
    error DayNotAnchored(uint64 day);

    /// @notice Open an integrity check for `day`. Emits CheckRequested; the oracle
    ///         later calls the fulfillment entrypoint with the observed root.
    function requestCheck(uint64 day) external returns (bytes32 requestId);

    /// @notice The anchored root for `day`, as seen through PeriodAnchor.
    function anchorOf(uint64 day) external view returns (bytes32);
}
