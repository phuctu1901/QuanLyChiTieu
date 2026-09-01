import Foundation
import SwiftData

@Model
final class CategoryBudget {
    var limitAmount: Int = 0

    var category: SpendingCategory?
    var monthlyBudget: MonthlyBudget?

    init(category: SpendingCategory, limitAmount: Int) {
        self.limitAmount = limitAmount
        self.category = category
    }
}

@Model
final class MonthlyBudget {
    #Unique<MonthlyBudget>([\.year, \.month])

    var id: UUID = UUID()
    var year: Int = 0
    var month: Int = 0
    var totalLimit: Int?
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \CategoryBudget.monthlyBudget)
    var categoryLimits: [CategoryBudget] = []

    init(year: Int, month: Int, totalLimit: Int? = nil) {
        self.id = UUID()
        self.year = year
        self.month = month
        self.totalLimit = totalLimit
        self.createdAt = Date()
    }
}
