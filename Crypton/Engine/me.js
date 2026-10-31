'use strict';
const statusText = document.getElementById('status'), returnLink = document.getElementById('return');
const sent = new Set(), received = new Set();
const allowed = new Set(['isAuthenticated','waitForAuthentication','getPublicKey','getNetwork','encrypt','decrypt','createHmac','verifyHmac','createSignature','verifySignature','createAction','listActions','discoverByAttributes','discoverByIdentityKey']);
let current = null, stopped = false, returning = false, returnTimer, returnAttempts = 0;
function returnToApp() {
  if (current || returning || returnAttempts >= 8) return;
  returning = true; returnAttempts++;
  // Updated ME validates this callback against UIKit's attributed source app and
  // refuses to leave while a native wallet prompt is active. No result is in it.
  window.ReactNativeWebView?.postMessage(JSON.stringify({type:'CRYPTON_RETURN',callback:returnLink.href}));
  returnTimer = setTimeout(()=>{ location.href=returnLink.href; },1500);
}
returnLink.addEventListener('click', event => { event.preventDefault(); if (current) return; returning=false; returnAttempts=0; returnToApp(); });
async function boundedFetch(path, options = {}) {
  const controller = new AbortController(), timer = setTimeout(()=>controller.abort(),4000);
  try { return await fetch(path,{...options,signal:controller.signal}); } finally { clearTimeout(timer); }
}
window.addEventListener('message', async event => {
  if (event.source !== window && event.source !== null) return;
  let response;
  try { response = typeof event.data === 'string' ? JSON.parse(event.data) : event.data; } catch { return; }
  if (response?.type === 'CRYPTON_RETURN_STATUS') {
    clearTimeout(returnTimer);
    if (!response.accepted) { returning=false; setTimeout(returnToApp,500); }
    return;
  }
  if (!response || response.type !== 'CWI' || response.isInvocation !== false || response.id !== current) return;
  // ME posts AND injects each response. Claim it before the first await so the
  // second channel cannot start a second save/recovery loop for the same UUID.
  if (received.has(response.id)) return;
  received.add(response.id);
  // The wallet has finished. If iOS suspended Crypton during a long approval,
  // foreground it and retry this SAME result, never re-invoke the wallet method.
  const requestID = current;
  for (let attempt=0; attempt<8; attempt++) {
    try {
      const saved = await boundedFetch('result',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(response)});
      if (!saved.ok) throw Error();
      if (current === requestID) current = null;
      return;
    } catch {
      if (current === requestID) current = null;
      statusText.textContent = 'Approval finished. Returning to Crypton to save the result…';
      returnToApp();
      await new Promise(resolve=>setTimeout(resolve,300));
    }
  }
  stopped = true; statusText.textContent = 'Could not save the wallet response. Return to Crypton and use its saved delivery recovery; do not pay again.';
});
const labels = {
  waitForAuthentication:'Unlock ME to connect Crypton.',
  getPublicKey:'Checking the selected wallet identity…',
  createAction:'Review the payment total in ME. Keep this page open until the payment prompt closes.',
  listActions:'Checking the saved payment in wallet history…',
  createSignature:'Authenticating with MessageBox…', verifySignature:'Verifying MessageBox authentication…'
};
async function poll() {
  if (stopped) return;
  // A command is issued once by the native server. Do not fetch the next one
  // until the current result is acknowledged, or it could be consumed and lost.
  if (current) { setTimeout(poll,150); return; }
  try {
    const response = await boundedFetch('next',{cache:'no-store'});
    if (!response.ok) throw Error();
    const {command,finished,session} = await response.json();
    returnLink.hidden = !(finished && !current);
    if (finished && !current) {
      statusText.textContent = 'Operation finished. Returning to Crypton…';
      returnToApp();
      if (!session) stopped=true;
    } else if (command && !sent.has(command.id) && !current) {
      if (!allowed.has(command.call) || !window.ReactNativeWebView) { statusText.textContent='Open this request in Metanet Explorer on this iPhone.'; stopped=true; }
      else {
        statusText.textContent=labels[command.call] || 'Preparing encrypted messages. Review any grouped permissions in ME.';
        sent.add(command.id); current=command.id;
        window.ReactNativeWebView.postMessage(JSON.stringify(command));
      }
    }
  } catch {
    // Never foreground Crypton while a wallet invocation/prompt is outstanding.
    if (!current) { statusText.textContent='Return to Crypton to resume this saved operation.'; returnToApp(); }
  }
  if (!stopped) setTimeout(poll,150);
}
poll();
