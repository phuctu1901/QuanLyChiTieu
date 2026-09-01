import SwiftUI
import SwiftData

/// Màn hình review cuối ngày: xác nhận pending extractions + nhập chi tiền mặt + hoàn tất.
struct EveningReviewView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<PendingExtraction> { $0.resolvedAt == nil },
           sort: \PendingExtraction.createdAt)
    private var pendingAll: [PendingExtraction]

    @State private var showAddCash = false
    @State private var completing = false
    @Environment(\.dismiss) private var dismiss

    private var pendingToday: [PendingExtraction] {
        pendingAll.filter { Calendar.current.isDateInToday($0.createdAt) }
    }

    /// Pending cũ hơn hôm nay vẫn hiển thị nhưng gắn nhãn
    private var pendingOlder: [PendingExtraction] {
        pendingAll.filter { !Calendar.current.isDateInToday($0.createdAt) }
    }

    var body: some View {
        NavigationStack {
            List {
                if pendingToday.isEmpty && pendingOlder.isEmpty {
                    emptySection
                } else {
                    if !pendingToday.isEmpty {
                        pendingSection("Hôm nay", items: pendingToday)
                    }
                    if !pendingOlder.isEmpty {
                        pendingSection("Còn tồn đọng", items: pendingOlder)
                    }
                }
                cashSection
                completeSection
            }
            .navigationTitle("Tổng kết ngày")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismissUI() }
                }
            }
            .sheet(isPresented: $showAddCash) {
                AddCashView()
            }
        }
    }

    // MARK: - Sections

    private var emptySection: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.green)
                Text("Không có giao dịch chờ xác nhận.")
                    .font(.headline)
                Text("Nếu còn chi tiêu bằng tiền mặt chưa ghi, hãy nhập thêm bên dưới.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }

    private func pendingSection(_ title: String, items: [PendingExtraction]) -> some View {
        Section(title) {
            ForEach(items) { pending in
                NavigationLink {
                    PendingEditView(pending: pending)
                } label: {
                    PendingRow(pending: pending)
                }
            }
        }
    }

    private var cashSection: some View {
        Section("Chi tiền mặt") {
            Button {
                showAddCash = true
            } label: {
                Label("Thêm chi tiêu tiền mặt", systemImage: "plus.circle.fill")
            }
        }
    }

    private var completeSection: some View {
        Section {
            Button {
                completeDay()
            } label: {
                Label("Hoàn tất ngày hôm nay", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
        } footer: {
            Text("Nếu vẫn còn giao dịch chờ xác nhận, chúng sẽ vẫn ở đây ngày mai.")
        }
    }

    // MARK: - Actions

    private func dismissUI() {
        dismiss()
    }

    private func completeDay() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let key = formatter.string(from: Date())
        let state = DayReviewState(day: key)
        context.insert(state)
        try? context.save()
        dismiss()
    }
}
