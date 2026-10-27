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
/// Dùng `PHCachingImageManager` để prefetch + cache thumbnail — tránh lag grid.
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

    // MARK: - Fetch screenshots

    /// Tất cả ảnh chụp màn hình (subtype photoScreenshot) trong thư viện, mới nhất trước.
    /// KHÔNG fallback lấy toàn bộ ảnh — chỉ screenshot liên quan giao dịch mới được xử lý.
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
        return assets
    }

    /// Ảnh screenshot CHƯA qua pipeline — ứng viên auto-tick trong màn chọn.
    func fetchUnprocessedScreenshots() -> [PHAsset] {
        fetchAllScreenshots().filter { !processedStore.isProcessed($0.localIdentifier) }
    }

    /// TOÀN BỘ ảnh trong thư viện (kể cả ảnh chụp thường), mới nhất trước —
    /// cho tab "Tất cả ảnh" chọn tay (ảnh lưu từ chat, ảnh chụp giấy tờ...).
    func fetchAllPhotos() -> [PHAsset] {
        guard Self.authStatus() == .authorized || Self.authStatus() == .limited else { return [] }
        var assets: [PHAsset] = []
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }

    // MARK: - Load ảnh (high quality — cho pipeline OCR)

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
}

// MARK: - Thumbnail Cache Manager

/// Singleton quản lý cache thumbnail cho grid ảnh.
/// Dùng `PHCachingImageManager` (best practice từ Apple/YPImagePicker/TLPhotoPicker)
/// thay vì `PHImageManager.default()` — prefetch theo scroll, cancel khi cell recycle.
/// PHCachingImageManager thread-safe — KHÔNG cần @MainActor.
final class ThumbnailCacheManager: @unchecked Sendable {
    static let shared = ThumbnailCacheManager()

    private let cachingManager = PHCachingImageManager()
    /// Kích thước thumbnail (pixel) — cell ~110pt * 3x scale ≈ 330, round to 240 cho nhẹ.
    let thumbnailSize = CGSize(width: 240, height: 240)

    /// Options dùng chung cho cả cache + request (PHẢI KHỚP để cache hit).
    let thumbnailOptions: PHImageRequestOptions = {
        let opt = PHImageRequestOptions()
        opt.deliveryMode = .opportunistic   // degraded → final (mượt)
        opt.resizeMode = .fast              // resize nhanh, không cần chính xác pixel
        opt.isNetworkAccessAllowed = false   // thumbnail không cần iCloud
        opt.isSynchronous = false
        return opt
    }()

    private init() {}

    /// Prefetch một batch asset (gọi khi grid sắp hiện).
    func startCaching(assets: [PHAsset]) {
        cachingManager.startCachingImages(
            for: assets,
            targetSize: thumbnailSize,
            contentMode: .aspectFill,
            options: thumbnailOptions
        )
    }

    /// Huỷ prefetch khi asset ra khỏi viewport.
    func stopCaching(assets: [PHAsset]) {
        cachingManager.stopCachingImages(
            for: assets,
            targetSize: thumbnailSize,
            contentMode: .aspectFill,
            options: thumbnailOptions
        )
    }

    /// Reset toàn bộ cache (khi dismiss screen).
    func resetCache() {
        cachingManager.stopCachingImagesForAllAssets()
    }

    /// Load thumbnail cho 1 cell. Trả `PHImageRequestID` để caller cancel nếu cell recycle.
    /// Callback có thể gọi 2 lần (degraded → final) do `.opportunistic`.
    @discardableResult
    func loadThumbnail(
        for asset: PHAsset,
        completion: @escaping (UIImage?) -> Void
    ) -> PHImageRequestID {
        cachingManager.requestImage(
            for: asset,
            targetSize: thumbnailSize,
            contentMode: .aspectFill,
            options: thumbnailOptions
        ) { image, _ in
            completion(image)
        }
    }

    /// Cancel request đang chạy (khi cell disappear).
    func cancelRequest(_ requestID: PHImageRequestID) {
        cachingManager.cancelImageRequest(requestID)
    }
}
