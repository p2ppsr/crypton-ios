'use strict';
// MessageBox lite retrieval: never internalizes recipient payments or acknowledges server messages.
function inboxEnvelope(body) {
  let value=body;
  for(let i=0;i<4;i++) {
    if(typeof value==='string') {
      if(value.length>100000)throw Error('Message is too large.');
      const text=value.trim();
      try { value=JSON.parse(text);continue; } catch {}
      const start=text.indexOf('{');
      if(start>=0){const candidate=text.slice(start);envelope(candidate);return candidate;}
      throw Error('Not a Crypton message.');
    }
    if(value?.protocol==='crypton'){const text=JSON.stringify(value);envelope(text);return text;}
    if(value&&typeof value==='object'&&!Array.isArray(value)&&Object.hasOwn(value,'message')){value=value.message;continue;}
    throw Error('Not a Crypton message.');
  }
  throw Error('Unsupported message wrapper.');
}
function inboxBody(raw) {
  let value=typeof raw==='string'?JSON.parse(raw):raw;
  if(value&&typeof value==='object'&&Object.hasOwn(value,'message'))value=typeof value.message==='string'?JSON.parse(value.message):value.message;
  return value;
}
async function removeInboxMessage(operation,request,w,checkRoot) {
  const client=authClient(operation,w);
  const checked=async(path,body)=>{
    await checkRoot();
    const response=await client.fetch(request.host+path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),retryCounter:1});
    if(!response.ok)throw Error('Server removal pending (HTTP '+response.status+').');
    if(response.headers.get('x-bsv-auth-identity-key')!==request.agent)throw Error('MessageBox server identity changed.');
    const data=await response.json();if(data.status==='error')throw Error('MessageBox has not confirmed removal.');return data;
  };
  const absent=async()=>{
    const data=await checked('/listMessages',{messageBox:'notifications',offset:0,limit:25,messageId:request.messageId});
    if(!Array.isArray(data.messages)||data.messages.length>1||data.hasMore===true||data.messages.some(m=>m.messageId!==request.messageId))
      throw Error('MessageBox did not provide a verifiable message lookup. Server removal pending.');
    return data.messages.length===0;
  };
  // A previous acknowledgement may have succeeded before the connection/process was lost.
  if(request.action!=='remove'||!await absent()) {
    let ackError;
    try {const data=await checked('/acknowledgeMessage',{messageIds:[request.messageId]});if(data.status!=='success')throw Error('MessageBox did not confirm acknowledgement.');}
    catch(error){ackError=error;}
    // Even after a lost response, an authenticated, ID-filtered lookup can confirm absence.
    if(!await absent())throw ackError||Error('Server removal pending: message is still retrievable.');
  }
  await checkRoot();await deliveryRpc(operation,'checkpoint',{kind:'removed',value:{wallet:request.wallet,messageId:request.messageId}});
}
window.runInbox=async request=>{
  const operation=request.id;active=operation;
  try {
    const w=deliveryWallet(operation);
    const root=(await w.getPublicKey({identityKey:true})).publicKey;
    if(!/^(02|03)[a-f0-9]{64}$/.test(root)||!PublicKey.fromString(root).validate())throw Error('The wallet returned an invalid identity.');
    const checkRoot=async()=>{if((await w.getPublicKey({identityKey:true})).publicKey!==root)throw Error('The wallet profile changed. Switch back and retry.');live(operation);};
    if(request.wallet&&request.wallet!==root)throw Error('Switch ME to the wallet for this saved inbox and retry.');
    let result;
    if(['open','openDiscard','layer'].includes(request.action)) {
      const opened=await openEnvelope(operation,request.envelope);await checkRoot();
      result={wallet:root,content:opened};
      if(request.action==='openDiscard') {
        await deliveryRpc(operation,'checkpoint',{kind:'decrypted',value:{wallet:root,messageId:request.messageId}});
        request.envelope='';result.ephemeral=true;
        try{await removeInboxMessage(operation,request,w,checkRoot);result.removed=true;}
        catch(error){result.removed=false;result.removalError=(error.message||'Server removal pending.').slice(0,350);}
      }
    } else if(request.action==='remove') {
      await removeInboxMessage(operation,request,w,checkRoot);result={wallet:root,removed:true};
    } else if(request.action==='refresh') {
      if((await w.getNetwork({})).network!=='mainnet')throw Error('Switch ME to mainnet to read this MessageBox inbox.');
      const client=authClient(operation,w);
      const response=await client.fetch(request.host+'/listMessages',{method:'POST',headers:{'Content-Type':'application/json'},
        body:JSON.stringify({messageBox:'notifications',offset:request.offset,limit:25}),retryCounter:1});
      if(!response.ok)throw Error('Inbox retrieval failed (HTTP '+response.status+'). Your saved messages are still available.');
      if(response.headers.get('x-bsv-auth-identity-key')!==request.agent)throw Error('MessageBox server identity changed.');
      const data=await response.json();
      if(data.status==='error'||!Array.isArray(data.messages)||data.messages.length>25)throw Error('MessageBox returned an invalid inbox page.');
      const messages=[];let skipped=0;
      for(const m of data.messages) {
        live(operation);
        try {
          if(typeof m.messageId!=='string'||!/^[A-Za-z0-9_-]{1,160}$/.test(m.messageId)||typeof m.sender!=='string'||!PublicKey.fromString(m.sender).validate())throw Error('Invalid message metadata.');
          const body=inboxBody(m.body);
          let inner=body;
          if(body&&typeof body.encryptedMessage==='string') {
            if(body.encryptedMessage.length>180000||!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(body.encryptedMessage))throw Error('Invalid transport ciphertext.');
            await checkRoot();
            const decoded=await w.decrypt({protocolID:[1,'messagebox'],keyID:'1',counterparty:m.sender,ciphertext:Utils.toArray(body.encryptedMessage,'base64')});
            inner=new TextDecoder('utf-8',{fatal:true}).decode(new Uint8Array(decoded.plaintext));
          } else throw Error('Not an encrypted Crypton transport.');
          messages.push({messageId:m.messageId,sender:m.sender,envelope:inboxEnvelope(inner)});
        }catch(error){
          // Permission rejection is actionable and must not look like an empty inbox.
          if(/declined|permission|denied|cancel|profile changed/i.test(error.message||''))throw error;
          skipped++;
        }
      }
      await checkRoot();
      let next=request.offset+data.messages.length;
      if(data.hasMore===true) {
        if(Number.isSafeInteger(data.nextOffset)&&data.nextOffset>request.offset)next=data.nextOffset;
        if(next<=request.offset||next>1000000)throw Error('MessageBox returned an invalid next page.');
      }
      await deliveryRpc(operation,'checkpoint',{kind:'page',value:{wallet:root,messages}});
      result={wallet:root,count:messages.length,skipped,hasMore:data.hasMore===true,nextOffset:next};
    } else throw Error('Unsupported inbox request.');
    live(operation);active=null;post({event:'result',id:operation,result});
  }catch(error){if(active===operation){active=null;post({event:'error',id:operation,message:error.message||'Could not read the inbox. Your saved messages were kept.'});}}
};
post({event:'ready'});
