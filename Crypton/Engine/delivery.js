'use strict';
// MessageBox HTTP/payment format follows the first-party MessageBox client.
// Native code owns authorization, journaling, host pinning, and the spending boundary.
function deliveryRpc(operation,event,fields) {
  live(operation);
  return new Promise((resolve,reject)=>{
    const id=String(++sequence);pending.set(id,{resolve,reject,operation});post({event,operation,id,...fields});
  });
}
function portable(value,field) {
  const byteFields=new Set(['tx','hmac','ciphertext','signature','data','plaintext']);
  if(value && typeof value==='object' && !Array.isArray(value) && byteFields.has(field)) {
    if(typeof value.__metanetByteArrayBase64==='string') {
      const bytes=Utils.toArray(value.__metanetByteArrayBase64,'base64');
      if(Object.keys(value).length!==2||bytes.length!==value.__metanetByteArrayLength)throw Error('Invalid wallet bytes.');return bytes;
    }
    const keys=Object.keys(value);
    if(keys.length && keys.every((k,i)=>k===String(i)))return keys.map(k=>value[k]);
  }
  if(Array.isArray(value)||ArrayBuffer.isView(value))return Array.from(value,x=>portable(x));
  if(value&&typeof value==='object')return Object.fromEntries(Object.entries(value).map(([k,v])=>[k,portable(v,k)]));
  return value;
}
function deliveryWallet(operation) {
  return new Proxy({}, {get:(_,call)=>async(args={})=>portable(await deliveryRpc(operation,'walletSdk',{call,args:portable(args)}))});
}
async function nativeFetch(operation,url,config={}) {
  const headers=Object.fromEntries(new Headers(config.headers||{}).entries());
  let body=config.body||'';
  if(typeof body!=='string')body=new TextDecoder('utf-8',{fatal:true}).decode(body);
  const result=await deliveryRpc(operation,'http',{request:{url:String(url),method:config.method||'GET',headers,body}});
  live(operation);
  return new Response(Uint8Array.from(Utils.toArray(result.body,'base64')),{status:result.status,headers:result.headers});
}
function authClient(operation,wallet) {
  return new bsv.AuthFetch(wallet,undefined,undefined,undefined,{requestTimeoutMs:120000,maxResponseBytes:2000000},(url,config)=>nativeFetch(operation,url,config));
}
function checkedQuote(quote,agent) {
  if(quote.deliveryAgentIdentityKey!==agent)throw Error('MessageBox server identity changed.');
  if(quote.recipientFee===-1)throw Error('This recipient has blocked messages from this wallet.');
  for(const n of [quote.deliveryFee,quote.recipientFee])if(!Number.isSafeInteger(n)||n<0||n>2147483647)throw Error('Invalid MessageBox fee.');
  if(quote.deliveryFee+quote.recipientFee>2147483647)throw Error('MessageBox fee is too large.');return quote;
}
async function getQuote(client,r,recipient) {
  const response=await client.fetch(r.host+'/permissions/quote?'+new URLSearchParams({recipient,messageBox:r.inbox}),{method:'GET',retryCounter:1});
  if(!response.ok)throw Error('MessageBox quote failed (HTTP '+response.status+').');
  const data=await response.json();if(data.status!=='success'||!data.quote)throw Error('MessageBox rejected the quote.');
  return checkedQuote({deliveryFee:data.quote.deliveryFee,recipientFee:data.quote.recipientFee,deliveryAgentIdentityKey:response.headers.get('x-bsv-auth-identity-key')},r.agent);
}
async function paymentPlan(wallet,r,recipient,sender,quote) {
  const outputs=[],remittances=[];
  for(const [fee,key,description,anyone] of [[quote.deliveryFee,r.agent,'MessageBox server delivery fee',false],[quote.recipientFee,recipient,'Recipient message fee',true]]) {
    if(!fee)continue;
    const derivationPrefix=Utils.toBase64(bsv.Random(32)),derivationSuffix=Utils.toBase64(bsv.Random(32));
    const source=anyone?new ProtoWallet('anyone'):wallet;
    const {publicKey}=await source.getPublicKey({protocolID:[2,'3241645161d8'],keyID:derivationPrefix+' '+derivationSuffix,counterparty:key});
    const lockingScript=new bsv.P2PKH().lock(PublicKey.fromString(publicKey).toAddress()).toHex();
    outputs.push({satoshis:fee,lockingScript,outputDescription:description,customInstructions:JSON.stringify({derivationPrefix,derivationSuffix,recipientIdentityKey:key})});
    const senderIdentityKey=anyone?(await source.getPublicKey({identityKey:true})).publicKey:sender;
    remittances.push({outputIndex:remittances.length,protocol:'wallet payment',paymentRemittance:{derivationPrefix,derivationSuffix,senderIdentityKey}});
  }
  return {action:{description:'MessageBox delivery payment',outputs,options:{randomizeOutputs:false,acceptDelayedBroadcast:false},labels:['crypton-delivery-'+r.id]},remittances};
}
function validatedPayment(result,p) {
  const bytes=portable(result.tx,'tx');if(!Array.isArray(bytes)||bytes.length===0||bytes.length>2000000)throw Error('ME did not return a complete payment transaction. Check the outbox before retrying.');
  const tx=bsv.Transaction.fromAtomicBEEF(bytes);
  if(result.txid && result.txid!==tx.id('hex'))throw Error('Wallet transaction ID does not match its payment.');
  if(tx.outputs.length<p.action.outputs.length)throw Error('Wallet payment omitted an output.');
  p.action.outputs.forEach((expected,i)=>{
    const actual=tx.outputs[i];if(actual.satoshis!==expected.satoshis||actual.lockingScript.toHex()!==expected.lockingScript)throw Error('Wallet payment changed the reviewed amount or destination.');
  });
  return {beef:Utils.toBase64(bytes),txid:tx.id('hex'),wire:{tx:bytes,outputs:p.remittances,description:'MessageBox delivery payment'}};
}
function receipt(data,p) {
  if(data?.status!=='success')throw Error('MessageBox did not return an acceptance receipt.');
  if(data.messageId!==undefined&&data.messageId!==p.messageId)throw Error('MessageBox receipt changed its message ID.');
  if(data.results!==undefined&&(!Array.isArray(data.results)||data.results.length!==1||data.results[0].recipient!==p.recipient||data.results[0].messageId!==p.messageId))throw Error('MessageBox receipt does not match this delivery.');
  return {status:'success',messageId:p.messageId};
}
window.runDelivery=async request=>{
  const operation=request.id;active=operation;
  try {
    const r=request.record;envelope(r.envelope);
    const wallet=deliveryWallet(operation),client=authClient(operation,wallet);
    const sender=(await wallet.getPublicKey({identityKey:true})).publicKey;
    let result;
    if(request.action==='prepare') {
      const recipient=r.recipient==='self'?sender:r.recipient;
      const quote=await getQuote(client,r,recipient);
      const message={message:'Encrypted message sent from Crypton for iOS. Open Crypton and import this payload:\n\n'+r.envelope,url:'https://crypton.metanet.app/'};
      const bodyText=JSON.stringify(message);
      const params={protocolID:[1,'messagebox'],keyID:'1',counterparty:recipient};
      const {hmac}=await wallet.createHmac({...params,data:Utils.toArray(bodyText,'utf8')});
      if(hmac.length!==32)throw Error('Wallet returned an invalid MessageBox identifier.');
      const messageId=Utils.toHex(hmac);
      const {ciphertext}=await wallet.encrypt({...params,plaintext:Utils.toArray(bodyText,'utf8')});
      const body=JSON.stringify({encryptedMessage:Utils.toBase64(ciphertext)});
      const plan=await paymentPlan(wallet,r,recipient,sender,quote);
      const prepared={sender,recipient,quote,messageId,body,...plan,quotedAt:Date.now()};
      await deliveryRpc(operation,'checkpoint',{kind:'prepared',value:prepared});result={prepared:true};
    } else if(request.action==='recover') {
      const history=await wallet.listActions({labels:['crypton-delivery-'+r.id],labelQueryMode:'all',includeOutputs:true,includeOutputLockingScripts:true,includeLabels:true,limit:10});
      const transactions=(history.actions||[]).map(a=>({txid:a.txid,status:a.status}));
      await deliveryRpc(operation,'checkpoint',{kind:'history',value:{transactions,totalActions:history.totalActions}});
      if(history.totalActions===1 && transactions.length===1 && ['unproven','completed'].includes(transactions[0].status)) {
        if(sender!==r.prepared.sender)throw Error('Switch back to the wallet used for this payment.');
        const evidence=await deliveryRpc(operation,'paymentProof',{});
        const tx=bsv.Transaction.fromHex(evidence.hex),proof=evidence.proof,block=evidence.block;
        if(tx.id('hex')!==transactions[0].txid || proof.txOrId!==tx.id('hex') || proof.target!==block.hash || !Number.isSafeInteger(proof.index) || proof.index<0 || !Number.isSafeInteger(block.height) || !Array.isArray(proof.nodes) || proof.nodes.length>32)throw Error('Invalid public payment proof.');
        const path=proof.nodes.map((hash,level)=>[{offset:(Math.floor(proof.index/2**level)^1),...(hash==='*'?{duplicate:true}:{hash})}]);
        path[0].push({offset:proof.index,hash:tx.id('hex'),txid:true});
        tx.merklePath=new bsv.MerklePath(block.height,path);
        if(tx.merklePath.computeRoot(tx.id('hex'))!==block.merkleroot)throw Error('Payment proof does not match its block.');
        const recovered={txid:transactions[0].txid,tx:tx.toAtomicBEEF()};
        validatedPayment(recovered,r.prepared);
        await deliveryRpc(operation,'checkpoint',{kind:'recoveredPayment',value:recovered});
      }
      result={recovered:true};
    } else {
      const p=r.prepared;if(sender!==p.sender)throw Error('ME wallet profile changed. Switch back to the wallet shown in this delivery.');
      let payment=r.payment;
      const required=p.quote.deliveryFee+p.quote.recipientFee;
      if(request.action==='send') {
        const current=await getQuote(client,r,p.recipient);
        if(current.deliveryFee!==p.quote.deliveryFee||current.recipientFee!==p.quote.recipientFee||current.deliveryAgentIdentityKey!==p.quote.deliveryAgentIdentityKey||Date.now()-p.quotedAt>300000)throw Error('The quote changed or expired. Refresh the fee before sending.');
        if(required) {
          const action=await wallet.createAction(p.action);
          payment=validatedPayment(action,p);
          await deliveryRpc(operation,'checkpoint',{kind:'paid',value:payment});
        }
      } else if(request.action==='resume') {
        if(r.state==='PAYMENT_RETURNED') {
          payment=validatedPayment(portable(r.walletResult),p);
          await deliveryRpc(operation,'checkpoint',{kind:'paid',value:payment});
        }
        if(required&&!payment)throw Error('The payment outcome needs checking in ME. A second payment is blocked.');
      } else throw Error('Unknown delivery operation.');
      const payload={message:{recipient:p.recipient,messageBox:r.inbox,messageId:p.messageId,body:p.body},...(payment?{payment:payment.wire}:{})};
      const response=await client.fetch(r.host+'/sendMessage',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload),retryCounter:1});
      if(!response.ok)throw Error('MessageBox delivery is unconfirmed (HTTP '+response.status+'). Use the saved delivery record; do not pay again.');
      const accepted=receipt(await response.json(),p);
      await deliveryRpc(operation,'checkpoint',{kind:'receipt',value:accepted});result=accepted;
    }
    live(operation);active=null;post({event:'result',id:operation,result});
  } catch(error) {
    if(active===operation){active=null;post({event:'error',id:operation,message:typeof error?.message==='string'?error.message.slice(0,350):'MessageBox delivery was interrupted. Check the outbox before trying again.'});}
  }
};
post({event:'ready'});
