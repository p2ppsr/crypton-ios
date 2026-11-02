// Loopback-only authenticated MessageBox and fake payment wallet. No accounts, broadcasting or real money.
const {isDeepStrictEqual}=require('node:util');
const {alice,bob,deliveryFixture,load}=require('./sdk-wallet-fixture.cjs');
const {ProtoWallet,PrivateKey,Transaction,Utils}=load('@bsv/sdk');
const express=load('express');const {createAuthMiddleware}=load('@bsv/auth-express-middleware');
// Opt-in CLI failure run: start with two stalled quotes to verify unpaid classification.
const timeoutQuotes=Number(process.env.CRYPTON_FIXTURE_TIMEOUT_QUOTES||0);
if(!Number.isInteger(timeoutQuotes)||timeoutQuotes<0||timeoutQuotes>2)throw Error('Invalid fixture quote timeout count');
deliveryFixture.quoteFaults=timeoutQuotes;
if(process.env.CRYPTON_FIXTURE_DROP_DELIVERY_RESPONSE==='1')deliveryFixture.drop=true;
const serverWallet=new ProtoWallet(new PrivateKey(2));const accepted=new Map();const senders=new Map();const acknowledged=new Set();
const app=express();app.use(express.json({limit:'8mb'}));app.use(express.raw({type:'application/octet-stream',limit:'8mb'}));
app.use((req,res,next)=>{if(req.path==='/.well-known/auth')deliveryFixture.authHandshakes++;next();});
app.use(createAuthMiddleware({wallet:serverWallet,allowUnauthenticated:false}));
app.get('/permissions/quote',(req,res)=>{
 deliveryFixture.quotes++;deliveryFixture.quoteRequestIds.push(req.headers['x-bsv-auth-request-id']);
 if(deliveryFixture.quoteFaults>0){
   deliveryFixture.quoteFaults--;
   if(deliveryFixture.quoteFaultMode==='http503')return res.status(503).json({status:'error'});
   // Actual stalled HTTP response exercises URLSession's production 15-second timeout.
   // End it later if a regression leaves the request waiting instead of timing out.
   const timer=setTimeout(()=>res.json({status:'error',reason:'fixture timeout did not fire'}),25000);
   res.on('close',()=>clearTimeout(timer));return;
 }
 res.json({status:'success',quote:{deliveryFee:deliveryFixture.changedFee||(deliveryFixture.changeFeeAtQuote&&deliveryFixture.quotes>=deliveryFixture.changeFeeAtQuote)?11:10,recipientFee:10}});
});
app.post('/listMessages',(req,res)=>{
 deliveryFixture.inboxLists++;
 // Optional test-only lag: an accepted message is absent from the first N reads.
 const deferred=Number(process.env.CRYPTON_FIXTURE_DEFER_INBOX_LISTS||0);
 if(Number.isSafeInteger(deferred)&&deferred>0&&deferred<=3&&deliveryFixture.inboxLists<=deferred)return res.json({status:'success',messages:[],hasMore:false});
 const {messageBox,offset,limit,messageId}=req.body;
 if(messageBox!=='notifications'||!Number.isInteger(offset)||offset<0||limit!==25)return res.status(400).json({status:'error'});
 const rows=[...deliveryFixture.inboxRows,...Array.from(accepted.values()).map(r=>({...r.message,sender:senders.get(r.message.messageId)}))]
   .filter(r=>r.recipient===req.auth.identityKey&&!acknowledged.has(r.recipient+":"+r.messageId));
 if(messageId!==undefined){
   if(typeof messageId!=='string')return res.status(400).json({status:'error'});
   if(deliveryFixture.ackMode==='badLookup')return res.json({status:'success',messages:[{messageId:'unrelated'}],hasMore:false});
   return res.json({status:'success',messages:rows.filter(r=>r.messageId===messageId).map(({recipient,...row})=>row),hasMore:false});
 }
 const messages=rows.slice(offset,offset+limit).map(({recipient,...row})=>row);
 res.json({status:'success',messages,hasMore:offset+messages.length<rows.length,nextOffset:offset+messages.length});
});
app.post('/acknowledgeMessage',(req,res)=>{
 const ids=req.body.messageIds;if(!Array.isArray(ids)||ids.length!==1||typeof ids[0]!=='string')return res.status(400).json({status:'error'});
 const own=[...deliveryFixture.inboxRows,...Array.from(accepted.values()).map(r=>r.message)].some(r=>r.recipient===req.auth.identityKey&&r.messageId===ids[0]);
 if(!own)return res.status(403).json({status:'error'});
 deliveryFixture.acks++;
 if(deliveryFixture.ackMode==='reject')return res.status(503).json({status:'error'});
 if(deliveryFixture.ackMode!=='retain')acknowledged.add(req.auth.identityKey+':'+ids[0]);
 if(deliveryFixture.ackMode==='drop'){req.socket.destroy();return;}
 res.json({status:'success'});
});
app.post('/sendMessage',async(req,res)=>{
 try {
  if(deliveryFixture.reject){deliveryFixture.reject=false;res.status(400).json({status:'error',description:'FIXTURE_REJECTED_PAYMENT_CHECK'});return;}
  const {message,payment}=req.body;
  if(!message?.messageId||!payment?.tx)throw Error('Missing fixture payment');
  const tx=Transaction.fromAtomicBEEF(payment.tx);
  if(tx.outputs[0].satoshis!==10||tx.outputs[1].satoshis!==10)throw Error('Incorrect amount');
  const bobKey=(await bob.getPublicKey({identityKey:true})).publicKey;
  const reader=message.recipient===bobKey?bob:alice;
  const ciphertext=JSON.parse(message.body).encryptedMessage;
  const decrypted=await reader.decrypt({protocolID:[1,'messagebox'],keyID:'1',counterparty:req.auth.identityKey,ciphertext:Utils.toArray(ciphertext,'base64')});
  const body=JSON.parse(Utils.toUTF8(decrypted.plaintext));if(!body.message.includes('"protocol":"crypton"'))throw Error('Missing v2 envelope');
  if(accepted.has(message.messageId)&&!isDeepStrictEqual(accepted.get(message.messageId),req.body))throw Error('Changed replay');
  if(!accepted.has(message.messageId)){accepted.set(message.messageId,req.body);senders.set(message.messageId,req.auth.identityKey);deliveryFixture.receiptCount++;}
  if(deliveryFixture.drop){deliveryFixture.drop=false;req.socket.destroy();return;}
  res.json({status:'success',messageId:message.messageId,results:[{recipient:message.recipient,messageId:message.messageId}]});
 }catch(error) {console.error('Fixture rejected:',error.message);res.status(400).json({status:'error',code:'FIXTURE_REJECTED'});}
});
app.listen(18777,'127.0.0.1',()=>console.log('MessageBox fixture ready on 127.0.0.1:18777'));
