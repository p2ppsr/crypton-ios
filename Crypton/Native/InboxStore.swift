import Foundation
import CryptoKit

/// Encrypted copies partitioned by receiving wallet. A pending removal contains no message body.
@MainActor final class InboxStore {
    let directory: URL
    let host: String
    let agent: String
    init(delivery:DeliveryStore,directory:URL? = nil) {
        host = delivery.serviceHost; agent = delivery.serviceAgent
        self.directory = directory ?? delivery.directory.deletingLastPathComponent().appendingPathComponent("Inboxes")
    }
    static func messageID(_ value:String) throws -> String {
        guard value.range(of:"^[A-Za-z0-9_-]{1,160}$",options:.regularExpression) != nil else { throw CryptonError("Invalid inbox message ID.") }; return value
    }
    static func pending(_ value:JSON) -> Bool { value["state"] as? String == "REMOVAL_PENDING" }
    private func folder(_ wallet:String) throws -> URL { directory.appendingPathComponent(try Wire.identity(wallet)) }
    private func file(_ wallet:String,_ id:String) throws -> URL {
        let hash = SHA256.hash(data:Data(try Self.messageID(id).utf8)).map { String(format:"%02x",$0) }.joined()
        return try folder(wallet).appendingPathComponent(hash + ".json")
    }
    private func validate(_ wallet:String,_ r:JSON) throws {
        guard integer(r["version"]) == 1, r["wallet"] as? String == wallet, r["host"] as? String == host, let id = r["messageId"] as? String else { throw CryptonError("Invalid saved inbox record.") }
        _ = try Self.messageID(id)
        if Self.pending(r) {
            guard Set(r.keys) == Set(["version","wallet","host","messageId","state"]) else { throw CryptonError("Invalid pending removal record.") }
        } else {
            _ = try Wire.identity(r["sender"] as? String ?? ""); _ = try Wire.envelope(r["envelope"] as? String ?? "")
        }
    }
    func get(_ wallet:String,_ id:String) throws -> JSON {
        let url = try file(wallet,id)
        guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) <= 100_000 else { throw CryptonError("Saved inbox record is too large.") }
        let r = try object(Data(contentsOf:url)); try validate(wallet,r)
        guard r["messageId"] as? String == id else { throw CryptonError("Saved inbox message changed.") }; return r
    }
    func list(_ wallet:String,dismissed:Bool = false) throws -> [JSON] {
        let folder = try folder(wallet)
        guard FileManager.default.fileExists(atPath:folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).filter { $0.pathExtension == "json" }.map { url in
            guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) <= 100_000 else { throw CryptonError("Saved inbox record is too large.") }
            let r = try object(Data(contentsOf:url)); try validate(wallet,r); return r
        }.filter { dismissed || $0["dismissed"] as? Bool != true }.sorted { ($0["receivedAt"] as? Double ?? 0) > ($1["receivedAt"] as? Double ?? 0) }
    }
    private func write(_ wallet:String,_ r:JSON) throws {
        try validate(wallet,r)
        let folder = try folder(wallet); try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var protected = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true; try protected.setResourceValues(values)
        try jsonData(r).write(to:file(wallet,r["messageId"] as! String),options:[.atomic,.completeFileProtection])
    }
    func merge(_ wallet:String,_ messages:[JSON]) throws {
        _ = try Wire.identity(wallet)
        guard messages.count <= 25 else { throw CryptonError("Inbox page is too large.") }
        var existing = try list(wallet,dismissed:true)
        for m in messages {
            let id = try Self.messageID(m["messageId"] as? String ?? ""), sender = try Wire.identity(m["sender"] as? String ?? ""), envelope = m["envelope"] as? String ?? ""
            _ = try Wire.envelope(envelope)
            if let old = existing.first(where:{$0["messageId"] as? String == id}) {
                if Self.pending(old) { continue }
                guard old["sender"] as? String == sender, old["envelope"] as? String == envelope else { throw CryptonError("A saved inbox message changed. Its original encrypted copy was kept.") }; continue
            }
            guard existing.count < 1000 else { throw CryptonError("This wallet's inbox has reached its 1,000 message limit.") }
            let r:JSON = ["version":1,"wallet":wallet,"host":host,"messageId":id,"sender":sender,"envelope":envelope,"receivedAt":Date().timeIntervalSince1970,"read":false,"dismissed":false]
            try write(wallet,r); existing.append(r)
        }
    }
    func decrypted(_ wallet:String,_ id:String) throws {
        if Self.pending(try get(wallet,id)) { return }
        try write(wallet,["version":1,"wallet":wallet,"host":host,"messageId":id,"state":"REMOVAL_PENDING"])
    }
    func removed(_ wallet:String,_ id:String) throws {
        guard Self.pending(try get(wallet,id)) else { throw CryptonError("Only a decrypted message may be removed.") }
        try FileManager.default.removeItem(at:file(wallet,id))
    }
    func nextPending(_ wallet:String) throws -> String? { try list(wallet,dismissed:true).first(where:Self.pending)?["messageId"] as? String }
    func flag(_ wallet:String,_ id:String,_ field:String,_ value:Bool) throws {
        guard ["read","dismissed"].contains(field) else { throw CryptonError("Invalid inbox flag.") }
        var r = try get(wallet,id); guard !Self.pending(r) else { throw CryptonError("Server removal is pending.") }
        r[field] = value; try write(wallet,r)
    }
}

/// Session capabilities exclude spending, fund imports and unrelated acknowledgements.
@MainActor final class InboxSession {
    let store:InboxStore
    let action:String
    let expectedWallet:String
    let messageID:String
    let offset:Int
    let envelope:String
    private(set) var wallet = ""
    private var decrypted = false, verificationRequested = false
    init(store:InboxStore,action:String,wallet:String,id:String,offset:Int,layer:String) throws {
        guard ["refresh","open","openDiscard","remove","layer"].contains(action), (0...1_000_000).contains(offset) else { throw CryptonError("Invalid inbox operation.") }
        self.store = store; self.action = action; self.offset = offset
        expectedWallet = wallet.isEmpty ? "" : try Wire.identity(wallet)
        messageID = ["refresh","layer"].contains(action) ? "" : try InboxStore.messageID(id)
        if action != "refresh", wallet.isEmpty { throw CryptonError("Select the receiving wallet first.") }
        if ["open","openDiscard"].contains(action) {
            let r = try store.get(wallet,id); guard !InboxStore.pending(r) else { throw CryptonError("Server removal is pending; the message copy is gone.") }
            envelope = r["envelope"] as! String
        } else { envelope = action == "layer" ? layer : "" }
        if action == "layer" { _ = try Wire.envelope(layer) }
        if action == "remove", !InboxStore.pending(try store.get(wallet,id)) { throw CryptonError("Only a decrypted message may be removed.") }
    }
    func beforeWallet(_ method:String,_ args:JSON) throws {
        if method == "getPublicKey", sameJSON(args,["identityKey":true]) { return }
        guard !wallet.isEmpty else { throw CryptonError("Connect a wallet before reading messages.") }
        if method == "getNetwork", args.isEmpty { return }
        let proto = args["protocolID"], peer = args["counterparty"] as? String ?? "self"
        let allowed:Bool
        switch method {
        case "createHmac","verifyHmac": allowed = sameJSON(proto,[2,"server hmac"]) && peer == "self"
        case "createSignature","verifySignature": allowed = sameJSON(proto,[2,"auth message signature"]) && peer == store.agent
        case "decrypt": allowed = action == "refresh" && sameJSON(proto,[1,"messagebox"]) && args["keyID"] as? String == "1" && (try? Wire.identity(peer)) != nil
        default: allowed = false
        }
        guard allowed else { throw CryptonError("This inbox operation cannot use that wallet feature or make a payment.") }
    }
    func returned(_ method:String,_ args:JSON,_ value:Any) throws {
        if method == "getPublicKey", sameJSON(args,["identityKey":true]) {
            let current = try Wire.identity((value as? JSON)?["publicKey"] as? String ?? "")
            guard (expectedWallet.isEmpty || current == expectedWallet), (wallet.isEmpty || wallet == current) else { throw CryptonError("The wallet profile changed. Switch back to this inbox's wallet and retry.") }; wallet = current
        }
    }
    func beforeCrypto(_ method:String,_ args:JSON) throws {
        guard ["open","openDiscard","layer"].contains(action), !wallet.isEmpty else { throw CryptonError("Unexpected inbox decryption request.") }
        if method == "decrypt" {
            let e = try Wire.envelope(envelope)
            guard sameJSON(args["ciphertext"],e["ciphertext"]), sameJSON(args["counterparty"],e["sender"]) else { throw CryptonError("Inbox decryption changed its envelope.") }
        }
    }
    func beforeHTTP(_ url:URL,_ method:String,_ body:String) throws {
        let base = URL(string:store.host)!
        guard !wallet.isEmpty, url.scheme == base.scheme, url.host == base.host, url.port == base.port, url.user == nil, url.password == nil, url.fragment == nil, url.query == nil, method == "POST" else { throw CryptonError("Inbox request left its trusted host.") }
        if ["refresh","openDiscard","remove"].contains(action), url.path == "/.well-known/auth" { return }
        let request = try object(Data(body.utf8))
        if ["openDiscard","remove"].contains(action), InboxStore.pending(try store.get(wallet,messageID)) {
            if url.path == "/acknowledgeMessage", sameJSON(request,["messageIds":[messageID]]) { return }
            if url.path == "/listMessages", sameJSON(request,["messageBox":"notifications","offset":0,"limit":25,"messageId":messageID]) { verificationRequested = true; return }
        }
        if action == "refresh", url.path == "/listMessages", sameJSON(request,["messageBox":"notifications","offset":offset,"limit":25]) { return }
        throw CryptonError("This inbox operation cannot use that endpoint or accept payments.")
    }
    func checkpoint(_ kind:String,_ value:JSON) throws {
        guard !wallet.isEmpty, value["wallet"] as? String == wallet else { throw CryptonError("Invalid inbox checkpoint.") }
        if kind == "page", action == "refresh", let rows = value["messages"] as? [JSON] { try store.merge(wallet,rows); return }
        guard value["messageId"] as? String == messageID else { throw CryptonError("Inbox message changed.") }
        if kind == "decrypted", action == "openDiscard", !decrypted { try store.decrypted(wallet,messageID); decrypted = true; return }
        if kind == "removed", ["openDiscard","remove"].contains(action), verificationRequested { try store.removed(wallet,messageID); return }
        throw CryptonError("Invalid inbox checkpoint.")
    }
}
