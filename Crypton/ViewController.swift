//
//  ViewController.swift
//  Crypton
//
//  Created by Brayden Langley on 9/19/22.
//

import UIKit
import WebKit
import BabbageSDK
import GenericJSON
import AVFoundation
import CodeScanner

// Controller responsible for handling interactions on the main view
class ViewController: UIViewController, UINavigationControllerDelegate, AVCapturePhotoCaptureDelegate, AVCaptureMetadataOutputObjectsDelegate {

    @IBOutlet var counterpartyTextField: UITextField!
    @IBOutlet var textView: UITextView!
    
    @IBOutlet weak var previewView: UIView!
    @IBOutlet var secureQRCode: UIImageView!
    
    var imagePicker: ImagePicker!
    var isSelectingRecipient = false
    
    var imageOrientation: AVCaptureVideoOrientation?
    var captureSession: AVCaptureSession?
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    var capturePhotoOutput: AVCapturePhotoOutput?
    
    let PROTOCOL_ID = "crypton"
    let KEY_ID = "1"
    // This should be a shared instance for all view controllers and passed around via segues
    var sdk:BabbageSDK = BabbageSDK(webviewStartURL: "https://staging-mobile-portal.babbage.systems") // http://localhost:3000 "https://staging-mobile-portal.babbage.systems" // TODO: Validate web view?
    
    var audioPlayer:AVAudioPlayer?
//    let imagePicker = UIImagePickerController()

    override func viewDidLoad() {
        super.viewDidLoad()
        sdk.setParent(parent: self)
        
        let whitePlaceholderText = NSAttributedString(string: "Recipient",
                                                      attributes: [NSAttributedString.Key.foregroundColor: UIColor.lightGray])
        counterpartyTextField.attributedPlaceholder = whitePlaceholderText
        
        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing))
        view.addGestureRecognizer(tap)
        
        self.imagePicker = ImagePicker(presentationController: self, delegate: self)
        
        // Get an instance of the AVCaptureDevice class to initialize a
        // device object and provide the video as the media type parameter
        guard let captureDevice = AVCaptureDevice.default(for: AVMediaType.video) else {
//            fatalError("No video device found")
            return
        }
        // handler chiamato quando viene cambiato orientamento
        self.imageOrientation = AVCaptureVideoOrientation.portrait
        
//        self.imagePicker.delegate = self
                              
        do {
            // Get an instance of the AVCaptureDeviceInput class using the previous deivce object
            let input = try AVCaptureDeviceInput(device: captureDevice)
                   
            // Initialize the captureSession object
            captureSession = AVCaptureSession()
                   
            // Set the input device on the capture session
            captureSession?.addInput(input)
                   
            // Get an instance of ACCapturePhotoOutput class
            capturePhotoOutput = AVCapturePhotoOutput()
            capturePhotoOutput?.isHighResolutionCaptureEnabled = true
                   
            // Set the output on the capture session
            captureSession?.addOutput(capturePhotoOutput!)
            captureSession?.sessionPreset = .high
                   
            // Initialize a AVCaptureMetadataOutput object and set it as the input device
            let captureMetadataOutput = AVCaptureMetadataOutput()
            captureSession?.addOutput(captureMetadataOutput)
                   
            // Set delegate and use the default dispatch queue to execute the call back
            captureMetadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            captureMetadataOutput.metadataObjectTypes = [AVMetadataObject.ObjectType.qr]
                   
            //Initialise the video preview layer and add it as a sublayer to the viewPreview view's layer
            videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
            videoPreviewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
            videoPreviewLayer?.frame = view.layer.bounds
            previewView.layer.addSublayer(videoPreviewLayer!)
                   
        } catch {
            //If any error occurs, simply print it out
            print(error)
            return
        }
    }
    
    // Gets a QRCode to decrypt
    @IBAction func scanQRCode(_ sender: UIButton) {
        
        if (sender.restorationIdentifier == "recipientBtn") {
            isSelectingRecipient = true
        } else {
            isSelectingRecipient = false
        }
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
    
    // MARK: - UIImagePickerControllerDelegate Methods

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let pickedImage = info[UIImagePickerController.InfoKey.originalImage] as? UIImage {
            secureQRCode.contentMode = .scaleAspectFit
            secureQRCode.image = pickedImage
        }

        dismiss(animated: true, completion: nil)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        dismiss(animated: true, completion: nil)
    }
    
    // TODO: Move to helper class
    func generateQRCode(from string: String) -> UIImage? {
        let data = string.data(using: String.Encoding.ascii)
      
        if let QRFilter = CIFilter(name: "CIQRCodeGenerator") {
            QRFilter.setValue(data, forKey: "inputMessage")
            guard let QRImage = QRFilter.outputImage else { return nil }
            let scaleUp = CGAffineTransform(scaleX: 10.0, y: 10.0)
            let scaledQR = QRImage.transformed(by: scaleUp)
            
            // set up activity view controller
            let imageToShare = [ scaledQR ]
            let activityViewController = UIActivityViewController(activityItems: imageToShare, applicationActivities: nil)
            activityViewController.popoverPresentationController?.sourceView = self.view // so that iPads won't crash

            // exclude some activity types from the list (optional)
            activityViewController.excludedActivityTypes = [ UIActivity.ActivityType.postToFacebook ]

            // present the view controller
            self.present(activityViewController, animated: true, completion: nil)
            return UIImage(ciImage: scaledQR)
        }
      
        return nil
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
        
        //self.captureSession?.stopRunning()
        
        // Get the metadata object.
        let metadataObj = metadataObjects[0] as! AVMetadataMachineReadableCodeObject
        
        if metadataObj.type == AVMetadataObject.ObjectType.qr {
            if let outputString = metadataObj.stringValue {
                DispatchQueue.main.async {
                    print(outputString)
                    self.textView.text = outputString
                    self.previewView.isHidden = true
                    self.captureSession?.stopRunning()
                }
            }
        }
        
    }
    
    // Shows/hides the Babbage Desktop webview
    @IBAction func showWebView(_ sender: Any) {
        sdk.showView()
    }
    
    // Figures out if counterparty is self
    func getCounterparty() -> String {
        var counterparty = "self"
        if (counterpartyTextField.text != "") {
            counterparty = counterpartyTextField.text!
        }
        return counterparty
    }

    // Encrypts the text from the textview
    @IBAction func encrypt(_ sender: Any) {
        Task.init {
            let encryptedText = await sdk.encrypt(plaintext: textView.text, protocolID: PROTOCOL_ID, keyID: KEY_ID, counterparty: getCounterparty())
            textView.text = encryptedText
            
            let QRCodeImage = generateQRCode(from: encryptedText)
            self.secureQRCode.image = QRCodeImage
        }
        
        // TODO: Figure out prepare for segue code and pass the UIImage to the next view to be displayed.
        // Figure out if the encryption code should be called with the same button click,
        // or if it should be executed and then segue initiated manually
    }
    // Decrypts the text from the textview
    @IBAction func decrypt(_ sender: UIButton) {
        Task.init {
            textView.text = await sdk.decrypt(ciphertext: self.textView.text, protocolID: PROTOCOL_ID, keyID: KEY_ID, counterparty: getCounterparty())
        }
    }
}

extension ViewController: ImagePickerDelegate {

    func didSelect(image: UIImage?) {
        self.secureQRCode.image = image
        if ((image) != nil) {
            let detector:CIDetector=CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy:CIDetectorAccuracyHigh])!
            let ciImage:CIImage=CIImage(image:self.secureQRCode.image!)!
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
                    if (isSelectingRecipient) {
                        counterpartyTextField.text = message
                    } else {
                        textView.text = message
                    }
                }
            }
        }
    }
}
