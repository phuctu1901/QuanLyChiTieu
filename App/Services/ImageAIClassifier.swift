import Foundation
import FoundationModels

/// Structured output: ảnh có chứa giao dịch ngân hàng/chuyển khoản không?
@Generable
struct AIClassification {
    @Guide(description: "true nếu text thuộc về: thông báo/app ngân hàng, biên lai chuyển khoản/thanh toán, biến động số dư, ví điện tử (MoMo/ZaloPay/Viettel Money). false nếu: chat mạng xã hội, quảng cáo, đơn hàng mua sắm, ảnh thường, spec sản phẩm, game.")
    var isTransaction: Bool

    @Guide(description: "Độ tin cậy 0.0-1.0 của quyết định trên.")
    var confidence: Double

    @Guide(description: "Lý do ngắn tiếng Việt. VD: 'Có tên ngân hàng + số tiền + chữ chuyển khoản' hoặc 'Chat Messenger thường'.")
    var reason: String
}

/// Tầng 1 AI: quyết định text OCR có phải screenshot giao dịch ngân hàng không.
/// Thay ImageClassifier (keyword) khi AI khả dụng — linh hoạt hơn danh sách từ khoá
/// cứng, bắt được các case keyword không foresee (app bank mới, format lạ).
///
/// Tầng 2 (TransactionParserAI) chỉ chạy khi tầng 1 trả true.
/// ImageClassifier keyword giữ làm fallback khi AI unavailable/lỗi.
struct ImageAIClassifier {

    /// Kiểm tra AI available — dùng switch trên availability enum
    /// thay vì boolean isAvailable (có thể trap khi model chưa sẵn sàng).
    static var isAvailable: Bool {
        guard #available(iOS 26, *) else { return false }
        switch SystemLanguageModel.default.availability {
        case .available:
            return true
        default:
            return false
        }
    }

    let session: LanguageModelSession

    init?() {
        guard Self.isAvailable else { return nil }
        session = LanguageModelSession(instructions: """
            BẠN CHỈ XỬ LÝ TIẾNG VIỆT. Mọi output phải bằng tiếng Việt.
            Bạn lọc screenshot từ thư viện ảnh điện thoại: quyết định text có phải
            của GIAO DỊCH NGÂN HÀNG/CHUYỂN KHOẢN/THANH TOÁN tại Việt Nam không.

            NHẬN (true) — các dạng:
            - App ngân hàng VN: MB, Vietcombank, Techcombank, VPBank, BIDV, TPBank,
              ACB, Agribank... (màn hình chuyển tiền, thành công, lịch sử, số dư
              có giao dịch, thông báo biến động)
            - SMS/push notification biến động số dư, chuyển khoản thành công
            - Ví điện tử VN: MoMo, ZaloPay, Viettel Money, VNPay (thanh toán/chuyển)
            - Biên lai/hóa đơn thanh toán có tên ngân hàng VN + số tiền VNĐ

            LOẠI (false) — các dạng:
            - Chat/mạng xã hội: Messenger, Facebook, Zalo (chat), Instagram, TikTok,
                Telegram — kể cả khi nhắc đến tiền trong đoạn chat
            - Quảng cáo, khuyến mãi, nạp game/thẻ cào
            - Đơn hàng mua sắm: Shopee, Lazada, Tiki, vận đơn
            - Ảnh chụp thường, món ăn, phong cảnh, người
            - Spec/sản phẩm, menu, bảng giá
            - OTP/xác thực (chỉ có mã OTP, không có giao dịch hoàn chỉnh)
            - Ảnh không đọc được nội dung rõ ràng
            - Giao dịch NGOÀI Việt Nam (ngoại tệ, ngân hàng nước ngoài)

            QUAN TRỌNG: chỉ nhận giao dịch TIỀN VIỆT NAM (VNĐ/đ/₫).
            Chỉ trả JSON đúng schema, lý do bằng tiếng Việt.
            """)
    }

    /// Phân loại text OCR. Trả nil nếu AI lỗi (caller fallback về keyword classifier).
    func classify(lines: [String]) async -> AIClassification? {
        let text = lines.joined(separator: "\n")
        guard !text.isEmpty else { return nil }
        do {
            let response = try await session.respond(
                to: "Text OCR:\n\(text)",
                generating: AIClassification.self
            )
            return response.content
        } catch {
            return nil
        }
    }
}
