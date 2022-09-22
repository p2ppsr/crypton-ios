////
////  ViewController.swift
////  Crypton
////
////  Created by Brayden Langley on 9/19/22.
////
//
//import UIKit
//import WebKit
//import BabbageSDK
//
//// Controller responsible for handling interactions on the main view
//class ViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
//
//    @IBOutlet var textView: UITextView!
//    @IBOutlet var showHideBtn: UIButton!
//    @IBOutlet var webView: WKWebView!
//
//    let PROTOCOL_ID = "crypton"
//    let KEY_ID = "1"
//    let HADES_BASE_URL = "http://localhost:3000" // https://staging-mobile-portal.babbage.systems
//
//    private var sdk: BabbageSDK?
//
//    override func loadView() {
//        super.loadView()
//        // Do any additional setup after loading the view.
//        webView.navigationDelegate = self
//        webView.uiDelegate = self
//        webView.customUserAgent = "babbage-webview-inlay"
//
//        // Disable zooming on webview
//        let source: String = "var meta = document.createElement('meta');" +
//            "meta.name = 'viewport';" +
//            "meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';" +
//            "var head = document.getElementsByTagName('head')[0];" +
//            "head.appendChild(meta);"
//        let script: WKUserScript = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
//        webView.configuration.userContentController.addUserScript(script)
//
//        // Load the request url for hades server
//        let request = NSURLRequest(url: URL(string: HADES_BASE_URL)!)
//        webView.load(request as URLRequest)
//
//        // Initialize the sdk with the webview
//        sdk = BabbageSDK.init()
//    }
//    // Show/hide the Babbage Desktop webview
//    @IBAction func toggleWebview(_ sender: Any) {
//        webView.isHidden = !webView.isHidden
//    }
//    // Encrypts the text from the textview
//    @IBAction func encrypt(_ sender: Any) {
//        // Note: needs to be a buffer or base64, and permission granting does not work in the mobile view currently
//        let utf8str = textView.text!.data(using: .utf8)
//        if let base64Encoded = utf8str?.base64EncodedString(options: Data.Base64EncodingOptions(rawValue: 0)) {
//            print("Encoded: \(base64Encoded)")
//
//            // Generate ID
//            let callbackID: String = (sdk?.generateCallbackID())!
//            // Set Webview callback
//            webView.configuration.userContentController.add(self, name: callbackID)
//            // pass it in to sdk call
//            Task.init {
//                textView.text = await sdk?.encrypt(plaintext: base64Encoded, protocolID: PROTOCOL_ID, keyID: KEY_ID, id: callbackID)
//            }
//        }
//    }
//    // Decrypts the text from the textview
//    @IBAction func decrypt(_ sender: Any) {
//        Task.init {
//            let callbackID: String = (sdk?.generateCallbackID())!
//            webView.configuration.userContentController.add(self, name: callbackID)
//            textView.text = await sdk?.decrypt(ciphertext: textView.text!, protocolID: PROTOCOL_ID, keyID: KEY_ID, id: callbackID)
//        }
//    }
//
//    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
//        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .actionSheet)
//
//        alertController.addAction(UIAlertAction(title: "Confirm", style: .destructive, handler: { (action) in
//            completionHandler(true)
//        }))
//
//        alertController.addAction(UIAlertAction(title: "Cancel", style: .default, handler: { (action) in
//            completionHandler(false)
//        }))
//
//        present(alertController, animated: true, completion: nil)
//    }
//
//    // Callback recieved from webkit.messageHandler.postMessage
//    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
//        //This function handles the events coming from javascript.
//        guard let response = message.body as? String else { return }
//
//        if (message.name == "closeBabbage") {
//              webView.isHidden = true
//        } else if (message.name == "openBabbage") {
//              webView.isHidden = false
//        } else {
//            sdk?.callbackIDMap[message.name]!(response)
//        }
//
////      else {
////            // Use this to decode JSON. Needs better error handling though...
////            let responseObject = try! JSONDecoder().decode(BabbageSDK.BabbageResponseWithArray.self, from:response.data(using: .utf8)!)
////
////            // Once we recieve the callback, we can dismiss the webview and show the user the app
////            if (responseObject.id == "isAuthenticated") {
////                if (responseObject.result[0] == "false") {
////                    webView.isHidden = false
////                    let cmd = BabbageSDK.BabbageCommand(type: "CWI", call:"waitForAuthentication", params: [:], id: "waitForAuthentication")
////                    BabbageSDK.init(webView: self.webView).runCommand(webView: webView, cmd: cmd)
////                }
////            } else {
////                textView.text = responseObject.result[0]
////            }
////        }
//    }
//
//    override func viewWillAppear(_ animated: Bool) {
//        print("test")
//    }
//
//    // Webview call back for when the view loads
//    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
//      // This function is called when the webview finishes navigating to the webpage.
//      // We use this to send data to the webview when it's loaded.
//        print("loaded")
//        let id:String = (sdk?.generateCallbackID())!
//        webView.configuration.userContentController.add(self, name: id)
//
//        Task.init {
//            let isAuthenticated:Bool? = await sdk?.isAuthenticated(id: id)
//
//            // Show/Hide the webview
//            if (isAuthenticated!) {
//                webView.isHidden = true
//            } else {
//                webView.isHidden = false
//                let id:String = (sdk?.generateCallbackID())!
//                webView.configuration.userContentController.add(self, name: id)
//                await sdk?.waitForAuthentication(id: id)
//                webView.isHidden = true
//            }
//        }
//    }
//}
//
