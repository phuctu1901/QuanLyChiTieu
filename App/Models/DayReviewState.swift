import Foundation
import SwiftData

@Model
final class DayReviewState {
    #Unique<DayReviewState>([\.day])

    var id: UUID = UUID()
    /// "yyyy-MM-dd" theo giờ địa phương
    var day: String = ""
    var completedAt: Date = Date()

    init(day: String) {
        self.id = UUID()
        self.day = day
        self.completedAt = Date()
    }
}
