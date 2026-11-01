import SwiftUI
import WebKit

import AVFoundation
import CoreImage
import ImageIO
import PhotosUI
import ContactsUI
import UniformTypeIdentifiers

/// Ciphertext and JSON must retain the exact characters entered by the sender.
struct MessageEditor: UIViewRepresentable {
    @Binding var text:String
    var label:String = "messageEditor"
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context:Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear; view.textColor = .white
        view.font = UIFontMetrics.default.scaledFont(for:.monospacedSystemFont(ofSize:17,weight:.regular))
        view.adjustsFontForContentSizeCategory = true
        view.autocorrectionType = .no; view.autocapitalizationType = .none
        view.smartQuotesType = .no; view.smartDashesType = .no; view.smartInsertDeleteType = .no
        view.accessibilityIdentifier = label; view.accessibilityLabel = label
        if label != "messageEditor" {
            context.coordinator.editor = view
            let toolbar = UIToolbar(frame:CGRect(x:0,y:0,width:320,height:44))
            let done = UIBarButtonItem(barButtonSystemItem:.done,target:context.coordinator,action:#selector(Coordinator.finishEditing))
            done.accessibilityIdentifier = "keyInputDone"; done.accessibilityLabel = "Done entering key"
            toolbar.items = [UIBarButtonItem.flexibleSpace(),done]; view.inputAccessoryView = toolbar
        }
        return view
    }
    func updateUIView(_ view:UITextView,context:Context) {
        context.coordinator.parent = self
        if view.text != text { view.text = text }
    }
    final class Coordinator: NSObject,UITextViewDelegate {
        var parent:MessageEditor
        weak var editor:UITextView?
        @objc func finishEditing() { editor?.resignFirstResponder() }
        init(_ parent:MessageEditor) { self.parent = parent }
        func textViewDidChange(_ textView:UITextView) { parent.text = textView.text }
    }
}

@MainActor enum QRTools {
    static func image(_ text: String) -> UIImage? {
        guard let filter = CIFilter(name:"CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8),forKey:"inputMessage"); filter.setValue("M",forKey:"inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        // Four-module white quiet zone, with whole pixels per module and no logo obscuring data.
        let scaled = output.transformed(by:CGAffineTransform(scaleX:6,y:6))
        guard let cg = CIContext().createCGImage(scaled,from:scaled.extent) else { return nil }
        let size = CGSize(width:cg.width+48,height:cg.height+48)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size:size,format:format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin:.zero,size:size)); context.cgContext.interpolationQuality = .none
            UIImage(cgImage:cg).draw(at:CGPoint(x:24,y:24))
        }
    }
    static func read(_ url: URL) throws -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL,nil), let image = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:2048,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else { throw CryptonError("Could not read this image.") }
        let context = CIContext(options:[.useSoftwareRenderer:true])
        guard let detector = CIDetector(ofType:CIDetectorTypeQRCode,context:context,options:[CIDetectorAccuracy:CIDetectorAccuracyHigh]) else { throw CryptonError("QR image detection is unavailable.") }
        let values = Set(detector.features(in:CIImage(cgImage:image)).compactMap { ($0 as? CIQRCodeFeature)?.messageString })
        guard values.count == 1, let value = values.first else { throw CryptonError("Choose an image containing one readable QR code.") }
        return value
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var completed: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context:Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems:items,applicationActivities:nil)
        controller.completionWithItemsHandler = { _,_,_,_ in dismiss(); completed() }
        return controller
    }
    func updateUIViewController(_ controller:UIActivityViewController,context:Context) {}
}
struct WalletWebView: UIViewRepresentable {
    let web: WKWebView
    func makeUIView(context:Context) -> WKWebView { web }
    func updateUIView(_ view:WKWebView,context:Context) {}
}

struct PhotoImporter: UIViewControllerRepresentable {
    var result: (Result<String,Error>) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(result) }
    func makeUIViewController(context:Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(); config.filter = .images; config.selectionLimit = 1
        let picker = PHPickerViewController(configuration:config); picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ controller:PHPickerViewController,context:Context) {}
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var result: (Result<String,Error>) -> Void
        init(_ result:@escaping (Result<String,Error>) -> Void) { self.result = result }
        func picker(_ picker:PHPickerViewController,didFinishPicking results:[PHPickerResult]) {
            picker.dismiss(animated:true)
            guard let item = results.first?.itemProvider else { return }
            item.loadFileRepresentation(forTypeIdentifier:UTType.image.identifier) { url,error in
                guard let url = url else { DispatchQueue.main.async { self.result(.failure(error ?? CryptonError("Could not load this image."))) }; return }
                // The provider URL lasts only for this callback. Copy just this user-selected image.
                let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension)
                do {
                    let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
                    guard size <= 20_000_000 else { throw CryptonError("Image too large.") }
                    try FileManager.default.copyItem(at:url,to:target)
                    DispatchQueue.main.async {
                        defer { try? FileManager.default.removeItem(at:target) }
                        self.result(Result { try QRTools.read(target) })
                    }
                } catch { DispatchQueue.main.async { self.result(.failure(error)) } }
            }
        }
    }
}

struct PhoneContacts: UIViewControllerRepresentable {
    var result: (Result<(String,String),Error>) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(result) }
    func makeUIViewController(context:Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController(); picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ controller:CNContactPickerViewController,context:Context) {}
    final class Coordinator: NSObject,CNContactPickerDelegate {
        let result: (Result<(String,String),Error>) -> Void
        init(_ result:@escaping (Result<(String,String),Error>) -> Void) { self.result = result }
        func contactPicker(_ picker:CNContactPickerViewController,didSelect contact:CNContact) {
            let name = CNContactFormatter.string(from:contact,style:.fullName) ?? "Contact"
            let candidates = contact.urlAddresses.map { $0.value as String } + contact.instantMessageAddresses.map { $0.value.username }
            if let key = candidates.compactMap({ value -> String? in
                let raw = value.hasPrefix("crypton:") ? String(value.dropFirst(8)) : value
                return try? Wire.identity(raw)
            }).first { result(.success((name,key))) }
            else { result(.failure(CryptonError("This contact has no Crypton identity in its URL or instant-message fields."))) }
        }
    }
}

struct QRScanner: UIViewControllerRepresentable {
    let result: (Result<String,Error>) -> Void
    func makeUIViewController(context:Context) -> ScannerController { ScannerController(result:result) }
    func updateUIViewController(_ controller:ScannerController,context:Context) {}
}
final class ScannerController: UIViewController,AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label:"crypton.camera")
    private var preview: AVCaptureVideoPreviewLayer?
    private var completed = false
    private let result: (Result<String,Error>) -> Void
    init(result:@escaping (Result<String,Error>) -> Void) { self.result = result; super.init(nibName:nil,bundle:nil) }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        let label = UILabel(); label.text = "Point the camera at one Crypton QR code"; label.textColor = .white; label.textAlignment = .center; label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(label)
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:20),label.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-20),label.bottomAnchor.constraint(equalTo:view.safeAreaLayoutGuide.bottomAnchor,constant:-32)])
        AVCaptureDevice.requestAccess(for:.video) { allowed in DispatchQueue.main.async { if allowed { self.configure() } else { self.finish(.failure(CryptonError("Camera access is off. Enable it in iOS Settings, or import a QR image."))) } } }
    }
    private func configure() {
        guard !completed else { return }
        do {
            guard let device = AVCaptureDevice.default(for:.video) else { throw CryptonError("No camera is available. Import a QR image instead.") }
            let input = try AVCaptureDeviceInput(device:device), output = AVCaptureMetadataOutput()
            guard session.canAddInput(input), session.canAddOutput(output) else { throw CryptonError("The camera could not start.") }
            session.addInput(input); session.addOutput(output); output.setMetadataObjectsDelegate(self,queue:.main); output.metadataObjectTypes = [.qr]
            let preview = AVCaptureVideoPreviewLayer(session:session); preview.videoGravity = .resizeAspectFill; view.layer.insertSublayer(preview,at:0); self.preview = preview; preview.frame = view.bounds
            queue.async { self.session.startRunning() }
        } catch { finish(.failure(error)) }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    override func viewWillDisappear(_ animated:Bool) { super.viewWillDisappear(animated); completed = true; queue.async { self.session.stopRunning() } }
    func metadataOutput(_ output:AVCaptureMetadataOutput,didOutput objects:[AVMetadataObject],from connection:AVCaptureConnection) {
        if let value = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue { finish(.success(value)) }
    }
    private func finish(_ value:Result<String,Error>) { guard !completed else { return }; completed = true; queue.async { self.session.stopRunning() }; result(value) }
}
