//
//  RecipientVC.swift
//  Crypton
//
//  Created by Brayden Langley on 2/18/23.
//

import Foundation
import UIKit

import Contacts
import ContactsUI

class CounterpartyVC: UIViewController, CNContactViewControllerDelegate, CNContactPickerDelegate, QRScannerDelegate, CustomAlertVCDelegate  {
    func okButtonPressed(_ alert: CustomAlertVC, alertTag: Int) {
        self.imagePicker.present(from: self.view)
    }
    
    func cancelButtonPressed(_ alert: CustomAlertVC, alertTag: Int) {
        print("Canceled")
    }
    
    @IBOutlet var nameLabel: UILabel?
    
    @IBOutlet var nextButton: UIButton!
    var identityKey:String?
    var contactIdentifier:String?
    
    var imagePicker:ImagePicker!
    var secureQRCode:UIImage?
    var isNewContact:Bool = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.imagePicker = ImagePicker(presentationController: self, delegate: self)
    }
    
    // Callback function for scanning QR code
    func didScanQRCode(withData data: String) {
        addInstantMessageService(to: contactIdentifier!, identityKey: data)
        nextButton.isHidden = false
    }
    
    @IBAction func selectCounterparty(sender: UIButton) {
        
        // Cnfigure the ContactPickerViewController
        let picker = CNContactPickerViewController()
        picker.delegate = self
        picker.displayedPropertyKeys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactInstantMessageAddressesKey]
        picker.predicateForEnablingContact = NSPredicate(value: true)

        // Manually add a button for adding a new contact
        if #available(iOS 15.0, *) {
            let newContactButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addNewContact))
            picker.navigationItem.rightBarButtonItem = newContactButton
            let navigationController = UINavigationController(rootViewController: picker)
            navigationController.navigationBar.tintColor = .systemBlue
            navigationController.navigationBar.prefersLargeTitles = false
            navigationController.topViewController?.navigationItem.rightBarButtonItem = newContactButton
            // Present a navigation controller with the newContact button
            present(navigationController, animated: true, completion: nil)
        } else {
            // Below iOS 15.0 is not supported anyways
            present(picker, animated: true, completion: nil)
        }
    }
    
    // Display a new view controller for adding a new contact
    @objc func addNewContact() {
        let newContactVC = CNContactViewController(forNewContact: nil)
        newContactVC.delegate = self

        // Dismiss the contact picker view controller
        dismiss(animated: true) {
            // Present the new contact view controller
            let navController = UINavigationController(rootViewController: newContactVC)
            self.isNewContact = true
            self.present(navController, animated: true, completion: nil)
        }
    }

    // Callback function for when a user selects an existing contact
    func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
        // Get the selected contacts name and look for MetaNet Identity Key
        let firstName = contact.givenName
        let lastName = contact.familyName
        self.contactIdentifier = contact.identifier
        
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let qrScannerVC = storyboard.instantiateViewController(withIdentifier: "qrScannerVC") as! QRScannerVC
        qrScannerVC.delegate = self
        
        // Check if an existing MetaNet Identity Key is present on the contact
        let metanetIdentityKey = contact.instantMessageAddresses.filter {
            $0.value.service == "MetaNet Identity Key"
        }
        if (((metanetIdentityKey.first?.value.username)) != nil) {
            identityKey = (metanetIdentityKey.first?.value.username) as String?
            nameLabel?.text = firstName + " " + lastName
            nextButton.isHidden = false
        } else {
            isNewContact = true
            promptUserForIdentityKey()
        }
    }
    
    // Do nothing if the picker is canceled
    func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
        // Handle the cancelled contact picker here
        print("Contact picker cancelled")
    }
    
    // Callback for when a new contact is created
    func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
      guard let contact = contact else { // User tapped "Cancel"
          viewController.dismiss(animated: true)
        return
      }
        
      let store = CNContactStore()
      let saveRequest = CNSaveRequest()
      saveRequest.update(contact.mutableCopy() as! CNMutableContact)
      do {
        try store.execute(saveRequest)
          viewController.dismiss(animated: true, completion: nil)
          if (isNewContact) {
              contactIdentifier = contact.identifier
              promptUserForIdentityKey()
          }
      } catch {
        // Handle error
      }
    }
    
    // Modify a contact to include a MetaNet Identity Key
    func addInstantMessageService(to contactIdentifier: String, identityKey: String) {
        let store = CNContactStore()
        let keysToFetch = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey, CNContactInstantMessageAddressesKey]
        let fetchRequest = CNContactFetchRequest(keysToFetch: keysToFetch as [CNKeyDescriptor])
        fetchRequest.predicate = CNContact.predicateForContacts(withIdentifiers: [contactIdentifier])
        do {
            try store.enumerateContacts(with: fetchRequest) { (contact, stop) in
                // Create a new instant message address with a service and username
                let instantMessageAddress = CNInstantMessageAddress(username: identityKey, service: "MetaNet Identity Key")
                self.identityKey = identityKey
                
                // Wrap the instant message address in a labeled value with a custom label
                let labeledValue = CNLabeledValue(label: "MetaNet Identity Key", value: instantMessageAddress)
                
                // Add the labeled value to the contact's instant message addresses
                let mutableContact = contact.mutableCopy() as! CNMutableContact
                mutableContact.instantMessageAddresses.append(labeledValue)
                
                let saveRequest = CNSaveRequest()
                saveRequest.update(mutableContact)
                do {
                    try store.execute(saveRequest)
                    
                    nameLabel?.text = contact.givenName + " " + contact.familyName
                    nextButton.isHidden = false
                } catch let error {
                    print("Error saving contact: \(error)")
                }
            }
        } catch let error {
            print("Error fetching contacts: \(error)")
        }
    }
    
    func promptUserForIdentityKey() {
        DispatchQueue.main.async {
            // Create a new alert
            showCustomAlert(vc: self, title: "New Counterparty", singleButtonMode: false, description: "Identity Key Not found!", customOkayButtonLabel: "Select QR Code")
        }
    }
    
    // Pass the identityKey for the given counterparty to the next view
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let vc = segue.destination as? MessageVC {
            vc.counterparty = identityKey ?? "self"
        } else if let vc = segue.destination as? DecryptorVC {
            vc.counterparty = identityKey ?? "self"
        }
    }
}

extension CounterpartyVC: ImagePickerDelegate {

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
            
            if (message == "") {
                print("nothing")
            } else {
                addInstantMessageService(to: contactIdentifier!, identityKey: message)
                nextButton.isHidden = false
            }
        }
    }
}

