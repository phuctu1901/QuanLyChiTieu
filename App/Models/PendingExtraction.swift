import Foundation
import SwiftData

/// Kết quả bóc tách từ OCR — struct Codable thuần, không phải @Model.
struct ParsedTransaction: Codable, Equatable {
    var amount: Int?
    var direction: Direction = .expense
    var occurredAt: Date?
    var note: String?
    var bankName: String?
    var suggestedCategoryName: String?

    /// Số field parse được / tổng field quan trọng (0...1)
    var confidence: Double {
        let fields: [Bool] = [amount != nil, occurredAt != nil, note?.isEmpty == false, bankName != nil]
        return Double(fields.filter { $0 }.count) / Double(fields.count)
    }
}

@Model
final class PendingExtraction {
    #Unique<PendingExtraction>([\.imageHash])

    var id: UUID = UUID()
    var imageHash: String = ""
    var imagePath: String = ""
    var ocrRawText: String = ""
    var parsedData: Data?
    var confidence: Double = 0
    var createdAt: Date = Date()
    var resolvedAt: Date?
    var sourceRaw: String = Source.manualPhoto.rawValue

    var source: Source {
        get { Source(rawValue: sourceRaw) ?? .manualPhoto }
        set { sourceRaw = newValue.rawValue }
    }

    var parsed: ParsedTransaction? {
        get {
            guard let data = parsedData else { return nil }
            return try? JSONDecoder().decode(ParsedTransaction.self, from: data)
        }
        set {
            guard let value = newValue, let data = try? JSONEncoder().encode(value) else {
                parsedData = nil
                return
            }
            parsedData = data
        }
    }

    /// Transaction đã tạo từ pending này (non-nil = đã resolve)
    var resolvedTransaction: Transaction?

    init(
        imageHash: String,
        imagePath: String,
        ocrRawText: String,
        parsed: ParsedTransaction?,
        source: Source
    ) {
        self.id = UUID()
        self.imageHash = imageHash
        self.imagePath = imagePath
        self.ocrRawText = ocrRawText
        self.parsed = parsed
        self.confidence = parsed?.confidence ?? 0
        self.createdAt = Date()
        self.sourceRaw = source.rawValue
    }
}
