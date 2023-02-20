//
//  QRScannerViewController.swift
//  Crypton
//
//  Created by Brayden Langley on 2/18/23.
//

import Foundation
import UIKit
import AVFoundation

/**
 Protocol definition for the QR scanner callbacks
 */
protocol QRScannerDelegate: AnyObject {
    func didScanQRCode(withData data: String)
}

/**
  View Controller responsible for loading QR scanner and triggering callback
 */
class QRScannerVC: UIViewController, AVCapturePhotoCaptureDelegate, AVCaptureMetadataOutputObjectsDelegate {
    
    // These are needed for live QR code capture
    var imageOrientation: AVCaptureVideoOrientation?
    var captureSession: AVCaptureSession?
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    var capturePhotoOutput: AVCapturePhotoOutput?
    var isSelectingRecipient:Bool = false

    weak var delegate: QRScannerDelegate?
    var delegateNotified: Bool = false
    
    @IBOutlet var qrScannerView: UIView!
    @IBOutlet var previewView: UIView!
    @IBOutlet var exitButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        previewView.layer.cornerRadius = 50
        previewView.layer.masksToBounds = true
//        exitButton.setTitle(exitButtonText ?? "Enter Manually", for: .normal)
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
            captureSession?.sessionPreset = .high

            //Initialise the video preview layer and add it as a sublayer to the viewPreview view's layer
            videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
            videoPreviewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
            videoPreviewLayer?.frame = view.layer.bounds
            previewView.layer.addSublayer(videoPreviewLayer!)
            
            self.captureSession?.startRunning()
            
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
    @IBAction func exit(_ sender: Any) {
        dismiss(animated: true, completion: nil)
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
                
                // Only notifiy the delegate once
                if !delegateNotified {
                    delegate?.didScanQRCode(withData: outputString)
                    delegateNotified = true
                }
                
                dismiss(animated: true, completion: nil)
            }
        }
        
    }
}
