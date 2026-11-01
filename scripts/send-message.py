#!/usr/bin/env python3
"""One recorded, human-approved Crypton send. Never retries payments or clicks Pay/Allow."""
import argparse
import base64
from datetime import datetime, timezone
import fcntl
import hashlib
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import secrets
import json
import os
from pathlib import Path
import plistlib
import re
import queue
import threading
import signal
import subprocess
import sys
import tempfile
import time
import uuid

REPO = Path(__file__).resolve().parents[1]
ARTIFACTS = REPO / '.recordings'
APP = 'com.projectbabbage.Crypton'
RUNNER = 'com.projectbabbage.CryptonUITests.xctrunner'
TEST = 'CryptonUITests/CryptonSendRunTests/testDeterministicMessageFlow'
EVENT = 'CRYPTON_RUN_EVENT '
FIXTURE_DEVICE = 'Crypton-iOS-Test'


def utc():
    return datetime.now(timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z')


def write(path, value):
    temp = path.with_suffix('.tmp')
    temp.write_text(json.dumps(value, indent=2) + '\n')
    temp.replace(path)


def command(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def sim(*args, **kwargs):
    return command(['xcrun', 'simctl', *args], **kwargs)


def targets(data):
    if 'TestConfigurations' in data:
        return [t for c in data['TestConfigurations'] for t in c['TestTargets']]
    return [v for k, v in data.items() if k != '__xctestrun_metadata__' and isinstance(v, dict)]


def configure_test(template, destination, plan):
    data = plistlib.loads(template.read_bytes())
    selected = [t for t in targets(data) if t.get('BlueprintName') == 'CryptonUITests' or t.get('ProductModuleName') == 'CryptonUITests']
    if not selected and 'CryptonUITests' in data:
        selected = [data['CryptonUITests']]
    if len(selected) != 1:
        raise RuntimeError('Expected one UI test target')
    t = selected[0]
    # Xcode supports UseDestinationArtifacts only on physical iOS devices.
    # Simulator runs install the built app in place; no uninstall/reset is used.
    t['OnlyTestIdentifiers'] = ['CryptonSendRunTests/testDeterministicMessageFlow']
    # Preserve build-root expansion after moving the private xctestrun file.
    root = str(template.parent)
    def expand(v):
        if isinstance(v, str): return v.replace('__TESTROOT__', root)
        if isinstance(v, list): return [expand(x) for x in v]
        if isinstance(v, dict): return {k: expand(x) for k, x in v.items()}
        return v
    t = expand(t)
    t.setdefault('EnvironmentVariables', {})['CRYPTON_SEND_PLAN'] = base64.b64encode(json.dumps(plan, ensure_ascii=False).encode()).decode()
    data = {'CryptonUITests': t, '__xctestrun_metadata__': {'FormatVersion': 1}}
    destination.write_bytes(plistlib.dumps(data))


class Run:
    def __init__(self, args, profiles):
        self.args, self.profiles = args, profiles
        self.folder = Path(tempfile.mkdtemp(prefix=datetime.now(timezone.utc).strftime('%Y-%m-%d_%H-%M-%S_UTC-send-'), dir=ARTIFACTS))
        now = utc(); run_id = str(uuid.uuid4())
        self.plan = {'run_id': run_id, 'composed_at': now, 'fixture': args.fixture, 'timeout': args.timeout,
                     'message': args.text + '\n\nComposed: ' + now + '\nRun: ' + run_id}
        if len(self.plan['message'].encode('utf-16-le')) // 2 > 16000:
            raise ValueError('Message including run timestamp must fit 16,000 UTF-16 units')
        self.events, self.recorders, self.logs = [], [], []
        self.state_lock = threading.RLock()
        self.claim_server = None
        self.process = None
        self.state = {'status': 'preparing', 'started_at': now, 'run_id': self.plan['run_id'], 'fixture': args.fixture,
                      'sender': profiles[0]['device'], 'receiver': profiles[1]['device'],
                      'text_sha256': hashlib.sha256(self.plan['message'].encode()).hexdigest(), 'folder': str(self.folder)}
        write(self.folder / 'request.json', self.plan)
        self.save()

    def save(self):
        with self.state_lock: write(self.folder / 'result.json', self.state)

    def start_claim_server(self):
        owner = self
        token = secrets.token_urlsafe(32)
        class Claim(BaseHTTPRequestHandler):
            def log_message(self, *_args): pass
            def do_POST(self):
                valid = (self.path == '/claim' and self.headers.get('X-Crypton-Run') == owner.plan['run_id']
                         and hmac.compare_digest(self.headers.get('Authorization', ''), 'Bearer ' + token)
                         and self.headers.get('Content-Length', '0') == '0')
                status = 403
                if valid:
                    # A host-side O_EXCL marker survives runner reinstalls and
                    # prevents Xcode recovery from initiating the same send twice.
                    with owner.state_lock:
                        try:
                            fd = os.open(owner.folder / 'send-claimed', os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
                            os.close(fd)
                            owner.state['status'] = 'sending'; owner.save(); status = 200
                        except FileExistsError: status = 409
                self.send_response(status); self.send_header('Content-Length', '0'); self.end_headers()
        self.claim_server = ThreadingHTTPServer(('127.0.0.1', 0), Claim)
        self.plan.update(claim_url='http://127.0.0.1:' + str(self.claim_server.server_port) + '/claim', claim_token=token)
        write(self.folder / 'request.json', self.plan)
        threading.Thread(target=self.claim_server.serve_forever, daemon=True).start()

    def start_capture(self):
        for device in dict.fromkeys(p['device'] for p in self.profiles):
            ready = self.folder / (device + '.ready.json')
            log = (self.folder / (device + '.recorder.log')).open('w')
            process = subprocess.Popen([sys.executable, str(REPO / 'scripts/record-ios-run.py'), '--device', device,
                '--label', 'send-' + self.plan['run_id'][:8], '--output-dir', str(self.folder), '--ready-file', str(ready)], stdout=log, stderr=subprocess.STDOUT)
            self.recorders.append((process, log, ready))
            deadline = time.monotonic() + 25
            while not ready.exists():
                if process.poll() is not None or time.monotonic() > deadline: raise RuntimeError('Recording did not start; no UI run will begin')
                time.sleep(.1)
            path = self.folder / (device + '.pipeline.jsonl')
            output = path.open('w')
            process = subprocess.Popen(['xcrun', 'simctl', 'spawn', device, 'log', 'stream', '--style', 'ndjson', '--level', 'info',
                '--predicate', 'process == "Crypton" AND eventMessage BEGINSWITH "Crypton pipeline "'], stdout=output, stderr=subprocess.DEVNULL)
            self.logs.append((process, output))
            time.sleep(.1)
            if process.poll() is not None: raise RuntimeError('Native timing capture failed before the UI run')

    def event(self, e):
        if e.get('run_id') != self.plan['run_id']: raise RuntimeError('Unexpected run identity in UI events')
        self.events.append(e)
        with (self.folder / 'events.jsonl').open('a') as f: f.write(json.dumps(e) + '\n')
        stage = e['stage']
        print(e['utc'], e['role'], stage, e.get('label', ''), flush=True)
        if stage == 'failed' and e.get('send_attempted') is False and e.get('role') == 'send' and not (self.folder / 'send-claimed').exists():
            self.state['status'] = 'failed'
        if stage == 'send_tapped':
            self.state['status'] = 'sending'
        if stage == 'pay_visible':
            # Bring the exact simulator window forward; never interact with Pay.
            command(['open', '-a', str(Path(os.environ['DEVELOPER_DIR'])/'Applications/Simulator.app') if 'DEVELOPER_DIR' in os.environ else 'Simulator', '--args', '-CurrentDeviceUDID', self.profiles[0]['device']])
            print('HUMAN ACTION (' + self.profiles[0].get('name', self.profiles[0]['device']) + '): review and click Pay once in ME. Leave Allow up to unchanged.\n'
                  'Composed: ' + self.plan['composed_at'] + '; run: ' + self.plan['run_id'], flush=True)
        if stage == 'accepted': self.state.update(status='accepted', message_id=e['message_id'])
        if stage == 'retained': self.state['status'] = 'complete'
        self.save()

    def phase(self, template, role, profile):
        plan = {**self.plan, 'role': role, 'recipient_name': self.profiles[1].get('name', 'Peer iOS'),
                'receiving_key': self.profiles[1].get('receivingKey', ''), 'wallet_identity': self.profiles[1].get('walletIdentity', ''),
                'message_id': self.state.get('message_id', '')}
        spec = self.folder / (role + '.xctestrun')
        configure_test(template, spec, plan)
        args = ['xcodebuild', 'test-without-building', '-xctestrun', str(spec), '-destination', 'platform=iOS Simulator,id=' + profile['device'],
                '-parallel-testing-enabled', 'NO', '-maximum-concurrent-test-simulator-destinations', '1',
                '-resultBundlePath', str(self.folder / (role + '.xcresult')), '-only-testing:' + TEST]
        if role == 'send':
            self.state['status'] = 'sending'; self.save()
        self.process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1, start_new_session=True)
        lines = queue.Queue()
        def reader():
            for line in self.process.stdout: lines.put(line)
            lines.put(None)
        threading.Thread(target=reader, daemon=True).start()
        deadline = time.monotonic() + self.args.timeout + 180
        with (self.folder / (role + '.log')).open('w') as log:
            while True:
                if time.monotonic() > deadline: raise RuntimeError(role + ' exceeded its host deadline')
                try: line = lines.get(timeout=.2)
                except queue.Empty: continue
                if line is None: break
                log.write(line); log.flush()
                if line.startswith(EVENT):
                    self.event(json.loads(line[len(EVENT):]))
        result = self.process.wait(timeout=10); self.process = None
        if result: raise RuntimeError(role + ' failed; inspect its xcresult/video. No automatic payment retry.')
        expected = {'send': 'accepted', 'receive': 'retained', 'preflight': 'preflight_complete'}[role]
        if not any(e['role'] == role and e['stage'] == expected for e in self.events):
            raise RuntimeError('UI test ended without the required ' + expected + ' evidence')

    def finish(self):
        if self.claim_server:
            self.claim_server.shutdown(); self.claim_server.server_close()
        if self.process and self.process.poll() is None:
            os.killpg(self.process.pid, signal.SIGINT)
            try: self.process.wait(timeout=15)
            except subprocess.TimeoutExpired: os.killpg(self.process.pid, signal.SIGTERM)
        for process, f in self.logs:
            if process.poll() is None: process.send_signal(signal.SIGINT)
            else: self.state['diagnostics_error'] = True
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired: process.terminate()
            f.close()
        for process, f, ready in self.recorders:
            if process.poll() is None: process.send_signal(signal.SIGINT)
            try: code = process.wait(timeout=45)
            except subprocess.TimeoutExpired: process.terminate(); code = 1
            f.close()
            if code: self.state['recording_error'] = True
            elif ready.exists():
                metadata = json.loads(ready.read_text()); metadata = json.loads((Path(metadata['runDirectory']) / 'run.json').read_text())
                if metadata['status'] != 'complete': self.state['recording_error'] = True
        if (self.state.get('recording_error') or self.state.get('diagnostics_error')) and self.state['status'] == 'complete': self.state['status'] = 'evidence_failed'
        self.state['finished_at'] = utc(); self.save()
        pairs = [('send_tapped', 'pay_visible'), ('send_tapped', 'accepted'), ('refresh_tapped', 'received'), ('decrypt_tapped', 'decrypted')]
        timings = []
        for start, end in pairs:
            a = next((e for e in self.events if e['stage'] == start), None); b = next((e for e in self.events if e['stage'] == end), None)
            if a and b: timings.append({'from': start, 'to': end, 'milliseconds': round(b['elapsed_ms'] - a['elapsed_ms'], 1)})
        write(self.folder / 'timings.json', timings)
        # Exact ME review events supplement the UI's sampled timestamps. Never
        # enable diagnostics or export keys, payloads, transaction data or origins.
        wallet_events = []
        if not self.args.fixture:
            fields = {'review_id','review_age_ms','review_lifetime_ms','stage','outcome','approval','primary_error_name','cleanup_error_name','execution_status','primary_preserved','action_blocked'}
            for profile in self.profiles:
                try:
                    root = Path(subprocess.check_output(['xcrun','simctl','get_app_container',profile['device'],'app.metanet.explorer','data'],text=True).strip())
                    store = root/'Library/Application Support/app.metanet.explorer/RCTAsyncLocalStorage_V1'
                    key = 'metanet.diagnostics.events.v1'; manifest = json.loads((store/'manifest.json').read_text())
                    raw = manifest.get(key)
                    if raw is None: raw = (store/hashlib.md5(key.encode()).hexdigest()).read_text()
                    wallet_events.extend({'device':profile['device'],'utc':e['at'],'stage':e['name'],'params':{k:v for k,v in e.get('params',{}).items() if k in fields}}
                        for e in json.loads(raw) if self.state['started_at'] <= e.get('at','') <= self.state['finished_at'] and e.get('name','').startswith('wallet_payment_'))
                except Exception:
                    self.state.setdefault('wallet_diagnostics_unavailable',[]).append(profile['device'])
            write(self.folder/'wallet-review-events.json',wallet_events); self.save()
        rows = ['Crypton single-command run', 'Run: ' + self.plan['run_id'], 'Composed (UTC): ' + self.plan['composed_at'], 'Result: ' + self.state['status'],
                '', 'UI-observed intervals (sampled completion timestamps; not pure network time):']
        rows += [t['from'] + ' -> ' + t['to'] + ': ' + str(t['milliseconds']) + ' ms' for t in timings]
        rows += ['', 'All UI events (UTC):']
        rows += [e['utc'] + ' ' + e['role'] + ' ' + e['stage'] for e in self.events]
        rows += ['', 'ME review events (exact diagnostic timestamps when enabled):']
        rows += [e['utc'] + ' ' + e['stage'] for e in wallet_events]
        rows += ['', 'Native HTTP/wallet/checkpoint spans: see *.pipeline.jsonl.',
                 'MP4s: see the per-device subdirectories. Recordings and request text are private local evidence.',
                 'Fixture mode uses disposable self-send; it does not establish a two-wallet production result.',
                 'On any uncertain payment outcome, inspect this saved run and the app outbox; do not rerun Send.']
        (self.folder/'timing-report.txt').write_text('\n'.join(rows)+'\n')
        print('Result:', self.state['status'], '\nEvidence:', self.folder, flush=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('text', help='Message text; the script appends UTC composition time and a unique run marker')
    p.add_argument('--config', type=Path, default=ARTIFACTS / 'send-profiles.json')
    p.add_argument('--reverse', action='store_true', help='Send peer -> primary')
    p.add_argument('--fixture', action='store_true', help='Disposable self-send on Crypton-iOS-Test only; no live wallets or spending')
    p.add_argument('--sdk-root', type=Path, default=os.environ.get('CRYPTON_SDK_ROOT'))
    p.add_argument('--timeout', type=int, default=300, help='Maximum seconds per UI phase; never overrides ME review expiry')
    p.add_argument('--dry-run', action='store_true', help='Validate profiles and print plan without UI or wallet actions')
    a = p.parse_args()
    if not a.text.strip() or not 30 <= a.timeout <= 900: p.error('Nonempty text and a timeout from 30 to 900 seconds are required')
    os.umask(0o077); ARTIFACTS.mkdir(exist_ok=True)
    if 'DEVELOPER_DIR' not in os.environ:
        preferred = Path('/Applications/Xcode-26.6.app/Contents/Developer')
        if preferred.exists(): os.environ['DEVELOPER_DIR'] = str(preferred)
    def interrupted(_signum, _frame): raise KeyboardInterrupt()
    signal.signal(signal.SIGTERM, interrupted)
    lock = (ARTIFACTS / 'send-command.lock').open('w')
    try: fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError: p.error('Another send command is running')
    devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))['devices']
    available = {d['udid']: d for rows in devices.values() for d in rows}
    if a.fixture:
        found = [d for d in available.values() if d['name'] == FIXTURE_DEVICE]
        if len(found) != 1 or not a.sdk_root: p.error('--fixture requires one Crypton-iOS-Test simulator and --sdk-root')
        profiles = [{'device': found[0]['udid'], 'name': 'Disposable self'}] * 2
    else:
        config = json.loads(a.config.read_text()); profiles = [config['primary'], config['peer']]
        if a.reverse: profiles.reverse()
        if profiles[0]['device'] == profiles[1]['device']: p.error('Production sender and receiver must be different simulators')
        for profile in profiles:
            for k in ['receivingKey', 'walletIdentity']:
                if not re.fullmatch(r'0[23][a-fA-F0-9]{64}', profile[k]): p.error('Invalid profile ' + k)
    for profile in profiles:
        if profile['device'] not in available: p.error('Configured simulator is unavailable')
    if a.dry_run:
        print(json.dumps({'sender': profiles[0]['device'], 'receiver': profiles[1]['device'], 'fixture': a.fixture,
                          'human_payment_approval': not a.fixture, 'text_utf16_units': len(a.text.encode('utf-16-le')) // 2}, indent=2)); return 0
    # A past ambiguous send is not permission for another payment.
    for result in ARTIFACTS.glob('*_UTC-send-*/result.json'):
        old = json.loads(result.read_text())
        if not a.fixture and not old.get('fixture') and old.get('sender') == profiles[0]['device'] and old.get('status') in ['sending', 'needs_recovery']:
            p.error('Resolve the saved payment outcome before another run: ' + str(result.parent))
    run, server, server_log = Run(a, profiles), None, None
    try:
        build = ARTIFACTS / ('send-run-fixture-build' if a.fixture else 'send-run-release-build')
        with (run.folder / 'build.log').open('w') as log:
            command(['xcodebuild', '-project', str(REPO / 'Crypton.xcodeproj'), '-scheme', 'CryptonSendRun', '-configuration', 'Debug' if a.fixture else 'Release',
                     '-destination', 'generic/platform=iOS Simulator', '-derivedDataPath', str(build), 'ARCHS=arm64', 'ONLY_ACTIVE_ARCH=YES', 'CODE_SIGN_IDENTITY=-',
                     'build-for-testing'], stdout=log, stderr=subprocess.STDOUT)
        templates = list((build / 'Build/Products').glob('*.xctestrun'))
        if len(templates) != 1: raise RuntimeError('Expected exactly one built UI test manifest')
        products = build / 'Build/Products' / ('Debug-iphonesimulator' if a.fixture else 'Release-iphonesimulator')
        for device in dict.fromkeys(p['device'] for p in profiles):
            if available[device]['state'] != 'Booted': sim('boot', device)
            sim('bootstatus', device, '-b', stdout=subprocess.DEVNULL)
        run.start_capture(); run.start_claim_server()
        if a.fixture:
            server_log = (run.folder / 'fixture.log').open('w')
            server = subprocess.Popen(['node', str(REPO / 'scripts/messagebox-fixture.cjs'), str(a.sdk_root)], cwd=REPO, stdout=server_log, stderr=subprocess.STDOUT)
            # Fixture readiness is checked from its explicit ready event, not a fixed startup delay.
            deadline = time.monotonic()+15
            while 'MessageBox fixture ready' not in (run.folder / 'fixture.log').read_text():
                if server.poll() is not None or time.monotonic()>deadline: raise RuntimeError('Disposable fixture failed to start')
                time.sleep(.1)
        for device in dict.fromkeys(p['device'] for p in profiles):
            if not a.fixture: sim('get_app_container', device, 'app.metanet.explorer', 'app', stdout=subprocess.DEVNULL)
            sim('install', device, str(products / 'Crypton.app'))
            sim('install', device, str(products / 'CryptonUITests-Runner.app'))
        run.phase(templates[0], 'preflight', profiles[1])
        run.phase(templates[0], 'send', profiles[0])
        run.phase(templates[0], 'receive', profiles[1])
    except (Exception, KeyboardInterrupt) as e:
        run.state['error'] = str(e) or 'Interrupted'
        if run.state['status'] == 'sending': run.state['status'] = 'needs_recovery'
        elif run.state['status'] != 'accepted': run.state['status'] = 'failed'
        print('Stopped:', run.state['error'], file=sys.stderr)
    finally:
        if server:
            server.terminate()
            try: server.wait(timeout=5)
            except subprocess.TimeoutExpired: server.kill()
            server_log.close()
        run.finish()
    return 0 if run.state['status'] == 'complete' else 1


if __name__ == '__main__':
    sys.exit(main())
