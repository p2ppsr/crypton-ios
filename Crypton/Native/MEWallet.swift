import Foundation
import UIKit
import Security
import CryptoKit

/// iOS ME's documented browser deep link and ReactNativeWebView CWI transport.
/// Each operation has a fresh loopback capability and each call a fresh UUID. Wallet results never travel in URL schemes.
@MainActor final class MEWallet: WalletConnection {
    private let open: @MainActor (URL) async -> Bool
    private let foreground: @MainActor () -> Bool
    private let backgroundTime: Bool
    private let requestTimeoutNanoseconds: UInt64
    private var server: LoopbackServer?
    private var continuation: CheckedContinuation<Any,Error>?
    private var timer: Task<Void,Never>?
    private var background: UIBackgroundTaskIdentifier = .invalid
    private var starting = false
    private var session = false
    private var operationDepth = 0
    private var sessionFinished = false
    private var closeTimer: Task<Void,Never>?
    var progress: ((String) -> Void)?
    private var generation = UUID()
    private var sessionBegan = ProcessInfo.processInfo.systemUptime
    private(set) var token = ""
    private(set) var origin = ""
    private var id = ""
    private var method = ""
    private var raw = false
    private var command: JSON?
    private var issued = false
    private var commandPageID:String?
    private var response: Result<Any,Error>?
    // A lost HTTP acknowledgement must not turn a saved response into a stale
    // UUID error when the engine has already queued its next wallet method.
    private var savedResults: [String:Data] = [:]
    private var savedResultOrder: [String] = []
    private var reopenAfterRecovery = false
    var waiting: ((Bool) -> Void)?
    private let scheme:String
    init(open: @escaping @MainActor (URL) async -> Bool = { await UIApplication.shared.open($0) },
         foreground: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .active },
         backgroundTime: Bool = true, scheme:String = "metanet", requestTimeoutNanoseconds:UInt64 = 300_000_000_000) {
        self.open = open; self.foreground = foreground; self.backgroundTime = backgroundTime; self.scheme = scheme
        self.requestTimeoutNanoseconds = requestTimeoutNanoseconds
    }
    static func handoffURL(_ target:URL,scheme:String = "metanet",pairing:[URLQueryItem] = []) throws -> URL {
        guard ["metanet","metanet-bob"].contains(scheme) else { throw CryptonError("Unsupported ME wallet application.") }
        var c = URLComponents(); c.scheme = scheme; c.host = "browser"
        c.queryItems = [URLQueryItem(name:"url",value:target.absoluteString),URLQueryItem(name:"target",value:"current")] + pairing
        guard let url = c.url else { throw CryptonError("Could not open Metanet Explorer.") }; return url
    }
    var pairingCode:String { (try? NativeWalletPairing.code()) ?? "Unavailable" }
    /// Keep one capability page alive across the validated engine operation.
    func beginOperation() { if sessionFinished { closeSession() }; operationDepth += 1; session = true; sessionFinished = false; closeTimer?.cancel() }
    func endOperation() {
        guard session else { return }
        operationDepth = max(0,operationDepth - 1)
        guard operationDepth == 0 else { return }
        sessionFinished = true; command = nil; waiting?(false)
        if foreground() { closeSession(); return }
        // Give the ME page time to observe completion and request its exact callback.
        closeTimer = Task { [weak self] in
            do { try await Task.sleep(nanoseconds:30_000_000_000) } catch { return }
            self?.closeSession()
        }
    }
    func call(_ method:String,_ args:JSON,raw:Bool = false) async throws -> Any {
        if sessionFinished { closeSession() }
        guard !starting, continuation == nil else { throw CryptonError("A wallet request is already in progress.") }
        let allowed = Set(["isAuthenticated","waitForAuthentication","getPublicKey","encrypt","decrypt","createHmac","verifyHmac","createSignature","verifySignature","createAction","listActions"])
        guard allowed.contains(method) || RecipientDiscovery.methods.contains(method) || (method == "getNetwork" && raw && args.isEmpty) else { throw CryptonError("Unsupported ME wallet request.") }
        let params = RecipientDiscovery.methods.contains(method) ? try RecipientDiscovery.arguments(method,args) : raw ? args : try Wire.walletArguments(method,args)
        guard try jsonData(params).count <= 500_000 else { throw CryptonError("ME request is too large.") }
        if session, server != nil, !sessionFinished {
            return try await request(method,params,raw:raw,openPage:foreground() || reopenAfterRecovery)
        }
        let run = UUID(); generation = run; sessionBegan = ProcessInfo.processInfo.systemUptime; starting = true
        let server = LoopbackServer(); self.server = server
        keepAlive()

        do {
            let port = try await server.start { [weak self] request,reply in
                Task { @MainActor in reply(self?.serve(request) ?? LoopbackResponse(status:410)) }
            }
            guard generation == run else { throw CancellationError() }
            try Task.checkCancellation()
            var random = [UInt8](repeating:0,count:32)
            guard SecRandomCopyBytes(kSecRandomDefault,random.count,&random) == errSecSuccess else { throw CryptonError("Could not create a secure wallet capability.") }
            token = Data(random).base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
            origin = "http://localhost:\(port)"; starting = false
            return try await request(method,params,raw:raw,openPage:true)

        } catch {
            if generation == run { finish(.failure(error)) }
            throw error
        }
    }
    private func trace(_ stage:String) {
        // Random operation UUID and fixed stages only; no capability, key or args.
        NSLog("Crypton pipeline %@ bridge.%@ %.1fms",generation.uuidString,stage,(ProcessInfo.processInfo.systemUptime-sessionBegan)*1000)
    }
    private func keepAlive() {
        guard backgroundTime, background == .invalid else { return }
        background = UIApplication.shared.beginBackgroundTask(withName:"Crypton wallet handoff") { [weak self] in
            guard let self = self, self.background != .invalid else { return }
            UIApplication.shared.endBackgroundTask(self.background); self.background = .invalid
        }
    }
    private func request(_ method:String,_ params:JSON,raw:Bool,openPage:Bool) async throws -> Any {
        if openPage { keepAlive(); reopenAfterRecovery = false }
        id = UUID().uuidString; self.method = method; self.raw = raw; response = nil
        command = ["type":"CWI","isInvocation":true,"id":id,"call":method,"args":params]; issued = false; commandPageID = nil
        let run = generation
        let target = URL(string:origin + "/" + token + "/")!
        let link = try Self.handoffURL(target,scheme:scheme,pairing:NativeWalletPairing.proof(target))
        progress?(method == "createAction" ? "Review the total and approve payment in ME" : "ME: " + Self.label(method))
        return try await withCheckedThrowingContinuation { done in
            continuation = done; waiting?(true); trace("command." + method + ".queued")
            // A human payment review has no silent deadline while ME still
            // offers Pay. Explicit cancellation retains PAYMENT_REQUESTED.
            if method != "createAction" {
                timer = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds:self?.requestTimeoutNanoseconds ?? 300_000_000_000) } catch { return }
                    self?.fail(CryptonError("ME approval did not finish within five minutes. Your draft and any payment recovery record are saved."))
                }
            }
            if openPage {
                Task { [weak self] in
                    let opened = await self?.open(link) ?? false
                    guard let self = self, self.generation == run else { return }
                    if !opened { self.fail(CryptonError("Install and unlock Metanet Explorer on this iPhone, then retry.")) }
                }
            }
        }
    }
    static func label(_ method:String) -> String {
        switch method {
        case "isAuthenticated", "waitForAuthentication": return "Unlock and connect your wallet"
        case "getPublicKey": return "Checking the wallet identity"
        case "createAction": return "Review payment in ME"
        case "listActions": return "Checking payment history"
        case "discoverByAttributes", "discoverByIdentityKey": return "Searching certified identities"
        case "createSignature", "verifySignature": return "Authenticating MessageBox"
        default: return "Preparing encrypted messages and wallet permissions"
        }
    }
    /// A return URL carries no result. It only foregrounds Crypton for an already received response.
    @discardableResult func returned(_ url:URL) -> Bool {
        guard url.scheme == "crypton-wallet", url.host == "return", url.path == "/"+token,
              !token.isEmpty, url.query == nil, url.fragment == nil, url.user == nil, url.password == nil, url.port == nil else { return false }
        trace(session && !sessionFinished ? "returned.unfinished" : "returned.finished")
        if session && !sessionFinished { reopenAfterRecovery = true }
        if foreground() { resumed() }; return true
    }
    func resumed() {
        if sessionFinished { closeSession() }
        else if server != nil {
            // A long wallet review can exhaust the previous iOS background
            // allowance. Renew it before handing the unfinished session back.
            if background != .invalid { UIApplication.shared.endBackgroundTask(background); background = .invalid }
            keepAlive()
            if !session, let response = response { finish(response) }
            else if reopenAfterRecovery, continuation != nil, response == nil, !issued {
                // The next command may have been queued during the app's
                // inactive -> active transition, before foreground() was true.
                reopenAfterRecovery = false
                let run = generation
                Task { [weak self] in
                    guard let self = self, self.generation == run,
                          let target = URL(string:self.origin + "/" + self.token + "/"),
                          let link = try? Self.handoffURL(target,scheme:self.scheme,pairing:NativeWalletPairing.proof(target)) else { return }
                    if !(await self.open(link)), self.generation == run { self.fail(CryptonError("Open Metanet Explorer to resume the saved operation.")) }
                }
            }
        }
    }
    func cancel() { fail(CryptonError("Wallet request cancelled. Your draft and any payment recovery record are saved.")); closeSession() }
    private func fail(_ error:Error) { finish(.failure(error)) }
    private func finish(_ result:Result<Any,Error>) {
        let done = continuation; continuation = nil
        command = nil; response = nil; id = ""; timer?.cancel(); timer = nil
        if !session { closeSession() }
        waiting?(false); done?.resume(with:result)
    }
    private func closeSession() {
        generation = UUID(); starting = false; session = false; sessionFinished = false; operationDepth = 0
        command = nil; response = nil; token = ""; origin = ""; id = ""
        savedResults.removeAll(); savedResultOrder.removeAll(); reopenAfterRecovery = false
        closeTimer?.cancel(); closeTimer = nil; timer?.cancel(); timer = nil
        server?.stop(); server = nil
        if background != .invalid { UIApplication.shared.endBackgroundTask(background); background = .invalid }
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
                <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><title>Crypton wallet request</title><link rel="manifest" href="manifest.json">
                <body style="background:#0a1010;color:#f0f6f4;font:18px system-ui;padding:28px"><h1>Crypton</h1>
                <p id="status">Keep ME open while Crypton completes this operation. Review any permission or payment prompt here.</p>
                <a id="return" href="crypton-wallet://return/\(token)" hidden style="color:#00ebb3">Return to Crypton</a><p>You return to Crypton automatically after completion. If interrupted, use Return to Crypton after the wallet prompt has closed.</p><script src="bridge.js"></script></body>
                """
                return LoopbackResponse(type:"text/html",body:Data(html.utf8))
            case ("GET","manifest.json"):
                guard let url = Bundle.main.url(forResource:"manifest",withExtension:"json",subdirectory:"Engine") else { return LoopbackResponse(status:500) }
                return LoopbackResponse(type:"application/manifest+json",body:try Data(contentsOf:url))
            case ("GET","bridge.js"):
                guard let url = Bundle.main.url(forResource:"me",withExtension:"js",subdirectory:"Engine") else { return LoopbackResponse(status:500) }
                return LoopbackResponse(type:"application/javascript",body:try Data(contentsOf:url))
            case ("GET","next"):
                // A lost GET response must be recoverable by its original page.
                // A reload/second page has a new nonce and cannot obtain the same
                // invocation. The owning page deduplicates dispatch by command UUID.
                let page = request.headers["x-crypton-page"]
                if let page = page, UUID(uuidString:page) == nil { return LoopbackResponse(status:403) }
                let samePage = page != nil && page == commandPageID
                let next = response == nil && (!issued || samePage) ? command : nil
                if next != nil { trace("command." + method + (issued ? ".recovered" : ".offered")); issued = true; commandPageID = page }
                return LoopbackResponse(body:try jsonData(["finished":session ? sessionFinished : response != nil,"session":session,"issued":issued,"command":next as Any? ?? NSNull()]))
            case ("POST","result"):
                guard request.headers["origin"] == origin, request.headers["content-type"] == "application/json" else { return LoopbackResponse(status:403) }
                let value = try object(request.body)
                guard let resultID = value["id"] as? String, value["type"] as? String == "CWI", value["isInvocation"] as? Bool == false, integer(value["isInvocation"]) == nil else { return LoopbackResponse(status:409) }
                let digest = Data(SHA256.hash(data:try jsonData(value)))
                if let saved = savedResults[resultID] {
                    guard saved == digest else { return LoopbackResponse(status:409) }
                    return acknowledgement(resultID)
                }
                guard continuation != nil else { return LoopbackResponse(status:403) }
                guard response == nil, resultID == id else { return LoopbackResponse(status:409) }
                if value["status"] as? String == "success", let result = value["result"] as? JSON {
                    do {
                        if RecipientDiscovery.methods.contains(method), let args = command?["args"] as? JSON { response = .success(try RecipientDiscovery.response(result,args)) }
                        else { response = .success(raw ? result : try Wire.walletResult(method,result)) }
                    }
                    catch { response = .failure(error) }
                } else {
                    let detail = String((value["description"] as? String ?? "Review the wallet permission prompt and retry.").prefix(300))
                    response = .failure(WalletRefusal(method:method,code:integer(value["code"]) ?? 0,detail:detail,notCommitted:value["executionStatus"] as? String == "not-committed"))
                }
                // A session resumes the engine only after the HTTP reply has been sent.
                // Further commands use this same ME page; no app switch or prompt dismissal.
                trace("result." + method + ".saved")
                savedResults[resultID] = digest; savedResultOrder.append(resultID)
                if savedResultOrder.count > 128 { savedResults.removeValue(forKey:savedResultOrder.removeFirst()) }
                #if DEBUG
                NSLog("Crypton ME response received: %@",method)
                #endif
                return acknowledgement(resultID)
            default: return LoopbackResponse(status:403)
            }
        } catch { return LoopbackResponse(status:400) }
    }
    private func acknowledgement(_ resultID:String) -> LoopbackResponse {
        var reply = LoopbackResponse()
        reply.sent = { [weak self] in Task { @MainActor in
            // A delayed acknowledgment of an earlier method cannot finish a
            // later request or resume its continuation with the wrong result.
            guard let self = self, self.id == resultID,
                  self.session || self.foreground(), let response = self.response else { return }
            self.finish(response)
        } }
        return reply
    }
}

/// This key identifies a Crypton installation to ME; it never encrypts messages
/// or authorizes spending. The wallet's grouped review displays its fingerprint.
enum NativeWalletPairing {
    private static func key() throws -> P256.Signing.PrivateKey {
        let query:[String:Any] = [kSecClass as String:kSecClassGenericPassword,
            kSecAttrService as String:"com.projectbabbage.Crypton.walletPairing",
            kSecAttrAccount as String:"native-signing-v1"]
        var read = query; read[kSecReturnData as String] = true; read[kSecMatchLimit as String] = kSecMatchLimitOne
        var value:CFTypeRef?; let status = SecItemCopyMatching(read as CFDictionary,&value)
        if status == errSecSuccess, let data = value as? Data { return try P256.Signing.PrivateKey(rawRepresentation:data) }
        guard status == errSecItemNotFound else { throw CryptonError("Unlock this device to use the wallet pairing key.") }
        let created = P256.Signing.PrivateKey(); var save = query
        save[kSecValueData as String] = created.rawRepresentation
        save[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(save as CFDictionary,nil) == errSecSuccess else { throw CryptonError("Could not save the wallet pairing key.") }
        return created
    }
    private static func encoded(_ data:Data) -> String {
        data.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
    }
    static func code() throws -> String {
        let digest = SHA256.hash(data:try key().publicKey.x963Representation).map { String(format:"%02x",$0) }.joined()
        return stride(from:0,to:12,by:4).map { String(digest.dropFirst($0).prefix(4)) }.joined(separator:" ")
    }
    static func proof(_ target:URL,privateKey:Data? = nil,expires:Date = Date().addingTimeInterval(900)) throws -> [URLQueryItem] {
        let signingKey = try privateKey.map { try P256.Signing.PrivateKey(rawRepresentation:$0) } ?? key()
        let publicKey = encoded(signingKey.publicKey.x963Representation)
        let deadline = String(Int64(expires.timeIntervalSince1970))
        let message = Data("crypton-pairing/v1\n\(target.absoluteString)\n\(deadline)\n\(publicKey)".utf8)
        return [URLQueryItem(name:"cryptonKey",value:publicKey),
                URLQueryItem(name:"cryptonExpires",value:deadline),
                URLQueryItem(name:"cryptonSignature",value:encoded(try signingKey.signature(for:message).derRepresentation))]
    }
}
