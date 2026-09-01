import Foundation
import SwiftData

enum IngestOutcome: Equatable {
    case created
    case duplicate
    case failed
}

/// Sản phẩm trung gian sau OCR + parse, trước khi ghi vào SwiftData.
struct PendingProduct: Sendable {
    let hash: String
    let path: String
    let rawText: String
    let parsed: ParsedTransaction
    let source: Source
}

extension ParsedTransaction {
    init(from r: BankParseResult) {
        self.init(
            amount: r.amount,
            direction: r.direction,
            occurredAt: r.occurredAt,
            note: r.note,
            bankName: r.bankName,
            suggestedCategoryName: r.suggestedCategoryName
        )
    }
}

/// Orchestrator: ảnh → hash/save → OCR → parse → PendingExtraction.
/// Actor để tránh đua khi 3 nguồn (photo scan, share ext, picker) gọi đồng thời.
/// Phần ghi DB delegate cho `persist` (MainActor) — SwiftData context không rời main actor.
actor ExtractionPipeline {
    typealias Persister = @MainActor (PendingProduct) -> IngestOutcome

    let imageStore: ImageStore
    let ocr: OCRService
    let persist: Persister

    init(imageStore: ImageStore, ocr: OCRService = OCRService(), persist: @escaping Persister) {
        self.imageStore = imageStore
        self.ocr = ocr
        self.persist = persist
    }

    /// Xử lý ảnh từ bất kỳ nguồn nào (auto-scan / share ext / picker).
    @discardableResult
    func ingest(imageData: Data, source: Source) async -> IngestOutcome {
        // 1) Lưu file + hash
        guard let saved = imageStore.save(imageData) else { return .failed }
        let (hash, path) = saved

        // 2) OCR
        let lines: [String]
        do {
            lines = try await ocr.recognizeLines(imageData: imageData)
        } catch {
            imageStore.delete(path: path)
            return .failed
        }
        let rawText = lines.joined(separator: "\n")

        // 3) Parse — parse không ra tiền vẫn tạo pending để user tự nhập từ ảnh
        let parsed = ParsedTransaction(from: BankMessageParser.parse(lines))

        // 4) Dedup + ghi DB trên main actor
        let product = PendingProduct(hash: hash, path: path, rawText: rawText, parsed: parsed, source: source)
        return await persist(product)
    }
}

/// Ghi PendingExtraction vào SwiftData (MainActor).
@MainActor
final class PendingStore {
    let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func persist(_ product: PendingProduct) -> IngestOutcome {
        let context = ModelContext(container)

        // Dedup cấp ảnh: hash đã có pending (kể cả đã resolve)
        let hash = product.hash
        let hashPredicate = #Predicate<PendingExtraction> { $0.imageHash == hash }
        let hashDesc = FetchDescriptor<PendingExtraction>(predicate: hashPredicate)
        if (try? context.fetchCount(hashDesc)) ?? 0 > 0 {
            return .duplicate
        }

        let pending = PendingExtraction(
            imageHash: product.hash,
            imagePath: product.path,
            ocrRawText: product.rawText,
            parsed: product.parsed,
            source: product.source
        )
        context.insert(pending)
        do {
            try context.save()
            return .created
        } catch {
            return .duplicate
        }
    }
}
