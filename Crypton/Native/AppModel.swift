import SwiftUI
import WebKit
import AVFoundation

struct PublicContact: Codable, Identifiable, Equatable {
    var name: String
    var key: String
    var walletIdentity: String? = nil
    var id: String { key }
    var shareText:String { (try? walletIdentity.map { try Wire.contactCode(name:name,key:key,wallet:$0) }) ?? key }
}
enum Screen { case home, recipient, compose, result, contacts, settings, guide, outbox, delivery, inbox, inboxMessage }

@MainActor final class AppModel: ObservableObject {
    @Published var screen: Screen = .home { didSet { if oldValue == .inboxMessage && screen != .inboxMessage { clearInboxView(); scheduleRemovalRetry(1) } } }
    @Published var busy = false
    @Published var activity = "Working…"
    @Published var error: String?
    @Published var status = "Connect your wallet"
    var statusReady:Bool {
        !busy && ["Wallet connected","Inbox up to date","Message decrypted · copy retained","MessageBox delivery complete","Message encrypted","Message decrypted","Private message opened","Message removed"].contains(status)
    }
    @Published var portalVisible = false
    @Published var decrypting = false
    @Published var message = ""
    @Published var ciphertext = ""
    @Published var peer = "self"
    @Published var peerName = "Myself"
    @Published var keyDraft = "" { didSet { if keyDraft != oldValue { recipientWalletDraft = "" } } }
    @Published var contactName = ""
    @Published var contactWalletDraft = ""
    @Published var recipientWalletDraft = ""
    @Published var sharedIdentity:PublicContact?
    var identityShareText:String { sharedIdentity?.shareText ?? output }
    @Published var recipientQuery = "" { didSet { if recipientQuery != oldValue { clearSearch() } } }
    @Published private(set) var recipientChosen = false
    @Published private(set) var searchResults: [DiscoveredIdentity] = []
    @Published private(set) var searchCompleted = false
    @Published private(set) var selectedIdentity: DiscoveredIdentity?
    @Published private(set) var recipientSaved = false
    private var peerWalletIdentity: String?
    @Published var output = ""
    @Published var outputKind = "message"
    @Published var layerNote = ""
    @Published var deliveryID = ""
    @Published var deliveryRecipient = ""
    @Published var contacts: [PublicContact] = []
    @Published var disappearSend:Bool { didSet { defaults.set(disappearSend,forKey:"disappearSend"); if disappearSend { clearOwnedClipboard() } } }
    @Published var disappearReceive:Bool { didSet { defaults.set(disappearReceive,forKey:"disappearReceive") } }
    @Published var inboxWallet:String { didSet { defaults.set(inboxWallet,forKey:"inboxWallet") } }
    @Published var inboxID = ""
    @Published var inboxRows:[JSON] = []
    @Published var inboxContent:JSON?
    @Published var inboxNotice = ""
    @Published var inboxMore = false
    @Published var showDismissed = false { didSet { loadInbox() } }
    @Published var privateInboxView = false
    @Published var privateRemoved = false
    @Published var foreground = false
    @Published var captureActive = false
    private var privateViewed = false
    private var inboxOffset = 0
    private var removalNeedsWallet = false
    private var removalRetry:Task<Void,Never>?
    let inboxStore:InboxStore
    @Published var legacy: Bool { didSet { defaults.set(legacy,forKey:"legacyMessages") } }
    @Published var walletMode: String
    @Published var endpoint: String
    @Published var soundEnabled: Bool { didSet { defaults.set(soundEnabled,forKey:"soundEnabled"); sound.enabled = soundEnabled } }
    @Published var advancedMode: Bool { didSet { defaults.set(advancedMode,forKey:"advancedMode") } }
    @Published private(set) var encryptedPreview:String?
    @Published var previewHovered = false
    @Published var previewPressed = false
    var presentsEncryptedPreview = false
    #if DEBUG
    private var holdPreviewForQA = false
    #endif
    let store: DeliveryStore
    let sound = SoundPlayer()
    private let defaults: UserDefaults
    private(set) var wallet: WalletConnection?
    private var engine: CryptoEngine?
    private var task: Task<Void,Never>?
    var portal: PortalWallet? { wallet as? PortalWallet }
    init(defaults: UserDefaults = .standard, store: DeliveryStore? = nil, wallet: WalletConnection? = nil) {
        NSLog("Crypton lifecycle model.created")
        let defaults = ProcessInfo.processInfo.arguments.contains("--uitesting") ? UserDefaults(suiteName:"crypton.uitests")! : defaults
        if ProcessInfo.processInfo.arguments.contains("--uitesting") { defaults.removePersistentDomain(forName:"crypton.uitests") }
        #if DEBUG
        let testInbox = ProcessInfo.processInfo.arguments.contains("--uitesting")
        if testInbox { defaults.set(false,forKey:"soundEnabled") }
        let sharedDefaults = UserDefaults(suiteName:IncomingShareStore.group)
        sharedDefaults?.set(testInbox,forKey:"useUITestInbox"); sharedDefaults?.synchronize()
        if testInbox, let shared = try? IncomingShareStore(), shared.directory.lastPathComponent == "UITestIncoming" { try? FileManager.default.removeItem(at:shared.directory) }
        if ProcessInfo.processInfo.arguments.contains("--uitesting"), ProcessInfo.processInfo.arguments.contains("--sdk-wallet-fixture") {
            defaults.set("json",forKey:"walletMode"); defaults.set("http://127.0.0.1:18776",forKey:"walletEndpoint"); defaults.set(false,forKey:"legacyMessages")
        }
        #endif
        self.defaults = defaults
        advancedMode = defaults.bool(forKey:"advancedMode")
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting"), ProcessInfo.processInfo.arguments.contains("--advanced-mode") { advancedMode = true }
        if ["--uitesting","--sdk-wallet-fixture","--messagebox-fixture","--hold-encrypted-preview-for-qa"].allSatisfy(ProcessInfo.processInfo.arguments.contains) { holdPreviewForQA = true }
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting"), ProcessInfo.processInfo.arguments.contains("--messagebox-fixture") {
            let directory = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("UITestDeliveries")
            if ProcessInfo.processInfo.arguments.contains("--reset-qa-outbox") { try? FileManager.default.removeItem(at:directory) }
            // Fixed disposable loopback service and public key; unreachable in Release builds.
            self.store = try! DeliveryStore(directory:directory,fixtureHost:"http://127.0.0.1:18777",fixtureAgent:"02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5")
        } else { self.store = store ?? DeliveryStore() }
        #else
        self.store = store ?? DeliveryStore()
        #endif
        #if DEBUG
        let inboxDirectory = ProcessInfo.processInfo.arguments.contains("--uitesting") ? self.store.directory.deletingLastPathComponent().appendingPathComponent("UITestInboxes") : nil
        if ProcessInfo.processInfo.arguments.contains("--reset-qa-inbox"), let inboxDirectory = inboxDirectory { try? FileManager.default.removeItem(at:inboxDirectory) }
        inboxStore = InboxStore(delivery:self.store,directory:inboxDirectory)
        #else
        inboxStore = InboxStore(delivery:self.store)
        #endif
        disappearSend = defaults.bool(forKey:"disappearSend"); disappearReceive = defaults.bool(forKey:"disappearReceive")
        inboxWallet = defaults.string(forKey:"inboxWallet") ?? ""
        walletMode = defaults.string(forKey:"walletMode") ?? "me"
        legacy = defaults.object(forKey:"legacyMessages") as? Bool ?? (defaults.string(forKey:"walletMode") == "portal")
        endpoint = defaults.string(forKey:"walletEndpoint") ?? ""
        soundEnabled = defaults.object(forKey:"soundEnabled") as? Bool ?? false
        if let data = defaults.data(forKey:"publicContacts"), let saved = try? JSONDecoder().decode([PublicContact].self,from:data) { contacts = saved }
        sound.enabled = soundEnabled
        configureWallet()
        if let wallet = wallet { self.wallet = wallet }
        if advancedMode && !defaults.bool(forKey:"guideSeen") && !ProcessInfo.processInfo.arguments.contains("--uitesting") { screen = .guide }
    }
    private func configureWallet() {
        clearSearch()
        engine?.close(); engine = nil; portal?.close(); wallet?.cancel(); wallet = nil
        status = "Connect your wallet"; portalVisible = false
        if ["me","me-bob"].contains(walletMode) {
            let me = MEWallet(scheme:walletMode == "me-bob" ? "metanet-bob" : "metanet")
            me.progress = { [weak self] value in guard let self = self, self.busy else { return }; self.activity = value; self.status = value }
            wallet = me
        } else if walletMode == "portal" {
            let portal = PortalWallet(); portal.visibility = { [weak self] show in self?.portalVisible = show }; wallet = portal
        } else if let url = try? Wire.endpoint(endpoint,debugLoopback: Self.debugLoopback) { wallet = JSONWallet(endpoint:url) }
    }
    static var debugLoopback: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    func saveWallet() {
        do {
            if walletMode == "json" { endpoint = try Wire.endpoint(endpoint,debugLoopback:Self.debugLoopback).absoluteString }
            defaults.set(walletMode,forKey:"walletMode"); defaults.set(endpoint,forKey:"walletEndpoint")
            legacy = walletMode == "portal"
            configureWallet(); error = nil
        } catch { self.error = error.localizedDescription }
    }
    func connection() throws -> WalletConnection {
        guard let wallet = wallet else { throw CryptonError("Add a BRC-100 wallet address in Settings first.") }; return wallet
    }
    #if targetEnvironment(simulator)
    private var scriptedRun: ScriptedRun?
    private var scriptedInbox: Task<Void,Never>?
    let scriptedRuntimeID = UUID().uuidString.lowercased()
    var scriptedExpectedSender:String?
    var scriptedEvent:((String) -> Void)?
    var scriptedEngineID:String? { engine?.instanceID }
    private var scriptedRoot:URL { FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("ScriptedRuns") }
    func publishScriptRuntime() {
        let value:JSON = ["driver_version":2,"runtime_id":scriptedRuntimeID,"engine_id":scriptedEngineID ?? "", "pid":ProcessInfo.processInfo.processIdentifier,"idle":!busy && scriptedRun?.finished != false]
        try? FileManager.default.createDirectory(at:scriptedRoot,withIntermediateDirectories:true)
        if let data = try? jsonData(value) { try? data.write(to:scriptedRoot.appendingPathComponent("runtime.json"),options:.atomic) }
    }
    private func consumeScriptInbox() {
        guard foreground, !busy, scriptedRun?.finished != false else { return }
        let pointer = scriptedRoot.appendingPathComponent("pending.txt")
        guard let bytes = try? Data(contentsOf:pointer), bytes.count <= 36 else { return }
        try? FileManager.default.removeItem(at:pointer)
        guard let id = UUID(uuidString:String(decoding:bytes,as:UTF8.self)) else { return }
        scriptedRun = ScriptedRun(model:self,id:id); scriptedRun?.start()
    }
    func startScriptIfRequested() {
        // Explicit simulator launch opt-in only. No URL or production control surface.
        guard scriptedInbox == nil, ProcessInfo.processInfo.arguments.contains("--crypton-script") else { return }
        scriptedRun = ScriptedRun(model:self); scriptedRun?.start()
        publishScriptRuntime()
        scriptedInbox = Task { [weak self] in
            while !Task.isCancelled {
                self?.consumeScriptInbox()
                do { try await Task.sleep(nanoseconds:100_000_000) } catch { return }
            }
        }
    }
    #endif
    private func crypto() throws -> CryptoEngine {
        if let engine = engine { return engine }
        let engine = CryptoEngine(wallet:try connection(),store:store,inbox:inboxStore)
        #if targetEnvironment(simulator)
        engine.scriptWalletIdentity = { [weak self] key in
            if let expected = self?.scriptedExpectedSender, key != expected { throw CryptonError("Sender wallet profile changed; no payment may proceed") }
            self?.scriptedEvent?("sender_verified")
        }
        engine.scriptStage = { [weak self] stage in self?.scriptedEvent?(stage) }
        #endif
        engine.progress = { [weak self] value in guard let self = self, self.busy else { return }; self.activity = value; self.status = value }
        self.engine = engine; return engine
    }
    func perform(_ work: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true; error = nil; activity = "Preparing request…"
        task = Task { [weak self] in
            guard let self = self else { return }
            defer { self.busy = false; self.task = nil; self.sound.stopEffect() }
            do { try await work() } catch { self.error = error.localizedDescription; self.status = self.screen == .delivery ? "Delivery paused · open the saved record" : "Request paused · " + self.activity }
        }
    }
    func cancel() { engine?.cancel(); wallet?.cancel(); task?.cancel(); portalVisible = false; encryptedPreview = nil; previewHovered = false; previewPressed = false }
    func connect(showPortal: Bool = false) {
        perform { [self] in
            if let portal = portal { try await portal.authenticate(); portalVisible = showPortal }
            else { _ = try await connection().call(wallet is MEWallet ? "waitForAuthentication" : "isAuthenticated",[:],raw:false) }
            status = "Wallet connected"
        }
    }
    func begin(decrypt: Bool) {
        clearSearch(); recipientQuery = ""
        decrypting = decrypt; keyDraft = peer == "self" ? "" : peer
        screen = decrypt ? .compose : .recipient
    }
    func choose(_ key: String, name: String = "Selected identity", walletIdentity:String? = nil) {
        do {
            let code = Wire.isContact(key) ? try Wire.contact(key) : nil
            let key = try code?.key ?? (key == "self" ? key : Wire.identity(key))
            let deliveryKey = try (code?.wallet ?? walletIdentity).map { try Wire.identity($0) }
            peer = key; peerName = code?.name ?? name; peerWalletIdentity = deliveryKey
            recipientWalletDraft = deliveryKey ?? (defaults.dictionary(forKey:"deliveryKeys") as? [String:String])?[key] ?? ""
            selectedIdentity = nil; recipientSaved = false; screen = .compose
            recipientChosen = true
        }
        catch { self.error = error.localizedDescription }
    }
    private func clearSearch() { searchResults = []; searchCompleted = false; selectedIdentity = nil; recipientSaved = false; recipientChosen = false }
    func searchRecipients() {
        guard !busy else { return }
        clearSearch()
        let query = recipientQuery
        perform { [self] in
            guard !(wallet is PortalWallet) else { throw CryptonError("Recipient search requires Metanet Explorer or a BRC-100 wallet. Choose one in Settings.") }
            _ = try RecipientDiscovery.request(query)
            let results = try await crypto().search(query)
            try Task.checkCancellation()
            guard recipientQuery == query else { return }
            searchResults = results; searchCompleted = true; status = "Wallet connected"
        }
    }
    func chooseDiscovered(_ identity:DiscoveredIdentity) {
        guard !busy, searchCompleted, searchResults.contains(identity) else { error = "Search again and select a current recipient."; return }
        choose(identity.key,name:String(identity.name.prefix(120)))
        peerWalletIdentity = identity.key; recipientWalletDraft = identity.key; selectedIdentity = identity; legacySenderSelected = true
    }
    func chooseContact(_ contact:PublicContact) {
        do {
            let key = try Wire.identity(contact.key)
            let walletKey = try contact.walletIdentity.map { try Wire.identity($0) }
            choose(key,name:contact.name,walletIdentity:walletKey)
            peerWalletIdentity = walletKey; legacySenderSelected = true
        } catch { self.error = error.localizedDescription }
    }
    func saveDiscoveredRecipient() {
        guard let identity = selectedIdentity, identity.key == peer, !busy else { return }
        do {
            let contact = PublicContact(name:String(identity.name.prefix(120)),key:try Wire.identity(identity.key),walletIdentity:try Wire.identity(identity.key))
            try persistContacts((contacts.filter { $0.key != contact.key } + [contact]).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
            recipientSaved = true
        } catch { self.error = error.localizedDescription }
    }
    func process(sendWithMessageBox:Bool = false) {
        // Raw ciphertext always requires an explicit sender selection, including imported files.
        if decrypting && !Wire.isEnvelope(ciphertext) && !legacySenderSelected { screen = .recipient; return }
        perform { [self] in
            let me = sendWithMessageBox ? wallet as? MEWallet : nil
            me?.beginOperation(); defer { me?.endOperation() }
            sound.effect(encrypt:!decrypting); layerNote = ""
            if !decrypting && !legacy {
                output = try await crypto().run("seal",text:message,peer:peer) as? String ?? ""
                _ = try Wire.envelope(output); outputKind = "encrypted"
            } else if decrypting && Wire.isEnvelope(ciphertext) {
                guard let value = try await crypto().run("open",text:ciphertext) as? JSON else { throw CryptonError("Invalid decrypted content.") }
                let layer = value["kind"] as? String == "layer"
                output = value[layer ? "envelope" : "text"] as? String ?? ""; layerNote = value["note"] as? String ?? ""
                outputKind = layer ? "layer" : "message"
            } else {
                let args = try Wire.legacy(decrypting ? ciphertext : message,peer:peer,encrypt:!decrypting)
                guard let result = try await connection().call(decrypting ? "decrypt" : "encrypt",args,raw:false) as? String, result.utf8.count <= 100_000 else { throw CryptonError("Invalid wallet response.") }
                output = result; outputKind = decrypting ? "message" : "encrypted"
            }
            if sendWithMessageBox { try await previewEncryptedMessage(output) }
            try Task.checkCancellation()
            screen = .result
            if sendWithMessageBox {
                guard !decrypting, !legacy else { throw CryptonError("MessageBox requires a Crypton v2 message.") }
                if peer != "self" {
                    peerWalletIdentity = try Wire.identity(recipientWalletDraft)
                    var saved = defaults.dictionary(forKey:"deliveryKeys") as? [String:String] ?? [:]
                    saved[peer] = peerWalletIdentity; defaults.set(saved,forKey:"deliveryKeys")
                }
                newDelivery()
                guard screen == .delivery else { throw CryptonError(error ?? "Could not prepare this delivery.") }
                do { _ = try await crypto().prepareAndSend(deliveryID) }
                catch {
                    if disappearSend, let marker = try? store.get(deliveryID), DeliveryStore.discarded(marker) { wipeSentMessage() }
                    throw error
                }
                if disappearSend, !FileManager.default.fileExists(atPath:store.directory.appendingPathComponent(deliveryID+".json").path) { wipeSentMessage() }
                else { status = "MessageBox delivery complete" }
            } else { status = decrypting ? "Message decrypted" : "Message encrypted" }
        }
    }
    /// Preview the actual ciphertext before creating any delivery/payment intent.
    /// Time only advances while the preview is visible and not held by the user.
    func previewEncryptedMessage(_ envelope:String) async throws {
        guard presentsEncryptedPreview, !advancedMode else { return }
        let value = try Wire.envelope(envelope)
        guard let ciphertext = value["ciphertext"] as? String else { throw CryptonError("Invalid encrypted preview.") }
        encryptedPreview = ciphertext; previewHovered = false; previewPressed = false
        #if DEBUG
        // Only the explicitly opted-in disposable UI fixture can hold the
        // short preview for a deterministic, zero-payment cancellation check.
        previewPressed = holdPreviewForQA
        #endif
        activity = "Message encrypted · hold to inspect"; status = activity
        NSLog("Crypton lifecycle encryptedPreview.presented")
        defer { encryptedPreview = nil; previewHovered = false; previewPressed = false }
        var remaining:TimeInterval = 0.5
        while remaining > 0 {
            try Task.checkCancellation()
            let began = ProcessInfo.processInfo.systemUptime
            let counting = foreground && !previewHovered && !previewPressed
            try await Task.sleep(nanoseconds:10_000_000)
            if counting && foreground && !previewHovered && !previewPressed {
                remaining -= ProcessInfo.processInfo.systemUptime - began
            }
        }
        try Task.checkCancellation()
        NSLog("Crypton lifecycle encryptedPreview.completed")
    }
    @Published var legacySenderSelected = false
    func identity(root: Bool = false) {
        perform { [self] in
            let result:Any
            sharedIdentity = nil
            if !legacy && !root {
                guard let card = try await crypto().run("contactIdentity") as? JSON else { throw CryptonError("Invalid contact identity.") }
                let receiving = try Wire.identity(card["receivingKey"] as? String ?? "")
                let delivery = try Wire.identity(card["walletIdentity"] as? String ?? "")
                sharedIdentity = PublicContact(name:"Crypton contact",key:receiving,walletIdentity:delivery)
                result = receiving
            } else { result = try await connection().call("getPublicKey",["identityKey":true],raw:false) }
            output = try Wire.identity(result as? String ?? "")
            outputKind = root ? "walletIdentity" : "identity"; screen = .result; status = "Wallet connected"
        }
    }
    @discardableResult func importMessage(_ value: String) -> Bool {
        do {
            guard value.utf8.count <= 100_000 else { throw CryptonError("Payload too large.") }
            if Wire.isContact(value) { try importIdentity(value); screen = .contacts; return true }
            if Wire.isEnvelope(value) { _ = try Wire.envelope(value) }
            else { _ = try Wire.legacy(value,peer:"self",encrypt:false) }
            ciphertext = value; decrypting = true; legacySenderSelected = false; output = ""; layerNote = ""
            screen = Wire.isEnvelope(value) ? .compose : .recipient
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult func importURL(_ url: URL) -> Bool {
        if url.scheme == "crypton-wallet" {
            guard wallet is MEWallet else { return false }
            return (wallet as? MEWallet)?.returned(url) ?? false
        }
        guard url.isFileURL else { self.error = "Unsupported Crypton link."; return false }
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
            guard size <= 20_000_000 else { throw CryptonError("This file is too large.") }
            if ["png","jpg","jpeg","heic"].contains(url.pathExtension.lowercased()) { return importMessage(try QRTools.read(url)) }
            else { return importMessage(try String(contentsOf:url,encoding:.utf8)) }
        } catch { self.error = error.localizedDescription; return false }
    }
    func importIdentity(_ text:String) throws {
        if Wire.isContact(text) {
            let card = try Wire.contact(text)
            keyDraft = card.key; contactWalletDraft = card.wallet
            if screen != .contacts || contactName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { contactName = card.name }
            recipientWalletDraft = card.wallet
        } else { keyDraft = try Wire.identity(text); contactWalletDraft = ""; recipientWalletDraft = "" }
    }
    func saveContact() {
        do {
            let name = contactName.trimmingCharacters(in:.whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 120 else { throw CryptonError("Enter a contact name of at most 120 characters.") }
            let card = Wire.isContact(keyDraft) ? try Wire.contact(keyDraft) : nil
            let key = try card?.key ?? Wire.identity(keyDraft)
            let walletText = card?.wallet ?? contactWalletDraft.trimmingCharacters(in:.whitespacesAndNewlines)
            let deliveryKey = walletText.isEmpty ? nil : try Wire.identity(walletText)
            if let deliveryKey = deliveryKey { _ = try Wire.contactCode(name:name,key:key,wallet:deliveryKey) }
            var updated = contacts.filter { $0.key != key }; updated.append(PublicContact(name:name,key:key,walletIdentity:deliveryKey)); updated.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            try persistContacts(updated); contactName = ""; keyDraft = ""; contactWalletDraft = ""
        } catch { self.error = error.localizedDescription }
    }
    func deleteContact(_ contact: PublicContact) { do { try persistContacts(contacts.filter { $0.key != contact.key }) } catch { self.error = error.localizedDescription } }
    private func persistContacts(_ value: [PublicContact]) throws { defaults.set(try JSONEncoder().encode(value),forKey:"publicContacts"); contacts = value }
    func clearSession() {
        cancel(); clearInboxView(); removalRetry?.cancel(); engine?.close(); engine = nil; portal?.close(); wallet = nil
        message = ""; ciphertext = ""; output = ""; layerNote = ""; peer = "self"; peerName = "Myself"; keyDraft = ""; peerWalletIdentity = nil; clearSearch(); recipientQuery = ""; legacySenderSelected = false; screen = .home
        WKWebsiteDataStore.default().removeData(ofTypes:WKWebsiteDataStore.allWebsiteDataTypes(),modifiedSince:.distantPast) { [weak self] in Task { @MainActor in self?.configureWallet() } }
    }
    func done() { message = ""; ciphertext = ""; output = ""; layerNote = ""; clearSearch(); recipientQuery = ""; legacySenderSelected = false; screen = .home }
    func openInner() { let inner = output; importMessage(inner) }
    func finishGuide() { defaults.set(true,forKey:"guideSeen"); screen = .home }
    func newDelivery() {
        do {
            guard outputKind == "encrypted", Wire.isEnvelope(output) else { throw CryptonError("Create a v2 message before using MessageBox.") }
            let saved = defaults.dictionary(forKey:"deliveryKeys") as? [String:String] ?? [:]
            let draft = recipientWalletDraft.trimmingCharacters(in:.whitespacesAndNewlines)
            let entered = draft.isEmpty ? nil : try Wire.identity(draft)
            let recipient = peer == "self" ? "self" : entered ?? peerWalletIdentity ?? saved[peer] ?? peer
            deliveryID = try store.create(envelope:output,key:peer,recipient:recipient,name:peerName,disappear:disappearSend)
            deliveryRecipient = recipient == "self" ? "" : recipient; screen = .delivery
        } catch { self.error = error.localizedDescription }
    }
    func showDelivery(_ id: String) { deliveryID = id; if let r = try? store.get(id) { deliveryRecipient = r["recipient"] as? String == "self" ? "" : r["recipient"] as? String ?? "" }; screen = .delivery }
    func deliver(_ action: String) {
        perform { [self] in
            let record = try store.get(deliveryID)
            if action == "retryRefused" { try store.retryRefusedPayment(deliveryID); status = "Payment was declined · ready for a fresh quote"; return }
            if action == "cleanup" { try store.cleanup(deliveryID); wipeSentMessage(); return }
            if ["prepare","send"].contains(action) {
                let key = deliveryRecipient.trimmingCharacters(in:.whitespacesAndNewlines)
                let recipient = key.isEmpty && record["encryptionKey"] as? String == "self" ? "self" : try Wire.identity(key)
                if action == "prepare" {
                    try store.recipient(deliveryID,recipient)
                    if let receiving = record["encryptionKey"] as? String, receiving != "self", recipient != "self" {
                        var saved = defaults.dictionary(forKey:"deliveryKeys") as? [String:String] ?? [:]
                        saved[receiving] = recipient; defaults.set(saved,forKey:"deliveryKeys")
                    }
                }
                else if record["recipient"] as? String != recipient { throw CryptonError("Recipient changed. Refresh the fee before sending.") }
            }
            do { _ = try await crypto().deliver(action,id:deliveryID) }
            catch {
                if record["disappear"] as? Bool == true, let marker = try? store.get(deliveryID), DeliveryStore.discarded(marker) { wipeSentMessage() }
                throw error
            }
            if record["disappear"] as? Bool == true, !FileManager.default.fileExists(atPath:store.directory.appendingPathComponent(deliveryID+".json").path) {
                wipeSentMessage(); return
            }
            if let current = try? store.get(deliveryID), action == "recover", let history = current["walletHistory"] as? JSON {
                status = integer(history["totalActions"]) == 0 ? "No payment found · review recovery options" : "Payment history checked"
            } else { status = action == "prepare" ? "Delivery fee ready · review payment in ME" : "MessageBox delivery complete" }
        }
    }
    func active(_ active: Bool) {
        foreground = active
        sound.active = active
        if active {
            captureActive = UIScreen.main.isCaptured
            (wallet as? MEWallet)?.resumed()
            if privateInboxView { privateViewed = true }
            if !busy { importPendingShare() }; scheduleRemovalRetry(1)
        } else {
            removalRetry?.cancel()
            if privateInboxView && privateViewed { closeInboxMessage() }
        }
    }
    func copyText(_ value:String) {
        UIPasteboard.general.setItems([["public.utf8-plain-text":value,"com.projectbabbage.Crypton.ownedClipboard":Data([1])]],options:[.localOnly:true,.expirationDate:Date().addingTimeInterval(120)])
    }
    private func clearOwnedClipboard() {
        if UIPasteboard.general.contains(pasteboardTypes:["com.projectbabbage.Crypton.ownedClipboard"]) { UIPasteboard.general.items = [] }
    }
    private func wipeSentMessage() {
        message = ""; ciphertext = ""; output = ""; layerNote = ""; peer = "self"; peerName = "Myself"; peerWalletIdentity = nil; keyDraft = ""; clearSearch(); recipientQuery = ""; clearOwnedClipboard()
        deliveryID = ""; deliveryRecipient = ""; screen = .outbox; status = "Sent · local message copies removed"
        engine?.close(); engine = nil
    }
    func loadInbox() {
        guard !inboxWallet.isEmpty else { inboxRows = []; return }
        do { inboxRows = try inboxStore.list(inboxWallet,dismissed:showDismissed) }
        catch { inboxNotice = "Saved inbox could not be read: " + error.localizedDescription }
    }
    func showInbox() { clearInboxView(); screen = .inbox; loadInbox(); scheduleRemovalRetry(1) }
    func showInboxMessage(_ id:String) { clearInboxView(); inboxID = id; screen = .inboxMessage }
    private func clearInboxView() { inboxContent = nil; privateInboxView = false; privateViewed = false; privateRemoved = false }
    func closeInboxMessage() { clearInboxView(); inboxID = ""; screen = .inbox; loadInbox(); scheduleRemovalRetry(1) }
    func flagInbox(_ dismissed:Bool) {
        do { try inboxStore.flag(inboxWallet,inboxID,"dismissed",dismissed); closeInboxMessage() } catch { self.error = error.localizedDescription }
    }
    func receive(_ requested:String,more:Bool = false,automatic:Bool = false) {
        guard !busy else { return }
        if !automatic { removalNeedsWallet = false }
        let action = requested == "open" && disappearReceive ? "openDiscard" : requested
        let expected = action == "refresh" && !more ? "" : inboxWallet, id = inboxID
        let offset = more ? inboxOffset : 0, layer = action == "layer" ? inboxContent?["envelope"] as? String ?? "" : ""
        let previouslyRemoved = privateRemoved
        perform { [self] in
            do {
                guard !(wallet is PortalWallet) else { throw CryptonError("The MessageBox inbox requires Metanet Explorer or a BRC-100 wallet.") }
                let result = try await crypto().inbox(action,wallet:expected,id:id,offset:offset,layer:layer)
                inboxWallet = try Wire.identity(result["wallet"] as? String ?? "")
                if ["open","openDiscard","layer"].contains(action) || (action == "verify" && result["content"] is JSON) {
                    guard let content = result["content"] as? JSON else { throw CryptonError("Invalid decrypted inbox message.") }
                    inboxContent = content; inboxID = id; screen = .inboxMessage
                    if ["open","verify"].contains(action) { try inboxStore.flag(inboxWallet,id,"read",true) }
                    else {
                        privateInboxView = true; privateViewed = foreground
                        privateRemoved = action == "layer" ? previouslyRemoved : result["removed"] as? Bool == true
                        if action == "openDiscard" {
                            clearOwnedClipboard()
                            let detail = result["removalError"] as? String ?? ""
                            inboxNotice = privateRemoved ? "Server removal confirmed" : "Server removal pending. " + detail
                            removalNeedsWallet = Self.needsWallet(detail)
                        }
                    }
                } else if action == "remove" {
                    inboxNotice = "Server removal confirmed · no saved message copy"
                    if privateInboxView { privateRemoved = true } else { inboxID = ""; screen = .inbox }
                } else {
                    inboxMore = result["hasMore"] as? Bool == true; inboxOffset = integer(result["nextOffset"]) ?? 0
                    inboxNotice = "Retrieved \(integer(result["count"]) ?? 0) Crypton message(s). \(integer(result["skipped"]) ?? 0) other or unreadable notification(s) left untouched."
                    clearInboxView(); screen = .inbox
                }
                if action == "verify", result["content"] is JSON { status = "Message decrypted · copy retained" }
                else if ["refresh","find","verify"].contains(action) { status = "Inbox up to date" }
                else if action == "open" || action == "layer" { status = privateInboxView ? "Private message opened" : "Message decrypted · copy retained" }
                else { status = privateRemoved || action == "remove" ? "Message removed" : "Server removal pending" }
                loadInbox(); scheduleRemovalRetry(30)
            } catch {
                if ["remove","openDiscard"].contains(action) {
                    inboxNotice = "Server removal pending. " + error.localizedDescription; status = "Server removal pending"; loadInbox()
                    removalNeedsWallet = Self.needsWallet(error.localizedDescription); scheduleRemovalRetry(60)
                }
                if !automatic { throw error }
            }
        }
    }
    private static func needsWallet(_ error:String) -> Bool { ["wallet","permission","declined","profile","denied","cancel"].contains { error.localizedCaseInsensitiveContains($0) } }
    func scheduleRemovalRetry(_ seconds:UInt64) {
        removalRetry?.cancel()
        guard foreground, !removalNeedsWallet, !inboxWallet.isEmpty else { return }
        removalRetry = Task { [weak self] in
            do { try await Task.sleep(nanoseconds:seconds * 1_000_000_000) } catch { return }
            guard let self = self, self.foreground, !self.privateInboxView else { return }
            if self.busy { self.scheduleRemovalRetry(30); return }
            do {
                if let id = try self.inboxStore.nextPending(self.inboxWallet) { self.inboxID = id; self.receive("remove",automatic:true) }
            } catch { self.inboxNotice = error.localizedDescription }
        }
    }
    func importPendingShare() {
        guard !busy, let shares = try? IncomingShareStore(), let files = try? shares.pending(), let url = files.first else { return }
        if importURL(url) { do { try shares.remove(url) } catch { self.error = error.localizedDescription } }
    }
}

@MainActor final class SoundPlayer {
    var enabled = false { didSet { update() } }
    var active = false { didSet { update() } }
    private var music: AVAudioPlayer?
    private var effectPlayer: AVAudioPlayer?
    private var interrupted = false
    private var interruptionObserver:NSObjectProtocol?
    init() {
        interruptionObserver = NotificationCenter.default.addObserver(forName:AVAudioSession.interruptionNotification,object:nil,queue:.main) { [weak self] notification in
            Task { @MainActor [weak self] in self?.handleInterruption(notification) }
        }
    }
    private func handleInterruption(_ notification:Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue:raw) else { return }
        if type == .began { interrupted = true; update() }
        else {
            interrupted = false
            let options = AVAudioSession.InterruptionOptions(rawValue:notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            if options.contains(.shouldResume) { update() }
        }
    }
    #if DEBUG
    var playbackState:(music:Bool,effect:Bool,allocated:Bool) { (music?.isPlaying == true,effectPlayer?.isPlaying == true,music != nil || effectPlayer != nil) }
    #endif
    private func update() {
        if enabled && active && !interrupted {
            if music == nil, let data = NSDataAsset(name:"PhantomFromSpace")?.data {
                try? AVAudioSession.sharedInstance().setCategory(.ambient,options:.mixWithOthers)
                try? AVAudioSession.sharedInstance().setActive(true)
                music = try? AVAudioPlayer(data:data); music?.numberOfLoops = -1; music?.volume = 0.12
            }
            music?.play()
        } else {
            music?.volume = 0; music?.stop(); music = nil
            effectPlayer?.stop(); effectPlayer = nil
            try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
        }
    }
    func effect(encrypt: Bool) {
        guard enabled && active && !interrupted, let data = NSDataAsset(name:encrypt ? "encryptSound" : "decryptSound")?.data else { return }
        effectPlayer = try? AVAudioPlayer(data:data); effectPlayer?.volume = 0.35; effectPlayer?.play()
    }
    func stopEffect() { effectPlayer?.stop() }
    deinit { if let observer = interruptionObserver { NotificationCenter.default.removeObserver(observer) }; music?.stop(); effectPlayer?.stop() }
}
