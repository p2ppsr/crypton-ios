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
    let PROTOCOL_ID = "crypton"
    let KEY_ID = "1"
    // This should be a shared instance for all view controllers and passed around via segues
    var sdk:BabbageSDK = BabbageSDK()

    override func viewDidLoad() {
        super.viewDidLoad()
        sdk.setParent(parent: self)
        
        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing))
        view.addGestureRecognizer(tap)
    }
    
    // Show/hide the Babbage Desktop webview
    @IBAction func showWebView(_ sender: Any) {
        sdk.showView()
    }

    // Encrypts the text from the textview
    @IBAction func encrypt(_ sender: Any) {
        Task.init {
            textView.text = await sdk.encrypt(plaintext: textView.text, protocolID: PROTOCOL_ID, keyID: KEY_ID)
        }
    }
    // Decrypts the text from the textview
    @IBAction func decrypt(_ sender: Any) {
        Task.init {
            textView.text = await sdk.decrypt(ciphertext: textView.text!, protocolID: PROTOCOL_ID, keyID: KEY_ID)
        }
    }
}

