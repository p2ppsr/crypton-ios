//
//  QRHelper.swift
//  Crypton
//
//  Created by Brayden Langley on 2/13/23.
//

import Foundation
import UIKit
import CoreImage
import BabbageSDK

// The larger the number the smaller the logo
let logoScaleFactor:CGFloat = 230.0
let defaultRed: CGFloat = 0x00 / 255.0 // 131/255
let defaultGreen: CGFloat = 0xeb / 255.0 //228/255
let defaultBlue: CGFloat = 0xb3 / 255.0 //150/255

let identityRed: CGFloat = 0x89 / 255.0 // 131/255
let identityGreen: CGFloat = 0xea / 255.0 //228/255
let identityBlue: CGFloat = 0xb2 / 255.0 //150/255
let userDefaults = UserDefaults.standard

func generateQRCode(from string: String, centerImage: UIImage?, color: String? = "Default") -> UIImage? {
    let data = string.data(using: String.Encoding.ascii)
    
    if let filter = CIFilter(name: "CIQRCodeGenerator") {
      filter.setValue(data, forKey: "inputMessage")
      let transform = CGAffineTransform(scaleX: 10, y: 10)
      
      // Convert the image to a format that can be saved on the device
      if let output = filter.outputImage?.transformed(by: transform) {
          
          let colorFilter = CIFilter(name: "CIFalseColor")
          if (color == "CryptonGreen") {
              colorFilter?.setDefaults()
              colorFilter?.setValue(output, forKey: "inputImage")
              colorFilter?.setValue(CIColor(red: identityRed, green: identityGreen, blue: identityBlue), forKey: "inputColor0")
              colorFilter?.setValue(CIColor(red: 0, green: 0, blue: 0), forKey: "inputColor1")
          }
          
          let context = CIContext()
          guard let cgImage = context.createCGImage(colorFilter?.outputImage ?? output, from: output.extent) else { return nil }
          let qrCodeImage = UIImage(cgImage: cgImage)
          
          if let centerImage = centerImage {
              let size = qrCodeImage.size
              
              UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
              qrCodeImage.draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
              
              let x = (size.width - (centerImage.size.width - logoScaleFactor)) / 2
              let y = (size.height - (centerImage.size.height - logoScaleFactor)) / 2
              centerImage.draw(in: CGRect(x: x, y: y, width: centerImage.size.width - logoScaleFactor, height: centerImage.size.height - logoScaleFactor))
              
              let result = UIGraphicsGetImageFromCurrentImageContext()
              UIGraphicsEndImageContext()
              
              return result
          } else {
              return qrCodeImage
          }
      }
    }
    
    return nil
}

func showErrorMessage(vc: UIViewController, error: Error) {
    let errorDescription:String = (error as! BabbageError).description
    // Create a new alert
    showCustomAlert(vc: vc, title: "Error", description: errorDescription)
}

func showCustomAlert(vc: UIViewController, title: String = "Alert", singleButtonMode: Bool = true, description: String, customOkayButtonLabel:String = "OK") {
    let alertVC = vc.storyboard?.instantiateViewController(withIdentifier: "CustomAlertVC") as! CustomAlertVC
    alertVC.customTitle = title
    alertVC.customDescription = description
    alertVC.customOkayButtonTitle = customOkayButtonLabel
    alertVC.singleButton = singleButtonMode
    alertVC.modalPresentationStyle = .overCurrentContext
    alertVC.modalTransitionStyle = .coverVertical
    alertVC.delegate = vc as? any CustomAlertVCDelegate
    vc.present(alertVC, animated: true, completion: nil)
}
