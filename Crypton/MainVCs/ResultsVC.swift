//
//  ResultsVC.swift
//  Crypton
//
//  Created by Brayden Langley on 2/9/23.
//

import Foundation
import UIKit
import BabbageSDK
import GenericJSON

class ResultsVC: UIViewController {
    
    let PROTOCOL_ID = "crypton"
    let KEY_ID = "1"
    var sdk:BabbageSDK = BabbageSDK(webviewStartURL: "https:/mobile-portal.babbage.systems")
    
    @IBOutlet var qrCodeImageView: UIImageView!
    var secureQRCode: UIImage?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        sdk.setParent(parent: self)
        qrCodeImageView.image = secureQRCode
        
    }
    
    @IBAction func share(_ sender: UIButton) {
        // Set up activity view controller
        let activityViewController = UIActivityViewController(activityItems: [secureQRCode!], applicationActivities: nil)
        activityViewController.isModalInPresentation = true
        activityViewController.popoverPresentationController?.sourceView = self.view // so that iPads won't crash

        // Present the view controller
        self.present(activityViewController, animated: true, completion: nil)

        // Set the completion block
        activityViewController.completionWithItemsHandler = { (activityType, completed, returnedItems, error) in
            if completed {
                // Create a new alert
                showCustomAlert(vc: self, title: "Shared", description: "Encrypted message shared!")
            }
        }
    }
    
    @IBAction func done(_ sender: UIButton) {
        self.navigationController?.popToRootViewController(animated: true)
    }
}
