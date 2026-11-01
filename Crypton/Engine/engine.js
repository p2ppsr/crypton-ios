'use strict';
// Mirrors crypton-web's v2 protocol. Keys here are app-scoped, memory-only;
// the wallet root key is never exported. Every seal uses a new ephemeral sender.
const {PrivateKey, ProtoWallet, Utils, PublicKey} = bsv;
const pending = new Map();
let active = null, sequence = 0;
function post(value) { cryptonEngine.postMessage(JSON.stringify(value)); }
function live(operation) { if (active !== operation) throw Error('Operation cancelled.'); }
function wallet(operation, call, args) {
  live(operation);
  return new Promise((resolve,reject) => {
    const id = String(++sequence); pending.set(id,{resolve,reject,operation});
    post({event:'wallet',operation,id,call,args});
  });
}
window.walletReply = (id, value, error) => {
  const job = pending.get(id); if (!job) return;
  pending.delete(id);
  if (job.operation !== active) return job.reject(Error('Operation cancelled.'));
  error ? job.reject(Error(error)) : job.resolve(value);
};
window.cancelCrypto = () => { active = null; for(const job of pending.values()) job.reject(Error('Operation cancelled.')); pending.clear(); };
function envelope(input) {
  if (new TextEncoder().encode(input).length > 64000) throw Error('Payload exceeds 64 KB.');
  const e = JSON.parse(input);
  if (e?.protocol !== 'crypton' || e.version !== 2 || Object.keys(e).length !== 4 || typeof e.ciphertext !== 'string'
      || e.ciphertext.length < 64 || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(e.ciphertext)
      || !/^(02|03)[0-9a-fA-F]{64}$/.test(e.sender) || !PublicKey.fromString(e.sender).validate()) throw Error('Invalid Crypton v2 envelope.');
  return e;
}
async function identity(operation) {
  for (let attempt=0;attempt<256;attempt++) {
    const hmac = Utils.toArray(await wallet(operation,'createHmac',{
      protocolID:[2,'crypton'], keyID:'1', counterparty:'self',
      data:Utils.toBase64(Utils.toArray(`crypton/messaging-identity/v1/${attempt}`,'utf8'))
    }),'base64');
    if (hmac.length !== 32) throw Error('Invalid Crypton key material.');
    let key;
    try { key = new PrivateKey(hmac,'be',undefined,'error'); } catch { continue; } finally { hmac.fill(0); }
    if (!key.isZero()) return {publicKey:key.toPublicKey().toString(),wallet:new ProtoWallet(key)};
  }
  throw Error('Unable to derive a Crypton identity.');
}
function content(text) {
  const c = JSON.parse(text);
  if (c?.protocol !== 'crypton-content' || c.version !== 1) throw Error('Unsupported encrypted content.');
  if (c.kind === 'message' && typeof c.text === 'string') return {kind:'message',text:c.text};
  if (c.kind === 'layer' && typeof c.envelope === 'string' && (c.note === undefined || typeof c.note === 'string')) {
    envelope(c.envelope); return {kind:'layer',envelope:c.envelope,note:c.note || ''};
  }
  throw Error('Unsupported encrypted content.');
}
async function openEnvelope(operation,input) {
      const e = envelope(input);
      const args = {protocolID:[2,'crypton'],keyID:'1',counterparty:e.sender};
      let text;
      try {
        const own = await identity(operation); live(operation);
        const {plaintext} = await own.wallet.decrypt({...args,ciphertext:Utils.toArray(e.ciphertext,'base64')});
        text = Utils.toUTF8(plaintext);
      } catch {
        live(operation);
        text = await wallet(operation,'decrypt',{...args,ciphertext:e.ciphertext});
      }
      return content(text);
}
window.runCrypto = async request => {
  const operation = request.id; active = operation;
  try {
    let result;
    if (request.action === 'identity') result = (await identity(operation)).publicKey;
    else if (request.action === 'contactIdentity') {
      const own = await identity(operation);
      const walletIdentity = await wallet(operation,'getPublicKey',{identityKey:true});
      result = {receivingKey:own.publicKey,walletIdentity};
    }
    else if (request.action === 'seal') {
      const recipient = request.peer === 'self' ? (await identity(operation)).publicKey : request.peer;
      live(operation);
      const senderWallet = new ProtoWallet(PrivateKey.fromRandom());
      const {publicKey:sender} = await senderWallet.getPublicKey({identityKey:true});
      const plaintext = JSON.stringify({protocol:'crypton-content',version:1,kind:'message',text:request.text});
      if (!request.text.trim() || new TextEncoder().encode(plaintext).length > 44000) throw Error('Message is empty or too large for Crypton v2.');
      const {ciphertext} = await senderWallet.encrypt({plaintext:Utils.toArray(plaintext,'utf8'),protocolID:[2,'crypton'],keyID:'1',counterparty:recipient});
      result = JSON.stringify({protocol:'crypton',version:2,ciphertext:Utils.toBase64(ciphertext),sender}); envelope(result);
    } else if (request.action === 'open') {
      result = await openEnvelope(operation,request.text);
    } else throw Error('Unsupported operation.');
    live(operation); active = null; post({event:'result',id:operation,result});
  } catch (error) {
    if (active === operation) { active = null; post({event:'error',id:operation,message:(typeof error.message === 'string' && error.message.startsWith('ME declined ')) ? error.message : 'Could not open or create this Crypton message. Check the recipient, wallet permissions and payload, then retry.'}); }
  }
};
