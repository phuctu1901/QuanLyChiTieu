import Foundation
import Photos
import UIKit

/// Theo dõi Photo Library: nhận change event khi app đang chạy + catch-up scan ảnh screenshot mới mỗi lần app active.
final class PhotoMonitor: NSObject, PHPhotoLibraryChangeObserver {
    let pipeline: ExtractionPipeline

    private var started = false

    init(pipeline: ExtractionPipeline) {
        self.pipeline = pipeline
        super.init()
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        PHPhotoLibrary.shared().register(self)
    }

    func stop() {
        guard started else { return }
        started = false
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    // MARK: - Catch-up scan

    /// Quét ảnh screenshot chụp sau lần scan cuối, ingest từng ảnh.
    func catchUpScan() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return }

        let lastScan = AppConstants.sharedDefaults.date(forKey: AppConstants.lastPhotoScanKey)
        var options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaSubtypes == %d AND creationDate > %@",
            PHAssetMediaSubtype.photoScreenshot.rawValue,
            (lastScan ?? Date.distantPast) as NSDate
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.fetchLimit = 20

        let assets = PHAsset.fetchAssets(with: options)
        guard assets.count > 0 else {
            AppConstants.sharedDefaults.set(Date(), forKey: AppConstants.lastPhotoScanKey)
            return
        }

        let imageManager = PHImageManager.default()
        let lastDate = lastScan
        let pipeline = self.pipeline
        assets.enumerateObjects { asset, _, _ in
            // Ảnh chụp trước lần scan cuối (đã xử lý rồi) bỏ qua
            if let lastDate, asset.creationDate! < lastDate { return }
            let opts = PHImageRequestOptions()
            opts.isSynchronous = false
            opts.deliveryMode = .highQualityFormat
            opts.isNetworkAccessAllowed = false
            imageManager.requestImage(
                for: asset,
                targetSize: CGSize(width: 1500, height: 1500),
                contentMode: .aspectFit,
                options: opts
            ) { image, _ in
                guard let image, let data = image.jpegData(compressionQuality: 0.85) else { return }
                Task { await pipeline.ingest(imageData: data, source: .ocrAutoScan) }
            }
        }
        AppConstants.sharedDefaults.set(Date(), forKey: AppConstants.lastPhotoScanKey)
    }

    // MARK: - PHPhotoLibraryChangeObserver

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        // Kiểm tra quyền trước khi quét (đăng ký observer tự có quyền khi authorized)
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return }
        catchUpScan()
    }
}
