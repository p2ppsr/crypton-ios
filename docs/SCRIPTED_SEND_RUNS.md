# One-command recorded sends

```sh
/Users/bob/crypton-ios/scripts/send-message.py "The text to send"
```

The default direction is primary iOS → peer iOS. Add `--reverse` for peer → primary. The command appends a UTC composition timestamp and a unique run ID when it creates the request body, before building/launching. That same ID appears in the message, console and reports. Text is passed as JSON data, never shell code.

## Execution

Version 2.6.1 uses a **simulator-only native driver** that calls Crypton's ordinary `AppModel` actions: choose the contact, compose, Send with MessageBox, refresh the inbox, open/decrypt, and close/reopen the retained copy. The real encryption, native ME bridge, grouped permissions, fresh quote comparison, payment journal and MessageBox validation all remain in those actions. The driver does not use XCTest taps or read application foreground states to decide whether an operation finished. It awaits each native action's actual completion.

The command builds Release, installs Crypton in place, and records each simulator around its own activity. The receiver setup check has a separate short clip. Its receive clip starts after the sender has a validated, saved acceptance receipt and before receiver launch/refresh; it does not include sender preparation or payment wait. Diagnostic logs remain continuous for both devices. It checks ME/v2/retained-message settings without changing them, then makes one Send attempt. Review the full wallet total and click **Pay once** yourself in ME; leave **Allow up to** unchanged. The command never clicks Pay/Allow, grants access, changes wallet policy or extends ME's review deadline. It foregrounds Simulator and prints the sender, composition time and run ID when review is requested. Exact Pay-visible timing comes from ME's existing spending-modal diagnostics when available; the earlier native review-request event is labeled separately.

After acceptance, the command refreshes the peer, selects the exact MessageBox ID, decrypts and compares the complete plaintext, then verifies its read encrypted copy remains available after closing/reopening. Completed empty reads can be retried; payments cannot. Network responses, wallet decisions and fees remain external inputs, so repeatable execution does not guarantee identical outcomes or durations.

The native control entry point is compiled only for the iOS simulator. It has no URL handler and cannot be invoked through a shared message or web page. A local `simctl` launch selects a private plan by UUID. The app consumes/deletes the transient plan; the controller also cleans it up on launch failure. The original request remains in the user's private recording directory. No wallet credential is placed in a plan. A single-use authenticated host claim prevents replaying Send after process/runner recovery. Verification plans have no sending capability.

## Configuration

This Mac's public contact keys and simulator UUIDs are in the ignored `.recordings/send-profiles.json`. On another Mac, copy `scripts/send-profiles.example.json`, fill both public keys from each Crypton contact card and both UUIDs, and pass `--config <path>` if needed. Production runs require two distinct iOS simulators with independently registered ME wallets and already-reviewed Crypton permissions.

Both profiles must use ME, Crypton v2, and retained sent/received copies. The command preserves wallet data, grants, contacts and journals; it never uninstalls/resets an app. It installs the checked-out Crypton build, so use the checkout you intend to test. Xcode, Python 3, FFmpeg and FFprobe are required; fixture mode also needs Node and the pinned fixture dependencies. `DEVELOPER_DIR` overrides Xcode selection; this Mac otherwise uses its installed Xcode 26.6.

```sh
./scripts/send-message.py "Profile check" --dry-run
./scripts/send-message.py 'Fixture: café 🌍 "quoted"' --fixture --sdk-root /tmp/crypton-ux251-fixtures
python3 scripts/test-send-command.py
```

Fixtures use only `Crypton-iOS-Test`, ephemeral SDK wallets and the loopback MessageBox service. They are retained self-sends and spend no live funds. A fixture pass does not prove a new two-wallet production payment.

## Verification-only recovery

For a known message that was already paid/submitted, verify the receiver without sending again:

```sh
./scripts/send-message.py --verify-run <original-run-directory> --message-id <exact-MessageBox-ID>
```

This mode reads the original text/hash/run ID, launches only the receiving simulator and performs refresh/decryption/retention checks. It rejects a sending phase and does not mint a send claim. Success marks the controller's original record `recipient_verified` with a link to the verification evidence. It does **not** manufacture a sender acceptance receipt or change a wallet/outbox journal. An outbox still marked SUBMITTING retains its saved payment and missing-receipt evidence.

A settled native failure whose own validated DRAFT/QUOTED journal has no payment-request, wallet-result/refusal, payment, submission or receipt markers is reported as `failed_before_payment`. A tapped Send or consumed host claim alone does not mean payment started. Missing/stale journals, unfinished operations, payment markers or unknown states cannot supply this proof.

An unresolved interrupted production send remains `needs_recovery`, blocking another send from that profile. Empty wallet history alone does not prove failure. Inspect the original run and saved outbox before any further payment. Ctrl-C/SIGTERM and host phase deadlines stop the scripted Crypton process before finalizing recordings. They do not stop ME, cancel or reverse an already-issued wallet operation, clear journals or permit a second payment. An interrupted capture is not proof of the eventual wallet outcome.

## Evidence

Each `.recordings/<UTC>-send-<unique>/` contains the private original request, structured UTC/monotonic events, result JSON, timing JSON/readable report, per-device native pipeline logs, `recording-events.jsonl` readiness timestamps, and purpose-labeled H.264 MP4 subdirectories (`send`, `receiver-setup`, `receive`). Scoped ME review events are exported if existing diagnostics consent makes them available; the command does not enable diagnostics or export unrelated wallet fields. Recordings/request files can contain message text and wallet details and remain outside Git.

Native action timestamps and ME diagnostic timestamps are distinct from controller observation time. Build/setup time is not MessageBox latency. Recorder or timing-capture failure prevents a successful evidence result. Native simulator event files contain stage information and hashes, not plaintext; the transient request file is consumed/deleted.

## Recorded incident and verification

The first live UI-driver run composed **2026-11-01 20:45:02 UTC**, run `1fff3335-716e-4032-a588-74f3c1886d1d`, reached Pay after 16.397 seconds. ME approved at 20:46:08.974 UTC and finalized signing at 20:46:10.324 UTC. XCTest then read the already-disappearing Pay button and failed. The paid transaction was saved and submission started, but no acceptance receipt reached the sender journal.

The retained recordings/diagnostics establish a script failure after approval. Further UI-driver checks exposed cached-row taps during refresh and unreliable cross-app state/hit points. The old XCTest path is retained only for regression investigation; the command now uses native action completion.

The native verification-only run matched that original plaintext on the peer at **21:25:19 UTC**, confirmed retention at **21:25:20 UTC**, and finalized its MP4. No second send/payment was made. The sender's SUBMITTING journal was preserved. A complete disposable native-driver send/receive/decrypt/retention run also passed with accented characters, emoji and quotes. Host tests cover literal data, run identity, replay denial, verification-only capability restrictions and transient-plan cleanup. A fresh paid production send with the native driver remains a separate test requiring human wallet approval.


## 2.5.6: unpaid quote timeout

Run `4885508a-4e76-43da-8fbf-38945815c1d0`, composed **2026-11-01 23:07:15 UTC**, completed wallet authentication but timed out during the first authenticated `/permissions/quote` GET after **68.137 seconds**. Its validated journal remained DRAFT, with no payment request/result, payment, submission or receipt. The controller incorrectly classified the consumed Send claim as requiring payment recovery. Scoped journal evidence corrected only that controller result to `failed_before_payment`; the native journal and original error were preserved. A later unauthenticated connectivity probe returned HTTP 401 promptly; it does not establish the original network/server cause.

Quote GET requests now have an explicit 15-second network inactivity timeout and one additional attempt for typed native timeout, connection-loss or connection-refused errors. Each attempt passes through AuthFetch again to obtain a fresh signed request nonce. HTTP rejections, invalid authentication, changed fees and server-identity validation are not retried by this policy. Wallet approval waits retain their existing deadlines. No wallet payment or message submission is automatically repeated. The 15-second timeout is not an end-to-end Send deadline: wallet processing, authentication and response validation take additional time.

Validation: four recorded simulator regressions passed, including a real stalled HTTP quote followed by a successful fresh-nonce retry and one synthetic payment, two actual timeouts with zero payment attempts, HTTP 503 without retry, changed-fee rejection, and conservative journal-marker checks. Twelve host contracts passed. A full recorded CLI fixture with `CRYPTON_FIXTURE_TIMEOUT_QUOTES=2` stopped after two stalled reads as `failed_before_payment`; its DRAFT proof and finalized MP4 were verified. The Release build passed and 2.5.6 (15) was installed in place on both live simulators. No live send, grant or spending action was made during this investigation. The original production timeout's underlying cause remains unconfirmed.

To reproduce the complete unpaid failure on the disposable simulator (expected exit code 1):

```sh
CRYPTON_FIXTURE_TIMEOUT_QUOTES=2 ./scripts/send-message.py 'Retained encrypted quote timeout test' --fixture --sdk-root /tmp/crypton-ux251-fixtures
```


## 2.5.7: recover a lost command response without returning early

Run `216530e5-b51c-4b43-9a00-f1b9e5eac5c2`, composed **2026-11-01 23:25:50 UTC**, stalled before authentication and fee lookup. Crypton started `createHmac` at **23:26:12.413 UTC**, but the scoped ME snapshot contained no HMAC dispatch. ME had just recorded a local fetch failure after 4,018 ms and a bridge return-status response. The controller stopped at **23:30:58.932 UTC** while the native request remained pending until **23:31:16.078 UTC**. Its subsequently settled journal was DRAFT with all payment markers absent. Only the controller classification was corrected; no payment or native journal was reset.

The bridge had two reproduced flaws: an idle `/next` fetch error requested an automatic app return while another command could be queued, and native `/next` consumed a command before its HTTP response was received. A lost response could therefore strand an invocation. The existing diagnostics do not establish the exact command-offer/visibility order in that production incident.

Each page now has a random owner ID. Native retrieval reserves the command to that page and permits that same page to retrieve the same UUID after a lost response. Reloaded/other pages cannot retrieve an issued command, and the page's UUID set still permits only one wallet invocation. Idle read errors reconnect on the existing ME page instead of switching apps. An in-progress recovery return pauses retrieval/dispatch until ME becomes visible again. Payment result saves remain idempotent, and payment/submission retries remain protected.

A scripted phase timeout now cancels its native engine/wallet task and waits briefly for settlement before emitting its failure record. A settled DRAFT can provide affirmative unpaid proof; pending or payment-marked operations remain protected. Cancellation cannot prove that an already-dispatched wallet payment failed. New fixed `bridge.command.<method>.queued/offered/recovered`, `bridge.result.<method>.saved` and bridge-return stages appear in the existing pipeline capture without capabilities, arguments, identities or amounts.

Validation: five JavaScript bridge regressions and four recorded native/SDK tests passed, including lost-command ownership, lost result acknowledgements, sequential calls and a complete disposable send. A full recorded CLI run with two stalled quotes and `--timeout 30` canceled and settled as `failed_before_payment`, with its MP4 finalized. Release 2.5.7 (16) builds successfully. The investigation's brief video gap after the original controller timeout is recorded in the private evidence notes; it is not claimed as uninterrupted capture. Fresh production success with the installed ME wallet remains unverified.


## 2.5.8: check the recipient after a lost submission response

The normal message composed **2026-11-01 23:49:01.832 UTC**, run `f528a365-7c5a-4da8-8d3d-7da3c8bc85d4`, reached Pay at **23:49:29.863 UTC** (21.375 seconds after Send). Its payment was saved at **23:49:33.788 UTC**, and `/sendMessage` started at **23:49:34.169 UTC**. No completion was logged until Crypton was foregrounded at **23:52:55 UTC**, when the HTTP timeout was processed. This is consistent with suspension delaying native response handling; it does not prove the original server/network timeout's cause.

The sender journal retained its payment and SUBMITTING state without an acceptance receipt. A separate recorded verification-only run found the exact message on Peer iOS, matched the full decrypted text at **23:54:02.693 UTC** and confirmed retention at **23:54:02.877 UTC**. No resend or second payment was made. The original controller result is `recipient_verified`; the native SUBMITTING record remains unchanged.

The command now performs that recipient check automatically when a settled native failure supplies validated SUBMITTING state, a saved payment and the exact message ID from its own newly created journal. It never retries Send, payment or submission. If the peer returns the exact plaintext and retains its copy, the result is `recipient_verified`, with `sender_receipt: unconfirmed` and the original `sender_error`. It does not manufacture a server receipt or mark the native outbox SENT. If verification fails, `needs_recovery` continues to block another paid run. Unpaid failures, payment-review uncertainty and missing/malformed native evidence cannot trigger this fallback.

Sixteen controller contracts pass. A complete recorded disposable run deliberately dropped the server's acceptance response after storing the message: the native sender failed with its paid SUBMITTING record, then the same command refreshed, decrypted and retained the exact message. It exited successfully as `recipient_verified`. Pipeline evidence confirms exactly one createAction call and one `/sendMessage` attempt; its MP4 finalized. Release 2.5.8 (17) builds successfully. This improves outcome verification after a missing receipt; it does not claim to eliminate the underlying HTTP timeout or the remaining iOS background-execution limitation.


## 2.5.9: explicit foreground handoff for submission and inbox networking

Run `44c3f344-fad2-4c16-9178-621d45df7d83`, composed **2026-11-02 00:11:57.173 UTC**, reached Pay at **00:12:26.870 UTC** and saved payment at **00:12:31.542 UTC**. Its `/sendMessage` request began at **00:12:31.744 UTC**, but Crypton stopped emitting stage events while ME remained foregrounded. The controller reached its phase deadline without receiving a native failure event, so 2.5.8's automatic fallback could not begin. After the existing app was foregrounded, its native operation settled/canceled with a saved payment and SUBMITTING journal. A recorded verification-only read matched the exact message on Peer iOS at **00:20:28.359 UTC** and confirmed retention at **00:20:28.980 UTC**. No additional send or payment was performed.

Before native `/sendMessage`, `/listMessages` and `/acknowledgeMessage` work, Crypton now explicitly asks the idle ME page to return. The native bridge waits for Crypton's actual active lifecycle event before starting HTTP; the return callback alone is insufficient. Outstanding wallet invocations block this request, and ME's existing idle/prompt checks still govern its app return. Cancellation clears the wait so a late lifecycle event cannot start network work. Fixed `bridge.network.foreground.requested/finished` stages capture the boundary.

Fee preparation and wallet review remain in the existing session. Submission returns to Crypton; ME can reopen to verify the authenticated server response. This adds a deliberate handoff after payment. It does not guarantee that a remote server will reply or remove the existing missing-receipt verification fallback. Original paid journals remain unchanged.

The two native lifecycle/cancellation tests passed. The first integration run exposed the fixture's periodic synthetic Return-link clicks continuing after a successful handoff; both that failed recording and the corrected fixture's recording are retained. Removing those repeated clicks models the shipped page's native return path. All three corrected integration cases pass: contact send, composer self-send and saved-payment recovery without a second payment. All six JavaScript bridge regressions pass. The first read-only installed-ME check was canceled during ME backgrounding before network handoff; its recording is retained as an unresolved startup-interruption observation, not counted as a successful test.


The second recorded installed-ME read verified the new boundary: foreground was requested at **00:30:47.476 UTC**, Crypton became active at **00:30:48.064 UTC**, and `/listMessages` ran from **00:30:48.064 to 00:30:52.157 UTC**. The exact message was found. Its subsequent extra decryption entered the Crypton root-fallback wallet permission prompt. That is distinct from the already-approved self-identity scope; the prompt was initially mislabeled during investigation, corrected, and the extra recheck stopped without granting it. The message's earlier successful decryption/retention at 00:20:28 remains the delivery evidence. This fallback permission/local-derived-decryption issue remains unverified and is not counted as a complete successful recheck. No additional paid submission was made to validate 2.5.9's live receipt path.

## 2.6.1: timing boundaries and host-load guard

`target-timing.json` measures **sender launch → validated, saved sender receipt**, with a 20-second target, excluding only the evidenced visible-Pay → matching sender review approval interval. This matches the Android sender comparison. `end-to-end-timing.json` separately measures launch → exact recipient plaintext retained. A missing receipt makes the sender target unavailable even when recipient verification succeeds. Original older reports using the recipient endpoint are preserved; see [measurement definitions and historical comparisons](HILLCLIMB_20_SECONDS.md).

Before build and immediately before sender launch, the controller requires three interval samples with at least 50% idle CPU and 1-minute load no higher than the logical CPU count. It discards `top`'s initial since-boot average. It waits up to 30 seconds per gate, records all observations in `cpu-load.json`, and exits as `deferred_cpu_busy` without starting Send if the machine remains busy or cannot be sampled. Use `--cpu-wait 120` to wait up to two minutes per gate; allowed values are 0–300 and none bypass the check. A paid run's recipient verification continues without another CPU gate. `python3 scripts/check-cpu.py` performs only a read-only host-load check.

All authorized native HTTP, including MessageBox authentication and quote requests, now explicitly waits for foreground Crypton after the preceding wallet result is saved. Separate foreground/HTTP spans and content-free lifecycle events are captured in native logs. The host stops only its scripted Crypton process on failed or interrupted phases so it cannot silently continue after recordings end; an already-dispatched ME operation may still finish, and unresolved payment records remain blocked. No automatic payment or Send retry was added.

Recorded native regressions and a production-wallet receiver-only check passed. A fresh paid run is still needed to establish the new sender timing. CPU-deferred attempts are not measurements.

## Cold/warm definitions and receive-video boundaries

- **Warm Crypton:** its existing process, app model and crypto engine are already running and reused for the measured send.
- **Cold Crypton:** its process is terminated before launch, so the app model and crypto engine are created afresh. Saved contacts, settings, grants, encrypted records and journals remain intact. This does not mean a simulator reboot or wallet reset.
- **ME readiness:** ME should already be unlocked and ready for either comparison. The controller leaves the ME process alone; its not being restarted does not itself prove readiness or warm caches.

The current command uses `simctl launch --terminate-running-process` for each Crypton phase and records `crypton_launch_mode: cold_process_restart` in `result.json`. It does not currently implement a warm send mode. Existing command timings must therefore be described as cold Crypton launches with ME left running, not as a matched warm/cold pair.

Normal two-device runs perform receiver setup before Send, finalize that short `receiver-setup` MP4, then leave the receiver video off during sender preparation, payment review and submission. Only native `accepted` evidence—emitted after Crypton validates and saves its sender receipt—allows the `receive` recorder to start. Its first-frame readiness must complete before receiver launch/refresh. A saved payment alone cannot start the receiver. Recipient checking no longer overlaps pending sender submission, so new end-to-end results must not be mixed with historical overlapping runs. Sender receipt timing retains the same endpoint.

If a paid submission finishes with a missing receipt, the existing exact-message recovery check remains available with a distinct `receipt-recovery` video label and an unconfirmed sender receipt. A separately requested read-only recheck uses `verification-only`. Neither is labeled as a successful accepted-send receive clip. One-device disposable fixtures keep their continuous video because sender and receiver are the same screen. Recording startup/finalization failure fails the evidence result; no additional payment is needed to test the gate.

Validation on 2 November: 29 host contracts pass, including no peer video at startup, payment-before-acceptance rejection, receiver setup finalization, recorder failure before receiver launch, and distinct recovery labels. A production-wallet read-only recheck of the message composed 00:11:57 UTC completed at 13:49:04.993 UTC with exact decryption and retention. Its verification MP4's first frame was at 13:48:49.528 UTC, 153 ms before receiver launch, and the finalized 15.967-second file passed FFprobe validation. This verifies actual recorder readiness/finalization without another payment; the normal new-send acceptance gate is covered by host contracts, not a new paid run.
