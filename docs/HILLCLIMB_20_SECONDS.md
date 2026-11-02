# Launch-to-verification optimization, 2 November 2026

Target: 20,000 ms from the sender's app-launch request until both a sender receipt and verification of the exact plaintext and retained recipient copy. The later completion boundary wins when sender and receiver overlap. Build/install, recorder startup and the receiver configuration preflight happen before sender launch. App initialization, sender work, receiver launch, retrieval, decryption and retention are included. Only the evidenced interval between the visible Pay button and the matching sender-wallet review approval is subtracted. Missing approval/launch/verification evidence produces an unavailable metric; it cannot silently count as zero delay. Older modal diagnostics without an ID require exactly one matching sender review opened within the preceding second. `target-timing.json` also distinguishes fixtures and missing sender receipts; a missing receipt cannot satisfy the target.

## Recorded iterations

| Candidate | Environment | Adjusted total | Outcome |
|---|---|---:|---|
| Baseline | Disposable SDK wallet + authenticated MessageBox fixture | 20.761 s | Above target |
| Reduced trace fsyncs + identity-error handling | Same fixture | 20.657 s | No meaningful timing gain |
| Exact-ID transport lookup | Same single-message fixture | 20.780 s | No gain with one entry; avoids unrelated historical decryptions |
| Combined exact retrieval + decryption | Same fixture | 18.497 s | Below target |
| Repeat | Same fixture | 18.942 s | Below target |
| Repeat | Same fixture | 18.559 s | Below target |
| First live optimized send | Primary iOS → peer iOS, production ME/MessageBox | 33.304 s | Exact plaintext retained; sender receipt confirmed; above target |
| Overlap candidate | Production, composed 02:02:41.788 UTC | Unavailable | Review expired without payment |
| Repeat overlap candidate | Production, composed 02:18:28.451 UTC | Unavailable | Review expired without payment; launch to visible Pay was 30.625 s |

The sub-20-second results are recorded synthetic self-sends, not a production timing claim. The production target remains open. The completed live send took 36.880 s wall time, less 3.576 s of evidenced Pay-button wait = 33.304 s. Its slow spans included server authentication (4.749 s), submission (5.143 s), and first wallet identity retrieval (3.872 s).

## Changes

- A targeted `find`/`verify` inbox operation avoids decrypting unrelated notifications, retains bounded authenticated pagination, and preserves wallet-profile/server-identity checks. `verify` checkpoints the exact encrypted envelope before opening it in the same engine/wallet session. Native authorization rejects unrelated/duplicate IDs, decryption before the checkpoint, spending and acknowledgement through this mode.
- Deriving a Crypton identity must succeed before attempting local decryption. A denied/failed derivation no longer masquerades as a legacy root-envelope failure and requests a broader permission.
- The wallet page wakes its single polling loop immediately after result acknowledgement. It retains single dispatch, page ownership and foreground/payment guards.
- Progress evidence is appended immediately; terminal stages synchronize it. Payment/outbox persistence is unchanged.
- Timing reports bind the human-wait interval to the sender device and review ID and retain live review diagnostics before the bounded wallet log can rotate.
- With two distinct simulators, recipient-only verification starts after native code has durably saved and validated the payment and exact message ID. It cannot initiate a payment. Completion still waits for the sender receipt. Same-device disposable runs remain sequential.
- A simulator-only `recover-review` role uses the ordinary saved-delivery history and refusal recovery methods. It requires an exact delivery/sender, a definite `notCommitted` refusal, fresh empty same-wallet history, and absence of every payment result before returning the record to DRAFT. It has no send claim and invokes no sending method. Both expired reviews were resolved this way with MP4 evidence; uncertain payments remain blocked.

## Companion ME work and startup regression

ME's resume hook can retain the exact authenticated/verified Crypton page instead of replacing its browser route. A newly verified capability can navigate the existing tab without replacing the browser/runtime. Cached read-only results include wallet runtime identity, so a wallet switch cannot reuse another wallet's identity/plaintext. Stale page callbacks cannot return from a newer page.

A read-only prefetch of the six wallet-bundled manifest scopes overlaps permission-record lookup latency. It uses the ordinary Toolbox token validation/cache path, grants nothing, and preserves the 30-second cache bounds, expiry, account-manager isolation and revocation revisions. The 02:18 run exposed a prefetch cache-key mismatch: native handoff initially supplied one origin while ordinary Toolbox lookups also include historical variants. Build 214 uses `prepareOriginator` for the same lookup list; this avoids warming a different key. Authentication/revocation tests pass. A new paid run is still required to quantify the improvement.

The first full-native ME 211 rebuild regressed saved-wallet startup, producing “Wallet Is Still Getting Ready” on both simulators. Its linker signing identifier initially differed from the installed app; matching it did not solve readiness. Restoring the known ME 210 native package restored startup. Compatible JavaScript-only updates on that preserved native runtime passed existing-wallet read-only verification as 211, 212 and 214, without registration, recovery or data reset. The full-native rebuild's exact readiness cause remains unresolved; do not treat that failed artifact as releasable. Installed ME 214 uses the proven native 210 runtime with the current compatible JavaScript bundle, matching signing identifier and empty simulator entitlements. Its recorded receiver-only check retrieved, decrypted and retained the already-delivered message composed 00:11:57 UTC, without a new send/payment. All comparisons/installations/rechecks have private MP4 evidence.

## Validation so far

Twenty host contracts, exact shipped-engine cryptographic/interoperability tests, targeted inbox tests and six page-bridge regressions pass. Recorded native regressions cover targeted checkpoint authorization, refusal/history recovery, lost-command page ownership, foreground gating and authenticated sending. Companion ME TypeScript, native-origin/resume policy, navigation, bridge protocol and authenticated permission-cache/revocation tests pass. An inventory concurrency assertion now uses a bounded proof-start gate instead of assuming all crypto finishes within 100 ms; authorization comparisons are unchanged. Fixtures made no live payments.

Private local evidence includes run manifests, MP4s, native HTTP/wallet/checkpoint spans, exact review diagnostics and target reports. These remain ignored under `.recordings`; no message text, wallet data or recordings are included in repository commits. The next paid run requires the user's one-time Pay click and must not start unattended: reviews expire after two minutes.
