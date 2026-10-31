import Foundation
import UIKit
import Security

/// iOS ME's documented browser deep link and ReactNativeWebView CWI transport.
/// Each request has a fresh loopback capability. Wallet results never travel in URL schemes.
@MainActor final class MEWallet: WalletConnection {
    private let open: @MainActor (URL) async -> Bool
    private let foreground: @MainActor () -> Bool
    private let backgroundTime: Bool
    private var server: LoopbackServer?
    private var continuation: CheckedContinuation<Any,Error>?
    private var timer: Task<Void,Never>?
    private var background: UIBackgroundTaskIdentifier = .invalid
    private var starting = false
    private var generation = UUID()
    private(set) var token = ""
    private(set) var origin = ""
    private var id = ""
    private var method = ""
    private var raw = false
    private var command: JSON?
    private var response: Result<Any,Error>?
    var waiting: ((Bool) -> Void)?
    private let scheme:String
    init(open: @escaping @MainActor (URL) async -> Bool = { await UIApplication.shared.open($0) },
         foreground: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .active },
         backgroundTime: Bool = true, scheme:String = "metanet") {
        self.open = open; self.foreground = foreground; self.backgroundTime = backgroundTime; self.scheme = scheme
    }
    static func handoffURL(_ target:URL,scheme:String = "metanet") throws -> URL {
        guard ["metanet","metanet-bob"].contains(scheme) else { throw CryptonError("Unsupported ME wallet application.") }
        var c = URLComponents(); c.scheme = scheme; c.host = "browser"
        c.queryItems = [URLQueryItem(name:"url",value:target.absoluteString)]
        guard let url = c.url else { throw CryptonError("Could not open Metanet Explorer.") }; return url
    }
    func call(_ method:String,_ args:JSON,raw:Bool = false) async throws -> Any {
        guard !starting, continuation == nil else { throw CryptonError("A wallet request is already in progress.") }
        let allowed = Set(["isAuthenticated","waitForAuthentication","getPublicKey","encrypt","decrypt","createHmac","verifyHmac","createSignature","verifySignature","createAction","listActions"])
        guard allowed.contains(method) || RecipientDiscovery.methods.contains(method) || (method == "getNetwork" && raw && args.isEmpty) else { throw CryptonError("Unsupported ME wallet request.") }
        let params = RecipientDiscovery.methods.contains(method) ? try RecipientDiscovery.arguments(method,args) : raw ? args : try Wire.walletArguments(method,args)
        guard try jsonData(params).count <= 500_000 else { throw CryptonError("ME request is too large.") }
        let run = UUID(); generation = run; starting = true
        let server = LoopbackServer(); self.server = server
        if backgroundTime {
            background = UIApplication.shared.beginBackgroundTask(withName:"Crypton wallet handoff") { [weak self] in
                // Expiration means the app may suspend, not that the wallet rejected
                // the request. Keep its capability and any received result until
                // foreground return or the bounded request deadline.
                guard let self = self, self.background != .invalid else { return }
                UIApplication.shared.endBackgroundTask(self.background); self.background = .invalid
            }
        }
        do {
            let port = try await server.start { [weak self] request,reply in
                Task { @MainActor in reply(self?.serve(request) ?? LoopbackResponse(status:410)) }
            }
            guard generation == run else { throw CancellationError() }
            try Task.checkCancellation()
            var random = [UInt8](repeating:0,count:32)
            guard SecRandomCopyBytes(kSecRandomDefault,random.count,&random) == errSecSuccess else { throw CryptonError("Could not create a secure wallet capability.") }
            token = Data(random).base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
            origin = "http://localhost:\(port)"; id = UUID().uuidString; self.method = method; self.raw = raw
            command = ["type":"CWI","isInvocation":true,"id":id,"call":method,"args":params]; response = nil; starting = false
            let target = URL(string:origin + "/" + token + "/")!
            let link = try Self.handoffURL(target,scheme:scheme)
            return try await withCheckedThrowingContinuation { done in
                continuation = done; waiting?(true)
                timer = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds:300_000_000_000) } catch { return }
                    self?.fail(CryptonError("ME did not respond in time. Return to Crypton and retry; your draft is still here."))
                }
                Task { [weak self] in
                    let opened = await self?.open(link) ?? false
                    guard let self = self, self.generation == run else { return }
                    if !opened { self.fail(CryptonError("Install and unlock Metanet Explorer on this iPhone, then retry.")) }
                }
            }
        } catch {
            if generation == run { finish(.failure(error)) }
            throw error
        }
    }
    /// A return URL carries no result. It only foregrounds Crypton for an already received response.
    @discardableResult func returned(_ url:URL) -> Bool {
        guard url.scheme == "crypton-wallet", url.host == "return", url.path == "/"+token,
              !token.isEmpty, url.query == nil, url.fragment == nil, url.user == nil, url.password == nil, url.port == nil else { return false }
        if foreground() { resumed() }; return true
    }
    func resumed() { if let response = response { finish(response) } }
    func cancel() { fail(CryptonError("Wallet request cancelled. Your draft is still here.")) }
    private func fail(_ error:Error) { finish(.failure(error)) }
    private func finish(_ result:Result<Any,Error>) {
        let done = continuation; continuation = nil
        generation = UUID(); starting = false; command = nil; response = nil; token = ""; origin = ""; id = ""
        timer?.cancel(); timer = nil; server?.stop(); server = nil; waiting?(false)
        if background != .invalid { UIApplication.shared.endBackgroundTask(background); background = .invalid }
        done?.resume(with:result)
    }
    // Internal for protocol tests. All routes still require the capability and exact Host/Origin.
    func serve(_ request:LoopbackRequest) -> LoopbackResponse {
        let prefix = "/"+token+"/"
        guard !token.isEmpty, request.headers["host"] == String(origin.dropFirst("http://".count)), request.path.hasPrefix(prefix) else { return LoopbackResponse(status:404) }
        let path = String(request.path.dropFirst(prefix.count))
        do {
            switch (request.method,path) {
            case ("GET",""):
                let html = """
                <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><title>Crypton wallet request</title>
                <body style="background:#0a1010;color:#f0f6f4;font:18px system-ui;padding:28px"><h1>Crypton</h1>
                <p id="status">Review the request in Metanet Explorer, then return to Crypton.</p>
                <a id="return" href="crypton-wallet://return/\(token)" hidden style="color:#00ebb3">Return to Crypton</a><p>If ME does not open the return link, switch back to Crypton using the app switcher.</p><script src="bridge.js"></script></body>
                """
                return LoopbackResponse(type:"text/html",body:Data(html.utf8))
            case ("GET","bridge.js"):
                guard let url = Bundle.main.url(forResource:"me",withExtension:"js",subdirectory:"Engine") else { return LoopbackResponse(status:500) }
                return LoopbackResponse(type:"application/javascript",body:try Data(contentsOf:url))
            case ("GET","next"):
                return LoopbackResponse(body:try jsonData(["finished":response != nil,"command":response == nil ? command as Any? ?? NSNull() : NSNull()]))
            case ("POST","result"):
                guard request.headers["origin"] == origin, request.headers["content-type"] == "application/json", continuation != nil else { return LoopbackResponse(status:403) }
                let value = try object(request.body)
                guard response == nil, value["id"] as? String == id, value["type"] as? String == "CWI", value["isInvocation"] as? Bool == false, integer(value["isInvocation"]) == nil else { return LoopbackResponse(status:409) }
                if value["status"] as? String == "success", let result = value["result"] as? JSON {
                    do {
                        if RecipientDiscovery.methods.contains(method), let args = command?["args"] as? JSON { response = .success(try RecipientDiscovery.response(result,args)) }
                        else { response = .success(raw ? result : try Wire.walletResult(method,result)) }
                    }
                    catch { response = .failure(error) }
                } else {
                    let detail = String((value["description"] as? String ?? "Review the wallet permission prompt and retry.").prefix(300))
                    response = .failure(CryptonError("ME declined \(method) (code \(integer(value["code"]) ?? 0)): \(detail)"))
                }
                // Keep the HTTP response/link available until foreground return. WebKit crypto work
                // resumes in Crypton, so a second permission request never launches from background.
                var reply = LoopbackResponse()
                #if DEBUG
                NSLog("Crypton ME response received: %@",method)
                #endif
                reply.sent = { [weak self] in Task { @MainActor in if self?.foreground() == true { self?.resumed() } } }
                return reply
            default: return LoopbackResponse(status:403)
            }
        } catch { return LoopbackResponse(status:400) }
    }
}
