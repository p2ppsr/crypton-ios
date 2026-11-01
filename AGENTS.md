# Recorded test runs

- Always include the message's composition timestamp (with timezone) and run marker, when available, in questions about sending, receipt, decryption or retention. Distinguish composition time from first-seen or read time.
- The operator requires an MP4 for every Crypton iOS / Metanet Explorer UI or device test run. Start recording before the first app interaction and keep it running through the final result or error, including recovery attempts.
- For manual runs, start `python3 scripts/record-ios-run.py --device <explicit simulator UUID> --label <run-name>` in a persistent terminal session. Wait for `"recording": "started"` before interacting. Send Control-C to that session when finished, then wait for `"recording": "complete"` and check `run.json`.
- `scripts/test-ios.sh` records its dedicated test simulator automatically. A recording startup/finalization failure fails the run; do not silently run unrecorded.
- Store recordings and notes in the ignored `.recordings/` directory. Keep them local; do not commit or upload wallet recordings. Note any missing beginning or interrupted segment honestly. Keep app privacy protections enabled.
- Use computer-use controls for manual app interaction. Recording does not authorize another UI automation method, a permission change, or a payment.
