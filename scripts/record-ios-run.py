#!/usr/bin/env python3
"""Record one explicitly selected simulator; finalize a private, verified MP4."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time


def utc():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True, help="Explicit simulator UUID; never 'booted'")
    parser.add_argument("--label", default="manual")
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--ready-file", type=Path, help="Written only after the first captured frame")
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", args.device):
        parser.error("--device must be an explicit simulator UUID")
    for command in ("xcrun", "ffmpeg", "ffprobe"):
        if not shutil.which(command):
            parser.error(f"{command} is required; recording must work before the run starts")
    os.umask(0o077)
    repo = Path(__file__).resolve().parents[1]
    output = (args.output_dir or repo / ".recordings").resolve()
    output.mkdir(parents=True, exist_ok=True, mode=0o700)
    label = re.sub(r"[^A-Za-z0-9._-]+", "-", args.label)[:60] or "run"
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%d_%H-%M-%S_UTC")
    folder = Path(tempfile.mkdtemp(prefix=f"{stamp}-{label}-", dir=output))
    raw, video = folder / "capture.mov", folder / "screen.mp4"
    metadata = {"device": args.device, "label": args.label, "startedAtUTC": utc(),
                "runDirectory": str(folder), "videoFile": str(video), "status": "starting"}
    revision = subprocess.run(["git", "-C", str(repo), "rev-parse", "HEAD"], capture_output=True, text=True)
    if revision.returncode == 0:
        metadata["checkoutCommit"] = revision.stdout.strip()
        dirty = subprocess.run(["git", "-C", str(repo), "status", "--porcelain"], capture_output=True, text=True)
        metadata["checkoutDirty"] = bool(dirty.stdout.strip())
    metadata_path = folder / "run.json"

    def save():
        temporary = metadata_path.with_suffix(".tmp")
        temporary.write_text(json.dumps(metadata, indent=2) + "\n")
        temporary.replace(metadata_path)

    stopped = False

    def stop(_signum, _frame):
        nonlocal stopped
        stopped = True

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)
    process = None
    save()
    try:
        with (folder / "recorder.log").open("w") as log:
            process = subprocess.Popen(["xcrun", "simctl", "io", args.device, "recordVideo", "--codec=h264", str(raw)],
                                       stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            deadline = time.monotonic() + 20
            while "Recording started" not in (folder / "recorder.log").read_text():
                if process.poll() is not None or stopped or time.monotonic() > deadline:
                    raise RuntimeError("Simulator recording did not become ready; see recorder.log")
                time.sleep(0.1)
            metadata["status"] = "recording"
            metadata["firstFrameAtUTC"] = utc()
            save()
            if args.ready_file:
                temporary = args.ready_file.with_suffix(".tmp")
                temporary.write_text(json.dumps(metadata) + "\n")
                temporary.replace(args.ready_file)
            print(json.dumps({"recording": "started", "videoFile": str(video), "runDirectory": str(folder)}), flush=True)
            while process.poll() is None and not stopped:
                time.sleep(0.1)
            if process.poll() is None:
                process.send_signal(signal.SIGINT)
            metadata["recorderExitCode"] = process.wait(timeout=30)
            if not stopped or process.returncode not in (0, 130):
                raise RuntimeError("Recorder ended unexpectedly; partial capture is retained")
            metadata["status"] = "finalizing"
            save()
            # simctl writes QuickTime even with an .mp4 suffix. Remux without
            # re-encoding so the deliverable is an actual MP4 with a fast-start index.
            subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-n", "-i", str(raw),
                            "-map", "0:v:0", "-c:v", "copy", "-movflags", "+faststart", str(video)],
                           stdout=log, stderr=subprocess.STDOUT, check=True)
            probe = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration:format_tags=major_brand",
                                    "-show_entries", "stream=codec_name,width,height", "-of", "json", str(video)],
                                   capture_output=True, text=True, check=True)
            details = json.loads(probe.stdout)
            if float(details.get("format", {}).get("duration", 0)) <= 0 or not details.get("streams"):
                raise RuntimeError("Recorded MP4 contains no usable video")
            metadata.update(status="complete", finishedAtUTC=utc(), media=details)
            save()
            print(json.dumps({"recording": "complete", "videoFile": str(video)}), flush=True)
            return 0
    except Exception as error:
        metadata.update(status="failed", finishedAtUTC=utc(), error=str(error))
        save()
        print(f"Recording failed: {error}; retained evidence: {folder}", file=sys.stderr, flush=True)
        return 1
    finally:
        if process is not None and process.poll() is None:
            process.send_signal(signal.SIGINT)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.terminate()


if __name__ == "__main__":
    sys.exit(main())
