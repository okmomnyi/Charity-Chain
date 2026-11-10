// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base} from "./Base.t.sol";
import {ISignatoryRegistry} from "../contracts/interfaces/ISignatoryRegistry.sol";

contract SignatoryRegistryTest is Base {
    function setUp() public {
        _deployCore();
    }

    function test_Bootstrap_setsThreeSignatories() public view {
        assertEq(registry.signatoryCount(), 3);
        assertTrue(registry.isSignatory(sig1));
        assertTrue(registry.isSignatory(sig2));
        assertTrue(registry.isSignatory(sig3));
    }

    function test_Bootstrap_onlyOnce() public {
        address[] memory again = new address[](2);
        again[0] = sig1;
        again[1] = sig2;
        vm.prank(admin);
        vm.expectRevert(ISignatoryRegistry.AlreadyBootstrapped.selector);
        registry.bootstrap(again);
    }

    function test_AddSignatory_withTwoSignatories() public {
        uint256 n = registry.nonce();
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = registry.addDigest(intruder, n, deadline);
        bytes[] memory sigs = _sign2(pk1, pk2, digest);

        registry.addSignatory(intruder, deadline, sigs); // anyone may submit valid sigs
        assertTrue(registry.isSignatory(intruder));
        assertEq(registry.signatoryCount(), 4);
        assertEq(registry.nonce(), n + 1, "nonce consumed");
    }

    function test_SameSignerTwice_reverts() public {
        uint256 n = registry.nonce();
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = registry.addDigest(intruder, n, deadline);
        bytes[] memory sigs = _sign2(pk1, pk1, digest); // sig1 signs both

        vm.expectRevert(abi.encodeWithSelector(ISignatoryRegistry.DuplicateSigner.selector, sig1));
        registry.addSignatory(intruder, deadline, sigs);
    }

    function test_NonSignatorySigner_reverts() public {
        uint256 n = registry.nonce();
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = registry.addDigest(intruder, n, deadline);
        bytes[] memory sigs = _sign2(pk1, pkIntruder, digest); // intruder is not a signatory

        vm.expectRevert(abi.encodeWithSelector(ISignatoryRegistry.SignerNotSignatory.selector, intruder));
        registry.addSignatory(intruder, deadline, sigs);
    }

    /// @dev Domain separation: a signature produced under a different chain id must not
    ///      verify here. The recovered address differs from any real signatory.
    function test_WrongChainId_reverts() public {
        uint256 n = registry.nonce();
        uint256 deadline = block.timestamp + 1 hours;

        uint256 original = block.chainid;
        vm.chainId(999_999); // sign against a foreign domain
        bytes32 foreignDigest = registry.addDigest(intruder, n, deadline);
        bytes[] memory sigs = _sign2(pk1, pk2, foreignDigest);
        vm.chainId(original); // contract will recompute the digest on the real chain

        // Recovered signers won't match the signatories => SignerNotSignatory.
        vm.expectRevert();
        registry.addSignatory(intruder, deadline, sigs);
    }

    /// @dev Tampering: signatures authorize adding `intruder`, but the call asks to add a
    ///      different address. The digests differ, so recovery yields non-signatories.
    function test_TamperedPayload_reverts() public {
        uint256 n = registry.nonce();
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = registry.addDigest(intruder, n, deadline);
        bytes[] memory sigs = _sign2(pk1, pk2, digest);

        address other = makeAddr("other-candidate");
        vm.expectRevert(); // SignerNotSignatory on a mismatched recovery
        registry.addSignatory(other, deadline, sigs);
    }

    function test_Expired_reverts() public {
        uint256 n = registry.nonce();
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = registry.addDigest(intruder, n, deadline);
        bytes[] memory sigs = _sign2(pk1, pk2, digest);

        vm.warp(deadline + 1);
        vm.expectRevert(abi.encodeWithSelector(ISignatoryRegistry.AuthorizationExpired.selector, deadline));
        registry.addSignatory(intruder, deadline, sigs);
    }

    function test_Replay_reverts() public {
        uint256 n = registry.nonce();
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = registry.addDigest(intruder, n, deadline);
        bytes[] memory sigs = _sign2(pk1, pk2, digest);

        registry.addSignatory(intruder, deadline, sigs);
        // Replaying the exact same signatures fails: nonce advanced and intruder is now a signatory.
        vm.expectRevert(abi.encodeWithSelector(ISignatoryRegistry.AlreadySignatory.selector, intruder));
        registry.addSignatory(intruder, deadline, sigs);
    }

    function test_Rotation_removeThenAdd() public {
        // Remove sig3 with sig1+sig2.
        uint256 n = registry.nonce();
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 rd = registry.removeDigest(sig3, n, deadline);
        registry.removeSignatory(sig3, deadline, _sign2(pk1, pk2, rd));
        assertFalse(registry.isSignatory(sig3));
        assertEq(registry.signatoryCount(), 2);

        // Add a replacement with the remaining two.
        n = registry.nonce();
        bytes32 ad = registry.addDigest(intruder, n, deadline);
        registry.addSignatory(intruder, deadline, _sign2(pk1, pk2, ad));
        assertTrue(registry.isSignatory(intruder));
        assertEq(registry.signatoryCount(), 3);
    }

    function test_RemoveBelowQuorum_reverts() public {
        // Drop to 2 first.
        uint256 n = registry.nonce();
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 rd = registry.removeDigest(sig3, n, deadline);
        registry.removeSignatory(sig3, deadline, _sign2(pk1, pk2, rd));

        // Removing one more would leave 1 < MIN_SIGNATORIES.
        n = registry.nonce();
        bytes32 rd2 = registry.removeDigest(sig2, n, deadline);
        vm.expectRevert(abi.encodeWithSelector(ISignatoryRegistry.WouldBreakQuorum.selector, uint256(1)));
        registry.removeSignatory(sig2, deadline, _sign2(pk1, pk2, rd2));
    }
}
