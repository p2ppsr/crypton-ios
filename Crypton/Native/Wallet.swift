import Foundation
import WebKit
import UIKit

/// A bounded, cookie-free HTTP request. Redirects never change a wallet or delivery destination.
final class BoundedHTTP: NSObject, URLSessionDataDelegate {
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    private var data = Data()
    private var response: HTTPURLResponse?
    private let limit: Int
    init(limit: Int = 8_000_000) { self.limit = limit }
    @MainActor func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil; config.urlCache = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.timeoutIntervalForRequest = 90; config.timeoutIntervalForResource = 120
            session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
            task = session!.dataTask(with: request); task!.resume()
        }
    }
    func cancel() { finish(.failure(CryptonError("Request cancelled. Your draft is still here."))) }
    private func finish(_ result: Result<(Data, HTTPURLResponse), Error>) {
        guard let done = continuation else { return }; continuation = nil
        task?.cancel(); session?.invalidateAndCancel(); task = nil; session = nil
        done.resume(with: result)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil); finish(.failure(CryptonError("The server redirected the request. Check its address.")))
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, response.expectedContentLength <= limit else { completionHandler(.cancel); finish(.failure(CryptonError("The response is too large."))); return }
        self.response = http; completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard self.data.count + data.count <= limit else { finish(.failure(CryptonError("The response is too large."))); return }
        self.data.append(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error { finish(.failure(error)) }
        else if let response = response { finish(.success((data, response))) }
        else { finish(.failure(CryptonError("The server returned no response."))) }
    }
}

@MainActor protocol WalletConnection: AnyObject {
    func call(_ method: String, _ args: JSON, raw: Bool) async throws -> Any
    func cancel()
}

@MainActor final class JSONWallet: WalletConnection {
    let endpoint: URL
    private var active: BoundedHTTP?
    init(endpoint: URL) { self.endpoint = endpoint }
    func call(_ method: String, _ args: JSON, raw: Bool = false) async throws -> Any {
        guard active == nil else { throw CryptonError("A wallet request is already in progress.") }
        let allowed = Set(["isAuthenticated","waitForAuthentication","getPublicKey","encrypt","decrypt","createHmac","verifyHmac","createSignature","verifySignature","createAction","listActions"])
        guard allowed.contains(method) else { throw CryptonError("Unsupported wallet request.") }
        let params = raw ? args : try Wire.walletArguments(method, args)
        let body = try jsonData(params)
        guard body.count <= 500_000 else { throw CryptonError("Wallet request too large.") }
        var request = URLRequest(url: endpoint.appendingPathComponent(method))
        request.httpMethod = "POST"; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://crypton.ios", forHTTPHeaderField: "Origin")
        request.setValue("https://crypton.ios", forHTTPHeaderField: "Originator")
        let http = BoundedHTTP(); active = http; defer { active = nil }
        let (bytes, response) = try await http.fetch(request)
        guard (200..<300).contains(response.statusCode) else { throw CryptonError("Wallet request failed (HTTP \(response.statusCode)). Open your wallet and retry.") }
        let result = try object(bytes)
        guard result["isError"] as? Bool != true else { throw CryptonError("The wallet declined the request. Check its permission prompt and retry.") }
        return raw ? result : try Wire.walletResult(method, result)
    }
    func cancel() { active?.cancel() }
}

/// The original iPhone portal contract, with origin and UUID checks around every callback.
@MainActor final class PortalWallet: NSObject, WalletConnection, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    static let origin = "https://mobile-portal.babbage.systems"
    var visibility: ((Bool) -> Void)?
    private(set) var web: WKWebView!
    private var load: CheckedContinuation<Void, Error>?
    private var pending: (id: String, continuation: CheckedContinuation<Any, Error>)?
    private var timer: Task<Void, Never>?
    private var loaded = false
    private var authenticated = false
    override init() {
        super.init()
        let controller = WKUserContentController()
        let script = """
        (() => {
          if (location.origin !== '\(Self.origin)') return;
          const send = (event,payload) => window.webkit.messageHandlers.portal.postMessage({event,payload});
          const bridge = {openBabbage:()=>send('open'),closeBabbage:()=>send('close'),isFocused:()=>send('focus')};
          ['isAuthenticated','waitForAuthentication','getPublicKey','encrypt','decrypt'].forEach(call=>bridge[call]=value=>{
            try{send('response',typeof value==='string'?JSON.parse(value):value)}catch{send('invalid')}
          });
          Object.defineProperty(window,'androidMessageHandler',{value:bridge});
          // The iOS portal also invokes named WK message handlers directly.
        })();
        """
        controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        for name in ["portal","openBabbage","closeBabbage","isFocused","isAuthenticated","waitForAuthentication","getPublicKey","encrypt","decrypt"] { controller.add(self, name: name) }
        let config = WKWebViewConfiguration(); config.userContentController = controller
        web = WKWebView(frame: .zero, configuration: config); web.navigationDelegate = self; web.uiDelegate = self
        web.customUserAgent = "babbage-webview-inlay"
    }
    private func trusted(_ url: URL?) -> Bool { url?.scheme == "https" && url?.host == "mobile-portal.babbage.systems" && (url?.port == nil || url?.port == 443) }
    private func ensureLoaded() async throws {
        if loaded { return }
        guard load == nil else { throw CryptonError("The wallet is already connecting.") }
        try await withCheckedThrowingContinuation { continuation in
            load = continuation
            arm(30)
            web.load(URLRequest(url: URL(string: Self.origin)!))
        }
    }
    func call(_ method: String, _ args: JSON, raw: Bool = false) async throws -> Any {
        guard !raw, ["isAuthenticated","waitForAuthentication","getPublicKey","encrypt","decrypt"].contains(method) else { throw CryptonError("This operation needs a BRC-100 wallet. Choose one in Settings; the original portal supports legacy messages.") }
        try await ensureLoaded()
        if !authenticated && !["isAuthenticated","waitForAuthentication"].contains(method) { try await authenticate() }
        return try await request(method, args)
    }
    func authenticate() async throws {
        try await ensureLoaded()
        let signedIn = try await request("isAuthenticated", [:])
        if signedIn as? Bool != true && signedIn as? String != "true" {
            visibility?(true)
            let result = try await request("waitForAuthentication", [:])
            guard result as? Bool == true || result as? String == "true" else { throw CryptonError("Wallet sign-in was not completed.") }
        }
        authenticated = true; visibility?(false)
    }
    private func request(_ method: String, _ args: JSON) async throws -> Any {
        guard pending == nil else { throw CryptonError("A wallet request is already in progress.") }
        let id = UUID().uuidString
        let command: JSON = ["type":"CWI","call":method,"params":args,"originator":"iOS_" + (Bundle.main.bundleIdentifier ?? "com.projectbabbage.Crypton"),"id":id]
        let script = "window.postMessage(\(try jsonString(command)), \(try jsonString(Self.origin)))"
        return try await withCheckedThrowingContinuation { continuation in
            web.configuration.userContentController.add(self, name: id)
            pending = (id, continuation); arm(method == "waitForAuthentication" ? 300 : 90)
            web.evaluateJavaScript(script) { [weak self] _, error in if let error = error { self?.fail(error) } }
        }
    }
    private func arm(_ seconds: UInt64) {
        timer?.cancel(); timer = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: seconds * 1_000_000_000) } catch { return }
            self?.fail(CryptonError("The wallet timed out. Your draft is still here; reconnect and retry."))
        }
    }
    private func fail(_ error: Error) {
        timer?.cancel(); timer = nil
        let loading = load; load = nil; let request = pending; pending = nil
        loaded = false; authenticated = false; visibility?(false)
        if let request = request { web.configuration.userContentController.removeScriptMessageHandler(forName: request.id) }
        loading?.resume(throwing: error); request?.continuation.resume(throwing: error)
    }
    func cancel() { web.stopLoading(); fail(CryptonError("Wallet request cancelled. Your draft is still here.")) }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, trusted(message.frameInfo.request.url) else { return }
        var body = message.body as? JSON
        if let string = message.body as? String { body = try? object(Data(string.utf8)) }
        let event = message.name == "portal" ? body?["event"] as? String : message.name
        switch event {
        case "open", "openBabbage": visibility?(true)
        case "close", "closeBabbage": visibility?(false)
        case "focus", "isFocused":
            web.evaluateJavaScript("window.postMessage({type:'CWI',call:'isFocused',params:{isFocused:true}},'\(Self.origin)')")
        default:
            let response = message.name == "portal" ? body?["payload"] as? JSON : body
            guard let r = response, let job = pending, (message.name == job.id || (r["uuid"] as? String ?? r["id"] as? String) == job.id) else { return }
            pending = nil; web.configuration.userContentController.removeScriptMessageHandler(forName: job.id)
            timer?.cancel(); timer = nil; visibility?(false)
            if r["status"] as? String == "error" || r["error"] as? Bool == true { job.continuation.resume(throwing: CryptonError(r["description"] as? String ?? "The wallet rejected the request.")) }
            else if let result = r["result"], !(result is NSNull) { job.continuation.resume(returning: result) }
            else { job.continuation.resume(throwing: CryptonError("The wallet returned an incomplete response.")) }
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if trusted(navigationAction.request.url) { decisionHandler(.allow) }
        else { decisionHandler(.cancel); if navigationAction.targetFrame?.isMainFrame == true { fail(CryptonError("The wallet left its trusted address.")) } }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard trusted(webView.url) else { return }; loaded = true; timer?.cancel(); timer = nil
        let done = load; load = nil; done?.resume()
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { fail(CryptonError("The wallet page closed. Reconnect and retry.")) }
    private func presentDialog(_ message:String, confirm:Bool, done:@escaping (Bool) -> Void) {
        guard let scene = UIApplication.shared.connectedScenes.first(where:{ $0.activationState == .foregroundActive }) as? UIWindowScene,
              var controller = scene.windows.first(where:{ $0.isKeyWindow })?.rootViewController else { done(false); return }
        while let presented = controller.presentedViewController { controller = presented }
        let alert = UIAlertController(title:"Wallet",message:message,preferredStyle:.alert)
        alert.addAction(UIAlertAction(title:"OK",style:.default) { _ in done(true) })
        if confirm { alert.addAction(UIAlertAction(title:"Cancel",style:.cancel) { _ in done(false) }) }
        controller.present(alert,animated:true)
    }
    func webView(_ webView:WKWebView,runJavaScriptAlertPanelWithMessage message:String,initiatedByFrame frame:WKFrameInfo,completionHandler:@escaping () -> Void) {
        guard frame.isMainFrame, trusted(frame.request.url) else { completionHandler(); return }
        presentDialog(message,confirm:false) { _ in completionHandler() }
    }
    func webView(_ webView:WKWebView,runJavaScriptConfirmPanelWithMessage message:String,initiatedByFrame frame:WKFrameInfo,completionHandler:@escaping (Bool) -> Void) {
        guard frame.isMainFrame, trusted(frame.request.url) else { completionHandler(false); return }
        presentDialog(message,confirm:true,done:completionHandler)
    }
    func close() { cancel(); web.configuration.userContentController.removeAllScriptMessageHandlers() }
}
