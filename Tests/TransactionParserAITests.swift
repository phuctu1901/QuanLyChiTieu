import XCTest
@testable import QuanLyChiTieu

/// Test logic merge AI ↔ regex (model thật chỉ chạy trên máy có Apple Intelligence).
final class TransactionParserAITests: XCTestCase {

    private func makeRegex(amount: Int?, occurredAt: Date? = nil, note: String? = nil) -> ParsedTransaction {
        ParsedTransaction(from: BankParseResult(
            amount: amount, direction: .expense,
            occurredAt: occurredAt, occurredAtSource: occurredAt != nil ? .fullDateTime : .unknown,
            note: note, bankName: nil, suggestedCategoryName: nil
        ))
    }

    // MARK: - AI confident (>= 0.5): AI là parser chính, đè regex

    func testConfidentAIOverridesRegexAmount() {
        // Regex sai (nhặt số dư) → AI đúng (tiền giao dịch) → AI đè
        let regex = makeRegex(amount: 50_450_000, note: "regex note")
        let ai = AIParseResult(
            amount: 350_000, occurredAtISO: nil, bankName: nil,
            counterAccount: nil, transactionCode: nil, category: nil,
            isIncome: false, confidence: 0.9, balanceAfter: 50_450_000
        )
        let merged = TransactionParserAI.merge(regex: regex, ai: ai)
        XCTAssertEqual(merged.amount, 350_000)
    }

    func testConfidentAIFillsAllFields() {
        let regex = makeRegex(amount: nil)
        let ai = AIParseResult(
            amount: 1_500_000,
            occurredAtISO: "2026-08-15T21:34:00",
            bankName: "MB Bank",
            counterAccount: "0123456789",
            transactionCode: "FT26081512345678",
            category: "Chuyển tiền",
            isIncome: true, confidence: 0.95, balanceAfter: nil
        )
        let merged = TransactionParserAI.merge(regex: regex, ai: ai)
        XCTAssertEqual(merged.amount, 1_500_000)
        XCTAssertEqual(merged.bankName, "MB Bank")
        XCTAssertEqual(merged.direction, .income)
        XCTAssertEqual(merged.suggestedCategoryName, "Chuyển tiền")
        XCTAssertNotNil(merged.occurredAt)
        XCTAssertEqual(merged.occurredAtSource, .fullDateTime)
    }

    func testAINeverTouchesNote() {
        // Ghi chú là của user — AI không điền dù tự tin cao
        var regex = makeRegex(amount: 50_000, note: "ghi chú của tôi")
        let ai = AIParseResult(
            amount: 99, occurredAtISO: nil, bankName: nil,
            counterAccount: nil, transactionCode: nil, category: nil,
            isIncome: false, confidence: 1.0, balanceAfter: nil
        )
        regex = TransactionParserAI.merge(regex: regex, ai: ai)
        XCTAssertEqual(regex.note, "ghi chú của tôi", "AI không được đè note của user")
    }

    func testConfidentAIKeepsRegexForNilFields() {
        // AI bỏ sót bank → giữ của regex
        var regex = makeRegex(amount: 50_000, note: "regex note")
        regex.bankName = "Techcombank"
        let ai = AIParseResult(
            amount: 50_000, occurredAtISO: nil, bankName: nil,
            counterAccount: nil, transactionCode: nil, category: nil,
            isIncome: false, confidence: 0.8, balanceAfter: nil
        )
        let merged = TransactionParserAI.merge(regex: regex, ai: ai)
        XCTAssertEqual(merged.note, "regex note")
        XCTAssertEqual(merged.bankName, "Techcombank")
    }

    // MARK: - AI không tự tin (< 0.5): chỉ đắp chỗ regex thiếu

    func testLowConfidenceAIDoesNotOverride() {
        let regex = makeRegex(amount: 123_000)
        let ai = AIParseResult(
            amount: 999_999, occurredAtISO: nil, bankName: nil,
            counterAccount: nil, transactionCode: nil, category: nil,
            isIncome: false, confidence: 0.3, balanceAfter: nil
        )
        let merged = TransactionParserAI.merge(regex: regex, ai: ai)
        XCTAssertEqual(merged.amount, 123_000, "AI không tự tin → không đè regex")
    }

    func testLowConfidenceAIFillsMissingOnly() {
        let regex = makeRegex(amount: nil)
        let ai = AIParseResult(
            amount: 500_000, occurredAtISO: nil, bankName: nil,
            counterAccount: nil, transactionCode: nil, category: nil,
            isIncome: false, confidence: 0.4, balanceAfter: nil
        )
        let merged = TransactionParserAI.merge(regex: regex, ai: ai)
        XCTAssertEqual(merged.amount, 500_000, "AI không tự tin nhưng regex thiếu → đắp vào chỗ trống")
    }

    // MARK: - ISO parse

    func testParseISOVariants() {
        XCTAssertNotNil(TransactionParserAI.parseISO("2026-08-15T21:34:00"))
        XCTAssertNil(TransactionParserAI.parseISO("khong phai ngay"))
        XCTAssertNil(TransactionParserAI.parseISO(""))
        // Giữ nguyên giờ local — không dịch múi giờ
        let date = TransactionParserAI.parseISO("2026-08-15T21:34:00")!
        let c = Calendar.current.dateComponents([.day, .hour, .minute], from: date)
        XCTAssertEqual(c.day, 15)
        XCTAssertEqual(c.hour, 21)
        XCTAssertEqual(c.minute, 34)
    }
}
