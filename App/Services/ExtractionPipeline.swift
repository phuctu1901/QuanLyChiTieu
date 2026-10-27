import Foundation
import SwiftData

enum IngestOutcome: Equatable {
    case created
    case duplicate
    case failed
    /// Ảnh bị loại vì không phải giao dịch ngân hàng/chuyển khoản.
    case notTransaction
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
    init(from r: BankParseResult, screenshotTakenAt: Date? = nil) {
        // Ảnh không có ngày → fallback giờ chụp screenshot (giao dịch thường chụp ngay)
        let occurredAt: Date?
        let source: OccurredAtSource
        if let date = r.occurredAt {
            occurredAt = date
            source = r.occurredAtSource
        } else if let taken = screenshotTakenAt {
            occurredAt = taken
            source = .screenshotTime
        } else {
            occurredAt = nil
            source = .unknown
        }
        self.init(
            amount: r.amount,
            direction: r.direction,
            occurredAt: occurredAt,
            occurredAtSource: source,
            note: r.note,
            bankName: r.bankName,
            contactName: r.contactName,
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
    /// Tầng 0 Core ML: phân loại ảnh bằng model train sẵn — nhanh, ổn định.
    var coreMLClassifier: CoreMLClassifier?
    /// Tầng 1 AI: lọc "ảnh có giao dịch?" — nil khi AI không khả dụng.
    let aiClassifier: ImageAIClassifier?
    /// Tầng 2 AI: bóc tách giao dịch — nil khi AI không khả dụng.
    let aiParser: TransactionParserAI?

    init(imageStore: ImageStore, ocr: OCRService = OCRService(), persist: @escaping Persister) {
        self.imageStore = imageStore
        self.ocr = ocr
        self.persist = persist
        self.coreMLClassifier = CoreMLClassifier()
        self.aiClassifier = ImageAIClassifier()
        self.aiParser = TransactionParserAI()
    }

    /// Tải lại model Core ML (gọi khi user đổi cấu hình trong Settings)
    func reloadModel() {
        self.coreMLClassifier = CoreMLClassifier()
    }

    /// Xử lý ảnh từ bất kỳ nguồn nào (auto-scan / share ext / picker).
    /// Ảnh không phải giao dịch bị loại trước khi lưu (trừ nguồn chọn tay).
    /// `screenshotTakenAt`: giờ chụp ảnh — fallback thời điểm khi OCR không ra ngày.
    @discardableResult
    func ingest(
        imageData: Data,
        source: Source,
        skipClassification: Bool = false,
        screenshotTakenAt: Date? = nil
    ) async -> IngestOutcome {
        // 0) Phân loại — 3 tầng:
        // Tầng 0 Core ML: model train sẵn (nhanh, không cần Apple Intelligence).
        // Tầng 1 AI: FoundationModels (nếu Core ML không chắc chắn).
        // Tầng 2 Keyword: ImageClassifier regex/keyword (fallback cuối).
        // (Nguồn chọn tay trong picker không lọc — user đã chủ động chọn.)
        if !skipClassification {
            guard await classifyImage(imageData: imageData) else {
                return .notTransaction
            }
        }

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

        // 3) Parse: AI là parser chính (bóc toàn bộ field + category + confidence).
        /// AI unavailable/lỗi/thiếu text → fallback regex. Kết quả luôn qua user xác nhận.
        var parsed = ParsedTransaction(
            from: BankMessageParser.parse(lines),
            screenshotTakenAt: screenshotTakenAt
        )
        if let ai = aiParser, let aiResult = await ai.parse(lines: lines) {
            parsed = TransactionParserAI.merge(regex: parsed, ai: aiResult)
        }

        // 4) Dedup + ghi DB trên main actor
        let product = PendingProduct(hash: hash, path: path, rawText: rawText, parsed: parsed, source: source)
        return await persist(product)
    }

    /// Phân loại ảnh 3 tầng:
    /// 1. Core ML (model train sẵn) — nhanh nhất, ổn định nhất
    /// 2. FoundationModels AI — linh hoạt hơn keyword
    /// 3. Keyword/regex — fallback cuối
    func classifyImage(imageData: Data) async -> Bool {
        // Tầng 0: Core ML — chạy trên Neural Engine, không cần Apple Intelligence
        if let coreML = coreMLClassifier,
           let result = coreML.classify(imageData: imageData) {
            // Core ML tự tin → dùng luôn
            if result.confidence >= CoreMLClassifier.threshold {
                return result.isTransaction
            }
            // Core ML không chắc → tiếp tầng sau
        }

        // Tầng 1: OCR + AI/keyword
        guard let lines = try? await ocr.recognizeLines(imageData: imageData) else {
            return false
        }

        // Tầng 1a: FoundationModels AI
        if let ai = aiClassifier, let verdict = await ai.classify(lines: lines) {
            if verdict.confidence >= 0.7 {
                return verdict.isTransaction
            }
            if verdict.isTransaction { return true }
            return ImageClassifier.classify(lines: lines) == .transaction
        }
        // Tầng 2: keyword classifier
        return ImageClassifier.classify(lines: lines) == .transaction
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
