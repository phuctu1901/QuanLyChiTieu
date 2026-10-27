import Foundation

/// Kết quả phân loại một ảnh: có phải screenshot giao dịch ngân hàng/chuyển khoản không.
enum ImageClassification: Equatable {
    /// Ảnh giao dịch — đưa vào pipeline.
    case transaction
    /// Ảnh không liên quan (chat, quảng cáo, mạng xã hội, sản phẩm…) — bỏ qua.
    case unrelated
    /// Không đọc được nội dung (ảnh mờ, OCR rỗng) — bỏ qua nhưng không chặn ảnh khác.
    case unreadable
}

/// Phân loại ảnh screenshot trước khi ingest: chỉ giữ ảnh giao dịch ngân hàng/chuyển khoản,
/// không nhặt đồng loạt mọi ảnh trong thư viện.
///
/// Chiến lược 3 lớp (học từ dữ liệu thật: 18 screenshot 2 ngày của user — toàn chat/ads):
/// 1. REJECT sớm: chat/mạng xã hội/quảng cáo/game/đơn hàng — thắng mọi tín hiệu dương.
/// 2. Bắt buộc hành động chuyển tiền (hoặc tên ngân hàng + "giao dịch").
/// 3. Bắt buộc số tiền format VN.
enum ImageClassifier: Sendable {

    // MARK: - Lớp 1: Từ chối (học từ ảnh thật)

    /// App chat/mạng xã hội — screenshot của các app này không phải giao dịch.
    /// Lưu ý: "zalo" nằm đây nhưng "zalopay" là ví — check zalopay TRƯỚC khi reject.
    static let rejectAppKeywords: [String] = [
        "messenger", "facebook", "instagram", "tiktok", "twitter",
        "whatsapp", "telegram", "wechat", "viber",
        // tín hiệu UI chat
        "online just now", "đang hoạt động", "dang hoat dong", "typing", "đang soạn",
        // tín hiệu UI mạng xã hội
        "thêm bạn bè", "them ban be", "reels",
    ]

    /// Quảng cáo/game/đặt cước — từ chối.
    static let rejectAdKeywords: [String] = [
        "sunwin", "nạp game", "nap game", "nạp thẻ", "nap the",
        "đặt cước", "dat cuoc", "khuyến mãi", "khuyen mai", "voucher",
        "giảm giá", "giam gia", "quảng cáo", "quang cao",
    ]

    /// Đơn hàng mua sắm — không phải giao dịch ngân hàng.
    static let rejectShoppingKeywords: [String] = [
        "shopee", "lazada", "tiki", "đơn hàng", "don hang", "giỏ hàng", "gio hang",
        "đặt hàng thành công", "dat hang thanh cong", "vận đơn", "van don",
    ]

    // MARK: - Lớp 2: Hành động giao dịch (bắt buộc)

    /// Hành động chuyển tiền/thanh toán — phải có ít nhất một (không dấu + có dấu).
    /// Chỉ "thành công" hay "giao dịch" đơn lẻ KHÔNG đủ.
    static let transferActions: [String] = [
        "chuyển khoản", "chuyen khoan", "chuyển tiền", "chuyen tien",
        "biến động số dư", "bien dong so du", "biến động tài khoản", "bien dong tai khoan",
        "thanh toán", "thanh toan",
        "nạp tiền thành công", "nap tien thanh cong",
        "nhận tiền", "nhan tien", "giao dịch thành công", "giao dich thanh cong",
        "đã chuyển", "da chuyen", "đã nhận", "da nhan",
        "hoàn tiền", "hoan tien", "refund",
    ]

    /// Tên ngân hàng/ví — điểm cộng khi classify (pattern "cake" bị bỏ: quá generic).
    static let bankNamePattern: String =
        BankMessageParser.bankCatalog
            .filter { $0.name != "Cake by VPBank" }
            .map(\.pattern)
            .joined(separator: "|")

    /// Tên app ví/ck tiên (ZaloPay, Viettel Money) — nếu có thì KHÔNG bị reject
    /// như app chat thường, vì đây là app thanh toán.
    static let walletAppPattern = #"(?i)\bzalopay\b|\bzalo\s?pay\b|\bviettel\s?money\b"#

    /// Screenshot chụp từ app banking: tên app ngân hàng/ví HIỂN THỊ trong UI
    /// (header/logo) + số tiền = đủ nhận là giao dịch, không cần chữ "giao dịch".
    /// Chỉ áp cho tên KHÔNG ambiguous (bỏ "cake", "timo", "momo" đơn lẻ có thể
    /// xuất hiện trong text thường).
    static let bankAppUIPattern: String = {
        let exactNames = [
            "MB Bank", "MBB", "Vietcombank", "VCB", "digibank", "Techcombank", "TCB",
            "VietinBank", "CTG iPay", "ACB", "ACB One", "VPBank", "VPB", "BIDV",
            "smartbanking", "TPBank", "TPB", "Agribank", "SHB", "Sacombank", "STB",
            "Eximbank", "EIB", "HDBank", "MSB", "OCB", "OCB OMNI", "SeaBank", "SCB",
            "Cake by VPBank", "VNPAY", "ZaloPay", "Viettel Money",
        ]
        return exactNames
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
    }()

    // MARK: - Lớp 3: Số tiền (bắt buộc)

    /// Số tiền VN: separator hàng nghìn kèm đơn vị đ/VND/₫ (trước hoặc sau số),
    /// hoặc số có dấu +/- chuyển tiền.
    static let moneyPattern = #"(?i)((?:vnd|vnđ|₫)\s*\d{1,3}(?:[.,]\d{3})+|\d{1,3}(?:[.,]\d{3})+\s*(?:đ|d|vnd|vnđ|₫|đồng)|[+−-]\s*\d{1,3}(?:[.,]\d{3})+|\d{4,}\s*(?:đ|vnd|vnđ|₫))"#

    /// Pattern nới lỏng: số format hàng nghìn (ít nhất 6 chữ số, dùng dấu , hoặc . phân nhóm)
    /// KHÔNG cần suffix tiền tệ — chỉ dùng khi đã có bank app UI context.
    /// Lý do: OCR trên VCB Digibank hay đọc sai "VND" thành "WD"/"VN D" do font gradient.
    static let relaxedMoneyPattern = #"\d{1,3}(?:[.,]\d{3}){1,}"#

    // MARK: - Phân loại

    static func classify(lines: [String]) -> ImageClassification {
        let nonEmpty = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !nonEmpty.isEmpty else { return .unreadable }

        let joined = nonEmpty.joined(separator: "\n")
        // Bỏ dấu để khớp cả OCR lỗi dấu
        let folded = joined.folding(options: .diacriticInsensitive, locale: Locale(identifier: "vi_VN"))

        // Screenshot chụp trong app banking: tên app hiển thị trong UI + số tiền
        // là đủ (không cần chữ "giao dịch" — nhiều màn hình app bank không có).
        // Check TRƯỚC reject để app ví (ZaloPay) không bị reject nhầm là app chat.
        let hasMoney = folded.range(of: moneyPattern, options: .regularExpression) != nil
            || joined.range(of: moneyPattern, options: .regularExpression) != nil
        let hasBankAppUI = joined.range(of: bankAppUIPattern, options: [.regularExpression, .caseInsensitive]) != nil
            || folded.range(of: bankAppUIPattern, options: [.regularExpression, .caseInsensitive]) != nil

        // Khi đã xác nhận bank app UI → dùng relaxed money pattern (không cần suffix VND/đ)
        // Lý do: OCR trên VCB Digibank hay đọc sai "VND" thành "WD" do font gradient xanh lá.
        let hasRelaxedMoney = hasMoney
            || (hasBankAppUI && (folded.range(of: relaxedMoneyPattern, options: .regularExpression) != nil
                || joined.range(of: relaxedMoneyPattern, options: .regularExpression) != nil))

        if hasBankAppUI && hasRelaxedMoney {
            // Nhưng vẫn loại nếu đồng thời có dấu hiệu chat/ads mạnh
            // (VD screenshot chat trong app bank hiếm nhưng có thể)
            let isChatUI = rejectAppKeywords.contains { joined.localizedCaseInsensitiveContains($0) }
                || rejectAppKeywords.contains { folded.localizedCaseInsensitiveContains($0) }
            let isShopping = rejectShoppingKeywords.contains { joined.localizedCaseInsensitiveContains($0) }
                || rejectShoppingKeywords.contains { folded.localizedCaseInsensitiveContains($0) }
            if !isChatUI && !isShopping {
                return .transaction
            }
            return .unrelated
        }

        // Lớp 1: từ chối chat/ads/shopping — thắng mọi tín hiệu dương còn lại
        // (app ví thanh toán đã được xử lý ở trên; "zalo" chat thường vẫn bị reject)
        let rejectLists = [rejectAppKeywords, rejectAdKeywords, rejectShoppingKeywords]
        let rejected = rejectLists.contains { list in
            list.contains { joined.localizedCaseInsensitiveContains($0) }
                || list.contains { folded.localizedCaseInsensitiveContains($0) }
        }
        if rejected { return .unrelated }

        // Lớp 3: bắt buộc có số tiền format VN (check lại cho path này)
        guard hasMoney else { return .unrelated }

        // Lớp 2: bắt buộc hành động chuyển tiền, hoặc tên ngân hàng + "giao dịch"
        let hasAction = transferActions.contains { kw in
            joined.localizedCaseInsensitiveContains(kw) || folded.localizedCaseInsensitiveContains(kw)
        }
        let hasBank = joined.range(of: bankNamePattern, options: .regularExpression) != nil
            || folded.range(of: bankNamePattern, options: .regularExpression) != nil
        let hasGenericTransaction = joined.localizedCaseInsensitiveContains("giao dịch")
            || folded.localizedCaseInsensitiveContains("giao dich")

        if hasAction { return .transaction }
        if hasBank && hasGenericTransaction { return .transaction }
        return .unrelated
    }
}
