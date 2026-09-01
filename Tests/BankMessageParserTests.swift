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
        XCTAssertNotNil(r.note)
    }
}
