// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title ICaseWorkflow
/// @notice Records the lifecycle of a disbursement case: submission, decision,
///         two-signatory release authorization, disbursement and closure. The
///         chain holds no funds — it is the tamper-evident record of who approved
///         what, and the ceiling an off-chain treasury may pay out.
interface ICaseWorkflow {
    /// @notice Case states. Only the transitions encoded in the contract are legal.
    ///         None -> Submitted -> {Approved|Rejected}
    ///         Approved -> Authorized -> Disbursed
    ///         {Disbursed|Authorized|Rejected} -> Closed
    enum CaseState {
        None,
        Submitted,
        Approved,
        Rejected,
        Authorized,
        Disbursed,
        Closed
    }

    event CaseSubmitted(bytes32 indexed caseId, bytes32 detailsHash, address indexed submitter, uint64 at);
    event DecisionRecorded(
        bytes32 indexed caseId, bool approved, bytes32 reasonHash, address indexed relayer, uint64 at
    );
    event ReleaseAuthorized(
        bytes32 indexed caseId,
        uint64 amountMinor,
        uint64 nonce,
        uint64 deadline,
        address signerA,
        address signerB,
        uint64 at
    );
    event DisbursementRecorded(
        bytes32 indexed caseId, uint64 amountMinor, uint64 totalDisbursed, bytes32 referenceHash, uint64 at
    );
    event CaseClosed(bytes32 indexed caseId, address indexed by, uint64 at);

    /// @dev The case is not in a state from which this action is legal.
    error InvalidState(bytes32 caseId, CaseState current);
    /// @dev A case already exists under this id.
    error CaseExists(bytes32 caseId);
    /// @dev The release authorization deadline has passed.
    error AuthorizationExpired(uint256 deadline);
    /// @dev Disbursing this amount would exceed the authorized ceiling.
    error ExceedsAuthorized(uint64 requested, uint64 remaining);
    /// @dev Zero is not a valid case id or amount.
    error ZeroValue();

    /// @notice Open a new case. None -> Submitted. Relayer-gated.
    function submitCase(bytes32 caseId, bytes32 detailsHash) external;

    /// @notice Record the off-chain decision. Submitted -> Approved|Rejected. Relayer-gated.
    function recordDecision(bytes32 caseId, bool approved, bytes32 reasonHash) external;

    /// @notice Authorize a release with two signatory signatures. Approved -> Authorized.
    ///         Callable by anyone who holds two valid signatures (the signatures are the
    ///         authority, not msg.sender).
    /// @param sigs Two signatures over `releaseDigest(caseId, amountMinor, nonce, deadline)`.
    function authorizeRelease(bytes32 caseId, uint64 amountMinor, uint64 deadline, bytes[] calldata sigs)
        external;

    /// @notice Record an actual off-chain payout against the authorized ceiling. Relayer-gated.
    ///         The running total can never exceed the authorized amount.
    function recordDisbursement(bytes32 caseId, uint64 amountMinor, bytes32 referenceHash) external;

    /// @notice Close a terminal case. {Disbursed|Authorized|Rejected} -> Closed. Relayer-gated.
    function close(bytes32 caseId) external;

    function stateOf(bytes32 caseId) external view returns (CaseState);
    function authorizedAmountOf(bytes32 caseId) external view returns (uint64);
    function disbursedOf(bytes32 caseId) external view returns (uint64);
    /// @notice Per-case release nonce; increments on each authorization (replay guard).
    function caseNonceOf(bytes32 caseId) external view returns (uint64);

    /// @notice EIP-712 digest a signatory must sign to authorize a release.
    function releaseDigest(bytes32 caseId, uint64 amountMinor, uint64 nonce_, uint64 deadline)
        external
        view
        returns (bytes32);
}
