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
}

extension PlaceholderTextView: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView.text == placeholder {
            textView.text = ""
        }
        
        textView.frame = CGRect(x: textView.frame.origin.x, y: textView.frame.origin.y - repositionAmount, width: textView.frame.width, height: textView.frame.height - decreaseAmount)
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        if textView.text == "" {
            textView.text = placeholder
            textView.textColor = .lightGray
        }
        textView.frame = CGRect(x: textView.frame.origin.x, y: textView.frame.origin.y + repositionAmount, width: textView.frame.width, height: textView.frame.height + decreaseAmount)
    }
    func textViewShouldEndEditing(_ textView: UITextView) -> Bool {
        textView.resignFirstResponder()
        return true
    }
}
