import Foundation
import CryptoKit
import UIKit
import ImageIO

/// Lưu ảnh giao dịch vào Application Support: downscale ≤1500px JPEG + SHA256 dedup.
final class ImageStore: @unchecked Sendable {
    static let shared: ImageStore? = {
        let store = ImageStore()
        return store.directoryCreated ? store : nil
    }()

    let directory: URL
    let directoryCreated: Bool

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TransactionImages", isDirectory: true)
        self.directory = base
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            directoryCreated = true
        } catch {
            directoryCreated = false
        }
    }

    /// Lưu imageData (downscale trước khi ghi), trả về (hash, path) hoặc nil nếu fail.
    /// Gọi save() hai lần với cùng data → cùng hash, file chỉ ghi 1 lần.
    func save(_ data: Data) -> (hash: String, path: String)? {
        let hash = Self.sha256(data)
        let fileName = "\(hash).jpg"
        let fileURL = directory.appendingPathComponent(fileName)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let jpeg = Self.downscaleJPEG(data, maxDimension: 1500, quality: 0.8)
            do {
                try (jpeg ?? data).write(to: fileURL, options: .atomic)
            } catch {
                return nil
            }
        }
        return (hash, fileName)
    }

    func loadImage(path: String) -> UIImage? {
        let url = directory.appendingPathComponent(path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func delete(path: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(path))
    }

    /// Xoá các file không được tham chiếu bởi bất kỳ PendingExtraction/Transaction nào.
    func cleanupOrphans(referencedPaths: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for url in files {
            guard url.pathExtension.lowercased() == "jpg" else { continue }
            if !referencedPaths.contains(url.lastPathComponent) {
                try? FileManager.default.removeItem(at: url)
            }
    }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Downscale bằng ImageIO (không decode full bitmap vào bộ nhớ) — dùng chung cho app + extension.
    static func downscaleJPEG(_ data: Data, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: quality)
    }
}
