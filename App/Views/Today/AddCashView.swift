import SwiftUI
import SwiftData

/// Nhập nhanh chi tiền mặt: số tiền + phân loại + ghi chú.
struct AddCashView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SpendingCategory.name) private var categories: [SpendingCategory]

    @State private var amountText = ""
    @State private var note = ""
    @State private var direction: Direction = .expense
    @State private var selectedCategory: SpendingCategory?

    private var amount: Int {
        Int(amountText.filter(\.isNumber)) ?? 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Số tiền") {
                    HStack {
                        TextField("0", text: $amountText)
                            .keyboardType(.numberPad)
                            .font(.system(size: 34, weight: .bold))
                        Text("đ")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    Picker("Loại", systemImage: "arrow.up.arrow.down", selection: $direction) {
                        Text("Chi tiền").tag(Direction.expense)
                        Text("Thu tiền").tag(Direction.income)
                    }
                    .pickerStyle(.segmented)
                }
                Section("Phân loại") {
                    Picker("Phân loại", selection: $selectedCategory) {
                        Text("Không phân loại").tag(SpendingCategory?.none)
                        ForEach(categories) { cat in
                            Text(cat.name).tag(SpendingCategory?.some(cat))
                        }
                    }
                }
                Section("Ghi chú") {
                    TextField("VD: Cà phê sáng", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Chi tiền mặt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { save() }
                        .disabled(amount <= 0)
                }
            }
        }
    }

    private func save() {
        let now = Date()
        let tx = Transaction(
            amount: amount,
            direction: direction,
            occurredAt: now,
            note: note,
            source: .cash,
            dedupKey: Transaction.dedupKey(bankName: nil, amount: amount, occurredAt: now, note: note) + "-" + UUID().uuidString
        )
        tx.category = selectedCategory
        context.insert(tx)
        try? context.save()
        dismiss()
    }
}
