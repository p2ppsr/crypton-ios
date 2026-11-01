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
                    run.phase(Path('unused'),'preflight',run.profiles[0])
    def test_another_run_cannot_inject_acceptance(self):
        run=send.Run.__new__(send.Run);run.plan={'run_id':'expected'}
        with self.assertRaisesRegex(RuntimeError,'Unexpected run identity'):
            run.event({'run_id':'other','stage':'accepted'})

if __name__=='__main__':unittest.main()
