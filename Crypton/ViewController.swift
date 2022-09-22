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
class ViewController: UIViewController {

    @IBOutlet var textView: UITextView!
    @IBOutlet var showHideBtn: UIButton!
//    @IBOutlet var webView: WKWebView!

//    let PROTOCOL_ID = "crypton"
//    let KEY_ID = "1"
//    let HADES_BASE_URL = "http://localhost:3000" // https://staging-mobile-portal.babbage.systems

    override func loadView() {
        super.loadView()
    }

    // Encrypts the text from the textview
    @IBAction func encrypt(_ sender: Any) {
        // Note: needs to be a buffer or base64, and permission granting does not work in the mobile view currently
        let utf8str = textView.text!.data(using: .utf8)
        if let base64Encoded = utf8str?.base64EncodedString(options: Data.Base64EncodingOptions(rawValue: 0)) {
//            print("Encoded: \(base64Encoded)")
            
            NotificationCenter.default.post(name: Notification.Name("Send"), object: nil)

            // Generate ID
//            let callbackID: String = (sdk?.generateCallbackID())!
//            // Set Webview callback
//            webView.configuration.userContentController.add(self, name: callbackID)
//            // pass it in to sdk call
//            Task.init {
//                textView.text = await sdk?.encrypt(plaintext: base64Encoded, protocolID: PROTOCOL_ID, keyID: KEY_ID, id: callbackID)
//            }
        }
    }
    // Decrypts the text from the textview
    @IBAction func decrypt(_ sender: Any) {
//        Task.init {
//            let callbackID: String = (sdk?.generateCallbackID())!
//            webView.configuration.userContentController.add(self, name: callbackID)
//            textView.text = await sdk?.decrypt(ciphertext: textView.text!, protocolID: PROTOCOL_ID, keyID: KEY_ID, id: callbackID)
//        }
    }
}

