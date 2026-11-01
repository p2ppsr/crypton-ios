import UIKit
import UniformTypeIdentifiers

/// Stages a user-selected encrypted payload or public contact code for import on Crypton's next foreground activation.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        let spinner = UIActivityIndicatorView(style:.large); spinner.center = view.center; spinner.autoresizingMask = [.flexibleWidth,.flexibleHeight,.flexibleTopMargin,.flexibleBottomMargin]; view.addSubview(spinner); spinner.startAnimating()
        guard let provider = (extensionContext?.inputItems.first as? NSExtensionItem)?.attachments?.first else { finish("No encrypted text, contact code or QR image was shared."); return }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadItem(forTypeIdentifier:UTType.image.identifier,options:nil) { [weak self] value,error in
                do {
                    guard let self = self else { return }
                    try self.stageImage(value)
                    DispatchQueue.main.async { self.finish("Saved. Open Crypton to import this QR image.") }
                } catch { DispatchQueue.main.async { self?.finish(error.localizedDescription) } }
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
            provider.loadItem(forTypeIdentifier:UTType.text.identifier,options:nil) { [weak self] value,error in
                do {
                    let text = value as? String ?? (value as? Data).flatMap { String(data:$0,encoding:.utf8) }
                    guard let text = text, text.utf8.count <= 100_000 else { throw NSError(domain:"Crypton",code:1,userInfo:[NSLocalizedDescriptionKey:"Share encrypted text of at most 100 KB."]) }
                    try IncomingShareStore().stage(text:text)
                    DispatchQueue.main.async { self?.finish(Wire.isContact(text) ? "Saved. Open Crypton to review this contact before saving it." : "Saved. Open Crypton to import this message and choose its sender if needed.") }
                } catch { DispatchQueue.main.async { self?.finish(error.localizedDescription) } }
            }
        } else { finish("Share encrypted text, a Crypton contact code or one QR image.") }
    }
    private func stageImage(_ value:NSSecureCoding?) throws {
        var image = value as? UIImage
        if image == nil {
            var data = value as? Data
            if let url = value as? URL {
                guard url.isFileURL, (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max) <= 20_000_000 else { throw CryptonError("Choose a smaller QR image.") }
                data = try Data(contentsOf:url)
            }
            guard let bytes = data, bytes.count <= 20_000_000 else { throw CryptonError("Could not read this image.") }
            // UIKit's public.image item representation can be an NSSecureCoding UIImage archive.
            // Decode only that explicit framework class; never instantiate arbitrary archive roots.
            image = UIImage(data:bytes) ?? (try? NSKeyedUnarchiver.unarchivedObject(ofClass:UIImage.self,from:bytes))
        }
        guard let source = image, source.size.width * source.scale * source.size.height * source.scale <= 40_000_000 else { throw CryptonError("Could not read this image.") }
        let format = UIGraphicsImageRendererFormat(); format.scale = source.scale; format.opaque = true
        let normalized = UIGraphicsImageRenderer(size:source.size,format:format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin:.zero,size:source.size)); source.draw(at:.zero)
        }
        guard let png = normalized.pngData() else { throw CryptonError("Could not encode this image.") }
        try IncomingShareStore().stage(imageData:png)
    }
    private func finish(_ text:String) {
        view.subviews.forEach { $0.removeFromSuperview() }
        let label = UILabel(); label.text = text; label.numberOfLines = 0; label.textAlignment = .center; label.font = .preferredFont(forTextStyle:.body)
        let button = UIButton(type:.system); button.setTitle("Done",for:.normal); button.accessibilityIdentifier = "cryptonShareDone"; button.addTarget(self,action:#selector(done),for:.touchUpInside)
        let stack = UIStackView(arrangedSubviews:[label,button]); stack.axis = .vertical; stack.spacing = 24; stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:30),stack.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-30),stack.centerYAnchor.constraint(equalTo:view.centerYAnchor)])
    }
    @objc private func done() { extensionContext?.completeRequest(returningItems:nil) }
}
