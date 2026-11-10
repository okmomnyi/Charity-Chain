// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import {ICaseWorkflow} from "./interfaces/ICaseWorkflow.sol";
import {ISignatoryRegistry} from "./interfaces/ISignatoryRegistry.sol";
import {Errors} from "./libraries/Errors.sol";

/// @title CaseWorkflow
/// @notice Tamper-evident record of a disbursement case's lifecycle. The chain holds
///         no funds; `authorizedAmount` is the ceiling an off-chain treasury may pay,
///         and `disbursed` is the audit trail of what it actually paid. A release can
///         only be authorized by two valid signatories via EIP-712 — not by the
///         relayer, not by the admin, not by anyone's bare transaction.
contract CaseWorkflow is ICaseWorkflow, AccessControl, Pausable, EIP712 {
    /// @notice The relayer backend that mirrors off-chain submissions/decisions/payouts.
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");

    /// @dev keccak256("ReleaseAuthorization(bytes32 caseId,uint64 amountMinor,uint64 nonce,uint64 deadline)")
    bytes32 private constant RELEASE_TYPEHASH =
        keccak256("ReleaseAuthorization(bytes32 caseId,uint64 amountMinor,uint64 nonce,uint64 deadline)");

    /// @notice Registry consulted for signatory membership and the 2-of-N check.
    ISignatoryRegistry public immutable registry;

    struct Case {
        CaseState state;
        uint64 authorizedAmount;
        uint64 disbursed;
        uint64 nonce; // per-case release nonce; increments on each authorization
    }

    mapping(bytes32 => Case) private _cases;

    /// @param admin    Receives DEFAULT_ADMIN_ROLE (role administration + pause).
    /// @param registry_ The SignatoryRegistry used to validate release signatures.
    constructor(address admin, ISignatoryRegistry registry_) EIP712("CaseWorkflow", "1") {
        if (admin == address(0) || address(registry_) == address(0)) revert Errors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        registry = registry_;
    }

    /// @inheritdoc ICaseWorkflow
    function submitCase(bytes32 caseId, bytes32 detailsHash)
        external
        whenNotPaused
        onlyRole(RELAYER_ROLE)
    {
        if (caseId == bytes32(0)) revert ZeroValue();
        Case storage c = _cases[caseId];
        if (c.state != CaseState.None) revert CaseExists(caseId);

        c.state = CaseState.Submitted;
        emit CaseSubmitted(caseId, detailsHash, msg.sender, uint64(block.timestamp));
    }

    /// @inheritdoc ICaseWorkflow
    function recordDecision(bytes32 caseId, bool approved, bytes32 reasonHash)
        external
        whenNotPaused
        onlyRole(RELAYER_ROLE)
    {
        Case storage c = _cases[caseId];
        if (c.state != CaseState.Submitted) revert InvalidState(caseId, c.state);

        c.state = approved ? CaseState.Approved : CaseState.Rejected;
        emit DecisionRecorded(caseId, approved, reasonHash, msg.sender, uint64(block.timestamp));
    }

    /// @inheritdoc ICaseWorkflow
    function authorizeRelease(bytes32 caseId, uint64 amountMinor, uint64 deadline, bytes[] calldata sigs)
        external
        whenNotPaused
    {
        if (amountMinor == 0) revert ZeroValue();
        Case storage c = _cases[caseId];
        if (c.state != CaseState.Approved) revert InvalidState(caseId, c.state);
        if (block.timestamp > deadline) revert AuthorizationExpired(deadline);

        uint64 n = c.nonce;
        bytes32 digest = _releaseDigest(caseId, amountMinor, n, deadline);
        // Two distinct, valid, current signatories — enforced by the registry.
        (address a, address b) = registry.verifyTwoOfThree(digest, sigs);

        c.nonce = n + 1; // consume the nonce: this signed authorization can't be replayed
        c.authorizedAmount = amountMinor;
        c.state = CaseState.Authorized;

        emit ReleaseAuthorized(caseId, amountMinor, n, deadline, a, b, uint64(block.timestamp));
    }

    /// @inheritdoc ICaseWorkflow
    function recordDisbursement(bytes32 caseId, uint64 amountMinor, bytes32 referenceHash)
        external
        whenNotPaused
        onlyRole(RELAYER_ROLE)
    {
        if (amountMinor == 0) revert ZeroValue();
        Case storage c = _cases[caseId];
        if (c.state != CaseState.Authorized) revert InvalidState(caseId, c.state);

        uint64 remaining = c.authorizedAmount - c.disbursed;
        if (amountMinor > remaining) revert ExceedsAuthorized(amountMinor, remaining);

        uint64 total = c.disbursed + amountMinor;
        c.disbursed = total;
        // When the authorized ceiling is fully paid out, the case is Disbursed.
        if (total == c.authorizedAmount) {
            c.state = CaseState.Disbursed;
        }

        emit DisbursementRecorded(caseId, amountMinor, total, referenceHash, uint64(block.timestamp));
    }

    /// @inheritdoc ICaseWorkflow
    function close(bytes32 caseId) external whenNotPaused onlyRole(RELAYER_ROLE) {
        Case storage c = _cases[caseId];
        CaseState s = c.state;
        // Terminal-ish states only; never from None/Submitted/Approved/Closed.
        if (s != CaseState.Disbursed && s != CaseState.Authorized && s != CaseState.Rejected) {
            revert InvalidState(caseId, s);
        }
        c.state = CaseState.Closed;
        emit CaseClosed(caseId, msg.sender, uint64(block.timestamp));
    }

    // --- views ---------------------------------------------------------------

    /// @inheritdoc ICaseWorkflow
    function stateOf(bytes32 caseId) external view returns (CaseState) {
        return _cases[caseId].state;
    }

    /// @inheritdoc ICaseWorkflow
    function authorizedAmountOf(bytes32 caseId) external view returns (uint64) {
        return _cases[caseId].authorizedAmount;
    }

    /// @inheritdoc ICaseWorkflow
    function disbursedOf(bytes32 caseId) external view returns (uint64) {
        return _cases[caseId].disbursed;
    }

    /// @inheritdoc ICaseWorkflow
    function caseNonceOf(bytes32 caseId) external view returns (uint64) {
        return _cases[caseId].nonce;
    }

    /// @inheritdoc ICaseWorkflow
    function releaseDigest(bytes32 caseId, uint64 amountMinor, uint64 nonce_, uint64 deadline)
        external
        view
        returns (bytes32)
    {
        return _releaseDigest(caseId, amountMinor, nonce_, deadline);
    }

    function _releaseDigest(bytes32 caseId, uint64 amountMinor, uint64 nonce_, uint64 deadline)
        internal
        view
        returns (bytes32)
    {
        return _hashTypedDataV4(
            keccak256(abi.encode(RELEASE_TYPEHASH, caseId, amountMinor, nonce_, deadline))
        );
    }

    // --- admin ---------------------------------------------------------------

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
