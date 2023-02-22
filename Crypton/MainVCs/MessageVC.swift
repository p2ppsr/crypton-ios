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
import FLAnimatedImage
import AVFoundation

class MessageVC: UIViewController, UITextViewDelegate {
    
    let TEXTVIEW_DECREASE_AMOUNT = 185.0
    let PROTOCOL_ID:JSON = [1, "crypton"]
    let KEY_ID = "1"
    var counterparty:String = "self"
    var sdk:BabbageSDK = BabbageSDK(webviewStartURL: "https://mobile-portal.babbage.systems") // TODO: Switch to prod before release
    var loadingAnimationView:FLAnimatedImageView!
    var sfxAudioPlayer = AVAudioPlayer()
    
    @IBOutlet var messageTextView: PlaceholderTextView!
    @IBOutlet var nextButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Note: The animation view must be added before the webview to still show permission popups
        loadingAnimationView = addLoadingAnimation(parentView: view)
        loadingAnimationView.isHidden = true
        sdk.setParent(parent: self)
        
        messageTextView.placeholder = "Enter the message you would like to encrypt"
        messageTextView.text = "Enter the message you would like to encrypt"
        
        messageTextView.addDoneButton(title: "Done", target: self, selector: #selector(tapDone(sender:)))
        
        // Fetch the Sound data set.
        if let asset = NSDataAsset(name:"encryptSound") {
           do {
               // Use NSDataAsset's data property to access the audio file stored in Sound.
               sfxAudioPlayer = try AVAudioPlayer(data:asset.data, fileTypeHint:"mp3")
               sfxAudioPlayer.volume = 0.1
           } catch let error as NSError {
                 print(error.localizedDescription)
           }
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        sfxAudioPlayer.stop()
    }

    @objc func tapDone(sender: Any) {
        self.view.endEditing(true)
    }
    
    @IBAction func encrypt(_ sender: Any) {
        
        if (messageTextView.text == messageTextView.placeholder) {
            // Create a new alert
            showCustomAlert(vc: self, title: "Error", description: "Please enter a message to encrypt!")
            return
        }
        if (userDefaults.bool(forKey: "soundDisabled") == false) {
            sfxAudioPlayer.currentTime = 0
            sfxAudioPlayer.play()
        }

        Task.init {
            do {
                // Configure animation view (note: does not loop forever)
                loadingAnimationView.runLoopMode = RunLoop.Mode.common
                self.loadingAnimationView.isHidden = false
                loadingAnimationView.startAnimating()
                let startTime = DispatchTime.now()
                
                let encryptedText = try await sdk.encrypt(plaintext: messageTextView.text, protocolID: PROTOCOL_ID, keyID: KEY_ID, counterparty: counterparty)
                
                let endTime = DispatchTime.now()
                let elapsedTime = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000
                let goalTime = 3.0
                
                DispatchQueue.main.asyncAfter(deadline: .now() + (goalTime - elapsedTime)) {
                    self.loadingAnimationView.stopAnimating()
                    self.loadingAnimationView.isHidden = true
                    self.messageTextView.text = encryptedText
                    
                    // Stop the encryption sound if playing
                    if (self.sfxAudioPlayer.isPlaying) {
                        self.sfxAudioPlayer.stop()
                    }
                    
                    if let vc = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "resultsVC") as? ResultsVC {
                        vc.secureQRCode = generateQRCode(from: encryptedText, centerImage: UIImage(named: "encryptedQRLogo"))
                        self.navigationController?.pushViewController(vc, animated: true)
                    }
                }
            } catch {
                showErrorMessage(vc: self, error: error)
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
