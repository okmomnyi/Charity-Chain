
Slither / Solhint Triage
Run:

solhint 'contracts/**/*.sol'
slither . --filter-paths "lib|test" --exclude-dependencies
Target: zero open high or medium findings. Everything below is either fixed in code or justified. Update this file whenever a run surfaces something new.

Expected informational / low findings (justified)
Detector	Where	Disposition
solc-version / pragma	all	Pinned to 0.8.24 (not a floating pragma); accepted.
timestamp (use of block.timestamp)	recordedAt, deadlines	Deadlines use hour+ windows; block.timestamp granularity is irrelevant at that scale. Not exploitable. Accepted.
reentrancy-events	authorizeRelease (external registry.verifyTwoOfThree before state write)	verifyTwoOfThree is a view on a trusted, immutable registry we deployed; it cannot re-enter. State is still written after the call and the function is whenNotPaused. Accepted. If the registry ever became untrusted/upgradeable, add nonReentrant.
naming-convention	internal _xxx helpers	Matches house style; Solhint configured to allow leading underscores. Accepted.
assembly	(none authored)	We write no inline assembly.
low-level-calls	(none in contracts)	No raw .call in the contracts; only in test tooling.
Checklist enforced in code (not relying on the linter)
Access control on every state-changing entrypoint (onlyRole) except authorizeRelease, which is intentionally permissionless but gated on 2-of-N signatures.
Custom errors everywhere (no revert strings) — cheaper and stable selectors.
Checks-Effects-Interactions: no external calls that move value; the only external call (verifyTwoOfThree) is a view to a trusted contract.
No selfdestruct, no delegatecall, no upgradeable proxies — the records must be immutable.
Integer safety: Solidity 0.8 checked math; disbursement uses an explicit remaining check before adding, so no overflow and no silent ceiling breach.
How to record a new finding
Re-run the commands above after any contract change.
For each new High/Medium: fix it, or add a row here with a concrete justification and a link to the test that proves it's not exploitable.
CI should fail if Slither reports an unsuppressed High/Medium.
