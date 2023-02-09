//
//  DecryptorVC.swift
//  Crypton
//
//  Created by Brayden Langley on 2/9/23.
//

import Foundation
import UIKit
import BabbageSDK
import GenericJSON

import AVFoundation

class DecryptorVC: UIViewController, AVCapturePhotoCaptureDelegate, AVCaptureMetadataOutputObjectsDelegate {
    
    let PROTOCOL_ID = "crypton"
    let KEY_ID = "1"
    var sdk:BabbageSDK = BabbageSDK(webviewStartURL: "https://staging-mobile-portal.babbage.systems")
    
    @IBOutlet weak var previewView: UIView!
    @IBOutlet var textView: UITextView!
    var secureQRCode: UIImage?
    
    // TODO: Figure out what is actually need here!
    var imagePicker: ImagePicker!
    var isSelectingRecipient = false
    
//    var imageOrientation: AVCaptureVideoOrientation?
//    var captureSession: AVCaptureSession?
//    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
//    var capturePhotoOutput: AVCapturePhotoOutput?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        sdk.setParent(parent: self)
        
        self.imagePicker = ImagePicker(presentationController: self, delegate: self)
        self.imagePicker.present(from: self.view)
        
        // Get an instance of the AVCaptureDevice class to initialize a
        // device object and provide the video as the media type parameter
//        guard let captureDevice = AVCaptureDevice.default(for: AVMediaType.video) else {
////            fatalError("No video device found")
//            return
//        }
        // handler chiamato quando viene cambiato orientamento
//        self.imageOrientation = AVCaptureVideoOrientation.portrait
//
//        do {
//            // Get an instance of the AVCaptureDeviceInput class using the previous deivce object
//            let input = try AVCaptureDeviceInput(device: captureDevice)
//
//            // Initialize the captureSession object
//            captureSession = AVCaptureSession()
//
//            // Set the input device on the capture session
//            captureSession?.addInput(input)
//
//            // Get an instance of ACCapturePhotoOutput class
//            capturePhotoOutput = AVCapturePhotoOutput()
//            capturePhotoOutput?.isHighResolutionCaptureEnabled = true
//
//            // Set the output on the capture session
//            captureSession?.addOutput(capturePhotoOutput!)
//            captureSession?.sessionPreset = .high
//
//            // Initialize a AVCaptureMetadataOutput object and set it as the input device
//            let captureMetadataOutput = AVCaptureMetadataOutput()
//            captureSession?.addOutput(captureMetadataOutput)
//
//            // Set delegate and use the default dispatch queue to execute the call back
//            captureMetadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
//            captureMetadataOutput.metadataObjectTypes = [AVMetadataObject.ObjectType.qr]
//
//            //Initialise the video preview layer and add it as a sublayer to the viewPreview view's layer
//            videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
//            videoPreviewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
//            videoPreviewLayer?.frame = view.layer.bounds
//            previewView.layer.addSublayer(videoPreviewLayer!)
//
//        } catch {
//            //If any error occurs, simply print it out
//            print(error)
//            return
//        }
    }
    
    // Gets a QRCode to decrypt
    @IBAction func scanQRCode(_ sender: UIButton) {
        
//        if (sender.restorationIdentifier == "recipientBtn") {
//            isSelectingRecipient = true
//        } else {
//            isSelectingRecipient = false
//        }
        self.imagePicker.present(from: sender)
//        imagePicker.allowsEditing = false
//        imagePicker.sourceType = .photoLibrary
//
//        present(imagePicker, animated: true, completion: nil)
        
//        if (captureSession?.isRunning == true) {
//            captureSession?.stopRunning()
//        } else {
//            captureSession?.startRunning()
//        }
//        previewView.isHidden = !previewView.isHidden
    }
    
    // Figures out if counterparty is self
//    func getCounterparty() -> String {
//        var counterparty = "self"
//        if (counterpartyTextField.text != "") {
//            counterparty = counterpartyTextField.text!
//        }
//        return counterparty
//    }
    
    @IBAction func decrypt(_ sender: UIButton) {
        Task.init {
            textView.text = await sdk.decrypt(ciphertext: self.textView.text, protocolID: PROTOCOL_ID, keyID: KEY_ID, counterparty: "self")
        }
    }

}

extension DecryptorVC: ImagePickerDelegate {

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
            }else{
                print("message: \(message)")
                Task.init {
//                    let decryptedText = await sdk.decrypt(ciphertext: message, protocolID: PROTOCOL_ID, keyID: KEY_ID, counterparty: getCounterparty())
//                    if (isSelectingRecipient) {
//                        counterpartyTextField.text = message
//                    } else {
                        textView.text = message
//                    }
                }
            }
        }
    }
}
