import Foundation
import SwiftData

/// Seed các phân loại chi tiêu mặc định (idempotent theo name).
enum CategorySeeder {
    static let defaults: [(name: String, icon: String, color: String)] = [
        ("Ăn uống", "fork.knife", "#FF9500"),
        ("Di chuyển", "car.fill", "#34C759"),
        ("Mua sắm", "bag.fill", "#AF52DE"),
        ("Hoá đơn", "doc.text.fill", "#5856D6"),
        ("Giải trí", "gamecontroller.fill", "#FF2D55"),
        ("Sức khoẻ", "heart.fill", "#FF3B30"),
        ("Giáo dục", "book.fill", "#007AFF"),
        ("Chuyển tiền", "arrow.left.arrow.right", "#5AC8FA"),
        ("Nạp tiền/Điện thoại", "iphone", "#32ADE6"),
        ("Khác", "ellipsis.circle", "#8E8E93"),
    ]

    static func seedIfNeeded(context: ModelContext) {
        let name = FetchDescriptor<SpendingCategory>()
        let existing = (try? context.fetchCount(name)) ?? 0
        guard existing == 0 else { return }
        for item in defaults {
            context.insert(SpendingCategory(
                name: item.name,
                iconName: item.icon,
                colorHex: item.color,
                isDefault: true
            ))
        }
        try? context.save()
    }
}
