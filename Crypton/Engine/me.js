'use strict';
const statusText = document.getElementById('status'), returnLink = document.getElementById('return');
const sent = new Set(), received = new Set();
const allowed = new Set(['isAuthenticated','waitForAuthentication','getPublicKey','getNetwork','encrypt','decrypt','createHmac','verifyHmac','createSignature','verifySignature','createAction','listActions','discoverByAttributes','discoverByIdentityKey']);
let current = null, stopped = false, returning = false, saving = false, returnAttempts = 0, pendingResponse = null;
const pageID = crypto.randomUUID();
const visible = () => !document.hidden;
function returnToApp() {
  if (!visible() || (current && !saving && !pendingResponse) || returning || returnAttempts >= 8) return;
  returning = true; returnAttempts++;
  // Updated ME validates this callback against UIKit's attributed source app and
  // refuses to leave while a native wallet prompt is active. No result is in it.
  window.ReactNativeWebView?.postMessage(JSON.stringify({type:'CRYPTON_RETURN',callback:returnLink.href}));
  // Native ME owns app switching. A delayed location.href fallback can navigate
  // an obsolete localhost page or interrupt the next payment/signature prompt.
}
document.addEventListener?.('visibilitychange', () => {
  if (!visible()) return;
  returning=false; returnAttempts=0;
  if (pendingResponse && !saving) { returning=false; returnAttempts=0; void saveResponse(); }
  else if (stopped && !returning && !returnLink.hidden) returnToApp();
});
returnLink.addEventListener('click', event => {
  event.preventDefault(); if (current && !pendingResponse) return;
  returning=false; returnAttempts=0; returnToApp();
  if (pendingResponse && !saving) void saveResponse();
});
async function boundedFetch(path, options = {}) {
  const controller = new AbortController(), timer = setTimeout(()=>controller.abort(),4000);
  try { return await fetch(path,{...options,signal:controller.signal}); } finally { clearTimeout(timer); }
}
window.addEventListener('message', async event => {
  if (event.source !== window && event.source !== null) return;
  let response;
  try { response = typeof event.data === 'string' ? JSON.parse(event.data) : event.data; } catch { return; }
  if (response?.type === 'CRYPTON_RETURN_STATUS') {
    if (!response.accepted) { returning=false; if (visible()) setTimeout(returnToApp,500); }
    else if (pendingResponse && !saving) void saveResponse();
    return;
  }
  if (!response || response.type !== 'CWI' || response.isInvocation !== false || response.id !== current) return;
  // ME posts AND injects each response. Claim it before the first await so the
  // second channel cannot start a second save/recovery loop for the same UUID.
  if (received.has(response.id)) return;
  received.add(response.id);
  // The wallet has finished. If iOS suspended Crypton during a long approval,
  // foreground it and retry this SAME result, never re-invoke the wallet method.
  pendingResponse = response;
  await saveResponse();
});
async function saveResponse() {
  if (saving || !pendingResponse) return;
  const response = pendingResponse, requestID = response.id; saving = true;
  for (let attempt=0; attempt<8; attempt++) {
    try {
      const saved = await boundedFetch('result',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(response)});
      if (!saved.ok) throw Error();
      if (current === requestID) current = null;
      pendingResponse = null; saving = false;
      if (stopped) { stopped = false; void poll(); }
      return;
    } catch {
      statusText.textContent = 'Approval finished. Returning to Crypton to save the result…';
      returnToApp();
      await new Promise(resolve=>setTimeout(resolve,300));
    }
  }
  // Keep the terminal result in memory after bounded retries. Closing a prompt
  // or returning manually can resume the SAME save; never re-invoke the wallet.
  saving = false; stopped = true; returnLink.hidden = false;
  statusText.textContent = 'The wallet result is retained on this page. Return to Crypton to save it; do not pay again.';
}
const labels = {
  waitForAuthentication:'Unlock ME to connect Crypton.',
  getPublicKey:'Checking the selected wallet identity…',
  createAction:'Review the payment total in ME. Keep this page open until the payment prompt closes.',
  listActions:'Checking the saved payment in wallet history…',
  createSignature:'Authenticating with MessageBox…', verifySignature:'Verifying MessageBox authentication…'
};
async function poll() {
  if (stopped) return;
  // The native server reserves each command for its owning page. Dispatch it
  // once and await the result acknowledgement before retrieving another command.
  if (current || saving || returning || !visible()) { setTimeout(poll,150); return; }
  try {
    const response = await boundedFetch('next',{cache:'no-store',headers:{'X-Crypton-Page':pageID}});
    if (!response.ok) throw Error();
    const {command,finished,foregroundRequired} = await response.json();
    returnLink.hidden = !((finished || foregroundRequired) && !current);
    if (foregroundRequired && !current) {
      statusText.textContent = 'Returning to Crypton for MessageBox networking…';
      returnToApp();
    } else if (finished && !current) {
      stopped = true;
      statusText.textContent = 'Operation finished. Returning to Crypton…';
      returnToApp();
    } else if (command && !sent.has(command.id) && !current) {
      if (!allowed.has(command.call) || !window.ReactNativeWebView) { statusText.textContent='Open this request in Metanet Explorer on this iPhone.'; stopped=true; }
      else {
        statusText.textContent=labels[command.call] || 'Preparing encrypted messages. Review any grouped permissions in ME.';
        sent.add(command.id); current=command.id;
        const invoke = () => {
          if (stopped || current !== command.id) return;
          if (returning || !visible()) { setTimeout(invoke,150); return; }
          returning=false; returnAttempts=0;
          window.ReactNativeWebView.postMessage(JSON.stringify(command));
        };
        invoke();
      }
    }
  } catch {
    // A failed idle read may already have claimed the next command. Stay here
    // and retrieve it with the SAME page identity; a return races wallet dispatch.
    if (!current) statusText.textContent='Reconnecting to Crypton’s local wallet bridge…';
  }
  if (!stopped) setTimeout(poll,150);
}
poll();
