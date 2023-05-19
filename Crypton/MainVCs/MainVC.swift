//
//  MainVC.swift
//  Crypton
//
//  Created by Brayden Langley on 2/10/23.
//

import Foundation
import UIKit
import BabbageSDK
import FLAnimatedImage
import AVFoundation

class MainVC: UIViewController, BabbageDelegate, CustomAlertVCDelegate {
    func okButtonPressed(_ alert: CustomAlertVC, alertTag: Int) {
        print("Okay pressed!")
    }
    
    func cancelButtonPressed(_ alert: CustomAlertVC, alertTag: Int) {
        print("Canceled!")
    }
    
    
    let PROTOCOL_ID = "crypton"
    let KEY_ID = "1"
    var sdk:BabbageSDK = BabbageSDK(webviewStartURL: "https://mobile-portal.babbage.systems")
    var identityKey:String?
    
    var contactIdentifier:String?
    var loadingIndicator:UIActivityIndicatorView!
    
    var backgroundAudioPlayer = AVAudioPlayer()
//    var sfxPlayer = AVAudioPlayer()
    var soundButton: UIBarButtonItem!
    var isSoundOn: Bool = true
    @IBOutlet var newMsgBtn: UIButton!
    @IBOutlet var decryptBtn: UIButton!
    @IBOutlet var identityKeyBtn: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Set the current viewController as the Babbage authentication callback delegate
        sdk.delegate = self
        // Create the loading indicator and center it in the view
        loadingIndicator = UIActivityIndicatorView(style: .large)
        loadingIndicator.center = self.view.center
        loadingIndicator.color = UIColor.white

        // Add the loading indicator to the view and start animating it
        self.view.addSubview(loadingIndicator)
        
        if userDefaults.bool(forKey: "hasLoggedInBefore") == false {
            loadingIndicator.startAnimating()
            // Disable the main buttons before auth
            newMsgBtn.isEnabled = false
            decryptBtn.isEnabled = false
            identityKeyBtn.isEnabled = false
        }
        
        sdk.setParent(parent: self)
        
        // Configure the nav bar tint
        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor:  UIColor(red: defaultRed, green: defaultGreen, blue: defaultBlue, alpha: 1.0)]
        navigationController?.navigationBar.tintColor = UIColor(red: defaultRed, green: defaultGreen, blue: defaultBlue, alpha: 1.0)
        
        if Reachability.isConnectedToNetwork() {
            // Internet connection reachable
        } else{
            // Create a new alert
            showCustomAlert(vc: self, title: "Error", description: "Internet connection required to login!")
        }
        
        // Fetch the Sound data set.
        if let asset = NSDataAsset(name:"PhantomFromSpace") {
           do {
               // Use NSDataAsset's data property to access the audio file stored in Sound.
               backgroundAudioPlayer = try AVAudioPlayer(data:asset.data, fileTypeHint:"mp3")
               // Loop the sound infintely
               backgroundAudioPlayer.numberOfLoops = -1
               backgroundAudioPlayer.volume = 0.07
           } catch let error as NSError {
                 print(error.localizedDescription)
           }
        }
    }
    
    @IBAction func getInfo(_ sender: Any) {
        Task.init {
            // Get the current user's identityKey
            if ((identityKey == nil)) {
                do {
                    loadingIndicator.startAnimating()
                    identityKey = try await sdk.getPublicKey(identityKey: true)
                } catch {
                    showErrorMessage(vc: self, error: error)
                }
                loadingIndicator.stopAnimating()
            }

            // Navigate to the settings view controller
            let settingsView = self.storyboard?.instantiateViewController(withIdentifier: "settingsVC") as! SettingsVC
            settingsView.identityKey = identityKey
            self.navigationController?.present(settingsView, animated: true, completion: nil)
        }
    }
    
    // Notifies the main view when the user is successfully authenticated
    func didAuthenticate(status: Bool) {
        if status {
            if (userDefaults.bool(forKey: "hasLoggedInBefore") == false) {
                userDefaults.set(true, forKey: "hasLoggedInBefore")
                self.loadingIndicator?.stopAnimating()
                
                // Enable buttons on auth
                newMsgBtn.isEnabled = true
                decryptBtn.isEnabled = true
                identityKeyBtn.isEnabled = true
            }
            
            if (userDefaults.bool(forKey: "soundDisabled") == false) {
                // Start the background audio once the user is logged in
                backgroundAudioPlayer.play()
                isSoundOn = true
            } else {
                isSoundOn = false
            }
            
            // Create a sound button
            soundButton = UIBarButtonItem(title: "", style: .plain, target: self, action: #selector(toggleSound))
            soundButton.tintColor = UIColor(red: defaultRed, green: defaultGreen, blue: defaultBlue, alpha: 1)
            let imageName = isSoundOn ? "soundOn" : "soundOff"
            soundButton.image = UIImage(named: imageName)
            navigationItem.rightBarButtonItem = soundButton
        }
    }
    
    @objc func toggleSound() {
         isSoundOn = !isSoundOn
         let imageName = isSoundOn ? "soundOn" : "soundOff"
         soundButton.image = UIImage(named: imageName)
         
         // Toggle sound here
         if isSoundOn {
             backgroundAudioPlayer.play()
             userDefaults.set(false, forKey: "soundDisabled")
         } else {
             backgroundAudioPlayer.stop()
             userDefaults.set(true, forKey: "soundDisabled")
         }
     }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
//        do {
//            sfxPlayer = try AVAudioPlayer(data:NSDataAsset(name:"buttonClick")!.data, fileTypeHint:"mp3")
//            sfxPlayer.play()
//        } catch{
//            print(error)
//        }
    }
}
