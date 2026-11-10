
Notary Contracts
Tamper-evident, append-only records for a donation/case/disbursement system. The contracts never hold funds. They record donations, case transitions, release authorizations and period anchors so nobody can alter them later and anyone can verify.

Stack: Solidity 0.8.24 · Foundry (forge/cast/anvil) · OpenZeppelin v5 · target Polygon Amoy (chain 80002), local Anvil (31337).

Contracts
Contract	Responsibility	Authority model
DonationLedger	Write-once donation records (hash + timestamp; full fields in events).	RELAYER_ROLE records; admin can pause.
SignatoryRegistry	The signatory set (3 at launch) + reusable 2-of-N EIP-712 check.	2-of-N signatories to add/remove; deployer bootstrap once.
CaseWorkflow	Case lifecycle + two-signatory release authorization.	Relayer drives recording; releases need 2-of-N signatures, not a role.
PeriodAnchor	Write-once daily Merkle roots; versioned quarterly report anchors.	ANCHOR_ROLE.
IntegrityMonitor	Cross-checks an observed daily root vs the anchored one; alerts on mismatch.	REQUESTER_ROLE opens, ORACLE_ROLE fulfills (Chainlink Functions in prod).
Interfaces (with every event, error and struct) live in contracts/interfaces/; shared hashing in contracts/libraries/HashLib.sol (pinned to the TS side via golden vectors).

Case state machine
None ──submitCase──▶ Submitted ──recordDecision──▶ Approved ──authorizeRelease(2of3)──▶ Authorized
                           │                                                                │
                           └──recordDecision(false)──▶ Rejected          recordDisbursement (≤ authorized)
                                        │                                                   │
                                        │                                      (total == authorized)
                                        ▼                                                   ▼
                                     Closed ◀───────────────────── close ──────────────── Disbursed
Guarantees enforced on-chain: only legal transitions; a case can't be authorized twice; a release signature can't be replayed (per-case nonce) or used after its deadline; disbursed total never exceeds the authorized ceiling; nobody (relayer/admin included) can authorize without two valid signatories; the relayer can't move a case backward or skip states.

Quick start
# with foundry on PATH
forge build
forge test -vvv
forge test --gas-report
forge coverage
Regenerate the shared hashing vectors (the "TypeScript side", via ethers):

npm install
node scripts/gen-vectors.mjs      # writes shared/vectors/donations.json
forge test --match-contract VectorsTest   # asserts Solidity == JS
Deploy
cp .env.example .env    # fill in keys/addresses
# Local Anvil:
anvil &
forge script scripts/Deploy.s.sol:Deploy --rpc-url anvil --broadcast
# Polygon Amoy (+ verify on Polygonscan):
forge script scripts/Deploy.s.sol:Deploy --rpc-url amoy --broadcast --verify
Deploy.s.sol deploys all five contracts, bootstraps the registry with the three signatories, grants the relayer/oracle roles, and (if ADMIN_ADDRESS differs from the deployer) hands DEFAULT_ADMIN_ROLE to the admin and renounces the deployer's.

Security
docs/threat-model.md — assets, actors, attacks (replay, malleability, relayer griefing, key loss, signer collusion, integrity divergence) and mitigations, each linked to a test.
docs/slither-triage.md — how to run Slither/Solhint and the disposition of each finding.
docs/gas-notes.md — per-function gas notes.
Layout
contracts/
  interfaces/   IDonationLedger, ICaseWorkflow, IPeriodAnchor, ISignatoryRegistry, IIntegrityMonitor
  libraries/    HashLib (mirrors shared/hashing), Errors
  DonationLedger.sol  SignatoryRegistry.sol  CaseWorkflow.sol  PeriodAnchor.sol  IntegrityMonitor.sol
test/           *.t.sol unit + fuzz + invariant tests; Vectors.t.sol cross-checks TS hashing
scripts/        Deploy.s.sol; gen-vectors.mjs; export-abis.mjs; write-manifest.mjs
functions/      dailyRootCheck.js (Chainlink Functions source for IntegrityMonitor)
docs/           threat-model, slither-triage, gas-notes
Notes on IntegrityMonitor (Chainlink)
The shipped IntegrityMonitor is the self-contained design from ARCHITECTURE 4.4: an ORACLE_ROLE delivers the observed root to fulfillCheck, which compares it to PeriodAnchor.dailyRoot(day) and emits IntegrityAlert on mismatch. In production the Chainlink Functions consumer (running functions/dailyRootCheck.js) holds ORACLE_ROLE and is the caller of fulfillCheck; the subscription id / router / DON id are configuration (.env), never hard-coded. Swapping in the Functions transport doesn't change the comparison logic, its events, or any invariant — the tests stay valid.

