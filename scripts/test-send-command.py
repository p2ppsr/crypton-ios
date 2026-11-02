#!/usr/bin/env python3
"""Host-only contract tests. No simulator, UI or wallet actions."""
import importlib.util
from pathlib import Path
import base64
import json
import plistlib
import tempfile
import types
import unittest
import urllib.request
import urllib.error

spec = importlib.util.spec_from_file_location('send_command', Path(__file__).with_name('send-message.py'))
send = importlib.util.module_from_spec(spec); spec.loader.exec_module(send)

class Contract(unittest.TestCase):
    def setUp(self):
        from unittest.mock import patch
        self.focus=patch.object(send.Run,'focus_window').start()
        self.video=patch.object(send.Run,'start_video',return_value=None).start()
        self.addCleanup(patch.stopall)
    def test_both_launch_modes_check_both_wallets_before_sending(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as folder,patch.object(send,'ARTIFACTS',Path(folder)):
            for kind in ['cold','warm']:
                run=send.Run(types.SimpleNamespace(text='Readiness',fixture=False,timeout=30,launch_kind=kind),[{'device':'sender'},{'device':'peer'}])
                calls=[]
                with patch.object(run,'phase',side_effect=lambda template,role,profile:calls.append((role,profile['device']))):run.send_and_verify(None)
                self.assertEqual(calls,[('preflight','sender'),('preflight','peer'),('send','sender'),('receive','peer'),('reopen','peer')])
    def test_warm_launch_uses_existing_runtime_and_queues_only_after_clock_start(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as folder,patch.object(send,'ARTIFACTS',Path(folder)):
            run=send.Run(types.SimpleNamespace(text='Warm',fixture=False,timeout=30,launch_kind='warm'),[{'device':'sender','walletIdentity':'pinned-sender'},{'device':'peer'}])
            root=Path(folder)/'container/Library/Application Support/ScriptedRuns'
            root.mkdir(parents=True)
            send.write(root/'runtime.json',{'driver_version':2,'idle':True,'runtime_id':'same-process','engine_id':'same-engine'})
            def launch(*args,**kwargs):
                self.assertNotIn('--terminate-running-process',args)
                self.assertEqual(run.events[-1]['stage'],'launch_requested')
                self.assertEqual((root/'pending.txt').read_text(),run.plan['run_id'])
                plan=json.loads((root/run.plan['run_id']/'request.json').read_text())
                self.assertEqual(plan['expected_runtime_id'],'same-process');self.assertEqual(plan['expected_engine_id'],'same-engine')
                self.assertEqual(plan['sender_identity'],'pinned-sender')
                (root/run.plan['run_id']/'events.jsonl').write_text(''.join(json.dumps({'run_id':run.plan['run_id'],'role':'send','stage':stage,'utc':'now','message_id':'a'*64})+'\n' for stage in ['accepted','phase_complete']))
            with patch.object(run,'check_cpu'),patch.object(send.subprocess,'check_output',return_value=str(Path(folder)/'container')+'\n'),patch.object(send,'sim',side_effect=launch):run.phase(None,'send',run.profiles[0])
            self.assertFalse((root/'pending.txt').exists())
    def test_missing_warm_engine_cannot_fall_back_to_cold_send(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as folder,patch.object(send,'ARTIFACTS',Path(folder)):
            run=send.Run(types.SimpleNamespace(text='Warm',fixture=False,timeout=30,launch_kind='warm'),[{'device':'sender'},{'device':'peer'}])
            root=Path(folder)/'container/Library/Application Support/ScriptedRuns'
            root.mkdir(parents=True)
            send.write(root/'runtime.json',{'driver_version':2,'idle':True,'runtime_id':'same-process','engine_id':''})
            with patch.object(run,'check_cpu'),patch.object(send.subprocess,'check_output',return_value=str(Path(folder)/'container')+'\n'),patch.object(send,'sim') as launch:
                with self.assertRaisesRegex(RuntimeError,'Warm launch requires'):run.phase(None,'send',run.profiles[0])
                launch.assert_not_called()
            self.assertFalse((run.folder/'send-claimed').exists())
    def test_new_timing_uses_one_host_clock_and_conservative_same_wallet_pay_interval(self):
        events=[{'role':'send','stage':'launch_requested','utc':'2026-11-02T00:00:00Z','host_mono_ns':1000000000},
                {'role':'send','stage':'pay_visible','utc':'2026-11-02T00:00:05Z','review_id':'own','params':{'capture_boundary':'caller_entry','capture_mono_ms':5000}},
                {'role':'send','stage':'accepted','utc':'2026-11-02T01:00:00Z','host_observed_ns':22000000000},
                {'role':'receive','stage':'retained','utc':'2026-11-01T23:00:00Z','host_observed_ns':26000000000}]
        wallet=[{'stage':'wallet_payment_review_approved','device':'sender','utc':'2026-11-02T00:00:07Z','params':{'review_id':'own','capture_boundary':'caller_entry','capture_mono_ms':7000,'approval':'once'}}]
        r=send.target_timing(events,wallet,sender_device='sender')
        self.assertEqual(r['total_ms'],21000);self.assertEqual(r['pay_wait_ms'],1998);self.assertEqual(r['adjusted_ms'],19002)
        self.assertEqual(send.target_timing(events,wallet,sender_device='sender',end_to_end=True)['total_ms'],25000)
        wallet[0]['params']['capture_mono_ms']=4999
        self.assertEqual(send.target_timing(events,wallet,sender_device='sender')['status'],'unavailable')
        wallet[0]['params'].pop('capture_mono_ms')
        self.assertEqual(send.target_timing(events,wallet,sender_device='sender')['status'],'unavailable')
    def test_sender_clip_starts_after_cpu_gate_and_stops_at_phase_completion(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as folder,patch.object(send,'ARTIFACTS',Path(folder)):
            run=send.Run(types.SimpleNamespace(text='Recorded',fixture=True,timeout=30),[{'device':'sender'},{'device':'peer'}])
            order=[]
            def launch(*args,**kwargs):
                order.append('launch')
                self.assertEqual(run.events[-1]['stage'],'launch_requested')
                path=Path(folder)/'container/Library/Application Support/ScriptedRuns'/run.plan['run_id']/'events.jsonl'
                path.write_text(''.join(json.dumps({'run_id':run.plan['run_id'],'role':'send','stage':stage,'utc':'now','message_id':'a'*64})+'\n' for stage in ['accepted','phase_complete']))
            with patch.object(run,'check_cpu',side_effect=lambda stage:order.append('cpu')),patch.object(run,'start_video',side_effect=lambda profile,purpose:order.append(purpose+'_video') or 'handle'),patch.object(run,'stop_video',side_effect=lambda handle:order.append('stop_video') or True),patch.object(send.subprocess,'check_output',return_value=str(Path(folder)/'container')+'\n'),patch.object(send,'sim',side_effect=launch):
                run.phase(None,'send',run.profiles[0])
            self.assertEqual(order,['cpu','send_video','launch','stop_video'])
    def test_initial_capture_keeps_diagnostics_continuous_without_early_video(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as folder,patch.object(send,'ARTIFACTS',Path(folder)):
            for verify in [False,True]:
                run=send.Run(types.SimpleNamespace(text='Recorded',fixture=False,timeout=30),[{'device':'sender'},{'device':'peer'}])
                if verify:run.args.verify_run=Path('original')
                with patch.object(run,'start_video') as video,patch.object(send.subprocess,'Popen') as process,patch.object(send.time,'sleep'):
                    process.return_value.poll.return_value=None
                    run.start_capture()
                    devices=[call.args[0][3] for call in process.call_args_list]
                    self.assertEqual(devices,['peer'] if verify else ['sender','peer'])
                    video.assert_not_called()
                for _,output in run.logs:output.close()
    def test_cpu_gate_requires_three_quiet_intervals_and_ignores_boot_average(self):
        def output(samples):
            return '\n'.join(f'Load Avg: {load}, 20.0, 30.0\nCPU usage: 20% user, 10% sys, {idle}% idle' for load,idle in samples)
        report=send.cpu_report(output([(50,0),(8,70),(9,65),(8,72)]),16)
        self.assertTrue(report['normal']);self.assertEqual(len(report['samples']),3)
        for samples in [[(1,99),(8,70),(9,49),(8,72)],[(1,99),(8,70),(17,65),(8,72)],[(1,99),(8,70),(9,65)]]:
            self.assertFalse(send.cpu_report(output(samples),16)['normal'])
        self.assertFalse(send.cpu_report('unrecognized sampler output',16)['normal'])
    def test_busy_cpu_prevents_send_launch_and_retains_its_report(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as folder,patch.object(send,'ARTIFACTS',Path(folder)):
            run=send.Run(types.SimpleNamespace(text='Test',fixture=False,timeout=60,cpu_wait=0),[{'device':'sender'},{'device':'receiver'}])
            with patch.object(send,'sample_cpu',return_value={'normal':False,'samples':[]}),patch.object(send.subprocess,'check_output') as read,patch.object(send,'sim') as launch:
                with self.assertRaises(send.CPUNotReady):run.phase(None,'send',run.profiles[0])
                read.assert_not_called();launch.assert_not_called()
            self.assertFalse((run.folder/'send-claimed').exists())
            self.assertFalse(json.loads((run.folder/'cpu-load.json').read_text())[0]['normal'])
    def test_cpu_gate_waits_for_headroom_and_preserves_all_samples(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as folder,patch.object(send,'ARTIFACTS',Path(folder)):
            run=send.Run(types.SimpleNamespace(text='Test',fixture=False,timeout=60,cpu_wait=30),[{'device':'sender'},{'device':'receiver'}])
            with patch.object(send,'sample_cpu',side_effect=[{'normal':False,'utc':'first','samples':[]},{'normal':True,'utc':'second','samples':[]}]),patch.object(send.time,'monotonic',side_effect=[0,1]):
                run.check_cpu('before_send_launch')
            reports=json.loads((run.folder/'cpu-load.json').read_text())
            self.assertEqual([r['normal'] for r in reports],[False,True])
            self.assertFalse((run.folder/'send-claimed').exists())
    def test_host_deadline_stops_only_the_scripted_app_and_cannot_retry_send(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as folder,patch.object(send,'ARTIFACTS',Path(folder)):
            run=send.Run(types.SimpleNamespace(text='Test',fixture=False,timeout=30),[{'device':'sender'},{'device':'receiver'}])
            with patch.object(run,'check_cpu'),patch.object(send.subprocess,'check_output',return_value=str(Path(folder)/'container')+'\n'),patch.object(send,'sim') as launch,patch.object(send.time,'monotonic',side_effect=[0,100]),patch.object(send.subprocess,'run',return_value=types.SimpleNamespace(returncode=0)) as stop:
                with self.assertRaisesRegex(RuntimeError,'phase deadline'):run.phase(None,'send',run.profiles[0])
                self.assertEqual(launch.call_count,1,'No replay or recovery launch after the deadline')
                stop.assert_called_once_with(['xcrun','simctl','terminate','sender',send.APP],capture_output=True,text=True,timeout=10)
            self.assertFalse((run.folder/'send-claimed').exists())
            self.assertEqual(run.events[-1]['stage'],'controller_app_stopped')
    def test_sender_target_and_separate_end_to_end_exclude_only_exact_pay_wait(self):
        def event(stage,role,seconds,**extra):
            return {'stage':stage,'role':role,'utc':f'2026-11-02T00:00:{seconds:02d}.000Z',**extra}
        events=[event('launch_requested','send',0),event('send_tapped','send',2),
                event('pay_visible','send',8,review_id='own'),event('accepted','send',19),event('retained','receive',24)]
        wallet=[event('wallet_payment_review_approved','send',9,device='peer',params={'review_id':'own'}),
                event('wallet_payment_review_approved','send',10,device='sender',params={'review_id':'other'}),
                event('wallet_payment_review_approved','send',14,device='sender',params={'review_id':'own'})]
        result=send.target_timing(events,wallet,sender_device='sender')
        self.assertEqual(result['total_ms'],19000);self.assertEqual(result['pay_wait_ms'],6000)
        self.assertEqual(result['adjusted_ms'],13000);self.assertTrue(result['met'])
        whole=send.target_timing(events,wallet,sender_device='sender',end_to_end=True)
        self.assertEqual(whole['adjusted_ms'],18000);self.assertIsNone(whole['target_ms']);self.assertIsNone(whole['met'])
        self.assertEqual(send.target_timing(events,[],sender_device='sender')['status'],'unavailable')
        self.assertEqual(send.target_timing(events[:-1],wallet,sender_device='sender')['status'],'measured')
        self.assertEqual(send.target_timing(events[:-1],wallet,sender_device='sender',end_to_end=True)['status'],'unavailable')
        fixture=send.target_timing(events,[],fixture=True)
        self.assertEqual(fixture['adjusted_ms'],19000);self.assertEqual(fixture['pay_wait_ms'],0)
        events[2]['review_id']=None
        self.assertEqual(send.target_timing(events,wallet,sender_device='sender')['status'],'unavailable','Unbound approval cannot become deducted wait')
        opened=event('wallet_payment_review_opened','send',8,device='sender',params={'review_id':'own'})
        self.assertEqual(send.target_timing(events,[opened,*wallet],sender_device='sender')['adjusted_ms'],13000)
        self.assertEqual(send.target_timing(events,[opened,opened,*wallet],sender_device='sender')['status'],'unavailable','Ambiguous opened reviews cannot bind a modal')
        events[2]['review_id']='own'
        events[3]['utc']='2026-11-02T00:00:30.000Z'
        late=send.target_timing(events,wallet,sender_device='sender')
        self.assertEqual(late['total_ms'],30000);self.assertFalse(late['met'],'Parallel receipt work must finish inside the target too')
        unconfirmed=send.target_timing([e for e in events if e['stage']!='accepted'],wallet,sender_device='sender')
        self.assertEqual(unconfirmed['status'],'unavailable','Missing sender receipt cannot satisfy the target')
        peer=send.target_timing([e for e in events if e['stage']!='accepted'],wallet,sender_device='sender',end_to_end=True)
        self.assertEqual(peer['adjusted_ms'],18000);self.assertEqual(peer['sender_receipt'],'unconfirmed')
    def test_message_and_reports_share_one_run_marker_and_composition_time(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as folder,patch.object(send,'ARTIFACTS',Path(folder)):
            args=types.SimpleNamespace(text='Literal café 🌍 "quoted"',fixture=True,timeout=300)
            run=send.Run(args,[{'device':'fake-one'},{'device':'fake-two'}])
            self.assertTrue(run.plan['message'].startswith(args.text+'\n\n'))
            self.assertTrue(run.plan['message'].endswith('Run: '+run.plan['run_id']))
            self.assertIn('Composed: '+run.plan['composed_at'],run.plan['message'])
            self.assertEqual(run.state['run_id'],run.plan['run_id'])
    def test_verification_reuses_exact_text_and_has_no_send_capability(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as folder,patch.object(send,'ARTIFACTS',Path(folder)):
            profiles=[{'device':'sender'},{'device':'receiver'}]
            original=send.Run(types.SimpleNamespace(text='Already paid',fixture=False,timeout=300),profiles)
            original.plan.update(claim_url='http://127.0.0.1:1234/claim',claim_token='old-secret')
            send.write(original.folder/'request.json',original.plan)
            args=types.SimpleNamespace(text='',fixture=False,timeout=120,verify_run=original.folder,message_id='a'*64)
            verified=send.Run(args,profiles)
            self.assertEqual(verified.plan['message'],original.plan['message'])
            self.assertEqual(verified.plan['run_id'],original.plan['run_id'])
            self.assertNotIn('claim_token',verified.plan)
            self.assertNotIn('claim_url',verified.plan)
            with patch.object(send.subprocess,'Popen') as process:
                with self.assertRaisesRegex(RuntimeError,'cannot enter a sending phase'):
                    verified.phase(Path('unused'),'send',profiles[0])
                process.assert_not_called()
    def test_native_watch_requires_a_matching_started_operation(self):
        from datetime import datetime
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'pipeline.jsonl'
            events=[('00:00:00','a','start.runCrypto'),('00:00:01','a','complete'),('00:00:02','b','start.runInbox'),('00:00:03','b','complete')]
            path.write_text('\n'.join(json.dumps({'timestamp':'2026-11-01 '+at+'.000000+0000','eventMessage':'Crypton pipeline '+op+' '+stage+' 1.0ms'}) for at,op,stage in events))
            after=datetime.fromisoformat('2026-11-01T00:00:01+00:00').timestamp()
            self.assertEqual(send.native_status(path,after,'runInbox'),'complete')
            self.assertEqual(send.native_status(path,after,'runDelivery'),'waiting')
            self.assertEqual(send.native_status(path,after+10,'runInbox'),'waiting')
    def test_verification_watch_server_cannot_grant_send(self):
        import threading
        with tempfile.TemporaryDirectory() as folder:
            run=send.Run.__new__(send.Run);run.folder=Path(folder);run.state_lock=threading.RLock()
            run.args=types.SimpleNamespace(verify_run=Path('old-run'));run.state={'status':'verifying'};run.plan={'run_id':'test'}
            run.start_claim_server()
            try:
                self.assertNotIn('claim_token',run.plan)
                req=urllib.request.Request(run.plan['watch_url'].replace('/watch','/claim'),data=b'',method='POST',headers={'Authorization':'Bearer '+run.plan['watch_token'],'X-Crypton-Run':'test'})
                with self.assertRaises(urllib.error.HTTPError) as error:urllib.request.urlopen(req,timeout=3)
                self.assertEqual(error.exception.code,403);error.exception.close()
                self.assertFalse((run.folder/'send-claimed').exists())
                self.assertEqual(run.state['status'],'verifying')
            finally:run.claim_server.shutdown();run.claim_server.server_close()
    def test_review_recovery_has_no_send_claim_or_other_phase(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as folder,patch.object(send,'ARTIFACTS',Path(folder)):
            run=send.Run(types.SimpleNamespace(text='',fixture=False,timeout=60,recovery_only=True),[{'device':'sender'},{'device':'receiver'}])
            run.state['mode']='recover_review'
            run.start_claim_server()
            try:
                self.assertNotIn('claim_token',run.plan)
                req=urllib.request.Request(run.plan['watch_url'].replace('/watch','/claim'),data=b'',method='POST',headers={'Authorization':'Bearer '+run.plan['watch_token'],'X-Crypton-Run':run.plan['run_id']})
                with self.assertRaises(urllib.error.HTTPError) as error:urllib.request.urlopen(req,timeout=3)
                self.assertEqual(error.exception.code,403);error.exception.close()
                with patch.object(send.subprocess,'check_output') as process:
                    for role in ['preflight','send','receive']:
                        with self.assertRaisesRegex(RuntimeError,'cannot enter another phase'):run.phase(None,role,run.profiles[0])
                    process.assert_not_called()
            finally:run.claim_server.shutdown();run.claim_server.server_close()
    def test_xctestrun_preserves_literal_text_and_selects_only_opt_in_test(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); template = root/'source.xctestrun'; target = root/'role.xctestrun'
            template.write_bytes(plistlib.dumps({'CryptonUITests':{'TestBundlePath':'__TESTHOST__/PlugIns/CryptonUITests.xctest','TestHostPath':'__TESTROOT__/Runner.app','UITargetAppPath':'__TESTROOT__/Crypton.app','TestingEnvironmentVariables':{'PATH':'__TESTROOT__/lib'}},'CryptonTests':{'Other':True}}))
            plan={'message':'café 🌍\n"quotes" $(literal) `literal`','run_id':'test','role':'send'}
            send.configure_test(template,target,plan)
            result=plistlib.loads(target.read_bytes())
            self.assertEqual(set(result),{'CryptonUITests','__xctestrun_metadata__'})
            t=result['CryptonUITests']
            self.assertEqual(json.loads(base64.b64decode(t['EnvironmentVariables']['CRYPTON_SEND_PLAN'])),plan)
            self.assertEqual(t['OnlyTestIdentifiers'],['CryptonSendRunTests/testDeterministicMessageFlow'])
            self.assertNotIn('UseDestinationArtifacts',t)
            self.assertEqual(t['TestHostPath'],str(root/'Runner.app'))
    def test_claim_is_single_use_and_wrong_token_cannot_consume_it(self):
        with tempfile.TemporaryDirectory() as folder:
            run=send.Run.__new__(send.Run)
            import threading
            run.state_lock=threading.RLock(); run.folder=Path(folder); run.state={'status':'preparing'}; run.plan={'run_id':'test'};run.claim_server=None
            run.start_claim_server()
            def claim(token):
                req=urllib.request.Request(run.plan['claim_url'],data=b'',headers={'Authorization':'Bearer '+token,'X-Crypton-Run':'test'},method='POST')
                try:
                    with urllib.request.urlopen(req,timeout=3) as response:return response.status
                except urllib.error.HTTPError as error:
                    code=error.code;error.close();return code
            try:
                self.assertEqual(claim('wrong'),403)
                self.assertFalse((run.folder/'send-claimed').exists())
                self.assertEqual(claim(run.plan['claim_token']),200)
                self.assertEqual(claim(run.plan['claim_token']),409)
                self.assertEqual(run.state['status'],'sending')
                self.assertTrue((run.folder/'send-claimed').exists())
            finally:run.claim_server.shutdown();run.claim_server.server_close()
    def test_a_claimed_send_cannot_be_cleared_by_a_restarted_runner(self):
        import threading
        with tempfile.TemporaryDirectory() as folder:
            run=send.Run.__new__(send.Run);run.plan={'run_id':'test'};run.folder=Path(folder)
            run.state_lock=threading.RLock();run.events=[];run.state={'status':'sending'}
            (run.folder/'send-claimed').touch()
            run.event({'run_id':'test','utc':'now','role':'send','stage':'failed','send_attempted':False})
            self.assertEqual(run.state['status'],'sending')
    def test_settled_unpaid_journal_proof_releases_only_pre_payment_failure(self):
        import threading
        with tempfile.TemporaryDirectory() as folder:
            run=send.Run.__new__(send.Run);run.plan={'run_id':'test'};run.folder=Path(folder)
            run.state_lock=threading.RLock();run.events=[];run.state={'status':'sending'}
            (run.folder/'send-claimed').touch()
            evidence={'run_id':'test','utc':'now','role':'send','stage':'failed','send_attempted':True,
                      'delivery_id':'43054422-2771-4052-a058-af93cc9c0314','delivery_state':'DRAFT','payment_not_requested':True}
            for changes in [{'payment_not_requested':False},{'delivery_state':'PAYMENT_REQUESTED'},{'delivery_id':''},{'role':'receive'}]:
                run.event({**evidence,**changes})
                self.assertEqual(run.state['status'],'sending')
            run.event(evidence)
            self.assertEqual(run.state['status'],'failed_before_payment')
            self.assertTrue(run.state['payment_not_requested'])
            run.state['status']='accepted'
            run.event(evidence)
            self.assertEqual(run.state['status'],'accepted')
    def test_recipient_fallback_requires_exact_settled_paid_submission_evidence(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as folder,patch.object(send,'ARTIFACTS',Path(folder)):
            run=send.Run(types.SimpleNamespace(text='Retained message',fixture=True,timeout=300),[{'device':'sender'},{'device':'peer'}])
            run.state['status']='sending'
            evidence={'run_id':run.plan['run_id'],'utc':'now','role':'send','stage':'failed','send_attempted':True,
                      'delivery_id':'43054422-2771-4052-a058-af93cc9c0314','delivery_state':'SUBMITTING','has_saved_payment':True,'message_id':'a'*64}
            for changes in [{'has_saved_payment':False},{'delivery_state':'PAYMENT_REQUESTED'},{'message_id':'bad'},{'delivery_id':'bad'},{'send_attempted':False}]:
                run.event({**evidence,**changes})
                self.assertFalse(run.state.get('verify_unconfirmed_submission',False))
                run.state['status']='sending'
            run.event(evidence)
            self.assertTrue(run.state['verify_unconfirmed_submission'])
            self.assertEqual(run.state['message_id'],'a'*64)
    def test_missing_sender_receipt_verifies_peer_without_another_send(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as folder,patch.object(send,'ARTIFACTS',Path(folder)):
            run=send.Run(types.SimpleNamespace(text='Already paid',fixture=True,timeout=300),[{'device':'sender'},{'device':'peer'}])
            phases=[]
            def phase(template,role,profile):
                phases.append(role)
                if role=='send':
                    run.state.update(verify_unconfirmed_submission=True,message_id='b'*64,sender_receipt='unconfirmed')
                    raise RuntimeError('Submission response lost')
                if role=='receive':
                    self.assertEqual(run.state['message_id'],'b'*64);run.state['status']='complete'
            with patch.object(run,'phase',side_effect=phase):run.send_and_verify(None)
            self.assertEqual(phases,['preflight','send','receive','reopen'])
            self.assertEqual(run.state['status'],'recipient_verified')
            self.assertEqual(run.state['sender_receipt'],'unconfirmed')
            self.assertEqual(run.state['sender_error'],'Submission response lost')
    def test_failed_recipient_fallback_keeps_payment_recovery_protection(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as folder,patch.object(send,'ARTIFACTS',Path(folder)):
            run=send.Run(types.SimpleNamespace(text='Already paid',fixture=True,timeout=300),[{'device':'sender'},{'device':'peer'}])
            phases=[]
            def phase(template,role,profile):
                phases.append(role)
                if role=='send':
                    run.state.update(verify_unconfirmed_submission=True,message_id='c'*64,sender_receipt='unconfirmed')
                    raise RuntimeError('Lost sender receipt')
                if role=='receive':raise RuntimeError('Peer unavailable')
            with patch.object(run,'phase',side_effect=phase):
                with self.assertRaisesRegex(RuntimeError,'Peer unavailable'):run.send_and_verify(None)
            self.assertEqual(phases,['preflight','send','receive'])
            self.assertEqual(run.state['status'],'needs_recovery')
    def test_unproven_submission_cannot_enter_recipient_fallback(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as folder,patch.object(send,'ARTIFACTS',Path(folder)):
            run=send.Run(types.SimpleNamespace(text='Unpaid',fixture=True,timeout=300),[{'device':'sender'},{'device':'peer'}])
            phases=[]
            def phase(template,role,profile):
                phases.append(role)
                if role=='send':raise RuntimeError('No submission evidence')
            with patch.object(run,'phase',side_effect=phase):
                with self.assertRaisesRegex(RuntimeError,'No submission evidence'):run.send_and_verify(None)
            self.assertEqual(phases,['preflight','send'])
    def test_receiver_waits_for_saved_sender_acceptance_not_payment(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as folder,patch.object(send,'ARTIFACTS',Path(folder)):
            run=send.Run(types.SimpleNamespace(text='Retained test',fixture=False,timeout=30),[{'device':'sender'},{'device':'peer'}])
            phases=[]
            def event(stage,role,**fields):run.event({'run_id':run.plan['run_id'],'utc':'now','stage':stage,'role':role,**fields})
            def phase(template,role,profile):
                phases.append(role)
                if role=='send':
                    run.state['status']='sending'
                    event('payment_saved','send',has_saved_payment=True,message_id='d'*64,delivery_id='43054422-2771-4052-a058-af93cc9c0314')
                    self.assertEqual(phases,['preflight','send'],'Payment cannot start the receiver')
                    with self.assertRaisesRegex(RuntimeError,'requires saved sender acceptance'):run.receiver_video_purpose()
                    event('accepted','send',message_id='d'*64)
                elif role=='receive':
                    self.assertEqual(run.receiver_video_purpose(),'receive')
                    event('retained','receive',message_id='d'*64)
            with patch.object(run,'phase',side_effect=phase):run.send_and_verify(None)
            self.assertEqual(phases,['preflight','send','receive','reopen'])
            self.assertEqual(run.state['status'],'complete');self.assertEqual(run.state['sender_receipt'],'confirmed')
    def test_unaccepted_receiver_cannot_start_video_or_launch(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as folder,patch.object(send,'ARTIFACTS',Path(folder)):
            run=send.Run(types.SimpleNamespace(text='Unconfirmed',fixture=False,timeout=30),[{'device':'sender'},{'device':'peer'}])
            with patch.object(run,'start_video') as video,patch.object(send,'sim') as launch,patch.object(send.subprocess,'check_output') as read:
                with self.assertRaisesRegex(RuntimeError,'requires saved sender acceptance'):run.phase(None,'receive',run.profiles[1])
                video.assert_not_called();launch.assert_not_called();read.assert_not_called()
            run.state.update(sender_receipt='confirmed',sender_status='accepted',message_id='a'*64)
            with self.assertRaises(RuntimeError):run.receiver_video_purpose()
    def test_missing_receipt_and_readonly_verification_have_distinct_video_labels(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as folder,patch.object(send,'ARTIFACTS',Path(folder)):
            run=send.Run(types.SimpleNamespace(text='Paid',fixture=False,timeout=30),[{'device':'sender'},{'device':'peer'}])
            run.state.update(sender_receipt='unconfirmed',sender_error='Lost response',message_id='a'*64)
            self.assertEqual(run.receiver_video_purpose(),'receipt-recovery')
            run.args.verify_run=Path('original')
            self.assertEqual(run.receiver_video_purpose(),'verification-only')
    def test_receiver_setup_clip_finishes_before_send_then_receive_video_precedes_launch(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as folder,patch.object(send,'ARTIFACTS',Path(folder)):
            run=send.Run(types.SimpleNamespace(text='Recorded',fixture=False,timeout=30),[{'device':'sender'},{'device':'peer'}])
            trace=[]
            def video(profile,purpose):trace.append(purpose+'_video');return purpose
            def launch(*args,**kwargs):
                role='receive' if 'receive_video' in trace else 'preflight'
                trace.append(role+'_launch')
                root=Path(folder)/'container/Library/Application Support/ScriptedRuns'/run.plan['run_id']
                stages=['retained','phase_complete'] if role=='receive' else ['preflight_complete','phase_complete']
                (root/'events.jsonl').write_text(''.join(json.dumps({'run_id':run.plan['run_id'],'role':role,'stage':stage,'utc':'now','elapsed_ms':0})+'\n' for stage in stages))
            with patch.object(run,'start_video',side_effect=video),patch.object(run,'stop_video',side_effect=lambda handle:trace.append(handle+'_stopped') or True),patch.object(send.subprocess,'check_output',return_value=str(Path(folder)/'container')+'\n'),patch.object(send,'sim',side_effect=launch):
                run.phase(None,'preflight',run.profiles[1])
                self.assertEqual(trace,['receiver-setup_video','preflight_launch','receiver-setup_stopped'])
                send.write(Path(folder)/'container/Library/Application Support/ScriptedRuns/runtime.json',{'driver_version':2,'idle':True,'runtime_id':'runtime','engine_id':'engine'})
                run.event({'run_id':run.plan['run_id'],'role':'send','stage':'accepted','message_id':'a'*64,'utc':'now'})
                run.phase(None,'receive',run.profiles[1])
            self.assertEqual(trace[-2:],['receive_video','receive_launch'])
    def test_recorder_failure_prevents_receiver_launch(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as folder,patch.object(send,'ARTIFACTS',Path(folder)):
            run=send.Run(types.SimpleNamespace(text='Paid',fixture=False,timeout=30),[{'device':'sender'},{'device':'peer'}])
            run.event({'run_id':run.plan['run_id'],'role':'send','stage':'accepted','message_id':'a'*64,'utc':'now'})
            with patch.object(run,'start_video',side_effect=RuntimeError('Recording did not start')),patch.object(send,'sim') as launch,patch.object(send.subprocess,'check_output') as read:
                with self.assertRaisesRegex(RuntimeError,'Recording did not start'):run.phase(None,'receive',run.profiles[1])
                launch.assert_not_called();read.assert_not_called()
    def test_single_device_fixture_never_launches_receiver_over_its_sender(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as folder,patch.object(send,'ARTIFACTS',Path(folder)):
            run=send.Run(types.SimpleNamespace(text='One device',fixture=True,timeout=30),[{'device':'same'},{'device':'same'}])
            phases=[]
            def phase(template,role,profile):
                phases.append(role)
                if role=='send':
                    run.state['status']='sending'
                    run.event({'run_id':run.plan['run_id'],'utc':'now','role':'send','stage':'payment_saved','has_saved_payment':True,'message_id':'e'*64,'delivery_id':'43054422-2771-4052-a058-af93cc9c0314'})
                    with self.assertRaises(RuntimeError):run.receiver_video_purpose()
                    run.event({'run_id':run.plan['run_id'],'utc':'now','role':'send','stage':'accepted','message_id':'e'*64})
                elif role=='receive':run.state['status']='complete'
            with patch.object(run,'phase',side_effect=phase):run.send_and_verify(None)
            self.assertEqual(phases,['preflight','send','receive','reopen'])
    def test_pre_send_failure_without_a_claim_does_not_block_a_new_run(self):
        import threading
        with tempfile.TemporaryDirectory() as folder:
            run=send.Run.__new__(send.Run);run.plan={'run_id':'test'};run.folder=Path(folder)
            run.state_lock=threading.RLock();run.events=[];run.state={'status':'sending'}
            run.event({'run_id':'test','utc':'now','role':'send','stage':'failed','send_attempted':False})
            self.assertEqual(run.state['status'],'failed')
    def test_empty_successful_xctest_is_not_a_completed_phase(self):
        import io
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as folder:
            run=send.Run.__new__(send.Run);run.folder=Path(folder);run.plan={'run_id':'test'}
            run.profiles=[{'device':'fake-simulator'},{'device':'fake-simulator'}]
            run.args=types.SimpleNamespace(timeout=30);run.state={};run.events=[]
            process=types.SimpleNamespace(stdout=io.StringIO(''),wait=lambda timeout=None:0)
            with patch.object(send,'configure_test'),patch.object(send.subprocess,'Popen',return_value=process):
                with self.assertRaisesRegex(RuntimeError,'without the required preflight_complete'):
                    run.phase_xctest(Path('unused'),'preflight',run.profiles[0])
    def test_failed_native_launch_removes_transient_plaintext_plan(self):
        import subprocess,threading
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as folder:
            run=send.Run.__new__(send.Run);run.folder=Path(folder);run.plan={'run_id':'11111111-1111-1111-1111-111111111111'}
            run.profiles=[{'device':'sender'},{'device':'receiver'}];run.args=types.SimpleNamespace(timeout=30,fixture=False)
            run.state={'sender_receipt':'unconfirmed','sender_error':'Lost response','message_id':'a'*64};run.events=[];run.state_lock=threading.RLock()
            run.args.fixture=True
            with patch.object(run,'start_video'),patch.object(send.subprocess,'check_output',return_value=str(Path(folder)/'container')+'\n'),patch.object(send,'sim',side_effect=RuntimeError('Launch failed')):
                with self.assertRaisesRegex(RuntimeError,'Launch failed'):run.phase(None,'receive',run.profiles[1])
            self.assertFalse((Path(folder)/'container/Library/Application Support/ScriptedRuns'/run.plan['run_id']/'request.json').exists())
    def test_another_run_cannot_inject_acceptance(self):
        run=send.Run.__new__(send.Run);run.plan={'run_id':'expected'}
        with self.assertRaisesRegex(RuntimeError,'Unexpected run identity'):
            run.event({'run_id':'other','stage':'accepted'})

if __name__=='__main__':unittest.main()
