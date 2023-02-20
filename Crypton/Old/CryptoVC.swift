////
////  CryptoVC.swift
////  Crypton
////
////  Created by Brayden Langley on 2/13/23.
////
//
//import Foundation
//import UIKit
//import BabbageSDK
//import GenericJSON
//import AVFoundation
//
//class CryptoVC: UIViewController, AVCapturePhotoCaptureDelegate, AVCaptureMetadataOutputObjectsDelegate, UITextFieldDelegate, UITextViewDelegate {
//    
//    let PROTOCOL_ID:JSON = [1, "crypton"]
//    let KEY_ID = "1"
//    var counterparty:String = "self"
//    var sdk:BabbageSDK = BabbageSDK(webviewStartURL: "https://mobile-portal.babbage.systems") // TODO: Switch to prod before release
//    
//    @IBOutlet var qrScannerView: UIView!
//    @IBOutlet var previewView: UIView!
//    @IBOutlet var counterpartyTextField: UITextField!
//    @IBOutlet var textView: PlaceholderTextView!
//    @IBOutlet var actionButton: UIButton!
//    
//    @IBOutlet var newScanBtn: UIButton!
//    
//    // These are needed for live QR code capture
//    var imageOrientation: AVCaptureVideoOrientation?
//    var captureSession: AVCaptureSession?
//    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
//    var capturePhotoOutput: AVCapturePhotoOutput?
//    
//    var secureQRCode: UIImage?
//    var imagePicker: ImagePicker!
//    var isSelectingRecipient:Bool = false
//
//    // What cryptography action is being taken?
//    var action:String = "Encrypt"
//    
////    private let sessionQueue = DispatchQueue(label: "session queue", qos: .background, attributes: [], autoreleaseFrequency: .workItem)
//    
//    override func viewWillAppear(_ animated: Bool) {
//        super.viewWillAppear(animated)
//        self.imagePicker = ImagePicker(presentationController: self, delegate: self)
//        
//        // Configure the context specific UI elements
//        if (action == "Encrypt") {
//            self.navigationItem.title = "Encryptor"
//            newScanBtn.isHidden = true
//        } else {
//            self.navigationItem.title = "Decryptor"
//        }
//    }
//    
//    override func viewDidAppear(_ animated: Bool) {
//        super.viewDidAppear(animated)
//        // Get an instance of the AVCaptureDevice class to initialize a
//        // device object and provide the video as the media type parameter
//        guard let captureDevice = AVCaptureDevice.default(for: AVMediaType.video) else {
//            return
//        }
//        self.imageOrientation = AVCaptureVideoOrientation.portrait
//
//        do {
//            // Get an instance of the AVCaptureDeviceInput class using the previous deivce object
//            let input = try AVCaptureDeviceInput(device: captureDevice)
//
//            // Initialize the captureSession object
//            captureSession = AVCaptureSession()
//            // Set the input device on the capture session
//            captureSession?.addInput(input)
//            captureSession?.sessionPreset = .high
//
//            //Initialise the video preview layer and add it as a sublayer to the viewPreview view's layer
//            videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
//            videoPreviewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
//            videoPreviewLayer?.frame = view.layer.bounds
//            previewView.layer.addSublayer(videoPreviewLayer!)
//
////            sessionQueue.async {
//                self.captureSession?.startRunning()
//                self.captureSession?.stopRunning()
////              }
//            
//            // Crop the cature window
//            let captureMetadataOutput = AVCaptureMetadataOutput()
//            captureMetadataOutput.rectOfInterest = (videoPreviewLayer?.metadataOutputRectConverted(fromLayerRect: previewView.frame))!
//            captureSession?.addOutput(captureMetadataOutput)
//            
//            // Set delegate and use the default dispatch queue to execute the call back
//            captureMetadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
//            captureMetadataOutput.metadataObjectTypes = [AVMetadataObject.ObjectType.qr]
//
//        } catch {
//            //If any error occurs, simply print it out
//            print(error)
//            return
//        }
//    }
//    
//    override func viewDidLoad() {
//        super.viewDidLoad()
//        sdk.setParent(parent: self)
//        previewView.layer.cornerRadius = 50
//        previewView.layer.masksToBounds = true
//        qrScannerView.isHidden = true
//        
//        // Setup a tap gesture for dynamically dismissing the keybaord
//        let tapGesture1 = UITapGestureRecognizer(target: self, action: #selector(handleTap))
//        let tapGesture2 = UITapGestureRecognizer(target: self, action: #selector(handleTap))
//        tapGesture1.cancelsTouchesInView = false
//        tapGesture2.cancelsTouchesInView = false
//        textView.addGestureRecognizer(tapGesture1)
//        counterpartyTextField.addGestureRecognizer(tapGesture2)
//        
//        counterpartyTextField.delegate = self
//        counterpartyTextField.returnKeyType = .done
//        
//        // why isn't this working?
//        actionButton.setTitle(action, for: .normal)
//        actionButton.titleLabel?.font = UIFont(name: "Menlo-Regular", size: 19)
//        
//        if (action == "Decrypt") {
//            var configuration = UIButton.Configuration.filled()
//            configuration.cornerStyle = .medium
//            configuration.baseBackgroundColor = .black
//            configuration.baseForegroundColor = .white
//            actionButton.configuration = configuration
//            actionButton.isHidden = true
//            textView.placeholder = "Enter the text, or scan the QR code, that you would like to decrypt!"
//            textView.text = "Enter the text, or scan the QR code, that you would like to decrypt!"
//        }
//        
//        // Configure the counterparty textField
//        let placeholderAttributes: [NSAttributedString.Key: Any] = [
//            .font: UIFont.systemFont(ofSize: 18),
//            .foregroundColor: UIColor.gray
//        ]
//        counterpartyTextField.borderStyle = .none
//        counterpartyTextField.attributedPlaceholder = NSAttributedString(string: "Recipient's identity key", attributes: placeholderAttributes)
//        
//        // Add some padding to the view
//        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: counterpartyTextField.frame.height))
//        counterpartyTextField.leftView = paddingView
//        counterpartyTextField.leftViewMode = .always
//    }
//    
//    // Gets a QRCode to decrypt
//    @IBAction func toggleQRScanner(_ sender: UIButton) {
//        
//        if (sender.restorationIdentifier == "recipientBtn") {
//            isSelectingRecipient = true
//        } else {
//            isSelectingRecipient = false
//        }
//        if (captureSession?.isRunning == true) {
//            captureSession?.stopRunning()
//            qrScannerView.isHidden = true
//        } else {
//            self.imagePicker.present(from: sender)
//        }
//    }
//
//    @IBAction func action(_ sender: UIButton) {
//        
//        if (textView.text == textView.placeholder) {
//            // Create a new alert
//            let dialogMessage = UIAlertController(title: "Error", message: "Please enter a message!", preferredStyle: .alert)
//            dialogMessage.addAction(UIAlertAction(title: "OK", style: .default, handler: { (action) -> Void in
//             }))
//            // Present alert to user
//            self.present(dialogMessage, animated: true, completion: nil)
//            return
//        }
//        
//        Task.init {
//            if (actionButton.title(for: .normal) == "Encrypt") {
//                let encryptedText = await sdk.encrypt(plaintext: textView.text, protocolID: PROTOCOL_ID, keyID: KEY_ID, counterparty: getCounterparty())
//                textView.text = encryptedText
//                
//                let QRCodeImage = generateQRCode(from: encryptedText, centerImage: UIImage(named: "encryptedQRLogo"))
//                self.secureQRCode = QRCodeImage
//                
//                if let vc = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "resultsVC") as? ResultsVC {
//                    vc.secureQRCode = QRCodeImage
//                    self.navigationController?.pushViewController(vc, animated: true)
//                }
//            } else {
//                do {
//                    textView.text = try await sdk.decrypt(ciphertext: self.textView.text, protocolID: PROTOCOL_ID, keyID: KEY_ID, counterparty: getCounterparty())
//                } catch {
//                    // Create a new alert
//                    let dialogMessage = UIAlertController(title: "Error", message: "Decryption failed!", preferredStyle: .alert)
//                    dialogMessage.addAction(UIAlertAction(title: "OK", style: .default, handler: { (action) -> Void in
//                     }))
//                    // Present alert to user
//                    self.present(dialogMessage, animated: true, completion: nil)
//                }
//            }
//        }
//    }
//    
//    // Figures out if counterparty is self
//    func getCounterparty() -> String {
//        var counterparty = "self"
//        if (counterpartyTextField.text != "") {
//            counterparty = counterpartyTextField.text!
//        }
//        return counterparty
//    }
//    
//    // Handle Delegate functions ---------------------------------------------------------
//    
//    // Dismiss the keyboard only if the textField is first responder.
//    @objc func handleTap(sender: UITapGestureRecognizer) {
//        
//        if let inputField = sender.view as? UITextField {
//             // Do something with the input field that was tapped
//            if inputField.isFirstResponder {
//                inputField.resignFirstResponder()
//            } else {
//                inputField.becomeFirstResponder()
//            }
//        } else {
//            if (textView.isFirstResponder == false && counterpartyTextField.isFirstResponder == false) {
//                textView.becomeFirstResponder()
//            } else{
//                self.view.endEditing(true)
//                
//                if (textView.text != textView.placeholder && action == "Decrypt") {
//                    actionButton.isHidden = false
//                }
//            }
//        }
//
//    }
//    
//    func textFieldDidBeginEditing(_ textField: UITextField) {
//        textView.frame = CGRect(x: textView.frame.origin.x, y: textView.frame.origin.y, width: textView.frame.width, height: textView.frame.height - (counterpartyTextField.frame.height + 50))
//    }
//    func textFieldDidEndEditing(_ textField: UITextField) {
//        textView.frame = CGRect(x: textView.frame.origin.x, y: textView.frame.origin.y, width: textView.frame.width, height: textView.frame.height + (counterpartyTextField.frame.height + 50))
//    }
//    
//    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
//           textField.resignFirstResponder()
//           return true
//       }
//    
//    // Find a camera with the specified AVCaptureDevicePosition, returning nil if one is not found
//    func cameraWithPosition(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
//        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: AVMediaType.video, position: .unspecified)
//        for device in discoverySession.devices {
//            if device.position == position {
//                return device
//            }
//        }
//        
//        return nil
//    }
//    
//    func metadataOutput(_ captureOutput: AVCaptureMetadataOutput,
//                        didOutput metadataObjects: [AVMetadataObject],
//                        from connection: AVCaptureConnection) {
//        // Check if the metadataObjects array is contains at least one object.
//        if metadataObjects.count == 0 {
//            return
//        }
//        
//        // Get the metadata object.
//        let metadataObj = metadataObjects[0] as! AVMetadataMachineReadableCodeObject
//        
//        if metadataObj.type == AVMetadataObject.ObjectType.qr {
//            if let outputString = metadataObj.stringValue {
//                
//                if (isSelectingRecipient) {
//                    counterpartyTextField.text = outputString
//                } else {
//                    Task.init {
//                        do {
//                            textView.text = try await sdk.decrypt(ciphertext: outputString, protocolID: PROTOCOL_ID, keyID: KEY_ID, counterparty: getCounterparty())
//                        } catch {
//                            // Create a new alert
//                            let dialogMessage = UIAlertController(title: "Error", message: "Decryption failed!", preferredStyle: .alert)
//                            dialogMessage.addAction(UIAlertAction(title: "OK", style: .default, handler: { (action) -> Void in
//                             }))
//                            // Present alert to user
//                            self.present(dialogMessage, animated: true, completion: nil)
//                        }
//                    }
//                }
//                
//                DispatchQueue.main.async {
//                    self.qrScannerView.isHidden = true
//                    self.captureSession?.stopRunning()
//                }
//            }
//        }
//        
//    }
//}
//
//extension CryptoVC: ImagePickerDelegate {
//
//    func didSelect(image: UIImage?) {
//        self.secureQRCode = image!
//        if ((image) != nil) {
//            let detector:CIDetector=CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy:CIDetectorAccuracyHigh])!
//            let ciImage:CIImage=CIImage(image:self.secureQRCode!)!
//            var message=""
//  
//            let features=detector.features(in: ciImage)
//            for feature in features as! [CIQRCodeFeature] {
//                message += feature.messageString!
//            }
//            
//            if message=="" {
//                print("nothing")
//            }else{
//                print("message: \(message)")
//                Task.init {
//                    if (isSelectingRecipient) {
//                        counterpartyTextField.text = message
//                    } else {
//                        do {
//                            textView.text = try await sdk.decrypt(ciphertext: message, protocolID: PROTOCOL_ID, keyID: KEY_ID, counterparty: getCounterparty())
//                        } catch {
//                            // Create a new alert
//                            let dialogMessage = UIAlertController(title: "Error", message: "Decryption failed!", preferredStyle: .alert)
//                            dialogMessage.addAction(UIAlertAction(title: "OK", style: .default, handler: { (action) -> Void in
//                             }))
//                            // Present alert to user
//                            self.present(dialogMessage, animated: true, completion: nil)
//                        }
//                    }
//                }
//            }
//        }
//    }
//}
