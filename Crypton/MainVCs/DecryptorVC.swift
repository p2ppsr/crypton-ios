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
import AVFoundation

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
    
    var sfxAudioPlayer = AVAudioPlayer()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        sdk.setParent(parent: self)
        
        messageTextView.placeholder = "Enter or scan the message you would like to decrypt"
        messageTextView.text = "Enter or scan the message you would like to decrypt"
        messageTextView.repositionAmount = 0
        
        messageTextView.addDoneButton(title: "Done", target: self, selector: #selector(tapDone(sender:)))
        
        self.imagePicker = ImagePicker(presentationController: self, delegate: self)
        self.imagePicker.present(from: self.view)
        
        // Fetch the Sound data set.
        if let asset = NSDataAsset(name:"decryptSound") {
           do {
               // Use NSDataAsset's data property to access the audio file stored in Sound.
               sfxAudioPlayer = try AVAudioPlayer(data:asset.data, fileTypeHint:"mp3")
               sfxAudioPlayer.volume = 0.1
           } catch let error as NSError {
                 print(error.localizedDescription)
           }
        }
    }
    
    @objc func tapDone(sender: Any) {
        self.view.endEditing(true)
    }
    
    func didScanQRCode(withData data: String) {
        messageTextView.text = data
    }
    
    @IBAction func decrypt(_ sender: Any) {
        
        if (messageTextView.text == messageTextView.placeholder) {
            // Create a new alert
            showCustomAlert(vc: self, title: "Error", description: "Please enter a message to decrypt!")
            return
        }
        
        if (userDefaults.bool(forKey: "soundDisabled") == false) {
            sfxAudioPlayer.currentTime = 0
            sfxAudioPlayer.play()
        }
        
        Task.init {
            do {
                messageTextView.text = try await sdk.decrypt(ciphertext: messageTextView.text!, protocolID: PROTOCOL_ID, keyID: KEY_ID, counterparty: counterparty)
            } catch {
                showErrorMessage(vc: self, error: error)
            }
//
//            // Stop the encryption sound if playing
//            if (self.sfxAudioPlayer.isPlaying) {
//                self.sfxAudioPlayer.stop()
//                self.sfxAudioPlayer.currentTime = 0
//            }
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
            
            if message == "" {
                print("nothing")
            } else {
                messageTextView.text = message
            }
        }
    }
}
