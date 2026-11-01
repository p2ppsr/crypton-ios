# Recording Crypton test runs

Record every iOS Crypton / ME UI run from before the first app interaction until the final result or error. Keep the recording running during permission review, user payment approval, app switching and saved-payment recovery. A recording started late is a partial record; note the missing beginning rather than describing it as a complete run.

## Manual simulator runs

Identify the intended simulator with `xcrun simctl list devices booted`, then start:

```sh
python3 scripts/record-ios-run.py --device <simulator-UUID> --label <run-name>
```

Use a persistent terminal session. Wait for `"recording": "started"` before interacting with the app. Stop that session with Control-C and wait for `"recording": "complete"`. The controller forwards SIGINT to the recorder, waits for it to flush, and verifies the final MP4. It requires Xcode command-line tools, Python 3, FFmpeg and FFprobe.

Each private `.recordings/<UTC-time>-<label>-<unique-id>/` directory contains:

- `screen.mp4`: H.264 video in an actual MP4 container, with a fast-start index.
- `capture.mov`: the unchanged simulator capture, retained for diagnosis.
- `run.json`: device UUID, UTC times, checkout revision/dirty flag, capture outcome and media details.
- `recorder.log`: capture and remux diagnostics.

Add short timestamped notes to that directory when an unexpected error or recovery occurs. App privacy protections remain enabled. The recording captures the selected simulator, not the recipient’s physical phone or the Mac desktop.

`simctl recordVideo` produces QuickTime even if the filename ends in `.mp4`. The controller records `.mov`, then copies its video stream into MP4 without re-encoding. It checks that a positive-duration video stream exists before reporting completion. Failed or partial evidence is retained and reported as a failure.

## Automated runs

`bash scripts/test-ios.sh ...` starts recording the dedicated `Crypton-iOS-Test` device before fixture setup and app launch. Recording is required: a startup/finalization failure fails the run. Tests never switch to the funded simulator just because it is booted.

The runner retains the video on test failure as well as success, writes `testExitCode` into `run.json`, and saves console output as `run.log` plus Xcode output as `xcodebuild.log`. Set `CRYPTON_RECORDING_LABEL` to identify a scenario. Result bundles remain controlled by `CRYPTON_RESULT_BUNDLE`.

## Storage

Recordings and notes are private local evidence. `.recordings/` is excluded from Git; do not publish wallet recordings or attach them to a public issue without the operator’s approval. Finalize recordings before sharing a local playback link.
