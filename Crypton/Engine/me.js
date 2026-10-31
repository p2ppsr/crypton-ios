'use strict';
const statusText = document.getElementById('status'), returnLink = document.getElementById('return');
const sent = new Set();
const allowed = new Set(['isAuthenticated','waitForAuthentication','getPublicKey','getNetwork','encrypt','decrypt','createHmac','verifyHmac','createSignature','verifySignature','createAction','listActions','discoverByAttributes','discoverByIdentityKey']);
let current = null, stopped = false;
window.addEventListener('message', async event => {
  if (event.source !== window && event.source !== null) return;
  let response;
  try { response = typeof event.data === 'string' ? JSON.parse(event.data) : event.data; } catch { return; }
  if (!response || response.type !== 'CWI' || response.isInvocation !== false || response.id !== current) return;
  current = null;
  try { const saved = await fetch('result', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(response)});
    if (!saved.ok) throw Error(); }
  catch { statusText.textContent = 'Connection interrupted. Return to Crypton and retry.'; }
});
async function poll() {
  if (stopped) return;
  try {
    const response = await fetch('next', {cache:'no-store'});
    if (!response.ok) throw Error();
    const {command, finished} = await response.json();
    returnLink.hidden = !finished;
    statusText.textContent = finished ? 'Request finished. Return to Crypton to see the result. If the link does not open, switch back to Crypton using the app switcher.' : command?.call === 'waitForAuthentication' ? 'Waiting for ME to unlock and finish loading your wallet…' : 'Review and approve the Crypton request in ME.';
    if (command && !sent.has(command.id)) {
      if (!allowed.has(command.call) || !window.ReactNativeWebView) {
        statusText.textContent = 'Open this request in Metanet Explorer on this iPhone.';
      } else {
        sent.add(command.id); current = command.id;
        window.ReactNativeWebView.postMessage(JSON.stringify(command));
      }
    }
  } catch { stopped = true; returnLink.hidden = false; statusText.textContent = 'Connection closed. Return to Crypton.'; }
  if (!stopped) setTimeout(poll, 300);
}
poll();
