//
//  PlaceholderTextView.swift
//  Crypton
//
//  Created by Brayden Langley on 2/13/23.
//

import Foundation
import UIKit

class PlaceholderTextView: UITextView {
    
    let placeholder: String = "Enter the text you'd like to encrypt"
    
    init(placeholder: String) {
        super.init(frame: .zero, textContainer: nil)
        self.text = placeholder
        self.textColor = .lightGray
//        self.font = .systemFont(ofSize: 14)
        self.delegate = self
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.text = placeholder
        self.textColor = .lightGray
//        self.font = .systemFont(ofSize: 14)
        self.delegate = self
        
        // Setup a tap gesture for dynamically dismissing the keybaord
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tapGesture.cancelsTouchesInView = false
        self.addGestureRecognizer(tapGesture)
    }
    
    // Dismiss the keyboard only if the textField is first responder.
    @objc func handleTap(sender: UITapGestureRecognizer) {
        if self.isFirstResponder {
            self.resignFirstResponder()
        } else {
            self.becomeFirstResponder()
        }
    }
}

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
