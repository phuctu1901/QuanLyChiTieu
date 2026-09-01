import UIKit
import UniformTypeIdentifiers

/// Share Extension: nhận ảnh → downscale → ghi vào App Group inbox → return.
/// KHÔNG OCR/SwiftData ở đây (giới hạn bộ nhớ extension). Self-contained, không phụ thuộc app code.
@objc(ShareViewController)
final class ShareViewController: UIViewController {

    private let appGroupID = "group.techcave.quanlychitieu.shared"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let label = UILabel()
        label.text = "Đang nhận ảnh…"
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        buildViewHierarchy(label)
        processSharedItems { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    private func buildViewHierarchy(_ label: UILabel) {
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func processSharedItems(completion: @escaping () -> Void) {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            completion()
            return
        }

        let group = DispatchGroup()
        for item in items {
            guard let providers = item.attachments else { continue }
            for provider in providers {
                guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { continue }
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    guard let data = item as? Data else {
                        if let url = item as? URL, let urlData = try? Data(contentsOf: url) {
                            self.saveToInbox(urlData)
                        }
                        return
                    }
                    self.saveToInbox(data)
                }
                break // chỉ lấy ảnh đầu tiên mỗi item
            }
        }
        group.notify(queue: .main) { completion() }
    }

    private func saveToInbox(_ data: Data) {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return }

        let inbox = container.appendingPathComponent("inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

        let outData = Self.downscaleJPEG(data, maxDimension: 1500, quality: 0.8) ?? data
        let fileName = UUID().uuidString + ".jpg"
        try? outData.write(to: inbox.appendingPathComponent(fileName), options: .atomic)
    }

    /// Downscale bằng ImageIO — không decode full bitmap, an toàn bộ nhớ extension.
    private static func downscaleJPEG(_ data: Data, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: quality)
    }
}
