// Reproduce installed ME's dual response channels and a slow result acknowledgement.
const assert = require('node:assert/strict');
const fs = require('node:fs'), vm = require('node:vm');
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
(async () => {
  const timers = new Set(), listeners = {}, invocations = [], returns = [];
  let nextCalls = 0, saves = 0, release, finished = false;
  const status = {textContent:''}, link = {href:'crypton-wallet://return/disposable',hidden:true,addEventListener:()=>{}};
  const sandbox = {AbortController,clearTimeout,console,document:{getElementById:id=>id==='status'?status:link},location:{href:''},
    setTimeout:(fn,ms)=>{const timer=setTimeout(fn,ms);timers.add(timer);return timer;},
    fetch:async path=>{
      if(path==='next') { nextCalls++; return {ok:true,json:async()=>({session:true,finished,command:finished?null:{id:String(nextCalls),call:'getNetwork',type:'CWI',isInvocation:true,args:{}}})}; }
      assert.equal(path,'result'); saves++;
      if(saves===1) await new Promise(resolve=>{release=resolve;});
      if(saves===2) finished=true;
      return {ok:true};
    }
  };
  sandbox.window=sandbox;
  sandbox.addEventListener=(name,fn)=>{listeners[name]=fn;};
  sandbox.ReactNativeWebView={postMessage:text=>{
    const message=JSON.parse(text);
    if(message.type==='CRYPTON_RETURN') {returns.push(message);void listeners.message({source:sandbox,data:{type:'CRYPTON_RETURN_STATUS',accepted:true}});}
    else invocations.push(message);
  }};
  vm.createContext(sandbox);
  const deliver=async id=>{
    const event={source:null,data:{id,type:'CWI',isInvocation:false,status:'success',result:{network:'mainnet'}}};
    // ReactNativeWebView.postMessage and ME's injected window MessageEvent.
    void listeners.message(event);void listeners.message(event);await pause(10);
  };
  try {
    vm.runInContext(fs.readFileSync('Crypton/Engine/me.js','utf8'),sandbox);
    await pause(20);assert.equal(invocations.length,1);
    await deliver('1');await pause(320);
    assert.equal(saves,1,'Duplicate wallet responses must have a single result save');
    assert.equal(nextCalls,1,'A slow acknowledgement must not consume the next command');
    release();await pause(180);assert.equal(invocations.length,2);
    await deliver('2');await pause(180);
    assert.equal(saves,2);assert.equal(returns.length,1);
    assert.equal(status.textContent,'Operation finished. Returning to Crypton…');
    assert.equal(sandbox.location.href,'','Native acknowledgement suppresses the old URL fallback');
    console.log('ME page: duplicate response channels, slow acknowledgement, queued calls and native return passed.');
  } finally {for(const timer of timers)clearTimeout(timer);}
})().catch(error=>{console.error(error);process.exitCode=1;});
