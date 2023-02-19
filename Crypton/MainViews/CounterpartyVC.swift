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

class CounterpartyVC: UIViewController, CNContactViewControllerDelegate, CNContactPickerDelegate, QRScannerDelegate  {
    @IBOutlet var nameLabel: UILabel?
    
    @IBOutlet var nextButton: UIButton!
    var identityKey:String?
    var contactIdentifier:String?
    
    var imagePicker: ImagePicker!
    var secureQRCode: UIImage?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.imagePicker = ImagePicker(presentationController: self, delegate: self)
    }
    func didScanQRCode(withData data: String) {
        addInstantMessageService(to: contactIdentifier!, identityKey: data)
        nextButton.isHidden = false
    }
    @IBAction func selectRecipient(sender: UIButton) {
        showContactPicker()
    }
    
    func showContactPicker() {
        let contactPicker = CNContactPickerViewController()
        contactPicker.delegate = self
        contactPicker.displayedPropertyKeys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactInstantMessageAddressesKey]
        
        self.present(contactPicker, animated: true, completion: nil)
    }
    
    func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
        // Handle the selected contact here
        let firstName = contact.givenName
        let lastName = contact.familyName
        let phoneNumber = contact.phoneNumbers.first?.value.stringValue ?? ""
        let contactIdentifier = contact.identifier
        print("Selected contact: \(firstName) \(lastName), phone number: \(phoneNumber)")
        
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let qrScannerVC = storyboard.instantiateViewController(withIdentifier: "qrScannerVC") as! QRScannerVC
        qrScannerVC.delegate = self
        self.contactIdentifier = contactIdentifier
        
//           if (contact.instantMessageAddresses.count == 0) {
//               DispatchQueue.main.async {
//                   self.present(qrScannerVC, animated: true)
//               }
//           } else {
//
//           }
        let metanetIdentityKey = contact.instantMessageAddresses.filter {
            $0.value.service == "MetaNet Identity Key"
        }
        if (((metanetIdentityKey.first?.value.username)) != nil) {
            identityKey = (metanetIdentityKey.first?.value.username) as String?
            nameLabel?.text = firstName + " " + lastName
            nextButton.isHidden = false
        } else {
            DispatchQueue.main.async {
                // Create a new alert
                let dialogMessage = UIAlertController(title: "New Counterparty", message: "Identity Key Not found!", preferredStyle: .alert)
                dialogMessage.addAction(UIAlertAction(title: "Select QR Code", style: .default, handler: { (action) -> Void in
                    self.imagePicker.present(from: self.view)
                 }))
                dialogMessage.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (action) -> Void in
                    // nothing
                 }))
                // Present alert to user
                self.present(dialogMessage, animated: true, completion: nil)
            }
        }
        
//           if (contact.instantMessageAddresses.count != 0) {
//               let metanetIdentityKey = contact.instantMessageAddresses.filter {
//                    $0.value.service == "MetaNet Identity Key"
//                }
//           } else {
//               // Prompt the user to scan / upload QR code
//
//               let storyboard = UIStoryboard(name: "Main", bundle: nil)
//               let qrScannerVC = storyboard.instantiateViewController(withIdentifier: "qrScannerVC") as! QRScannerVC
//               qrScannerVC.delegate = self
//               self.contactIdentifier = contactIdentifier
//
//               self.present(qrScannerVC, animated: true)
//           }
//           if (metanetIdentityKey.first?.value.username == nil) {
//
//           } else {
//               print((metanetIdentityKey.first?.value.username)! as String)
//           }
    }
    
    func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
        // Handle the cancelled contact picker here
        print("Contact picker cancelled")
    }
    
    
    func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
      guard let contact = contact else { // User tapped "Cancel"
        navigationController?.popViewController(animated: true)
        return
      }

      let store = CNContactStore()
      let saveRequest = CNSaveRequest()
      saveRequest.update(contact.mutableCopy() as! CNMutableContact)
      do {
        try store.execute(saveRequest)
        navigationController?.popViewController(animated: true)
      } catch {
        // Handle error
      }
    }
    
    func addInstantMessageService(to contactIdentifier: String, identityKey: String) {
        let store = CNContactStore()
        let keysToFetch = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey, CNContactInstantMessageAddressesKey]
        let fetchRequest = CNContactFetchRequest(keysToFetch: keysToFetch as [CNKeyDescriptor])
        fetchRequest.predicate = CNContact.predicateForContacts(withIdentifiers: [contactIdentifier])
        do {
            try store.enumerateContacts(with: fetchRequest) { (contact, stop) in
                // Create a new instant message address with a service and username
                let instantMessageAddress = CNInstantMessageAddress(username: identityKey, service: "MetaNet Identity Key")
                
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
                    
                    print("Contact updated with instant message service.")
                } catch let error {
                    print("Error saving contact: \(error)")
                }
            }
        } catch let error {
            print("Error fetching contacts: \(error)")
        }
    }
    
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
        self.secureQRCode = image!
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
            } else {
                addInstantMessageService(to: contactIdentifier!, identityKey: message)
                nextButton.isHidden = false
            }
        }
    }
}

