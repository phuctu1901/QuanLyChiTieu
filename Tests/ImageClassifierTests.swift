import XCTest
@testable import QuanLyChiTieu

/// Test phân loại ảnh: screenshot giao dịch → .transaction, ảnh thường → .unrelated.
/// Bộ reject test mô phỏng lại 18 screenshot thật của user (chat/ads/shopping).
final class ImageClassifierTests: XCTestCase {

    // MARK: - Ảnh giao dịch (phải được nhận)

    func testBankTransferScreenshot() {
        let lines = [
            "MB Bank",
            "Giao dich thanh cong",
            "Chuyen tien cho NGUYEN VAN A",
            "-500,000d",
            "17:34 - 15/08/2026",
        ]
        XCTAssertEqual(ImageClassifier.classify(lines: lines), .transaction)
    }

    func testNotificationBalanceChange() {
        let lines = [
            "Vietcombank",
            "TK 0071***888 VL",
            "Biến động số dư",
            "Giao dịch: +2,350,000 VND",
            "15/08/2026 17:34",
        ]
        XCTAssertEqual(ImageClassifier.classify(lines: lines), .transaction)
    }

    func testTransferWithoutBankNameButWithKeyword() {
        let lines = [
            "Chuyển tiền thành công",
            "Số tiền: 250.000đ",
            "Người nhận: TRAN THI B",
        ]
        XCTAssertEqual(ImageClassifier.classify(lines: lines), .transaction)
    }

    func testMoMoWallet() {
        let lines = [
            "Ví MoMo",
            "Thanh toán hóa đơn",
            "350,000đ",
        ]
        XCTAssertEqual(ImageClassifier.classify(lines: lines), .transaction)
    }

    func testBankAppWithoutActionButBankAndGiaoDich() {
        // Tên ngân hàng + "giao dịch" + tiền → nhận (kể cả không có từ "chuyển")
        let lines = [
            "Techcombank",
            "Lịch sử giao dịch",
            "Giá trị: 1.200.000 VND",
        ]
        XCTAssertEqual(ImageClassifier.classify(lines: lines), .transaction)
    }

    // MARK: - Screenshot chụp từ app banking (tên app trong UI + tiền là đủ)

    func testBankAppHomeScreenWithBalance() {
        // Màn chính app bank: số dư + tên app, không có chữ "giao dịch"/"chuyển khoản"
        let lines = [
            "21:34",
            "Techcombank",
            "Số dư khả dụng",
            "50.450.000 đ",
            "TK 1903 xxxx 888",
        ]
        XCTAssertEqual(ImageClassifier.classify(lines: lines), .transaction)
    }

    func testZaloPayScreenshot() {
        // ZaloPay = ví thanh toán — KHÔNG bị reject như Zalo chat
        let lines = [
            "ZaloPay",
            "Thanh toán hóa đơn",
            "350,000đ",
        ]
        XCTAssertEqual(ImageClassifier.classify(lines: lines), .transaction)
    }

    func testZaloChatStillRejected() {
        // Zalo chat thường vẫn bị reject kể cả khi nhắc số tiền
        let lines = [
            "Zalo",
            "Online Just Now",
            "chuyển giúp t 50.000 nhé",
        ]
        XCTAssertEqual(ImageClassifier.classify(lines: lines), .unrelated)
    }

    func testViettelMoneyScreenshot() {
        let lines = [
            "Viettel Money",
            "Số dư: 1.200.000đ",
        ]
        XCTAssertEqual(ImageClassifier.classify(lines: lines), .transaction)
    }

    func testBankAppUIWithChatSignalStillRejected() {
        // Screenshot chat (có "online just now") trong app có tên bank vẫn loại
        let lines = [
            "Techcombank",
            "Online Just Now",
            "50.000đ",
        ]
        XCTAssertEqual(ImageClassifier.classify(lines: lines), .unrelated)
    }

    func testBankAppNameWithoutMoneyRejected() {
        // Tên app bank nhưng không có số tiền → không phải giao dịch
        let lines = [
            "MB Bank",
            "Đăng nhập",
            "Tài khoản",
        ]
        XCTAssertEqual(ImageClassifier.classify(lines: lines), .unrelated)
    }

    // MARK: - Ảnh rác thật của user (phải bị loại)

    func testFacebookChat() {
        // img_006 thật: facebook header
        let lines = [
            "facebook",
            "Nhạc Trưởng • Thêm bạn bè",
            "11 giờ",
        ]
        XCTAssertEqual(ImageClassifier.classify(lines: lines), .unrelated)
    }

    func testMessengerChat() {
        // img_012-017 thật: Messenger + "Online Just Now"
        let lines = [
            "Messenger",
            "PA05. A TÚ. Đ3",
            "Online Just Now",
            "18:35",
            "25",
        ]
        XCTAssertEqual(ImageClassifier.classify(lines: lines), .unrelated)
    }

    func testZaloChatWithMoneyMention() {
        // Chat nhắc số tiền — vẫn phải loại vì là chat
        let lines = [
            "Zalo",
            "Online Just Now",
            "mai trả tao 50.000 nhé",
        ]
        XCTAssertEqual(ImageClassifier.classify(lines: lines), .unrelated)
    }

    func testSunwinGameAd() {
        // img_007 thật: quảng cáo game Sunwin có số điện thoại
        let lines = [
            "Sunwin. Mẹ Bảo.",
            "điện thoại (3)",
            "096 6720805",
            "G Việt Nam",
        ]
        XCTAssertEqual(ImageClassifier.classify(lines: lines), .unrelated)
    }

    func testShopeeOrder() {
        // Đơn hàng mua sắm có tiền — không phải giao dịch ngân hàng
        let lines = [
            "Shopee",
            "Đặt hàng thành công",
            "Tổng tiền: 254.000đ",
            "Vận đơn: SP12345",
        ]
        XCTAssertEqual(ImageClassifier.classify(lines: lines), .unrelated)
    }

    func testProductSpecSheet() {
        // img_001 thật: spec loa (số hiệu sản phẩm)
        let lines = [
            "NF-A4x10 5V EWM",
            "DC5V-0.35W-021A",
            "CE CA ROHS E",
        ]
        XCTAssertEqual(ImageClassifier.classify(lines: lines), .unrelated)
    }

    // MARK: - Ảnh thường khác

    func testSelfieOrPhotoWithoutMoney() {
        let lines = [
            "Cafe sáng nay",
            "Trời đẹp quá",
            "Với bạn bè",
        ]
        XCTAssertEqual(ImageClassifier.classify(lines: lines), .unrelated)
    }

    func testLandscapeWithYearOnly() {
        let lines = [
            "Đà Lạt 2026",
            "Chuyến đi tháng 8",
            "Rất tuyệt",
        ]
        XCTAssertEqual(ImageClassifier.classify(lines: lines), .unrelated)
    }

    func testFoodPhotoWithMenuText() {
        let lines = [
            "Phở bò đặc biệt",
            "45.000",
        ]
        // Có "45.000" nhưng không có hành động chuyển tiền, không tên ngân hàng → loại
        XCTAssertEqual(ImageClassifier.classify(lines: lines), .unrelated)
    }

    func testEnglishCakeTextIsNotBank() {
        // "cake" không còn khớp ngân hàng Cake by VPBank — text bánh ngọt phải bị loại
        let lines = [
            "Birthday cake recipe",
            "Price: 250.000",
        ]
        XCTAssertEqual(ImageClassifier.classify(lines: lines), .unrelated)
    }

    // MARK: - Ảnh đọc không được

    func testEmptyLines() {
        XCTAssertEqual(ImageClassifier.classify(lines: []), .unreadable)
        XCTAssertEqual(ImageClassifier.classify(lines: ["", "  "]), .unreadable)
    }

    func testAccountNumberOnlyIsNotTransaction() {
        let lines = [
            "Số tài khoản",
            "0123456789",
        ]
        XCTAssertEqual(ImageClassifier.classify(lines: lines), .unrelated)
    }
}
