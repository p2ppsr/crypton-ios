//
//  MessageVC.swift
//  Crypton
//
//  Created by Brayden Langley on 2/18/23.
//

import Foundation
import UIKit
import BabbageSDK

class MessageVC: UIViewController, UITextViewDelegate {
    
    let TEXTVIEW_DECREASE_AMOUNT = 185.0
    let PROTOCOL_ID = "crypton"
    let KEY_ID = "1"
    var counterparty:String = "self"
    var sdk:BabbageSDK = BabbageSDK(webviewStartURL: "https://mobile-portal.babbage.systems") // TODO: Switch to prod before release
    
    @IBOutlet var messageTextView: PlaceholderTextView!
    @IBOutlet var nextButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        sdk.setParent(parent: self)
        
        messageTextView.placeholder = "Enter the message you would like to encrypt"
        messageTextView.text = "Enter the message you would like to encrypt"
        
        messageTextView.addDoneButton(title: "Done", target: self, selector: #selector(tapDone(sender:)))
    }
    
    @objc func tapDone(sender: Any) {
        self.view.endEditing(true)
    }
    
    @IBAction func encrypt(_ sender: Any) {
        
        if (messageTextView.text == messageTextView.placeholder) {
            // Create a new alert
            let dialogMessage = UIAlertController(title: "Error", message: "Please enter a message!", preferredStyle: .alert)
            dialogMessage.addAction(UIAlertAction(title: "OK", style: .default, handler: { (action) -> Void in
             }))
            // Present alert to user
            self.present(dialogMessage, animated: true, completion: nil)
            return
        }
        
        Task.init {
            let encryptedText = await sdk.encrypt(plaintext: messageTextView.text, protocolID: PROTOCOL_ID, keyID: KEY_ID, counterparty: counterparty)
            messageTextView.text = encryptedText
            
            let QRCodeImage = generateQRCode(from: encryptedText, centerImage: UIImage(named: "encryptedQRLogo"))
            
            if let vc = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "resultsVC") as? ResultsVC {
                vc.secureQRCode = QRCodeImage
                self.navigationController?.pushViewController(vc, animated: true)
            }
        }
    }
}

extension UITextView {
    
    // Add a done button to the editor keyboard
    func addDoneButton(title: String, target: Any, selector: Selector) {
        
        let toolBar = UIToolbar(frame: CGRect(x: 0.0,
                                              y: 0.0,
                                              width: UIScreen.main.bounds.size.width,
                                              height: 44.0))
        let flexible = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let barButton = UIBarButtonItem(title: title, style: .plain, target: target, action: selector)
        toolBar.setItems([flexible, barButton], animated: false)
        self.inputAccessoryView = toolBar
    }
}
