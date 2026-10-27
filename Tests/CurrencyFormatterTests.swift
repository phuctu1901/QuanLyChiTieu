import XCTest
@testable import QuanLyChiTieu

/// Test format nhóm 3 chữ số cho ô nhập số tiền.
final class CurrencyFormatterTests: XCTestCase {

    func testGroupDigits() {
        XCTAssertEqual(CurrencyFormatter.groupDigits(""), "")
        XCTAssertEqual(CurrencyFormatter.groupDigits("0"), "0")
        XCTAssertEqual(CurrencyFormatter.groupDigits("500"), "500")
        XCTAssertEqual(CurrencyFormatter.groupDigits("5000"), "5.000")
        XCTAssertEqual(CurrencyFormatter.groupDigits("50000"), "50.000")
        XCTAssertEqual(CurrencyFormatter.groupDigits("1234567"), "1.234.567")
        XCTAssertEqual(CurrencyFormatter.groupDigits("2000000000"), "2.000.000.000")
    }

    func testGroupDigitsIgnoresNonDigits() {
        // Paste "1.234.567đ" → normalize về "1234567" rồi nhóm lại
        XCTAssertEqual(CurrencyFormatter.groupDigits("1.234.567đ"), "1.234.567")
        XCTAssertEqual(CurrencyFormatter.groupDigits("500,000 VND"), "500.000")
    }

    func testGroupDigitsRoundTripWithAmountParse() {
        // Format xong vẫn parse lại đúng số bằng filter(\.isNumber) như production
        let formatted = CurrencyFormatter.groupDigits("1234567")
        XCTAssertEqual(Int(formatted.filter(\.isNumber)), 1_234_567)
    }
}
