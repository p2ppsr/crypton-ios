import Foundation
import CoreFoundation

typealias JSON = [String: Any]
struct CryptonError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
func jsonData(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]) }
func jsonString(_ value: Any) throws -> String { String(decoding: try jsonData(value), as: UTF8.self) }
func object(_ data: Data) throws -> JSON {
    guard let result = try JSONSerialization.jsonObject(with: data) as? JSON else { throw CryptonError("Invalid JSON response.") }
    return result
}
func sameJSON(_ a: Any?, _ b: Any?) -> Bool {
    guard let a = a, let b = b, let left = try? jsonData(a), let right = try? jsonData(b) else { return false }
    return left == right
}
func integer(_ value: Any?) -> Int? {
    guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue == Double(n.intValue) else { return nil }
    return n.intValue
}

// Public-key validation only. No private-key arithmetic is performed in native code.
// Little-endian limbs with addition/multiplication modulo the secp256k1 field.
private struct Field: Equatable, Comparable {
    var words: [UInt64]
    static let zero = Field(words: [0,0,0,0])
    static let p = Field(words: [0xfffffffefffffc2f, .max, .max, .max])
    static func < (a: Field, b: Field) -> Bool {
        for i in (0..<4).reversed() { if a.words[i] != b.words[i] { return a.words[i] < b.words[i] } }
        return false
    }
    func subtract(_ b: Field) -> Field {
        var out = words, borrow = false
        for i in 0..<4 {
            let (x, first) = words[i].subtractingReportingOverflow(b.words[i])
            let (y, second) = x.subtractingReportingOverflow(borrow ? 1 : 0)
            out[i] = y; borrow = first || second
        }
        return Field(words: out)
    }
    func add(_ b: Field) -> Field {
        let gap = Field.p.subtract(b)
        if self >= gap { return subtract(gap) }
        var out = words, carry = false
        for i in 0..<4 {
            let (x, first) = words[i].addingReportingOverflow(b.words[i])
            let (y, second) = x.addingReportingOverflow(carry ? 1 : 0)
            out[i] = y; carry = first || second
        }
        return Field(words: out)
    }
    func multiply(_ b: Field) -> Field {
        var sum = Field.zero, value = self
        for word in b.words { for bit in 0..<64 { if (word >> bit) & 1 == 1 { sum = sum.add(value) }; value = value.add(value) } }
        return sum
    }
    func power(_ exponent: Field) -> Field {
        var value = self, result = Field(words: [1,0,0,0])
        for word in exponent.words { for bit in 0..<64 { if (word >> bit) & 1 == 1 { result = result.multiply(value) }; value = value.multiply(value) } }
        return result
    }
}

enum Wire {
    static let maxPayload = 64_000
    static func identity(_ value: String) throws -> String {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard key.range(of: "^0[23][0-9a-f]{64}$", options: .regularExpression) != nil else { throw CryptonError("Enter a compressed identity public key (66 hexadecimal characters).") }
        let hex = String(key.dropFirst(2))
        var words: [UInt64] = []
        for i in (0..<4).reversed() {
            let start = hex.index(hex.startIndex, offsetBy: i * 16)
            words.append(UInt64(hex[start..<hex.index(start, offsetBy: 16)], radix: 16)!)
        }
        let x = Field(words: words)
        guard x < .p else { throw CryptonError("Identity key is outside the secp256k1 field.") }
        let square = x.multiply(x).multiply(x).add(Field(words: [7,0,0,0]))
        let y = square.power(Field(words: [0xffffffffbfffff0c, .max, .max, 0x3fffffffffffffff]))
        guard y.multiply(y) == square else { throw CryptonError("Identity key is not on the secp256k1 curve.") }
        return key
    }
    static func base64(_ value: String) throws -> Data {
        guard !value.isEmpty, let bytes = Data(base64Encoded: value), bytes.base64EncodedString() == value else { throw CryptonError("Invalid base64 ciphertext.") }
        return bytes
    }
    static func envelope(_ input: String) throws -> JSON {
        guard input.utf8.count <= maxPayload else { throw CryptonError("This Crypton payload exceeds 64 KB.") }
        let e = try object(Data(input.utf8))
        guard Set(e.keys) == Set(["protocol", "version", "sender", "ciphertext"]), e["protocol"] as? String == "crypton", integer(e["version"]) == 2,
              let sender = e["sender"] as? String, let cipher = e["ciphertext"] as? String, cipher.count >= 64 else { throw CryptonError("Invalid Crypton v2 envelope. Public recipient metadata is not supported.") }
        _ = try identity(sender); _ = try base64(cipher)
        return e
    }
    static func isEnvelope(_ value: String) -> Bool { value.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") }
    static func legacy(_ input: String, peer: String, encrypt: Bool) throws -> JSON {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, input.utf16.count <= (encrypt ? 16_000 : 100_000) else { throw CryptonError("Enter a message within the size limit.") }
        let key = peer == "self" ? peer : try identity(peer)
        let data = encrypt ? Data(input.utf8).base64EncodedString() : input.filter { !$0.isWhitespace }
        if !encrypt { _ = try base64(data) }
        return [encrypt ? "plaintext" : "ciphertext": data, "protocolID": [1,"crypton"], "keyID": "1", "counterparty": key, "returnType": "string"]
    }
    static func endpoint(_ text: String, debugLoopback: Bool = false) throws -> URL {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        guard let c = URLComponents(string: value), let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              c.port == nil || (1...65535).contains(c.port!),
              c.scheme == "https" || (debugLoopback && c.scheme == "http" && ["localhost","127.0.0.1"].contains(host)), let url = c.url else { throw CryptonError("Enter an HTTPS BRC-100 wallet address.") }
        return url
    }
    static func walletArguments(_ call: String, _ args: JSON) throws -> JSON {
        switch call {
        case "getPublicKey": return ["identityKey": true, "seekPermission": true]
        case "isAuthenticated", "waitForAuthentication": return [:]
        case "createHmac", "encrypt", "decrypt":
            let field = call == "createHmac" ? "data" : call == "encrypt" ? "plaintext" : "ciphertext"
            guard let data = args[field] as? String, let protocolID = args["protocolID"], let key = args["keyID"], let peer = args["counterparty"] else { throw CryptonError("Invalid wallet arguments.") }
            return [field: Array(try base64(data)), "protocolID": protocolID, "keyID": key, "counterparty": peer, "seekPermission": true]
        default: throw CryptonError("Unsupported wallet operation.")
        }
    }
    static func bytes(_ value: Any?) throws -> Data {
        if let array = value as? [Any], array.count <= 2_000_000 {
            return try Data(array.map { value in guard let n = integer(value), (0...255).contains(n) else { throw CryptonError("The wallet returned invalid bytes.") }; return UInt8(n) })
        }
        if let obj = value as? JSON {
            if let encoded = obj["__metanetByteArrayBase64"] as? String {
                let data = try base64(encoded)
                guard obj.count == 2, integer(obj["__metanetByteArrayLength"]) == data.count, data.count <= 2_000_000 else { throw CryptonError("Invalid wallet byte length.") }
                return data
            }
            guard obj.count <= 2_000_000 else { throw CryptonError("Wallet response too large.") }
            return try bytes((0..<obj.count).map { obj[String($0)] ?? NSNull() })
        }
        throw CryptonError("Invalid wallet bytes.")
    }
    static func walletResult(_ call: String, _ response: JSON) throws -> Any {
        if response["isError"] as? Bool == true { throw CryptonError("The wallet declined the request. Check its permission prompt and retry.") }
        switch call {
        case "isAuthenticated", "waitForAuthentication":
            guard response["authenticated"] as? Bool == true else { throw CryptonError("Open and unlock your wallet, then retry.") }; return true
        case "getPublicKey": return try identity(response["publicKey"] as? String ?? "")
        default:
            let data = try bytes(response[call == "createHmac" ? "hmac" : call == "encrypt" ? "ciphertext" : "plaintext"])
            if call == "createHmac" && data.count != 32 { throw CryptonError("Invalid Crypton key material.") }
            if call == "decrypt" { guard let text = String(data: data, encoding: .utf8) else { throw CryptonError("Invalid UTF-8 plaintext.") }; return text }
            return data.base64EncodedString()
        }
    }
}

struct DiscoveredIdentity: Identifiable, Equatable {
    let key: String
    let name: String
    let certification: String
    let certifier: String
    let certificateType: String
    var id: String { key + ":" + certifier + ":" + certificateType }
}

/// Discovery is read-only and always uses the connected wallet's trust policy.
enum RecipientDiscovery {
    static let methods: Set<String> = ["discoverByAttributes", "discoverByIdentityKey"]
    static let limit = 20
    static func text(_ value: Any?, maximum: Int) throws -> String {
        guard let value = value as? String, value.utf8.count <= maximum,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || (0x200B...0x200F).contains($0.value) || (0x202A...0x202E).contains($0.value) || (0x2066...0x2069).contains($0.value) || $0.value == 0xFEFF }) else { throw CryptonError("Invalid identity search text or wallet metadata.") }
        return value.trimmingCharacters(in:.whitespacesAndNewlines)
    }
    static func request(_ input: String) throws -> (method:String,args:JSON) {
        let query = try text(input,maximum:256)
        guard query.count >= 2 else { throw CryptonError("Enter at least two characters to search.") }
        if query.range(of:"^[0-9a-fA-F]{66}$",options:.regularExpression) != nil {
            return ("discoverByIdentityKey",["identityKey":try Wire.identity(query),"limit":limit,"offset":0,"seekPermission":true])
        }
        return ("discoverByAttributes",["attributes":["any":query],"limit":limit,"offset":0,"seekPermission":true])
    }
    static func arguments(_ method:String,_ args:JSON) throws -> JSON {
        guard methods.contains(method), integer(args["limit"]) == limit, integer(args["offset"]) == 0,
              let seek = args["seekPermission"] as? Bool, seek, integer(args["seekPermission"]) == nil else { throw CryptonError("Invalid identity discovery request.") }
        let query:String
        if method == "discoverByIdentityKey" {
            guard Set(args.keys) == Set(["identityKey","limit","offset","seekPermission"]), let key = args["identityKey"] as? String else { throw CryptonError("Invalid identity key lookup.") }
            query = try Wire.identity(key)
        } else {
            guard Set(args.keys) == Set(["attributes","limit","offset","seekPermission"]), let attributes = args["attributes"] as? JSON, Set(attributes.keys) == Set(["any"]), let value = attributes["any"] as? String else { throw CryptonError("Invalid identity attribute lookup.") }
            query = value
        }
        let expected = try request(query)
        guard expected.method == method, sameJSON(expected.args,args) else { throw CryptonError("Identity discovery arguments changed.") }
        return args
    }
    static func response(_ value:Any,_ args:JSON) throws -> JSON {
        guard let value = value as? JSON, value["isError"] as? Bool != true,
              let total = integer(value["totalCertificates"]), total >= 0,
              let certificates = value["certificates"] as? [JSON], certificates.count <= limit, total >= certificates.count,
              try jsonData(value).count <= 1_000_000 else { throw CryptonError("The wallet returned invalid identity search results.") }
        for certificate in certificates {
            let subject = try Wire.identity(certificate["subject"] as? String ?? "")
            _ = try Wire.identity(certificate["certifier"] as? String ?? "")
            if let expected = args["identityKey"] as? String, subject != expected { throw CryptonError("The wallet returned a different identity.") }
            guard let info = certificate["certifierInfo"] as? JSON, let trust = integer(info["trust"]), (1...10).contains(trust),
                  let fields = certificate["decryptedFields"] as? JSON, fields.count <= 100 else { throw CryptonError("The wallet returned incomplete certificate details.") }
            _ = try text(info["name"],maximum:500)
            for field in fields.values { _ = try text(field,maximum:4096) }
        }
        return value
    }
    static func identities(_ value:Any) throws -> [DiscoveredIdentity] {
        guard let rows = value as? [JSON], rows.count <= limit else { throw CryptonError("Invalid identity search results.") }
        var seen = Set<String>()
        return try rows.compactMap { row in
            let key = try Wire.identity(row["key"] as? String ?? "")
            let identity = DiscoveredIdentity(key:key,name:try text(row["name"],maximum:4096),certification:try text(row["certification"],maximum:1000),certifier:try Wire.identity(row["certifier"] as? String ?? ""),certificateType:try text(row["certificateType"],maximum:256))
            guard !identity.name.isEmpty, !identity.certification.isEmpty, !identity.certificateType.isEmpty else { throw CryptonError("Incomplete identity search result.") }
            return seen.insert(identity.id).inserted ? identity : nil
        }
    }
}
