//
//  ViewController.swift
//  Crypton
//
//  Created by Brayden Langley on 9/19/22.
//

import UIKit
import WebKit
import BabbageSDK

// Controller responsible for handling interactions on the main view
class ViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate {
    
    @IBOutlet var textView: UITextView!
    @IBOutlet var showHideBtn: UIButton!
    @IBOutlet var webView: WKWebView!
    
    let PROTOCOL_ID = "crypton"
    let KEY_ID = "1"
    let HADES_BASE_URL = "http://localhost:3000" // "https://staging-mobile-portal.babbage.systems"
   
    private var sdk: BabbageSDK?
    
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
        webView.configuration.userContentController.add(self, name: "isAuthenticated")
        webView.configuration.userContentController.add(self, name: "waitForAuthentication")
        
        // Disable zooming on webview
        let source: String = "var meta = document.createElement('meta');" +
            "meta.name = 'viewport';" +
            "meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';" +
            "var head = document.getElementsByTagName('head')[0];" +
            "head.appendChild(meta);"
        let script: WKUserScript = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        webView.configuration.userContentController.addUserScript(script)
        
        // Load the request url for hades server
        let request = NSURLRequest(url: URL(string: HADES_BASE_URL)!)
        webView.load(request as URLRequest)

        // Initialize the sdk with the webview
        sdk = BabbageSDK.init(webView: webView)
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
            
            sdk?.encrypt(plaintext: base64Encoded, protocolID: PROTOCOL_ID, keyID: KEY_ID)
        }
    }
    // Decrypts the text from the textview
    @IBAction func decrypt(_ sender: Any) {
        sdk?.decrypt(ciphertext: textView.text!, protocolID: PROTOCOL_ID, keyID: KEY_ID)
    }

    // Callback recieved from webkit.messageHandler.postMessage
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        //This function handles the events coming from javascript.
        guard let response = message.body as? String else { return }
        
        if (response == "closeBabbage") {
            webView.isHidden = true
        } else {
            // Use this to decode JSON. Needs better error handling though...
            let responseObject = try! JSONDecoder().decode(BabbageSDK.BabbageResponse.self, from:response.data(using: .utf8)!)
            
            // Once we recieve the callback, we can dismiss the webview and show the user the app
            if (responseObject.id == "waitForAuthentication") {
                if (responseObject.result == "true") {
                    webView.isHidden = true
                }
            } else {
                textView.text = responseObject.result
            }
        }
    }
    
    // Webview call back for when the view loads
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      // This function is called when the webview finishes navigating to the webpage.
      // We use this to send data to the webview when it's loaded.
        print("loaded")
        let cmd = BabbageSDK.BabbageCommand(type: "CWI", call:"waitForAuthentication", params: [:], id: "waitForAuthentication")
        BabbageSDK.init(webView: self.webView).runCommand(webView: webView, cmd: cmd)
    }
}

