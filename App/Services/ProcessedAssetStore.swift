import Foundation
import Photos

/// Track các PHAsset localIdentifier đã xử lý qua pipeline.
/// Dùng để: (1) auto-tick ảnh CHƯA nhập trong màn chọn thư viện, (2) auto-scan bỏ qua ảnh đã xử lý.
struct ProcessedAssetStore: @unchecked Sendable {
    private static let key = "processedAssetIDs"
    private let lock = NSLock()

    private let defaults: UserDefaults?

    /// Dùng cùng defaults đã được check fallback trong AppConstants.
    init(defaults: UserDefaults? = AppConstants.sharedDefaults.defaults) {
        self.defaults = defaults
    }

    private func loadIDs() -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        guard let raw = defaults?.stringArray(forKey: Self.key) else { return [] }
        return Set(raw)
    }

    func isProcessed(_ id: String) -> Bool {
        loadIDs().contains(id)
    }

    func markProcessed(_ ids: Set<String>) {
        lock.lock(); defer { lock.unlock() }
        var current = Set(defaults?.stringArray(forKey: Self.key) ?? [])
        current.formUnion(ids)
        defaults?.set(Array(current), forKey: Self.key)
    }

    func unprocessed(_ ids: [String]) -> [String] {
        let processed = loadIDs()
        return ids.filter { !processed.contains($0) }
    }

    /// Xoá toàn bộ lịch sử quét (buộc hệ thống quét lại từ đầu ở lần tới)
    func clear() {
        lock.lock(); defer { lock.unlock() }
        defaults?.removeObject(forKey: Self.key)
    }

    /// Danh sách ảnh screenshot trong thư viện CHƯA xử lý (để auto-scan ingest).
    /// Chỉ lấy ảnh có subtype photoScreenshot (ảnh chụp màn hình) — KHÔNG fallback
    /// lấy toàn bộ thư viện: ảnh thường (selfie, phong cảnh…) sẽ không bị nhặt vào.
    func pendingScreenshotAssetIDs() -> [String] {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized
            || PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited else { return [] }

        var result: [String] = []
        let processed = loadIDs()

        let screenshotOptions = PHFetchOptions()
        screenshotOptions.predicate = NSPredicate(
            format: "mediaSubtypes == %d",
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        screenshotOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let screenshots = PHAsset.fetchAssets(with: screenshotOptions)
        screenshots.enumerateObjects { asset, _, _ in
            if !processed.contains(asset.localIdentifier) {
                result.append(asset.localIdentifier)
            }
        }
        return result
    }
}
