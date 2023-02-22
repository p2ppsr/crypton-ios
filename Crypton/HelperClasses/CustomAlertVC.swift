//
//  CustomAlertVC.swift
//  Crypton
//
//  Created by Brayden Langley on 2/21/23.
//

import Foundation
import UIKit

class CustomAlertVC: UIViewController {
    @IBOutlet var alertTitle:UILabel!
    @IBOutlet var alertDescription:UITextView!
    @IBOutlet var cancelButton:UIButton!
    @IBOutlet var okayButton:UIButton!
    
    @IBOutlet var singleButtonView:UIView!
    @IBOutlet var twoButtonView:UIView!
    @IBOutlet var alertView: UIView!
    
    weak var delegate: CustomAlertVCDelegate?
    
    var customTitle:String = ""
    var customDescription:String = ""
    var customOkayButtonTitle:String = "OK"
    var singleButton:Bool = true
    
    override func viewDidLoad() {
        super.viewDidLoad()
        alertTitle.text = customTitle
        alertDescription.text = customDescription
        okayButton.titleLabel?.text = customOkayButtonTitle
       
        // Add a drop shadow
        alertView.layer.shadowColor = UIColor.black.cgColor
        alertView.layer.shadowOpacity = 0.5
        alertView.layer.shadowOffset = CGSize(width: 0, height: 2)
        alertView.layer.shadowRadius = 4

        // Set the corner radius
        alertView.layer.cornerRadius = 8
        
        // Toggle the two modes of dialogs
        if (singleButton) {
            singleButtonView.isHidden = false
            twoButtonView.isHidden = true
        } else {
            singleButtonView.isHidden = true
            twoButtonView.isHidden = false
        }
    }
    
    @IBAction func okayPressed(_ sender: Any) {
        self.dismiss(animated: true, completion: nil)
        delegate?.okButtonPressed(self, alertTag: 0)
    }
    
    @IBAction func cancelPressed(_ sender: Any) {
        self.dismiss(animated: true, completion: nil)
        delegate?.cancelButtonPressed(self, alertTag: 1)
    }
}

protocol CustomAlertVCDelegate: AnyObject {
    func okButtonPressed(_ alert: CustomAlertVC, alertTag: Int)
    func cancelButtonPressed(_ alert: CustomAlertVC, alertTag: Int)
}
