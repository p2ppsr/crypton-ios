import Foundation

/// Durable encrypted outbox. A payment write-ahead record is never reset by cancellation or retry.
@MainActor final class DeliveryStore {
    nonisolated static let host = "https://messagebox.babbage.systems"
    nonisolated static let agent = "028155878063d691f01cfc0eeb626404ebe9303ec50f9542c234c5c85100a98ca1"
    let serviceHost: String
    let serviceAgent: String
    let directory: URL
    init(directory: URL? = nil) {
        serviceHost = Self.host; serviceAgent = Self.agent
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Deliveries")
    }
    #if DEBUG
    /// Compiled out of Release. Fixtures are restricted to an explicitly selected device loopback port.
    init(directory:URL,fixtureHost:String,fixtureAgent:String) throws {
        let url = try Wire.endpoint(fixtureHost,debugLoopback:true)
        guard url.scheme == "http", ["localhost","127.0.0.1"].contains(url.host ?? ""), url.port != nil, url.path.isEmpty else { throw CryptonError("MessageBox fixtures must use a loopback port.") }
        serviceHost = url.absoluteString; serviceAgent = try Wire.identity(fixtureAgent); self.directory = directory
    }
    #endif
    func feeTotal(_ quote:JSON) throws -> Int { try Self.total(quote,expectedAgent:serviceAgent) }
    private func file(_ id: String) throws -> URL {
        guard UUID(uuidString: id) != nil else { throw CryptonError("Invalid delivery record.") }
        return directory.appendingPathComponent(id + ".json")
    }
    func get(_ id: String) throws -> JSON {
        let url = try file(id)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 8_000_000 else { throw CryptonError("Delivery record too large.") }
        let r = try object(Data(contentsOf: url))
        guard r["id"] as? String == id, integer(r["version"]) == 1, r["host"] as? String == serviceHost, r["agent"] as? String == serviceAgent, r["inbox"] as? String == "notifications", let envelope = r["envelope"] as? String else { throw CryptonError("Invalid delivery record.") }
        _ = try Wire.envelope(envelope); return r
    }
    func list() throws -> [JSON] {
        if !FileManager.default.fileExists(atPath: directory.path) { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.map { try get($0.deletingPathExtension().lastPathComponent) }.sorted { ($0["created"] as? Double ?? 0) > ($1["created"] as? Double ?? 0) }
    }
    private func write(_ record: JSON) throws {
        let bytes = try jsonData(record)
        guard bytes.count <= 8_000_000, let id = record["id"] as? String else { throw CryptonError("Delivery record too large or incomplete.") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true; try folder.setResourceValues(values)
        try bytes.write(to: file(id), options: [.atomic, .completeFileProtection])
    }
    func create(envelope: String, key: String, recipient: String, name: String) throws -> String {
        _ = try Wire.envelope(envelope)
        let key = key == "self" ? key : try Wire.identity(key), to = recipient == "self" ? recipient : try Wire.identity(recipient)
        let id = UUID().uuidString.lowercased()
        try write(["version":1,"id":id,"created":Date().timeIntervalSince1970 * 1000,"state":"DRAFT","host":serviceHost,"agent":serviceAgent,"inbox":"notifications","envelope":envelope,"encryptionKey":key,"recipient":to,"name":String(name.prefix(120))])
        return id
    }
    private func require(_ record: JSON, _ states: String...) throws {
        guard states.contains(record["state"] as? String ?? "") else { throw CryptonError("A second payment is blocked. Use this delivery’s saved payment or recovery action.") }
    }
    static func total(_ quote: JSON, expectedAgent:String = agent) throws -> Int {
        guard let a = integer(quote["deliveryFee"]), let b = integer(quote["recipientFee"]), a >= 0, b >= 0, a <= Int32.max, b <= Int32.max, a + b <= Int32.max, quote["deliveryAgentIdentityKey"] as? String == expectedAgent else { throw CryptonError("Invalid MessageBox fee or server identity.") }
        return a + b
    }
    func recipient(_ id: String, _ value: String) throws {
        var r = try get(id); try require(r,"DRAFT","QUOTED")
        let to = value == "self" ? value : try Wire.identity(value)
        if to != r["recipient"] as? String { r["recipient"] = to; r["state"] = "DRAFT"; r.removeValue(forKey: "prepared"); r.removeValue(forKey: "error"); try write(r) }
    }
    func begin(_ id: String, action: String) throws {
        let r = try get(id)
        switch action {
        case "prepare": try require(r,"DRAFT","QUOTED")
        case "send": try require(r,"QUOTED")
        case "recover": try require(r,"PAYMENT_REQUESTED")
        case "resume": try require(r,"PAYMENT_RETURNED","PAID","SUBMITTING")
        default: throw CryptonError("Invalid delivery operation.")
        }
    }
    func beforeWallet(_ id: String, action: String, method: String, args: JSON) throws {
        let r = try get(id), p = r["prepared"] as? JSON
        if method == "createAction" {
            guard action == "send", let p = p, let q = p["quote"] as? JSON else { throw CryptonError("New payments are blocked during recovery.") }
            try require(r,"QUOTED")
            let now = Date().timeIntervalSince1970 * 1000, at = p["quotedAt"] as? Double ?? 0
            guard try feeTotal(q) > 0, now >= at, now - at <= 300_000, sameJSON(args, p["action"]) else { throw CryptonError("Payment differs from the reviewed quote, or the quote expired.") }
            try validateAction(p, args, id)
            var updated = r; updated["state"] = "PAYMENT_REQUESTED"; updated["paymentRequestedAt"] = now
            try write(updated); return
        }
        if method == "listActions" {
            let expected: JSON = ["labels":["crypton-delivery-" + id],"labelQueryMode":"all","includeOutputs":true,"includeOutputLockingScripts":true,"includeLabels":true,"limit":10]
            guard action == "recover", sameJSON(args,expected) else { throw CryptonError("Wallet history request is outside this delivery.") }; return
        }
        if method == "getPublicKey", args["identityKey"] as? Bool == true { return }
        guard let proto = args["protocolID"] as? [Any], proto.count == 2, let level = integer(proto[0]), let name = proto[1] as? String else { throw CryptonError("Missing delivery wallet protocol.") }
        let peer = args["counterparty"] as? String ?? "self", recipient = p?["recipient"] as? String ?? r["recipient"] as? String ?? ""
        let recipientOK = peer == recipient || (recipient == "self" && (try? Wire.identity(peer)) != nil)
        let allowed: Bool
        switch method {
        case "createHmac", "verifyHmac": allowed = (level == 2 && name == "server hmac" && peer == "self") || (level == 1 && name == "messagebox" && (peer == "self" || recipientOK))
        case "createSignature", "verifySignature": allowed = level == 2 && name == "auth message signature" && peer == serviceAgent
        case "encrypt": allowed = level == 1 && name == "messagebox" && recipientOK
        case "getPublicKey": allowed = level == 2 && name == "3241645161d8" && peer == serviceAgent
        default: allowed = false
        }
        guard allowed else { throw CryptonError("Unsupported delivery wallet feature or counterparty.") }
    }
    private func validateAction(_ p: JSON, _ action: JSON, _ id: String) throws {
        guard action.count == 4, action["description"] as? String == "MessageBox delivery payment",
              sameJSON(action["options"],["randomizeOutputs":false,"acceptDelayedBroadcast":false]), sameJSON(action["labels"],["crypton-delivery-" + id]),
              let outputs = action["outputs"] as? [JSON], let quote = p["quote"] as? JSON else { throw CryptonError("Unexpected payment request.") }
        _ = try feeTotal(quote)
        var index = 0
        for field in ["deliveryFee","recipientFee"] {
            let amount = integer(quote[field])!; if amount == 0 { continue }
            guard index < outputs.count else { throw CryptonError("Missing payment destination.") }
            let o = outputs[index]; index += 1
            let key = field == "deliveryFee" ? serviceAgent : p["recipient"] as? String ?? ""
            let description = field == "deliveryFee" ? "MessageBox server delivery fee" : "Recipient message fee"
            guard o.count == 4, integer(o["satoshis"]) == amount, o["outputDescription"] as? String == description,
                  let instructions = o["customInstructions"] as? String, let parsed = try? object(Data(instructions.utf8)), parsed.count == 3, parsed["recipientIdentityKey"] as? String == key,
                  let script = o["lockingScript"] as? String, script.range(of: "^76a914[0-9a-f]{40}88ac$", options: .regularExpression) != nil else { throw CryptonError("Unexpected payment destination or amount.") }
        }
        guard index == outputs.count else { throw CryptonError("Unexpected payment outputs.") }
    }
    func walletReturned(_ id: String, result: JSON) throws {
        var r = try get(id); try require(r,"PAYMENT_REQUESTED")
        r["walletResult"] = result; r["state"] = "PAYMENT_RETURNED"; try write(r)
    }
    func recoveryTransaction(_ id:String) throws -> String {
        let r = try get(id); try require(r,"PAYMENT_REQUESTED")
        guard let history = r["walletHistory"] as? JSON, integer(history["totalActions"]) == 1,
              let transactions = history["transactions"] as? [JSON], transactions.count == 1,
              let txid = transactions[0]["txid"] as? String, txid.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil,
              ["completed","unproven"].contains(transactions[0]["status"] as? String ?? "") else { throw CryptonError("No unique completed payment to recover.") }
        return txid
    }
    func checkpoint(_ id: String, action: String, kind: String, value: JSON) throws {
        var r = try get(id)
        switch kind {
        case "prepared":
            try require(r,"DRAFT","QUOTED")
            guard action == "prepare", let recipient = value["recipient"] as? String, let sender = value["sender"] as? String,
                  let q = value["quote"] as? JSON, let messageID = value["messageId"] as? String, messageID.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
                  let body = value["body"] as? String, body.utf8.count <= 180_000, let parsed = try? object(Data(body.utf8)), parsed.count == 1, parsed["encryptedMessage"] is String,
                  r["recipient"] as? String == "self" || r["recipient"] as? String == recipient else { throw CryptonError("Delivery preparation changed its recipient or payload.") }
            _ = try Wire.identity(recipient); _ = try Wire.identity(sender); _ = try feeTotal(q)
            guard let payment = value["action"] as? JSON else { throw CryptonError("Missing payment plan.") }; try validateAction(value,payment,id)
            var prepared = value; prepared["quotedAt"] = Date().timeIntervalSince1970 * 1000
            r["prepared"] = prepared; r["state"] = "QUOTED"; r.removeValue(forKey:"error")
        case "paid":
            try require(r,"PAYMENT_RETURNED")
            guard let txid = value["txid"] as? String, txid.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil,
                  let beef = value["beef"] as? String, let returned = r["walletResult"] as? JSON, let wire = value["wire"] as? JSON,
                  let p = r["prepared"] as? JSON, sameJSON(p["remittances"],wire["outputs"]), wire["description"] as? String == "MessageBox delivery payment",
                  try Wire.bytes(returned["tx"]).base64EncodedString() == beef, try Wire.bytes(wire["tx"]).base64EncodedString() == beef,
                  returned["txid"] == nil || returned["txid"] as? String == txid else { throw CryptonError("Payment differs from the saved wallet result.") }
            r["payment"] = value; r["state"] = "PAID"
        case "receipt":
            try require(r,"SUBMITTING")
            guard value["status"] as? String == "success", let p = r["prepared"] as? JSON, sameJSON(value["messageId"],p["messageId"]) else { throw CryptonError("Receipt does not match this delivery.") }
            r["receipt"] = value; r["state"] = "SENT"; r["acceptedAt"] = Date().timeIntervalSince1970 * 1000; r.removeValue(forKey:"error")
        case "history": try require(r,"PAYMENT_REQUESTED"); r["walletHistory"] = value
        case "recoveredPayment":
            try require(r,"PAYMENT_REQUESTED")
            guard action == "recover", let history = r["walletHistory"] as? JSON,
                  integer(history["totalActions"]) == 1, let transactions = history["transactions"] as? [JSON], transactions.count == 1,
                  let txid = value["txid"] as? String, txid == transactions[0]["txid"] as? String,
                  ["unproven","completed"].contains(transactions[0]["status"] as? String ?? ""),
                  !(try Wire.bytes(value["tx"])).isEmpty else { throw CryptonError("Recovered payment does not match this delivery's wallet history.") }
            r["walletResult"] = value; r["state"] = "PAYMENT_RETURNED"; r.removeValue(forKey:"error")
        default: throw CryptonError("Unknown delivery checkpoint.")
        }
        try write(r)
    }
    func beforeHTTP(_ id: String, action: String, url: URL, method: String, body: String) throws {
        let base = URL(string:serviceHost)!
        guard url.scheme == base.scheme, url.host == base.host, (url.port ?? (url.scheme == "https" ? 443 : 80)) == (base.port ?? (base.scheme == "https" ? 443 : 80)), url.user == nil, url.password == nil, url.fragment == nil else { throw CryptonError("MessageBox tried to leave its trusted host.") }
        if (url.path == "/.well-known/auth" && method == "POST") || (url.path == "/permissions/quote" && method == "GET") { return }
        guard url.path == "/sendMessage", method == "POST", ["send","resume"].contains(action) else { throw CryptonError("Unexpected MessageBox request.") }
        var r = try get(id)
        guard let p = r["prepared"] as? JSON, let q = p["quote"] as? JSON else { throw CryptonError("Missing saved delivery quote.") }
        let free = try feeTotal(q) == 0
        if free { try require(r,"QUOTED","SUBMITTING") } else { try require(r,"PAID","SUBMITTING") }
        let request = try object(Data(body.utf8))
        let expected: JSON = ["recipient":p["recipient"]!,"messageBox":"notifications","messageId":p["messageId"]!,"body":p["body"]!]
        guard request.count == (free ? 1 : 2), sameJSON(request["message"],expected), free || sameJSON(request["payment"],(r["payment"] as? JSON)?["wire"]) else { throw CryptonError("Delivery payload or saved payment changed.") }
        r["state"] = "SUBMITTING"; r["submittedAt"] = Date().timeIntervalSince1970 * 1000; try write(r)
    }
    func saveError(_ id: String, _ error: Error) throws {
        var r = try get(id); if r["state"] as? String == "SENT" { return }
        r["error"] = String(error.localizedDescription.prefix(400)); try write(r)
    }
}
