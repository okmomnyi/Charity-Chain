
Gas Notes
Generate exact numbers with:

forge test --gas-report
forge snapshot            # writes .gas-snapshot, diff in CI with `forge snapshot --check`
Design choices that bound gas
Storage is minimal and write-once. DonationLedger stores only a 32-byte hash + an 8-byte timestamp per id; the full record lives in the event (calldata/log, not storage). One SSTORE from zero for the hash, one for the packed timestamp.
Case state is one packed slot. Case { CaseState state; uint64 authorizedAmount; uint64 disbursed; uint64 nonce; } fits in a single 32-byte slot (1 + 8 + 8 + 8 = 25 bytes), so a full authorization touches one slot.
No loops over the signatory set in the hot path. verifyTwoOfThree does exactly two ecrecovers and two hasRole reads regardless of N.
Custom errors instead of revert strings keep the revert path cheap and the deploy size down.
Report anchors append to a dynamic array; reads are O(1) by index.
Measured costs
From forge test --gas-report (Foundry 1.9.0, solc 0.8.24, optimizer 200, evm paris). Avg over the test runs; "min" is the warm/cheap path.

Function	Notes	Min	Avg
DonationLedger.recordDonation	2 SSTORE (cold) + 1 event	25,723	76,628
CaseWorkflow.submitCase	1 SSTORE + event	27,070	51,304
CaseWorkflow.recordDecision	1 SSTORE (warm) + event	29,724	34,900
CaseWorkflow.authorizeRelease	2 ecrecover + 2 hasRole + 1 SSTORE + event	30,272	54,388
CaseWorkflow.recordDisbursement	1 SSTORE + event	29,816	35,324
CaseWorkflow.close	1 SSTORE + event	28,961	31,263
PeriodAnchor.anchorDaily	2 SSTORE + event	26,277	60,756
PeriodAnchor.anchorReport	array push (2 SSTORE) + event	27,480	72,668
SignatoryRegistry.addSignatory	2 ecrecover + role grant + event	27,853	53,633
SignatoryRegistry.removeSignatory	2 ecrecover + role revoke + event	30,209	61,085
SignatoryRegistry.bootstrap	3× role grant + event	27,160	146,105
IntegrityMonitor.requestCheck	1 SSTORE + event	29,550	66,907
IntegrityMonitor.fulfillCheck	1 SSTORE + 1–2 events	24,819	32,513
All comfortably within block limits on Polygon Amoy. authorizeRelease is the costliest hot-path call at ~54k avg — dominated by the two ecrecovers, which are irreducible for a 2-of-N scheme. Re-run before a release with forge test --gas-report (and forge snapshot --check in CI to catch regressions).

