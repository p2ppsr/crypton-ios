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
