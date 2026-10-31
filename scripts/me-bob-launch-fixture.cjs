// Opt-in ME Bob UI smoke test: static loopback page, no wallet APIs or accounts.
const http = require('node:http');
http.createServer((req,res)=>{
  if(req.method!=='GET'||req.url!=='/test/bob-route-check'){res.writeHead(404);res.end();return;}
  res.writeHead(200,{'Content-Type':'text/html; charset=utf-8','Content-Security-Policy':"default-src 'none'"});
  res.end('<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Crypton Bob handoff test</title></head><body><h1>Crypton ME Bob handoff verified</h1><p>Disposable local page. No wallet account, permission or payment was used.</p></body></html>');
}).listen(18778,'127.0.0.1',()=>console.log('Bob handoff page ready on 127.0.0.1:18778'));
