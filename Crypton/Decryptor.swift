//
//  InstantDecryptor.swift
//  Crypton
//
//  Created by Brayden Langley on 2/10/23.
//

import Foundation
import UIKit
import BabbageSDK
import GenericJSON

import AVFoundation

class Decryptor: UIViewController, AVCapturePhotoCaptureDelegate, AVCaptureMetadataOutputObjectsDelegate {
    
    let PROTOCOL_ID = "crypton"
    let KEY_ID = "1"
    var counterparty:String = "self"
    var sdk:BabbageSDK = BabbageSDK(webviewStartURL: "https://staging-mobile-portal.babbage.systems") // TODO: Switch to prod before release
    
    @IBOutlet var previewView: UIView!
    @IBOutlet var qrScannerView: UIView!
    @IBOutlet var textView: PlaceholderTextView!
    var secureQRCode: UIImage?
    
    
    var imagePicker: ImagePicker!
//    var isSelectingRecipient = false
    
    // These are needed for live QR code capture
    var imageOrientation: AVCaptureVideoOrientation?
    var captureSession: AVCaptureSession?
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    var capturePhotoOutput: AVCapturePhotoOutput?
    
    private let sessionQueue = DispatchQueue(label: "session queue", qos: .background, attributes: [], autoreleaseFrequency: .workItem)
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.imagePicker = ImagePicker(presentationController: self, delegate: self)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Get an instance of the AVCaptureDevice class to initialize a
        // device object and provide the video as the media type parameter
        guard let captureDevice = AVCaptureDevice.default(for: AVMediaType.video) else {
            return
        }
        self.imageOrientation = AVCaptureVideoOrientation.portrait

        do {
            // Get an instance of the AVCaptureDeviceInput class using the previous deivce object
            let input = try AVCaptureDeviceInput(device: captureDevice)

            // Initialize the captureSession object
            captureSession = AVCaptureSession()
            // Set the input device on the capture session
            captureSession?.addInput(input)

            // Get an instance of ACCapturePhotoOutput class
//            capturePhotoOutput = AVCapturePhotoOutput()
//            capturePhotoOutput?.isHighResolutionCaptureEnabled = true
//
//            // Set the output on the capture session
//            captureSession?.addOutput(capturePhotoOutput!)
            captureSession?.sessionPreset = .high

            //Initialise the video preview layer and add it as a sublayer to the viewPreview view's layer
            videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
            videoPreviewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
            videoPreviewLayer?.frame = view.layer.bounds
            previewView.layer.addSublayer(videoPreviewLayer!)

//            sessionQueue.async {
            self.captureSession?.startRunning()
            self.captureSession?.stopRunning()
//              }
            
            // Crop the cature window
            let captureMetadataOutput = AVCaptureMetadataOutput()
            captureMetadataOutput.rectOfInterest = (videoPreviewLayer?.metadataOutputRectConverted(fromLayerRect: previewView.frame))!
            captureSession?.addOutput(captureMetadataOutput)
            
            // Set delegate and use the default dispatch queue to execute the call back
            captureMetadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            captureMetadataOutput.metadataObjectTypes = [AVMetadataObject.ObjectType.qr]

        } catch {
            //If any error occurs, simply print it out
            print(error)
            return
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        sdk.setParent(parent: self)
        previewView.layer.cornerRadius = 50
        previewView.layer.masksToBounds = true
        qrScannerView.isHidden = true
        
        // Dimiss active keyboard
//        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing)) // TODO: Reuse code from encryptor textView...
//        view.addGestureRecognizer(tap)
    }
    
    // Find a camera with the specified AVCaptureDevicePosition, returning nil if one is not found
    func cameraWithPosition(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: AVMediaType.video, position: .unspecified)
        for device in discoverySession.devices {
            if device.position == position {
                return device
            }
        }
        
        return nil
    }
    
    func metadataOutput(_ captureOutput: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        // Check if the metadataObjects array is contains at least one object.
        if metadataObjects.count == 0 {
            return
        }
        
        // Get the metadata object.
        let metadataObj = metadataObjects[0] as! AVMetadataMachineReadableCodeObject
        
        if metadataObj.type == AVMetadataObject.ObjectType.qr {
            if let outputString = metadataObj.stringValue {
                
                Task.init {
                    textView.text = await sdk.decrypt(ciphertext: outputString, protocolID: PROTOCOL_ID, keyID: KEY_ID, counterparty: "self")
                }
                
                DispatchQueue.main.async {
                    self.qrScannerView.isHidden = true
                    self.captureSession?.stopRunning()
                }
            }
        }
        
    }
    
    // Gets a QRCode to decrypt
    @IBAction func toggleQRScanner(_ sender: UIButton) {
        
//        if (sender.restorationIdentifier == "recipientBtn") {
//            isSelectingRecipient = true
//        } else {
//            isSelectingRecipient = false
//        }
        
//        self.imagePicker.present(from: sender) ///////////////////////////
        
//        imagePicker.allowsEditing = false
//        imagePicker.sourceType = .photoLibrary
//
        
        
        if (captureSession?.isRunning == true) {
            captureSession?.stopRunning()
            qrScannerView.isHidden = true
        } else {
//            captureSession?.startRunning()
            self.imagePicker.present(from: sender)
        }
//        qrScannerView.isHidden = !qrScannerView.isHidden
    }
    
    // Figures out if counterparty is self
//    func getCounterparty() -> String {
//        var counterparty = "self"
//        if (counterpartyTextField.text != "") {
//            counterparty = counterpartyTextField.text!
//        }
//        return counterparty
//    }
    
    @IBAction func decrypt(_ sender: Any) {
        Task.init {
            textView.text = await sdk.decrypt(ciphertext: self.textView.text, protocolID: PROTOCOL_ID, keyID: KEY_ID, counterparty: "self")
        }
    }
}

extension Decryptor: ImagePickerDelegate {

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
                    let decryptedMessage = await sdk.decrypt(ciphertext: message, protocolID: PROTOCOL_ID, keyID: KEY_ID, counterparty: counterparty)
//                    if (isSelectingRecipient) {
//                        counterpartyTextField.text = message
//                    } else {
                        textView.text = decryptedMessage
//                    }
                }
            }
        }
    }
}
