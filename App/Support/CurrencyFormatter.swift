import Foundation

enum CurrencyFormatter {
    /// "50000đ" / "-1,200,000đ" — gọn cho row
    static func short(_ amount: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "."
        f.locale = Locale(identifier: "vi_VN")
        let num = f.string(from: NSNumber(value: abs(amount))) ?? "\(abs(amount))"
        return "\(num)đ"
    }

    /// "+1.200.000đ" có dấu hướng giao dịch
    static func signed(_ amount: Int, direction: Direction) -> String {
        let prefix = direction == .income ? "+" : "-"
        return prefix + short(amount)
    }

    /// "5.000.000 ₫" đầy đủ cho header/tổng
    static func full(_ amount: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "vi_VN")
        f.currencySymbol = "₫"
        return f.string(from: NSNumber(value: amount)) ?? "\(amount) ₫"
    }
}
