// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

import {SignatoryRegistry} from "../contracts/SignatoryRegistry.sol";
import {CaseWorkflow} from "../contracts/CaseWorkflow.sol";
import {PeriodAnchor} from "../contracts/PeriodAnchor.sol";
import {DonationLedger} from "../contracts/DonationLedger.sol";
import {IntegrityMonitor} from "../contracts/IntegrityMonitor.sol";
import {ISignatoryRegistry} from "../contracts/interfaces/ISignatoryRegistry.sol";

/// @notice Shared deployment + signing helpers for the notary test suite.
abstract contract Base is Test {
    // Roles
    bytes32 internal constant RELAYER_ROLE = keccak256("RELAYER_ROLE");
    bytes32 internal constant ANCHOR_ROLE = keccak256("ANCHOR_ROLE");
    bytes32 internal constant REQUESTER_ROLE = keccak256("REQUESTER_ROLE");
    bytes32 internal constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    address internal admin = makeAddr("admin");
    address internal relayer = makeAddr("relayer");
    address internal oracle = makeAddr("oracle");
    address internal outsider = makeAddr("outsider");

    // Three launch signatories, with known private keys so tests can sign.
    uint256 internal pk1 = 0xA11CE;
    uint256 internal pk2 = 0xB0B;
    uint256 internal pk3 = 0xC0FFEE;
    uint256 internal pkIntruder = 0xBADA55;
    address internal sig1;
    address internal sig2;
    address internal sig3;
    address internal intruder;

    SignatoryRegistry internal registry;
    CaseWorkflow internal workflow;
    PeriodAnchor internal anchor;
    DonationLedger internal ledger;
    IntegrityMonitor internal monitor;

    function _deployCore() internal {
        sig1 = vm.addr(pk1);
        sig2 = vm.addr(pk2);
        sig3 = vm.addr(pk3);
        intruder = vm.addr(pkIntruder);

        vm.startPrank(admin);
        registry = new SignatoryRegistry(admin);
        address[] memory initial = new address[](3);
        initial[0] = sig1;
        initial[1] = sig2;
        initial[2] = sig3;
        registry.bootstrap(initial);

        workflow = new CaseWorkflow(admin, ISignatoryRegistry(address(registry)));
        workflow.grantRole(RELAYER_ROLE, relayer);

        anchor = new PeriodAnchor(admin);
        anchor.grantRole(ANCHOR_ROLE, relayer);

        ledger = new DonationLedger(admin);
        ledger.grantRole(RELAYER_ROLE, relayer);

        monitor = new IntegrityMonitor(admin, anchor);
        monitor.grantRole(REQUESTER_ROLE, relayer);
        monitor.grantRole(ORACLE_ROLE, oracle);
        vm.stopPrank();
    }

    /// @dev Produce a 65-byte (r,s,v) signature for `digest` from `pk`.
    function _sign(uint256 pk, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    /// @dev Two signatures over `digest`, from `pkA` then `pkB`.
    function _sign2(uint256 pkA, uint256 pkB, bytes32 digest) internal pure returns (bytes[] memory sigs) {
        sigs = new bytes[](2);
        sigs[0] = _sign(pkA, digest);
        sigs[1] = _sign(pkB, digest);
    }
}
