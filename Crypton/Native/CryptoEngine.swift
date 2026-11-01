import WebKit

@MainActor final class CryptoEngine: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var web: WKWebView!
    private let wallet: WalletConnection
    private let store: DeliveryStore
    let inboxStore:InboxStore
    private var inboxSession:InboxSession?
    private var ready = false
    private var queued: (String, JSON)?
    private var pending: CheckedContinuation<Any, Error>?
    private var operation: String?
    private var delivery: (id: String, action: String)?
    private var sendAfterPreparation = false
    private var timingStarted: TimeInterval?
    private var discovery: (method:String,args:JSON)?
    private var discoveryRequested = false
    private var sharingIdentity = false
    private var timer: Task<Void,Never>?
    private var http: BoundedHTTP?
    var progress: ((String) -> Void)?
    private var root: URL?
    init(wallet: WalletConnection, store: DeliveryStore, inbox:InboxStore? = nil) {
        self.wallet = wallet; self.store = store; inboxStore = inbox ?? InboxStore(delivery:store)
        super.init()
        let controller = WKUserContentController()
        controller.add(self, name: "cryptonEngine")
        controller.addUserScript(WKUserScript(source:"window.cryptonEngine={postMessage:value=>window.webkit.messageHandlers.cryptonEngine.postMessage(value)};",injectionTime:.atDocumentStart,forMainFrameOnly:true))
        let config = WKWebViewConfiguration(); config.userContentController = controller; config.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: .zero, configuration: config); web.navigationDelegate = self
        if let url = Bundle.main.url(forResource:"engine",withExtension:"html",subdirectory:"Engine") {
            root = url.deletingLastPathComponent(); web.loadFileURL(url, allowingReadAccessTo: root!)
        }
    }
    func run(_ action: String, text: String = "", peer: String = "self") async throws -> Any {
        guard pending == nil else { throw CryptonError("Another Crypton request is in progress.") }
        if action == "open" { _ = try Wire.envelope(text) }
        if action == "seal" {
            if peer != "self" { _ = try Wire.identity(peer) }
            guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, text.utf16.count <= 16_000 else { throw CryptonError("Enter a message of at most 16,000 characters.") }
        }
        delivery = nil; discovery = nil; inboxSession = nil; sharingIdentity = action == "contactIdentity"
        return try await start("runCrypto", request:["action":action,"text":text,"peer":peer])
    }
    func search(_ query:String) async throws -> [DiscoveredIdentity] {
        guard pending == nil else { throw CryptonError("Another Crypton request is in progress.") }
        let request = try RecipientDiscovery.request(query)
        delivery = nil; inboxSession = nil; discovery = request; discoveryRequested = false
        return try RecipientDiscovery.identities(await start("runDiscovery",request:["method":request.method,"args":request.args]))
    }
    func deliver(_ action: String, id: String) async throws -> Any {
        guard pending == nil else { throw CryptonError("Another Crypton request is in progress.") }
        try store.begin(id,action:action); delivery = (id,action); discovery = nil; inboxSession = nil
        do { return try await start("runDelivery",request:["action":action,"record":try store.get(id)]) }
        catch { try? store.saveError(id,error); throw error }
    }
    /// One native ME visit covers quotation, revalidation and the final wallet review.
    /// Each phase still uses the existing journal and wallet/HTTP validators.
    func prepareAndSend(_ id:String) async throws -> Any {
        let me = wallet as? MEWallet
        me?.beginOperation(); defer { me?.endOperation() }
        guard pending == nil else { throw CryptonError("Another Crypton request is in progress.") }
        try store.begin(id,action:"prepare")
        delivery = (id,"prepare"); discovery = nil; inboxSession = nil; sendAfterPreparation = true
        defer { sendAfterPreparation = false }
        do { return try await start("runDelivery",request:["action":"prepareAndSend","record":try store.get(id)]) }
        catch { try? store.saveError(id,error); throw error }
    }
    func inbox(_ action:String,wallet:String = "",id:String = "",offset:Int = 0,layer:String = "") async throws -> JSON {
        guard pending == nil else { throw CryptonError("Another Crypton request is in progress.") }
        let session = try InboxSession(store:inboxStore,action:action,wallet:wallet,id:id,offset:offset,layer:layer)
        inboxSession = session; delivery = nil; discovery = nil
        let value = try await start("runInbox",request:["action":action,"wallet":wallet,"messageId":id,"offset":offset,"envelope":session.envelope,"host":inboxStore.host,"agent":inboxStore.agent])
        guard let result = value as? JSON, result["wallet"] as? String == session.wallet else { throw CryptonError("Invalid inbox response.") }; return result
    }
    private func start(_ function: String, request: JSON) async throws -> Any {
        guard pending == nil else { throw CryptonError("Another Crypton request is in progress.") }
        guard root != nil else { throw CryptonError("Bundled crypto engine is missing.") }
        let id = UUID().uuidString; operation = id; timingStarted = ProcessInfo.processInfo.systemUptime
        trace("start." + function)
        var request = request; request["id"] = id
        return try await withCheckedThrowingContinuation { continuation in
            (wallet as? MEWallet)?.beginOperation()
            pending = continuation; queued = (function, request)
            armTimeout(id)
            dispatch()
        }
    }
    /// Local timing only: operation ID, fixed stage names and monotonic elapsed time.
    /// No wallet keys, message content, transaction bytes or request arguments.
    private func trace(_ stage:String, token:String? = nil) {
        guard let id = operation, token == nil || token == id, let began = timingStarted else { return }
        NSLog("Crypton pipeline %@ %@ %.1fms",id,stage,(ProcessInfo.processInfo.systemUptime - began) * 1000)
    }
    private func armTimeout(_ id:String) {
        timer?.cancel()
        timer = Task { [weak self] in
            do { try await Task.sleep(nanoseconds:900_000_000_000) } catch { return }
            guard let self = self, self.operation == id else { return }
            self.cancel(reason:"Crypton timed out. Your draft and saved delivery record are still here.")
        }
    }
    private func dispatch() {
        guard ready, let job = queued else { return }; queued = nil
        do { web.evaluateJavaScript("\(job.0)(\(try jsonString(job.1))); void 0") { [weak self] _, error in if let error = error { self?.finish(.failure(error)) } } }
        catch { finish(.failure(error)) }
    }
    private func finish(_ result: Result<Any,Error>) {
        switch result { case .success: trace("complete"); case .failure: trace("failed") }
        timingStarted = nil; sendAfterPreparation = false
        (wallet as? MEWallet)?.endOperation()
        let done = pending; pending = nil; operation = nil; sharingIdentity = false; queued = nil; discovery = nil; inboxSession = nil; timer?.cancel(); timer = nil
        done?.resume(with:result)
    }
    func cancel(reason: String = "Crypton request cancelled. Your draft is still here.") {
        finish(.failure(CryptonError(reason))); wallet.cancel(); http?.cancel(); http = nil
        web.evaluateJavaScript("window.cancelCrypto && cancelCrypto()")
    }
    func close() { cancel(); web.configuration.userContentController.removeAllScriptMessageHandlers(); web.stopLoading() }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let url = message.frameInfo.request.url, url.isFileURL, url == root?.appendingPathComponent("engine.html"), let string = message.body as? String, string.utf8.count <= 8_000_000, let data = try? object(Data(string.utf8)) else { return }
        let event = data["event"] as? String ?? ""
        if event == "ready" { ready = true; dispatch(); return }
        guard let token = operation else { return }
        if event == "result" || event == "error" {
            guard data["id"] as? String == token else { return }
            if event == "result", let result = data["result"] { finish(.success(result)) }
            else { finish(.failure(CryptonError(data["message"] as? String ?? "Crypton operation failed."))) }; return
        }
        guard data["operation"] as? String == token, let id = data["id"] as? String else { return }
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let value: Any
                switch event {
                case "walletDiscovery":
                    guard let search = discovery, !discoveryRequested,
                          data["call"] as? String == search.method, sameJSON(data["args"],search.args) else { throw CryptonError("Unauthorized identity lookup.") }
                    discoveryRequested = true
                    value = try RecipientDiscovery.response(await wallet.call(search.method,search.args,raw:true),search.args)
                case "wallet":
                    if sharingIdentity, data["call"] as? String == "getPublicKey", sameJSON(data["args"],["identityKey":true]) {
                        value = try await wallet.call("getPublicKey",["identityKey":true],raw:false); break
                    }
                    guard let method = data["call"] as? String, let args = data["args"] as? JSON,
                          ["createHmac","decrypt"].contains(method), sameJSON(args["protocolID"],[2,"crypton"]), args["keyID"] as? String == "1" else { throw CryptonError("Unsupported engine wallet operation.") }
                    if method == "createHmac" {
                        guard args["counterparty"] as? String == "self", let encoded = args["data"] as? String,
                              let source = String(data:try Wire.base64(encoded),encoding:.utf8), source.range(of:"^crypton/messaging-identity/v1/[0-9]{1,3}$",options:.regularExpression) != nil else { throw CryptonError("Invalid receiving identity request.") }
                    } else { _ = try Wire.identity(args["counterparty"] as? String ?? "") }
                    try inboxSession?.beforeCrypto(method,args)
                    value = try await wallet.call(method,args,raw:false)
                case "walletSdk":
                    guard let method = data["call"] as? String, let args = data["args"] as? JSON else { throw CryptonError("Missing wallet authorization.") }
                    if let session = inboxSession {
                        try session.beforeWallet(method,args)
                        value = try await wallet.call(method,args,raw:true); try session.returned(method,args,value)
                        break
                    }
                    guard let session = delivery else { throw CryptonError("Missing delivery authorization.") }
                    #if DEBUG
                    NSLog("Crypton delivery wallet: %@",method)
                    #endif
                    try store.beforeWallet(session.id,action:session.action,method:method,args:args)
                    let reviewingPayment = method == "createAction" && wallet is MEWallet
                    if reviewingPayment { timer?.cancel(); timer = nil }
                    defer { if reviewingPayment, operation == token { armTimeout(token) } }
                    trace("wallet." + method + ".start",token:token)
                    defer { trace("wallet." + method + ".finished",token:token) }
                    do { value = try await wallet.call(method,args,raw:true) }
                    catch {
                        if method == "createAction", let refusal = error as? WalletRefusal, refusal.notCommitted { try store.walletRefused(session.id,refusal:refusal) }
                        throw error
                    }
                    // Save the returned transaction even if the user cancelled while the wallet was approving it.
                    if method == "createAction" { guard let result = value as? JSON else { throw CryptonError("Invalid wallet transaction.") }; try store.walletReturned(session.id,result:result) }
                case "checkpoint":
                    guard let kind = data["kind"] as? String, let v = data["value"] as? JSON else { throw CryptonError("Invalid checkpoint.") }
                    if let session = inboxSession { try session.checkpoint(kind,v) }
                    else if let session = delivery {
                        try store.checkpoint(session.id,action:session.action,kind:kind,value:v)
                        if sendAfterPreparation && kind == "prepared" {
                            try store.begin(session.id,action:"send"); delivery = (session.id,"send")
                        }
                    }
                    else { throw CryptonError("Missing checkpoint authorization.") }
                    trace("checkpoint." + kind); value = true
                case "http":
                    guard let request = data["request"] as? JSON else { throw CryptonError("Missing HTTP request.") }
                    if let address = request["url"] as? String, let url = URL(string:address) {
                        progress?(url.path == "/sendMessage" ? "Sending encrypted message with saved payment…" : url.path == "/permissions/quote" ? "Checking MessageBox delivery fee…" : "Authenticating with MessageBox…")
                    }
                    value = try await fetch(request)
                case "paymentProof":
                    guard let session = delivery, session.action == "recover" else { throw CryptonError("Payment proof recovery is unavailable.") }
                    value = try await paymentProof(store.recoveryTransaction(session.id))
                default: throw CryptonError("Unknown engine request.")
                }
                reply(token,id,value,nil)
            } catch {
                #if DEBUG
                NSLog("Crypton engine %@ failed: %@",event,error.localizedDescription)
                #endif
                reply(token,id,nil,error.localizedDescription)
            }
        }
    }
    private func reply(_ token: String, _ id: String, _ result: Any?, _ error: String?) {
        guard operation == token else { return }
        do { web.evaluateJavaScript("walletReply(\(try jsonString(id)),\(try jsonString(result ?? NSNull())),\(try jsonString(error as Any? ?? NSNull())))") }
        catch { finish(.failure(error)) }
    }
    private func fetch(_ input: JSON) async throws -> Any {
        guard let address = input["url"] as? String, let url = URL(string:address), let method = input["method"] as? String,
              let headers = input["headers"] as? [String:String], headers.count <= 128 else { throw CryptonError("Invalid MessageBox request.") }
        let body = input["body"] as? String ?? ""
        guard body.utf8.count <= 8_000_000 else { throw CryptonError("MessageBox request too large.") }
        if let session = inboxSession { try session.beforeHTTP(url,method,body) }
        else if let session = delivery { try store.beforeHTTP(session.id,action:session.action,url:url,method:method,body:body) }
        else { throw CryptonError("Missing MessageBox authorization.") }
        let timingToken = operation ?? ""
        trace("http." + url.path + ".start",token:timingToken)
        defer { trace("http." + url.path + ".finished",token:timingToken) }
        var request = URLRequest(url:url); request.httpMethod = method
        if method == "POST" { request.httpBody = Data(body.utf8) }
        for (key,value) in headers {
            guard key.range(of:"^[A-Za-z0-9-]{1,100}$",options:.regularExpression) != nil, value.count <= 32_000, !value.contains("\r"), !value.contains("\n"), !["host","connection","content-length","cookie","authorization"].contains(key.lowercased()) else { throw CryptonError("Invalid MessageBox header.") }
            request.setValue(value,forHTTPHeaderField:key)
        }
        let client = BoundedHTTP(limit:2_000_000); http = client; defer { http = nil }
        let (bodyData,response) = try await client.fetch(request)
        #if DEBUG
        NSLog("Crypton delivery HTTP %@ %@: %ld",method,url.path,response.statusCode)
        #endif
        var resultHeaders: [String:String] = [:]
        for (key,value) in response.allHeaderFields { resultHeaders[String(describing:key).lowercased()] = String(describing:value) }
        return ["status":response.statusCode,"headers":resultHeaders,"body":bodyData.base64EncodedString()] as JSON
    }
    private func paymentProof(_ txid:String) async throws -> JSON {
        let base = "https://api.whatsonchain.com/v1/bsv/main/"
        func get(_ path:String) async throws -> Data {
            let (data,response) = try await BoundedHTTP(limit:2_000_000).fetch(URLRequest(url:URL(string:base+path)!))
            guard response.statusCode == 200 else { throw CryptonError("Public payment proof is unavailable. Keep this saved delivery and retry recovery later.") }
            return data
        }
        let hex = String(decoding:try await get("tx/"+txid+"/hex"),as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
        let proofs = try JSONSerialization.jsonObject(with:try await get("tx/"+txid+"/proof/tsc")) as? [JSON]
        guard let proof = proofs?.first, proofs?.count == 1, proof["txOrId"] as? String == txid,
              let hash = proof["target"] as? String, hash.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil else { throw CryptonError("Wait for the saved payment's confirmation, then retry recovery.") }
        let block = try object(await get("block/hash/"+hash))
        return ["hex":hex,"proof":proof,"block":["hash":block["hash"] ?? NSNull(),"height":block["height"] ?? NSNull(),"merkleroot":block["merkleroot"] ?? NSNull()]]
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let allowed = navigationAction.request.url == root?.appendingPathComponent("engine.html")
        decisionHandler(allowed ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { ready = false; finish(.failure(CryptonError("Crypto engine stopped. Clear the wallet session and retry."))) }
}
