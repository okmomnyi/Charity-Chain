// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {ISignatoryRegistry} from "./interfaces/ISignatoryRegistry.sol";
import {Errors} from "./libraries/Errors.sol";

/// @title SignatoryRegistry
/// @notice The authoritative set of signatories. Mutating the set (add/remove)
///         requires two existing signatories to sign an EIP-712 authorization,
///         except the deployer's one-time `bootstrap`. Exposes a reusable
///         `verifyTwoOfThree` so other contracts (CaseWorkflow) can gate their own
///         typed-data actions on the same quorum without duplicating the checks.
contract SignatoryRegistry is ISignatoryRegistry, AccessControl, EIP712 {
    /// @notice Held by every current signatory.
    bytes32 public constant SIGNATORY_ROLE = keccak256("SIGNATORY_ROLE");

    /// @notice Minimum signatories the set may hold: two distinct signers are needed
    ///         to authorize anything, so the set can never drop below two.
    uint256 public constant MIN_SIGNATORIES = 2;

    bytes32 private constant ADD_TYPEHASH =
        keccak256("AddSignatory(address signatory,uint256 nonce,uint256 deadline)");
    bytes32 private constant REMOVE_TYPEHASH =
        keccak256("RemoveSignatory(address signatory,uint256 nonce,uint256 deadline)");

    uint256 private _count;
    uint256 private _nonce;
    bool private _bootstrapped;

    /// @param admin Receives DEFAULT_ADMIN_ROLE (may run the one-time bootstrap).
    constructor(address admin) EIP712("SignatoryRegistry", "1") {
        if (admin == address(0)) revert Errors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @inheritdoc ISignatoryRegistry
    function bootstrap(address[] calldata signatories) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_bootstrapped) revert AlreadyBootstrapped();
        uint256 n = signatories.length;
        if (n < MIN_SIGNATORIES) revert InvalidSignatoryCount(n);

        _bootstrapped = true;
        for (uint256 i; i < n; ++i) {
            address s = signatories[i];
            if (s == address(0)) revert Errors.ZeroAddress();
            // _grantRole is idempotent, so reject duplicates explicitly for a clean set.
            if (hasRole(SIGNATORY_ROLE, s)) revert AlreadySignatory(s);
            _grantRole(SIGNATORY_ROLE, s);
        }
        _count = n;
        emit Bootstrapped(signatories);
    }

    /// @inheritdoc ISignatoryRegistry
    function addSignatory(address newSignatory, uint256 deadline, bytes[] calldata sigs) external {
        if (newSignatory == address(0)) revert Errors.ZeroAddress();
        if (hasRole(SIGNATORY_ROLE, newSignatory)) revert AlreadySignatory(newSignatory);
        if (block.timestamp > deadline) revert AuthorizationExpired(deadline);

        uint256 n = _nonce;
        bytes32 digest = _addDigest(newSignatory, n, deadline);
        (address a, address b) = _verifyTwoOfThree(digest, sigs);

        _nonce = n + 1; // consume the nonce: this exact authorization can't be replayed
        _grantRole(SIGNATORY_ROLE, newSignatory);
        _count += 1;
        emit SignatoryAdded(newSignatory, a, b, n);
    }

    /// @inheritdoc ISignatoryRegistry
    function removeSignatory(address signatory, uint256 deadline, bytes[] calldata sigs) external {
        if (!hasRole(SIGNATORY_ROLE, signatory)) revert NotSignatory(signatory);
        if (_count - 1 < MIN_SIGNATORIES) revert WouldBreakQuorum(_count - 1);
        if (block.timestamp > deadline) revert AuthorizationExpired(deadline);

        uint256 n = _nonce;
        bytes32 digest = _removeDigest(signatory, n, deadline);
        (address a, address b) = _verifyTwoOfThree(digest, sigs);

        _nonce = n + 1;
        _revokeRole(SIGNATORY_ROLE, signatory);
        _count -= 1;
        emit SignatoryRemoved(signatory, a, b, n);
    }

    /// @inheritdoc ISignatoryRegistry
    function verifyTwoOfThree(bytes32 digest, bytes[] calldata sigs)
        external
        view
        returns (address a, address b)
    {
        return _verifyTwoOfThree(digest, sigs);
    }

    /// @dev The core 2-of-N check, reused by add/remove and by external callers.
    ///      Guarantees: exactly two signatures, two *distinct* recovered signers,
    ///      both currently hold SIGNATORY_ROLE, and each signature is non-malleable
    ///      and well-formed (OpenZeppelin ECDSA.recover reverts on high-s / bad v).
    function _verifyTwoOfThree(bytes32 digest, bytes[] calldata sigs)
        internal
        view
        returns (address a, address b)
    {
        if (sigs.length != 2) revert InvalidSignatureCount(sigs.length);

        a = ECDSA.recover(digest, sigs[0]);
        b = ECDSA.recover(digest, sigs[1]);

        if (a == b) revert DuplicateSigner(a);
        if (!hasRole(SIGNATORY_ROLE, a)) revert SignerNotSignatory(a);
        if (!hasRole(SIGNATORY_ROLE, b)) revert SignerNotSignatory(b);
    }

    /// @inheritdoc ISignatoryRegistry
    function addDigest(address signatory, uint256 nonce_, uint256 deadline) external view returns (bytes32) {
        return _addDigest(signatory, nonce_, deadline);
    }

    /// @inheritdoc ISignatoryRegistry
    function removeDigest(address signatory, uint256 nonce_, uint256 deadline)
        external
        view
        returns (bytes32)
    {
        return _removeDigest(signatory, nonce_, deadline);
    }

    function _addDigest(address signatory, uint256 nonce_, uint256 deadline) internal view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(ADD_TYPEHASH, signatory, nonce_, deadline)));
    }

    function _removeDigest(address signatory, uint256 nonce_, uint256 deadline)
        internal
        view
        returns (bytes32)
    {
        return _hashTypedDataV4(keccak256(abi.encode(REMOVE_TYPEHASH, signatory, nonce_, deadline)));
    }

    /// @inheritdoc ISignatoryRegistry
    function isSignatory(address account) external view returns (bool) {
        return hasRole(SIGNATORY_ROLE, account);
    }

    /// @inheritdoc ISignatoryRegistry
    function signatoryCount() external view returns (uint256) {
        return _count;
    }

    /// @inheritdoc ISignatoryRegistry
    function nonce() external view returns (uint256) {
        return _nonce;
    }
}
