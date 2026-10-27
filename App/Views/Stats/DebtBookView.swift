import SwiftUI
import SwiftData

struct DebtPerson: Identifiable {
    let id = UUID()
    let name: String
    var balance: Int // Positive means they owe me (I gave them money). Negative means I owe them (I borrowed money).
    var transactions: [Transaction]
}

struct DebtBookView: View {
    @Query(filter: #Predicate<Transaction> { tx in
        tx.typeRaw != "normal"
    }, sort: \Transaction.occurredAt, order: .reverse) private var debtTransactions: [Transaction]

    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                if groupedDebts.isEmpty {
                    ContentUnavailableView("Chưa có sổ nợ", systemImage: "book.pages", description: Text("Các giao dịch được gắn nhãn 'Cho mượn tiền', 'Đi vay', 'Trả nợ' sẽ tự động xuất hiện ở đây."))
                } else {
                    let totalLent = groupedDebts.filter { $0.balance > 0 }.reduce(0) { $0 + $1.balance }
                    let totalBorrowed = groupedDebts.filter { $0.balance < 0 }.reduce(0) { $0 + abs($1.balance) }

                    Section {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Người ta nợ mình")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(CurrencyFormatter.full(totalLent))
                                    .font(.headline)
                                    .foregroundStyle(.green)
                            }
                            Spacer()
                            Divider().frame(height: 30)
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("Mình nợ người ta")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(CurrencyFormatter.full(totalBorrowed))
                                    .font(.headline)
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    ForEach(filteredDebts) { person in
                        NavigationLink(destination: DebtPersonDetailView(person: person)) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(person.name)
                                        .font(.headline)
                                    Text("\(person.transactions.count) giao dịch")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    if person.balance > 0 {
                                        Text("Còn nợ bạn")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(CurrencyFormatter.short(person.balance))
                                            .foregroundStyle(.green)
                                            .bold()
                                    } else if person.balance < 0 {
                                        Text("Bạn còn nợ")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(CurrencyFormatter.short(abs(person.balance)))
                                            .foregroundStyle(.red)
                                            .bold()
                                    } else {
                                        Text("Đã tất toán")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sổ Công Nợ")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Tìm tên người...")
        }
    }

    private var groupedDebts: [DebtPerson] {
        var dict: [String: DebtPerson] = [:]

        for tx in debtTransactions {
            let name = tx.contactName ?? "Không tên"
            var person = dict[name] ?? DebtPerson(name: name, balance: 0, transactions: [])
            person.transactions.append(tx)
            
            switch tx.type {
            case .loanGiven:
                person.balance += tx.amount
            case .loanCollected:
                person.balance -= tx.amount
            case .borrowed:
                person.balance -= tx.amount
            case .debtPaid:
                person.balance += tx.amount
            case .normal:
                break
            }
            dict[name] = person
        }

        return dict.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var filteredDebts: [DebtPerson] {
        if searchText.isEmpty { return groupedDebts }
        return groupedDebts.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}

struct DebtPersonDetailView: View {
    let person: DebtPerson

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Trạng thái")
                    Spacer()
                    if person.balance > 0 {
                        Text("Họ đang nợ bạn \(CurrencyFormatter.short(person.balance))")
                            .bold()
                            .foregroundStyle(.green)
                    } else if person.balance < 0 {
                        Text("Bạn đang nợ họ \(CurrencyFormatter.short(abs(person.balance)))")
                            .bold()
                            .foregroundStyle(.red)
                    } else {
                        Text("Đã tất toán")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Lịch sử giao dịch") {
                ForEach(person.transactions) { tx in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tx.type == .loanGiven ? "Cho mượn" : tx.type == .loanCollected ? "Thu nợ" : tx.type == .borrowed ? "Đi vay" : "Trả nợ")
                                .font(.subheadline.bold())
                                .foregroundStyle(tx.direction == .expense ? .red : .green)
                            
                            Text(tx.occurredAt.formatted(date: .numeric, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(tx.direction == .expense ? "-" : "+")\(CurrencyFormatter.short(tx.amount))")
                                .font(.subheadline.bold())
                            if !tx.note.isEmpty {
                                Text(tx.note)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
