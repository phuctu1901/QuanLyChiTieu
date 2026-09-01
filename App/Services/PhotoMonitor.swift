import Foundation
import Photos
import UIKit

/// Tự động quét thư viện ảnh: nhận change event khi app chạy + auto-scan ảnh screenshot
/// chưa xử lý mỗi lần app active. Quét TOÀN BỘ thư viện (không lọc ngày) — ProcessedAssetStore
/// đảm bảo không xử lý lại ảnh đã qua pipeline.
///
/// `pendingScreenshotAssetIDs()` fetch toàn bộ screenshots rồi lọc bằng Set đã xử lý —
/// O(tổng screenshot), chấp nhận được với thư viện cá nhân (vài trăm đến vài nghìn ảnh).
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
            _ = await pipeline.ingest(imageData: data, source: .ocrAutoScan)
            processedStore.markProcessed([asset.localIdentifier])
        }
    }

    /// Load ảnh pixel data (tối đa ~1500px) cho pipeline OCR.
    static func loadData(for asset: PHAsset, manager: PHImageManager) async -> Data? {
        await withCheckedContinuation { continuation in
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .highQualityFormat
            opts.isNetworkAccessAllowed = true
            manager.requestImage(
                for: asset,
                targetSize: CGSize(width: 1500, height: 1500),
                contentMode: .aspectFit,
                options: opts
            ) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !degraded else { return }
                guard let image else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: image.jpegData(compressionQuality: 0.85))
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
