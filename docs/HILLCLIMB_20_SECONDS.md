# Launch-to-verification optimization, 2 November 2026

Target: **20,000 ms from the sender's app-launch request to its validated, durably saved MessageBox acceptance receipt**, excluding only the evidenced Pay-review interval. This matches the Android comparison supplied on 2 November: app launch → saved sender receipt. Build/install, recorder startup and receiver configuration preflight happen before sender launch. ME is already registered, unlocked and permissioned; draft/contact entry is scripted. Cold/warm claims must state which app processes were restarted.

Recipient retrieval, exact plaintext comparison and retention are measured separately in `end-to-end-timing.json`. They remain required checks for a complete two-way test, but are not part of the 20-second sender target. A missing sender receipt cannot satisfy that target, even if recipient verification proves delivery. Only the visible Pay button → matching sender-wallet review approval interval is subtracted. Missing launch, receipt or review evidence makes the primary metric unavailable; unknown delay is never counted as zero. Older review events without an ID require exactly one matching sender review opened within the preceding second.

Reports before 2.6.1 used the stricter recipient-retention endpoint under the same filename. Those original reports are preserved. Offline recalculation of the completed live run has separate `sender-target-timing-v2.json` and `end-to-end-timing-v2.json` files; this is a definition correction, not a new run or performance gain.

| Comparable endpoint, excluding Pay review | Android warm | Android cold | Latest completed iOS production run |
|---|---:|---:|---:|
| Launch → validated saved sender receipt | 13.825 s | 17.631 s | 24.686 s |
| Launch → recipient plaintext retained | 22.155 s | 22.141 s | 33.304 s |

The Android messages were composed at 12:07:56 and 12:11:26 UTC. The iOS message was composed at 01:38:00 UTC using an earlier candidate, with ME already unlocked. This is not a matched warm/cold experiment and does not establish current-candidate performance.

## Recorded iterations

| Candidate | Environment | Adjusted launch → recipient retained | Outcome |
|---|---|---:|---|
| Baseline | Disposable SDK wallet + authenticated MessageBox fixture | 20.761 s | Synthetic baseline |
| Reduced trace fsyncs + identity-error handling | Same fixture | 20.657 s | No meaningful timing gain |
| Exact-ID transport lookup | Same single-message fixture | 20.780 s | No gain with one entry; avoids unrelated historical decryptions |
| Combined exact retrieval + decryption | Same fixture | 18.497 s | Synthetic end-to-end result |
| Repeat | Same fixture | 18.942 s | Synthetic end-to-end result |
| Repeat | Same fixture | 18.559 s | Synthetic end-to-end result |
| First live optimized send | Primary iOS → peer iOS, production ME/MessageBox | 33.304 s | Exact plaintext retained; sender receipt confirmed |
| Overlap candidate | Production, composed 02:02:41.788 UTC | Unavailable | Review expired without payment |
| Repeat overlap candidate | Production, composed 02:18:28.451 UTC | Unavailable | Review expired without payment; launch to visible Pay was 30.625 s |

The sub-20-second results are recorded synthetic self-sends, not a production timing claim. The production target remains open. The completed live send took 28.262 s to the sender receipt, less 3.576 s of evidenced Pay-button wait = **24.686 s**, 4.686 s above the sender target. Recipient retention took 36.880 s wall time, or 33.304 s after that same deduction. Its slow spans included server authentication (4.749 s), submission (5.143 s), and first wallet identity retrieval (3.872 s).

## Changes

- A targeted `find`/`verify` inbox operation avoids decrypting unrelated notifications, retains bounded authenticated pagination, and preserves wallet-profile/server-identity checks. `verify` checkpoints the exact encrypted envelope before opening it in the same engine/wallet session. Native authorization rejects unrelated/duplicate IDs, decryption before the checkpoint, spending and acknowledgement through this mode.
- Deriving a Crypton identity must succeed before attempting local decryption. A denied/failed derivation no longer masquerades as a legacy root-envelope failure and requests a broader permission.
- The wallet page wakes its single polling loop immediately after result acknowledgement. It retains single dispatch, page ownership and foreground/payment guards.
- Progress evidence is appended immediately; terminal stages synchronize it. Payment/outbox persistence is unchanged.
- Timing reports bind the human-wait interval to the sender device and review ID and retain live review diagnostics before the bounded wallet log can rotate.
- Historical overlap experiments started recipient verification after a durable payment and exact message ID. The current runner instead waits for the validated saved sender receipt, then starts the receiver clip before launch/refresh. Receiver setup has a separate short clip and diagnostics stay continuous. A missing-receipt recovery check is separately labeled. These changes affect end-to-end sequencing, not the sender receipt endpoint; see the [cold/warm definitions and recording policy](SCRIPTED_SEND_RUNS.md#coldwarm-definitions-and-receive-video-boundaries).
- A simulator-only `recover-review` role uses the ordinary saved-delivery history and refusal recovery methods. It requires an exact delivery/sender, a definite `notCommitted` refusal, fresh empty same-wallet history, and absence of every payment result before returning the record to DRAFT. It has no send claim and invokes no sending method. Both expired reviews were resolved this way with MP4 evidence; uncertain payments remain blocked.

## Companion ME work and startup regression

ME's resume hook can retain the exact authenticated/verified Crypton page instead of replacing its browser route. A newly verified capability can navigate the existing tab without replacing the browser/runtime. Cached read-only results include wallet runtime identity, so a wallet switch cannot reuse another wallet's identity/plaintext. Stale page callbacks cannot return from a newer page.

A read-only prefetch of the six wallet-bundled manifest scopes overlaps permission-record lookup latency. It uses the ordinary Toolbox token validation/cache path, grants nothing, and preserves the 30-second cache bounds, expiry, account-manager isolation and revocation revisions. The 02:18 run exposed a prefetch cache-key mismatch: native handoff initially supplied one origin while ordinary Toolbox lookups also include historical variants. Build 214 uses `prepareOriginator` for the same lookup list; this avoids warming a different key. Authentication/revocation tests pass. A new paid run is still required to quantify the improvement.

The first full-native ME 211 rebuild regressed saved-wallet startup, producing “Wallet Is Still Getting Ready” on both simulators. Its linker signing identifier initially differed from the installed app; matching it did not solve readiness. Restoring the known ME 210 native package restored startup. Compatible JavaScript-only updates on that preserved native runtime passed existing-wallet read-only verification as 211, 212 and 214, without registration, recovery or data reset. The full-native rebuild's exact readiness cause remains unresolved; do not treat that failed artifact as releasable. Installed ME 214 uses the proven native 210 runtime with the current compatible JavaScript bundle, matching signing identifier and empty simulator entitlements. Its recorded receiver-only check retrieved, decrypted and retained the already-delivered message composed 00:11:57 UTC, without a new send/payment. All comparisons/installations/rechecks have private MP4 evidence.

## Validation so far

Twenty host contracts, exact shipped-engine cryptographic/interoperability tests, targeted inbox tests and six page-bridge regressions pass. Recorded native regressions cover targeted checkpoint authorization, refusal/history recovery, lost-command page ownership, foreground gating and authenticated sending. Companion ME TypeScript, native-origin/resume policy, navigation, bridge protocol and authenticated permission-cache/revocation tests pass. An inventory concurrency assertion now uses a bounded proof-start gate instead of assuming all crypto finishes within 100 ms; authorization comparisons are unchanged. Fixtures made no live payments.

Private local evidence includes run manifests, MP4s, native HTTP/wallet/checkpoint spans, exact review diagnostics and target reports. These remain ignored under `.recordings`; no message text, wallet data or recordings are included in repository commits. The next paid run requires the user's one-time Pay click and must not start unattended: reviews expire after two minutes.

## Recovery rendering and temporary-build cleanup

ME 218 renders local-page recovery instructions directly in WebView's error renderer, independent of transient browser load state. Its full-page layout was visually verified. Valid native return capabilities remain subject to current-tab and pending-prompt checks; expired or unknown local pages offer app-switcher/system-back instructions without reloading wallet requests. The source is preserved on companion branch `codex/crypton-wallet-usability`, commit `719f8c7`.

The next run, composed 10:36:49.668 UTC, was cancelled before payment. Its native DRAFT journal confirmed payment was never requested. ME's startup diagnostics showed storage `makeAvailable` timeouts and authentication connection failures. Host HTTPS probes reached both public services, but successful simulator wallet authentication remains unresolved; no new production timing result was obtained.

At the user's request, 24 temporary ME build/checkouts/result directories and 188 archived duplicate logs were removed. Directory allocation totalled 42.245 GiB; measured free space increased by 37.202 GiB to 48.799 GiB. A private diagnostic bundle of approximately 369 MiB retains source revisions, the older uncommitted native patch, lockfiles, build/test logs, test results and compressed native-210/candidate-218 simulator packages. Relevant MP4 evidence and installed wallet containers were preserved. The temporary worktrees were removed through Git; source branches remain in the main repository and the current fix is pushed. Build dependencies can be recreated when needed rather than retained as large temporary trees.

## 2.6.1: foreground networking, bounded runs and CPU gates

Authentication and fee-quote HTTP now use the same explicit Crypton foreground boundary as submission and inbox requests. Authorization still precedes networking; a completed wallet callback alone cannot start HTTP until Crypton is active. Separate foreground and HTTP spans show where time is spent. This closes a reproduced gap in the guard, but adds handoffs and needs fresh production measurement. [Crypton issue #2](https://github.com/p2ppsr/crypton-ios/issues/2) retains the intermittent failure evidence; its exact process/lifecycle cause is not yet established.

A host deadline or interruption now stops only the scripted Crypton process before ending capture. It does not stop ME, reverse an already-issued wallet operation, clear journals or retry Send/payment. Fixed lifecycle events distinguish model creation and scene transitions without message content, keys or capabilities.

Every run checks CPU headroom before building and again immediately before sender launch. Three consecutive interval samples must each have at least 50% idle CPU, with 1-minute load no greater than the logical CPU count. The initial since-boot CPU average is discarded. The controller waits up to 30 seconds per gate by default (`--cpu-wait 0..300`), records every sample, and reports `deferred_cpu_busy` if the gate fails. Sampling failure also blocks launch. Recipient checks following a paid send are allowed to finish without another gate. These thresholds are a local timing-test policy, not a claim that CPU alone determines latency.

Validation: 24 host contracts and four recorded native/SDK regressions pass. Native tests cover actual foreground state at authentication, quote and submission, cancellation, fresh-nonce quote retry and one payment. A recorded production-wallet read-only check retrieved, decrypted and retained the previously delivered 00:11:57 UTC message at 12:37:56 UTC, without a send or payment. Two subsequent new-send attempts were deferred by CPU gates; they are not timing results. A fresh paid receipt measurement is still required.

Saved-wallet startup recovered on both simulators after restarting ME, without resetting wallet data. Diagnostics show exhausted storage-initialization attempts were not restarted by the UI's Try again action. [Companion ME issue #82](https://github.com/p2ppsr/metanet-explorer-mobile/issues/82) records that evidence. The underlying initial storage connection failure and the earlier full-native rebuild regression remain unproven causes, and are not conflated.
