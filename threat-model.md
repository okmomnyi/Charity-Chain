
Notary — Threat Model
The notary contracts are an append-only, tamper-evident record. They never custody funds. Their job: make donations, case decisions, release authorizations and period anchors impossible to alter after the fact, and cheap for anyone to verify.

Assets
Asset	Why it matters
Donation records	Public proof that a donation was received and its canonical hash.
Case decision trail	Proof of who approved/rejected a case and when.
Release authorizations	The signed 2-of-N authority that caps what a treasury may pay out.
Period anchors (daily roots, report hashes)	Inclusion proofs for the whole dataset; the integrity backstop.
The signatory set	The root of trust for every authorization.
Actors
Admin (DEFAULT_ADMIN_ROLE) — manages roles and pause. Expected to be a multisig.
Relayer (RELAYER_ROLE / ANCHOR_ROLE / REQUESTER_ROLE) — the backend that mirrors off-chain events on-chain. Trusted for liveness, not for authority.
Signatories (SIGNATORY_ROLE) — the N (3 at launch) keys whose 2-of-N signatures authorize releases and set changes.
Oracle (ORACLE_ROLE) — delivers independently-observed roots to IntegrityMonitor (Chainlink Functions DON in production).
Anyone — may read everything, submit a valid release authorization, and verify hashes.
Attacks and mitigations
1. Signature replay
A release/add/remove signature is reused to authorize a second action.

Mitigation: every signed payload includes a monotonic nonce — per-case for releases (caseNonceOf), global for registry changes (nonce()). The nonce is consumed on use, so the same signature can never be accepted twice. Release also requires the case to be in Approved, which it leaves on first authorization. Tests: test_Inv3_*, test_Replay_reverts.
2. Signature malleability / forged signatures
An attacker mangles s/v to mint a second valid signature, or submits garbage.

Mitigation: all recovery goes through OpenZeppelin ECDSA.recover, which rejects high-s (EIP-2) and invalid v, reverting instead of returning address(0). Two distinct recovered signers are required. Tests: test_SameSignerTwice_reverts.
3. Cross-domain / cross-chain replay
A signature from another chain or another contract is replayed here.

Mitigation: EIP-712 domain separation — the digest binds chainId, verifyingContract, name and version. CaseWorkflow and SignatoryRegistry each have their own domain, so a registry signature cannot authorize a release and vice-versa. Test: test_WrongChainId_reverts.
4. Relayer griefing / overreach
The relayer tries to move a case backward, skip states, authorize a release, or over-disburse.

Mitigation: the relayer can only drive the recording transitions (submit → decision → disbursement → close). Authorization is gated solely on signatory signatures — msg.sender is irrelevant, so the relayer has no privileged path. Every transition is guarded by an explicit InvalidState check; disbursement is capped by ExceedsAuthorized. Tests: test_Inv5_*, test_Inv6_*, test_Inv4_*, invariant invariant_DisbursedNeverExceedsAuthorized.
5. Signer key loss
A signatory loses a key.

Mitigation: the remaining signatories can rotate it out via removeSignatory + addSignatory (each 2-of-N), with a quorum floor (MIN_SIGNATORIES = 2) that prevents the set from becoming unusable. Test: test_Rotation_removeThenAdd, test_RemoveBelowQuorum_reverts.
6. Signatory collusion (2 malicious signers)
Two signatories collude to authorize an illegitimate release or change the set.

Residual risk, by design. 2-of-3 means two colluding signers can authorize. This is a governance/key-custody concern, not a contract bug. Mitigations are operational: distribute keys across independent custodians/HSMs, raise N and the threshold for higher-value flows, and rely on IntegrityMonitor + the immutable event trail for detection. The chain holds no funds, so collusion yields a record, not a withdrawal; the off-chain treasury remains a second gate.
7. Integrity divergence (silent tampering of off-chain data)
The off-chain dataset is altered after a root was anchored.

Mitigation: daily roots are write-once; IntegrityMonitor compares an independently observed root (Chainlink Functions) to the anchored root and emits IntegrityAlert on mismatch. Tests: test_Fulfill_mismatchedRoot_emitsAlert.
8. Record forgery / duplication
Someone records a false donation or double-records an id.

Mitigation: recording is RELAYER_ROLE-gated and write-once per id (AlreadyRecorded); the full fields are emitted so any observer can independently recompute the hash. Corrections are new records that reference the old id, never in-place edits.
9. Denial of service / pausing
Mitigation: Pausable lets the admin halt recording during an incident without ever being able to rewrite history. Pause blocks writes, not reads or verification.
Trust boundaries (summary)
On-chain enforces: authorization authority (2-of-N), state-machine legality, disbursement ceiling, write-once-ness, domain/nonce replay protection.
Off-chain is trusted for: liveness (the relayer actually posting events) and the honesty of the inputs (what a donation's metadata says). The notary makes inputs tamper-evident; it cannot make them true. IntegrityMonitor narrows the off-chain trust by cross-checking roots.
