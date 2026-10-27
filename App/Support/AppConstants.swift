import Foundation

/// Wrapper UserDefaults an toàn concurrency (UserDefaults thread-safe từ iOS).
struct SharedDefaults: @unchecked Sendable {
    let defaults: UserDefaults?

    func date(forKey key: String) -> Date? {
        defaults?.object(forKey: key) as? Date
    }

    func set(_ value: Date, forKey key: String) {
        defaults?.set(value, forKey: key)
    }

    func string(forKey key: String) -> String? {
        defaults?.string(forKey: key)
    }
}

enum AppConstants {
    /// App Group dùng chung giữa main app và Share Extension
    static let appGroupID = "group.techcave.quanlychitieu.shared"
    static let appGroupContainerURL: URL? = {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }()

    /// Thư mục inbox trong App Group — Share Extension ghi ảnh vào đây
    static var shareInboxURL: URL? {
        appGroupContainerURL?.appendingPathComponent("inbox", isDirectory: true)
    }

    /// UserDefaults dùng chung app + extension.
    /// Fallback về `.standard` khi App Group chưa provision (tránh warning CFPrefs trên simulator).
    static let sharedDefaults: SharedDefaults = {
        if let _ = appGroupContainerURL,
           let suite = UserDefaults(suiteName: appGroupID) {
            return SharedDefaults(defaults: suite)
        }
        return SharedDefaults(defaults: .standard)
    }()

    /// Key lưu thời điểm quét photo library gần nhất (catch-up scan)
    static let lastPhotoScanKey = "lastPhotoScanDate"
    /// Key giờ nhắc review cuối ngày "HH:mm", mặc định 21:00
    static let reviewReminderTimeKey = "reviewReminderTime"
}
