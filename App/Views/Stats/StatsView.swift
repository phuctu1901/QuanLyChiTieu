import SwiftUI
import SwiftData
import Charts

/// Tab "Thống kê": chi tiêu theo khoảng thời gian + theo phân loại.
struct StatsView: View {
    @State private var range: StatsRange = .month

    private var window: DateInterval {
        let cal = Calendar.current
        let now = Date()
        switch range {
        case .day: return DateInterval(start: cal.startOfDay(for: now), duration: 24 * 3600)
        case .week:
            let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? cal.startOfDay(for: now)
            return DateInterval(start: start, duration: 7 * 24 * 3600)
        case .month:
            let interval = cal.dateInterval(of: .month, for: now) ?? DateInterval(start: now, duration: 0)
            return interval
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Xem theo", selection: $range) {
                        Text("Ngày").tag(StatsRange.day)
                        Text("Tuần").tag(StatsRange.week)
                        Text("Tháng").tag(StatsRange.month)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    NavigationLink(destination: DebtBookView()) {
                        Label("Sổ công nợ (Cho mượn / Đi vay)", systemImage: "book.closed")
                            .foregroundStyle(.blue)
                    }
                }
                StatsContentView(window: window)
           }
            .navigationTitle("Thống kê")
        }
    }
}

struct StatsContentView: View {
    @Query private var transactions: [Transaction]
    
    init(window: DateInterval) {
        let start = window.start
        let end = window.end
        let normal = TransactionType.normal.rawValue
        
        _transactions = Query(
            filter: #Predicate<Transaction> {
                $0.typeRaw == normal && $0.occurredAt >= start && $0.occurredAt <= end
            },
            sort: \.occurredAt
        )
    }
    
    private var expensesInWindow: [Transaction] {
        transactions.filter { $0.direction == .expense }
    }

    private var incomeInWindow: [Transaction] {
        transactions.filter { $0.direction == .income }
    }

    private var byCategory: [(category: SpendingCategory?, total: Int)] {
        let grouped = Dictionary(grouping: expensesInWindow, by: { $0.category })
        return grouped.map { (cat, txs) in (cat, txs.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.1 > $1.1 }
    }
    
    var body: some View {
        summarySection
        if !expensesInWindow.isEmpty {
            Section("Chi theo ngày") {
                Chart(expensesInWindow) { tx in
                    BarMark(
                        x: .value("Ngày", tx.occurredAt, unit: .day),
                        y: .value("Số tiền", tx.amount)
                    )
                    .foregroundStyle(by: .value("Phân loại", tx.category?.name ?? "Khác"))
                }
                .chartScrollableAxes(.horizontal)
                .frame(height: 220)
                .padding(.vertical, 8)
            }
            Section("Chi theo phân loại") {
                Chart(byCategory, id: \.category?.id) { item in
                    SectorMark(
                        angle: .value("Số tiền", item.total),
                        innerRadius: .ratio(0.6),
                        angularInset: 1.5
                    )
                    .cornerRadius(4)
                    .foregroundStyle(by: .value("Phân loại", item.category?.name ?? "Khác"))
                }
                .frame(height: 240)
                .padding(.vertical, 8)
            }
            categoryListSection
        } else {
            Section {
                Text("Chưa có dữ liệu chi tiêu trong khoảng này.")
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var summarySection: some View {
        Section {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chi").font(.caption).foregroundStyle(.secondary)
                    Text(CurrencyFormatter.full(expensesInWindow.reduce(0) { $0 + $1.amount }))
                        .font(.headline).foregroundStyle(.red)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Thu").font(.caption).foregroundStyle(.secondary)
                    Text(CurrencyFormatter.full(incomeInWindow.reduce(0) { $0 + $1.amount }))
                        .font(.headline).foregroundStyle(.green)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var categoryListSection: some View {
        Section("Chi tiết") {
            ForEach(byCategory, id: \.category?.id) { item in
                HStack {
                    CategoryIconView(category: item.category)
                    Text(item.category?.name ?? "Khác")
                    Spacer()
                    Text(CurrencyFormatter.short(item.total))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

enum StatsRange: String, CaseIterable {
    case day, week, month
}
