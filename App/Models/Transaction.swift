import Foundation
import SwiftData
import CryptoKit

enum Direction: String, Codable {
    case expense
    case income
}

enum Source: String, Codable {
    case ocrAutoScan
    case shareExt
    case manualPhoto
    case cash
}

@Model
final class Transaction {
    #Unique<Transaction>([\.dedupKey])

    var id: UUID = UUID()
    var amount: Int = 0
    var directionRaw: String = Direction.expense.rawValue
    var occurredAt: Date = Date()
    var note: String = ""
    var bankName: String?
    var sourceRaw: String = Source.manualPhoto.rawValue
    var imagePath: String?
    var confirmedAt: Date?
    var createdAt: Date = Date()
    var dedupKey: String = UUID().uuidString

    var category: SpendingCategory?

    var direction: Direction {
        get { Direction(rawValue: directionRaw) ?? .expense }
        set { directionRaw = newValue.rawValue }
    }

    var source: Source {
        get { Source(rawValue: sourceRaw) ?? .manualPhoto }
        set { sourceRaw = newValue.rawValue }
    }

    /// dedupKey = SHA256(bank + amount + occurredAt + normalizedNote) — 2 ảnh khác nhau cùng 1 giao dịch → trùng key.
    static func dedupKey(bankName: String?, amount: Int, occurredAt: Date, note: String) -> String {
        let time = Int(occurredAt.timeIntervalSince1970)
        let normalizedNote = note.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = "\(bankName ?? "")|\(abs(amount))|\(time)|\(normalizedNote)"
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    init(
        amount: Int,
        direction: Direction,
        occurredAt: Date,
        note: String,
        bankName: String? = nil,
        source: Source,
        imagePath: String? = nil,
        dedupKey: String
    ) {
        self.id = UUID()
        self.amount = abs(amount)
        self.directionRaw = direction.rawValue
        self.occurredAt = occurredAt
        self.note = note
        self.bankName = bankName
        self.sourceRaw = source.rawValue
        self.imagePath = imagePath
        self.confirmedAt = Date()
        self.createdAt = Date()
        self.dedupKey = dedupKey
    }
}
