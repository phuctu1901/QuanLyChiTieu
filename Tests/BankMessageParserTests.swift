import XCTest
@testable import QuanLyChiTieu

final class BankMessageParserTests: XCTestCase {

    func testParseVNNumber() {
        XCTAssertEqual(BankMessageParser.parseVNNumber("50.000"), 50000)
        XCTAssertEqual(BankMessageParser.parseVNNumber("50,000"), 50000)
        XCTAssertEqual(BankMessageParser.parseVNNumber("1,200,000"), 1200000)
        XCTAssertEqual(BankMessageParser.parseVNNumber("50000"), 50000)
    }

    func testExtractAmountVariants() {
        XCTAssertEqual(BankMessageParser.extractAmount(from: "Số tiền: -50,000đ")?.amount, 50000)
        XCTAssertEqual(BankMessageParser.extractAmount(from: "-50.000 VND")?.sign, "-")
        XCTAssertEqual(BankMessageParser.extractAmount(from: "+1.500.000đ nhận tiền")?.amount, 1500000)
        XCTAssertEqual(BankMessageParser.extractAmount(from: "+1.500.000đ nhận tiền")?.sign, "+")
        XCTAssertNil(BankMessageParser.extractAmount(from: "TK 0123456789012"))
        XCTAssertEqual(BankMessageParser.extractAmount(from: "Thanh toán 250.000")?.amount, 250000)
    }

    // MARK: - Số tiền kèm đơn vị VND (format app bank thật)

    func testExtractAmountUnitBefore() {
        // "VND 500,000" — đơn vị đứng trước
        XCTAssertEqual(BankMessageParser.extractAmount(from: "VND 500,000")?.amount, 500000)
        XCTAssertEqual(BankMessageParser.extractAmount(from: "Số tiền: VND 1.500.000")?.amount, 1500000)
    }

    func testExtractAmountUnitAfter() {
        XCTAssertEqual(BankMessageParser.extractAmount(from: "500,000 VND")?.amount, 500000)
        XCTAssertEqual(BankMessageParser.extractAmount(from: "1.500.000đ")?.amount, 1500000)
        XCTAssertEqual(BankMessageParser.extractAmount(from: "₫250,000")?.amount, 250000)
    }

    func testTransactionAmountBeatsBiggerBalance() {
        // Screenshot có cả số dư (lớn hơn) và tiền giao dịch có dấu +/-:
        // phải chọn tiền GIAO DỊCH (có sign), không chọn số dư
        let lines = [
            "MB Bank",
            "Số dư khả dụng: 50.450.000đ",
            "Giao dịch: -350,000 VND",
            "Nội dung: CHUYEN TIEN CHO ANH MINH",
        ]
        let r = BankMessageParser.parse(lines)
        XCTAssertEqual(r.amount, 350000, "Phải chọn tiền giao dịch có dấu, không phải số dư")
    }

    func testAmountWithUnitBeatsBiggerBareNumber() {
        // Số có đơn vị thắng số trần lớn hơn (số trần khả năng là TK/năm)
        let lines = [
            "Vietcombank",
            "Giao dịch thành công",
            "TK 0071000812345",
            "Số tiền 250.000 VND",
        ]
        let r = BankMessageParser.parse(lines)
        XCTAssertEqual(r.amount, 250000)
    }

    func testDetectBank() {
        XCTAssertEqual(BankMessageParser.detectBank(["MB Bank", "Giao dịch thành công"]), "MB Bank")
        XCTAssertEqual(BankMessageParser.detectBank(["Vietcombank Digibank"]), "Vietcombank")
        XCTAssertEqual(BankMessageParser.detectBank(["Techcombank"]), "Techcombank")
        XCTAssertEqual(BankMessageParser.detectBank(["Ví MoMo"]), "Ví MoMo")
    }

    func testDetectDate() {
        let date = BankMessageParser.detectDate(["15/08/2026 21:34", "Giao dịch thành công"])
        XCTAssertNotNil(date)
        let c = Calendar.current.dateComponents([.day, .month, .year, .hour, .minute], from: date!)
        XCTAssertEqual(c.day, 15)
        XCTAssertEqual(c.month, 8)
        XCTAssertEqual(c.year, 2026)
        XCTAssertEqual(c.hour, 21)
        XCTAssertEqual(c.minute, 34)
    }

    // MARK: -detectDateWithSource — các format thật hay gặp

    func testDateSourceFullDateTime() {
        let (date, source) = BankMessageParser.detectDateWithSource(["21:34 - 15/08/2026"])
        XCTAssertEqual(source, .fullDateTime)
        let c = Calendar.current.dateComponents([.day, .month, .year, .hour, .minute], from: date!)
        XCTAssertEqual(c.day, 15); XCTAssertEqual(c.month, 8)
        XCTAssertEqual(c.hour, 21); XCTAssertEqual(c.minute, 34)
    }

    func testDateSourceDateWithStatusBarTime() {
        // Screenshot thật: giờ status bar "17:34" dòng đầu + ngày đầy đủ dòng dưới
        let (date, source) = BankMessageParser.detectDateWithSource([
            "17:34",
            "Vietcombank",
            "Ngày giao dịch: 15/08/2026",
            "-500,000đ",
        ])
        XCTAssertEqual(source, .dateWithStatusBarTime)
        let c = Calendar.current.dateComponents([.day, .month, .hour], from: date!)
        XCTAssertEqual(c.day, 15); XCTAssertEqual(c.month, 8); XCTAssertEqual(c.hour, 17)
    }

    func testDateSourceDateOnly() {
        // Ngày không giờ, không có giờ status bar → dateOnly, giờ 0:00
        let (date, source) = BankMessageParser.detectDateWithSource([
            "Ngày: 15/08/2026",
            "Số tiền: 50.000đ",
        ])
        XCTAssertEqual(source, .dateOnly)
        let c = Calendar.current.dateComponents([.day, .hour, .minute], from: date!)
        XCTAssertEqual(c.day, 15); XCTAssertEqual(c.hour, 0); XCTAssertEqual(c.minute, 0)
    }

    func testDateSourceIOSVietnameseFormat() {
        // Format iOS tiếng Việt: "15 thg 8, 2026"
        let (date, source) = BankMessageParser.detectDateWithSource(["15 thg 8, 2026", "500.000đ"])
        XCTAssertEqual(source, .dateOnly)
        let c = Calendar.current.dateComponents([.day, .month, .year], from: date!)
        XCTAssertEqual(c.day, 15); XCTAssertEqual(c.month, 8); XCTAssertEqual(c.year, 2026)
    }

    func testDateSourceNoYear() {
        // "15/08" không năm → năm hiện tại
        let (date, source) = BankMessageParser.detectDateWithSource(["Ngày 15/08", "Chuyển khoản 200.000đ"])
        XCTAssertEqual(source, .dateOnly)
        let c = Calendar.current.dateComponents([.day, .month, .year], from: date!)
        XCTAssertEqual(c.day, 15); XCTAssertEqual(c.month, 8)
        XCTAssertEqual(c.year, Calendar.current.component(.year, from: Date()))
    }

    func testDateSourceUnknown() {
        let (date, source) = BankMessageParser.detectDateWithSource(["Chuyển khoản", "50.000đ"])
        XCTAssertNil(date)
        XCTAssertEqual(source, .unknown)
    }

    func testFallbackToScreenshotTime() {
        // OCR không ra ngày → dùng giờ chụp screenshot
        let parsed = ParsedTransaction(
            from: BankMessageParser.parse(["Chuyển khoản", "50.000đ"]),
            screenshotTakenAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        XCTAssertEqual(parsed.occurredAtSource, .screenshotTime)
        XCTAssertEqual(parsed.occurredAt, Date(timeIntervalSince1970: 1_800_000_000))
    }

    func testParsedTransactionDecodeOldDataWithoutSource() {
        // Data cũ không có occurredAtSource → decode không crash, source = nil
        let json = #"{"amount":50000,"direction":"expense","occurredAt":700000000.0,"note":"test"}"#
        let data = json.data(using: .utf8)!
        let parsed = try? JSONDecoder().decode(ParsedTransaction.self, from: data)
        XCTAssertNotNil(parsed)
        XCTAssertNil(parsed?.occurredAtSource)
    }

    func testParseFullScreenshot() {
        let lines = [
            "MB Bank",
            "Giao dịch thành công",
            "Chuyen tien DOI PHUONG",
            "-500,000đ",
            "17:34 - 15/08/2026",
        ]
        let r = BankMessageParser.parse(lines)
        XCTAssertEqual(r.amount, 500000)
        XCTAssertEqual(r.direction, .expense)
        XCTAssertEqual(r.bankName, "MB Bank")
        XCTAssertEqual(r.suggestedCategoryName, "Chuyển tiền")
        XCTAssertNotNil(r.occurredAt)
        // Note do user tự viết — parser không tự điền từ OCR
        XCTAssertNil(r.note)
    }

    func testDetectContactNameMultiLine() {
        // Tên trên 2 dòng
        let lines1 = [
            "Tên người thụ hưởng:",
            "CONG TY TNHH",
            "DICH VU ABC"
        ]
        XCTAssertEqual(BankMessageParser.detectContactName(lines1), "CONG TY TNHH DICH VU ABC")

        // Tên bắt đầu trên cùng dòng nhãn, nhưng dài qua 2 dòng tiếp theo
        let lines2 = [
            "Tên người thụ hưởng: CONG TY TNHH",
            "THUONG MAI",
            "DICH VU ABC"
        ]
        XCTAssertEqual(BankMessageParser.detectContactName(lines2), "CONG TY TNHH THUONG MAI DICH VU ABC")

        // Tên chứa 1 ký tự hợp lệ ở dòng sau (như A)
        let lines3 = [
            "Người thụ hưởng",
            "NGUYEN VAN",
            "A"
        ]
        XCTAssertEqual(BankMessageParser.detectContactName(lines3), "NGUYEN VAN A")
    }
}
