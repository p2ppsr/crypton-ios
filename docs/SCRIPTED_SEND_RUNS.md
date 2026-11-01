# One-command recorded sends

From this checkout on the configured Mac:

```sh
./scripts/send-message.py "The text to send"
```

The default direction is primary iOS → peer iOS. Add `--reverse` for peer → primary. A UTC composition timestamp and a unique run ID are appended to the supplied text when the request body is created, before building/launching the apps. The same run ID appears in the message, console and reports; the later UI text-entry time is recorded separately. Use shell quoting as usual; the runner passes text as data, never as shell code.

The command builds the `CryptonSendRun` scheme, starts private MP4 recording on both selected simulators, installs the app/test runner in place, verifies normal-message settings, composes the text, and taps Send once. It waits for ME's final payment review without switching away or clicking Pay/Allow. When Pay appears it brings Simulator forward and prints the sender device, composition timestamp and run ID. Review the full wallet total and click **Pay once** yourself; leave **Allow up to** unchanged. ME's own review deadline still applies. New permission prompts also require operator review; the script never grants access.

After server acceptance, the command refreshes the other simulator's inbox, selects the **exact accepted MessageBox ID**, decrypts it, compares the full plaintext, and checks that the encrypted message remains available after leaving and reopening it. If the first inbox read is empty, it retries completed reads up to ten times within the phase deadline, without making a payment or switching away from an open wallet request. The script reports success only after explicit completion events; a green but empty XCTest run does not count.

The UI sequence and checks are repeatable. Wallet approval time, storage/network responses and server delivery remain external inputs. This is not a promise that every run will succeed or take the same time.

## Machine configuration

This Mac's primary/peer profiles are saved privately in `.recordings/send-profiles.json`. The file contains simulator UUIDs, names and public receiving/delivery keys. It is excluded from Git. To configure another machine, copy `scripts/send-profiles.example.json` there, fill in both devices and both public keys from each Crypton contact card, and use `--config <path>` if needed. Production runs require two distinct available iOS simulators with independently registered ME wallets and the required Crypton permissions already reviewed.

Both simulators must use **Metanet Explorer**, Crypton v2, **Sent: remove after confirmed delivery = off**, and **Received: decrypt once and remove = off**. The script checks these settings and fails without changing them. Existing wallets, grants, contacts and saved outbox/inbox data are preserved; the command never uninstalls or resets applications. It installs the checked-out Crypton build, so make sure the checkout is the version you intend to test.

Xcode, Python 3, Node (fixture mode only), FFmpeg and FFprobe are required. `DEVELOPER_DIR` overrides the Xcode selection; on this Mac the runner otherwise selects the installed Xcode 26.6. UI automation uses Xcode/XCTest, not coordinate clicks. The production configuration builds Release; disposable fixtures use Debug and the existing isolated fixture stores.

```sh
# Validate profiles without launching an app or touching a wallet.
./scripts/send-message.py "Profile check" --dry-run

# Test the whole command without a live wallet or any real spending.
./scripts/send-message.py 'Unicode test: café 🌍 "quoted"' \
  --fixture --sdk-root /tmp/crypton-ux251-fixtures

# Host-only tests for literal parameter handling and replay protection.
python3 scripts/test-send-command.py
```

Fixture mode is restricted to the explicitly named `Crypton-iOS-Test` simulator and uses an ephemeral SDK wallet and loopback MessageBox service. It performs a retained self-send through the same UI harness. A fixture pass does not establish a production two-wallet send or test human ME payment approval.

## Evidence and timings

Each command creates `.recordings/<UTC>-send-<unique>/` containing:

- `request.json`: exact text, timestamp and run configuration; private local data.
- `events.jsonl`: UTC and monotonic UI-stage timestamps.
- `timings.json` and `timing-report.txt`: observed stage intervals and a readable timeline.
- Per-device `*.pipeline.jsonl`: native HTTP, wallet and checkpoint spans, without payloads or keys.
- `wallet-review-events.json`: scoped ME approval/expiry/finalization diagnostics when existing diagnostics consent makes them available. The command does not enable diagnostics or export unrelated fields.
- Per-device recording subdirectories: finalized H.264 `screen.mp4`, original capture and metadata.
- Build/test logs, per-phase xcresults and `result.json` with the exact outcome and accepted message ID.

UI completion times are sampled observations. Use native spans and ME diagnostics for exact operation boundaries. Preparation, cold application launches, payment review and verification are separate events; build time is not MessageBox latency. The same run ID correlates both endpoints. Keep all evidence local because recordings, request files and xcresults can contain message text and wallet details.

## Failure and replay behavior

There is one Send attempt per run. A host-side exclusive claim survives test-runner reinstalls; a second runner cannot claim the same send. An additional runner-local marker blocks ordinary test recovery replays. A lost claim response fails closed. No test failure automatically repeats a payment, resets a journal or requests another quote.

An interrupted production send is marked `needs_recovery`; another command from that sender is blocked while that outcome remains unresolved. Inspect the named run and Crypton's saved outbox using the normal recovery controls. Empty wallet history alone is not proof that a payment failed. A confirmed accepted message whose receiving check failed remains `accepted`, rather than being misreported as unsent. Receiver-only resumption and automated resolution of an uncertain payment are not implemented by this command.

Ctrl-C and SIGTERM stop the test and finalize its recordings. A failed recorder prevents a successful result from being reported. Host deadlines bound stuck tests; they do not extend ME's payment-review deadline or bypass its approval checks.

## Verification

Recorded disposable runs passed with quoted text, accented characters and emoji, including exact plaintext matching and retained-message reopening. An additional recorded run deliberately returned an empty first inbox page; its read-only retry then received, decrypted and retained the message without another Send. Host tests cover literal parameter encoding, selecting only the opt-in UI test, refusing events from another run, and single-use claims (including a bad token and duplicate claims). The Release automation scheme builds successfully. The initial setup failures and their finalized recordings are retained privately alongside the successful runs.

A two-wallet production run using this command, including its human Pay handoff, remains to be performed. Previous manually driven production sends are separate evidence.
