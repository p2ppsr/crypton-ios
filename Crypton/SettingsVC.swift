//
//  SettingsVC.swift
//  Crypton
//
//  Created by Brayden Langley on 2/13/23.
//

import Foundation
import UIKit

class SettingsVC: UIViewController {

    @IBOutlet var identityKeyImageView: UIImageView!
    var identityKey: String?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Get the identityKey which should be initialized by the mainVC
        identityKeyImageView.image = generateQRCode(from: identityKey ?? "", centerImage: UIImage(named: "userIcon"), color: "CryptonGreen")
    }
    
    @IBAction func shareButton(_ sender: Any) {
        // Set up activity view controller
        let activityViewController = UIActivityViewController(activityItems: [identityKeyImageView.image!], applicationActivities: nil)
        activityViewController.isModalInPresentation = true
        activityViewController.popoverPresentationController?.sourceView = self.view // so that iPads won't crash

        // Present the view controller
        self.present(activityViewController, animated: true, completion: nil)

        // Set the completion block
        activityViewController.completionWithItemsHandler = { (activityType, completed, returnedItems, error) in
            if completed {
                // Create a new alert
                let dialogMessage = UIAlertController(title: "Shared", message: "IdentityKey shared!", preferredStyle: .alert)
                dialogMessage.addAction(UIAlertAction(title: "OK", style: .default, handler: { (action) -> Void in
                 }))
                // Present alert to user
                self.present(dialogMessage, animated: true, completion: nil)
            }
        }
    }
}
