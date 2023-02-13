//
//  EncryptorVC.swift
//  Crypton
//
//  Created by Brayden Langley on 2/9/23.
//

import Foundation
import BabbageSDK
import GenericJSON
import UIKit
import AVFoundation

/**
  View Controller responsible for encrypting messages
 */
class EncryptorVC: UIViewController, AVCapturePhotoCaptureDelegate, AVCaptureMetadataOutputObjectsDelegate {
    
    let PROTOCOL_ID = "crypton"
    let KEY_ID = "1"
    var sdk:BabbageSDK = BabbageSDK(webviewStartURL: "https://staging-mobile-portal.babbage.systems")
    
    var secureQRCode:UIImage!
    @IBOutlet var textView: PlaceholderTextView!
    @IBOutlet var counterpartyTextField: UITextField!
    @IBOutlet var previewView: UIView!
    @IBOutlet var qrScannerView: UIView!
    
    // These are needed for live QR code capture
    var imageOrientation: AVCaptureVideoOrientation?
    var captureSession: AVCaptureSession?
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    var capturePhotoOutput: AVCapturePhotoOutput?
    
    var imagePicker: ImagePicker!
    
//    private lazy var counterpartyTextField: UITextField = {
//        let textField = UITextField()
//        textField.borderStyle = .roundedRect
//
//        textField.placeholder = "Login"
//        return textField
//    }()
//    private lazy var counterpartyTextField: UIButton = {
//        let button = UIButton()
//        button.configuration = .filled()
//        button.layer.cornerRadius = 8
//        button.translatesAutoresizingMaskIntoConstraints = false
//        button.backgroundColor = UIColor.blue
//        button.setTitle("Login", for: .normal)
//        return button
//    }()
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.imagePicker = ImagePicker(presentationController: self, delegate: self)
//        let buttonBottom = view.keyboardLayoutGuide.topAnchor.constraint(equalToSystemSpacingBelow: counterpartyTextField.bottomAnchor, multiplier: 1.0)
//        let buttonTrailing = view.keyboardLayoutGuide.trailingAnchor.constraint(equalToSystemSpacingAfter: counterpartyTextField.trailingAnchor, multiplier: 1.0)
//        NSLayoutConstraint.activate([buttonBottom, buttonTrailing])
        
//        view.keyboardLayoutGuide.followsUndockedKeyboard = true
    }
    
    
    private func addcounterpartyTextFieldConstraints() {
        let buttonDockedTrailing = view.keyboardLayoutGuide.trailingAnchor.constraint(equalToSystemSpacingAfter: counterpartyTextField.trailingAnchor, multiplier: 2.0)
        buttonDockedTrailing.identifier = "buttonDockedTrailing"
        view.keyboardLayoutGuide.setConstraints([buttonDockedTrailing], activeWhenNearEdge: .bottom)
//
        let buttonCenterX = view.keyboardLayoutGuide.centerXAnchor.constraint(equalTo: counterpartyTextField.centerXAnchor)
        buttonCenterX.identifier = "buttonCenterX"
        view.keyboardLayoutGuide.setConstraints([buttonCenterX], activeWhenAwayFrom: [.leading, .trailing, .bottom])

//        let buttonUndockedTrailing = view.keyboardLayoutGuide.trailingAnchor.constraint(
//            equalToSystemSpacingAfter: counterpartyTextField.trailingAnchor, multiplier: 1.0)
//        buttonUndockedTrailing.identifier = "buttonUndockedTrailing"
//        view.keyboardLayoutGuide.setConstraints([buttonUndockedTrailing], activeWhenNearEdge: .trailing)

//        let buttonUndockedLeading = counterpartyTextField.leadingAnchor.constraint(
//            equalToSystemSpacingAfter: view.keyboardLayoutGuide.leadingAnchor, multiplier: 1.0)
//        buttonUndockedLeading.identifier = "buttonUndockedLeading"
//        view.keyboardLayoutGuide.setConstraints([buttonUndockedLeading], activeWhenNearEdge: .leading)

        let buttonTop = view.keyboardLayoutGuide.topAnchor.constraint(equalToSystemSpacingBelow: counterpartyTextField.bottomAnchor, multiplier: 18.0)
        buttonTop.identifier = "buttonTop"
        view.keyboardLayoutGuide.setConstraints([buttonTop], activeWhenAwayFrom: .top)

//        let buttonBottom = counterpartyTextField.topAnchor.constraint(equalToSystemSpacingBelow: view.keyboardLayoutGuide.bottomAnchor, multiplier: 2.0)
//        buttonBottom.identifier = "buttonBottom"
//        view.keyboardLayoutGuide.setConstraints([buttonBottom], activeWhenNearEdge: .top)
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
        
        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing))
        view.addGestureRecognizer(tap)
        
        counterpartyTextField.attributedPlaceholder = NSAttributedString(string: "Recipient identity key",attributes: [NSAttributedString.Key.foregroundColor: UIColor.gray])
        
        counterpartyTextField.translatesAutoresizingMaskIntoConstraints = false
        view.keyboardLayoutGuide.followsUndockedKeyboard = true
        self.addcounterpartyTextFieldConstraints()
     }

    // Encrypts the text from the textview
    @IBAction func encrypt(_ sender: Any) {
        
        if (textView.text == textView.placeholder) {
            // Create a new alert
            let dialogMessage = UIAlertController(title: "Error", message: "Please enter a message to encrypt!", preferredStyle: .alert)
            dialogMessage.addAction(UIAlertAction(title: "OK", style: .default, handler: { (action) -> Void in
             }))
            // Present alert to user
            self.present(dialogMessage, animated: true, completion: nil)
            return
        }
        
        Task.init {
            let encryptedText = await sdk.encrypt(plaintext: textView.text, protocolID: PROTOCOL_ID, keyID: KEY_ID, counterparty: getCounterparty())
            textView.text = encryptedText
            
            let QRCodeImage = generateQRCode(from: encryptedText, centerImage: UIImage(named: "encryptedQRLogo"))
            self.secureQRCode = QRCodeImage
            
            if let vc = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "resultsVC") as? ResultsVC {
                vc.secureQRCode = QRCodeImage
                self.navigationController?.pushViewController(vc, animated: true)
            }
        }
    }
    
    // Figures out if counterparty is self
    func getCounterparty() -> String {
        var counterparty = "self"
        if (counterpartyTextField.text != "") {
            counterparty = counterpartyTextField.text!
        }
        return counterparty
    }
    
    @IBAction func toggleQRScanner(_ sender: UIButton) {
        if (captureSession?.isRunning == true) {
            captureSession?.stopRunning()
            qrScannerView.isHidden = true
        } else {
//            captureSession?.startRunning()
            self.imagePicker.present(from: sender)
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let vc = segue.destination as? ResultsVC else { return }
        vc.qrCodeImageView.image = secureQRCode
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

                counterpartyTextField.text = outputString
                DispatchQueue.main.async {
                    self.qrScannerView.isHidden = true
                    self.captureSession?.stopRunning()
                }
            }
        }
        
    }
}


extension EncryptorVC: ImagePickerDelegate {

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
                counterpartyTextField.text = message
            }
        }
    }
}
