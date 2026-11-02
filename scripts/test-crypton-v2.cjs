// Run the exact bundled engine against the independent SDK implementation.
// Disposable wallets only. No network, accounts or transactions.
const {createRequire} = require('node:module');
const path = require('node:path'), fs = require('node:fs'), vm = require('node:vm');
const assert = require('node:assert/strict');
const load = createRequire(path.resolve(process.argv[2], 'package.json'));
const sdk = load('@bsv/sdk');
const {PrivateKey,ProtoWallet,Utils} = sdk;
const native = new ProtoWallet(PrivateKey.fromRandom()), bob = new ProtoWallet(PrivateKey.fromRandom());
const protocol = {protocolID:[2,'crypton'],keyID:'1'};
let done, calls = 0, denied = false;
const sandbox = {fetch:()=>{throw Error("Network forbidden in crypto test");},TextEncoder,TextDecoder,URL,URLSearchParams,AbortController,setTimeout,clearTimeout,crypto:require("node:crypto").webcrypto,window:null,cryptonEngine:{postMessage:async json => {
  const data = JSON.parse(json);
  if (data.event === 'wallet') {
    calls++;
    try {
      if (denied) throw Error('denied');
      const args = data.args;
      if(args.data) args.data = Utils.toArray(args.data,'base64');
      if(args.ciphertext) args.ciphertext = Utils.toArray(args.ciphertext,'base64');
      const result = await native[data.call](args);
      sandbox.walletReply(data.id, data.call === 'createHmac' ? Utils.toBase64(result.hmac) : Utils.toUTF8(result.plaintext),null);
    } catch { sandbox.walletReply(data.id,null,'denied or wrong recipient'); }
  } else if(data.event === 'result') done.resolve(data.result);
  else if(data.event === 'error') done.reject(Error(data.message));
}}};
sandbox.window = sandbox;
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync("Crypton/Engine/vendor/bsv-sdk-3.2.1.js","utf8"), sandbox);
vm.runInContext(fs.readFileSync('Crypton/Engine/engine.js','utf8'),sandbox);
let id = 0;
async function run(action,text='',peer='self') {
  return new Promise((resolve,reject) => {done={resolve,reject}; sandbox.runCrypto({id:String(++id),action,text,peer});});
}
async function sealFor(recipient,content) {
  const ephemeral = new ProtoWallet(PrivateKey.fromRandom());
  const {ciphertext} = await ephemeral.encrypt({...protocol,counterparty:recipient,plaintext:Utils.toArray(JSON.stringify({protocol:'crypton-content',version:1,...content}),'utf8')});
  return JSON.stringify({protocol:'crypton',version:2,sender:(await ephemeral.getPublicKey({identityKey:true})).publicKey,ciphertext:Utils.toBase64(ciphertext)});
}
(async () => {
  const identity = await run('identity');
  const {hmac} = await native.createHmac({...protocol,counterparty:'self',data:Utils.toArray('crypton/messaging-identity/v1/0','utf8')});
  assert.equal(identity,new PrivateKey(hmac,'be',undefined,'error').toPublicKey().toString()); hmac.fill(0);
  assert.equal(identity,await run('identity'));
  const bobKey = (await bob.getPublicKey({identityKey:true})).publicKey;
  const text = 'Native iOS → web: café 🌍\n"quoted"';
  const sealed = JSON.parse(await run('seal',text,bobKey));
  assert.deepEqual(Object.keys(sealed).sort(),['ciphertext','protocol','sender','version']);
  assert.notEqual(sealed.sender,(await native.getPublicKey({identityKey:true})).publicKey);
  const opened = await bob.decrypt({...protocol,counterparty:sealed.sender,ciphertext:Utils.toArray(sealed.ciphertext,'base64')});
  assert.equal(JSON.parse(Utils.toUTF8(opened.plaintext)).text,text);
  assert.notEqual(sealed.sender,JSON.parse(await run('seal',text,bobKey)).sender);
  const received = await sealFor(identity,{kind:'message',text});
  assert.deepEqual(await run('open',received),{kind:'message',text});
  const self = await run('seal',text); assert.equal((await run('open',self)).text,text);
  const root = (await native.getPublicKey({identityKey:true})).publicKey;
  assert.equal((await run('open',await sealFor(root,{kind:'message',text}))).text,text);
  const inner = await sealFor(bobKey,{kind:'message',text:'only Bob'});
  assert.deepEqual(await run('open',await sealFor(identity,{kind:'layer',envelope:inner,note:'Pass to Bob'})),{kind:'layer',envelope:inner,note:'Pass to Bob'});
  await assert.rejects(run('open',inner));
  const before = calls;
  await assert.rejects(run('open',JSON.stringify({...sealed,recipient:bobKey})));
  assert.equal(calls,before,'Invalid public metadata must not reach the wallet');
  denied = true; await assert.rejects(run('identity'));
  const beforeDeniedOpen=calls;
  await assert.rejects(run('open', received));
  assert.equal(calls-beforeDeniedOpen,1,'Denied identity derivation must not request root-key fallback permissions');
  console.log('Crypton v2: identity parity, ephemeral sealing, SDK recipient, derived recipient, self, root fallback, layer, wrong recipient, metadata rejection and denial passed.');
})().catch(error => {console.error(error);process.exitCode=1;});
