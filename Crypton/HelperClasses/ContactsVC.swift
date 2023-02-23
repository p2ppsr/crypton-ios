//
//  ContactsVC.swift
//  Crypton
//
//  Created by Brayden Langley on 2/23/23.
//

import UIKit
import Contacts
import ContactsUI

// Delegate for notifiying the mainVC of the user's action
protocol ContactsViewControllerDelegate: AnyObject {
    func didSelectContact(_ contact: CNContact, vc: UIViewController)
    func didSelectAddContact()
}

class ContactsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate  {

    var contacts = [CNContact]()
    let contactStore = CNContactStore()
    var allContacts = [CNContact]()
    var filteredContacts = [CNContact]()
    let searchController = UISearchController(searchResultsController: nil)
    weak var delegate: ContactsViewControllerDelegate?
    
    @IBOutlet var tableView: UITableView!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Make the top nav bar transparent
        navigationController?.navigationBar.barTintColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0)
        
        // Configure the search bar delegate and style
        searchController.searchResultsUpdater = self
        searchController.searchBar.searchTextField.backgroundColor = .black
        searchController.searchBar.searchTextField.textColor = .white
        searchController.searchResultsUpdater = self
        searchController.searchBar.searchBarStyle = .minimal
        searchController.searchBar.tintColor = defaultTint
        tableView.tableHeaderView = searchController.searchBar
        
        if let searchBarTextField = searchController.searchBar.value(forKey: "searchField") as? UITextField {
            searchBarTextField.attributedPlaceholder = NSAttributedString(string: "Search Contacts", attributes: [NSAttributedString.Key.foregroundColor: UIColor.gray])
        }
        
        // Request access to the user's contacts
        contactStore.requestAccess(for: .contacts) { (granted, error) in
            if granted {
                // Retrieve contacts
                let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactInstantMessageAddressesKey] as [CNKeyDescriptor]
                let request = CNContactFetchRequest(keysToFetch: keys)
                do {
                    try self.contactStore.enumerateContacts(with: request, usingBlock: { (contact, stop) in
                        self.contacts.append(contact)
                    })
                    // Reload table view data on the main thread
                    DispatchQueue.main.async {
                        self.tableView.reloadData()
                    }
                } catch let error {
                    print("Error retrieving contacts: \(error.localizedDescription)")
                }
            } else {
                print("Access to contacts denied.")
            }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        allContacts = fetchContacts()
        tableView.reloadData()
    }
    
    // MARK: - Helper Methods
    
    private func fetchContacts() -> [CNContact] {
        let store = CNContactStore()
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactInstantMessageAddressesKey] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys as [CNKeyDescriptor])
        request.sortOrder = CNContactSortOrder.userDefault
        var contacts = [CNContact]()
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                contacts.append(contact)
            }
        } catch {
            print("Error fetching contacts: \(error.localizedDescription)")
        }
        return contacts
    }
    
    // Figure out if the contacts are filtered or not
    func getContact(index: Int) -> CNContact {
        let contact: CNContact
        if isFiltering() {
            contact = filteredContacts[index]
        } else {
            contact = allContacts[index]
        }
        return contact
    }
    
    // MARK: - UITableViewDataSource
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if isFiltering() {
            return filteredContacts.count
        } else {
            return allContacts.count
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let contact = getContact(index: indexPath.row)
        
        cell.textLabel?.text = "\(contact.givenName) \(contact.familyName)"
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let contact = getContact(index: indexPath.row)
        
        // Do something with selected contact
        searchController.dismiss(animated: true) {
            self.delegate?.didSelectContact(contact, vc: self)
        }
    }
    
    @objc func addNewContact() {
        delegate?.didSelectAddContact()
    }
}

// MARK: - UISearchResultsUpdating

extension ContactsViewController: UISearchResultsUpdating {
    
    func updateSearchResults(for searchController: UISearchController) {
        let searchBar = searchController.searchBar
        filterContentForSearchText(searchBar.text!)
    }
    
    private func filterContentForSearchText(_ searchText: String) {
        filteredContacts = allContacts.filter { contact in
            let name = "\(contact.givenName) \(contact.familyName)"
            return name.lowercased().contains(searchText.lowercased())
        }
        tableView.reloadData()
    }
    
    private func isFiltering() -> Bool {
        return searchController.isActive && !searchBarIsEmpty()
    }
    
    private func searchBarIsEmpty() -> Bool {
        return searchController.searchBar.text?.isEmpty ?? true
    }
}
