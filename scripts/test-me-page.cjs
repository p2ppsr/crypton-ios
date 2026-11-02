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
  sandbox.crypto=require('node:crypto').webcrypto;
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
    assert.equal(sandbox.location.href,'','Only native ME may perform the app return');
    const callsAtCompletion = nextCalls; await pause(350);
    assert.equal(nextCalls,callsAtCompletion,'A completed page must not poll a closed localhost listener');
    console.log('ME page: duplicate response channels, slow acknowledgement, queued calls and native return passed.');
  } finally {for(const timer of timers)clearTimeout(timer);}
})().catch(error=>{console.error(error);process.exitCode=1;});

(async () => {
  const timers=new Set(), events={}, invocations=[], returns=[];
  let reads=0, saves=0;
  const doc={hidden:true,getElementById:id=>id==='status'?{textContent:''}:{href:'crypton-wallet://return/hidden',hidden:true,addEventListener:()=>{}}};
  const sandbox={AbortController,clearTimeout,document:doc,location:{href:''},setTimeout:(fn,ms)=>{const t=setTimeout(fn,ms);timers.add(t);return t},fetch:async path=>{
    if(path==='result'){saves++;return {ok:true}}
    reads++;return {ok:true,json:async()=>({session:true,finished:saves===1,command:saves?null:{id:'visible-only',call:'getNetwork',type:'CWI',isInvocation:true,args:{}}})}
  }};
  sandbox.window=sandbox;sandbox.addEventListener=(name,fn)=>{events[name]=fn};
  sandbox.ReactNativeWebView={postMessage:text=>{const m=JSON.parse(text);(m.type==='CRYPTON_RETURN'?returns:invocations).push(m)}};
  sandbox.crypto=require('node:crypto').webcrypto;
  vm.createContext(sandbox);
  try {
    vm.runInContext(fs.readFileSync('Crypton/Engine/me.js','utf8'),sandbox);
    await pause(180);assert.equal(reads,0,'Hidden ME must not consume or dispatch wallet commands');
    doc.hidden=false;await pause(180);assert.equal(invocations.length,1);
    doc.hidden=true;await events.message({source:null,data:{id:'visible-only',type:'CWI',isInvocation:false,status:'success',result:{network:'mainnet'}}});
    await pause(180);assert.equal(saves,1);assert.equal(returns.length,0,'Saving a completed response must not force a hidden app return');
    doc.hidden=false;await pause(180);assert.equal(returns.length,1);
    const finalReads=reads;await pause(1700);
    assert.equal(sandbox.location.href,'','A missing native acknowledgement must not trigger a delayed URL navigation');
    assert.equal(reads,finalReads,'Completion must stop polling even without a return acknowledgement');
    console.log('ME page: hidden-page dispatch, completed result save, stopped polling and no unsafe URL fallback passed.');
  } finally { for(const timer of timers)clearTimeout(timer) }
})().catch(error=>{console.error(error);process.exitCode=1});

(async () => {
  const timers=new Set(), events={}, invocations=[], returns=[];
  let saves=0, reads=0, saved=false, finished=false;
  const status={textContent:''}, link={href:'crypton-wallet://return/lost-ack',hidden:true,addEventListener:()=>{}};
  const doc={hidden:false,addEventListener:(name,fn)=>{events[name]=fn},getElementById:id=>id==='status'?status:link};
  const sandbox={AbortController,clearTimeout,document:doc,location:{href:''},setTimeout:(fn,ms)=>{const t=setTimeout(fn,ms);timers.add(t);return t},fetch:async path=>{
    if(path==='result') {
      saves++;
      if(saves===1){saved=true;throw Error('HTTP response lost after native save')}
      assert.equal(saved,true);
      if(saves===3)finished=true;
      return {ok:true}; // Native idempotent acknowledgement of the same response.
    }
    reads++;return {ok:true,json:async()=>({session:true,finished,command:finished?null:{id:saved?'second':'first',call:'getNetwork',type:'CWI',isInvocation:true,args:{}}})};
  }};
  sandbox.window=sandbox;sandbox.addEventListener=(name,fn)=>{events[name]=fn};
  sandbox.ReactNativeWebView={postMessage:text=>{
    const m=JSON.parse(text);
    if(m.type==='CRYPTON_RETURN') {
      returns.push(m);
      if(!finished)doc.hidden=true; // Crypton foregrounds to restore its listener.
      void events.message({source:null,data:{type:'CRYPTON_RETURN_STATUS',accepted:true}});
    } else invocations.push(m);
  }};
  sandbox.crypto=require('node:crypto').webcrypto;
  vm.createContext(sandbox);
  const deliver=async id=>events.message({source:null,data:{id,type:'CWI',isInvocation:false,status:'success',result:{network:'mainnet'}}});
  try {
    vm.runInContext(fs.readFileSync('Crypton/Engine/me.js','utf8'),sandbox);
    await pause(30);assert.equal(invocations.length,1);
    await deliver('first');await pause(180);
    assert.equal(saves,2,'A lost HTTP reply retries the same result');
    assert.equal(invocations.length,1,'A hidden recovery page cannot dispatch the next wallet request');
    assert.equal(returns.length,1);
    const hiddenReads=reads;await pause(180);assert.equal(reads,hiddenReads);
    doc.hidden=false;events.visibilitychange();await pause(180); // Native Crypton reopens ME for the queued request.
    assert.equal(invocations.length,2);assert.equal(invocations[1].id,'second');
    await deliver('second');await pause(180);
    assert.equal(saves,3);assert.equal(returns.length,2);
    assert.equal(status.textContent,'Operation finished. Returning to Crypton…');
    console.log('ME page: lost HTTP acknowledgement, same-result retry, hidden recovery and next-command continuation passed.');
  } finally {for(const timer of timers)clearTimeout(timer)}
})().catch(error=>{console.error(error);process.exitCode=1});

(async () => {
  const timers=new Set(), events={}, invocations=[], bodies=[];
  let click, online=false, saved=false, posts=0;
  const status={textContent:''}, link={href:'crypton-wallet://return/retained-result',hidden:true,addEventListener:(name,fn)=>{if(name==='click')click=fn}};
  const sandbox={AbortController,clearTimeout,document:{hidden:false,addEventListener:(name,fn)=>{events[name]=fn},getElementById:id=>id==='status'?status:link},location:{href:''},
    setTimeout:(fn,ms)=>{const t=setTimeout(fn,Math.min(ms,8));timers.add(t);return t},
    fetch:async(path,options)=>{
      if(path==='result') { posts++;bodies.push(options.body);if(!online)throw Error('Crypton suspended');saved=true;return {ok:true} }
      return {ok:true,json:async()=>({finished:saved,command:saved?null:{id:'retained-payment',call:'createAction',type:'CWI',isInvocation:true,args:{}}})};
    }
  };
  sandbox.window=sandbox;sandbox.addEventListener=(name,fn)=>{events[name]=fn};
  sandbox.ReactNativeWebView={postMessage:text=>{
    const value=JSON.parse(text);
    if(value.type==='CRYPTON_RETURN')void events.message({source:null,data:{type:'CRYPTON_RETURN_STATUS',accepted:online}});
    else invocations.push(value);
  }};
  sandbox.crypto=require('node:crypto').webcrypto;
  vm.createContext(sandbox);
  try {
    vm.runInContext(fs.readFileSync('Crypton/Engine/me.js','utf8'),sandbox);
    await pause(20);assert.equal(invocations.length,1);
    await events.message({source:null,data:{id:'retained-payment',type:'CWI',isInvocation:false,status:'error',code:1,description:'Payment review expired',executionStatus:'not-committed'}});
    assert.equal(posts,8);assert.match(status.textContent,/retained on this page/);assert.equal(link.hidden,false);
    await pause(40);assert.equal(posts,8,'Retries must remain bounded while the prompt blocks return');
    online=true;click({preventDefault(){}});await pause(20);
    // Returning for a result save must pause dispatch until ME becomes visible again.
    sandbox.document.hidden=true; sandbox.document.hidden=false; events.visibilitychange();await pause(70);
    assert(saved,'Manual return after bounded retries must save the retained terminal result');
    assert.equal(invocations.length,1,'Never replay createAction to recover an old result');
    assert(bodies.every(body=>body===bodies[0]),'Only the identical completed response may be retried');
    assert.equal(status.textContent,'Operation finished. Returning to Crypton…');
    console.log('ME page: terminal result retained after exhausted retries; manual return saves it without another wallet call.');
  } finally {for(const t of timers)clearTimeout(t)}
})().catch(error=>{console.error(error);process.exitCode=1});


(async () => {
  const timers=new Set(), events={}, calls=[], returns=[], owners=[];
  let reads=0, saved=false;
  const status={textContent:''}, link={href:'crypton-wallet://return/lost-command',hidden:true,addEventListener:()=>{}};
  const sandbox={AbortController,clearTimeout,crypto:require('node:crypto').webcrypto,
    document:{hidden:false,getElementById:id=>id==='status'?status:link},
    setTimeout:(fn,ms)=>{const t=setTimeout(fn,Math.min(ms,10));timers.add(t);return t},
    fetch:async(path,options)=>{
      if(path==='result'){saved=true;return {ok:true}}
      reads++;owners.push(options.headers['X-Crypton-Page']);
      if(reads===1)throw Error('Response lost after native command claim');
      return {ok:true,json:async()=>({finished:saved,command:saved?null:{id:'same-command',call:'createAction',type:'CWI',isInvocation:true,args:{}}})};
    }
  };
  sandbox.window=sandbox;sandbox.addEventListener=(name,fn)=>{events[name]=fn};
  sandbox.ReactNativeWebView={postMessage:text=>{const m=JSON.parse(text);(m.type==='CRYPTON_RETURN'?returns:calls).push(m)}};
  vm.createContext(sandbox);
  try {
    vm.runInContext(fs.readFileSync('Crypton/Engine/me.js','utf8'),sandbox);
    await pause(60);
    assert.equal(reads,2);assert.equal(new Set(owners).size,1,'Lost responses must retain their page owner');
    assert.equal(returns.length,0,'An idle read failure must not switch apps before dispatch');
    assert.equal(calls.length,1);assert.equal(calls[0].id,'same-command');
    await events.message({source:null,data:{id:'same-command',type:'CWI',isInvocation:false,status:'success',result:{}}});
    await pause(30);assert.equal(calls.length,1,'Recovering a command cannot invoke it twice');
    assert.equal(returns.length,1);
    console.log('ME page: lost command response recovers on the owning page, with no early return or duplicate payment invocation.');
  } finally {for(const t of timers)clearTimeout(t)}
})().catch(error=>{console.error(error);process.exitCode=1});

(async () => {
  const timers=new Set(), events={}, calls=[], returns=[];
  let walletFinished=false;
  const status={textContent:''}, link={href:'crypton-wallet://return/network',hidden:true,addEventListener:()=>{}};
  const sandbox={AbortController,clearTimeout,crypto:require('node:crypto').webcrypto,
    document:{hidden:false,getElementById:id=>id==='status'?status:link},
    setTimeout:(fn,ms)=>{const t=setTimeout(fn,Math.min(ms,10));timers.add(t);return t},
    fetch:async path=>{
      if(path==='result'){walletFinished=true;return {ok:true}}
      return {ok:true,json:async()=>({finished:false,foregroundRequired:walletFinished,command:walletFinished?null:{id:'payment-first',call:'createAction',type:'CWI',isInvocation:true,args:{}}})};
    }
  };
  sandbox.window=sandbox;sandbox.addEventListener=(name,fn)=>{events[name]=fn};
  sandbox.ReactNativeWebView={postMessage:text=>{const m=JSON.parse(text);(m.type==='CRYPTON_RETURN'?returns:calls).push(m)}};
  vm.createContext(sandbox);
  try {
    vm.runInContext(fs.readFileSync('Crypton/Engine/me.js','utf8'),sandbox);
    await pause(40);assert.equal(calls.length,1);assert.equal(returns.length,0,'Never leave an outstanding wallet payment');
    await events.message({source:null,data:{id:'payment-first',type:'CWI',isInvocation:false,status:'success',result:{}}});
    await pause(40);assert.equal(returns.length,1);assert.equal(calls.length,1);
    assert.match(status.textContent,/MessageBox networking/);
    console.log('ME page: explicit network handoff returns only after the wallet result is saved; no payment is interrupted or replayed.');
  } finally {for(const t of timers)clearTimeout(t)}
})().catch(error=>{console.error(error);process.exitCode=1});
