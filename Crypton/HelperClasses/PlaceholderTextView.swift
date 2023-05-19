//
//  PlaceholderTextView.swift
//  Crypton
//
//  Created by Brayden Langley on 2/13/23.
//

import Foundation
import UIKit

class PlaceholderTextView: UITextView {
    var decreaseAmount = 185.0
    var repositionAmount = 50.0
    
    var placeholder: String = "Enter the text, or scan the QR code, that you would like to encrypt or decrypt!"
    
    init(placeholder: String) {
        super.init(frame: .zero, textContainer: nil)
        self.text = placeholder
        self.textColor = .lightGray
        self.delegate = self
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.text = placeholder
        self.textColor = .lightText
        self.delegate = self
        
        // Add an observer to scroll the content up when editing
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChangeFrame(notification:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }
    
    // Dismiss the keyboard only if the textField is first responder.
    @objc func handleTap(sender: UITapGestureRecognizer) {
        if self.isFirstResponder {
            self.superview?.endEditing(true)
        } else {
            self.superview?.endEditing(true)
            self.becomeFirstResponder()
        }
    }
    
    // Callback for moving the keyboard content up
    @objc func keyboardWillChangeFrame(notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }
        
        let keyboardHeight = (self.superview?.bounds.height ?? 1000) - keyboardFrame.origin.y - 28
        let contentInset = UIEdgeInsets(top: 0, left: 0, bottom: keyboardHeight, right: 0)
        
        self.contentInset = contentInset
        self.scrollIndicatorInsets = contentInset
        
        let bottomOffset = CGPoint(x: 0, y: 0)
        self.setContentOffset(bottomOffset, animated: true)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// Extensions to add a placeholder text to the view
extension PlaceholderTextView: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView.text == placeholder {
            textView.text = ""
        }
    }
    func textViewDidEndEditing(_ textView: UITextView) {
        if textView.text == "" {
            textView.text = placeholder
            textView.textColor = .lightGray
        }
    }
    func textViewShouldEndEditing(_ textView: UITextView) -> Bool {
        textView.resignFirstResponder()
        return true
    }
}
