import SwiftUI
import SwiftData
import PhotosUI

/// Tab "Hôm nay": giao dịch trong ngày + nhập ảnh + thêm chi tiền mặt.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppServices.self) private var services
    @Query(sort: \Transaction.occurredAt, order: .reverse)
    private var allTransactions: [Transaction]
    @Query(filter: #Predicate<PendingExtraction> { $0.resolvedAt == nil },
           sort: \PendingExtraction.createdAt)
    private var pendingExtractions: [PendingExtraction]

    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showAddCash = false
    @State private var showReview = false
    @State private var showPhotoPick = false
    @State private var processingCount = 0

    private var todayTransactions: [Transaction] {
        allTransactions.filter { Calendar.current.isDateInToday($0.occurredAt) }
    }

    private var todayExpense: Int {
        todayTransactions.filter { $0.direction == .expense }.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection
                if !pendingExtractions.isEmpty {
                    pendingSection
                }
                transactionsSection
            }
            .navigationTitle("Hôm nay")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showReview = true
                    } label: {
                        Label("Xem lại cuối ngày", systemImage: "moon.stars.fill")
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    photoPickerButton
                    Spacer()
                    addCashButton
                }
            }
            .sheet(isPresented: $showAddCash) {
                AddCashView()
            }
            .sheet(isPresented: $showReview) {
                EveningReviewView()
            }
            .sheet(isPresented: $showPhotoPick) {
                PhotoPickView()
            }
            .onChange(of: selectedPhotos) { _, items in
                guard !items.isEmpty else { return }
                let picked = items
                selectedPhotos = []
                Task { await ingestPicked(picked) }
            }
            .overlay {
                if processingCount > 0 {
                    ProgressView("Đang bóc tách \(processingCount) ảnh…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Chi tiêu hôm nay")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(CurrencyFormatter.full(todayExpense))
                        .font(.title.bold())
                        .foregroundStyle(.red)
                }
                Spacer()
                if !pendingExtractions.isEmpty {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Chờ xác nhận")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(pendingExtractions.count) ảnh")
                            .font(.headline)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var pendingSection: some View {
        Section("Chờ xác nhận") {
            ForEach(pendingExtractions) { pending in
                NavigationLink {
                    PendingEditView(pending: pending)
                } label: {
                    PendingRow(pending: pending)
                }
            }
        }
    }

    private var transactionsSection: some View {
        Section(todayTransactions.isEmpty ? "" : "Giao dịch") {
            if todayTransactions.isEmpty {
                Text("Chưa có giao dịch nào hôm nay.\nChụp màn hình app ngân hàng rồi bấm nút ảnh để nhập.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
            }
            ForEach(todayTransactions) { tx in
                TransactionRow(transaction: tx)
            }
        }
    }

    // MARK: - Buttons

    private var photoPickerButton: some View {
        Button {
            showPhotoPick = true
        } label: {
            Label("Nhập ảnh", systemImage: "photo.badge.plus")
        }
        .disabled(processingCount > 0)
    }

    private var addCashButton: some View {
        Button {
            showAddCash = true
        } label: {
            Label("Chi tiền mặt", systemImage: "plus.circle.fill")
        }
    }

    // MARK: - Data

    private func ingestPicked(_ items: [PhotosPickerItem]) async {
        for item in items {
            processingCount += 1
            if let data = try? await item.loadTransferable(type: Data.self) {
                await services.pipeline.ingest(imageData: data, source: .manualPhoto)
            }
            processingCount -= 1
        }
    }
}

// MARK: - Rows

struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: 12) {
            CategoryIconView(category: transaction.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.note.isEmpty ? "Giao dịch" : transaction.note)
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let bank = transaction.bankName {
                        Text(bank)
                    }
                    Text(transaction.occurredAt, format: .dateTime.hour().minute())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(CurrencyFormatter.signed(transaction.amount, direction: transaction.direction))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(transaction.direction == .expense ? Color.primary : Color.green)
        }
    }
}

struct PendingRow: View {
    let pending: PendingExtraction

    var body: some View {
        HStack(spacing: 12) {
            if let image = ImageStore.shared?.loadImage(path: pending.imagePath) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(pending.parsed?.note ?? "Không đọc được nội dung")
                    .font(.subheadline)
                    .lineLimit(1)
                Text(pending.parsed.map { CurrencyFormatter.signed($0.amount ?? 0, direction: $0.direction) } ?? "—")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Spacer()
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.orange)
        }
    }
}

struct CategoryIconView: View {
    let category: SpendingCategory?

    var body: some View {
        Image(systemName: category?.iconName ?? "questionmark.circle")
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(Color(hex: category?.colorHex ?? "#8E8E93"), in: RoundedRectangle(cornerRadius: 8))
    }
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension Calendar {
    func isDateInTodayFilter(_ dates: [Date]) -> [Date] {
        dates.filter { isDateInToday($0) }
    }
}
