// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base} from "./Base.t.sol";
import {IPeriodAnchor} from "../contracts/interfaces/IPeriodAnchor.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract PeriodAnchorTest is Base {
    function setUp() public {
        _deployCore();
    }

    function test_AnchorDaily_storesRoot() public {
        vm.prank(relayer);
        anchor.anchorDaily(20_000, keccak256("root-20000"));
        assertEq(anchor.dailyRoot(20_000), keccak256("root-20000"));
        assertTrue(anchor.isDayAnchored(20_000));
    }

    function test_AnchorDaily_duplicate_reverts() public {
        vm.prank(relayer);
        anchor.anchorDaily(20_000, keccak256("a"));
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(IPeriodAnchor.DayAlreadyAnchored.selector, uint64(20_000)));
        anchor.anchorDaily(20_000, keccak256("b"));
    }

    function test_AnchorDaily_zeroRoot_reverts() public {
        vm.prank(relayer);
        vm.expectRevert(IPeriodAnchor.ZeroRoot.selector);
        anchor.anchorDaily(1, bytes32(0));
    }

    function test_AnchorDaily_wrongRole_reverts() public {
        vm.prank(outsider);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, outsider, ANCHOR_ROLE)
        );
        anchor.anchorDaily(1, keccak256("r"));
    }

    function test_Report_versionsIncrement() public {
        vm.startPrank(relayer);
        uint32 v1 = anchor.anchorReport(2025, 1, keccak256("h1"), keccak256("r1"));
        uint32 v2 = anchor.anchorReport(2025, 1, keccak256("h2"), keccak256("r2"));
        uint32 v3 = anchor.anchorReport(2025, 1, keccak256("h3"), keccak256("r3"));
        vm.stopPrank();

        assertEq(v1, 1);
        assertEq(v2, 2);
        assertEq(v3, 3);
        assertEq(anchor.latestReportVersion(2025, 1), 3);

        // Old versions remain readable after corrections.
        assertEq(anchor.reportHash(2025, 1, 1), keccak256("h1"));
        assertEq(anchor.reportHash(2025, 1, 2), keccak256("h2"));
        assertEq(anchor.reportHash(2025, 1, 3), keccak256("h3"));
        assertEq(anchor.reportPeriodRoot(2025, 1, 1), keccak256("r1"));
    }

    function test_Report_distinctQuartersIndependent() public {
        vm.startPrank(relayer);
        anchor.anchorReport(2025, 1, keccak256("q1"), keccak256("qr1"));
        anchor.anchorReport(2025, 2, keccak256("q2"), keccak256("qr2"));
        vm.stopPrank();
        assertEq(anchor.latestReportVersion(2025, 1), 1);
        assertEq(anchor.latestReportVersion(2025, 2), 1);
        assertEq(anchor.reportHash(2025, 2, 1), keccak256("q2"));
    }

    function test_Report_invalidQuarter_reverts() public {
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(IPeriodAnchor.InvalidQuarter.selector, uint8(5)));
        anchor.anchorReport(2025, 5, keccak256("h"), keccak256("r"));
    }

    function test_Report_wrongRole_reverts() public {
        vm.prank(outsider);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, outsider, ANCHOR_ROLE)
        );
        anchor.anchorReport(2025, 1, keccak256("h"), keccak256("r"));
    }
}
