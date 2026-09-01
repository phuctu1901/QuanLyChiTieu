import SwiftUI
import SwiftData

/// Tab "Ngân sách": tổng tháng + limit theo phân loại, cảnh báo vượt.
struct BudgetView: View {
    @Environment(\.modelContext) private var context
    @Query private var budgets: [MonthlyBudget]
    @Query(sort: \Transaction.occurredAt) private var transactions: [Transaction]

    @State private var showEdit = false

    private var currentMonth: (year: Int, month: Int) {
        let c = Calendar.current.dateComponents([.year, .month], from: Date())
        return (c.year ?? 2026, c.month ?? 1)
    }

    private var monthBudget: MonthlyBudget? {
        budgets.first { $0.year == currentMonth.year && $0.month == currentMonth.month }
    }

    private var monthInterval: DateInterval {
        Calendar.current.dateInterval(of: .month, for: Date()) ?? DateInterval(start: Date(), duration: 0)
    }

    private var monthExpense: Int {
        transactions
            .filter { $0.direction == .expense && monthInterval.contains($0.occurredAt) }
            .reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        NavigationStack {
            List {
                totalSection
                categoryLimitsSection
                if monthBudget == nil {
                    Section {
                        Button("Đặt ngân sách tháng này") { showEdit = true }
                    }
                }
            }
            .navigationTitle("Ngân sách")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sửa") { showEdit = true }
                }
            }
            .sheet(isPresented: $showEdit) {
                BudgetEditView()
            }
        }
    }

    private var totalSection: some View {
        Section("Ngân sách tổng — tháng \(String(format: "%02d", currentMonth.month))/\(currentMonth.year)") {
            if let limit = monthBudget?.totalLimit, limit > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Đã chi").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("Giới hạn").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(CurrencyFormatter.full(monthExpense))
                            .font(.title3.bold())
                            .foregroundStyle(monthExpense > limit ? .red : .primary)
                        Spacer()
                        Text(CurrencyFormatter.full(limit))
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    BudgetProgressView(spent: monthExpense, limit: limit)
                    if monthExpense > limit {
                        Label("Đã vượt ngân sách \(CurrencyFormatter.short(monthExpense - limit))", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 4)
            } else {
                Text("Chưa đặt ngân sách tổng cho tháng này.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var categoryLimitsSection: some View {
        Section("Ngân sách theo phân loại") {
            let limits = monthBudget?.categoryLimits ?? []
            if limits.isEmpty {
                Text("Chưa có ngân sách theo phân loại.")
                    .foregroundStyle(.secondary)
            }
            ForEach(limits, id: \.id) { limit in
                if let cat = limit.category {
                    let spent = expense(for: cat)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            CategoryIconView(category: cat)
                            Text(cat.name)
                            Spacer()
                            Text("\(CurrencyFormatter.short(spent)) / \(CurrencyFormatter.short(limit.limitAmount))")
                                .font(.caption)
                                .foregroundStyle(spent > limit.limitAmount ? .red : .secondary)
                        }
                        BudgetProgressView(spent: spent, limit: limit.limitAmount)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func expense(for category: SpendingCategory) -> Int {
        transactions
            .filter { $0.direction == .expense && $0.category?.id == category.id && monthInterval.contains($0.occurredAt) }
            .reduce(0) { $0 + $1.amount }
    }
}

/// Thanh tiến độ ngân sách: xanh <80%, vàng 80-100%, đỏ >100%.
struct BudgetProgressView: View {
    let spent: Int
    let limit: Int

    private var ratio: Double {
        guard limit > 0 else { return 0 }
        return Double(spent) / Double(limit)
    }

    private var color: Color {
        if ratio > 1.0 { return .red }
        if ratio > 0.8 { return .orange }
        return .green
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * min(ratio, 1.0))
            }
        }
        .frame(height: 8)
    }
}
