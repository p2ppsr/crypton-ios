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
              colorFilter?.setValue(CIColor(red: 131/255, green: 228/255, blue: 150/255), forKey: "inputColor0")
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
    let dialogMessage = UIAlertController(title: "Error", message: errorDescription, preferredStyle: .alert)
    dialogMessage.addAction(UIAlertAction(title: "OK", style: .default, handler: { (action) -> Void in
     }))
    // Present alert to user
    vc.present(dialogMessage, animated: true, completion: nil)
}

//func generateGreenQRCode(from string: String, centerImage: UIImage?) -> UIImage? {
//    let data = string.data(using: String.Encoding.ascii)
//
//    if let filter = CIFilter(name: "CIQRCodeGenerator") {
//        filter.setValue(data, forKey: "inputMessage")
//        let transform = CGAffineTransform(scaleX: 10, y: 10)
//
//        // Convert the image to a format that can be saved on the device
//        if let output = filter.outputImage?.transformed(by: transform) {
//            let colorFilter = CIFilter(name: "CIFalseColor")
//            colorFilter?.setDefaults()
//            colorFilter?.setValue(output, forKey: "inputImage")
//            colorFilter?.setValue(CIColor(red: 131/255, green: 228/255, blue: 150/255), forKey: "inputColor0")
//            colorFilter?.setValue(CIColor(red: 0, green: 0, blue: 0), forKey: "inputColor1")
//
//            let context = CIContext()
//            guard let cgImage = context.createCGImage(colorFilter?.outputImage ?? output, from: output.extent) else { return nil }
//            let qrCodeImage = UIImage(cgImage: cgImage)
//
//            // Add a center logo
//            if let centerImage = centerImage {
//                let size = qrCodeImage.size
//
//                UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
//                qrCodeImage.draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
//
//                let x = (size.width - (centerImage.size.width - logoScaleFactor)) / 2
//                let y = (size.height - (centerImage.size.height - logoScaleFactor)) / 2
//                centerImage.draw(in: CGRect(x: x, y: y, width: centerImage.size.width - logoScaleFactor, height: centerImage.size.height - logoScaleFactor))
//
//                let result = UIGraphicsGetImageFromCurrentImageContext()
//                UIGraphicsEndImageContext()
//
//                return result
//            } else {
//                return qrCodeImage
//            }
//
//            UIGraphicsBeginImageContextWithOptions(qrCodeImage.size, false, qrCodeImage.scale)
//            let path = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: qrCodeImage.size.width, height: qrCodeImage.size.height), cornerRadius: 10)
//            path.addClip()
//            qrCodeImage.draw(in: CGRect(x: 10, y: 10, width: qrCodeImage.size.width - 20, height: qrCodeImage.size.height - 20))
//            path.lineWidth = 20
//            UIColor.black.setStroke()
//            path.stroke()
//            let roundedQRCode = UIGraphicsGetImageFromCurrentImageContext()
//            UIGraphicsEndImageContext()
//
//            return roundedQRCode
//        }
//    }
//    return nil
//}

extension CIImage {
//    var transparent: CIImage? {
//        return inverted?.blackTransparent
//    }
//
//    var inverted: CIImage? {
//        guard let invertedColorFilter = CIFilter(name: "CIColorInvert") else { return nil }
//        invertedColorFilter.setValue(self, forKey: "inputImage")
//        return invertedColorFilter.outputImage
//    }
//
//    var blackTransparent: CIImage? {
//        guard let blackTransparentCIFilter = CIFilter(name: "CIMaskToAlpha") else { return nil }
//        blackTransparentCIFilter.setValue(self, forKey: "inputImage")
//        return blackTransparentCIFilter.outputImage
//    }
//
//    func tinted(using color: UIColor) -> CIImage?
//    {
//        guard
//            let transparentQRImage = transparent,
//            let filter = CIFilter(name: "CIMultiplyCompositing"),
//            let colorFilter = CIFilter(name: "CIConstantColorGenerator") else { return nil }
//
//        let ciColor = CIColor(color: color)
//        colorFilter.setValue(ciColor, forKey: kCIInputColorKey)
//        let colorImage = colorFilter.outputImage
//        filter.setValue(colorImage, forKey: kCIInputImageKey)
//        filter.setValue(transparentQRImage, forKey: kCIInputBackgroundImageKey)
//        return filter.outputImage!
//    }
    
    func addLogo(with image: CIImage) -> CIImage? {
        guard let combinedFilter = CIFilter(name: "CISourceOverCompositing") else { return nil }
        let centerTransform = CGAffineTransform(translationX: extent.midX - (image.extent.size.width / 2), y: extent.midY - (image.extent.size.height / 2))
        combinedFilter.setValue(image.transformed(by: centerTransform), forKey: "inputImage")
        combinedFilter.setValue(self, forKey: "inputBackgroundImage")
        return combinedFilter.outputImage!
    }
}
