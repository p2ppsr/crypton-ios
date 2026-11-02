import XCTest
import AVFoundation
@testable import Crypton

final class CryptonTests: XCTestCase {
    let key = "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
    func envelope() throws -> String { try jsonString(["protocol":"crypton","version":2,"sender":key,"ciphertext":Data(repeating:4,count:48).base64EncodedString()]) }
    @MainActor func testExactVerificationRequiresTargetedJournalBeforeCryptography() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store = InboxStore(delivery:DeliveryStore(directory:directory.appendingPathComponent("delivery")),directory:directory.appendingPathComponent("inbox"))
        let id = String(repeating:"a",count:64)
        let session = try InboxSession(store:store,action:"verify",wallet:key,id:id,offset:0,layer:"")
        try session.returned("getPublicKey",["identityKey":true],["publicKey":key])
        XCTAssertThrowsError(try session.beforeCrypto("createHmac",[:]),"No decryption before an exact-ID page checkpoint")
        let encrypted = try envelope()
        let row:JSON = ["messageId":id,"sender":key,"envelope":encrypted]
        var other = row; other["messageId"] = String(repeating:"b",count:64)
        XCTAssertThrowsError(try session.checkpoint("page",["wallet":key,"messages":[other]]))
        XCTAssertThrowsError(try session.checkpoint("page",["wallet":key,"messages":[row,row]]))
        try session.checkpoint("page",["wallet":key,"messages":[row]])
        let args:JSON = ["protocolID":[2,"crypton"],"keyID":"1","counterparty":key,"ciphertext":try Wire.envelope(encrypted)["ciphertext"]!]
        XCTAssertNoThrow(try session.beforeCrypto("decrypt",args))
        var changed = args; changed["ciphertext"] = "changed"
        XCTAssertThrowsError(try session.beforeCrypto("decrypt",changed))
        XCTAssertThrowsError(try session.beforeWallet("createAction",[:]))
        XCTAssertThrowsError(try session.beforeHTTP(URL(string:store.host+"/acknowledgeMessage")!,"POST",try jsonString(["messageIds":[id]])))
    }
    @MainActor func testUnpaidProofRejectsEveryPaymentMarkerAndUnknownState() {
        for state in ["DRAFT","QUOTED"] {
            XCTAssertTrue(DeliveryStore.paymentNeverRequested(["state":state]))
            for marker in ["paymentRequestedAt","walletResult","walletRefusal","payment","submittedAt","receipt"] {
                XCTAssertFalse(DeliveryStore.paymentNeverRequested(["state":state,marker:NSNull()]),marker)
            }
        }
        for state in ["PAYMENT_REQUESTED","PAYMENT_RETURNED","PAID","SUBMITTING","SENT","unknown",""] {
            XCTAssertFalse(DeliveryStore.paymentNeverRequested(["state":state]),state)
        }
        XCTAssertFalse(DeliveryStore.paymentNeverRequested([:]))
    }
    @MainActor func testCombinedContactImportExportAndDeliveryBinding() throws {
        let deliveryKey = "02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"
        let code = try Wire.contactCode(name:"Peer iOS",key:key,wallet:deliveryKey)
        let suite = "crypton.contact."+UUID().uuidString, defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let model = AppModel(defaults:defaults)
        XCTAssertTrue(model.importMessage(code)); XCTAssertEqual(model.screen,.contacts)
        XCTAssertTrue(model.contacts.isEmpty,"Contact import requires explicit saving")
        model.saveContact()
        let saved = try XCTUnwrap(model.contacts.first)
        XCTAssertEqual(saved.walletIdentity,deliveryKey)
        XCTAssertEqual(try Wire.contact(saved.shareText).key,key)
        let reopened = AppModel(defaults:defaults)
        reopened.chooseContact(try XCTUnwrap(reopened.contacts.first))
        XCTAssertEqual(reopened.peer,key); XCTAssertEqual(reopened.recipientWalletDraft,deliveryKey)
        reopened.output = try envelope(); reopened.outputKind = "encrypted"; reopened.newDelivery()
        XCTAssertEqual(reopened.deliveryRecipient,deliveryKey)
        model.choose(code); XCTAssertEqual(model.peer,key); XCTAssertEqual(model.recipientWalletDraft,deliveryKey)
        var bad = try object(Data(code.utf8)); bad["privateKey"] = "never import"; XCTAssertThrowsError(try Wire.contact(try jsonString(bad)))
        bad.removeValue(forKey:"privateKey"); bad["walletIdentity"] = String(repeating:"0",count:66); XCTAssertThrowsError(try Wire.contact(try jsonString(bad)))
        bad["walletIdentity"] = deliveryKey; bad["version"] = true; XCTAssertThrowsError(try Wire.contact(try jsonString(bad)))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let shares = try IncomingShareStore(directory:directory)
        let file = try shares.stage(text:code); XCTAssertEqual(try String(contentsOf:file),code)
    }
    func testIdentityCurveValidation() throws {
        XCTAssertEqual(try Wire.identity("  " + key.uppercased() + "\n"),key)
        XCTAssertThrowsError(try Wire.identity("02" + String(repeating:"0",count:64)))
        XCTAssertThrowsError(try Wire.identity("02" + String(repeating:"f",count:64)))
        XCTAssertThrowsError(try Wire.identity("04" + String(key.dropFirst(2))))
    }
    @MainActor func testEncryptedInboxIsolationMinimalRemovalAndRetention() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let delivery = DeliveryStore(directory:folder.appendingPathComponent("outbox")), inbox = InboxStore(delivery:delivery,directory:folder.appendingPathComponent("inbox"))
        let row:JSON = ["messageId":"test-message","sender":key,"envelope":try envelope()]
        try inbox.merge(key,[row]); try inbox.flag(key,"test-message","read",true); try inbox.flag(key,"test-message","dismissed",true)
        XCTAssertTrue(try inbox.list(key).isEmpty); XCTAssertEqual(try inbox.list(key,dismissed:true).count,1)
        let other = "02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"
        XCTAssertTrue(try inbox.list(other,dismissed:true).isEmpty)
        var changed = row; changed["envelope"] = try jsonString(["protocol":"crypton","version":2,"sender":key,"ciphertext":Data(repeating:8,count:48).base64EncodedString()])
        XCTAssertThrowsError(try inbox.merge(key,[changed])); XCTAssertThrowsError(try inbox.removed(key,"test-message"))
        try inbox.decrypted(key,"test-message")
        let pending = try inbox.get(key,"test-message")
        XCTAssertEqual(Set(pending.keys),Set(["version","wallet","host","messageId","state"]))
        try inbox.merge(key,[row]); XCTAssertTrue(InboxStore.pending(try inbox.get(key,"test-message")))
        try inbox.removed(key,"test-message"); XCTAssertTrue(try inbox.list(key,dismissed:true).isEmpty)
        let sent = try delivery.create(envelope:envelope(),key:key,recipient:key,name:"Private",disappear:true)
        XCTAssertThrowsError(try delivery.cleanup(sent)); XCTAssertNotNil(try delivery.get(sent)["envelope"])
    }
    @MainActor func testInboxSessionCannotSpendImportAcknowledgeEarlyOrChangeProfile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let inbox = InboxStore(delivery:DeliveryStore(directory:folder))
        let session = try InboxSession(store:inbox,action:"refresh",wallet:key,id:"",offset:0,layer:"")
        try session.beforeWallet("getPublicKey",["identityKey":true]); try session.returned("getPublicKey",["identityKey":true],["publicKey":key])
        for method in ["createAction","internalizeAction","signAction","encrypt","listActions"] { XCTAssertThrowsError(try session.beforeWallet(method,[:])) }
        XCTAssertThrowsError(try session.beforeHTTP(URL(string:inbox.host+"/acknowledgeMessage")!,"POST","{\"messageIds\":[\"test\"]}"))
        XCTAssertThrowsError(try session.beforeHTTP(URL(string:"https://example.com/listMessages")!,"POST","{}"))
        XCTAssertThrowsError(try session.returned("getPublicKey",["identityKey":true],["publicKey":"02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"]))
        XCTAssertThrowsError(try InboxStore.messageID("../escape"))
        let link = try MEWallet.handoffURL(URL(string:"http://localhost:42/cap/")!,scheme:"metanet-bob")
        XCTAssertEqual(link.scheme,"metanet-bob")
    }
    func testDiscoveryScopeAndUntrustedMetadata() throws {
        let lookup = try RecipientDiscovery.request("  bob@example.com  ")
        XCTAssertEqual(lookup.method,"discoverByAttributes")
        XCTAssertEqual((lookup.args["attributes"] as? JSON)?["any"] as? String,"bob@example.com")
        XCTAssertNoThrow(try RecipientDiscovery.arguments(lookup.method,lookup.args))
        XCTAssertEqual(try RecipientDiscovery.request(key).method,"discoverByIdentityKey")
        for query in ["a",String(repeating:"a",count:257),"bob\n@example.com","bob\u{202E}@example.com","02"+String(repeating:"0",count:64)] { XCTAssertThrowsError(try RecipientDiscovery.request(query)) }
        for changed:JSON in [["seekPermission":false],["limit":21],["offset":1],["trustedCertifiers":[key]],["attributes":["email":"bob@example.com"]]] {
            var args = lookup.args; changed.forEach { args[$0.key] = $0.value }
            XCTAssertThrowsError(try RecipientDiscovery.arguments(lookup.method,args))
        }
        XCTAssertNoThrow(try RecipientDiscovery.response(["totalCertificates":0,"certificates":[]],lookup.args))
        for response:JSON in [["totalCertificates":true,"certificates":[]],["totalCertificates":-1,"certificates":[]],["totalCertificates":1,"certificates":[["subject":key]]],["isError":true,"totalCertificates":0,"certificates":[]]] { XCTAssertThrowsError(try RecipientDiscovery.response(response,lookup.args)) }
        let row:JSON = ["key":key,"name":"bob@example.com","certification":"Email certified by Fixture SocialCert","certifier":key,"certificateType":"email"]
        XCTAssertEqual(try RecipientDiscovery.identities([row,row]).count,1)
        var bad = row; bad["certifier"] = "02"+String(repeating:"0",count:64)
        XCTAssertThrowsError(try RecipientDiscovery.identities([bad]))
        let oldContact = Data("[{\"name\":\"Existing contact\",\"key\":\"\(key)\"}]".utf8)
        XCTAssertNil(try JSONDecoder().decode([PublicContact].self,from:oldContact).first?.walletIdentity)
    }
    func testEnvelopeRejectsMetadataAndMalformedCiphertext() throws {
        var e = try Wire.envelope(envelope()); e["recipient"] = key
        XCTAssertThrowsError(try Wire.envelope(jsonString(e)))
        e.removeValue(forKey:"recipient"); e["version"] = true
        XCTAssertThrowsError(try Wire.envelope(jsonString(e)))
        e["version"] = 2; e["ciphertext"] = String(repeating:"!",count:64)
        XCTAssertThrowsError(try Wire.envelope(jsonString(e)))
        XCTAssertThrowsError(try Wire.envelope(String(repeating:"a",count:64_001)))
    }
    func testLegacyTransportPreservesUnicodeAndCiphertext() throws {
        let text = "café 🌍\n\"quoted\""
        let args = try Wire.legacy(text,peer:key,encrypt:true)
        XCTAssertEqual(args["plaintext"] as? String,Data(text.utf8).base64EncodedString())
        XCTAssertTrue(sameJSON(args["protocolID"],[1,"crypton"]))
        XCTAssertEqual(args["counterparty"] as? String,key)
        let cipher = Data(repeating:7,count:64).base64EncodedString()
        XCTAssertEqual(try Wire.legacy("\n"+cipher,peer:"self",encrypt:false)["ciphertext"] as? String,cipher)
        XCTAssertThrowsError(try Wire.legacy("",peer:key,encrypt:true))
    }
    func testWalletArgumentsAndStrictBytes() throws {
        let text = "你好"
        let args = try Wire.walletArguments("encrypt",Wire.legacy(text,peer:"self",encrypt:true))
        XCTAssertEqual(try Wire.bytes(args["plaintext"]),Data(text.utf8))
        XCTAssertEqual(try Wire.walletResult("decrypt",["plaintext":Array(text.utf8)]) as? String,text)
        XCTAssertThrowsError(try Wire.bytes([true]))
        XCTAssertThrowsError(try Wire.bytes([256]))
        XCTAssertThrowsError(try Wire.walletResult("decrypt",["plaintext":[255]]))
        XCTAssertThrowsError(try Wire.walletResult("createHmac",["hmac":[0]]))
        XCTAssertThrowsError(try Wire.walletResult("isAuthenticated",["authenticated":false]))
    }
    @MainActor func testQRImageRoundTripAndOversizeFallback() throws {
        let text = try envelope()
        let image = try XCTUnwrap(QRTools.image(text))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        defer { try? FileManager.default.removeItem(at:url) }
        try XCTUnwrap(image.pngData()).write(to:url)
        XCTAssertEqual(try QRTools.read(url),text)
        XCTAssertNil(QRTools.image(String(repeating:"x",count:64_000)))
    }
    func testEndpointPolicy() throws {
        XCTAssertEqual(try Wire.endpoint("https://wallet.example/api/").absoluteString,"https://wallet.example/api")
        for url in ["http://wallet.example","https://a:b@wallet.example","https://wallet.example?q=x","https://wallet.example#x","https://wallet.example:0"] { XCTAssertThrowsError(try Wire.endpoint(url)) }
        XCTAssertThrowsError(try Wire.endpoint("http://127.0.0.1:3321"))
        XCTAssertNoThrow(try Wire.endpoint("http://127.0.0.1:3321",debugLoopback:true))
    }
    @MainActor func testFreshQuoteRevalidationAndDefiniteRefusalRecovery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store = DeliveryStore(directory:directory)
        func draft() throws -> (String,JSON,JSON) {
            let id = try store.create(envelope:envelope(),key:key,recipient:key,name:"Fixture")
            let action:JSON = ["description":"MessageBox delivery payment","outputs":[["satoshis":1,"lockingScript":"76a914"+String(repeating:"0",count:40)+"88ac","outputDescription":"MessageBox server delivery fee","customInstructions":try jsonString(["recipientIdentityKey":DeliveryStore.agent,"derivationPrefix":"a","derivationSuffix":"b"])]],"options":["randomizeOutputs":false,"acceptDelayedBroadcast":false],"labels":["crypton-delivery-"+id]]
            let quote:JSON = ["deliveryFee":1,"recipientFee":0,"deliveryAgentIdentityKey":DeliveryStore.agent]
            try store.checkpoint(id,action:"prepare",kind:"prepared",value:["sender":key,"recipient":key,"quote":quote,"messageId":String(repeating:"a",count:64),"body":"{\"encryptedMessage\":\"AAAA\"}","action":action,"remittances":[]])
            return (id,action,quote)
        }
        let (id,action,quote) = try draft()
        // Simulate an old reviewed quote; a fresh identical authenticated quote
        // renews freshness without changing the reviewed action or recipients.
        var old = try store.get(id), prepared = old["prepared"] as! JSON
        prepared["quotedAt"] = 0; old["prepared"] = prepared
        try jsonData(old).write(to:directory.appendingPathComponent(id+".json"))
        XCTAssertThrowsError(try store.beforeWallet(id,action:"send",method:"createAction",args:action))
        var changed = quote; changed["deliveryFee"] = 2
        XCTAssertThrowsError(try store.checkpoint(id,action:"send",kind:"quoteRevalidated",value:["quote":changed]))
        try store.checkpoint(id,action:"send",kind:"quoteRevalidated",value:["quote":quote])
        try store.beforeWallet(id,action:"send",method:"createAction",args:action)
        try store.checkpoint(id,action:"recover",kind:"history",value:["sender":key,"totalActions":0,"transactions":[]])
        XCTAssertThrowsError(try store.retryRefusedPayment(id),"Empty history alone must not authorize repayment")
        try store.walletRefused(id,refusal:WalletRefusal(method:"createAction",code:1,detail:"Permission denied before signing",notCommitted:true))
        let reopened = DeliveryStore(directory:directory)
        try reopened.retryRefusedPayment(id)
        XCTAssertEqual(try reopened.get(id)["state"] as? String,"DRAFT")
        XCTAssertNil(try reopened.get(id)["prepared"])
        XCTAssertNotNil(try reopened.get(id)["previousRefusal"])
        let (uncertain,args,_) = try draft()
        try store.beforeWallet(uncertain,action:"send",method:"createAction",args:args)
        XCTAssertThrowsError(try store.walletRefused(uncertain,refusal:WalletRefusal(method:"createAction",code:1,detail:"Timeout",notCommitted:false)))
        XCTAssertThrowsError(try store.checkpoint(uncertain,action:"recover",kind:"history",value:["sender":DeliveryStore.agent,"totalActions":0,"transactions":[]]))
        XCTAssertThrowsError(try store.begin(uncertain,action:"send"))
    }
    @MainActor func testOutboxWriteAheadBlocksSecondPayment() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store = DeliveryStore(directory:directory)
        let id = try store.create(envelope:envelope(),key:key,recipient:key,name:"Recipient")
        let action: JSON = ["description":"MessageBox delivery payment","outputs":[["satoshis":1,"lockingScript":"76a914"+String(repeating:"0",count:40)+"88ac","outputDescription":"MessageBox server delivery fee","customInstructions":try jsonString(["recipientIdentityKey":DeliveryStore.agent,"derivationPrefix":"a","derivationSuffix":"b"])]],"options":["randomizeOutputs":false,"acceptDelayedBroadcast":false],"labels":["crypton-delivery-"+id]]
        let p: JSON = ["sender":key,"recipient":key,"quote":["deliveryFee":1,"recipientFee":0,"deliveryAgentIdentityKey":DeliveryStore.agent],"messageId":String(repeating:"a",count:64),"body":"{\"encryptedMessage\":\"AAAA\"}","action":action,"remittances":[]]
        try store.checkpoint(id,action:"prepare",kind:"prepared",value:p)
        var changed = action; changed["outputs"] = []
        XCTAssertThrowsError(try store.beforeWallet(id,action:"send",method:"createAction",args:changed))
        try store.beforeWallet(id,action:"send",method:"createAction",args:action)
        let reopened = DeliveryStore(directory:directory)
        XCTAssertEqual(try reopened.get(id)["state"] as? String,"PAYMENT_REQUESTED")
        XCTAssertThrowsError(try reopened.beforeWallet(id,action:"send",method:"createAction",args:action))
        XCTAssertThrowsError(try reopened.begin(id,action:"send"))
        XCTAssertThrowsError(try reopened.recipient(id,"self"))
        XCTAssertNoThrow(try reopened.begin(id,action:"recover"))
        XCTAssertThrowsError(try reopened.beforeHTTP(id,action:"send",url:URL(string:"https://evil.example/sendMessage")!,method:"POST",body:"{}"))
        XCTAssertThrowsError(try reopened.recoveryTransaction(id))
        let txid = String(repeating:"b",count:64)
        let history:JSON = ["sender":key,"totalActions":1,"transactions":[["txid":txid,"status":"completed"]]]
        try reopened.checkpoint(id,action:"recover",kind:"history",value:history)
        XCTAssertEqual(try reopened.recoveryTransaction(id),txid)
        // Native journal guards identity/state; the engine separately validates BEEF and outputs.
        let recovered:JSON = ["txid":txid,"tx":[1,2,3]]
        XCTAssertThrowsError(try reopened.checkpoint(id,action:"send",kind:"recoveredPayment",value:recovered))
        XCTAssertThrowsError(try reopened.checkpoint(id,action:"recover",kind:"recoveredPayment",value:["txid":String(repeating:"c",count:64),"tx":[1]]))
        try reopened.checkpoint(id,action:"recover",kind:"recoveredPayment",value:recovered)
        let recoveredStore = DeliveryStore(directory:directory)
        XCTAssertEqual(try recoveredStore.get(id)["state"] as? String,"PAYMENT_RETURNED")
        XCTAssertNoThrow(try recoveredStore.begin(id,action:"resume"))
        XCTAssertThrowsError(try recoveredStore.begin(id,action:"send"))
        XCTAssertThrowsError(try recoveredStore.beforeWallet(id,action:"send",method:"createAction",args:action))
        XCTAssertThrowsError(try recoveredStore.recoveryTransaction(id))
    }
    @MainActor func testRealWebKitEngineSelfAndWrongRecipient() async throws {
        let wallet = MemoryWallet(), store = DeliveryStore()
        let engine = CryptoEngine(wallet:wallet,store:store)
        defer { engine.close() }
        let identity = try await engine.run("identity") as? String
        XCTAssertNoThrow(try Wire.identity(identity ?? ""))
        let repeated = try await engine.run("identity") as? String
        XCTAssertEqual(repeated,identity)
        let text = "iOS → Android / web: café 🌍\n\"quotes\""
        let sealed = try await engine.run("seal",text:text) as! String
        XCTAssertEqual(try Wire.envelope(sealed).count,4)
        let opened = try await engine.run("open",text:sealed) as! JSON
        XCTAssertEqual(opened["text"] as? String,text)
        let second = try await engine.run("seal",text:text) as! String
        XCTAssertNotEqual(try Wire.envelope(second)["sender"] as? String,try Wire.envelope(sealed)["sender"] as? String)
        let wrong = try await engine.run("seal",text:text,peer:key) as! String
        do { _ = try await engine.run("open",text:wrong); XCTFail("Wrong recipient opened message") } catch { }
    }
    @MainActor func testImportedLegacyRequiresSenderAndContactsPersist() throws {
        let suite = "crypton.tests."+UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!; defer { defaults.removePersistentDomain(forName:suite) }
        let model = AppModel(defaults:defaults)
        model.importMessage(Data(repeating:8,count:64).base64EncodedString())
        XCTAssertEqual(model.screen,.recipient); XCTAssertFalse(model.legacySenderSelected)
        model.contactName = "Friend"; model.keyDraft = key; model.saveContact()
        let reopened = AppModel(defaults:defaults)
        XCTAssertEqual(reopened.contacts,[PublicContact(name:"Friend",key:key)])
        model.message = "private draft"; model.output = "private result"; model.done()
        XCTAssertEqual(model.message,""); XCTAssertEqual(model.output,"")
    }
    @MainActor func testAudioMuteBackgroundAndInterruption() async throws {
        let sound = SoundPlayer()
        defer { sound.enabled = false; sound.active = false }
        sound.enabled = true; sound.active = true
        XCTAssertTrue(sound.playbackState.music,"The actual simulator music player should start")
        sound.effect(encrypt:true)
        sound.enabled = false
        XCTAssertFalse(sound.playbackState.allocated,"Mute must release both music and effect players")
        sound.enabled = true; sound.active = false
        XCTAssertFalse(sound.playbackState.allocated,"Backgrounding must release the players")
        sound.active = true
        XCTAssertTrue(sound.playbackState.music)
        func interrupt(_ type:AVAudioSession.InterruptionType,_ options:AVAudioSession.InterruptionOptions = []) async throws {
            NotificationCenter.default.post(name:AVAudioSession.interruptionNotification,object:AVAudioSession.sharedInstance(),userInfo:[AVAudioSessionInterruptionTypeKey:type.rawValue,AVAudioSessionInterruptionOptionKey:options.rawValue])
            try await Task.sleep(nanoseconds:30_000_000)
        }
        try await interrupt(.began)
        XCTAssertFalse(sound.playbackState.allocated,"An interruption must silence and release the players")
        try await interrupt(.ended,.shouldResume)
        XCTAssertTrue(sound.playbackState.music,"Foreground enabled music should resume only when permitted")
        try await interrupt(.began)
        sound.enabled = false
        try await interrupt(.ended,.shouldResume)
        XCTAssertFalse(sound.playbackState.allocated,"An interruption must not undo mute")
        sound.enabled = true
        try await interrupt(.began)
        sound.active = false
        try await interrupt(.ended,.shouldResume)
        XCTAssertFalse(sound.playbackState.allocated,"An interruption must not start background music")
        sound.active = true
        XCTAssertTrue(sound.playbackState.music)
        try await interrupt(.began)
        try await interrupt(.ended)
        XCTAssertFalse(sound.playbackState.allocated,"A missing shouldResume flag must keep playback stopped")
    }
    @MainActor func testFileImportsAndInvalidInputsPreserveDraft() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let suite = "crypton.filetests."+UUID().uuidString, defaults = UserDefaults(suiteName:suite)!
        defaults.set(false,forKey:"soundEnabled"); defer { defaults.removePersistentDomain(forName:suite) }
        let model = AppModel(defaults:defaults), value = try envelope()
        let text = directory.appendingPathComponent("sealed.crypton")
        try Data(value.utf8).write(to:text)
        XCTAssertTrue(model.importURL(text)); XCTAssertEqual(model.ciphertext,value)
        let image = try XCTUnwrap(QRTools.image(value))
        for (name,bytes) in [("code.png",try XCTUnwrap(image.pngData())),("code.jpg",try XCTUnwrap(image.jpegData(compressionQuality:1)))] {
            let url = directory.appendingPathComponent(name); try bytes.write(to:url)
            XCTAssertTrue(model.importURL(url)); XCTAssertEqual(model.ciphertext,value)
        }
        for (name,bytes) in [("plain.txt",Data("Unencrypted text is not a Crypton message.".utf8)),("broken.png",Data([1,2,3])),("invalid-utf8.txt",Data([255]))] {
            let url = directory.appendingPathComponent(name); try bytes.write(to:url)
            XCTAssertFalse(model.importURL(url)); XCTAssertEqual(model.ciphertext,value,"A failed import must preserve the existing draft")
        }
        let huge = directory.appendingPathComponent("huge.crypton")
        FileManager.default.createFile(atPath:huge.path,contents:Data())
        let file = try FileHandle(forWritingTo:huge); try file.truncate(atOffset:20_000_001); try file.close()
        XCTAssertFalse(model.importURL(huge)); XCTAssertEqual(model.error,"This file is too large.")
        XCTAssertFalse(model.importURL(URL(string:"https://example.invalid/payload")!))
        let legacy = directory.appendingPathComponent("legacy.txt"), ciphertext = Data(repeating:7,count:64).base64EncodedString()
        try Data(ciphertext.utf8).write(to:legacy)
        XCTAssertTrue(model.importURL(legacy)); XCTAssertEqual(model.ciphertext,ciphertext)
        XCTAssertEqual(model.screen,.recipient); XCTAssertFalse(model.legacySenderSelected)
    }
}

@MainActor private final class MemoryWallet: WalletConnection {
    func call(_ method:String,_ args:JSON,raw:Bool) async throws -> Any {
        if method == "createHmac" { return Data(repeating:7,count:32).base64EncodedString() }
        throw CryptonError("Fixture wallet denied decryption.")
    }
    func cancel() {}
}

final class SDKWalletIntegrationTests: XCTestCase {
    @MainActor private func fixture(_ path:String,_ args:JSON = [:]) async throws -> JSON {
        var request = URLRequest(url:URL(string:"http://127.0.0.1:18776/test/"+path)!)
        request.httpMethod = "POST"; request.httpBody = try jsonData(args)
        request.setValue("https://crypton.ios",forHTTPHeaderField:"Origin"); request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        let (data,response) = try await BoundedHTTP().fetch(request)
        guard response.statusCode == 200 else { throw CryptonError("Fixture rejected the request.") }; return try object(data)
    }
    @MainActor func testSDKWalletHTTPInteropAndDenial() async throws {
        do { _ = try await fixture("recipient") } catch { throw XCTSkip("Start scripts/sdk-wallet-fixture.cjs to run SDK-backed HTTP integration tests.") }
        let wallet = JSONWallet(endpoint:URL(string:"http://127.0.0.1:18776")!)
        _ = try await wallet.call("isAuthenticated",[:])
        let engine = CryptoEngine(wallet:wallet,store:DeliveryStore()); defer { engine.close() }
        let recipient = try await fixture("recipient")["publicKey"] as! String
        let text = "iOS SDK integration: 你好 café 🌍\n\"quoted\""
        let sealed = try await engine.run("seal",text:text,peer:recipient) as! String
        let opened = try await fixture("v2-open",["envelope":sealed])
        XCTAssertEqual(opened["text"] as? String,text)
        do { _ = try await fixture("v2-wrong",["envelope":sealed]); XCTFail("Wrong SDK recipient opened message") } catch { }
        for mode in ["derived","root"] {
            let incoming = try await fixture("v2-for-ios",["mode":mode,"content":["kind":"message","text":text]])["envelope"] as! String
            let result = try await engine.run("open",text:incoming) as! JSON
            XCTAssertEqual(result["text"] as? String,text)
        }
        let layer = try await fixture("v2-for-ios",["content":["kind":"layer","envelope":sealed,"note":"Forward to friend"]])["envelope"] as! String
        let result = try await engine.run("open",text:layer) as! JSON
        XCTAssertEqual(result["kind"] as? String,"layer"); XCTAssertEqual(result["envelope"] as? String,sealed); XCTAssertEqual(result["note"] as? String,"Forward to friend")
        let legacy = try await wallet.call("encrypt",Wire.legacy(text,peer:recipient,encrypt:true)) as! String
        let legacyOpened = try await fixture("decrypt-from-ios",["ciphertext":legacy])
        XCTAssertEqual(legacyOpened["plaintext"] as? String,text)
        let incoming = try await fixture("encrypt-for-ios",["plaintext":text])
        let args = try Wire.legacy(incoming["ciphertext"] as! String,peer:incoming["sender"] as! String,encrypt:false)
        let clear = try await wallet.call("decrypt",args) as! String; XCTAssertEqual(clear,text)
        _ = try await fixture("deny-next")
        do { _ = try await wallet.call("getPublicKey",[:]); XCTFail("Permission denial ignored") } catch { }
        _ = try await fixture("redirect-next")
        do { _ = try await wallet.call("getPublicKey",[:]); XCTFail("Wallet redirect followed") } catch { }
    }
}
