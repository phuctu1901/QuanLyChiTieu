import Foundation
import FoundationModels

/// Structured output cho LLM — đầy đủ thông tin một giao dịch ngân hàng VN.
/// KHÔNG có field note — ghi chú do user tự viết (ý nghĩa cá nhân, AI không thay được).
@Generable
struct AIParseResult {
    @Guide(description: "Số tiền GIAO DỊCH nguyên không separator. VD: '1.500.000đ' → 1500000. Là số tiền đã chuyển/thanh toán/nhận — KHÔNG phải số dư tài khoản. Không tìm thấy thì nil.")
    var amount: Int?

    @Guide(description: "Chuỗi ISO 8601 ngày+giờ của GIAO DỊCH. VD: '2026-08-15T21:34:00'. Nếu không có giờ trong text thì dùng giờ đồng hồ thanh trạng thái (dòng HH:mm đầu screenshot). Không tìm thấy thì nil.")
    var occurredAtISO: String?

    @Guide(description: "Tên ngân hàng/ví phát sinh giao dịch. VD: MB Bank, Vietcombank, Techcombank, MoMo, ZaloPay. Không có thì nil.")
    var bankName: String?

    @Guide(description: "Số tài khoản/SĐT đối ứng nếu có (8-16 ký tự). Không có thì nil.")
    var counterAccount: String?

    @Guide(description: "Tên người gửi hoặc người nhận (Tên đối tác giao dịch). VD: NGUYEN VAN A, CONG TY TNHH ABC. KHÔNG phải tên ngân hàng. Không có thì nil.")
    var counterpartName: String?

    @Guide(description: "Mã giao dịch/tham chiếu nếu có (VD: FT26081512345678). Không có thì nil.")
    var transactionCode: String?

    @Guide(description: "Phân loại chi tiêu tiếng Việt. Chọn một: Ăn uống | Di chuyển | Mua sắm | Hoá đơn | Giải trí | Sức khoẻ | Giáo dục | Chuyển tiền | Nạp tiền/Điện thoại | Khác. Nếu là nhận tiền thì 'Khác'.")
    var category: String?

    @Guide(description: "true nếu NHẬN tiền (+), false nếu CHI tiền (-). Mặc định false.")
    var isIncome: Bool

    @Guide(description: "Độ tin cậy bóc tách 0.0-1.0. 1.0 = text rõ ràng đủ mọi field; 0.5 = mập mờ có thể nhầm số dư với tiền giao dịch; 0.0 = không đọc được gì.")
    var confidence: Double

    @Guide(description: "Số dư tài khoản sau giao dịch nếu hiển thị (int, không separator). KHÔNG dùng làm amount. Không có thì nil.")
    var balanceAfter: Int?
}

/// Parser chính bằng Foundation Models on-device — bóc tách TOÀN BỘ giao dịch
/// từ text OCR: tiền, thời điểm, note, ngân hàng, số TK đối ứng, mã GD, category,
/// hướng, kèm confidence từng lần parse.
///
/// Regex (BankMessageParser) chỉ là fallback khi AI unavailable hoặc lỗi.
/// Kết quả luôn qua màn xác nhận của user trước khi ghi Transaction.
///
/// Yêu cầu: iOS 26+, Apple Intelligence bật, ngôn ngữ máy được hỗ trợ.
struct TransactionParserAI {

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

    /// Mô tả chi tiết tình trạng model — dùng trong SettingsView.
    static var availabilityDescription: String {
        guard #available(iOS 26, *) else { return "Yêu cầu iOS 26+" }
        switch SystemLanguageModel.default.availability {
        case .available:
            return "Sẵn sàng"
        case .unavailable(.deviceNotEligible):
            return "Thiết bị không hỗ trợ"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence chưa bật"
        case .unavailable(.modelNotReady):
            return "Model đang tải xuống…"
        case .unavailable(let reason):
            return "Không khả dụng: \(reason)"
        @unknown default:
            return "Không xác định"
        }
    }

    let session: LanguageModelSession

    init?() {
        guard Self.isAvailable else { return nil }
        session = LanguageModelSession(instructions: """
            BẠN CHỈ XỬ LÝ TIẾNG VIỆT. Mọi output phải bằng tiếng Việt.
            Bạn là máy bóc tách giao dịch ngân hàng Việt Nam từ text OCR screenshot.
            CHỈ xử lý giao dịch tiền Việt Nam (VNĐ/đ/₫). Bỏ qua ngoại tệ.
            Text OCR có thể sai dấu, sai thứ tự dòng, lẫn lộn số. Phân biệt kỹ:
            - TIỀN GIAO DỊCH: số kèm đơn vị (đ/VND/₫) thường có dấu +/- , thường nằm
              cạnh chữ "số tiền"/"giá trị"/"số tiền chuyển".
            - SỐ DƯ: nằm cạnh chữ "số dư"/"số dư khả dụng"/"balance" — cho vào
              balanceAfter, KHÔNG BAO GIỜ cho vào amount.
            - TÊN ĐỐI TÁC (counterpartName): Tên người hoặc tên công ty gửi/nhận tiền (VD: 'NGUYEN VAN A', 'CONG TY TNHH SAN XUAT THUONG MAI ABC'). 
              LƯU Ý ĐẮC BIỆT: Tên công ty hoặc tên người trên hoá đơn có thể DÀI VÀ BỊ XUỐNG DÒNG (nằm trên 2 hoặc 3 dòng liên tiếp). BẠN PHẢI NỐI ĐẦY ĐỦ CÁC DÒNG ĐÓ THÀNH MỘT TÊN HOÀN CHỈNH, KHÔNG ĐƯỢC CẮT BỚT DÒNG SAU.
              KHÔNG lấy tên ngân hàng (như Vietcombank, MB Bank, Techcombank, MoMo) làm tên đối tác. Nếu không có tên thì để nil.
            - TÊN NGÂN HÀNG (bankName): Tên ngân hàng xử lý giao dịch. Không nhầm lẫn với tên đối tác.
            - MÃ GIAO DỊCH: chuỗi có tiền tố FT/GD/MB/VCB... + số.
            Ngày: dd/mm/yyyy hoặc dd thg mm, yyyy; "thg" = tháng; năm 2 chữ số = 20xx.
            Giờ: HH:mm; giờ đầu screenshot là đồng hồ thanh trạng thái.
            Category: suy từ nội dung note (ăn uống, grab, shopee, hoá đơn...) — trả tiếng Việt.
            Chỉ trả JSON đúng schema, không giải thích.
            """)
    }

    /// Bốc tách toàn bộ bằng LLM. Trả nil nếu AI lỗi (caller fallback về regex).
    func parse(lines: [String]) async -> AIParseResult? {
        let text = lines.joined(separator: "\n")
        guard !text.isEmpty else { return nil }
        do {
            let response = try await session.respond(
                to: "Text OCR:\n\(text)",
                generating: AIParseResult.self
            )
            return response.content
        } catch {
            return nil
        }
    }

    // MARK: - Merge

    /// AI là parser chính: kết quả AI confidence đủ cao thì dùng, field nào AI
    /// bỏ sót (nil) thì giữ của regex. Regex chỉ thắng khi AI confidence thấp.
    /// NOTE không bao giờ bị AI đụng — user tự viết ghi chú.
    static func merge(regex: ParsedTransaction, ai: AIParseResult) -> ParsedTransaction {
        var merged = regex
        let aiConfident = ai.confidence >= 0.5

        if aiConfident {
            if let amount = ai.amount { merged.amount = amount }
            if let bank = ai.bankName, !bank.isEmpty { merged.bankName = bank }
            if let contact = ai.counterpartName, !contact.isEmpty { merged.contactName = contact }
            merged.direction = ai.isIncome ? .income : .expense
            if let iso = ai.occurredAtISO, let date = parseISO(iso) {
                merged.occurredAt = date
                merged.occurredAtSource = .fullDateTime
            }
            if let cat = ai.category, !cat.isEmpty {
                merged.suggestedCategoryName = cat
            }
        } else {
            // AI không tự tin: chỉ đắp field regex đang thiếu
            if merged.amount == nil, let amount = ai.amount { merged.amount = amount }
            if merged.bankName == nil, let bank = ai.bankName, !bank.isEmpty { merged.bankName = bank }
            if merged.contactName == nil, let contact = ai.counterpartName, !contact.isEmpty { merged.contactName = contact }
            if ai.isIncome { merged.direction = .income }
            if merged.occurredAt == nil, let iso = ai.occurredAtISO, let date = parseISO(iso) {
                merged.occurredAt = date
                merged.occurredAtSource = .fullDateTime
            }
        }
        return merged
    }

    /// ISO 8601 → Date. LLM trả giờ local của giao dịch (không múi giờ) —
    /// parse theo đúng các số đó, không dịch múi giờ.
    static func parseISO(_ s: String) -> Date? {
        // "2026-08-15T21:34:00" → components theo nguyên văn
        let parts = s.split(separator: "T")
        guard parts.count == 2 else { return nil }
        let dateParts = parts[0].split(separator: "-")
        guard dateParts.count == 3,
              let year = Int(dateParts[0]),
              let month = Int(dateParts[1]),
              let day = Int(dateParts[2]) else { return nil }
        let timeParts = parts[1].split(separator: ":")
        guard let hour = Int(timeParts.first ?? ""), let minute = timeParts.count > 1 ? Int(timeParts[1]) : nil else { return nil }
        let second = timeParts.count > 2 ? Int(timeParts[2].prefix(2)) ?? 0 : 0
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute; comps.second = second
        return Calendar.current.date(from: comps)
    }
}
