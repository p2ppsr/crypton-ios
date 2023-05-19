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
import BabbageSDK

class CounterpartyVC: UIViewController, CNContactViewControllerDelegate, CNContactPickerDelegate, ContactsViewControllerDelegate, QRScannerDelegate, CustomAlertVCDelegate  {
    
    func didSelectAddContact() {
        addNewContact()
    }
    
    func didSelectContact(_ contact: CNContact, vc: UIViewController) {
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
            if (!isValidPublicKey(identityKey: identityKey ?? "")) {
                self.dismiss(animated: true )
                showErrorMessage(vc: self, error: BabbageError(description: "Invalid Identity Key Found! \n Please delete the invalid key using the contacts app."))
                print("Invalid key")
                return
            }
            
            nameLabel?.text = firstName + " " + lastName
            nextButton.isHidden = false
        } else {
            isNewContact = true
            // Dismiss the current vc so the alert vc can be displayed
            promptUserForIdentityKey()
        }
        self.dismiss(animated: true )
    }
    
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
    
    func isValidPublicKey(identityKey: String) -> Bool {
        // Simple compressed public key validation
        // Note: Future validation can be more extensive
        if (identityKey != "" && identityKey.count == 66) {
            return true
        }
        return false
    }
    
    // Callback function for scanning QR code
    func didScanQRCode(withData data: String) {
        addInstantMessageService(to: contactIdentifier!, identityKey: data)
        nextButton.isHidden = false
    }
    
    @IBAction func selectCounterparty(sender: UIButton) {
        
        let contactsVC = self.storyboard?.instantiateViewController(withIdentifier: "ContactsVC") as! ContactsViewController
        contactsVC.delegate = self
        let newContactButton = UIBarButtonItem(barButtonSystemItem: .add, target: contactsVC, action: #selector(contactsVC.addNewContact))
        newContactButton.tintColor = defaultTint

        // Create a new navigation controller with ContactsViewController as the root view controller
        let navigationController = UINavigationController(rootViewController: contactsVC)
        navigationController.modalPresentationStyle = .popover

        let cancelButton = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(dismissView))
        cancelButton.tintColor = defaultTint

        // Set the newContactButton as the right bar button item for ContactsViewController
        contactsVC.navigationItem.rightBarButtonItem = newContactButton
        contactsVC.navigationItem.leftBarButtonItem = cancelButton

        // Present the navigation controller
        present(navigationController, animated: true, completion: nil)
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
    
    @objc func dismissView() {
        self.dismiss(animated: true)
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
            // Validate the existing identity key on the contact
            if (!isValidPublicKey(identityKey: identityKey ?? "")) {
                showErrorMessage(vc: self, error: BabbageError(description: "Invalid Identity Key!"))
                print("Invalid key")
                return
            }
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
        // Make sure the identity key provided is valid
        if (isValidPublicKey(identityKey: identityKey) == false) {
            // Dismiss the current view before showing the alert
            self.dismiss(animated: true )
            showErrorMessage(vc: self, error: BabbageError(description: "Invalid Identity Key!"))
            print("Invalid key")
            return
        }
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
                showErrorMessage(vc: self, error: BabbageError(description: "Unable to read QR code!"))
            } else {
                addInstantMessageService(to: contactIdentifier!, identityKey: message)
                nextButton.isHidden = false
            }
        }
    }
}

