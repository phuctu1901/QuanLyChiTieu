import Foundation
import Photos
import UIKit

/// Export screenshot + OCR + classification ra Documents/DebugOCR —
/// để debug filter ảnh rác trên thư viện thật (kéo về máy qua devicectl).
enum DebugExportService {

    struct Entry: Codable {
        let id: String
        let createdAt: Date?
        let classification: String
        let ocrText: String
        let imageFile: String
    }

    /// Export TOÀN BỘ screenshot + ảnh lưu từ banking apps trong thư viện.
    /// Ghi ảnh full-size + manifest.json + marker "done" khi xong.
    /// Dùng để thu thập dataset test/train ML classifier.
    static func exportAllScreenshots() async -> Int {
        let folder = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DebugOCR", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        var assets: [PHAsset] = []
        PHAsset.fetchAssets(with: .image, options: options).enumerateObjects { asset, _, _ in
            let subtype = asset.mediaSubtypes.rawValue
            if subtype == PHAssetMediaSubtype.photoScreenshot.rawValue || subtype == 0 {
                assets.append(asset)
            }
        }

        let ocr = OCRService()
        let manager = PHImageManager.default()
        var entries: [Entry] = []

        for (index, asset) in assets.enumerated() {
            guard let data = await PhotoMonitor.loadData(for: asset, manager: manager) else { continue }

            // Tên file: ngày_index.jpg
            let dateStr: String
            if let date = asset.creationDate {
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyyMMdd_HHmmss"
                dateStr = fmt.string(from: date)
            } else {
                dateStr = "unknown"
            }
            let isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
            let prefix = isScreenshot ? "ss" : "photo"
            let fileName = "\(prefix)_\(dateStr)_\(String(format: "%04d", index)).jpg"
            try? data.write(to: folder.appendingPathComponent(fileName))

            let lines = (try? await ocr.recognizeLines(imageData: data)) ?? []
            let verdict = ImageClassifier.classify(lines: lines)
            entries.append(Entry(
                id: asset.localIdentifier,
                createdAt: asset.creationDate,
                classification: "\(verdict)",
                ocrText: lines.joined(separator: " | "),
                imageFile: fileName
            ))
        }

        // Ghi manifest
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let json = try? encoder.encode(entries) {
            try? json.write(to: folder.appendingPathComponent("manifest.json"))
        }
        // Marker: export xong
        try? Data("done \(entries.count) images".utf8)
            .write(to: folder.appendingPathComponent("done.txt"))

        return entries.count
    }

    /// Đường dẫn thư mục DebugOCR.
    static var exportFolder: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DebugOCR", isDirectory: true)
    }

    /// Nén thư mục DebugOCR → file .zip để AirDrop.
    /// Trả URL của file zip, hoặc nil nếu lỗi.
    static func zipExportFolder() -> URL? {
        let folder = exportFolder
        guard FileManager.default.fileExists(atPath: folder.path) else { return nil }

        let zipURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DebugOCR_export.zip")

        // Xoá zip cũ nếu có
        try? FileManager.default.removeItem(at: zipURL)

        // Tạo zip bằng NSFileCoordinator
        var error: NSError?
        let coordinator = NSFileCoordinator()
        var resultURL: URL?

        coordinator.coordinate(
            readingItemAt: folder,
            options: .forUploading,
            error: &error
        ) { tempZipURL in
            try? FileManager.default.copyItem(at: tempZipURL, to: zipURL)
            resultURL = zipURL
        }

        if let error {
            print("❌ Zip error: \(error)")
            return nil
        }
        return resultURL
    }

    /// Export phiên bản cũ — 2 ngày gần nhất (giữ lại để backward compat)
    static func exportRecentScreenshots(days: Int = 2) async {
        _ = await exportAllScreenshots()
    }
}
