import Foundation
import ImageIO

/// Shared by the app and extension; contains only user-selected encrypted text or QR images.
final class IncomingShareStore {
    static let group = "group.com.projectbabbage.Crypton"
    let directory: URL
    init(directory:URL? = nil) throws {
        if let directory = directory { self.directory = directory }
        else {
            guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:Self.group) else { throw CryptonError("Shared storage is unavailable. Import this file from inside Crypton instead.") }
            var folder = "Incoming"
            #if DEBUG
            if UserDefaults(suiteName:Self.group)?.bool(forKey:"useUITestInbox") == true { folder = "UITestIncoming" }
            #endif
            self.directory = group.appendingPathComponent(folder)
        }
    }
    func pending() throws -> [URL] {
        guard FileManager.default.fileExists(atPath:directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.creationDateKey,.isRegularFileKey]).filter {
            ["txt","png"].contains($0.pathExtension) && ((try? $0.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile) == true)
        }.sorted { a,b in
            let left = (try? a.resourceValues(forKeys:[.creationDateKey]).creationDate) ?? .distantPast
            let right = (try? b.resourceValues(forKeys:[.creationDateKey]).creationDate) ?? .distantPast
            return left == right ? a.lastPathComponent < b.lastPathComponent : left < right
        }
    }
    @discardableResult func stage(text:String) throws -> URL {
        guard text.utf8.count <= 100_000 else { throw CryptonError("Share encrypted text of at most 100 KB.") }
        if Wire.isEnvelope(text) { _ = try Wire.envelope(text) }
        else { _ = try Wire.legacy(text,peer:"self",encrypt:false) }
        return try write(Data(text.utf8),extension:"txt")
    }
    @discardableResult func stage(image:URL) throws -> URL {
        guard image.isFileURL, (try image.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max) <= 20_000_000 else { throw CryptonError("The image exceeds 20 MB.") }
        return try stage(imageData:Data(contentsOf:image))
    }
    @discardableResult func stage(imageData:Data) throws -> URL {
        guard imageData.count <= 20_000_000, let source = CGImageSourceCreateWithData(imageData as CFData,nil), CGImageSourceGetCount(source) > 0 else { throw CryptonError("Could not read this image.") }
        return try write(imageData,extension:"png")
    }
    private func write(_ data:Data,extension ext:String) throws -> URL {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        guard try pending().count < 10 else { throw CryptonError("Open Crypton to import pending messages before sharing more.") }
        var folder = directory, values = URLResourceValues(); values.isExcludedFromBackup = true; try folder.setResourceValues(values)
        let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        try data.write(to:url,options:[.atomic,.completeFileProtection]); return url
    }
    func remove(_ url:URL) throws {
        guard url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else { throw CryptonError("Invalid incoming share.") }
        try FileManager.default.removeItem(at:url)
    }
}
