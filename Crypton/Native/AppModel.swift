import SwiftUI
import WebKit
import AVFoundation

struct PublicContact: Codable, Identifiable, Equatable {
    var name: String
    var key: String
    var walletIdentity: String? = nil
    var id: String { key }
}
enum Screen { case home, recipient, compose, result, contacts, settings, guide, outbox, delivery }

@MainActor final class AppModel: ObservableObject {
    @Published var screen: Screen = .home
    @Published var busy = false
    @Published var error: String?
    @Published var status = "Connect your wallet"
    @Published var portalVisible = false
    @Published var decrypting = false
    @Published var message = ""
    @Published var ciphertext = ""
    @Published var peer = "self"
    @Published var peerName = "Myself"
    @Published var keyDraft = ""
    @Published var contactName = ""
    @Published var recipientQuery = "" { didSet { if recipientQuery != oldValue { clearSearch() } } }
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
    @Published var legacy: Bool { didSet { defaults.set(legacy,forKey:"legacyMessages") } }
    @Published var walletMode: String
    @Published var endpoint: String
    @Published var soundEnabled: Bool { didSet { defaults.set(soundEnabled,forKey:"soundEnabled"); sound.enabled = soundEnabled } }
    let store: DeliveryStore
    let sound = SoundPlayer()
    private let defaults: UserDefaults
    private(set) var wallet: WalletConnection?
    private var engine: CryptoEngine?
    private var task: Task<Void,Never>?
    var portal: PortalWallet? { wallet as? PortalWallet }
    init(defaults: UserDefaults = .standard, store: DeliveryStore? = nil, wallet: WalletConnection? = nil) {
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
        walletMode = defaults.string(forKey:"walletMode") ?? "me"
        legacy = defaults.object(forKey:"legacyMessages") as? Bool ?? (defaults.string(forKey:"walletMode") == "portal")
        endpoint = defaults.string(forKey:"walletEndpoint") ?? ""
        soundEnabled = defaults.object(forKey:"soundEnabled") as? Bool ?? true
        if let data = defaults.data(forKey:"publicContacts"), let saved = try? JSONDecoder().decode([PublicContact].self,from:data) { contacts = saved }
        sound.enabled = soundEnabled
        configureWallet()
        if let wallet = wallet { self.wallet = wallet }
        if !defaults.bool(forKey:"guideSeen") && !ProcessInfo.processInfo.arguments.contains("--uitesting") { screen = .guide }
    }
    private func configureWallet() {
        clearSearch()
        engine?.close(); engine = nil; portal?.close(); wallet?.cancel(); wallet = nil
        status = "Connect your wallet"; portalVisible = false
        if walletMode == "me" {
            let me = MEWallet()
            me.waiting = { [weak self] waiting in if waiting { self?.status = "Approve in ME, then return to Crypton" } }
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
    private func crypto() throws -> CryptoEngine {
        if let engine = engine { return engine }
        let engine = CryptoEngine(wallet:try connection(),store:store); self.engine = engine; return engine
    }
    func perform(_ work: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true; error = nil
        task = Task { [weak self] in
            guard let self = self else { return }
            defer { self.busy = false; self.task = nil; self.sound.stopEffect() }
            do { try await work() } catch { self.error = error.localizedDescription; self.status = "Wallet request needs attention" }
        }
    }
    func cancel() { engine?.cancel(); wallet?.cancel(); task?.cancel(); portalVisible = false }
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
    func choose(_ key: String, name: String = "Selected identity") {
        do {
            let key = key == "self" ? key : try Wire.identity(key)
            peer = key; peerName = name; peerWalletIdentity = nil; selectedIdentity = nil; recipientSaved = false; screen = .compose
        }
        catch { self.error = error.localizedDescription }
    }
    private func clearSearch() { searchResults = []; searchCompleted = false; selectedIdentity = nil; recipientSaved = false }
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
        peerWalletIdentity = identity.key; selectedIdentity = identity; legacySenderSelected = true
    }
    func chooseContact(_ contact:PublicContact) {
        do {
            let key = try Wire.identity(contact.key)
            let walletKey = try contact.walletIdentity.map { try Wire.identity($0) }
            choose(key,name:contact.name)
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
    func process() {
        // Raw ciphertext always requires an explicit sender selection, including imported files.
        if decrypting && !Wire.isEnvelope(ciphertext) && !legacySenderSelected { screen = .recipient; return }
        perform { [self] in
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
            screen = .result
            if decrypting || legacy || peer == "self" { status = "Wallet connected" }
        }
    }
    @Published var legacySenderSelected = false
    func identity(root: Bool = false) {
        perform { [self] in
            let result = (legacy || root) ? try await connection().call("getPublicKey",["identityKey":true],raw:false) : try await crypto().run("identity")
            output = try Wire.identity(result as? String ?? ""); outputKind = root ? "walletIdentity" : "identity"; screen = .result; status = "Wallet connected"
        }
    }
    @discardableResult func importMessage(_ value: String) -> Bool {
        do {
            guard value.utf8.count <= 100_000 else { throw CryptonError("Payload too large.") }
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
    func saveContact() {
        do {
            let name = contactName.trimmingCharacters(in:.whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 120 else { throw CryptonError("Enter a contact name of at most 120 characters.") }
            let key = try Wire.identity(keyDraft)
            var updated = contacts.filter { $0.key != key }; updated.append(PublicContact(name:name,key:key)); updated.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            try persistContacts(updated); contactName = ""; keyDraft = ""
        } catch { self.error = error.localizedDescription }
    }
    func deleteContact(_ contact: PublicContact) { do { try persistContacts(contacts.filter { $0.key != contact.key }) } catch { self.error = error.localizedDescription } }
    private func persistContacts(_ value: [PublicContact]) throws { defaults.set(try JSONEncoder().encode(value),forKey:"publicContacts"); contacts = value }
    func clearSession() {
        cancel(); engine?.close(); engine = nil; portal?.close(); wallet = nil
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
            let recipient = peer == "self" ? "self" : peerWalletIdentity ?? saved[peer] ?? peer
            deliveryID = try store.create(envelope:output,key:peer,recipient:recipient,name:peerName)
            deliveryRecipient = recipient == "self" ? "" : recipient; screen = .delivery
        } catch { self.error = error.localizedDescription }
    }
    func showDelivery(_ id: String) { deliveryID = id; if let r = try? store.get(id) { deliveryRecipient = r["recipient"] as? String == "self" ? "" : r["recipient"] as? String ?? "" }; screen = .delivery }
    func deliver(_ action: String) {
        perform { [self] in
            let record = try store.get(deliveryID)
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
            _ = try await crypto().deliver(action,id:deliveryID)
            status = "Wallet connected"
        }
    }
    func active(_ active: Bool) {
        sound.active = active
        if active { (wallet as? MEWallet)?.resumed(); if !busy { importPendingShare() } }
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
