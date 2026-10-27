import Foundation
import Photos
import UIKit

/// Tự động quét thư viện ảnh: nhận change event khi app chạy + auto-scan ảnh screenshot
/// chưa xử lý mỗi lần app active. Chỉ lấy ảnh chụp màn hình (subtype photoScreenshot),
/// mỗi ảnh được phân loại — chỉ screenshot giao dịch ngân hàng/chuyển khoản mới ingest.
///
/// `pendingScreenshotAssetIDs()` fetch screenshots rồi lọc bằng Set đã xử lý —
/// O(tổng screenshot), chấp nhận được với thư viện cá nhân (vài trăm đến vài nghìn ảnh).
/// `fullScan()` bỏ qua trạng thái đã xử lý — nút "Rà quét toàn bộ" chạy lại được,
/// dedup cấp hash đảm bảo không tạo pending trùng.
final class PhotoMonitor: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    let pipeline: ExtractionPipeline
    let processedStore: ProcessedAssetStore

    private let stateLock = NSLock()
    private var started = false

    init(pipeline: ExtractionPipeline, processedStore: ProcessedAssetStore) {
        self.pipeline = pipeline
        self.processedStore = processedStore
        super.init()
    }

    // MARK: - Lifecycle

    func start() {
        stateLock.lock(); defer { stateLock.unlock() }
        guard !started else { return }
        started = true
        PHPhotoLibrary.shared().register(self)
    }

    func stop() {
        stateLock.lock(); defer { stateLock.unlock() }
        guard started else { return }
        started = false
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    // MARK: - Auto scan

    /// Quét mọi ảnh screenshot chưa xử lý rồi ingest. Tự xin quyền nếu chưa từng hỏi.
    /// Không lọc theo ngày — quét toàn bộ thư viện ngay lần đầu (phục vụ test với ảnh cũ).
    func autoScan() {
        Task { [pipeline, processedStore] in
            var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            if status == .notDetermined {
                status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            }
            guard status == .authorized || status == .limited else { return }
            await Self.scanUnprocessed(pipeline: pipeline, processedStore: processedStore)
        }
    }

    /// Scan tĩnh — không đụng instance state, an toàn concurrency.
    static func scanUnprocessed(pipeline: ExtractionPipeline, processedStore: ProcessedAssetStore) async {
        let pendingIDs = processedStore.pendingScreenshotAssetIDs()
        guard !pendingIDs.isEmpty else { return }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: pendingIDs, options: nil)
        let imageManager = PHImageManager.default()

        var assetList: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            assetList.append(asset)
        }

        for asset in assetList {
            guard let data = await Self.loadData(for: asset, manager: imageManager) else {
                processedStore.markProcessed([asset.localIdentifier])
                continue
            }
            _ = await pipeline.ingest(
                imageData: data,
                source: .ocrAutoScan,
                screenshotTakenAt: asset.creationDate
            )
            processedStore.markProcessed([asset.localIdentifier])
        }
    }

    // MARK: - Rà quét toàn bộ (manual, phục vụ test)

    /// Kết quả rà quét toàn bộ thư viện screenshot.
    struct FullScanSummary: Sendable, Equatable {
        var total = 0
        var scanned = 0
        var created = 0
        var duplicates = 0
        var notTransactions = 0
        var failed = 0

        var isRunning: Bool { scanned < total }
    }

    /// Quét TOÀN BỘ ảnh chụp màn hình. Mặc định sẽ bỏ qua các ảnh đã quét (skipProcessed = true) để tiết kiệm tài nguyên.
    /// Mỗi ảnh được phân loại: chỉ ảnh giao dịch ngân hàng/chuyển khoản mới ingest.
    /// Idempotent: ảnh đã nhập trả .duplicate, ảnh không liên quan bị loại, không ghi lung tung.
    static func fullScan(
        pipeline: ExtractionPipeline,
        processedStore: ProcessedAssetStore,
        skipProcessed: Bool = true,
        progress: (@Sendable (FullScanSummary) -> Void)? = nil
    ) async -> FullScanSummary {
        var summary = FullScanSummary()

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        var assetList: [PHAsset] = []
        PHAsset.fetchAssets(with: .image, options: options).enumerateObjects { asset, _, _ in
            let subtype = asset.mediaSubtypes.rawValue
            // Chỉ lấy Screenshot (4) hoặc Ảnh lưu từ app/ảnh thường (0)
            if subtype == PHAssetMediaSubtype.photoScreenshot.rawValue || subtype == 0 {
                if skipProcessed && processedStore.isProcessed(asset.localIdentifier) {
                    // Bỏ qua ảnh đã quét
                    return
                }
                assetList.append(asset)
            }
        }

        summary.total = assetList.count
        guard summary.total > 0 else { return summary }

        let imageManager = PHImageManager.default()
        for asset in assetList {
            if let data = await Self.loadData(for: asset, manager: imageManager) {
                let outcome = await pipeline.ingest(
                    imageData: data,
                    source: .ocrAutoScan,
                    screenshotTakenAt: asset.creationDate
                )
                switch outcome {
                case .created: summary.created += 1
                case .duplicate: summary.duplicates += 1
                case .notTransaction: summary.notTransactions += 1
                case .failed: summary.failed += 1
                }
            } else {
                summary.failed += 1
            }
            processedStore.markProcessed([asset.localIdentifier])
            summary.scanned += 1
            progress?(summary)
            await Task.yield()
        }
        return summary
    }

    /// Load ảnh pixel data (tối đa ~1200px) cho pipeline OCR.
    static func loadData(for asset: PHAsset, manager: PHImageManager) async -> Data? {
        await withCheckedContinuation { continuation in
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .highQualityFormat
            opts.isNetworkAccessAllowed = true
            manager.requestImage(
                for: asset,
                targetSize: CGSize(width: 1200, height: 1200),
                contentMode: .aspectFit,
                options: opts
            ) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !degraded else { return }
                guard let image else {
                    continuation.resume(returning: nil)
                    return
                }
                autoreleasepool {
                    let data = image.jpegData(compressionQuality: 0.8)
                    continuation.resume(returning: data)
                }
            }
        }
    }

    // MARK: - PHPhotoLibraryChangeObserver

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return }
        Task { [pipeline, processedStore] in
            await Self.scanUnprocessed(pipeline: pipeline, processedStore: processedStore)
        }
    }
}
