#!/usr/bin/env python3
"""Check timing-test CPU headroom without starting an app or wallet request."""
import argparse
import importlib.util
from pathlib import Path
import json
import os
from datetime import datetime, timezone

spec=importlib.util.spec_from_file_location('crypton_send',Path(__file__).with_name('send-message.py'))
send=importlib.util.module_from_spec(spec);spec.loader.exec_module(send)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output',type=Path)
    args=p.parse_args();os.umask(0o077)
    output=args.output or send.ARTIFACTS/('cpu-check-'+datetime.now(timezone.utc).strftime('%Y-%m-%d_%H-%M-%S_UTC')+'.json')
    try:report=send.sample_cpu()
    except send.CPUNotReady as error:report={'normal':False,'error':str(error),'utc':send.utc()}
    output.parent.mkdir(parents=True,exist_ok=True);send.write(output,report)
    print(json.dumps(report,indent=2));print('CPU evidence:',output)
    return 0 if report['normal'] else 2

if __name__=='__main__':raise SystemExit(main())
