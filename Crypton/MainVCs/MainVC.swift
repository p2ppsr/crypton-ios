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

class MainVC: UIViewController, BabbageDelegate {
    
    let PROTOCOL_ID = "crypton"
    let KEY_ID = "1"
    var sdk:BabbageSDK = BabbageSDK(webviewStartURL: "https://mobile-portal.babbage.systems")
    var identityKey:String?
    
    var contactIdentifier:String?
    var loadingIndicator:UIActivityIndicatorView!
    
    @IBAction func getInfo(_ sender: Any) {
        Task.init {
            // Get the current user's identityKey
            if ((identityKey == nil)) {
                identityKey = await sdk.getPublicKey(identityKey: true)
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
            let userDefaults = UserDefaults.standard
            let hasLoggedIn = userDefaults.bool(forKey: "hasLoggedInBefore")

            if (hasLoggedIn == false) {
                userDefaults.set(true, forKey: "hasLoggedInBefore")
                self.loadingIndicator?.stopAnimating()
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the current viewController as the Babbage authentication callback delegate
        sdk.delegate = self
        
        let userDefaults = UserDefaults.standard
        if userDefaults.bool(forKey: "hasLoggedInBefore") == false {
            // Create the loading indicator and center it in the view
            loadingIndicator = UIActivityIndicatorView(style: .large)
            loadingIndicator.center = self.view.center

            // Add the loading indicator to the view and start animating it
            self.view.addSubview(loadingIndicator)
            loadingIndicator.startAnimating()
        }
        
        sdk.setParent(parent: self)
        
        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor:  UIColor(red: 154/255, green: 224/255, blue: 157/255, alpha: 1.0)]
        
        if Reachability.isConnectedToNetwork() {
            // Internet connection reachable
        } else{
            // Create a new alert
            let dialogMessage = UIAlertController(title: "Error", message: "Internet connection required to login!", preferredStyle: .alert)
            dialogMessage.addAction(UIAlertAction(title: "OK", style: .default, handler: { (action) -> Void in
            }))
            // Present alert to user
            self.present(dialogMessage, animated: true, completion: nil)
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
//        guard let vc = segue.destination as? CryptoVC else { return }
//        if let button = sender as? UIButton {
//            if (button.tag == 0){
//                vc.action = "Encrypt"
//            } else {
//                vc.action = "Decrypt"
//            }
//        }
    }
}
