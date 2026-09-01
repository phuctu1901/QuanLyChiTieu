import Foundation

/// Kết quả bóc tách một thông điệp giao dịch ngân hàng Việt Nam.
struct BankParseResult: Equatable {
    var amount: Int?
    var direction: Direction
    var occurredAt: Date?
    var note: String?
    var bankName: String?
    var suggestedCategoryName: String?
}

/// Bóc tách text OCR từ screenshot app ngân hàng VN thành giao dịch.
///
/// Chiến lược:
/// 1. Chuẩn hoá các dòng OCR (bỏ khoảng trắng thừa, sửa lỗi OCR số).
/// 2. Tìm số tiền: dòng có số lớn nhất khớp format tiền tệ VN (separator hàng nghìn hoặc đơn vị đ/VND).
/// 3. Loại trừ số tài khoản (10-16 chữ số liền, không separator).
/// 4. Ngày giờ: dd/mm/yyyy (+ giờ), hoặc giờ đứng trước ngày.
/// 5. Ngân hàng: catalog tên + regex viết tắt.
/// 6. Note: dòng văn bản dài nhất không chứa số tiền/ngày.
enum BankMessageParser {

    // MARK: - Catalog ngân hàng

    static let bankCatalog: [(name: String, pattern: String)] = [
        ("MB Bank", #"(?i)\bMB\s?Bank\b|\bMBB\b"#),
        ("Vietcombank", #"(?i)\bvietcombank\b|\bVCB\b|\bdigibank\b"#),
        ("Techcombank", #"(?i)\btechcombank\b|\bTCB\b"#),
        ("VietinBank", #"(?i)\bvietin\s?bank\b|\bvietinbank\b|\bCTG\s?iPay\b"#),
        ("ACB", #"(?i)\bACB\b|\bACB\s?One\b"#),
        ("VPBank", #"(?i)\bVPBank\b|\bVPB\b"#),
        ("BIDV", #"(?i)\bBIDV\b|\bsmartbanking\b"#),
        ("TPBank", #"(?i)\bTP\s?Bank\b|\bTPBank\b|\bTPB\b"#),
        ("Ví MoMo", #"(?i)\bmomo\b"#),
        ("Agribank", #"(?i)\bagribank\b|\bAgribank\s?mBank\b"#),
        ("SHB", #"(?i)\bSHB\s?Mobile\b|\bSHB\b"#),
        ("Sacombank", #"(?i)\bsacombank\b|\bSacom\s?bank\b|\bSTB\b"#),
        ("Eximbank", #"(?i)\beximbank\b|\bEIB\b"#),
        ("HDBank", #"(?i)\bHD\s?Bank\b|\bHDBank\b"#),
        ("MSB", #"(?i)\bMSB\b|\bmaritime\s?bank\b"#),
        ("OCB", #"(?i)\bOCB\s?OMNI\b|\bOCB\b"#),
        ("SeaBank", #"(?i)\bsea\s?bank\b|\bseabank\b"#),
        ("Cake by VPBank", #"(?i)\bcake\s?by\s?VPBank\b|\bcake\b"#),
        ("Timo", #"(?i)\btimo\b"#),
        ("VNPAY", #"(?i)\bvnpay\b"#),
    ]

    // MARK: - Regex patterns

    /// Số tiền VN: có dấu phân tách hàng nghìn (dấu . hoặc ,), kèm đ/VND tùy chọn, dấu +/− tùy chọn
    static let amountPattern = #"(?i)([-+])?\s?(\d{1,3}(?:[.,]\d{3})+|\d{4,})\s?(đ|d|đồng|vnd|vnđ|dong|₫)?"#

    /// Ngày dd/mm/yyyy (hoặc dd-mm-yyyy), kèm giờ tùy chọn phía sau
    static let datePattern = #"\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})\b(?:\s+(\d{1,2}):(\d{2}))?"#

    /// Giờ đứng trước ngày: "21:34 15/08/2026" hoặc "21:34 - 15/08/2026"
    static let timeFirstPattern = #"\b(\d{1,2}):(\d{2})\s*[-–]?\s*(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})\b"#

    /// Số tài khoản/thẻ: 10-16 chữ số liền không separator — để loại trừ
    static let accountNumberPattern = #"\b\d{10,16}\b"#

    // MARK: - Public API

    static func parse(_ lines: [String]) -> BankParseResult {
        var result = BankParseResult(
            amount: nil, direction: .expense,
            occurredAt: nil, note: nil,
            bankName: nil, suggestedCategoryName: nil
        )
        guard !lines.isEmpty else { return result }

        let normalized = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { normalizeOcr($0) }
        guard !normalized.isEmpty else { return result }

        result.bankName = detectBank(normalized)
        result.occurredAt = detectDate(normalized)

        var candidates: [(index: Int, amount: Int, sign: String?)] = []
        for (i, line) in normalized.enumerated() {
            if let c = extractAmount(from: line) {
                candidates.append((i, c.amount, c.sign))
            }
        }

        if let best = candidates.max(by: { $0.amount < $1.amount }) {
            result.amount = best.amount
            result.direction = best.sign == "+" ? .income : .expense
            result.note = extractNote(from: normalized, excludingLineAt: best.index)
        } else {
            result.note = extractNote(from: normalized, excludingLineAt: nil)
        }

        result.suggestedCategoryName = suggestCategory(for: result)
        return result
    }

    // MARK: - Chuẩn hoá OCR

    /// Sửa lỗi OCR thường gặp: chữ O lẫn vào số "5O.000" → "50.000".
    static func normalizeOcr(_ line: String) -> String {
        var s = line
        while let r = s.range(of: #"\d[Oo](?=[\d.,])"#, options: .regularExpression) {
            s.replaceSubrange(r, with: "0")
        }
        while let r = s.range(of: #"(?<=[\d.,])[Oo]"#, options: .regularExpression) {
            s.replaceSubrange(r, with: "0")
        }
        return s
    }

    // MARK: - Số tiền

    /// Tách số tiền từ một dòng. Trả nil nếu không có số hợp lệ.
    static func extractAmount(from line: String) -> (amount: Int, sign: String?)? {
        guard let match = line.range(of: amountPattern, options: .regularExpression) else { return nil }
        let token = String(line[match])

        // Nếu token là một dải 10-16 chữ số liền → khả năng số tài khoản, bỏ
        let plainDigits = token.filter(\.isNumber)
        if plainDigits.count >= 10 && !token.contains(where: { $0 == "." || $0 == "," }) {
            return nil
        }

        let sign = token.hasPrefix("+") ? "+" : (token.hasPrefix("-") ? "-" : nil)
        guard let m = token.range(of: #"\d{1,3}(?:[.,]\d{3})+|\d+"#, options: .regularExpression) else { return nil }
        guard let amount = parseVNNumber(String(token[m])), isPlausibleAmount(amount) else { return nil }
        return (amount, sign)
    }

    /// "50.000" / "50,000" / "50000" → 50000
    static func parseVNNumber(_ s: String) -> Int? {
        let digits = s.filter(\.isNumber)
        guard !digits.isEmpty, digits.count <= 12 else { return nil }
        return Int(digits)
    }

    /// Giao dịch VN thực tế: từ 1.000đ đến ~2 tỷ
    static func isPlausibleAmount(_ n: Int) -> Bool {
        (1_000...2_000_000_000).contains(n)
    }

    // MARK: - Ngày giờ

    static func detectDate(_ lines: [String]) -> Date? {
        let joined = lines.joined(separator: " ")
        let calendar = Calendar.current
        let now = Date()
        let componentsNow = calendar.dateComponents([.year, .month, .day], from: now)

        // Dạng "21:34 15/08/2026"
        if let m = joined.range(of: timeFirstPattern, options: .regularExpression) {
            let nums = extractNumbers(from: String(joined[m]))
            if nums.count >= 5, let date = makeDate(
                day: nums[2], month: nums[3], year: nums[4],
                hour: nums[0], minute: nums[1], fallbackYear: componentsNow.year ?? 2026
            ) {
                return date
            }
        }

        // Dạng "15/08/2026 21:34"
        if let m = joined.range(of: datePattern, options: .regularExpression) {
            let nums = extractNumbers(from: String(joined[m]))
            // datePattern: d m y [h min]
            let day = nums[0], month = nums[1], year = nums.count > 2 ? nums[2] : (componentsNow.year ?? 2026)
            let hour = nums.count > 3 ? nums[3] : 12
            let minute = nums.count > 4 ? nums[4] : 0
            if let date = makeDate(day: day, month: month, year: year, hour: hour, minute: minute, fallbackYear: componentsNow.year ?? 2026) {
                return date
            }
        }
        return nil
    }

    private static func extractNumbers(from s: String) -> [Int] {
        s.split(whereSeparator: { !"0123456789".contains($0) })
            .compactMap { Int($0) }
    }

    private static func makeDate(day: Int, month: Int, year: Int, hour: Int, minute: Int, fallbackYear: Int) -> Date? {
        let fullYear = year < 100 ? 2000 + year : year
        guard (1...31).contains(day), (1...12).contains(month), fullYear >= 2000 else { return nil }
        var comps = DateComponents()
        comps.year = fullYear
        comps.month = month
        comps.day = day
        comps.hour = min(max(hour, 0), 23)
        comps.minute = min(max(minute, 0), 59)
        return Calendar.current.date(from: comps)
    }

    // MARK: - Ngân hàng

    static func detectBank(_ lines: [String]) -> String? {
        let joined = lines.joined(separator: " \n ")
        for (name, pattern) in bankCatalog {
            if joined.range(of: pattern, options: .regularExpression) != nil {
                return name
            }
        }
        return nil
    }

    // MARK: - Note

    /// Dòng dài nhất không chứa số tiền và không phải ngày, ưu tiên dòng có chữ.
    static func extractNote(from lines: [String], excludingLineAt excludedIndex: Int?) -> String? {
        let moneyOrNoise = #"(?i)(đ|vnd|vnđ|₫|số dư|so du|giao dịch|giao dich|balance|nạp|lỗi|thành công|thanh cong)"#
        let candidates = lines.enumerated().filter { entry in
            guard entry.offset != excludedIndex else { return false }
            let line = entry.element
            guard line.count >= 6 else { return false }
            // Bỏ dòng chỉ là số/mà_nước
            let letters = line.filter { $0.isLetter }
            guard letters.count >= 4 else { return false }
            // Bỏ dòng "thanh toán thành công" kiểu status
            if line.range(of: #"(?i)thành công|thanh cong|success"#, options: .regularExpression) != nil {
                return false
            }
            return true
        }
        // Ưu tiên dòng có nội dung giao dịch ("chuyen tien", "thanh toan", "nap", "chuyen")
        let contentWords = #"(?i)(chuyển|chuyen|thanh toán|thanh toan|nạp|nap|trả|tra|mua|lương|luong|coffee|food|bill)"#
        if let preferred = candidates.first(where: { $0.element.range(of: contentWords, options: .regularExpression) != nil }) {
            return cleanNote(preferred.element)
        }
        if let longest = candidates.max(by: { scoreNote($0.element) < scoreNote($1.element) }) {
            return cleanNote(longest.element)
        }
        return nil
    }

    private static func scoreNote(_ line: String) -> Int {
        let letters = line.filter { $0.isLetter }.count
        let hasMoney = line.range(of: #"(?i)đ[^0-9a-zA-Z]|vnd"#, options: .regularExpression) != nil || line.contains("đ")
        return letters - (hasMoney ? 50 : 0)
    }

    private static func cleanNote(_ s: String) -> String {
        let collapsed = s.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Gợi ý category

    static func suggestCategory(for result: BankParseResult) -> String? {
        guard let note = result.note?.lowercased() else {
            return result.direction == .income ? "Khác" : nil
        }
        let diacriticFree = note.folding(options: .diacriticInsensitive, locale: Locale(identifier: "vi_VN"))
        let rules: [(pattern: String, category: String)] = [
            (#"(?i)ca ?fe|coffee|cà phê|an sang|ăn sáng|com|rice|food|do an|đồ ăn|nha hang|nhà hàng|quan an|quán ăn"#, "Ăn uống"),
            (#"(?i)grab|be(?: ?car)?|taxi|xekhach|xíc |xe ôm|xe om|caphe|bus|metro|xang|xăng|petrol|fuel|do xang|parking|gui xe|gửi xe"#, "Di chuyển"),
            (#"(?i)shopee|lazada|tiki|amazon|mua sam|mua sắm|sieu thi|siêu thị|vinmart|big c|coopmart|lotte"#, "Mua sắm"),
            (#"(?i)hoa don|hoá đơn|dien|điện|nuoc|nước|internet|wifi|truyen hinh|truyền hình|cap|cáp|electric|evn"#, "Hoá đơn"),
            (#"(?i)netflix|spotify|youtube|game|choi game|chơi game|phim|movie|karaoke|bida|gungy|cgv|cinema"#, "Giải trí"),
            (#"(?i)benh vien|bệnh viện|thuoc|thuốc|phong kham|phòng khám|bac si|bác sĩ|hospital|clinic|dentist|nhakhoa|nha khoa"#, "Sức khoẻ"),
            (#"(?i)hoc phi|học phí|sach|sách|khoahoc|khóa học|course|udemy|coursera|trường|truong|tuition"#, "Giáo dục"),
            (#"(?i)chuyen tien|chuyển tiền|chuyen khoan|chuyển khoản|ck |transfer|chuyen ti|ib "#, "Chuyển tiền"),
            (#"(?i)nap |nạp |topup|top up|naptien|vina|viettel|mobi|dat cuoc|đặt cước|thecao|thẻ cào|data"#, "Nạp tiền/Điện thoại"),
        ]
        for (pattern, category) in rules {
            if diacriticFree.range(of: pattern, options: .regularExpression) != nil
                || note.range(of: pattern, options: .regularExpression) != nil {
                return category
            }
        }
        return nil
    }
}
