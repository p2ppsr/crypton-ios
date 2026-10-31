// Loopback-only authenticated MessageBox and fake payment wallet. No accounts, broadcasting or real money.
const {isDeepStrictEqual}=require('node:util');
const {alice,bob,deliveryFixture,load}=require('./sdk-wallet-fixture.cjs');
const {ProtoWallet,PrivateKey,Transaction,Utils}=load('@bsv/sdk');
const express=load('express');const {createAuthMiddleware}=load('@bsv/auth-express-middleware');
const serverWallet=new ProtoWallet(new PrivateKey(2));const accepted=new Map();
const app=express();app.use(express.json({limit:'8mb'}));app.use(express.raw({type:'application/octet-stream',limit:'8mb'}));
app.use(createAuthMiddleware({wallet:serverWallet,allowUnauthenticated:false}));
app.get('/permissions/quote',(req,res)=>res.json({status:'success',quote:{deliveryFee:deliveryFixture.changedFee?11:10,recipientFee:10}}));
app.post('/sendMessage',async(req,res)=>{
 try {
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
  if(!accepted.has(message.messageId)){accepted.set(message.messageId,req.body);deliveryFixture.receiptCount++;}
  if(deliveryFixture.drop){deliveryFixture.drop=false;req.socket.destroy();return;}
  res.json({status:'success',messageId:message.messageId,results:[{recipient:message.recipient,messageId:message.messageId}]});
 }catch(error) {console.error('Fixture rejected:',error.message);res.status(400).json({status:'error',code:'FIXTURE_REJECTED'});}
});
app.listen(18777,'127.0.0.1',()=>console.log('MessageBox fixture ready on 127.0.0.1:18777'));
