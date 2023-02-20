//
//  MessageVC.swift
//  Crypton
//
//  Created by Brayden Langley on 2/18/23.
//

import Foundation
import UIKit
import BabbageSDK
import GenericJSON

class DecryptorVC: UIViewController, UITextViewDelegate, QRScannerDelegate {
    
    let TEXTVIEW_DECREASE_AMOUNT = 185.0
    let PROTOCOL_ID:JSON = [1, "crypton"]
    let KEY_ID = "1"
    var counterparty:String = "self"
    var sdk:BabbageSDK = BabbageSDK(webviewStartURL: "https://mobile-portal.babbage.systems") // TODO: Switch to prod before release
    
    @IBOutlet var messageTextView: PlaceholderTextView!
    @IBOutlet var nextButton: UIButton!
    
    var secureQRCode: UIImage?
    var imagePicker: ImagePicker!
    
    var encryptedMessage:String?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        sdk.setParent(parent: self)
        
        messageTextView.placeholder = "Enter or scan the message you would like to decrypt"
        messageTextView.text = "Enter or scan the message you would like to decrypt"
        messageTextView.repositionAmount = 0
        
        messageTextView.addDoneButton(title: "Done", target: self, selector: #selector(tapDone(sender:)))
        
        self.imagePicker = ImagePicker(presentationController: self, delegate: self)
        self.imagePicker.present(from: self.view)
    }
    
    @objc func tapDone(sender: Any) {
        self.view.endEditing(true)
    }
    
    func didScanQRCode(withData data: String) {
        encryptedMessage = data
        messageTextView.text = encryptedMessage
    }
    
    @IBAction func decrypt(_ sender: Any) {
        
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
            do {
                messageTextView.text = try await sdk.decrypt(ciphertext: encryptedMessage!, protocolID: PROTOCOL_ID, keyID: KEY_ID, counterparty: counterparty)
            } catch {
                showErrorMessage(vc: self, error: error)
            }
        }
    }
    @IBAction func scanQRCode(_ sender: Any) {
        self.imagePicker.present(from: self.view)
    }
}

extension DecryptorVC: ImagePickerDelegate {

    func didSelect(image: UIImage?) {
        self.secureQRCode = image
        if ((image) != nil) {
            let detector:CIDetector=CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy:CIDetectorAccuracyHigh])!
            let ciImage:CIImage=CIImage(image:self.secureQRCode!)!
            var message=""
  
            let features=detector.features(in: ciImage)
            for feature in features as! [CIQRCodeFeature] {
                message += feature.messageString!
            }
            
            if message=="" {
                print("nothing")
            }else{
                print("message: \(message)")
                messageTextView.text = message
                encryptedMessage = message
//                Task.init {
//                    if (isSelectingRecipient) {
//                        counterpartyTextField.text = message
//                    } else {
//                        do {
//                            textView.text = try await sdk.decrypt(ciphertext: message, protocolID: PROTOCOL_ID, keyID: KEY_ID, counterparty: getCounterparty())
//                        } catch {
//                            // Create a new alert
//                            let dialogMessage = UIAlertController(title: "Error", message: "Decryption failed!", preferredStyle: .alert)
//                            dialogMessage.addAction(UIAlertAction(title: "OK", style: .default, handler: { (action) -> Void in
//                             }))
//                            // Present alert to user
//                            self.present(dialogMessage, animated: true, completion: nil)
//                        }
//                    }
//                }
            }
        }
    }
}
