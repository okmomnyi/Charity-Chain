// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {SignatoryRegistry} from "../contracts/SignatoryRegistry.sol";
import {CaseWorkflow} from "../contracts/CaseWorkflow.sol";
import {PeriodAnchor} from "../contracts/PeriodAnchor.sol";
import {DonationLedger} from "../contracts/DonationLedger.sol";
import {IntegrityMonitor} from "../contracts/IntegrityMonitor.sol";
import {ISignatoryRegistry} from "../contracts/interfaces/ISignatoryRegistry.sol";

/// @title Deploy
/// @notice Deploys the notary suite and wires roles in one broadcast. Configuration
///         comes from env vars so the same script serves Anvil and Amoy.
///
/// Required env:
///   PRIVATE_KEY        deployer key (also the initial DEFAULT_ADMIN_ROLE holder)
///   RELAYER_ADDRESS    backend relayer (gets RELAYER_ROLE / ANCHOR_ROLE / REQUESTER_ROLE)
///   SIGNATORY_1/2/3    the three launch signatories
/// Optional env:
///   ORACLE_ADDRESS     integrity oracle / Chainlink callback (gets ORACLE_ROLE); defaults to relayer
///   ADMIN_ADDRESS      final admin; defaults to deployer
///
/// Usage:
///   forge script scripts/Deploy.s.sol:Deploy --rpc-url amoy --broadcast --verify
contract Deploy is Script {
    bytes32 constant RELAYER_ROLE = keccak256("RELAYER_ROLE");
    bytes32 constant ANCHOR_ROLE = keccak256("ANCHOR_ROLE");
    bytes32 constant REQUESTER_ROLE = keccak256("REQUESTER_ROLE");
    bytes32 constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    struct Deployed {
        SignatoryRegistry registry;
        CaseWorkflow workflow;
        PeriodAnchor anchor;
        DonationLedger ledger;
        IntegrityMonitor monitor;
    }

    function run() external returns (Deployed memory d) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address admin = vm.envOr("ADMIN_ADDRESS", deployer);
        address relayer = vm.envAddress("RELAYER_ADDRESS");
        address oracle = vm.envOr("ORACLE_ADDRESS", relayer);

        address[] memory signatories = new address[](3);
        signatories[0] = vm.envAddress("SIGNATORY_1");
        signatories[1] = vm.envAddress("SIGNATORY_2");
        signatories[2] = vm.envAddress("SIGNATORY_3");

        vm.startBroadcast(pk);
        d = _deploy(deployer, admin, relayer, oracle, signatories);
        vm.stopBroadcast();

        _log(d);
    }

    /// @dev Deploy + wire. `deployer` must be the broadcaster so it can bootstrap/grant,
    ///      then DEFAULT_ADMIN_ROLE is handed to `admin` if different.
    function _deploy(
        address deployer,
        address admin,
        address relayer,
        address oracle,
        address[] memory signatories
    ) internal returns (Deployed memory d) {
        // Deployer holds admin during wiring, then transfers to `admin`.
        d.registry = new SignatoryRegistry(deployer);
        d.registry.bootstrap(signatories);

        d.workflow = new CaseWorkflow(deployer, ISignatoryRegistry(address(d.registry)));
        d.workflow.grantRole(RELAYER_ROLE, relayer);

        d.anchor = new PeriodAnchor(deployer);
        d.anchor.grantRole(ANCHOR_ROLE, relayer);

        d.ledger = new DonationLedger(deployer);
        d.ledger.grantRole(RELAYER_ROLE, relayer);

        d.monitor = new IntegrityMonitor(deployer, d.anchor);
        d.monitor.grantRole(REQUESTER_ROLE, relayer);
        d.monitor.grantRole(ORACLE_ROLE, oracle);

        if (admin != deployer) {
            _handoff(d, admin, deployer);
        }
    }

    /// @dev Grant DEFAULT_ADMIN_ROLE to `admin` and renounce the deployer's.
    function _handoff(Deployed memory d, address admin, address deployer) internal {
        bytes32 da = 0x00; // DEFAULT_ADMIN_ROLE
        d.registry.grantRole(da, admin);
        d.registry.renounceRole(da, deployer);
        d.workflow.grantRole(da, admin);
        d.workflow.renounceRole(da, deployer);
        d.anchor.grantRole(da, admin);
        d.anchor.renounceRole(da, deployer);
        d.ledger.grantRole(da, admin);
        d.ledger.renounceRole(da, deployer);
        d.monitor.grantRole(da, admin);
        d.monitor.renounceRole(da, deployer);
    }

    function _log(Deployed memory d) internal pure {
        console2.log("SignatoryRegistry:", address(d.registry));
        console2.log("CaseWorkflow:     ", address(d.workflow));
        console2.log("PeriodAnchor:     ", address(d.anchor));
        console2.log("DonationLedger:   ", address(d.ledger));
        console2.log("IntegrityMonitor: ", address(d.monitor));
    }
}
