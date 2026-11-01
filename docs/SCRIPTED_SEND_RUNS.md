# One-command recorded sends

```sh
/Users/bob/crypton-ios/scripts/send-message.py "The text to send"
```

The default direction is primary iOS → peer iOS. Add `--reverse` for peer → primary. The command appends a UTC composition timestamp and a unique run ID when it creates the request body, before building/launching. That same ID appears in the message, console and reports. Text is passed as JSON data, never shell code.

## Execution

Version 2.5.5 uses a **simulator-only native driver** that calls Crypton's ordinary `AppModel` actions: choose the contact, compose, Send with MessageBox, refresh the inbox, open/decrypt, and close/reopen the retained copy. The real encryption, native ME bridge, grouped permissions, fresh quote comparison, payment journal and MessageBox validation all remain in those actions. The driver does not use XCTest taps or read application foreground states to decide whether an operation finished. It awaits each native action's actual completion.

The command builds Release, records both selected simulators, and installs Crypton in place. It checks ME/v2/retained-message settings without changing them, then makes one Send attempt. Review the full wallet total and click **Pay once** yourself in ME; leave **Allow up to** unchanged. The command never clicks Pay/Allow, grants access, changes wallet policy or extends ME's review deadline. It foregrounds Simulator and prints the sender, composition time and run ID when review is requested. Exact Pay-visible timing comes from ME's existing spending-modal diagnostics when available; the earlier native review-request event is labeled separately.

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

An unresolved interrupted production send remains `needs_recovery`, blocking another send from that profile. Empty wallet history alone does not prove failure. Inspect the original run and saved outbox before any further payment. Ctrl-C/SIGTERM stop the controller and finalize recordings; they do not cancel an in-flight wallet operation. An interrupted capture is not proof of the eventual wallet outcome.

## Evidence

Each `.recordings/<UTC>-send-<unique>/` contains the private original request, structured UTC/monotonic events, result JSON, timing JSON/readable report, per-device native pipeline logs and finalized H.264 MP4 subdirectories. Scoped ME review events are exported if existing diagnostics consent makes them available; the command does not enable diagnostics or export unrelated wallet fields. Recordings/request files can contain message text and wallet details and remain outside Git.

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
