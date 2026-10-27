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

enum TransactionType: String, Codable {
    case normal         // Chi tiêu / Thu nhập bình thường
    case loanGiven      // Mình cho người khác mượn tiền (Tiền ra, nhưng không phải expense)
    case loanCollected  // Người khác trả tiền cho mình (Tiền vào, nhưng không phải income)
    case borrowed       // Mình mượn tiền người khác (Tiền vào, nhưng không phải income)
    case debtPaid       // Mình trả nợ người khác (Tiền ra, nhưng không phải expense)
}

@Model
final class Transaction {
    #Unique<Transaction>([\.dedupKey])

    var id: UUID = UUID()
    var amount: Int = 0
    var directionRaw: String = Direction.expense.rawValue
    var typeRaw: String = TransactionType.normal.rawValue
    var contactName: String?
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

    var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .normal }
        set { typeRaw = newValue.rawValue }
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
        type: TransactionType = .normal,
        contactName: String? = nil,
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
        self.typeRaw = type.rawValue
        self.contactName = contactName
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
