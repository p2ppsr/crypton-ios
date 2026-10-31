// Exact packaged inbox driver with disposable SDK keys; network and financial methods forbidden.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),path=require('node:path');
const load=require('node:module').createRequire(path.resolve(process.argv[2],'package.json'));
const {ProtoWallet,PrivateKey,Utils}=load('@bsv/sdk');
const reader=new ProtoWallet(PrivateKey.fromRandom()),sender=new ProtoWallet(PrivateKey.fromRandom());
let ackMode='normal',acks=0;const pendingRemoval=new Set();
let completed,sandbox,rows=[],saved=[],agent,root,failNetwork=false,badAgent=false,changeProfile=false,identities=0,decryptDenied=false;
async function bridge(raw){
 const e=JSON.parse(raw);if(e.event==='ready')return;
 if(e.event==='result')return completed.resolve(e.result);if(e.event==='error')return completed.reject(Error(e.message));
 try {
  let result;
  if(e.event==='walletSdk') {
   assert.ok(['getPublicKey','getNetwork','decrypt'].includes(e.call),'Inbox must not spend or accept payments');
   if(e.call==='getNetwork')result={network:'mainnet'};
   else if(e.call==='getPublicKey'){identities++;result={publicKey:changeProfile&&identities>1?agent:root};}
   else {if(decryptDenied)throw Error('ME declined feature permission');result=await reader.decrypt(e.args);}
  }else if(e.event==='wallet'){
   assert.ok(['createHmac','decrypt'].includes(e.call));const args={...e.args};
   if(args.data)args.data=Utils.toArray(args.data,'base64');if(args.ciphertext)args.ciphertext=Utils.toArray(args.ciphertext,'base64');
   const value=await reader[e.call](args);result=e.call==='createHmac'?Utils.toBase64(value.hmac):Utils.toUTF8(value.plaintext);
  }else if(e.event==='http'){
   const endpoint=new URL(e.request.url).pathname,body=JSON.parse(e.request.body);assert.equal(e.request.method,'POST');
   if(failNetwork)throw Error('Simulated offline');
   let data={status:'success'};
   if(endpoint==='/acknowledgeMessage') {
     assert.deepEqual(body,{messageIds:['a'.repeat(64)]});assert.ok(pendingRemoval.has(body.messageIds[0]),'Decryption checkpoint must precede acknowledgement');acks++;
     if(ackMode==='reject')throw Error('Simulated server rejection');
     if(ackMode!=='retain')rows=rows.filter(m=>m.messageId!==body.messageIds[0]);
     if(ackMode==='drop')throw Error('Lost acknowledgement response');
   } else {
     assert.equal(endpoint,'/listMessages');
     assert.deepEqual(body,{messageBox:'notifications',offset:0,limit:25,...(body.messageId?{messageId:'a'.repeat(64)}:{})});
     data.messages=body.messageId?rows.filter(m=>m.messageId===body.messageId):rows;
     if(body.messageId&&ackMode==='badLookup')data.messages=[{messageId:'other'}];data.hasMore=false;
   }
   result={status:200,headers:{'x-bsv-auth-identity-key':badAgent?root:agent},body:Utils.toBase64(Utils.toArray(JSON.stringify(data),'utf8'))};
  }else if(e.event==='checkpoint'){
   assert.equal(e.value.wallet,root);
   if(e.kind==='page')saved.push(...e.value.messages);
   else if(e.kind==='decrypted'){pendingRemoval.add(e.value.messageId);saved=saved.filter(m=>m.messageId!==e.value.messageId);}
   else if(e.kind==='removed'){assert.ok(pendingRemoval.has(e.value.messageId));pendingRemoval.delete(e.value.messageId);}
   else throw Error('Unexpected checkpoint');result=true;
  }else throw Error('Unexpected native request');
  sandbox.walletReply(e.id,JSON.parse(JSON.stringify(result)),null);
 }catch(error){sandbox.walletReply(e.id,null,error.message);}
}
sandbox={TextEncoder,TextDecoder,URL,URLSearchParams,Headers,Response,AbortController,setTimeout,clearTimeout,crypto:require('node:crypto').webcrypto,fetch:()=>{throw Error('Network forbidden');},cryptonEngine:{postMessage:bridge}};
sandbox.window=sandbox;vm.createContext(sandbox);
for(const file of ['vendor/bsv-sdk-3.2.1.js','engine.js','delivery.js','inbox.js'])vm.runInContext(fs.readFileSync('Crypton/Engine/'+file,'utf8'),sandbox);
vm.runInContext('authClient=(operation,wallet)=>({fetch:(url,args)=>nativeFetch(operation,url,args)});',sandbox);
let seq=0;
function run(action='refresh',envelope){identities=0;return new Promise((resolve,reject)=>{completed={resolve,reject};sandbox.runInbox({id:String(++seq),action,wallet:root,host:'https://fixture.invalid',agent,offset:0,envelope,messageId:'a'.repeat(64)});});}
(async()=>{
 root=(await reader.getPublicKey({identityKey:true})).publicKey;agent=(await sender.getPublicKey({identityKey:true})).publicKey;
 const ephemeral=new ProtoWallet(PrivateKey.fromRandom());
 const inner=await ephemeral.encrypt({protocolID:[2,'crypton'],keyID:'1',counterparty:root,plaintext:Utils.toArray(JSON.stringify({protocol:'crypton-content',version:1,kind:'message',text:'Receiving works'}),'utf8')});
 const envelope=JSON.stringify({protocol:'crypton',version:2,sender:(await ephemeral.getPublicKey({identityKey:true})).publicKey,ciphertext:Utils.toBase64(inner.ciphertext)});
 const outer=await sender.encrypt({protocolID:[1,'messagebox'],keyID:'1',counterparty:root,plaintext:Utils.toArray(JSON.stringify({message:'Crypton message:\n\n'+envelope}),'utf8')});
 rows=[{messageId:'a'.repeat(64),sender:agent,body:JSON.stringify({message:JSON.stringify({encryptedMessage:Utils.toBase64(outer.ciphertext)}),payment:{neverImport:true}})}];
 const received=rows[0];
 assert.equal((await run()).count,1);assert.equal(saved[0].envelope,envelope);assert.equal((await run('open',envelope)).content.text,'Receiving works');
 const kept=JSON.stringify(saved);failNetwork=true;await assert.rejects(run(),/offline/);failNetwork=false;assert.equal(JSON.stringify(saved),kept);
 badAgent=true;await assert.rejects(run(),/identity changed/);badAgent=false;assert.equal(JSON.stringify(saved),kept);
 changeProfile=true;await assert.rejects(run(),/profile changed/);changeProfile=false;assert.equal(JSON.stringify(saved),kept);
 decryptDenied=true;await assert.rejects(run(),/declined/);decryptDenied=false;assert.equal(JSON.stringify(saved),kept);
 rows=[{messageId:'other',sender:agent,body:'Unrelated notification'}];const ignored=await run();assert.equal(ignored.count,0);assert.equal(ignored.skipped,1);assert.equal(JSON.stringify(saved),kept);
 rows=Array(26).fill({});await assert.rejects(run(),/invalid inbox page/);assert.equal(JSON.stringify(saved),kept);
 for(const mode of ['normal','reject','retain','drop','badLookup']) {
   rows=[received];saved=[{messageId:received.messageId,envelope}];ackMode=mode;
   const opened=await run('openDiscard',envelope);assert.equal(opened.content.text,'Receiving works');assert.equal(saved.length,0,'Ciphertext must be purged immediately after successful decryption');
   const removed=['normal','drop'].includes(mode);assert.equal(opened.removed,removed);assert.equal(pendingRemoval.has(received.messageId),!removed);
   if(!removed){ackMode='normal';assert.equal((await run('remove')).removed,true);assert.equal(pendingRemoval.size,0);}
 }
 rows=[received];saved=[{messageId:received.messageId,envelope}];ackMode='normal';const before=acks;
 await assert.rejects(run('openDiscard',JSON.stringify({...JSON.parse(envelope),ciphertext:'A'.repeat(64)})));
 assert.equal(acks,before,'Failed decryption must never acknowledge a message');assert.equal(saved.length,1);assert.equal(pendingRemoval.size,0);
 console.log('MessageBox inbox passed: exact encrypted transport, root decryption, offline cache preservation, server pinning, profile change, permission denial, unrelated notifications, bounded pages, automatic acknowledgement, immediate ciphertext purge, retry after rejection, lost responses, false success and no acknowledgement after failed decryption.');
})().catch(e=>{console.error(e);process.exitCode=1;});
