#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
node scripts/test-me-page.cjs
# Run only on a dedicated Crypton device, never the user's currently booted simulator.
CRYPTON_DEVICE_ID="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; print(next((d["udid"] for devices in json.load(sys.stdin)["devices"].values() for d in devices if d["name"] == "Crypton-iOS-Test"), ""))')"
if [ -z "$CRYPTON_DEVICE_ID" ]; then
  CRYPTON_DEVICE_ID="$(xcrun simctl create Crypton-iOS-Test com.apple.CoreSimulator.SimDeviceType.iPhone-16)"
fi
CRYPTON_DEVICE_STATE="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; print(next(d["state"] for devices in json.load(sys.stdin)["devices"].values() for d in devices if d["udid"] == sys.argv[1]))' "$CRYPTON_DEVICE_ID")"
if [ "$CRYPTON_DEVICE_STATE" != "Booted" ]; then xcrun simctl boot "$CRYPTON_DEVICE_ID"; fi
CRYPTON_FIXTURE_PID=""
CRYPTON_MEDIA_DIRECTORY=""
CRYPTON_RECORDER_PID=""
CRYPTON_RUN_DIRECTORY=""
CRYPTON_RECORDING_READY="$(mktemp -t crypton-recording-ready)"
CRYPTON_LOG="$(mktemp -t crypton-fixture)"
cleanup() {
  local test_exit=$?
  trap - EXIT INT TERM
  if [ -n "$CRYPTON_FIXTURE_PID" ]; then kill "$CRYPTON_FIXTURE_PID" 2>/dev/null || true; wait "$CRYPTON_FIXTURE_PID" 2>/dev/null || true; fi
  if [ -n "$CRYPTON_MEDIA_DIRECTORY" ]; then rm -rf "$CRYPTON_MEDIA_DIRECTORY"; fi
  if [ -n "$CRYPTON_RECORDER_PID" ]; then
    kill -INT "$CRYPTON_RECORDER_PID" 2>/dev/null || true
    if wait "$CRYPTON_RECORDER_PID"; then :; elif [ "$test_exit" -eq 0 ]; then test_exit=1; fi
  fi
  if [ -n "$CRYPTON_RUN_DIRECTORY" ]; then
    python3 - "$CRYPTON_RUN_DIRECTORY/run.json" "$test_exit" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]); data=json.loads(p.read_text()); data['testExitCode']=int(sys.argv[2])
p.write_text(json.dumps(data,indent=2)+'\n')
PY
  fi
  rm -f "$CRYPTON_RECORDING_READY"
  rm -f "$CRYPTON_LOG"
  exit "$test_exit"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
xcrun simctl bootstatus "$CRYPTON_DEVICE_ID" -b >/dev/null
python3 scripts/record-ios-run.py --device "$CRYPTON_DEVICE_ID" --label "${CRYPTON_RECORDING_LABEL:-ios-tests}" --ready-file "$CRYPTON_RECORDING_READY" &
CRYPTON_RECORDER_PID=$!
for ((attempt=0; attempt<250; attempt++)); do
  if [ -s "$CRYPTON_RECORDING_READY" ]; then break; fi
  if ! kill -0 "$CRYPTON_RECORDER_PID" 2>/dev/null; then echo 'Recording failed before tests started.' >&2; exit 1; fi
  sleep 0.1
done
if [ ! -s "$CRYPTON_RECORDING_READY" ]; then echo 'Recording did not become ready; tests were not started.' >&2; exit 1; fi
CRYPTON_RUN_DIRECTORY="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["runDirectory"])' "$CRYPTON_RECORDING_READY")"
exec > >(tee "$CRYPTON_RUN_DIRECTORY/run.log") 2>&1
if [ -n "${CRYPTON_SDK_ROOT:-}" ]; then
  xcrun simctl bootstatus "$CRYPTON_DEVICE_ID" -b >/dev/null
  CRYPTON_MEDIA_DIRECTORY="$(mktemp -d -t crypton-heic)"
  cp scripts/fixtures/public-identity.heic "$CRYPTON_MEDIA_DIRECTORY/identity.heic"
  touch "$CRYPTON_MEDIA_DIRECTORY/identity.heic"
  xcrun simctl addmedia "$CRYPTON_DEVICE_ID" "$CRYPTON_MEDIA_DIRECTORY/identity.heic"
  rm -rf "$CRYPTON_MEDIA_DIRECTORY"
  export CRYPTON_QA_HEIC_READY=1
  node scripts/test-crypton-v2.cjs "$CRYPTON_SDK_ROOT"
  node scripts/test-messagebox-inbox.cjs "$CRYPTON_SDK_ROOT"
  CRYPTON_FIXTURE_SCRIPT=scripts/sdk-wallet-fixture.cjs
  if node -e 'const {createRequire}=require("node:module"); const path=require("node:path"); createRequire(path.resolve(process.argv[1],"package.json")).resolve("@bsv/auth-express-middleware")' "$CRYPTON_SDK_ROOT" >/dev/null 2>&1; then
    CRYPTON_FIXTURE_SCRIPT=scripts/messagebox-fixture.cjs
  fi
  node "$CRYPTON_FIXTURE_SCRIPT" "$CRYPTON_SDK_ROOT" > "$CRYPTON_LOG" 2>&1 &
  CRYPTON_FIXTURE_PID=$!
  sleep 1
  if ! kill -0 "$CRYPTON_FIXTURE_PID" 2>/dev/null; then cat "$CRYPTON_LOG"; exit 1; fi
fi
CRYPTON_RESULT_ARGS=()
if [ -n "${CRYPTON_RESULT_BUNDLE:-}" ]; then CRYPTON_RESULT_ARGS=(-resultBundlePath "$CRYPTON_RESULT_BUNDLE"); fi
xcodebuild -project Crypton.xcodeproj -scheme Crypton \
  -destination "platform=iOS Simulator,id=$CRYPTON_DEVICE_ID" \
  -derivedDataPath "${CRYPTON_DERIVED_DATA:-/tmp/crypton-ios-derived}" \
  -parallel-testing-enabled NO "${CRYPTON_RESULT_ARGS[@]}" CODE_SIGN_IDENTITY=- test "$@" 2>&1 | tee "$CRYPTON_RUN_DIRECTORY/xcodebuild.log"
