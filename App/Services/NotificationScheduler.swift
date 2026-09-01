import Foundation
import UserNotifications

/// Lập lịch local notification nhắc review cuối ngày.
enum NotificationScheduler {
    static let notificationID = "daily-review-reminder"

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Lập lịch nhắc hằng ngày theo "HH:mm" (mặc định 21:00).
    static func scheduleDailyReminder(time: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])

        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return }
        var comps = DateComponents()
        comps.hour = parts[0]
        comps.minute = parts[1]

        let content = UNMutableNotificationContent()
        content.title = "Đã đến giờ tổng kết chi tiêu"
        content.body = "Mở app để xác nhận các giao dịch đã bóc tách và nhập chi tiền mặt hôm nay."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
        center.add(request)
    }
}
