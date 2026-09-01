import Foundation
import SwiftData

@Model
final class SpendingCategory {
    var id: UUID = UUID()
    var name: String = ""
    var iconName: String = "questionmark.circle"
    var colorHex: String = "#007AFF"
    var isDefault: Bool = false
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction] = []

    init(name: String, iconName: String, colorHex: String, isDefault: Bool = false) {
        self.id = UUID()
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.isDefault = isDefault
        self.createdAt = Date()
    }
}
