import Foundation

/// Kết quả bóc tách một thông điệp giao dịch ngân hàng Việt Nam.
struct BankParseResult: Equatable {
    var amount: Int?
    var direction: Direction
    var occurredAt: Date?
    var occurredAtSource: OccurredAtSource
    var note: String?
    var bankName: String?
    var contactName: String?
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
        ("SCB", #"(?i)\bSCB\b"#),
        ("Cake by VPBank", #"(?i)\bcake\s?by\s?VPBank\b"#),
        ("Timo", #"(?i)\btimo\b"#),
        ("VNPAY", #"(?i)\bvnpay\b"#),
        ("ZaloPay", #"(?i)\bzalopay\b|\bzalo\s?pay\b"#),
        ("Viettel Money", #"(?i)\bviettel\s?money\b"#),
    ]

    // MARK: - Regex patterns

    /// Số tiền VN: có dấu phân tách hàng nghìn (dấu . hoặc ,), kèm đ/VND tùy chọn
    /// (đứng trước "VND 500,000" hoặc sau "500,000 VND"), dấu +/− tùy chọn
    static let amountPattern = #"(?i)([−+-])?\s?(?:vnd\s*|vnđ\s*|₫\s*)?(\d{1,3}(?:[.,]\d{3})+|\d{4,})\s?(đ|d|đồng|vnd|vnđ|dong|₫)?"#

    /// Ngày dd/mm/yyyy (hoặc dd-mm-yyyy), kèm giờ tùy chọn phía sau
    static let datePattern = #"\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})\b(?:\s+(\d{1,2}):(\d{2}))?"#

    /// Giờ đứng trước ngày: "21:34 15/08/2026" hoặc "21:34 - 15/08/2026"
    static let timeFirstPattern = #"\b(\d{1,2}):(\d{2})\s*[-–]?\s*(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})\b"#

    /// Ngày không năm: "15/08" hoặc "15-08" (năm lấy từ hiện tại)
    static let dateNoYearPattern = #"\b(\d{1,2})[\/\-.](\d{1,2})\b(?:\s+(\d{1,2}):(\d{2}))?"#

    /// Ngày kiểu iOS tiếng Việt: "15 thg 8, 2026" / "15 thg 8" (OCR có thể đọc "tháng")
    static let monthNamePattern = #"(?i)\b(\d{1,2})\s*(?:thg|tháng|thang)\.?\s*(\d{1,2})(?:\s*,?\s*(\d{4}))?"#

    /// Giờ đứng một mình: "17:34" / "17:34:05" (status bar screenshot) — dùng khi ngày không có giờ
    static let timeOnlyPattern = #"\b(\d{1,2}):(\d{2})(?::(\d{2}))?\b"#

    /// Số tài khoản/thẻ: 10-16 chữ số liền không separator — để loại trừ
    static let accountNumberPattern = #"\b\d{10,16}\b"#

    // MARK: - Public API

    static func parse(_ lines: [String]) -> BankParseResult {
        var result = BankParseResult(
            amount: nil, direction: .expense,
            occurredAt: nil, occurredAtSource: .unknown, note: nil,
            bankName: nil, contactName: nil, suggestedCategoryName: nil
        )
        guard !lines.isEmpty else { return result }

        let normalized = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { normalizeOcr($0) }
        guard !normalized.isEmpty else { return result }

        result.bankName = detectBank(normalized)
        result.contactName = detectContactName(normalized)
        (result.occurredAt, result.occurredAtSource) = detectDateWithSource(normalized)

        var candidates: [(index: Int, amount: Int, sign: String?, hasUnit: Bool)] = []
        for (i, line) in normalized.enumerated() {
            if let c = extractAmount(from: line) {
                // Đánh dấu candidate này có kèm đơn vị không (ưu tiên khi chọn)
                let hasUnit = line.range(of: amountWithUnitPattern, options: .regularExpression) != nil
                candidates.append((i, c.amount, c.sign, hasUnit))
            }
        }

        // Ưu tiên max: (1) có đơn vị đ/VND, (2) có dấu +/- (giao dịch, không phải số dư),
        // (3) số lớn hơn. Comparator là "a < b" (areIncreasingOrder).
        let best = candidates.max(by: { a, b in
            if a.hasUnit != b.hasUnit { return !a.hasUnit }
            if (a.sign != nil) != (b.sign != nil) { return b.sign != nil }
            return a.amount < b.amount
        })
        // Nội dung giao dịch chỉ dùng nội bộ để gợi ý category — KHÔNG gán vào note.
        /// Ghi chú là ý nghĩa cá nhân (chi cho gì, với ai) → user tự viết.
        var contentHint: String?
        if let best {
            result.amount = best.amount
            result.direction = best.sign == "+" ? .income : .expense
            contentHint = extractNote(from: normalized, excludingLineAt: best.index)
        } else {
            contentHint = extractNote(from: normalized, excludingLineAt: nil)
        }

        result.suggestedCategoryName = suggestCategory(for: result, contentHint: contentHint)
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

    /// Số tiền có kèm đơn vị (đ/VND/₫/đồng) — tín hiệu mạnh nhất là tiền thật.
    /// Lưu ý: sign +/- yêu cầu separator hàng nghìn, để không nuốt năm "2026"
    /// từ ngày "15/08/2026" đứng sau dấu gạch.
    static let amountWithUnitPattern = #"(?i)([−+-]\s?\d{1,3}(?:[.,]\d{3})+\s*(?:đ|d|đồng|vnd|vnđ|dong|₫))|((?:vnd|vnđ|₫)\s*\d{1,3}(?:[.,]\d{3})+)|(\d{1,3}(?:[.,]\d{3})+\s*(?:đ|d|đồng|vnd|vnđ|dong|₫))|(\d{4,}\s*(?:đ|vnd|vnđ|₫))"#

    /// Tách số tiền từ một dòng. Trả nil nếu không có số hợp lệ.
    /// Ưu tiên số CÓ đơn vị (đ/VND/₫) — số tiền thật gần như luôn kèm đơn vị;
    /// số trần không đơn vị thường là số tài khoản/năm/spec → chỉ nhận khi
    /// có separator hàng nghìn hợp lệ (VD "1.500.000").
    /// Dòng chứa ngày/giờ ("17:34 - 15/08/2026") bị bỏ để không nuốt năm.
    static func extractAmount(from line: String) -> (amount: Int, sign: String?)? {
        // Dòng có ngày dd/mm/yyyy hoặc giờ HH:mm → không phải dòng tiền
        if line.range(of: datePattern, options: .regularExpression) != nil
            || line.range(of: timeOnlyPattern, options: .regularExpression) != nil {
            return nil
        }
        // 1) Thử match có đơn vị trước
        if let found = firstAmount(in: line, pattern: amountWithUnitPattern) {
            return found
        }
        // 2) Fallback: match amountPattern tổng quát (cho dòng chỉ có "500.000")
        if let match = line.range(of: amountPattern, options: .regularExpression) {
            return parseAmountToken(String(line[match]))
        }
        return nil
    }

    /// Tìm match đầu tiên theo pattern, parse thành (amount, sign).
    private static func firstAmount(in line: String, pattern: String) -> (amount: Int, sign: String?)? {
        guard let match = line.range(of: pattern, options: .regularExpression) else { return nil }
        return parseAmountToken(String(line[match]))
    }

    /// Token text → (amount, sign). Lọc số tài khoản (10-16 chữ số liền).
    private static func parseAmountToken(_ token: String) -> (amount: Int, sign: String?)? {
        // Dải 10-16 chữ số liền không separator → số tài khoản, bỏ
        let plainDigits = token.filter(\.isNumber)
        if plainDigits.count >= 10 && !token.contains(where: { $0 == "." || $0 == "," }) {
            return nil
        }

        let sign = token.hasPrefix("+") ? "+" : (token.hasPrefix("-") || token.hasPrefix("−") ? "-" : nil)
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

    /// detectDate + nguồn thời điểm (để UI chú thích độ tin cậy).
    static func detectDateWithSource(_ lines: [String]) -> (date: Date?, source: OccurredAtSource) {
        let joined = lines.joined(separator: " ")
        let fallbackYear = Calendar.current.dateComponents([.year], from: Date()).year ?? 2026

        // 1. Giờ trước ngày: "21:34 15/08/2026"
        if let m = joined.range(of: timeFirstPattern, options: .regularExpression) {
            let nums = extractNumbers(from: String(joined[m]))
            if nums.count >= 5, let date = makeDate(
                day: nums[2], month: nums[3], year: nums[4],
                hour: nums[0], minute: nums[1], fallbackYear: fallbackYear
            ) {
                return (date, .fullDateTime)
            }
        }

        // 2-3. "15/08/2026 21:34" hoặc "15/08/2026" (+ giờ status bar nếu có)
        if let m = joined.range(of: datePattern, options: .regularExpression) {
            let nums = extractNumbers(from: String(joined[m]))
            let day = nums[0], month = nums[1]
            let year = nums.count > 2 ? nums[2] : fallbackYear
            var hour: Int? = nums.count > 3 ? nums[3] : nil
            var minute: Int? = nums.count > 4 ? nums[4] : nil
            var source = OccurredAtSource.dateOnly
            if hour == nil, let (h, min) = detectStatusBarTime(joined, excluding: m) {
                hour = h
                minute = min
                source = .dateWithStatusBarTime
            }
            if let date = makeDate(
                day: day, month: month, year: year,
                hour: hour ?? 0, minute: minute ?? 0, fallbackYear: fallbackYear
            ) {
                return (date, hour != nil && source == .dateOnly ? .fullDateTime : source)
            }
        }

        // 4. "15 thg 8, 2026" (iOS tiếng Việt)
        if let m = joined.range(of: monthNamePattern, options: .regularExpression) {
            let nums = extractNumbers(from: String(joined[m]))
            if nums.count >= 2 {
                let day = nums[0], month = nums[1]
                let year = nums.count > 2 ? nums[2] : fallbackYear
                if let date = makeDate(
                    day: day, month: month, year: year,
                    hour: 0, minute: 0, fallbackYear: fallbackYear
                ) {
                    return (date, .dateOnly)
                }
            }
        }

        // 5. "15/08" (không năm)
        if let m = joined.range(of: dateNoYearPattern, options: .regularExpression) {
            let nums = extractNumbers(from: String(joined[m]))
            if nums.count >= 2, nums[0] <= 31, nums[1] <= 12 {
                let day = nums[0], month = nums[1]
                var hour: Int? = nums.count > 2 ? nums[2] : nil
                var minute: Int? = nums.count > 3 ? nums[3] : nil
                var source = OccurredAtSource.dateOnly
                if hour == nil, let (h, min) = detectStatusBarTime(joined, excluding: m) {
                    hour = h
                    minute = min
                    source = .dateWithStatusBarTime
                }
                if let date = makeDate(
                    day: day, month: month, year: fallbackYear,
                    hour: hour ?? 0, minute: minute ?? 0, fallbackYear: fallbackYear
                ) {
                    return (date, source)
                }
            }
        }
        return (nil, .unknown)
    }

    /// Bóc thời điểm giao dịch (không kèm nguồn) — giữ API cũ cho test.
    static func detectDate(_ lines: [String]) -> Date? {
        detectDateWithSource(lines).date
    }

    /// Tìm giờ "HH:mm" đứng độc lập (status bar screenshot) ngoài range đã loại trừ.
    /// Ảnh chụp gần đây → giờ status bar ≈ giờ giao dịch, tốt hơn để trống.
    private static func detectStatusBarTime(
        _ joined: String,
        excluding excluded: Range<String.Index>
    ) -> (hour: Int, minute: Int)? {
        var cursor = joined.startIndex
        while let m = joined.range(
            of: timeOnlyPattern, options: .regularExpression,
            range: cursor..<joined.endIndex
        ) {
            defer { cursor = m.upperBound }
            // Bỏ match nằm trong range ngày đã dùng
            if m.lowerBound >= excluded.lowerBound && m.upperBound <= excluded.upperBound { continue }
            let nums = extractNumbers(from: String(joined[m]))
            if let h = nums.first, let min = nums.dropFirst().first, (0...23).contains(h), (0...59).contains(min) {
                return (h, min)
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

    // MARK: - Tên đối tác (Contact Name)

    /// Pattern nhận diện nhãn hệ thống (label) trong OCR — dùng để skip khi quét tìm tên
    private static let labelNoisePattern = #"(?i)^(tài khoản|tên người|người nhận|người chuyển|ngân hàng|nội dung|mã tham chiếu|mã giao dịch|mã gd|phí\b|phí chuyển|thời gian|số tiền|số dư|chuyển lúc|ngày|thông tin|chi tiết|nguồn tiền|đơn vị|hình thức|lưu mẫu|thực hiện|giao dịch thành|chuyển thành|quay lại|số tài khoản)"#

    /// Nhận diện tên người/công ty đối tác giao dịch từ OCR lines (hỗ trợ tên dài bị xuống dòng 2-3 dòng)
    ///
    /// Xử lý đúng 2 layout OCR phổ biến:
    /// - **Inline**: "Tên người nhận: NGUYEN VAN A" (tên cùng dòng nhãn)
    /// - **Interleave (VCB)**: Nhãn trên dòng riêng, giá trị ở dòng dưới, có thể xen kẽ
    ///   với các nhãn khác (Tài khoản nhận / Tên người nhận / Ngân hàng nhận rồi mới
    ///   đến giá trị TK / tên / ngân hàng)
    static func detectContactName(_ lines: [String]) -> String? {
        let labelPatterns = [
            #"(?i)(?:tên\s+)?(?:người|tài khoản|tk)\s+(?:thụ\s+hưởng|nhận|chuyển|gửi)"#,
            #"(?i)(?:người|tài khoản)\s+(?:thụ\s+hưởng|nhận|chuyển|gửi)"#,
            #"(?i)(?:tên\s+)?đơn\s+vị\s+(?:thanh\s+toán|chấp\s+nhận)"#,
            #"(?i)\b(?:người\s+nhận|người\s+chuyển|người\s+thụ\s+hưởng|nhà\s+cung\s+cấp|thương\s+nhân|merchant)\b"#
        ]
        
        let bankNamesLower = bankCatalog.map { $0.name.lowercased() }
        
        for (i, line) in lines.enumerated() {
            for pattern in labelPatterns {
                if line.range(of: pattern, options: .regularExpression) != nil {
                    // 1. Nếu tên bắt đầu ngay trên cùng dòng (sau dấu : hoặc -)
                    if let colonIndex = line.firstIndex(of: ":") ?? line.firstIndex(of: "-") {
                        let candidate = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if isValidNameChunk(candidate, bankNamesLower: bankNamesLower) {
                            var fullParts = [cleanContactName(candidate)]
                            // Kiểm tra các dòng tiếp theo xem có phải phần kéo dài xuống dòng không
                            for k in 1...2 {
                                if i + k < lines.count {
                                    let nextLine = lines[i + k].trimmingCharacters(in: .whitespacesAndNewlines)
                                    if isValidNameChunk(nextLine, bankNamesLower: bankNamesLower) {
                                        fullParts.append(cleanContactName(nextLine))
                                    } else {
                                        break
                                    }
                                }
                            }
                            let combined = fullParts.joined(separator: " ")
                            if isValidContactName(combined, bankNamesLower: bankNamesLower) {
                                return cleanContactName(combined)
                            }
                        }
                    }
                    
                    // 2. Tên nằm ở các dòng tiếp theo (xuống dòng dưới nhãn tiêu đề)
                    if let multiLineName = extractMultiLineName(startingAt: i + 1, in: lines, bankNamesLower: bankNamesLower) {
                        return multiLineName
                    }
                }
            }
        }
        
        // Fallback: Tìm các dòng chữ IN HOA đứng độc lập liên tiếp (VD: dòng 1 "CONG TY CO PHAN", dòng 2 "DICH VU ABC")
        for i in 0..<lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if isStandaloneUppercaseName(line, bankNamesLower: bankNamesLower) {
                var fullParts = [cleanContactName(line)]
                for k in 1...2 {
                    if i + k < lines.count {
                        let nextLine = lines[i + k].trimmingCharacters(in: .whitespacesAndNewlines)
                        if isStandaloneUppercaseName(nextLine, bankNamesLower: bankNamesLower) {
                            fullParts.append(cleanContactName(nextLine))
                        } else {
                            break
                        }
                    }
                }
                let combined = fullParts.joined(separator: " ")
                if isValidContactName(combined, bankNamesLower: bankNamesLower) {
                    return cleanContactName(combined)
                }
            }
        }
        
        return nil
    }

    /// Quét các dòng phía sau nhãn tên để gom tên đầy đủ (hỗ trợ interleave layout).
    ///
    /// Chiến lược: quét tối đa 10 dòng phía sau, **skip** các dòng là:
    /// - Nhãn hệ thống (Ngân hàng nhận, Nội dung, Mã tham chiếu, Hình thức chuyển…)
    /// - Số tài khoản (8+ chữ số)
    /// - Tên ngân hàng (match bankCatalog)
    ///
    /// Các dòng còn lại nếu pass `isValidNameChunk` → gom thành tên.
    /// Gom tối đa 3 dòng liên tiếp (sau khi skip) tạo thành 1 tên hoàn chỉnh.
    private static func extractMultiLineName(startingAt index: Int, in lines: [String], bankNamesLower: [String]) -> String? {
        var nameParts: [String] = []
        let scanLimit = min(index + 10, lines.count) // Quét tối đa 10 dòng (VCB có thể 7-8 nhãn liên tiếp)
        
        for lineIdx in index..<scanLimit {
            let rawLine = lines[lineIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip dòng rỗng
            if rawLine.isEmpty { continue }
            
            // Skip nhãn hệ thống (Ngân hàng nhận, Nội dung, Mã tham chiếu…)
            if rawLine.range(of: labelNoisePattern, options: .regularExpression) != nil {
                if !nameParts.isEmpty { break } // Đã bắt đầu gom tên → gặp nhãn mới = hết tên
                continue
            }
            
            // Dùng cleanContactName trước khi đếm chữ số (bỏ mã tham chiếu dính tên)
            let cleaned = cleanContactName(rawLine)
            
            // Skip số tài khoản (8+ chữ số SAU KHI clean)
            let digits = cleaned.filter(\.isNumber).count
            if digits >= 8 {
                if !nameParts.isEmpty { break }
                continue
            }
            
            // Skip tên ngân hàng
            if detectBank([rawLine]) != nil {
                if !nameParts.isEmpty { break }
                continue
            }
            
            // Dòng hợp lệ là phần tên
            if isValidNameChunk(rawLine, bankNamesLower: bankNamesLower) {
                nameParts.append(cleaned)
                if nameParts.count >= 3 { break } // Tối đa 3 dòng tên
            } else if !nameParts.isEmpty {
                break // Đã bắt đầu gom → gặp dòng không hợp lệ = hết tên
            }
        }
        
        guard !nameParts.isEmpty else { return nil }
        let fullName = nameParts.joined(separator: " ")
        return isValidContactName(fullName, bankNamesLower: bankNamesLower) ? cleanContactName(fullName) : nil
    }

    private static func isValidNameChunk(_ s: String, bankNamesLower: [String]) -> Bool {
        let clean = cleanContactName(s)
        guard clean.count >= 1 && clean.count <= 60 else { return false }
        let digits = clean.filter(\.isNumber).count
        guard digits <= 2 else { return false }
        
        let lower = clean.lowercased()
        if bankNamesLower.contains(where: { lower.contains($0) }) { return false }
        
        let systemNoise = #"(?i)(thành công|giao dịch|số tiền|nội dung|ngân hàng|phí|mã gd|mã tham chiếu|tham chiếu|thời gian|số tài khoản|stk|chuyển tiền|thanh toán|vnd|vnđ|momo|zalopay|nguồn tiền|tài khoản|tên người|người nhận|người chuyển|thụ hưởng|tài khoản nhận|tài khoản chuyển|đơn vị|chấp nhận|thương nhân|merchant|chi tiết|bảng kê|hoá đơn|hóa đơn|thông tin)"#
        if clean.range(of: systemNoise, options: .regularExpression) != nil { return false }
        
        let words = clean.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        return !words.isEmpty
    }

    private static func isValidContactName(_ s: String, bankNamesLower: [String]) -> Bool {
        let clean = cleanContactName(s)
        guard clean.count >= 3 && clean.count <= 60 else { return false }
        // Không chứa quá 2 chữ số (để tránh lầm số tài khoản/số tiền)
        let digits = clean.filter(\.isNumber).count
        guard digits <= 2 else { return false }
        
        let lower = clean.lowercased()
        // Không chứa tên ngân hàng
        if bankNamesLower.contains(where: { lower.contains($0) }) { return false }
        
        // Không phải từ rác / từ hệ thống / nhãn tiêu đề
        let systemNoise = #"(?i)(thành công|giao dịch|số tiền|nội dung|ngân hàng|phí|mã gd|mã tham chiếu|tham chiếu|thời gian|số tài khoản|stk|chuyển tiền|thanh toán|vnd|vnđ|momo|zalopay|nguồn tiền|tài khoản|tên người|người nhận|người chuyển|thụ hưởng|tài khoản nhận|tài khoản chuyển|đơn vị|chấp nhận|thương nhân|merchant|chi tiết|bảng kê|hoá đơn|hóa đơn|thông tin)"#
        if clean.range(of: systemNoise, options: .regularExpression) != nil { return false }
        
        let words = clean.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        return words.count >= 2
    }

    private static func isStandaloneUppercaseName(_ s: String, bankNamesLower: [String]) -> Bool {
        let clean = cleanContactName(s)
        guard isValidContactName(clean, bankNamesLower: bankNamesLower) else { return false }
        // Toàn bộ ký tự chữ cái phải là IN HOA (VD: NGUYEN VAN A, CTY TNHH XYZ)
        let letters = clean.filter { $0.isLetter }
        // Yêu cầu tối thiểu 3 ký tự chữ cái để tránh match rác OCR (VD: "5G C")
        guard letters.count >= 3 && letters.allSatisfy({ $0.isUppercase }) else { return false }
        let words = clean.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        return (2...6).contains(words.count)
    }

    private static func cleanContactName(_ s: String) -> String {
        var clean = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // Bỏ số thứ tự ở đầu dòng kiểu "07.NGUYEN PHUC TU" -> "NGUYEN PHUC TU"
        clean = clean.replacingOccurrences(of: #"^\d{1,2}\.\s*"#, with: "", options: .regularExpression)
        // Bỏ ký tự nhiễu đặc biệt ở đầu dòng (dấu hai chấm, gạch ngang, dấu chấm, ngoặc...)
        clean = clean.replacingOccurrences(of: #"^[^\p{L}\p{N}]+"#, with: "", options: .regularExpression)
        // Bỏ mã tham chiếu VCB dính vào tên: "TUAN_102881306472" → "TUAN"
        clean = clean.replacingOccurrences(of: #"[_-]\d{6,}$"#, with: "", options: .regularExpression)
        // Bỏ ký tự đặc biệt ở cuối
        clean = clean.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        return clean.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
    }

    // MARK: - Note

    /// Dòng dài nhất không chứa số tiền và không phải ngày, ưu tiên dòng có chữ.
    static func extractNote(from lines: [String], excludingLineAt excludedIndex: Int?) -> String? {
        let _ = #"(?i)(đ|vnd|vnđ|₫|số dư|so du|giao dịch|giao dich|balance|nạp|lỗi|thành công|thanh cong)"#
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

    /// Gợi ý category từ nội dung OCR (contentHint) — không dùng note của user.
    static func suggestCategory(for result: BankParseResult, contentHint: String? = nil) -> String? {
        guard let content = (contentHint ?? result.note)?.lowercased(), !content.isEmpty else {
            return result.direction == .income ? "Khác" : nil
        }
        let note = content
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
