// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base} from "./Base.t.sol";
import {ICaseWorkflow} from "../contracts/interfaces/ICaseWorkflow.sol";
import {ISignatoryRegistry} from "../contracts/interfaces/ISignatoryRegistry.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract CaseWorkflowTest is Base {
    bytes32 internal constant CASE = keccak256("case-1");

    function setUp() public {
        _deployCore();
    }

    // --- helpers -------------------------------------------------------------

    function _submit(bytes32 caseId) internal {
        vm.prank(relayer);
        workflow.submitCase(caseId, keccak256("details"));
    }

    function _approve(bytes32 caseId) internal {
        _submit(caseId);
        vm.prank(relayer);
        workflow.recordDecision(caseId, true, keccak256("ok"));
    }

    function _authorize(bytes32 caseId, uint64 amount) internal returns (uint64 deadline) {
        deadline = uint64(block.timestamp + 1 hours);
        uint64 n = workflow.caseNonceOf(caseId);
        bytes32 d = workflow.releaseDigest(caseId, amount, n, deadline);
        workflow.authorizeRelease(caseId, amount, deadline, _sign2(pk1, pk2, d));
    }

    // --- Invariant 1: only legal state transitions succeed --------------------

    function test_Inv1_LegalPath() public {
        _approve(CASE);
        _authorize(CASE, 1000);
        vm.prank(relayer);
        workflow.recordDisbursement(CASE, 1000, keccak256("ref"));
        assertEq(uint8(workflow.stateOf(CASE)), uint8(ICaseWorkflow.CaseState.Disbursed));
        vm.prank(relayer);
        workflow.close(CASE);
        assertEq(uint8(workflow.stateOf(CASE)), uint8(ICaseWorkflow.CaseState.Closed));
    }

    function test_Inv1_DecisionBeforeSubmit_reverts() public {
        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(ICaseWorkflow.InvalidState.selector, CASE, ICaseWorkflow.CaseState.None)
        );
        workflow.recordDecision(CASE, true, keccak256("ok"));
    }

    function test_Inv1_AuthorizeBeforeApproved_reverts() public {
        _submit(CASE); // Submitted, not Approved
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes32 d = workflow.releaseDigest(CASE, 1000, 0, deadline);
        vm.expectRevert(
            abi.encodeWithSelector(ICaseWorkflow.InvalidState.selector, CASE, ICaseWorkflow.CaseState.Submitted)
        );
        workflow.authorizeRelease(CASE, 1000, deadline, _sign2(pk1, pk2, d));
    }

    function test_Inv1_DisburseBeforeAuthorize_reverts() public {
        _approve(CASE);
        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(ICaseWorkflow.InvalidState.selector, CASE, ICaseWorkflow.CaseState.Approved)
        );
        workflow.recordDisbursement(CASE, 10, keccak256("ref"));
    }

    function test_Inv1_DoubleSubmit_reverts() public {
        _submit(CASE);
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(ICaseWorkflow.CaseExists.selector, CASE));
        workflow.submitCase(CASE, keccak256("details"));
    }

    function test_Inv1_RejectedCannotBeAuthorized() public {
        _submit(CASE);
        vm.prank(relayer);
        workflow.recordDecision(CASE, false, keccak256("no")); // Rejected
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes32 d = workflow.releaseDigest(CASE, 1000, 0, deadline);
        vm.expectRevert(
            abi.encodeWithSelector(ICaseWorkflow.InvalidState.selector, CASE, ICaseWorkflow.CaseState.Rejected)
        );
        workflow.authorizeRelease(CASE, 1000, deadline, _sign2(pk1, pk2, d));
    }

    // --- Invariant 2: a case cannot be authorized twice -----------------------

    function test_Inv2_CannotAuthorizeTwice() public {
        _approve(CASE);
        _authorize(CASE, 1000);
        // Second authorization: state is Authorized, not Approved.
        uint64 deadline = uint64(block.timestamp + 1 hours);
        uint64 n = workflow.caseNonceOf(CASE);
        bytes32 d = workflow.releaseDigest(CASE, 1000, n, deadline);
        vm.expectRevert(
            abi.encodeWithSelector(ICaseWorkflow.InvalidState.selector, CASE, ICaseWorkflow.CaseState.Authorized)
        );
        workflow.authorizeRelease(CASE, 1000, deadline, _sign2(pk1, pk2, d));
    }

    // --- Invariant 3: no replay, no use after deadline ------------------------

    function test_Inv3_ReplayAcrossCases_reverts() public {
        // Signatures are bound to caseId + nonce; a sig for CASE can't authorize another.
        _approve(CASE);
        bytes32 other = keccak256("case-2");
        _approve(other);

        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes32 d = workflow.releaseDigest(CASE, 1000, 0, deadline);
        bytes[] memory sigs = _sign2(pk1, pk2, d);

        // Same signatures, different case => recovered signers won't be signatories for `other`'s digest.
        vm.expectRevert();
        workflow.authorizeRelease(other, 1000, deadline, sigs);
    }

    function test_Inv3_ExpiredSignature_reverts() public {
        _approve(CASE);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes32 d = workflow.releaseDigest(CASE, 1000, 0, deadline);
        bytes[] memory sigs = _sign2(pk1, pk2, d);
        vm.warp(deadline + 1);
        vm.expectRevert(abi.encodeWithSelector(ICaseWorkflow.AuthorizationExpired.selector, deadline));
        workflow.authorizeRelease(CASE, 1000, deadline, sigs);
    }

    // --- Invariant 4: disbursed total never exceeds authorized ----------------

    function test_Inv4_ExceedingDisbursement_reverts() public {
        _approve(CASE);
        _authorize(CASE, 1000);
        vm.prank(relayer);
        workflow.recordDisbursement(CASE, 600, keccak256("r1"));
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(ICaseWorkflow.ExceedsAuthorized.selector, uint64(500), uint64(400)));
        workflow.recordDisbursement(CASE, 500, keccak256("r2"));
    }

    function testFuzz_Inv4_PartialDisbursementsNeverExceed(uint64 authorized, uint64 a, uint64 b) public {
        authorized = uint64(bound(authorized, 1, type(uint64).max));
        _approve(CASE);
        _authorize(CASE, authorized);

        a = uint64(bound(a, 1, authorized));
        vm.prank(relayer);
        workflow.recordDisbursement(CASE, a, keccak256("a"));
        assertLe(workflow.disbursedOf(CASE), workflow.authorizedAmountOf(CASE));

        uint64 remaining = authorized - a;
        if (remaining == 0) return;
        // Widen to avoid uint64 overflow when `remaining` is near max; cap at uint64 max.
        uint256 upper = uint256(remaining) + 10; // may overshoot to exercise the guard
        if (upper > type(uint64).max) upper = type(uint64).max;
        uint64 bb = uint64(bound(b, 1, upper));
        if (bb > remaining) {
            vm.prank(relayer);
            vm.expectRevert(
                abi.encodeWithSelector(ICaseWorkflow.ExceedsAuthorized.selector, bb, remaining)
            );
            workflow.recordDisbursement(CASE, bb, keccak256("b"));
        } else {
            vm.prank(relayer);
            workflow.recordDisbursement(CASE, bb, keccak256("b"));
        }
        assertLe(workflow.disbursedOf(CASE), workflow.authorizedAmountOf(CASE));
    }

    // --- Invariant 5: nobody can authorize without two valid signatories ------

    function test_Inv5_RelayerCannotAuthorizeWithoutSigs() public {
        _approve(CASE);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes[] memory sigs = new bytes[](2);
        sigs[0] = _sign(pk1, workflow.releaseDigest(CASE, 1000, 0, deadline));
        sigs[1] = _sign(pkIntruder, workflow.releaseDigest(CASE, 1000, 0, deadline)); // not a signatory

        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(ISignatoryRegistry.SignerNotSignatory.selector, intruder));
        workflow.authorizeRelease(CASE, 1000, deadline, sigs);
    }

    function test_Inv5_AdminCannotAuthorizeWithOneSig() public {
        _approve(CASE);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes[] memory one = new bytes[](1);
        one[0] = _sign(pk1, workflow.releaseDigest(CASE, 1000, 0, deadline));

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ISignatoryRegistry.InvalidSignatureCount.selector, uint256(1)));
        workflow.authorizeRelease(CASE, 1000, deadline, one);
    }

    // --- Invariant 6: relayer cannot move a case backward or skip states ------

    function test_Inv6_RelayerCannotSkipToDisburse() public {
        _submit(CASE); // Submitted
        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(ICaseWorkflow.InvalidState.selector, CASE, ICaseWorkflow.CaseState.Submitted)
        );
        workflow.recordDisbursement(CASE, 1, keccak256("x"));
    }

    function test_Inv6_RelayerCannotCloseSubmitted() public {
        _submit(CASE);
        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(ICaseWorkflow.InvalidState.selector, CASE, ICaseWorkflow.CaseState.Submitted)
        );
        workflow.close(CASE);
    }

    function test_Inv6_RelayerCannotReopenClosed() public {
        _approve(CASE);
        _authorize(CASE, 10);
        vm.prank(relayer);
        workflow.recordDisbursement(CASE, 10, keccak256("r"));
        vm.prank(relayer);
        workflow.close(CASE);
        // No path out of Closed.
        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(ICaseWorkflow.InvalidState.selector, CASE, ICaseWorkflow.CaseState.Closed)
        );
        workflow.close(CASE);
    }

    function test_SubmitRequiresRelayerRole() public {
        vm.prank(outsider);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, outsider, RELAYER_ROLE)
        );
        workflow.submitCase(CASE, keccak256("d"));
    }
}
