//
//  EncryptorVC.swift
//  Crypton
//
//  Created by Brayden Langley on 2/9/23.
//

import Foundation
import BabbageSDK
import GenericJSON
import UIKit

/**
  View Controller responsible for encrypting messages
 */
class EncryptorVC: UIViewController {
    
    let PROTOCOL_ID = "crypton"
    let KEY_ID = "1"
    var sdk:BabbageSDK = BabbageSDK(webviewStartURL: "https://staging-mobile-portal.babbage.systems")
    
    var secureQRCode:UIImage!
    @IBOutlet var textView: UITextView!
    @IBOutlet var counterpartyTextField: UITextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        sdk.setParent(parent: self)
        
        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing))
        view.addGestureRecognizer(tap)
    }
    
    // Encrypts the text from the textview
    @IBAction func encrypt(_ sender: Any) {
        Task.init {
            let encryptedText = await sdk.encrypt(plaintext: textView.text, protocolID: PROTOCOL_ID, keyID: KEY_ID, counterparty: getCounterparty())
            textView.text = encryptedText
            
            let QRCodeImage = generateQRCode(from: encryptedText)
            self.secureQRCode = QRCodeImage
            
            if let vc = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "resultsVC") as? ResultsVC {
                vc.secureQRCode = QRCodeImage
                self.navigationController?.pushViewController(vc, animated: true)
            }

//
//            if let mvc = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "resultsVC") as? ResultsVC {
//                self.present(mvc, animated: true, completion: nil)
//              }
        }
    }
    
    // Helper class?
    // Figures out if counterparty is self
    func getCounterparty() -> String {
        var counterparty = "self"
        if (counterpartyTextField.text != "") {
            counterparty = counterpartyTextField.text!
        }
        return counterparty
    }
    
    func generateQRCode(from string: String) -> UIImage? {
        let data = string.data(using: String.Encoding.ascii)
        
        if let filter = CIFilter(name: "CIQRCodeGenerator") {
            filter.setValue(data, forKey: "inputMessage")
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            
            // Convert the image to a format that can be saved on the device
            if let output = filter.outputImage?.transformed(by: transform) {
                let context = CIContext()
                guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
                return UIImage(cgImage: cgImage)
            }
        }
        
        return nil
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let vc = segue.destination as? ResultsVC else { return }
        vc.qrCodeImageView.image = secureQRCode
    }
}
