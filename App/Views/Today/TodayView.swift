import SwiftUI
import SwiftData
import PhotosUI

/// Tab chính: giao dịch gần đây nhóm theo ngày + nhập ảnh + chi tiền mặt.
/// Hiển thị toàn bộ giao dịch (không giới hạn "hôm nay"), nhóm theo ngày giảm dần.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppServices.self) private var services
    
    @Query private var allTransactions: [Transaction]
    
    @Query(filter: #Predicate<PendingExtraction> { $0.resolvedAt == nil },
           sort: \PendingExtraction.createdAt)
    private var pendingExtractions: [PendingExtraction]

    init() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        _allTransactions = Query(
            filter: #Predicate<Transaction> { $0.occurredAt >= cutoff },
            sort: \.occurredAt, order: .reverse
        )
    }

    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showAddCash = false
    @State private var showAddIncome = false
    @State private var showReview = false
    @State private var showPhotoPick = false
    @State private var processingCount = 0
    @State private var fabExpanded = false

    // Scan state
    @State private var fullScanning = false
    @State private var fullScanSummary: PhotoMonitor.FullScanSummary?

    // MARK: - Computed

    private var todayExpense: Int {
        allTransactions
            .filter { $0.direction == .expense && $0.type == .normal && Calendar.current.isDateInToday($0.occurredAt) }
            .reduce(0) { $0 + $1.amount }
    }

    private var weekExpense: Int {
        let cal = Calendar.current
        let weekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return allTransactions
            .filter { $0.direction == .expense && $0.type == .normal && $0.occurredAt >= weekStart }
            .reduce(0) { $0 + $1.amount }
    }

    /// Nhóm giao dịch theo ngày.
    private var groupedByDay: [(date: Date, transactions: [Transaction])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: allTransactions) { tx in
            cal.startOfDay(for: tx.occurredAt)
        }
        return grouped
            .map { (date: $0.key, transactions: $0.value) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                List {
                    // MARK: - Summary cards
                    summaryCards

                    // MARK: - Scan progress (if running)
                    if fullScanning, let s = fullScanSummary {
                        scanProgressSection(s)
                    } else if let s = fullScanSummary, !fullScanning, s.total > 0 {
                        scanResultSection(s)
                    }

                    // MARK: - Pending
                    if !pendingExtractions.isEmpty {
                        pendingSection
                    }

                    // MARK: - Transactions grouped by day
                    if groupedByDay.isEmpty {
                        Section {
                            emptyStateView
                        }
                    } else {
                        ForEach(groupedByDay, id: \.date) { group in
                            Section {
                                ForEach(group.transactions) { tx in
                                    TransactionRow(transaction: tx)
                                }
                            } header: {
                                dayHeader(group.date, transactions: group.transactions)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle("Giao dịch")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            startFullScan()
                        } label: {
                            Label("Rà quét", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(fullScanning)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showReview = true
                        } label: {
                            Label("Xem lại cuối ngày", systemImage: "moon.stars.fill")
                        }
                    }
                }

                // MARK: - FAB
                fabOverlay
            }
            .sheet(isPresented: $showAddCash) {
                AddCashView()
            }
            .sheet(isPresented: $showAddIncome) {
                AddCashView(presetDirection: .income)
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

    // MARK: - Summary Cards

    private var summaryCards: some View {
        Section {
            HStack(spacing: 16) {
                // Hôm nay
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "sun.max.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text("Hôm nay")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(CurrencyFormatter.full(todayExpense))
                        .font(.title3.bold())
                        .foregroundStyle(todayExpense > 0 ? .red : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                    .frame(height: 40)

                // Tuần này
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .foregroundStyle(.blue)
                            .font(.caption)
                        Text("Tuần này")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(CurrencyFormatter.full(weekExpense))
                        .font(.title3.bold())
                        .foregroundStyle(weekExpense > 0 ? .red : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Pending badge
                if !pendingExtractions.isEmpty {
                    Divider()
                        .frame(height: 40)
                    VStack(alignment: .trailing, spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text("\(pendingExtractions.count)")
                            .font(.title3.bold())
                            .foregroundStyle(.orange)
                        Text("chờ")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Scan

    private func scanProgressSection(_ s: PhotoMonitor.FullScanSummary) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Đang rà quét \(s.scanned)/\(s.total) ảnh…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: Double(s.scanned), total: Double(max(s.total, 1)))
                    .tint(.blue)
            }
        }
    }

    private func scanResultSection(_ s: PhotoMonitor.FullScanSummary) -> some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Đã quét \(s.total) ảnh")
                        .font(.footnote.weight(.medium))
                    Text(fullScanResultText(s))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Bỏ qua") {
                    fullScanSummary = nil
                }
                .font(.caption)
            }
        }
    }

    private func fullScanResultText(_ s: PhotoMonitor.FullScanSummary) -> String {
        var parts: [String] = []
        if s.created > 0 { parts.append("Mới: \(s.created)") }
        if s.duplicates > 0 { parts.append("Đã có: \(s.duplicates)") }
        if s.notTransactions > 0 { parts.append("Loại: \(s.notTransactions)") }
        if s.failed > 0 { parts.append("Lỗi: \(s.failed)") }
        return parts.joined(separator: " · ")
    }

    private func startFullScan() {
        guard !fullScanning else { return }
        fullScanning = true
        fullScanSummary = nil
        let pipeline = services.pipeline
        let processedStore = services.processedStore
        Task.detached(priority: .userInitiated) {
            let summary = await PhotoMonitor.fullScan(
                pipeline: pipeline,
                processedStore: processedStore
            ) { progress in
                Task { @MainActor in
                    fullScanSummary = progress
                }
            }
            await MainActor.run {
                fullScanSummary = summary
                fullScanning = false
            }
        }
    }

    // MARK: - Day Header

    private func dayHeader(_ date: Date, transactions: [Transaction]) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(date)
        let isYesterday = cal.isDateInYesterday(date)
        let dayTotal = transactions
            .filter { $0.direction == .expense && $0.type == .normal }
            .reduce(0) { $0 + $1.amount }

        let title: String = {
            if isToday { return "Hôm nay" }
            if isYesterday { return "Hôm qua" }
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "vi_VN")
            fmt.dateFormat = "EEEE, dd/MM"
            return fmt.string(from: date).capitalized
        }()

        return HStack {
            Text(title)
            Spacer()
            if dayTotal > 0 {
                Text("-\(CurrencyFormatter.short(dayTotal))")
                    .foregroundStyle(.red)
                    .font(.caption.weight(.semibold))
            }
        }
    }

    // MARK: - Pending

    @ViewBuilder
    private var pendingSection: some View {
        let grouped = Dictionary(grouping: pendingExtractions) { pending -> Int in
            let date = pending.parsed?.occurredAt ?? pending.createdAt
            let cal = Calendar.current
            if cal.isDateInToday(date) { return 0 }
            if cal.isDateInYesterday(date) { return 1 }
            
            let now = Date()
            if let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start, date >= weekStart { return 2 }
            if let monthStart = cal.dateInterval(of: .month, for: now)?.start, date >= monthStart { return 3 }
            return 4
        }
        
        let keys = grouped.keys.sorted()
        ForEach(keys, id: \.self) { key in
            let title: String = {
                switch key {
                case 0: return "Chờ xác nhận (Hôm nay)"
                case 1: return "Chờ xác nhận (Hôm qua)"
                case 2: return "Chờ xác nhận (Tuần này)"
                case 3: return "Chờ xác nhận (Tháng này)"
                default: return "Chờ xác nhận (Cũ hơn)"
                }
            }()
            
            Section {
                ForEach(grouped[key]!) { pending in
                    NavigationLink {
                        PendingEditView(pending: pending)
                    } label: {
                        PendingRow(pending: pending)
                    }
                }
            } header: {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                    Text(title)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)
            Text("Chưa có giao dịch nào")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Chụp màn hình app ngân hàng (tự nhận)\nhoặc bấm ➕ để nhập ảnh / chi tiền mặt.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .listRowSeparator(.hidden)
    }

    // MARK: - FAB Overlay

    private var fabOverlay: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack {
                Spacer()
                ZStack(alignment: .bottom) {
                    if fabExpanded {
                        Color.black.opacity(0.25)
                            .ignoresSafeArea()
                            .onTapGesture { withAnimation(.spring(duration: 0.25)) { fabExpanded = false } }
                            .transition(.opacity)
                    }

                    VStack(spacing: 14) {
                        if fabExpanded {
                            fabSubButton(
                                title: "Nhập ảnh",
                                icon: "photo.badge.plus",
                                color: .blue
                            ) {
                                withAnimation(.spring(duration: 0.25)) { fabExpanded = false }
                                showPhotoPick = true
                            }
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.3).combined(with: .opacity).combined(with: .offset(y: 20)),
                                removal: .scale(scale: 0.5).combined(with: .opacity)
                            ))

                            fabSubButton(
                                title: "Tiền mặt",
                                icon: "banknote",
                                color: .green
                            ) {
                                withAnimation(.spring(duration: 0.25)) { fabExpanded = false }
                                showAddCash = true
                            }
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.3).combined(with: .opacity).combined(with: .offset(y: 10)),
                                removal: .scale(scale: 0.5).combined(with: .opacity)
                            ))

                            fabSubButton(
                                title: "Thu nhập",
                                icon: "arrow.down.circle.fill",
                                color: .orange
                            ) {
                                withAnimation(.spring(duration: 0.25)) { fabExpanded = false }
                                showAddIncome = true
                            }
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.3).combined(with: .opacity).combined(with: .offset(y: 5)),
                                removal: .scale(scale: 0.5).combined(with: .opacity)
                            ))
                        }

                        Button {
                            withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                                fabExpanded.toggle()
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                )
                                .shadow(color: Color.accentColor.opacity(0.4), radius: 8, y: 4)
                                .rotationEffect(.degrees(fabExpanded ? 45 : 0))
                        }
                        .disabled(processingCount > 0)
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .ignoresSafeArea(.keyboard)
    }

    private func fabSubButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

            Button(action: action) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(color.gradient))
                    .shadow(color: color.opacity(0.4), radius: 6, y: 3)
            }
        }
        .padding(.trailing, 6)
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
            if transaction.type != .normal {
                Image(systemName: "person.circle.fill")
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 8))
            } else {
                CategoryIconView(category: transaction.category)
            }
            VStack(alignment: .leading, spacing: 2) {
                if transaction.type != .normal, let name = transaction.contactName {
                    HStack(spacing: 4) {
                        Text(transaction.type == .loanGiven ? "Cho mượn:" : transaction.type == .loanCollected ? "Thu nợ:" : transaction.type == .borrowed ? "Đi vay:" : "Trả nợ:")
                            .font(.caption.bold())
                            .foregroundStyle(.blue)
                        Text(name)
                            .font(.subheadline.bold())
                    }
                    if !transaction.note.isEmpty {
                        Text(transaction.note)
                            .font(.caption)
                            .lineLimit(1)
                    }
                } else {
                    let counterpart = transaction.contactName ?? "đối tác"
                    let defaultNote = transaction.direction == .income ? "Nhận từ \(counterpart)" : "Chuyển đến \(counterpart)"
                    Text(transaction.note.isEmpty ? defaultNote : transaction.note)
                        .font(.subheadline)
                        .lineLimit(1)
                }
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
                let counterpart = pending.parsed?.contactName ?? "đối tác"
                let defaultNote = pending.parsed?.direction == .income ? "Nhận từ \(counterpart)" : "Chuyển đến \(counterpart)"
                let note = pending.parsed?.note ?? ""
                Text(note.isEmpty ? defaultNote : note)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(pending.parsed.map { CurrencyFormatter.signed($0.amount ?? 0, direction: $0.direction) } ?? "—")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                if let time = pending.parsed?.occurredAt {
                    let isFromImage = pending.parsed?.occurredAtSource == .fullDateTime
                        || pending.parsed?.occurredAtSource == .dateWithStatusBarTime
                        || pending.parsed?.occurredAtSource == .dateOnly
                    HStack(spacing: 2) {
                        Image(systemName: isFromImage ? "clock" : "camera")
                        Text(time, format: .dateTime.day().month().hour().minute())
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
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
