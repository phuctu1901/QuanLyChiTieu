import SwiftUI
import SwiftData

/// Sửa ngân sách tháng: tổng + theo phân loại.
struct BudgetEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SpendingCategory.name) private var categories: [SpendingCategory]
    @Query private var budgets: [MonthlyBudget]

    @State private var totalText = ""
    @State private var categoryAmounts: [UUID: String] = [:]

    private var currentMonth: (year: Int, month: Int) {
        let c = Calendar.current.dateComponents([.year, .month], from: Date())
        return (c.year ?? 2026, c.month ?? 1)
    }

    private var monthBudget: MonthlyBudget? {
        return budgets.first { $0.year == currentMonth.year && $0.month == currentMonth.month }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tổng tháng \(String(format: "%02d", currentMonth.month))/\(currentMonth.year)") {
                    HStack {
                        TextField("Không giới hạn", text: $totalText)
                            .keyboardType(.numberPad)
                        Text("đ").foregroundStyle(.secondary)
                    }
                }
                Section("Theo phân loại") {
                    ForEach(categories) { cat in
                        HStack {
                            CategoryIconView(category: cat)
                            Text(cat.name)
                            Spacer()
                            TextField("0", text: bindingFor(cat))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 120)
                        }
                    }
                }
            }
            .navigationTitle("Sửa ngân sách")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { save() }
                }
            }
        }
        .onAppear { loadExisting() }
    }

    private func bindingFor(_ cat: SpendingCategory) -> Binding<String> {
        return Binding(
            get: { categoryAmounts[cat.id] ?? "" },
            set: { categoryAmounts[cat.id] = $0 }
        )
    }

    private func loadExisting() {
        guard let budget = monthBudget else { return }
        if let total = budget.totalLimit {
            totalText = String(total)
        }
        for limit in budget.categoryLimits {
            if let cat = limit.category {
                categoryAmounts[cat.id] = String(limit.limitAmount)
            }
        }
    }

    private func save() {
        let budget = monthBudget ?? MonthlyBudget(year: currentMonth.year, month: currentMonth.month)
        if monthBudget == nil {
            context.insert(budget)
        }
        budget.totalLimit = Int(totalText.filter(\.isNumber))
        for limit in budget.categoryLimits {
            context.delete(limit)
        }
        for cat in categories {
            guard let text = categoryAmounts[cat.id],
                  let amount = Int(text.filter(\.isNumber)),
                  amount > 0 else { continue }
            let limit = CategoryBudget(category: cat, limitAmount: amount)
            limit.monthlyBudget = budget
            context.insert(limit)
        }
        try? context.save()
        dismiss()
    }
}
