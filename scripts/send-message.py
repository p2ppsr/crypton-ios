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
from concurrent.futures import ThreadPoolExecutor
import signal
import subprocess
import sys
import tempfile
import time
import uuid
from urllib.parse import urlsplit, parse_qs

REPO = Path(__file__).resolve().parents[1]
ARTIFACTS = REPO / '.recordings'
APP = 'com.projectbabbage.Crypton'
RUNNER = 'com.projectbabbage.CryptonUITests.xctrunner'
TEST = 'CryptonUITests/CryptonSendRunTests/testDeterministicMessageFlow'
EVENT = 'CRYPTON_RUN_EVENT '
FIXTURE_DEVICE = 'Crypton-iOS-Test'
WALLET_FIELDS = {'review_id','review_age_ms','review_lifetime_ms','stage','outcome','approval','primary_error_name','cleanup_error_name','execution_status','primary_preserved','action_blocked'}


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


def native_status(path, after, kind):
    if kind not in ['runInbox','runDelivery']: raise ValueError('Unsupported operation kind')
    operations = {}
    if not path.exists(): return 'waiting'
    for line in path.read_text().splitlines():
        try:
            item = json.loads(line)
            at = datetime.fromisoformat(item['timestamp']).timestamp()
            match = re.fullmatch(r'Crypton pipeline ([A-Fa-f0-9-]+) ([A-Za-z0-9_./-]+) [0-9.]+ms',item['eventMessage'])
        except (ValueError,KeyError,TypeError): continue
        if not match or at < after: continue
        operation, stage = match.groups()
        if stage == 'start.'+kind: operations[operation] = 'waiting'
        elif operation in operations and stage in ['complete','failed']: operations[operation] = stage
    return next(reversed(operations.values())) if operations else 'waiting'


def payment_review_id(visible, wallet_events, sender_device):
    if not visible: return None
    if visible.get('review_id'): return visible['review_id']
    stamp = lambda e: datetime.fromisoformat(e['utc'].replace('Z', '+00:00')).timestamp()
    # Older spending-modal diagnostics omit the ID. Bind only to one review
    # opened immediately before that modal on the same sender, never any approval.
    matches = [e.get('params',{}).get('review_id') for e in wallet_events
               if e.get('stage') == 'wallet_payment_review_opened' and e.get('device') == sender_device
               and 0 <= stamp(visible)-stamp(e) <= 1]
    return matches[0] if len(matches) == 1 and matches[0] else None


def target_timing(events, wallet_events, fixture=False, sender_device=None):
    """Cross-device UTC boundaries; deduct only an evidenced visible Pay wait."""
    def first(stage, role):
        return next((e for e in events if e.get('stage') == stage and e.get('role') == role), None)
    launch, verified = first('launch_requested', 'send'), first('retained', 'receive')
    accepted = first('accepted','send')
    report = {'target_ms': 20000, 'verification': 'exact_plaintext_and_retained_copy',
              'fixture': fixture, 'status': 'unavailable'}
    if not launch or not verified: return {**report, 'reason': 'Missing launch or recipient-verification boundary'}
    def stamp(e): return datetime.fromisoformat(e['utc'].replace('Z', '+00:00')).timestamp()
    if accepted and stamp(accepted) > stamp(verified): verified=accepted
    total = (stamp(verified) - stamp(launch)) * 1000
    wait = 0
    if not fixture:
        visible = first('pay_visible', 'send')
        review_id = payment_review_id(visible,wallet_events,sender_device)
        approved = next((e for e in wallet_events if e.get('stage') == 'wallet_payment_review_approved'
                         and visible and review_id and e.get('device') == sender_device
                         and e.get('params',{}).get('review_id') == review_id
                         and stamp(e) >= stamp(visible)), None)
        if not visible or not approved: return {**report, 'reason': 'Missing evidenced Pay-visible/approval interval', 'total_ms': round(total, 1)}
        wait = (stamp(approved) - stamp(visible)) * 1000
    if not 0 <= wait <= total: return {**report, 'reason': 'Invalid clock ordering'}
    adjusted = total - wait
    return {**report, 'status': 'measured', 'launch_utc': launch['utc'], 'verified_utc': verified['utc'],
            'total_ms': round(total, 1), 'pay_wait_ms': round(wait, 1), 'adjusted_ms': round(adjusted, 1),
            'met': adjusted <= 20000 and accepted is not None, 'sender_receipt': 'confirmed' if accepted else 'unconfirmed'}


class Run:
    def __init__(self, args, profiles):
        self.args, self.profiles = args, profiles
        self.folder = Path(tempfile.mkdtemp(prefix=datetime.now(timezone.utc).strftime('%Y-%m-%d_%H-%M-%S_UTC-send-'), dir=ARTIFACTS))
        now = utc(); run_id = str(uuid.uuid4())
        self.plan = {'run_id': run_id, 'composed_at': now, 'fixture': args.fixture, 'timeout': args.timeout,
                     'message': args.text + '\n\nComposed: ' + now + '\nRun: ' + run_id}
        if len(self.plan['message'].encode('utf-16-le')) // 2 > 16000:
            raise ValueError('Message including run timestamp must fit 16,000 UTF-16 units')
        original = getattr(args,'verify_run',None)
        if original:
            saved = json.loads((original/'request.json').read_text())
            result = json.loads((original/'result.json').read_text())
            if saved['run_id'] != result['run_id'] or hashlib.sha256(saved['message'].encode()).hexdigest() != result['text_sha256']:
                raise ValueError('Original run identity/text hash does not match')
            if saved.get('fixture') or (result['sender'],result['receiver']) != (profiles[0]['device'],profiles[1]['device']):
                raise ValueError('Verification profiles do not match the original production run')
            self.plan = {k:v for k,v in saved.items() if k not in ['claim_url','claim_token','watch_url','watch_token']}
            self.plan['timeout'] = args.timeout
        self.events, self.recorders, self.logs = [], [], []
        self.state_lock = threading.RLock()
        self.claim_server = None
        self.process = None
        self.review_prompted = False
        self.wallet_roots = {}
        self.live_wallet_events = {}
        self.receive_pool = None
        self.receive_future = None
        self.stop_phases = threading.Event()
        self.state = {'status': 'preparing', 'started_at': now, 'run_id': self.plan['run_id'], 'fixture': args.fixture,
                      'sender': profiles[0]['device'], 'receiver': profiles[1]['device'],
                      'text_sha256': hashlib.sha256(self.plan['message'].encode()).hexdigest(), 'folder': str(self.folder)}
        if original:
            self.state.update(status='verifying',mode='verify_only',original_run=str(original.resolve()),message_id=args.message_id,
                              run_id=self.plan['run_id'],text_sha256=hashlib.sha256(self.plan['message'].encode()).hexdigest())
        write(self.folder / 'request.json', self.plan)
        self.save()

    def save(self):
        with self.state_lock: write(self.folder / 'result.json', self.state)

    def start_claim_server(self):
        owner = self
        token = secrets.token_urlsafe(32)
        may_send = not (getattr(getattr(self,'args',None),'verify_run',None) or getattr(getattr(self,'args',None),'recovery_only',False))
        class Claim(BaseHTTPRequestHandler):
            def log_message(self, *_args): pass
            def do_POST(self):
                valid = (may_send and self.path == '/claim' and self.headers.get('X-Crypton-Run') == owner.plan['run_id']
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
            def do_GET(self):
                url = urlsplit(self.path); params = parse_qs(url.query)
                valid = (url.path == '/watch' and self.headers.get('X-Crypton-Run') == owner.plan['run_id']
                         and hmac.compare_digest(self.headers.get('Authorization',''),'Bearer '+token))
                try:
                    device = params['device'][0]; kind = params['kind'][0]; after = float(params['after'][0])
                    if device not in [p['device'] for p in owner.profiles] or not re.fullmatch(r'[a-fA-F0-9-]{36}',device): raise ValueError('Unknown simulator')
                    result = native_status(owner.folder/(device+'.pipeline.jsonl'),after,kind) if valid else 'denied'
                except (ValueError,KeyError): valid = False; result = 'denied'
                body = json.dumps({'status':result}).encode()
                self.send_response(200 if valid else 403); self.send_header('Content-Type','application/json')
                self.send_header('Content-Length',str(len(body))); self.end_headers(); self.wfile.write(body)
        self.claim_server = ThreadingHTTPServer(('127.0.0.1', 0), Claim)
        base = 'http://127.0.0.1:' + str(self.claim_server.server_port)
        self.plan.update(watch_url=base+'/watch',watch_token=token)
        if may_send: self.plan.update(claim_url=base+'/claim',claim_token=token)
        write(self.folder / 'request.json', self.plan)
        threading.Thread(target=self.claim_server.serve_forever, daemon=True).start()

    def start_capture(self):
        active = self.profiles[1:] if getattr(self.args,'verify_run',None) else self.profiles
        for device in dict.fromkeys(p['device'] for p in active):
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
        with self.state_lock:
            self._event(e)

    def _event(self, e):
        if e.get('run_id') != self.plan['run_id']: raise RuntimeError('Unexpected run identity in UI events')
        self.events.append(e)
        with (self.folder / 'events.jsonl').open('a') as f: f.write(json.dumps(e) + '\n')
        stage = e['stage']
        print(e['utc'], e['role'], stage, e.get('label', e.get('detail','')), flush=True)
        if stage == 'failed' and e.get('send_attempted') is False and e.get('role') == 'send' and not (self.folder / 'send-claimed').exists():
            self.state['status'] = 'failed'
        if (stage == 'failed' and self.state.get('status') == 'sending' and e.get('role') == 'send' and e.get('send_attempted') is True
                and e.get('payment_not_requested') is True and e.get('delivery_state') in ['DRAFT','QUOTED']
                and isinstance(e.get('delivery_id'), str) and re.fullmatch(r'[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}', e['delivery_id'])):
            self.state.update(status='failed_before_payment', delivery_id=e['delivery_id'],
                              payment_not_requested=True, delivery_state=e['delivery_state'])
        if (stage == 'failed' and self.state.get('status') == 'sending' and e.get('role') == 'send'
                and e.get('send_attempted') is True and e.get('delivery_state') == 'SUBMITTING'
                and e.get('has_saved_payment') is True
                and re.fullmatch(r'[a-f0-9]{64}', str(e.get('message_id', '')))
                and re.fullmatch(r'[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}', str(e.get('delivery_id', '')))):
            self.state.update(verify_unconfirmed_submission=True, delivery_id=e['delivery_id'],
                              message_id=e['message_id'], sender_receipt='unconfirmed')
        if (stage == 'payment_saved' and self.state.get('status') == 'sending' and e.get('role') == 'send' and e.get('has_saved_payment') is True
                and re.fullmatch(r'[a-f0-9]{64}', str(e.get('message_id','')))
                and re.fullmatch(r'[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}', str(e.get('delivery_id','')))):
            self.state.update(message_id=e['message_id'],delivery_id=e['delivery_id'])
            if (getattr(self,'receive_pool',None) is not None and self.receive_future is None
                    and self.profiles[0]['device'] != self.profiles[1]['device']):
                self.receive_future=self.receive_pool.submit(self.phase,None,'receive',self.profiles[1])
        if stage == 'send_tapped':
            self.state['status'] = 'sending'
        if stage == 'pay_visible' or (stage == 'progress' and 'approve payment' in e.get('detail','').lower()):
            if not getattr(self,'review_prompted',False):
                self.review_prompted = True
                command(['open','-a',str(Path(os.environ['DEVELOPER_DIR'])/'Applications/Simulator.app') if 'DEVELOPER_DIR' in os.environ else 'Simulator','--args','-CurrentDeviceUDID',self.profiles[0]['device']])
                print('HUMAN ACTION ('+self.profiles[0].get('name',self.profiles[0]['device'])+'): review the final total and click Pay once in ME. Leave Allow up to unchanged.\n'
                      'Composed: '+self.plan['composed_at']+'; run: '+self.plan['run_id'],flush=True)
        if stage == 'accepted':
            if self.state.get('message_id') and self.state['message_id'] != e['message_id']: raise RuntimeError('Acceptance changed the saved message ID')
            self.state.update(status='complete' if self.state.get('recipient_retained') else 'accepted',
                              sender_status='accepted',sender_receipt='confirmed',message_id=e['message_id'])
        if stage == 'retained':
            self.state['recipient_retained']=True
            if self.state.get('sender_status') == 'accepted' or self.state.get('sender_receipt') == 'unconfirmed' or getattr(getattr(self,'args',None),'verify_run',None):
                self.state['status']='complete'
        self.save()

    def send_and_verify(self, template):
        self.phase(template, 'preflight', self.profiles[1])
        self.receive_pool=ThreadPoolExecutor(max_workers=1)
        try:
            try:
                self.phase(template, 'send', self.profiles[0])
            except Exception as error:
                # Only reads overlap the already-durable payment/submission.
                if not self.state.pop('verify_unconfirmed_submission', False): raise
                with self.state_lock:
                    self.state.update(status='needs_recovery',sender_error=str(error),sender_receipt='unconfirmed')
                    self.save()
                print('Sender receipt missing; checking the exact paid message on the recipient. No resend/payment.\n'
                      'Composed: '+self.plan['composed_at']+'; run: '+self.plan['run_id'],flush=True)
            if self.receive_future is not None:
                self.receive_future.result(timeout=self.args.timeout+35)
            else:
                self.phase(template,'receive',self.profiles[1])
            if self.state.get('sender_receipt') == 'unconfirmed':
                self.state['status']='recipient_verified';self.save()
        finally:
            self.stop_phases.set()
            self.receive_pool.shutdown(wait=True,cancel_futures=True)
            self.receive_pool=None

    # Historical UI executor, retained for regression tests only. The CLI uses phase() below.
    def phase_xctest(self, template, role, profile):
        if getattr(self.args,'verify_run',None) and role != 'receive':
            raise RuntimeError('Verification mode cannot enter a sending phase')
        plan = {**self.plan, 'role': role, 'device':profile['device'], 'recipient_name': self.profiles[1].get('name', 'Peer iOS'),
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

    def phase(self, template, role, profile):
        if getattr(self.args,'verify_run',None) and role != 'receive':
            raise RuntimeError('Verification mode cannot enter a sending phase')
        if getattr(self.args,'recovery_only',False) and role != 'recover-review':
            raise RuntimeError('Review recovery cannot enter another phase')
        root = Path(subprocess.check_output(['xcrun','simctl','get_app_container',profile['device'],APP,'data'],text=True).strip())
        folder = root/'Library/Application Support/ScriptedRuns'/self.plan['run_id']
        folder.mkdir(parents=True,exist_ok=True,mode=0o700)
        events_path = folder/'events.jsonl'; events_path.write_text('')
        plan = {**self.plan,'role':role,'device':profile['device'],'mode':self.state.get('mode','send'),
                'recipient_name':self.profiles[1].get('name','Peer iOS'),'receiving_key':self.profiles[1].get('receivingKey',''),
                'wallet_identity':self.profiles[1].get('walletIdentity',''),'message_id':self.state.get('message_id','')}
        write(folder/'request.json',plan)
        if role == 'send':self.state['status']='sending';self.save()
        launch = ['launch','--terminate-running-process',profile['device'],APP]
        if self.args.fixture:launch += ['--uitesting','--sdk-wallet-fixture','--messagebox-fixture']
        launch += ['--crypton-script',self.plan['run_id']]
        offset = 0; pay_seen = False; deadline = time.monotonic()+self.args.timeout+30
        try:
            self.event({'run_id':self.plan['run_id'],'role':role,'stage':'launch_requested','utc':utc(), 'elapsed_ms':0})
            sim(*launch,stdout=subprocess.DEVNULL)
            while time.monotonic()<deadline:
                if self.stop_phases.is_set(): raise RuntimeError('Recorded phase stopped')
                with events_path.open() as f:
                    f.seek(offset)
                    while True:
                        position = f.tell();line = f.readline()
                        if not line or not line.endswith('\n'):f.seek(position);break
                        event = json.loads(line)
                        self.event(event)
                        if event['stage']=='failed':raise RuntimeError(event.get('reason','Native script failed'))
                        if event['stage']=='phase_complete':
                            expected={'preflight':'preflight_complete','send':'accepted','receive':'retained','recover-review':'unpaid_review_recovered'}[role]
                            if not any(e['role']==role and e['stage']==expected for e in self.events):raise RuntimeError('Missing '+expected+' evidence')
                            return
                    offset=f.tell()
                if role=='send' and not self.args.fixture:
                    pay_seen=self.observe_payment(profile, report=not pay_seen) or pay_seen
                time.sleep(.1)
            raise RuntimeError(role+' exceeded its native phase deadline; inspect the saved outcome')
        finally:
            (folder/'request.json').unlink(missing_ok=True)
            (folder/'request.tmp').unlink(missing_ok=True)

    def observe_payment(self, profile, report=True):
        try:
            if profile['device'] not in self.wallet_roots:
                self.wallet_roots[profile['device']]=Path(subprocess.check_output(['xcrun','simctl','get_app_container',profile['device'],'app.metanet.explorer','data'],text=True).strip())/'Library/Application Support/app.metanet.explorer/RCTAsyncLocalStorage_V1'
            root=self.wallet_roots[profile['device']]
            key='metanet.diagnostics.events.v1'; manifest=json.loads((root/'manifest.json').read_text());raw=manifest.get(key)
            if raw is None:raw=(root/hashlib.md5(key.encode()).hexdigest()).read_text()
            data=json.loads(raw)
            for e in data:
                if e.get('at','') >= self.state['started_at'] and e.get('name','').startswith('wallet_payment_'):
                    value={'device':profile['device'],'utc':e['at'],'stage':e['name'],'params':{k:v for k,v in e.get('params',{}).items() if k in WALLET_FIELDS}}
                    self.live_wallet_events[(profile['device'],e['at'],e['name'])]=value
            write(self.folder/'wallet-review-events.json',list(self.live_wallet_events.values()))
            visible=next((e for e in data if e.get('at','')>=self.state['started_at'] and e.get('name')=='wallet_permission_spending_modal_visible' and 'crypton' in e.get('params',{}).get('originator','').lower()),None)
            if visible and report:
                started=next(e for e in self.events if e['role']=='send' and e['stage']=='started')
                elapsed=(datetime.fromisoformat(visible['at'])-datetime.fromisoformat(started['utc'])).total_seconds()*1000
                self.event({'run_id':self.plan['run_id'],'role':'send','stage':'pay_visible','utc':visible['at'],'elapsed_ms':elapsed,
                            'label':'Pay '+str(visible['params']['spending_amount'])+' sats','review_id':visible.get('params',{}).get('review_id'),'source':'ME spending-modal diagnostic'})
                return True
        except (OSError,ValueError,KeyError,StopIteration,subprocess.CalledProcessError):pass
        return False

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
        if (self.state.get('recording_error') or self.state.get('diagnostics_error')) and self.state['status'] in ['complete','recipient_verified']: self.state['status'] = 'evidence_failed'
        self.state['finished_at'] = utc(); self.save()
        pairs = [('send_tapped', 'pay_visible'), ('send_tapped', 'accepted'), ('refresh_tapped', 'received'), ('decrypt_tapped', 'decrypted')]
        timings = []
        for start, end in pairs:
            a = next((e for e in self.events if e['stage'] == start), None); b = next((e for e in self.events if e['stage'] == end), None)
            if a and b: timings.append({'from': start, 'to': end, 'milliseconds': round(b['elapsed_ms'] - a['elapsed_ms'], 1)})
        write(self.folder / 'timings.json', timings)
        # Exact ME review events supplement the UI's sampled timestamps. Never
        # enable diagnostics or export keys, payloads, transaction data or origins.
        wallet_events = list(self.live_wallet_events.values())
        if not self.args.fixture:
            fields = WALLET_FIELDS
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
            wallet_events=list({(e['device'],e['utc'],e['stage']):e for e in wallet_events}.values())
            write(self.folder/'wallet-review-events.json',wallet_events); self.save()
        target = target_timing(self.events, wallet_events, self.args.fixture, self.profiles[0]['device'])
        write(self.folder/'target-timing.json', target)
        self.state['target_timing'] = target; self.save()
        if target['status'] == 'measured':
            print('Launch → verified, excluding Pay click wait: '+str(target['adjusted_ms'])+' ms; target 20000 ms; '+('MET' if target['met'] else 'NOT MET')+(' (disposable fixture)' if self.args.fixture else ''), flush=True)
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
    p.add_argument('text', nargs='?', default='', help='Message text; the script appends UTC composition time and a unique run marker')
    p.add_argument('--verify-run',type=Path,help='Verify/decrypt an existing paid run on its receiver only; never sends or pays')
    p.add_argument('--message-id',help='Exact known MessageBox ID for --verify-run')
    p.add_argument('--config', type=Path, default=ARTIFACTS / 'send-profiles.json')
    p.add_argument('--reverse', action='store_true', help='Send peer -> primary')
    p.add_argument('--fixture', action='store_true', help='Disposable self-send on Crypton-iOS-Test only; no live wallets or spending')
    p.add_argument('--sdk-root', type=Path, default=os.environ.get('CRYPTON_SDK_ROOT'))
    p.add_argument('--timeout', type=int, default=300, help='Maximum seconds per UI phase; never overrides ME review expiry')
    p.add_argument('--dry-run', action='store_true', help='Validate profiles and print plan without UI or wallet actions')
    a = p.parse_args()
    if (not a.verify_run and not a.text.strip()) or not 30 <= a.timeout <= 900: p.error('Nonempty text and a timeout from 30 to 900 seconds are required')
    if a.verify_run and (a.text or a.fixture or not re.fullmatch(r'[a-f0-9]{64}',a.message_id or '')): p.error('--verify-run requires --message-id and excludes new text/fixtures')
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
        if a.verify_run:
            old = json.loads((a.verify_run/'result.json').read_text())
            if profiles[0]['device'] == old['receiver']: profiles.reverse()
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
        if not a.verify_run and not a.fixture and not old.get('fixture') and old.get('sender') == profiles[0]['device'] and old.get('status') in ['sending', 'needs_recovery']:
            p.error('Resolve the saved payment outcome before another run: ' + str(result.parent))
    run, server, server_log = Run(a, profiles), None, None
    try:
        build = ARTIFACTS / ('send-run-fixture-build' if a.fixture else 'send-run-release-build')
        with (run.folder / 'build.log').open('w') as log:
            command(['xcodebuild', '-project', str(REPO / 'Crypton.xcodeproj'), '-scheme', 'Crypton', '-configuration', 'Debug' if a.fixture else 'Release',
                     '-destination', 'generic/platform=iOS Simulator', '-derivedDataPath', str(build), 'ARCHS=arm64', 'ONLY_ACTIVE_ARCH=YES', 'CODE_SIGN_IDENTITY=-',
                     'build'], stdout=log, stderr=subprocess.STDOUT)
        templates = [None]
        products = build / 'Build/Products' / ('Debug-iphonesimulator' if a.fixture else 'Release-iphonesimulator')
        active_profiles = profiles[1:] if a.verify_run else profiles
        for device in dict.fromkeys(p['device'] for p in active_profiles):
            if available[device]['state'] != 'Booted': sim('boot', device)
            sim('bootstatus', device, '-b', stdout=subprocess.DEVNULL)
        run.start_capture()
        run.start_claim_server()
        if a.fixture:
            server_log = (run.folder / 'fixture.log').open('w')
            server = subprocess.Popen(['node', str(REPO / 'scripts/messagebox-fixture.cjs'), str(a.sdk_root)], cwd=REPO, stdout=server_log, stderr=subprocess.STDOUT)
            # Fixture readiness is checked from its explicit ready event, not a fixed startup delay.
            deadline = time.monotonic()+15
            while 'MessageBox fixture ready' not in (run.folder / 'fixture.log').read_text():
                if server.poll() is not None or time.monotonic()>deadline: raise RuntimeError('Disposable fixture failed to start')
                time.sleep(.1)
        for device in dict.fromkeys(p['device'] for p in active_profiles):
            if not a.fixture: sim('get_app_container', device, 'app.metanet.explorer', 'app', stdout=subprocess.DEVNULL)
            sim('install', device, str(products / 'Crypton.app'))

        if not a.verify_run:
            run.send_and_verify(templates[0])
        else:
            run.phase(templates[0], 'receive', profiles[1])
    except (Exception, KeyboardInterrupt) as e:
        run.state['error'] = str(e) or 'Interrupted'
        if run.state['status'] == 'sending': run.state['status'] = 'needs_recovery'
        elif run.state['status'] not in ['accepted','failed_before_payment','needs_recovery']: run.state['status'] = 'failed'
        print('Stopped:', run.state['error'], file=sys.stderr)
    finally:
        if server:
            server.terminate()
            try: server.wait(timeout=5)
            except subprocess.TimeoutExpired: server.kill()
            server_log.close()
        run.finish()
    if a.verify_run and run.state['status'] == 'complete':
        original_path = a.verify_run/'result.json'; original = json.loads(original_path.read_text())
        original.update(previous_status=original['status'],status='recipient_verified',message_id=a.message_id,
                        recipient_verification=str(run.folder),sender_receipt='unconfirmed')
        write(original_path,original)
    return 0 if run.state['status'] in ['complete','recipient_verified'] else 1


if __name__ == '__main__':
    sys.exit(main())
