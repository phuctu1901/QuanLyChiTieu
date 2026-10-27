import SwiftUI
import SwiftData

/// Nhập nhanh chi tiền mặt hoặc thu nhập: số tiền + phân loại + ghi chú.
struct AddCashView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SpendingCategory.name) private var categories: [SpendingCategory]

    /// Cho phép preset hướng giao dịch (mặc định .expense cho tiền mặt, .income cho thu nhập)
    var presetDirection: Direction = .expense

    @State private var amountText = ""
    @State private var note = ""
    @State private var direction: Direction = .expense
    @State private var type: TransactionType = .normal
    @State private var contactName = ""
    @State private var selectedCategory: SpendingCategory?
    @State private var didInit = false

    private var amount: Int {
        Int(amountText.filter(\.isNumber)) ?? 0
    }

    /// Format lại có "." phân nhóm 3 chữ số ngay khi gõ ("1234567" → "1.234.567").
    private var amountBinding: Binding<String> {
        Binding(
            get: { CurrencyFormatter.groupDigits(amountText) },
            set: { amountText = $0 }
        )
    }


    var body: some View {
        let navTitle: String = {
            if type != .normal { return "Công nợ" }
            return presetDirection == .income ? "Nhập thu nhập" : "Chi tiền mặt"
        }()
        NavigationStack {
            Form {
                Section("Số tiền") {
                    HStack {
                        TextField("0", text: amountBinding)
                            .keyboardType(.numberPad)
                            .font(.system(size: 34, weight: .bold))
                        Text("đ")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    if type == .normal {
                        Picker("Hướng", systemImage: "arrow.up.arrow.down", selection: $direction) {
                            Text("Chi tiền").tag(Direction.expense)
                            Text("Thu tiền").tag(Direction.income)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Section("Loại giao dịch") {
                    Picker("Loại", selection: $type) {
                        Text("Chi tiêu / Thu nhập").tag(TransactionType.normal)
                        Text("Cho mượn tiền").tag(TransactionType.loanGiven)
                        Text("Thu nợ").tag(TransactionType.loanCollected)
                        Text("Đi vay").tag(TransactionType.borrowed)
                        Text("Trả nợ").tag(TransactionType.debtPaid)
                    }
                    if type != .normal {
                        TextField("Tên người giao dịch (Bắt buộc)", text: $contactName)
                            .textInputAutocapitalization(.words)
                    }
                }
                if type == .normal {
                    Section("Phân loại") {
                        Picker("Phân loại", selection: $selectedCategory) {
                            Text("Không phân loại").tag(SpendingCategory?.none)
                            ForEach(categories) { cat in
                                Text(cat.name).tag(SpendingCategory?.some(cat))
                            }
                        }
                    }
                }
                Section("Ghi chú") {
                    TextField(presetDirection == .income ? "VD: Lương tháng 9" : "VD: Cà phê sáng", text: $note, axis: .vertical)
                }
            }
            .navigationTitle(navTitle)
            .onAppear {
                if !didInit {
                    direction = presetDirection
                    didInit = true
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { save() }
                        .disabled(amount <= 0 || (type != .normal && contactName.trimmingCharacters(in: .whitespaces).isEmpty))
                }
            }
        }
    }

    private func save() {
        let now = Date()
        let finalDirection: Direction = {
            switch type {
            case .normal: return direction
            case .loanGiven, .debtPaid: return .expense
            case .loanCollected, .borrowed: return .income
            }
        }()

        let tx = Transaction(
            amount: amount,
            direction: finalDirection,
            type: type,
            contactName: contactName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : contactName.trimmingCharacters(in: .whitespaces),
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
