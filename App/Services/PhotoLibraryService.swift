import Foundation
import Photos
import UIKit

enum PhotoAuthStatus: Equatable {
    case notDetermined
    case denied
    case limited
    case authorized
}

/// Nghiệp vụ thư viện ảnh: quyền, fetch screenshot, load ảnh pixel.
struct PhotoLibraryService: Sendable {
    let processedStore: ProcessedAssetStore

    init(processedStore: ProcessedAssetStore = ProcessedAssetStore()) {
        self.processedStore = processedStore
    }

    // MARK: - Quyền

    static func authStatus() -> PhotoAuthStatus {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        case .limited: return .limited
        case .authorized: return .authorized
        @unknown default: return .denied
        }
    }

    /// Xin quyền truy cập thư viện. Trả status cuối cùng.
    static func requestAccess() async -> PhotoAuthStatus {
        let granted = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        switch granted {
        case .authorized: return .authorized
        case .limited: return .limited
        default: return .denied
        }
    }

    // MARK: - Fetch screenshots (TOÀN BỘ thư viện, không lọc ngày — phục vụ test)

    /// Tất cả ảnh screenshot trong thư viện, mới nhất trước.
    /// Fallback: nếu không có ảnh nào được đánh dấu screenshot (thư viện test/import),
    /// trả mọi ảnh — dedup + auto-tick vẫn hoạt động đúng nhờ ProcessedAssetStore.
    func fetchAllScreenshots() -> [PHAsset] {
        guard Self.authStatus() == .authorized || Self.authStatus() == .limited else { return [] }

        var assets: [PHAsset] = []
        let screenshotOptions = PHFetchOptions()
        screenshotOptions.predicate = NSPredicate(
            format: "mediaSubtypes == %d",
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        screenshotOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        PHAsset.fetchAssets(with: screenshotOptions).enumerateObjects { asset, _, _ in
            assets.append(asset)
        }

        if assets.isEmpty {
            let allOptions = PHFetchOptions()
            allOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            PHAsset.fetchAssets(with: allOptions).enumerateObjects { asset, _, _ in
                assets.append(asset)
            }
        }
        return assets
    }

    /// Ảnh screenshot CHƯA qua pipeline — ứng viên auto-tick trong màn chọn.
    func fetchUnprocessedScreenshots() -> [PHAsset] {
        fetchAllScreenshots().filter { !processedStore.isProcessed($0.localIdentifier) }
    }

    // MARK: - Load ảnh

    /// Load ảnh full-ish (tối đa 1500px) cho pipeline OCR.
    func loadImageData(for asset: PHAsset, maxDimension: CGFloat = 1500) async -> Data? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            let targetSize = CGSize(width: maxDimension, height: maxDimension)
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
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

    /// Load thumbnail cho lưới chọn ảnh.
    func loadThumbnail(for asset: PHAsset, side: CGFloat) async -> UIImage? {
        let data = await loadImageData(for: asset, maxDimension: side)
        guard let data else { return nil }
        return UIImage(data: data)
    }
}
