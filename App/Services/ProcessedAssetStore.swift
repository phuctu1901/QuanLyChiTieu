import Foundation
import Photos

/// Track các PHAsset localIdentifier đã xử lý qua pipeline.
/// Dùng để: (1) auto-tick ảnh CHƯA nhập trong màn chọn thư viện, (2) auto-scan bỏ qua ảnh đã xử lý.
struct ProcessedAssetStore: @unchecked Sendable {
    private static let key = "processedAssetIDs"
    private let lock = NSLock()

    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: AppConstants.appGroupID)) {
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

    /// Danh sách ảnh screenshot trong thư viện CHƯA xử lý (để auto-scan ingest).
    /// Ưu tiên ảnh có subtype photoScreenshot; nếu thư viện không có ảnh nào
    /// được đánh dấu screenshot (VD ảnh import qua simctl/test không có cờ),
    /// fallback quét mọi ảnh chưa xử lý — dedup hash sẽ loại trùng lặp.
    func pendingScreenshotAssetIDs() -> [String] {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized
            || PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited else { return [] }

        var result: [String] = []
        let processed = loadIDs()

        func collect(_ assets: PHFetchResult<PHAsset>) {
            assets.enumerateObjects { asset, _, _ in
                if !processed.contains(asset.localIdentifier) {
                    result.append(asset.localIdentifier)
                }
            }
        }

        let screenshotOptions = PHFetchOptions()
        screenshotOptions.predicate = NSPredicate(
            format: "mediaSubtypes == %d",
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        let screenshots = PHAsset.fetchAssets(with: screenshotOptions)
        collect(screenshots)

        if result.isEmpty {
            // Fallback: chưa có screenshot nào được đánh dấu (thư viện test)
            let allOptions = PHFetchOptions()
            allOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            collect(PHAsset.fetchAssets(with: allOptions))
        }
        return result
    }
}
