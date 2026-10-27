import Foundation

/// Drain ảnh từ App Group inbox (Share Extension ghi vào) — chạy khi app active.
@MainActor
final class ShareInboxService: Sendable {
    let pipeline: ExtractionPipeline

    init(pipeline: ExtractionPipeline) {
        self.pipeline = pipeline
    }

    /// Xử lý hết file trong inbox rồi xoá. Trả số ảnh đã ingest.
    @discardableResult
    func drainInbox() async -> Int {
        guard let inbox = AppConstants.shareInboxURL else { return 0 }
        let fm = FileManager.default

        guard let files = try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil) else { return 0 }
        var count = 0
        for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let data = try? Data(contentsOf: url) else {
                try? fm.removeItem(at: url)
                continue
            }
            _ = await pipeline.ingest(imageData: data, source: .shareExt, skipClassification: true)
            try? fm.removeItem(at: url)
            count += 1
        }
        return count
    }
}
