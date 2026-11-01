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
            run.state={};run.events=[];run.state_lock=threading.RLock()
            with patch.object(send.subprocess,'check_output',return_value=str(Path(folder)/'container')+'\n'),patch.object(send,'sim',side_effect=RuntimeError('Launch failed')):
                with self.assertRaisesRegex(RuntimeError,'Launch failed'):run.phase(None,'receive',run.profiles[1])
            self.assertFalse((Path(folder)/'container/Library/Application Support/ScriptedRuns'/run.plan['run_id']/'request.json').exists())
    def test_another_run_cannot_inject_acceptance(self):
        run=send.Run.__new__(send.Run);run.plan={'run_id':'expected'}
        with self.assertRaisesRegex(RuntimeError,'Unexpected run identity'):
            run.event({'run_id':'other','stage':'accepted'})

if __name__=='__main__':unittest.main()
