// Test-only BRC-100 wallet. Ephemeral SDK keys; no real accounts or transactions.
const http = require('node:http');
const path = require('node:path');
const { createRequire } = require('node:module');
const fs = require('node:fs');
const load = createRequire(path.resolve(process.argv[2], 'package.json'));
if (JSON.parse(fs.readFileSync(path.resolve(process.argv[2], 'node_modules/@bsv/sdk/package.json'), 'utf8')).version !== '3.2.1') throw new Error('Use @bsv/sdk 3.2.1 for this fixture');
const { ProtoWallet, PrivateKey, Utils, Transaction, Script } = load('@bsv/sdk');
const alice = new ProtoWallet(PrivateKey.fromRandom());
const bob = new ProtoWallet(PrivateKey.fromRandom());
const stranger = new ProtoWallet(PrivateKey.fromRandom());
let denyNext = false;
let redirectNext = false;
let losePayment = false, holdPayment = false, paymentFailure = null, offlineNext = false; const actionHistory = [];
const deliveryFixture={acks:0,ackMode:"normal",inboxRows:[],inboxLists:0,payments:0,paymentAttempts:0,drop:false,changedFee:false,receiptCount:0};
const protocol = { protocolID: [1, 'crypton'], keyID: '1' };
let discoveryRequests = 0;
// Models a wallet's already-verified discovery response. No public certificate
// is issued and no real directory is queried by this fixture.
function discoveryCertificate(subject, email) {
  return {subject,certifier:new PrivateKey(2).toPublicKey().toString(),
    type:'exOl3KM0dIJ04EW5pZgbZmPag6MdJXd3/a1enmUU/BA=',
    serialNumber:Utils.toBase64(Array(32).fill(3)),revocationOutpoint:'00'.repeat(32)+'.0',
    signature:'00'.repeat(64),fields:{email:'fixture-only'},publiclyRevealedKeyring:{},
    decryptedFields:{email},certifierInfo:{name:'Fixture SocialCert',iconUrl:'https://example.com/icon.png',description:'Disposable fixture',trust:5}};
}
async function forIOS(content) {
  const {hmac}=await alice.createHmac({protocolID:[2,'crypton'],keyID:'1',counterparty:'self',data:Utils.toArray('crypton/messaging-identity/v1/0','utf8')});
  const recipient=new PrivateKey(hmac,'be',undefined,'error').toPublicKey().toString();hmac.fill(0);
  const ephemeral=new ProtoWallet(PrivateKey.fromRandom());
  const {ciphertext}=await ephemeral.encrypt({protocolID:[2,'crypton'],keyID:'1',counterparty:recipient,plaintext:Utils.toArray(JSON.stringify({protocol:'crypton-content',version:1,...content}),'utf8')});
  return JSON.stringify({protocol:'crypton',version:2,ciphertext:Utils.toBase64(ciphertext),sender:(await ephemeral.getPublicKey({identityKey:true})).publicKey});
}
const server = http.createServer(async (request, response) => {
  try {
    if(request.method==='GET' && request.url==='/test/download/qa-message.crypton') {
      const envelope=await forIOS({kind:'message',text:'Files picker round trip QA-20261030'});
      response.writeHead(200,{'Content-Type':'application/octet-stream','Content-Disposition':'attachment; filename="qa-message.crypton"'});response.end(envelope);return;
    }
    if (request.method !== 'POST' || request.headers.origin !== 'https://crypton.ios') throw new Error('Invalid test request');
    const chunks = [];
    let size = 0;
    for await (const block of request) {
      size += block.length;
      if (size > 1_000_000) throw new Error('Too large');
      chunks.push(block);
    }
    const args = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    const aliceKey = (await alice.getPublicKey({ identityKey: true })).publicKey;
    const bobKey = (await bob.getPublicKey({ identityKey: true })).publicKey;
    let result;
    if (request.url === '/test/delivery-config') result = {host:'http://127.0.0.1:18777', agent:new PrivateKey(2).toPublicKey().toString()};
    else if (request.url === '/test/qa-config') result = {heicReady:process.env.CRYPTON_QA_HEIC_READY==='1'};
    else if (request.url === '/test/recipient') result = { publicKey: bobKey };
    else if(request.url==='/test/seed-inbox') {
      const count=args.count??1;if(!Number.isInteger(count)||count<1||count>30)throw Error('Invalid seed count');
      deliveryFixture.inboxRows=[];
      const ephemeral=new ProtoWallet(PrivateKey.fromRandom());
      const h=await alice.createHmac({protocolID:[2,'crypton'],keyID:'1',counterparty:'self',data:Utils.toArray('crypton/messaging-identity/v1/0','utf8')});
      const cryptonKey=new PrivateKey(h.hmac,'be',undefined,'error').toPublicKey().toString();h.hmac.fill(0);
      for(let i=0;i<count;i++) {
        const text='Android inbox fixture message '+i;
        const receivingKey=args.mode==='wrong'?bobKey:args.mode==='root'?aliceKey:cryptonKey;
        let content={protocol:'crypton-content',version:1,kind:'message',text};
        if(args.layer) {
          const innerWallet=new ProtoWallet(PrivateKey.fromRandom());
          const inner=await innerWallet.encrypt({protocolID:[2,'crypton'],keyID:'1',counterparty:receivingKey,plaintext:Utils.toArray(JSON.stringify(content),'utf8')});
          content={protocol:'crypton-content',version:1,kind:'layer',note:'Disposable outer layer',envelope:JSON.stringify({protocol:'crypton',version:2,sender:(await innerWallet.getPublicKey({identityKey:true})).publicKey,ciphertext:Utils.toBase64(inner.ciphertext)})};
        }
        const sealed=await ephemeral.encrypt({protocolID:[2,'crypton'],keyID:'1',counterparty:receivingKey,plaintext:Utils.toArray(JSON.stringify(content),'utf8')});
        const envelope=JSON.stringify({protocol:'crypton',version:2,sender:(await ephemeral.getPublicKey({identityKey:true})).publicKey,ciphertext:Utils.toBase64(sealed.ciphertext)});
        const inner=JSON.stringify({message:'Encrypted message sent from Crypton for Android. Open Crypton and import this payload:\n\n'+envelope,url:'https://crypton.metanet.app/'});
        const outer=await bob.encrypt({protocolID:[1,'messagebox'],keyID:'1',counterparty:aliceKey,plaintext:Utils.toArray(inner,'utf8')});
        const encrypted={encryptedMessage:Utils.toBase64(outer.ciphertext)};
        const body=i%2?JSON.stringify(encrypted):JSON.stringify({message:JSON.stringify(encrypted),payment:{fixture:'must not be imported'}});
        deliveryFixture.inboxRows.push({messageId:require('node:crypto').randomBytes(32).toString('hex'),recipient:aliceKey,sender:bobKey,body});
      }
      result={wallet:aliceKey,ids:deliveryFixture.inboxRows.map(m=>m.messageId)};
    }
    else if (request.url === '/test/ack-mode') { if(!['normal','reject','retain','drop','badLookup'].includes(args.mode))throw Error('Invalid acknowledgement mode');deliveryFixture.ackMode=args.mode;result={ready:true}; }
    else if (request.url === '/test/discovery-stats') result = {requests:discoveryRequests};
    else if (request.url === '/test/v2-for-ios') {
      let recipient = aliceKey;
      if (args.mode !== 'root') {
        const { hmac } = await alice.createHmac({protocolID:[2,'crypton'],keyID:'1',counterparty:'self',data:Utils.toArray('crypton/messaging-identity/v1/0','utf8')});
        recipient = new PrivateKey(hmac,'be',undefined,'error').toPublicKey().toString(); hmac.fill(0);
      }
      const ephemeral = new ProtoWallet(PrivateKey.fromRandom());
      const {ciphertext} = await ephemeral.encrypt({protocolID:[2,'crypton'],keyID:'1',counterparty:recipient,plaintext:Utils.toArray(JSON.stringify({protocol:'crypton-content',version:1,...args.content}),'utf8')});
      result = {envelope:JSON.stringify({protocol:'crypton',version:2,ciphertext:Utils.toBase64(ciphertext),sender:(await ephemeral.getPublicKey({identityKey:true})).publicKey})};
    } else if (request.url === '/test/v2-open' || request.url === '/test/v2-wrong') {
      const e = JSON.parse(args.envelope);
      const reader = request.url === '/test/v2-wrong' ? stranger : bob;
      const {plaintext} = await reader.decrypt({protocolID:[2,'crypton'],keyID:'1',counterparty:e.sender,ciphertext:Utils.toArray(e.ciphertext,'base64')});
      result = JSON.parse(Utils.toUTF8(plaintext));
    }
    else if (request.url === '/test/delivery-stats') result = {...deliveryFixture};
    else if (request.url === '/test/lose-next-payment') { losePayment=true;result={ready:true}; }
    else if (request.url === '/test/hold-next-payment') { holdPayment=true;result={ready:true}; }
    else if (request.url === '/test/payment-failure') {
      if(!['insufficient','denied',null].includes(args.kind))throw Error('Unknown disposable failure');
      paymentFailure=args.kind;result={ready:true};
    }
    else if (request.url === '/test/offline-next') { offlineNext=true;result={ready:true}; }
    else if (request.url === '/test/nested-for-ios') {
      const inner=await forIOS({kind:'message',text:'Nested inner plaintext QA-20261030'});
      result={inner,envelope:await forIOS({kind:'layer',envelope:inner,note:'Outer note QA-20261030'})};
    }
    else if (request.url === '/test/drop-next-delivery') { deliveryFixture.drop=true;result={ready:true}; }
    else if (request.url === '/test/reject-next-delivery') { deliveryFixture.reject=true;result={ready:true}; }
    else if (request.url === '/test/change-delivery-fee') { deliveryFixture.changedFee=Boolean(args.changed);result={ready:true}; }
    else if (request.url === '/test/deny-next') { denyNext = true; result = { ready: true }; }
    else if (request.url === '/test/redirect-next') { redirectNext = true; result = { ready: true }; }
    else if (request.url === '/test/encrypt-for-ios') {
      const { ciphertext } = await bob.encrypt({ ...protocol, counterparty: aliceKey, plaintext: Utils.toArray(args.plaintext, 'utf8') });
      result = { ciphertext: Utils.toBase64(ciphertext), sender: bobKey };
    } else if (request.url === '/test/decrypt-from-ios' || request.url === '/test/wrong-recipient') {
      const reader = request.url === '/test/wrong-recipient' ? stranger : bob;
      const { plaintext } = await reader.decrypt({ ...protocol, counterparty: aliceKey, ciphertext: Utils.toArray(args.ciphertext, 'base64') });
      result = { plaintext: Utils.toUTF8(plaintext) };
    } else {
      if(offlineNext){offlineNext=false;request.socket.destroy();return;}
      if (redirectNext) {
        redirectNext = false;
        response.writeHead(307, { Location: 'https://untrusted.example' });
        response.end();
        return;
      }
      if (denyNext) { denyNext = false; throw new Error('Fixture permission denied'); }
      if (request.url === '/isAuthenticated' || request.url === '/waitForAuthentication') result = { authenticated: true };
      else if (request.url === '/getNetwork') result = {network:'mainnet'};
      else if (request.url === '/discoverByAttributes' || request.url === '/discoverByIdentityKey') {
        discoveryRequests++;
        if(args.limit!==20 || args.offset!==0 || args.seekPermission!==true)throw Error('Unexpected discovery scope');
        const query=args.attributes?.any || args.identityKey;
        let certificates = query==='empty@example.com' ? [] : [discoveryCertificate(bobKey,'bob@example.com')];
        if(query==='ambiguous')certificates.push(discoveryCertificate((await stranger.getPublicKey({identityKey:true})).publicKey,'another@example.com'));
        if(query==='malformed')certificates[0].subject='02'+'00'.repeat(32);
        if(request.url==='/discoverByIdentityKey' && args.identityKey!==bobKey)certificates=[];
        result={totalCertificates:certificates.length,certificates};
      }
      else if (request.url === '/getPublicKey') result = await alice.getPublicKey(args);
      else if (request.url === '/createAction') {
        if(args.description!=='MessageBox delivery payment'||args.options.randomizeOutputs!==false)throw Error('Unexpected fixture payment');
        deliveryFixture.paymentAttempts++;
        if(paymentFailure){const failure=paymentFailure;paymentFailure=null;throw Error(failure==='insufficient'?'Insufficient disposable funds':'Disposable payment declined');}
        deliveryFixture.payments++;
        const tx=new Transaction();args.outputs.forEach(o=>tx.addOutput({satoshis:o.satoshis,lockingScript:Script.fromHex(o.lockingScript)}));
        result={tx:tx.toAtomicBEEF(),txid:tx.id('hex')};
        // Synthetic transactions are unsigned and never broadcast or confirmed.
        actionHistory.push({txid:result.txid,status:'unsigned',labels:args.labels});
        if(losePayment){losePayment=false;request.socket.destroy();return;}
        if(holdPayment){holdPayment=false;request.once('close',()=>{});return;}
      } else if(request.url==='/listActions') result={totalActions:actionHistory.filter(a=>(args.labels||[]).every(label=>a.labels.includes(label))).length,actions:actionHistory.filter(a=>(args.labels||[]).every(label=>a.labels.includes(label)))};
      else if (['/encrypt','/decrypt','/createHmac','/verifyHmac','/createSignature','/verifySignature'].includes(request.url)) {
        if(args.protocolID?.[1]==='crypton') {
          if (![JSON.stringify(protocol.protocolID), JSON.stringify([2,'crypton'])].includes(JSON.stringify(args.protocolID)) || args.keyID !== protocol.keyID || args.seekPermission !== true) throw new Error('Incorrect Crypton protocol');
        } else if(!['messagebox','auth message signature','server hmac'].includes(args.protocolID?.[1])) throw Error('Unsupported fixture protocol');
        result = await alice[request.url.slice(1)](args);
      } else throw new Error('Unsupported operation');
    }
    response.writeHead(200, { 'Content-Type': 'application/json' });
    response.end(JSON.stringify(result, (_key, value) => value instanceof Uint8Array ? Array.from(value) : value));
  } catch {
    response.writeHead(400, { 'Content-Type': 'application/json' });
    response.end(JSON.stringify({ isError: true, code: 1, message: 'Fixture request rejected' }));
  }
});
server.listen(18776, '127.0.0.1', () => console.log('SDK fixture ready on 127.0.0.1:18776'));

module.exports={alice,bob,stranger,deliveryFixture,load};
