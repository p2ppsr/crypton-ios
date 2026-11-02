import XCTest
import WebKit
import CryptoKit
@testable import Crypton

final class MEWalletTests: XCTestCase {
    func testNativePairingSignsExactCapabilityWithAnInstallationKey() throws {
        let target = URL(string:"http://localhost:12345/" + String(repeating:"a",count:43) + "/")!
        let rawKey = Data(repeating:1,count:32)
        let fields = try NativeWalletPairing.proof(target,privateKey:rawKey,expires:Date(timeIntervalSince1970:2_000_000_000))
        let values = Dictionary(uniqueKeysWithValues:fields.map { ($0.name,$0.value!) })
        XCTAssertEqual(Set(values.keys),Set(["cryptonKey","cryptonExpires","cryptonSignature"]))
        XCTAssertEqual(values["cryptonExpires"],"2000000000")
        func decode(_ value:String) -> Data {
            let text = value.replacingOccurrences(of:"-",with:"+").replacingOccurrences(of:"_",with:"/")
            return Data(base64Encoded:text + String(repeating:"=",count:(4-text.count%4)%4))!
        }
        let publicKey = try P256.Signing.PublicKey(x963Representation:decode(values["cryptonKey"]!))
        let signature = try P256.Signing.ECDSASignature(derRepresentation:decode(values["cryptonSignature"]!))
        let message = "crypton-pairing/v1\n\(target.absoluteString)\n2000000000\n\(values["cryptonKey"]!)"
        XCTAssertTrue(publicKey.isValidSignature(signature,for:Data(message.utf8)))
        XCTAssertFalse(publicKey.isValidSignature(signature,for:Data(message.replacingOccurrences(of:"12345",with:"12346").utf8)))
        XCTAssertEqual(publicKey.x963Representation,try P256.Signing.PrivateKey(rawRepresentation:rawKey).publicKey.x963Representation)
    }
    @MainActor func testOperationSessionQueuesCallsWithoutReturningOrReopeningME() async throws {
        let opened = expectation(description:"ME opened once"), second = expectation(description:"Second method queued")
        var launches = 0
        let me = MEWallet(open:{ _ in launches += 1; opened.fulfill(); return true },foreground:{false},backgroundTime:false)
        me.beginOperation()
        let first = Task { try await me.call("isAuthenticated",[:]) }
        await fulfillment(of:[opened],timeout:5)
        let capability = me.token
        let headers = ["host":String(me.origin.dropFirst("http://".count))]
        func next() throws -> JSON {
            try object(me.serve(LoopbackRequest(method:"GET",path:"/"+capability+"/next",headers:headers,body:Data())).body)
        }
        func respond(_ command:JSON) throws -> LoopbackResponse {
            var postHeaders = headers; postHeaders["origin"] = me.origin; postHeaders["content-type"] = "application/json"
            return me.serve(LoopbackRequest(method:"POST",path:"/"+capability+"/result",headers:postHeaders,body:try jsonData(["id":command["id"]!,"type":"CWI","isInvocation":false,"status":"success","result":["authenticated":true]])))
        }
        let firstCommand = try XCTUnwrap(try next()["command"] as? JSON)
        XCTAssertTrue(try next()["command"] is NSNull,"Another page must never receive the same wallet invocation")
        let response = try respond(firstCommand); XCTAssertEqual(response.status,200); response.sent?()
        let authenticated = try await first.value; XCTAssertEqual(authenticated as? Bool,true)
        XCTAssertEqual(me.token,capability,"Session must retain its capability between calls")
        me.progress = { _ in second.fulfill() }
        let following = Task { try await me.call("isAuthenticated",[:]) }
        await fulfillment(of:[second],timeout:5)
        let secondCommand = try XCTUnwrap(try next()["command"] as? JSON)
        XCTAssertNotEqual(firstCommand["id"] as? String,secondCommand["id"] as? String)
        let retry = try respond(firstCommand)
        XCTAssertEqual(retry.status,200,"An identical saved result is acknowledged after a lost reply")
        retry.sent?() // Must not satisfy the second method's continuation.
        let secondResponse = try respond(secondCommand); secondResponse.sent?()
        _ = try await following.value
        XCTAssertEqual(launches,1)
        me.endOperation(); XCTAssertEqual(try next()["finished"] as? Bool,true)
        XCTAssertTrue(me.returned(URL(string:"crypton-wallet://return/"+capability)!))
        me.resumed(); XCTAssertTrue(me.token.isEmpty)
    }
    @MainActor func testLostCommandResponseIsRetrievableOnlyByItsOriginalPage() async throws {
        let opened = expectation(description:"Wallet opened")
        let me = MEWallet(open:{ _ in opened.fulfill(); return true },foreground:{false},backgroundTime:false)
        defer { me.cancel() }
        me.beginOperation()
        let job = Task { try await me.call("isAuthenticated",[:]) }
        await fulfillment(of:[opened],timeout:5)
        let owner = UUID().uuidString, other = UUID().uuidString
        func next(_ page:String?) throws -> JSON {
            var headers = ["host":String(me.origin.dropFirst("http://".count))]
            headers["x-crypton-page"] = page
            return try object(me.serve(LoopbackRequest(method:"GET",path:"/"+me.token+"/next",headers:headers,body:Data())).body)
        }
        let lost = try XCTUnwrap(try next(owner)["command"] as? JSON)
        let retry = try XCTUnwrap(try next(owner)["command"] as? JSON)
        XCTAssertEqual(lost["id"] as? String,retry["id"] as? String,"An aborted HTTP response must not lose the command")
        XCTAssertTrue(try next(other)["command"] is NSNull,"A reload/second tab cannot re-invoke an issued command")
        XCTAssertTrue(try next(nil)["command"] is NSNull,"Legacy pages cannot steal the claim")
        let headers = ["host":String(me.origin.dropFirst("http://".count)),"origin":me.origin,"content-type":"application/json"]
        let result:JSON = ["id":retry["id"]!,"type":"CWI","isInvocation":false,"status":"success","result":["authenticated":true]]
        let ack = me.serve(LoopbackRequest(method:"POST",path:"/"+me.token+"/result",headers:headers,body:try jsonData(result)))
        XCTAssertEqual(ack.status,200); ack.sent?(); _ = try await job.value
        XCTAssertTrue(try next(owner)["command"] is NSNull,"A completed command cannot be recovered as a new invocation")
    }
    @MainActor func testNetworkingWaitsForCryptonActiveAndRejectsConcurrentWalletCall() async throws {
        let opened = expectation(description:"Wallet opened")
        var foreground = false, ready = false
        let me = MEWallet(open:{ _ in opened.fulfill(); return true },foreground:{foreground},backgroundTime:false)
        defer { me.cancel() }
        me.beginOperation()
        let call = Task { try await me.call("isAuthenticated",[:]) }
        await fulfillment(of:[opened],timeout:5)
        let token = me.token, host = String(me.origin.dropFirst("http://".count))
        func next() throws -> JSON { try object(me.serve(LoopbackRequest(method:"GET",path:"/"+token+"/next",headers:["host":host],body:Data())).body) }
        do { try await me.prepareForNetwork(); XCTFail("A pending wallet prompt was bypassed") } catch { }
        let command = try XCTUnwrap(try next()["command"] as? JSON)
        let result:JSON = ["id":command["id"]!,"type":"CWI","isInvocation":false,"status":"success","result":["authenticated":true]]
        let ack = me.serve(LoopbackRequest(method:"POST",path:"/"+token+"/result",headers:["host":host,"origin":me.origin,"content-type":"application/json"],body:try jsonData(result)))
        ack.sent?(); _ = try await call.value
        let network = Task { try await me.prepareForNetwork(); ready = true }
        for _ in 0..<50 { if try next()["foregroundRequired"] as? Bool == true { break }; await Task.yield() }
        XCTAssertEqual(try next()["foregroundRequired"] as? Bool,true)
        XCTAssertTrue(try next()["command"] is NSNull,"A networking handoff cannot queue a wallet invocation")
        do { _ = try await me.call("isAuthenticated",[:]); XCTFail("Concurrent wallet call during handoff") } catch { }
        XCTAssertTrue(me.returned(URL(string:"crypton-wallet://return/"+token)!))
        await Task.yield(); XCTAssertFalse(ready,"A callback alone cannot start background networking")
        foreground = true; me.resumed(); try await network.value
        XCTAssertTrue(ready); XCTAssertEqual(try next()["foregroundRequired"] as? Bool,false)
    }
    @MainActor func testCancellingForegroundHandoffCannotStartNetworking() async throws {
        let opened = expectation(description:"Wallet opened")
        let me = MEWallet(open:{ _ in opened.fulfill(); return true },foreground:{false},backgroundTime:false)
        me.beginOperation()
        let call = Task { try await me.call("isAuthenticated",[:]) }
        await fulfillment(of:[opened],timeout:5)
        let headers = ["host":String(me.origin.dropFirst("http://".count))]
        let path = "/"+me.token
        let command = try XCTUnwrap(try object(me.serve(LoopbackRequest(method:"GET",path:path+"/next",headers:headers,body:Data())).body)["command"] as? JSON)
        var h = headers; h["origin"] = me.origin; h["content-type"] = "application/json"
        let ack = me.serve(LoopbackRequest(method:"POST",path:path+"/result",headers:h,body:try jsonData(["id":command["id"]!,"type":"CWI","isInvocation":false,"status":"success","result":["authenticated":true]])))
        ack.sent?(); _ = try await call.value
        let network = Task { try await me.prepareForNetwork() }
        for _ in 0..<50 { if try object(me.serve(LoopbackRequest(method:"GET",path:path+"/next",headers:headers,body:Data())).body)["foregroundRequired"] as? Bool == true { break }; await Task.yield() }
        me.cancel()
        do { try await network.value; XCTFail("Cancelled handoff started networking") } catch { }
        XCTAssertTrue(me.token.isEmpty)
    }
    @MainActor func testBobWalletUsesSeparateSchemeWithoutOfficialFallback() async throws {
        let opened = expectation(description:"Bob wallet opened"); var link:URL?
        let wallet = MEWallet(open:{ link = $0; opened.fulfill(); return true },foreground:{false},backgroundTime:false,scheme:"metanet-bob")
        let request = Task { try await wallet.call("getPublicKey",[:]) }
        await fulfillment(of:[opened],timeout:5)
        XCTAssertEqual(link?.scheme,"metanet-bob"); XCTAssertEqual(link?.host,"browser")
        wallet.cancel(); do { _ = try await request.value; XCTFail("Cancelled Bob request returned") } catch { }
    }
    @MainActor func testStrictHTTPParserAndDeepLink() throws {
        let first = Data("POST /cap/result HTTP/1.1\r\nHost: localhost:1\r\nContent-Length: 2\r\n\r\n{".utf8)
        XCTAssertNil(try LoopbackRequest.parse(first))
        XCTAssertEqual(try LoopbackRequest.parse(first + Data("}".utf8))?.body,Data("{}".utf8))
        for value in ["GET / HTTP/1.1\r\nHost: x\r\nHost: y\r\n\r\n", "POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n", "POST / HTTP/1.1\r\nContent-Length: 8000001\r\n\r\n", "GET http://evil/ HTTP/1.1\r\n\r\n"] { XCTAssertThrowsError(try LoopbackRequest.parse(Data(value.utf8))) }
        let target = URL(string:"http://localhost:1234/random-capability/")!
        let link = try MEWallet.handoffURL(target)
        XCTAssertEqual(link.scheme,"metanet"); XCTAssertEqual(link.host,"browser")
        XCTAssertEqual(URLComponents(url:link,resolvingAgainstBaseURL:false)?.queryItems?.first?.value,target.absoluteString)
    }
    @MainActor func testCapabilityOriginUUIDAndReturnBoundary() async throws {
        let launched = expectation(description:"ME opened")
        var link:URL?, foreground = false
        let me = MEWallet(open:{ link = $0; launched.fulfill(); return true },foreground:{ foreground },backgroundTime:false)
        let job = Task { try await me.call("getPublicKey",[:]) }
        await fulfillment(of:[launched],timeout:5)
        let page = try XCTUnwrap(URLComponents(url:XCTUnwrap(link),resolvingAgainstBaseURL:false)?.queryItems?.first?.value.flatMap(URL.init(string:)))
        var request = URLRequest(url:page.appendingPathComponent("next"))
        let (bytes,http) = try await BoundedHTTP().fetch(request)
        XCTAssertEqual(http.statusCode,200)
        let state = try object(bytes), command = try XCTUnwrap(state["command"] as? JSON)
        XCTAssertEqual(command["call"] as? String,"getPublicKey")
        let key = "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
        let body: JSON = ["type":"CWI","isInvocation":false,"id":command["id"]!,"status":"success","result":["publicKey":key]]
        request.url = page.appendingPathComponent("result"); request.httpMethod = "POST"; request.httpBody = try jsonData(body)
        request.setValue("application/json",forHTTPHeaderField:"Content-Type"); request.setValue("https://evil.example",forHTTPHeaderField:"Origin")
        let (_,refused) = try await BoundedHTTP().fetch(request); XCTAssertEqual(refused.statusCode,403)
        request.setValue(me.origin,forHTTPHeaderField:"Origin")
        var wrong = body; wrong["id"] = UUID().uuidString; request.httpBody = try jsonData(wrong)
        let (_,stale) = try await BoundedHTTP().fetch(request); XCTAssertEqual(stale.statusCode,409)
        wrong = body; wrong["isInvocation"] = 0; request.httpBody = try jsonData(wrong)
        let (_,numeric) = try await BoundedHTTP().fetch(request); XCTAssertEqual(numeric.statusCode,409)
        request.httpBody = try jsonData(body)
        let (_,accepted) = try await BoundedHTTP().fetch(request); XCTAssertEqual(accepted.statusCode,200)
        let (_,duplicate) = try await BoundedHTTP().fetch(request); XCTAssertEqual(duplicate.statusCode,200)
        XCTAssertFalse(me.token.isEmpty,"Response must wait for foreground return")
        XCTAssertFalse(me.returned(URL(string:"crypton-wallet://return/stale")!))
        let capability = me.token
        foreground = true; XCTAssertTrue(me.returned(URL(string:"crypton-wallet://return/"+capability)!))
        let actual = try await job.value
        XCTAssertEqual(actual as? String,key)
        XCTAssertTrue(me.token.isEmpty)
        XCTAssertFalse(me.returned(URL(string:"crypton-wallet://return/"+capability)!))
    }
    @MainActor func testCancellationAndUnavailableME() async throws {
        let absent = MEWallet(open:{ _ in false },backgroundTime:false)
        do { _ = try await absent.call("isAuthenticated",[:]); XCTFail("Unavailable ME succeeded") } catch { XCTAssertTrue(error.localizedDescription.contains("Install and unlock")) }
        let opened = expectation(description:"Request launched")
        let me = MEWallet(open:{ _ in opened.fulfill(); return true },backgroundTime:false)
        let job = Task { try await me.call("waitForAuthentication",[:]) }
        await fulfillment(of:[opened],timeout:5); me.cancel()
        do { _ = try await job.value; XCTFail("Cancelled request succeeded") } catch { }
        XCTAssertTrue(me.token.isEmpty)
    }
    @MainActor func testForegroundReturnWithoutCallbackLink() async throws {
        let opened = expectation(description:"ME request opened")
        let me = MEWallet(open:{ _ in opened.fulfill(); return true },foreground:{ false },backgroundTime:false)
        let job = Task { try await me.call("isAuthenticated",[:]) }
        await fulfillment(of:[opened],timeout:5)
        let headers = ["host":String(me.origin.dropFirst("http://".count))]
        let state = try object(me.serve(LoopbackRequest(method:"GET",path:"/"+me.token+"/next",headers:headers,body:Data())).body)
        let command = try XCTUnwrap(state["command"] as? JSON)
        var postHeaders = headers; postHeaders["origin"] = me.origin; postHeaders["content-type"] = "application/json"
        let body:JSON = ["type":"CWI","isInvocation":false,"id":command["id"]!,"status":"success","result":["authenticated":true]]
        XCTAssertEqual(me.serve(LoopbackRequest(method:"POST",path:"/"+me.token+"/result",headers:postHeaders,body:try jsonData(body))).status,200)
        me.resumed()
        let result = try await job.value; XCTAssertEqual(result as? Bool,true)
    }
    @MainActor func testLostAcknowledgementReturnsForSaveThenReopensMEForNextMethod() async throws {
        let firstOpen = expectation(description:"Initial wallet page"), recoveryOpen = expectation(description:"Resume wallet after saving result")
        var launches = 0, foreground = false, completed = false
        let me = MEWallet(open:{ _ in
            launches += 1
            if launches == 1 { firstOpen.fulfill() } else { recoveryOpen.fulfill() }
            return true
        },foreground:{foreground},backgroundTime:false)
        defer { me.cancel() }
        me.beginOperation()
        let first = Task { let value = try await me.call("isAuthenticated",[:]); completed = true; return value }
        await fulfillment(of:[firstOpen],timeout:5)
        let token = me.token, origin = me.origin
        let headers = ["host":String(origin.dropFirst("http://".count))]
        func next() throws -> JSON { try object(me.serve(LoopbackRequest(method:"GET",path:"/"+token+"/next",headers:headers,body:Data())).body) }
        func post(_ value:JSON, originOverride:String? = nil) throws -> LoopbackResponse {
            var h = headers; h["origin"] = originOverride ?? origin; h["content-type"] = "application/json"
            return me.serve(LoopbackRequest(method:"POST",path:"/"+token+"/result",headers:h,body:try jsonData(value)))
        }
        let command = try XCTUnwrap(try next()["command"] as? JSON)
        let body:JSON = ["type":"CWI","isInvocation":false,"id":command["id"]!,"status":"success","result":["authenticated":true]]
        let lost = try post(body); XCTAssertEqual(lost.status,200) // HTTP acknowledgement lost before .sent.
        foreground = true
        XCTAssertTrue(me.returned(URL(string:"crypton-wallet://return/"+token)!)); me.resumed()
        await Task.yield(); XCTAssertFalse(completed,"Returning for recovery must wait for the page's save acknowledgement")
        let retry = try post(body); XCTAssertEqual(retry.status,200); retry.sent?()
        _ = try await first.value
        foreground = false // Simulates the inactive/active handoff race.
        let following = Task { try await me.call("isAuthenticated",[:]) }
        await fulfillment(of:[recoveryOpen],timeout:5)
        let second = try XCTUnwrap(try next()["command"] as? JSON)
        XCTAssertNotEqual(second["id"] as? String,command["id"] as? String)
        lost.sent?(); (try post(body)).sent?() // Late callbacks cannot finish the second method.
        var changed = body; changed["result"] = ["authenticated":false]
        XCTAssertEqual(try post(changed).status,409,"Same UUID with different content is not an acknowledgement retry")
        XCTAssertEqual(try post(body,originOverride:"https://evil.example").status,403)
        var secondBody = body; secondBody["id"] = second["id"]
        let final = try post(secondBody); XCTAssertEqual(final.status,200); final.sent?()
        let result = try await following.value; XCTAssertEqual(result as? Bool,true)
        XCTAssertEqual(launches,2,"Recovery must reopen ME even before Crypton becomes active")
        me.endOperation()
    }
    @MainActor func testPaymentReviewWaitsForUserWhileOrdinaryRequestsRemainBounded() async throws {
        let opened = expectation(description:"Payment review opened")
        var finished = false
        let me = MEWallet(open:{ _ in opened.fulfill(); return true },foreground:{false},backgroundTime:false,requestTimeoutNanoseconds:100_000_000)
        let payment = Task {
            defer { finished = true }
            return try await me.call("createAction",[:],raw:true)
        }
        await fulfillment(of:[opened],timeout:5)
        try await Task.sleep(nanoseconds:350_000_000)
        XCTAssertFalse(finished,"Crypton must not silently expire a still-open payment review")
        XCTAssertFalse(me.token.isEmpty)
        me.cancel()
        do { _ = try await payment.value; XCTFail("Canceled payment review returned success") } catch { }
        let bounded = MEWallet(open:{ _ in true },foreground:{false},backgroundTime:false,requestTimeoutNanoseconds:100_000_000)
        do { _ = try await bounded.call("isAuthenticated",[:]); XCTFail("Non-payment wallet requests must retain their timeout") }
        catch { XCTAssertTrue(error.localizedDescription.contains("did not finish")) }
        bounded.cancel()
    }
    @MainActor func testSharedStoreCrossInstanceValidationAndImageImport() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let writer = try IncomingShareStore(directory:directory), reader = try IncomingShareStore(directory:directory)
        XCTAssertThrowsError(try writer.stage(text:"Unencrypted private draft"))
        let text = Data(repeating:7,count:64).base64EncodedString()
        let staged = try writer.stage(text:text)
        XCTAssertEqual(try reader.pending(),[staged])
        XCTAssertEqual(try String(contentsOf:staged,encoding:.utf8),text)
        let image = try XCTUnwrap(QRTools.image(text)), source = directory.appendingPathComponent("source.image")
        let archive = try NSKeyedArchiver.archivedData(withRootObject:image,requiringSecureCoding:true)
        XCTAssertThrowsError(try writer.stage(imageData:archive),"A UIKit archive must not be saved as an encoded image")
        try XCTUnwrap(image.pngData()).write(to:source)
        let incoming = try writer.stage(image:source)
        XCTAssertEqual(try QRTools.read(incoming),text)
        XCTAssertTrue(try directory.resourceValues(forKeys:[.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        try reader.remove(staged); XCTAssertEqual(try reader.pending(),[incoming])
    }
}

/// A real WKWebView running the shipped ME request page. The official CWI bridge contract
/// is backed by a separate SDK wallet fixture; this is not the installed ME application.
@MainActor private final class MEPageFixture: NSObject,WKScriptMessageHandler,WKNavigationDelegate {
    private var web:WKWebView!
    private var active = false
    var isCryptonActive:Bool { active }
    private(set) var wallet:MEWallet!
    private(set) var requests = 0
    private(set) var launches = 0
    override init() {
        super.init()
        let content = WKUserContentController(); content.add(self,name:"fixtureME")
        content.addUserScript(WKUserScript(source:"window.ReactNativeWebView={postMessage:value=>window.webkit.messageHandlers.fixtureME.postMessage(value)}",injectionTime:.atDocumentStart,forMainFrameOnly:true))
        let config = WKWebViewConfiguration(); config.userContentController = content; config.websiteDataStore = .nonPersistent()
        web = WKWebView(frame:CGRect(x:0,y:0,width:2,height:2),configuration:config); web.navigationDelegate = self
        // ME's page correctly refuses wallet calls while hidden. Attach the
        // fixture to the test app's window so it models a foreground wallet.
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        scene?.windows.first(where:{ $0.isKeyWindow })?.addSubview(web)
        wallet = MEWallet(open:{ [weak self] url in
            guard let self = self, url.scheme == "metanet", url.host == "browser", let target = URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems?.first(where:{ $0.name == "url" })?.value.flatMap(URL.init(string:)) else { return false }
            self.launches += 1; self.active = false; self.web.load(URLRequest(url:target)); return true
        },foreground:{ [weak self] in self?.active ?? false },backgroundTime:false)
    }
    func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let data = message.body as? String, let command = try? object(Data(data.utf8)) else { return }
        if command["type"] as? String == "CRYPTON_RETURN", let callback = command["callback"] as? String, let url = URL(string:callback) {
            let accepted = wallet.returned(url)
            if accepted { active = true; wallet.resumed() }
            web.evaluateJavaScript("window.postMessage({type:'CRYPTON_RETURN_STATUS',accepted:\(accepted)},'*');void 0")
            return
        }
        guard let id = command["id"] as? String, command["type"] as? String == "CWI", command["isInvocation"] as? Bool == true, let method = command["call"] as? String, let args = command["args"] as? JSON else { return }
        requests += 1
        Task {
            var response:JSON = ["type":"CWI","isInvocation":false,"id":id]
            do {
                let result = try await JSONWallet(endpoint:URL(string:"http://127.0.0.1:18776")!).call(method,args,raw:true)
                response["status"] = "success"; response["result"] = result
            } catch { response["status"] = "error"; response["description"] = "Disposable fixture declined request"; response["code"] = 1 }
            do { _ = try await web.evaluateJavaScript("window.postMessage(\(try jsonString(try jsonString(response))),'*');window.dispatchEvent(new MessageEvent('message',{data:\(try jsonString(try jsonString(response)))}));void 0") }
            catch { wallet.cancel() }
        }
    }
    func webView(_ webView:WKWebView,decidePolicyFor navigationAction:WKNavigationAction,decisionHandler:@escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, url.scheme == "crypton-wallet" {
            if wallet.returned(url) { active = true; wallet.resumed() }
            decisionHandler(.cancel)
        }
        else { decisionHandler(.allow) }
    }
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) {
        let error = error as NSError
        // Loading the next capability page cancels the previous navigation. That
        // old callback must not cancel the next wallet request.
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled { return }
        wallet.cancel()
    }
    func close() { wallet.cancel(); web.configuration.userContentController.removeAllScriptMessageHandlers(); web.stopLoading(); web.removeFromSuperview() }
}

final class MEAndDeliveryIntegrationTests: XCTestCase {
    @MainActor func testNativeMEInboxRetrievalDecryptionAndRemoval() async throws {
        try await available()
        _ = try await fixture("ack-mode",["mode":"normal"])
        let seeded = try await fixture("seed-inbox",["count":1]), root = seeded["wallet"] as! String, id = (seeded["ids"] as! [String])[0]
        let config = try await fixture("delivery-config"), folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let delivery = try DeliveryStore(directory:folder.appendingPathComponent("outbox"),fixtureHost:config["host"] as! String,fixtureAgent:config["agent"] as! String)
        let page = MEPageFixture(); defer { page.close() }
        let engine = CryptoEngine(wallet:page.wallet,store:delivery); defer { engine.close() }
        _ = try await engine.inbox("refresh")
        let opened = try await engine.inbox("openDiscard",wallet:root,id:id)
        XCTAssertEqual((opened["content"] as? JSON)?["text"] as? String,"Android inbox fixture message 0")
        XCTAssertEqual(opened["removed"] as? Bool,true); XCTAssertThrowsError(try engine.inboxStore.get(root,id))
    }
    @MainActor func testPrivateMessageClearsOnBackgroundAndRemovalRetriesAfterRestart() async throws {
        try await available()
        let config = try await fixture("delivery-config"), folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "crypton.private."+UUID().uuidString, defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite); try? FileManager.default.removeItem(at:folder) }
        let store = try DeliveryStore(directory:folder.appendingPathComponent("outbox"),fixtureHost:config["host"] as! String,fixtureAgent:config["agent"] as! String)
        let wallet = JSONWallet(endpoint:URL(string:"http://127.0.0.1:18776")!)
        defaults.set(false,forKey:"soundEnabled"); defaults.set(true,forKey:"guideSeen"); defaults.set(true,forKey:"disappearReceive")
        _ = try await fixture("ack-mode",["mode":"reject"])
        let seeded = try await fixture("seed-inbox",["count":1]), id = (seeded["ids"] as! [String])[0]
        let model = AppModel(defaults:defaults,store:store,wallet:wallet)
        func settle(_ model:AppModel) async throws {
            for _ in 0..<400 { if !model.busy { return }; try await Task.sleep(nanoseconds:100_000_000) }
            XCTFail("Inbox model timed out"); model.cancel()
        }
        model.active(true); model.receive("refresh"); try await settle(model)
        model.showInboxMessage(id); model.receive("open"); try await settle(model)
        XCTAssertNotNil(model.inboxContent); XCTAssertTrue(model.privateInboxView); XCTAssertFalse(model.privateRemoved)
        model.active(false); XCTAssertNil(model.inboxContent); XCTAssertEqual(model.screen,.inbox)
        _ = try await fixture("ack-mode",["mode":"normal"])
        let restarted = AppModel(defaults:defaults,store:store,wallet:wallet)
        defer { restarted.active(false); restarted.cancel() }
        XCTAssertTrue(InboxStore.pending(try restarted.inboxStore.get(restarted.inboxWallet,id)))
        restarted.active(true)
        for _ in 0..<400 {
            if (try? restarted.inboxStore.get(restarted.inboxWallet,id)) == nil { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        try await settle(restarted)
        XCTAssertThrowsError(try restarted.inboxStore.get(restarted.inboxWallet,id))
        XCTAssertTrue(restarted.inboxNotice.contains("Server removal confirmed"))
    }
    @MainActor func testNativeInboxPaginationPersistenceWalletBindingAndDecryption() async throws {
        try await available()
        let config = try await fixture("delivery-config"), folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let delivery = try DeliveryStore(directory:folder.appendingPathComponent("outbox"),fixtureHost:config["host"] as! String,fixtureAgent:config["agent"] as! String)
        let inbox = InboxStore(delivery:delivery)
        let wallet = JSONWallet(endpoint:URL(string:"http://127.0.0.1:18776")!)
        let engine = CryptoEngine(wallet:wallet,store:delivery,inbox:inbox); defer { engine.close() }
        for mode in ["derived","root"] {
            var stage = "seed"
            do {
            let seeded = try await fixture("seed-inbox",["count":mode == "derived" ? 28 : 1,"mode":mode]), root = seeded["wallet"] as! String
            stage = "first page"
            let first = try await engine.inbox("refresh")
            XCTAssertEqual(first["wallet"] as? String,root)
            stage = "second page"
            if first["hasMore"] as? Bool == true { _ = try await engine.inbox("refresh",wallet:root,offset:first["nextOffset"] as! Int) }
            let id = (seeded["ids"] as! [String])[0]
            stage = "open"
            let opened = try await engine.inbox("open",wallet:root,id:id)
            XCTAssertEqual((opened["content"] as? JSON)?["text"] as? String,"Android inbox fixture message 0")
            stage = "dismiss"
            try inbox.flag(root,id,"dismissed",true)
            stage = "reopen"
            let reopened = InboxStore(delivery:delivery)
            XCTAssertEqual(try reopened.get(root,id)["dismissed"] as? Bool,true)
            do { _ = try await engine.inbox("open",wallet:config["agent"] as! String,id:id); XCTFail("Different profile opened saved message") } catch { }
            } catch { throw CryptonError("Inbox \(mode) at \(stage): \(error)") }
        }
    }
    @MainActor func testDisappearingInboxVerifiedRemovalFailuresLostResponseAndNestedContent() async throws {
        try await available()
        let config = try await fixture("delivery-config"), folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let delivery = try DeliveryStore(directory:folder.appendingPathComponent("outbox"),fixtureHost:config["host"] as! String,fixtureAgent:config["agent"] as! String)
        let inbox = InboxStore(delivery:delivery), wallet = JSONWallet(endpoint:URL(string:"http://127.0.0.1:18776")!)
        let engine = CryptoEngine(wallet:wallet,store:delivery,inbox:inbox); defer { engine.close() }
        for mode in ["normal","reject","retain","drop","badLookup"] {
            _ = try await fixture("ack-mode",["mode":mode])
            let seeded = try await fixture("seed-inbox",["count":1,"layer":mode == "normal"]), root = seeded["wallet"] as! String, id = (seeded["ids"] as! [String])[0]
            _ = try await engine.inbox("refresh")
            let opened = try await engine.inbox("openDiscard",wallet:root,id:id)
            if mode == "normal" {
                let content = opened["content"] as! JSON
                let inner = try await engine.inbox("layer",wallet:root,layer:content["envelope"] as! String)
                XCTAssertEqual((inner["content"] as? JSON)?["text"] as? String,"Android inbox fixture message 0")
            }
            if ["normal","drop"].contains(mode) { XCTAssertEqual(opened["removed"] as? Bool,true); XCTAssertThrowsError(try inbox.get(root,id)) }
            else {
                XCTAssertEqual(opened["removed"] as? Bool,false)
                XCTAssertEqual(try inbox.get(root,id).count,5)
                _ = try await engine.inbox("refresh"); XCTAssertTrue(InboxStore.pending(try inbox.get(root,id)),"Refresh must not restore a disappearing ciphertext")
                _ = try await fixture("ack-mode",["mode":"normal"])
                let restarted = CryptoEngine(wallet:wallet,store:delivery,inbox:inbox); defer { restarted.close() }
                _ = try await restarted.inbox("remove",wallet:root,id:id); XCTAssertThrowsError(try inbox.get(root,id))
            }
        }
        _ = try await fixture("ack-mode",["mode":"normal"])
        let seeded = try await fixture("seed-inbox",["count":1,"mode":"wrong"]), root = seeded["wallet"] as! String, id = (seeded["ids"] as! [String])[0]
        _ = try await engine.inbox("refresh")
        let before = try await fixture("delivery-stats")
        do { _ = try await engine.inbox("openDiscard",wallet:root,id:id); XCTFail("Wrong recipient decrypted") } catch { }
        let after = try await fixture("delivery-stats")
        XCTAssertEqual(integer(before["acks"]),integer(after["acks"])); XCTAssertNotNil(try inbox.get(root,id)["envelope"])
    }
    @MainActor func testDisappearingSendRemovesConfirmedCopyAndRetainsUncertainPayment() async throws {
        try await available()
        let config = try await fixture("delivery-config"), folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let store = try DeliveryStore(directory:folder,fixtureHost:config["host"] as! String,fixtureAgent:config["agent"] as! String)
        let wallet = JSONWallet(endpoint:URL(string:"http://127.0.0.1:18776")!), engine = CryptoEngine(wallet:wallet,store:store); defer { engine.close() }
        let envelope = try await engine.run("seal",text:"Disappearing fixture send") as! String
        let id = try store.create(envelope:envelope,key:"self",recipient:"self",name:"Private",disappear:true)
        _ = try await engine.deliver("prepare",id:id); _ = try await engine.deliver("send",id:id)
        XCTAssertThrowsError(try store.get(id)); XCTAssertTrue(try store.list().isEmpty)
        let uncertain = try store.create(envelope:envelope,key:"self",recipient:"self",name:"Private",disappear:true)
        _ = try await engine.deliver("prepare",id:uncertain); _ = try await fixture("lose-next-payment")
        do { _ = try await engine.deliver("send",id:uncertain) } catch { }
        XCTAssertEqual(try store.get(uncertain)["state"] as? String,"PAYMENT_REQUESTED")
        XCTAssertThrowsError(try store.cleanup(uncertain)); XCTAssertThrowsError(try store.begin(uncertain,action:"send"))
    }
    @MainActor func testNativeMESearchSelectionContactAndEncryption() async throws {
        try await available()
        let page = MEPageFixture(); defer { page.close() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = DeliveryStore(directory:directory)
        let suite = "crypton.search." + UUID().uuidString, defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite); try? FileManager.default.removeItem(at:directory) }
        defaults.set(false,forKey:"soundEnabled"); defaults.set(true,forKey:"guideSeen")
        let recipient = try await fixture("recipient"), statsBefore = try await fixture("delivery-stats")
        let key = try XCTUnwrap(recipient["publicKey"] as? String)
        defaults.set([key:"0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"],forKey:"deliveryKeys")
        let model = AppModel(defaults:defaults,store:store,wallet:page.wallet)
        defer { model.cancel() }
        func settle() async throws {
            for _ in 0..<200 {
                if !model.busy { return }
                try await Task.sleep(nanoseconds:100_000_000)
            }
            XCTFail("Search model did not finish"); model.cancel()
        }
        model.begin(decrypt:false); model.recipientQuery = "ambiguous"
        XCTAssertEqual(page.requests,0,"Typing must not open ME")
        model.searchRecipients(); try await settle()
        XCTAssertNil(model.error); XCTAssertEqual(model.searchResults.count,2)
        XCTAssertEqual(model.peer,"self"); XCTAssertEqual(model.screen,.recipient,"A result must never be auto-selected")
        let stale = try XCTUnwrap(model.searchResults.first)
        model.recipientQuery = "bob@example.com"
        XCTAssertTrue(model.searchResults.isEmpty); XCTAssertFalse(model.searchCompleted)
        model.chooseDiscovered(stale); XCTAssertNotNil(model.error); XCTAssertEqual(model.peer,"self")
        model.searchRecipients(); try await settle()
        let selected = try XCTUnwrap(model.searchResults.first)
        XCTAssertEqual(selected.key,key); XCTAssertTrue(selected.certification.contains("Fixture SocialCert"))
        model.chooseDiscovered(selected)
        XCTAssertEqual(model.peer,key); XCTAssertEqual(model.screen,.compose); XCTAssertTrue(model.contacts.isEmpty)
        model.saveDiscoveredRecipient(); XCTAssertEqual(model.contacts.first?.walletIdentity,key)
        model.message = "Discovered recipient: café 🌍"; model.process(); try await settle()
        XCTAssertNil(model.error)
        let envelope = model.output
        let opened = try await fixture("v2-open",["envelope":envelope])
        XCTAssertEqual(opened["text"] as? String,model.message)
        model.newDelivery(); XCTAssertEqual(model.deliveryRecipient,key,"Search must override an obsolete delivery-key mapping")
        XCTAssertEqual(try store.get(model.deliveryID)["recipient"] as? String,key)
        let reopened = AppModel(defaults:defaults,store:store,wallet:page.wallet)
        reopened.chooseContact(try XCTUnwrap(reopened.contacts.first)); reopened.output = envelope; reopened.outputKind = "encrypted"
        reopened.newDelivery(); XCTAssertEqual(reopened.deliveryRecipient,key)
        let statsAfter = try await fixture("delivery-stats")
        XCTAssertEqual(integer(statsAfter["payments"]),integer(statsBefore["payments"]),"Discovery, contact saving and encryption must not make payments")
    }
    @MainActor func testNativeMEDiscoveryEmptyDenialMalformedOfflineAndCancellation() async throws {
        try await available()
        let page = MEPageFixture(); defer { page.close() }
        let engine = CryptoEngine(wallet:page.wallet,store:DeliveryStore()); defer { engine.close() }
        let empty = try await engine.search("empty@example.com"); XCTAssertTrue(empty.isEmpty)
        let recipient = try await fixture("recipient")
        let key = try XCTUnwrap(recipient["publicKey"] as? String)
        let byKey = try await engine.search(key); XCTAssertEqual(byKey.first?.key,key)
        for preparation in ["deny-next","offline-next"] {
            _ = try await fixture(preparation)
            do { _ = try await engine.search("bob@example.com"); XCTFail("Failed discovery was treated as a result") } catch { }
        }
        do { _ = try await engine.search("malformed"); XCTFail("Malformed discovery key was accepted") } catch { }
        let opened = expectation(description:"Search opened ME")
        let held = MEWallet(open:{ _ in opened.fulfill(); return true },foreground:{false},backgroundTime:false)
        let heldEngine = CryptoEngine(wallet:held,store:DeliveryStore()); defer { heldEngine.close() }
        let cancelled = Task { try await heldEngine.search("bob@example.com") }
        await fulfillment(of:[opened],timeout:10)
        heldEngine.cancel()
        do { _ = try await cancelled.value; XCTFail("Cancelled search returned results") } catch { }
        XCTAssertTrue(held.token.isEmpty)
    }
    @MainActor private func fixture(_ path:String,_ args:JSON = [:]) async throws -> JSON {
        var request = URLRequest(url:URL(string:"http://127.0.0.1:18776/test/"+path)!)
        request.httpMethod = "POST"; request.httpBody = try jsonData(args)
        request.setValue("https://crypton.ios",forHTTPHeaderField:"Origin"); request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        let (data,response) = try await BoundedHTTP().fetch(request)
        guard response.statusCode == 200 else { throw CryptonError("Fixture request rejected.") }; return try object(data)
    }
    @MainActor private func available() async throws {
        do { _ = try await fixture("recipient") } catch { throw XCTSkip("Start the SDK/MessageBox fixtures to run native ME integration tests.") }
    }
    @MainActor func testMEPageIdentityCryptoAndDenial() async throws {
        try await available()
        let page = MEPageFixture(); defer { page.close() }
        _ = try await page.wallet.call("waitForAuthentication",[:])
        let engine = CryptoEngine(wallet:page.wallet,store:DeliveryStore()); defer { engine.close() }
        let identity = try await engine.run("identity") as! String
        XCTAssertNoThrow(try Wire.identity(identity))
        let text = "Native ME page round trip: café 🌍"
        let sealed = try await engine.run("seal",text:text) as! String
        let opened = try await engine.run("open",text:sealed) as! JSON
        XCTAssertEqual(opened["text"] as? String,text)
        _ = try await fixture("deny-next")
        do { _ = try await page.wallet.call("getPublicKey",[:]); XCTFail("ME denial ignored") } catch { XCTAssertTrue(error.localizedDescription.contains("declined")) }
        XCTAssertGreaterThanOrEqual(page.requests,5)
    }
    @MainActor func testContactIdentityAndForegroundSubmission() async throws {
        try await available()
        let config = try await fixture("delivery-config"), folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let store = try DeliveryStore(directory:folder,fixtureHost:config["host"] as! String,fixtureAgent:config["agent"] as! String)
        let page = MEPageFixture(); defer { page.close() }
        let engine = CryptoEngine(wallet:page.wallet,store:store); defer { engine.close() }
        var networkPaths = Set<String>()
        engine.httpWillStart = { url in
            XCTAssertTrue(page.isCryptonActive,"Authentication, fee reads and submission must all start in foreground Crypton")
            networkPaths.insert(url.path)
        }
        let identityValue = try await engine.run("contactIdentity")
        let identity = try XCTUnwrap(identityValue as? JSON)
        XCTAssertNoThrow(try Wire.identity(identity["receivingKey"] as? String ?? ""))
        XCTAssertNoThrow(try Wire.identity(identity["walletIdentity"] as? String ?? ""))
        XCTAssertNotEqual(identity["receivingKey"] as? String,identity["walletIdentity"] as? String)
        let envelope = try await engine.run("seal",text:"Single ME visit retained message") as! String
        let id = try store.create(envelope:envelope,key:"self",recipient:"self",name:"Self")
        let beforeStats = try await fixture("delivery-stats")
        let before = integer(beforeStats["payments"])!
        _ = try await engine.prepareAndSend(id)
        XCTAssertTrue(Set(["/.well-known/auth","/permissions/quote","/sendMessage"]).isSubset(of:networkPaths))
        XCTAssertEqual(try store.get(id)["state"] as? String,"SENT")
        let sentStats = try await fixture("delivery-stats")
        let paymentCount = integer(sentStats["payments"])
        XCTAssertEqual(paymentCount,before+1)
        XCTAssertEqual(integer(sentStats["authHandshakes"]),integer(beforeStats["authHandshakes"])!+1,"Immediate send must authenticate once across both quote requests")
        XCTAssertEqual(integer(sentStats["quotes"]),integer(beforeStats["quotes"])!+2,"The final quote must still be revalidated")
        do { _ = try await engine.prepareAndSend(id); XCTFail("A completed record must not pay again") } catch { }
        let finalPaymentCount = integer(try await fixture("delivery-stats")["payments"])
        XCTAssertEqual(finalPaymentCount,before+1)
    }
    @MainActor func testQuoteTimeoutRetriesWithFreshAuthenticationAndPaysOnce() async throws {
        try await available()
        let config = try await fixture("delivery-config"), folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let store = try DeliveryStore(directory:folder,fixtureHost:config["host"] as! String,fixtureAgent:config["agent"] as! String)
        let page = MEPageFixture(); defer { page.close() }
        let engine = CryptoEngine(wallet:page.wallet,store:store); defer { engine.close() }
        let envelope = try await engine.run("seal",text:"Transient quote timeout retained test") as! String
        let id = try store.create(envelope:envelope,key:"self",recipient:"self",name:"Timeout fixture")
        let before = try await fixture("delivery-stats")
        _ = try await fixture("quote-fault",["count":1,"mode":"timeout"])
        _ = try await engine.prepareAndSend(id)
        let after = try await fixture("delivery-stats")
        XCTAssertEqual(try store.get(id)["state"] as? String,"SENT")
        XCTAssertEqual(integer(after["quotes"]),integer(before["quotes"])!+3,"Retry plus final quote revalidation")
        XCTAssertEqual(integer(after["paymentAttempts"]),integer(before["paymentAttempts"])!+1)
        let ids = Array((after["quoteRequestIds"] as! [String]).suffix(3))
        XCTAssertEqual(Set(ids).count,3,"Every quote must have a fresh authenticated request nonce")
    }
    @MainActor func testQuoteRetryExhaustionAndHTTPRejectionNeverReachPayment() async throws {
        try await available()
        let config = try await fixture("delivery-config"), folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let store = try DeliveryStore(directory:folder,fixtureHost:config["host"] as! String,fixtureAgent:config["agent"] as! String)
        let page = MEPageFixture(); defer { page.close() }
        let engine = CryptoEngine(wallet:page.wallet,store:store); defer { engine.close() }
        let envelope = try await engine.run("seal",text:"Quote failure cannot pay") as! String
        for mode in ["timeout","http503"] {
            let count = mode == "timeout" ? 2 : 1
            let id = try store.create(envelope:envelope,key:"self",recipient:"self",name:"Unpaid fixture")
            let before = try await fixture("delivery-stats")
            _ = try await fixture("quote-fault",["count":count,"mode":mode])
            do { _ = try await engine.prepareAndSend(id); XCTFail("Failed quote reached payment") }
            catch { XCTAssertTrue(error.localizedDescription.contains(mode == "timeout" ? "timed out" : "HTTP 503"),error.localizedDescription) }
            let after = try await fixture("delivery-stats")
            XCTAssertEqual(integer(after["quotes"]),integer(before["quotes"])!+count)
            XCTAssertEqual(integer(after["paymentAttempts"]),integer(before["paymentAttempts"]))
            XCTAssertTrue(DeliveryStore.paymentNeverRequested(try store.get(id)))
        }
    }
    @MainActor func testImmediateSendStillRejectsChangedRevalidationWithoutPayment() async throws {
        try await available()
        let config = try await fixture("delivery-config"), folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let store = try DeliveryStore(directory:folder,fixtureHost:config["host"] as! String,fixtureAgent:config["agent"] as! String)
        let page = MEPageFixture(); defer { page.close() }
        let engine = CryptoEngine(wallet:page.wallet,store:store); defer { engine.close() }
        let envelope = try await engine.run("seal",text:"Immediate send must revalidate before payment") as! String
        let id = try store.create(envelope:envelope,key:"self",recipient:"self",name:"Disposable changed fee")
        let before = try await fixture("delivery-stats")
        _ = try await fixture("change-fee-on-revalidation",["changed":true])
        do { _ = try await engine.prepareAndSend(id); XCTFail("Changed quote reached payment") }
        catch { XCTAssertTrue(error.localizedDescription.contains("quote changed")) }
        _ = try await fixture("change-fee-on-revalidation",["changed":false])
        XCTAssertEqual(try store.get(id)["state"] as? String,"QUOTED")
        let after = try await fixture("delivery-stats")
        XCTAssertEqual(integer(after["payments"]),integer(before["payments"]))
        XCTAssertEqual(integer(after["paymentAttempts"]),integer(before["paymentAttempts"]))
        XCTAssertEqual(integer(after["quotes"]),integer(before["quotes"])!+2)
        XCTAssertEqual(integer(after["authHandshakes"]),integer(before["authHandshakes"])!+1)
    }
    @MainActor func testComposerSelfSendReturnsForForegroundSubmission() async throws {
        try await available()
        let config = try await fixture("delivery-config"), folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let store = try DeliveryStore(directory:folder,fixtureHost:config["host"] as! String,fixtureAgent:config["agent"] as! String)
        let suite = "crypton.send."+UUID().uuidString, defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        defaults.set(false,forKey:"soundEnabled"); defaults.set(true,forKey:"guideSeen")
        let page = MEPageFixture(); defer { page.close() }
        let model = AppModel(defaults:defaults,store:store,wallet:page.wallet)
        model.choose("self"); model.message = "Composer single visit: retained SDK fixture"
        model.process(sendWithMessageBox:true)
        for _ in 0..<600 { if !model.busy { break }; try await Task.sleep(nanoseconds:100_000_000) }
        XCTAssertFalse(model.busy); XCTAssertNil(model.error)
        XCTAssertEqual(model.screen,.delivery)
        XCTAssertEqual(try store.get(model.deliveryID)["state"] as? String,"SENT")
        XCTAssertEqual(model.status,"MessageBox delivery complete"); XCTAssertTrue(model.statusReady)
    }
    @MainActor func testNativePaidDeliveryRecoveryWithoutSecondPayment() async throws {
        try await available()
        let config = try await fixture("delivery-config"), directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store = try DeliveryStore(directory:directory,fixtureHost:config["host"] as! String,fixtureAgent:config["agent"] as! String)
        let page = MEPageFixture(); defer { page.close() }
        let engine = CryptoEngine(wallet:page.wallet,store:store); defer { engine.close() }
        let envelope = try await engine.run("seal",text:"Disposable native delivery test") as! String
        var req = URLRequest(url:URL(string:store.serviceHost+"/permissions/quote")!); req.timeoutInterval = 2
        do { _ = try await BoundedHTTP().fetch(req) } catch { throw XCTSkip("Start scripts/messagebox-fixture.cjs to run delivery tests.") }
        let before = integer(try await fixture("delivery-stats")["payments"])!
        let id = try store.create(envelope:envelope,key:"self",recipient:"self",name:"Disposable self")
        let beforeLaunches = page.launches
        _ = try await engine.deliver("prepare",id:id)
        XCTAssertEqual(page.launches,beforeLaunches + 1,"One ME launch must serve the whole quote operation")
        let prepared = try XCTUnwrap(try store.get(id)["prepared"] as? JSON)
        XCTAssertEqual(try store.feeTotal(prepared["quote"] as! JSON),20)
        _ = try await fixture("reject-next-delivery")
        do { _ = try await engine.deliver("send",id:id); XCTFail("Rejected delivery unexpectedly succeeded") }
        catch { XCTAssertTrue(error.localizedDescription.contains("FIXTURE_REJECTED_PAYMENT_CHECK"),"Preserve the authenticated server's reason for diagnosis") }
        let interrupted = try store.get(id)
        if interrupted["state"] as? String != "SENT" {
            XCTAssertEqual(interrupted["state"] as? String,"SUBMITTING")
            _ = try await fixture("drop-next-delivery")
            do { _ = try await engine.deliver("resume",id:id) } catch { print("Expected dropped receipt: " + error.localizedDescription) }
            if try store.get(id)["state"] as? String != "SENT" { _ = try await engine.deliver("resume",id:id) }
        }
        XCTAssertEqual(try store.get(id)["state"] as? String,"SENT")
        do { _ = try await engine.deliver("send",id:id); XCTFail("Sent record created another payment") } catch { }
        let stats = try await fixture("delivery-stats"); XCTAssertEqual(integer(stats["payments"]),before+1)
        let uncertain = try store.create(envelope:envelope,key:"self",recipient:"self",name:"Lost wallet response")
        _ = try await engine.deliver("prepare",id:uncertain)
        _ = try await fixture("lose-next-payment")
        do { _ = try await engine.deliver("send",id:uncertain); XCTFail("Lost wallet response unexpectedly confirmed") } catch { }
        XCTAssertEqual(try store.get(uncertain)["state"] as? String,"PAYMENT_REQUESTED")
        do { _ = try await engine.deliver("send",id:uncertain); XCTFail("Uncertain payment was repeated") } catch { }
        _ = try await engine.deliver("recover",id:uncertain)
        let history = try XCTUnwrap(try store.get(uncertain)["walletHistory"] as? JSON)
        XCTAssertEqual((history["transactions"] as? [JSON])?.count,1)
        let final = try await fixture("delivery-stats"); XCTAssertEqual(integer(final["payments"]),before+2)
    }
    @MainActor func testChangedQuoteDeniedPaymentInsufficientFundsAndOffline() async throws {
        try await available()
        let config = try await fixture("delivery-config"), directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store = try DeliveryStore(directory:directory,fixtureHost:config["host"] as! String,fixtureAgent:config["agent"] as! String)
        let wallet = JSONWallet(endpoint:URL(string:"http://127.0.0.1:18776")!)
        let engine = CryptoEngine(wallet:wallet,store:store); defer { engine.close() }
        let envelope = try await engine.run("seal",text:"Disposable failure tests") as! String
        func draft() async throws -> String {
            let id = try store.create(envelope:envelope,key:"self",recipient:"self",name:"Failure fixture")
            _ = try await engine.deliver("prepare",id:id); return id
        }
        let before = integer(try await fixture("delivery-stats")["payments"])!
        let changed = try await draft()
        _ = try await fixture("change-delivery-fee",["changed":true])
        do { _ = try await engine.deliver("send",id:changed); XCTFail("Changed quote was paid") } catch { }
        _ = try await fixture("change-delivery-fee",["changed":false])
        XCTAssertEqual(try store.get(changed)["state"] as? String,"QUOTED")
        for failure in ["insufficient","denied"] {
            let id = try await draft()
            _ = try await fixture("payment-failure",["kind":failure])
            do { _ = try await engine.deliver("send",id:id); XCTFail("Rejected payment succeeded") } catch { }
            XCTAssertEqual(try store.get(id)["state"] as? String,"PAYMENT_REQUESTED")
            let reopened = try DeliveryStore(directory:directory,fixtureHost:store.serviceHost,fixtureAgent:store.serviceAgent)
            XCTAssertThrowsError(try reopened.begin(id,action:"send"),"An unsuccessful wallet response must not authorize a second payment")
        }
        let revoked = try await draft()
        _ = try await fixture("deny-next")
        do { _ = try await engine.deliver("send",id:revoked); XCTFail("Revoked wallet request succeeded") } catch { }
        XCTAssertEqual(try store.get(revoked)["state"] as? String,"QUOTED")
        let offline = try await draft()
        _ = try await fixture("offline-next")
        do { _ = try await engine.deliver("send",id:offline); XCTFail("Offline wallet request succeeded") } catch { }
        XCTAssertEqual(try store.get(offline)["state"] as? String,"QUOTED")
        let after = try await fixture("delivery-stats")
        XCTAssertEqual(integer(after["payments"]),before)
    }
}
