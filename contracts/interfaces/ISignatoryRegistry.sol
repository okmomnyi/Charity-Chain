// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title ISignatoryRegistry
/// @notice The set of signatories (three at launch, configurable) whose EIP-712
///         signatures authorize privileged notary actions. Adding or removing a
///         signatory itself requires two existing signatories, except the one-time
///         deployer `bootstrap`.
interface ISignatoryRegistry {
    event Bootstrapped(address[] signatories);
    event SignatoryAdded(address indexed signatory, address signerA, address signerB, uint256 nonce);
    event SignatoryRemoved(address indexed signatory, address signerA, address signerB, uint256 nonce);

    /// @dev `bootstrap` has already been run; the set is now immutable except via 2-of-N.
    error AlreadyBootstrapped();
    /// @dev Bootstrap set must contain at least 2 distinct signatories.
    error InvalidSignatoryCount(uint256 provided);
    /// @dev Account is already in the signatory set.
    error AlreadySignatory(address account);
    /// @dev Account is not in the signatory set.
    error NotSignatory(address account);
    /// @dev Removing would drop the set below the 2 signers needed to authorize.
    error WouldBreakQuorum(uint256 remaining);
    /// @dev Exactly two signatures are required.
    error InvalidSignatureCount(uint256 provided);
    /// @dev The same signer appeared twice; two *distinct* signatories are required.
    error DuplicateSigner(address signer);
    /// @dev A recovered signer is not a current signatory.
    error SignerNotSignatory(address signer);
    /// @dev The authorization deadline has passed.
    error AuthorizationExpired(uint256 deadline);

    /// @notice One-time initialization by the deployer. Grants SIGNATORY_ROLE to each.
    function bootstrap(address[] calldata signatories) external;

    /// @notice Add `newSignatory`, authorized by two existing signatories (EIP-712).
    /// @param sigs Exactly two signatures over `addDigest(newSignatory, nonce(), deadline)`.
    function addSignatory(address newSignatory, uint256 deadline, bytes[] calldata sigs) external;

    /// @notice Remove `signatory`, authorized by two existing signatories (EIP-712).
    /// @param sigs Exactly two signatures over `removeDigest(signatory, nonce(), deadline)`.
    function removeSignatory(address signatory, uint256 deadline, bytes[] calldata sigs) external;

    /// @notice Verify two distinct current signatories signed `digest`. Reverts otherwise.
    /// @dev `digest` is a fully-formed EIP-712 digest from the *calling* domain, letting
    ///      other contracts (e.g. CaseWorkflow) reuse the 2-of-N check for their own types.
    /// @return a First recovered signatory. @return b Second recovered signatory.
    function verifyTwoOfThree(bytes32 digest, bytes[] calldata sigs) external view returns (address a, address b);

    function isSignatory(address account) external view returns (bool);
    function signatoryCount() external view returns (uint256);
    /// @notice Monotonic nonce; increments on each successful add/remove (replay guard).
    function nonce() external view returns (uint256);

    /// @notice EIP-712 digest a client must sign to add `signatory`.
    function addDigest(address signatory, uint256 nonce_, uint256 deadline) external view returns (bytes32);
    /// @notice EIP-712 digest a client must sign to remove `signatory`.
    function removeDigest(address signatory, uint256 nonce_, uint256 deadline) external view returns (bytes32);
}
