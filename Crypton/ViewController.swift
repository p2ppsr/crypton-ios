//
//  ViewController.swift
//  Crypton
//
//  Created by Brayden Langley on 9/19/22.
//

import UIKit
import WebKit
//import BabbageSDK

struct BabbageSDK {
    // Define the request and response objects
    struct BabbageResponse: Decodable {
        enum Category: String, Decodable {
            case swift, combine, debugging, xcode
        }

        let type: String
        let result: String // Hmm...
        let id: String
    }

    struct BabbageCommand: Codable {
        enum Category: String, Codable {
            case swift, combine, debugging, xcode
        }

        let type: String
        let call: String // Hmm...
        let params: [String:String]
        let id: String
    }
}
// Controller responsible for handling interactions on the main view
class ViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate {
    
    @IBOutlet var textView: UITextView!
    @IBOutlet var showHideBtn: UIButton!
    @IBOutlet var webView: WKWebView!
    
    let PROTOCOL_ID = "crypton"
    let KEY_ID = "1"
    
    override func loadView() {
        super.loadView()
        // Do any additional setup after loading the view.
        webView.navigationDelegate = self
        webView.customUserAgent = "babbage-webview-inlay"
        
        // Supported callbacks (include to restrict unwanted generic callbacks?)
        webView.configuration.userContentController.add(self, name: "getPublicKey")
        webView.configuration.userContentController.add(self, name: "encrypt")
        webView.configuration.userContentController.add(self, name: "decrypt")
        webView.configuration.userContentController.add(self, name: "closeBabbage")
        
        // Disable zooming on webview
        let source: String = "var meta = document.createElement('meta');" +
            "meta.name = 'viewport';" +
            "meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';" +
            "var head = document.getElementsByTagName('head')[0];" +
            "head.appendChild(meta);"
        let script: WKUserScript = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        webView.configuration.userContentController.addUserScript(script)
        
        // Load the request url for hades server
        let request = NSURLRequest(url: URL(string: "http://localhost:3000")!)
////        let request = NSURLRequest(url: URL(string: "https://staging-mobile-portal.babbage.systems")!)
        webView.load(request as URLRequest)
    }
    // Show/hide the Babbage Desktop webview
    @IBAction func toggleWebview(_ sender: Any) {
        webView.isHidden = !webView.isHidden
    }
    // Encrypts the text from the textview
    @IBAction func encrypt(_ sender: Any) {
        // Note: needs to be a buffer or base64, and permission granting does not work in the mobile view currently
        let utf8str = textView.text!.data(using: .utf8)
        if let base64Encoded = utf8str?.base64EncodedString(options: Data.Base64EncodingOptions(rawValue: 0)) {
            print("Encoded: \(base64Encoded)")
            
            let cmd = BabbageSDK.BabbageCommand(type: "CWI", call:"encrypt", params: ["plaintext":"\(base64Encoded)", "protocolID": PROTOCOL_ID, "keyID": KEY_ID, "originator": "projectbabbage.com", "returnType": "string"], id: "fooisabar")
            runCommand(cmd: cmd)

            // For decoding base64 to utf8 string
//            if let base64Decoded = Data(base64Encoded: base64Encoded, options: Data.Base64DecodingOptions(rawValue: 0))
//            .map({ String(data: $0, encoding: .utf8) }) {
//                // Convert back to a string
//                print("Decoded: \(base64Decoded ?? "")")
//            }
        }
    }
    // Decrypts the text from the textview
    @IBAction func decrypt(_ sender: Any) {
        // TODO: Check text data type?
        let cmd = BabbageSDK.BabbageCommand(type: "CWI", call:"decrypt", params: ["ciphertext":"\(textView.text!)", "protocolID": PROTOCOL_ID, "keyID":  KEY_ID, "originator": "projectbabbage.com", "returnType": "string"], id: "fooisabar")
        runCommand(cmd: cmd)
    }

    // Callback recieved from webkit.messageHandler.postMessage
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        //This function handles the events coming from javascript.
        guard let response = message.body as? String else { return }
        
        if (response == "closeBabbage") {
            webView.isHidden = true;
        } else {
            // Use this to decode JSON. Needs better error handling though...
            let responseObject = try! JSONDecoder().decode(BabbageSDK.BabbageResponse.self, from:response.data(using: .utf8)!)
            textView.text = responseObject.result
        }
    }
    
    // Helper function to convert dictionary Swift structure to JSON object string
    func convertDictionaryToJSON(dictionary: [String: String]) -> String {
        let theJSONData = try? JSONSerialization.data(
          withJSONObject: dictionary,
          options: .prettyPrinted
          )
        let jsonString = String(data: theJSONData!,
            encoding: String.Encoding.ascii
        )
        return jsonString!
    }
    
    // Execute the JS command
    func runCommand(cmd: BabbageSDK.BabbageCommand) {
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
    // Webview call back for when the view loads
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      // This function is called when the webview finishes navigating to the webpage.
      // We use this to send data to the webview when it's loaded.
        print("loaded")
    }
}

