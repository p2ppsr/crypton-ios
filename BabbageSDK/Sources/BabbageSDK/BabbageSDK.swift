import Foundation
import WebKit
public struct BabbageSDK {
    
    public let webView: WKWebView
    
    public init(webView: WKWebView) {
        self.webView = webView
    }
    
    // Defines the structure of a BabbageResponse
    public struct BabbageResponse: Decodable {
        enum Category: String, Decodable {
            case swift, combine, debugging, xcode
        }

        public let type: String
        public let result: String
        public let id: String
        
        // Initialize the properties
        public init(type: String, result: String, id: String){
            self.type = type
            self.result = result
            self.id = id
        }
    }

    // Defines the structure of a BabbageCommand
    public struct BabbageCommand: Codable {
        enum Category: String, Codable {
            case swift, combine, debugging, xcode
        }

        public let type: String
        public let call: String
        public let params: [String:String]
        public let id: String
        
        // Initialize the properties
        public init(type: String, call: String, params: [String:String], id: String){
            self.type = type
            self.call = call
            self.params = params
            self.id = id
        }
    }

    // Encrypts data using CWI.encrypt
    public func encrypt(plaintext: String, protocolID: String, keyID: String) {
        let cmd = BabbageSDK.BabbageCommand(type: "CWI", call: "encrypt", params: ["plaintext": plaintext, "protocolID": protocolID, "keyID": keyID, "originator": "projectbabbage.com", "returnType": "string"], id: "encrypt")
        runCommand(webView: webView, cmd: cmd)
    }

    // Encrypts data using CWI.decrypt
    public func decrypt(ciphertext: String, protocolID: String, keyID: String) {
        let cmd = BabbageSDK.BabbageCommand(type: "CWI", call: "decrypt", params: ["ciphertext": ciphertext, "protocolID": protocolID, "keyID": keyID, "originator": "projectbabbage.com", "returnType": "string"], id: "decrypt")
        runCommand(webView: webView, cmd: cmd)
    }
    
    // Execute the BabbageCommand
    public func runCommand(webView: WKWebView, cmd: BabbageCommand) {
        do {
            let jsonData = try JSONEncoder().encode(cmd)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            webView.evaluateJavaScript("window.postMessage(\(jsonString))") { (result, error) in
//                if error == nil {
//                    print(result as Any)
//                }
            }
        } catch {

        }
    }
}
