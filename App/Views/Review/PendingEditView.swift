import SwiftUI
import SwiftData

/// Sửa + xác nhận một pending extraction: xem ảnh, raw OCR, form sửa đầy đủ.
struct PendingEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SpendingCategory.name) private var categories: [SpendingCategory]

    let pending: PendingExtraction

    @State private var amountText = ""
    @State private var note = ""
    @State private var direction: Direction = .expense
    @State private var type: TransactionType = .normal
    @State private var contactName = ""
    @State private var bankName: String = ""
    @State private var occurredAt: Date = Date()
    @State private var selectedCategory: SpendingCategory?
    @State private var showImage = false
    @State private var loaded = false

    // AI re-parse
    @State private var aiRunning = false
    @State private var aiResultMessage: String?
    @State private var aiSucceeded = false

    var body: some View {
        Form {
            imageSection
            aiSection
            amountSection
            typeSection
            noteSection
            if type == .normal {
                categorySection
            }
            rawOCRSection
        }
        .navigationTitle("Xác nhận giao dịch")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Bỏ qua") { resolveAsIgnored() }
                    .foregroundStyle(.red)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Xác nhận") { resolveAsTransaction() }
                    .disabled(Int(amountText.filter(\.isNumber)) ?? 0 <= 0 || (type != .normal && contactName.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
        .onAppear { loadState() }
        .sheet(isPresented: $showImage) {
            ImageViewer(imagePath: pending.imagePath)
        }
    }

    // MARK: - Sections

    private var imageSection: some View {
        Section {
            Button {
                showImage = true
            } label: {
                if let image = ImageStore.shared?.loadImage(path: pending.imagePath) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Label("Xem ảnh gốc", systemImage: "photo")
                }
            }
            .buttonStyle(.plain)
        } header: {
            Text("Ảnh chụp màn hình")
        } footer: {
            Text("Chạm để xem ảnh lớn. So sánh với kết quả bóc tách bên dưới rồi sửa nếu OCR sai.")
        }
    }

    /// Nút ép chạy AI on-device bóc tách lại từ text OCR — đắp field đang trống.
    private var aiSection: some View {
        Section {
            Button {
                runAIParse()
            } label: {
                HStack {
                    Label(
                        aiRunning ? "Đang chạy AI…" : "Bóc tách lại bằng AI",
                        systemImage: "sparkles"
                    )
                    if aiRunning {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(aiRunning || aiUnavailable)

            if aiUnavailable {
                Label("AI không khả dụng — cần Apple Intelligence bật và ngôn ngữ máy được hỗ trợ.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if let message = aiResultMessage {
                Label(message, systemImage: aiSucceeded ? "checkmark.circle" : "xmark.circle")
                    .font(.footnote)
                    .foregroundStyle(aiSucceeded ? Color.green : Color.orange)
            }
        } header: {
            Text("Trợ lý AI")
        } footer: {
            Text("Chạy Apple Intelligence trên máy để bóc tách toàn bộ từ ảnh: số tiền, thời điểm, nội dung, phân loại. Kết quả đè giá trị hiện tại — kiểm tra trước khi xác nhận.")
        }
    }

    private var aiUnavailable: Bool {
        !TransactionParserAI.isAvailable
    }

    private var amountSection: some View {
        Section("Số tiền") {
            HStack {
                TextField("0", text: amountBinding)
                    .keyboardType(.numberPad)
                    .font(.system(size: 28, weight: .bold))
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
            DatePicker("Thời điểm", selection: $occurredAt)
            if let note = timeSourceNote {
                Label(note.text, systemImage: note.icon)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            TextField(type == .normal ? "Tên đối tác (Tuỳ chọn)" : "Tên người giao dịch (Bắt buộc)", text: $contactName)
                .textInputAutocapitalization(.words)
            TextField("Ngân hàng", text: $bankName)
        }
    }

    private var typeSection: some View {
        Section("Loại giao dịch") {
            Picker("Loại", selection: $type) {
                Text("Chi tiêu / Thu nhập").tag(TransactionType.normal)
                Text("Cho mượn tiền").tag(TransactionType.loanGiven)
                Text("Thu nợ").tag(TransactionType.loanCollected)
                Text("Đi vay").tag(TransactionType.borrowed)
                Text("Trả nợ").tag(TransactionType.debtPaid)
            }
        }
    }

    private var noteSection: some View {
        Section {
            TextField("VD: Trả tiền ăn trưa cùng đội", text: $note, axis: .vertical)
        } header: {
            Text("Ghi chú")
        } footer: {
            Text("Ghi chú do bạn tự viết — app không tự điền từ ảnh.")
        }
    }

    private var categorySection: some View {
        Section("Phân loại") {
            Picker("Phân loại", selection: $selectedCategory) {
                Text("Không phân loại").tag(SpendingCategory?.none)
                ForEach(categories) { cat in
                    Text(cat.name).tag(SpendingCategory?.some(cat))
                }
            }
        }
    }

    private var rawOCRSection: some View {
        Section("Text OCR gốc") {
            Text(pending.ocrRawText)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    // MARK: - State

    /// Format lại có "." phân nhóm 3 chữ số ngay khi gõ ("1234567" → "1.234.567").
    private var amountBinding: Binding<String> {
        Binding(
            get: { CurrencyFormatter.groupDigits(amountText) },
            set: { amountText = $0 }
        )
    }

    /// Chú thích nguồn thời điểm — giúp user biết khi nào cần sửa tay.
    private var timeSourceNote: (text: String, icon: String)? {
        switch pending.parsed?.occurredAtSource {
        case .fullDateTime:
            return ("Thời điểm đọc từ ảnh (đủ ngày + giờ)", "checkmark.circle")
        case .dateWithStatusBarTime:
            return ("Ngày đọc từ ảnh, giờ lấy từ đồng hồ thanh trạng thái của ảnh chụp", "clock.badge.checkmark")
        case .dateOnly:
            return ("Chỉ đọc được ngày từ ảnh — kiểm tra lại giờ", "clock")
        case .screenshotTime:
            return ("Ảnh không ghi ngày — dùng giờ chụp màn hình làm mặc định", "camera")
        case .unknown, nil:
            return ("Không đọc được thời điểm từ ảnh — mặc định theo giờ tạo bản ghi, hãy sửa nếu cần", "exclamationmark.clock")
        }
    }

    private func loadState() {
        guard !loaded else { return }
        loaded = true
        let parsed = pending.parsed
        if let amount = parsed?.amount {
            amountText = CurrencyFormatter.groupDigits(String(amount))
        }
        note = parsed?.note ?? ""
        direction = parsed?.direction ?? .expense
        bankName = parsed?.bankName ?? ""
        contactName = parsed?.contactName ?? ""
        occurredAt = parsed?.occurredAt ?? pending.createdAt
        // Gợi ý category theo tên
        if let suggested = parsed?.suggestedCategoryName {
            selectedCategory = categories.first { $0.name == suggested }
        }
    }

    // MARK: - Actions

    /// Ép chạy AI on-device bóc tách lại TOÀN BỘ — đè các giá trị hiện tại
    /// (user chủ động yêu cầu nên tin kết quả AI hơn regex).
    private func runAIParse() {
        guard !aiRunning, let ai = TransactionParserAI() else { return }
        aiRunning = true
        aiResultMessage = nil

        let lines = pending.ocrRawText.components(separatedBy: "\n")
        Task { @MainActor in
            guard let result = await ai.parse(lines: lines) else {
                aiRunning = false
                aiSucceeded = false
                aiResultMessage = "AI không trả được kết quả — giữ nguyên giá trị hiện tại."
                return
            }

            // User chủ động ép chạy → AI đè toàn bộ field có giá trị,
            // NGOẠI TRỪ ghi chú — user tự viết.
            var filledCount = 0
            if let amount = result.amount {
                amountText = CurrencyFormatter.groupDigits(String(amount))
                filledCount += 1
            }
            if let aiBank = result.bankName, !aiBank.isEmpty {
                bankName = aiBank
                filledCount += 1
            }
            if let aiContact = result.counterpartName, !aiContact.isEmpty {
                contactName = aiContact
                filledCount += 1
            }
            direction = result.isIncome ? .income : .expense
            if let iso = result.occurredAtISO, let date = TransactionParserAI.parseISO(iso) {
                occurredAt = date
                filledCount += 1
            }
            // Gợi ý category theo AI
            if let cat = result.category,
               let match = categories.first(where: { $0.name.localizedCaseInsensitiveCompare(cat) == .orderedSame }) {
                selectedCategory = match
            }

            aiRunning = false
            aiSucceeded = true
            aiResultMessage = filledCount > 0
                ? "AI đã điền \(filledCount) ô (độ tin cậy \(Int(result.confidence * 100))%). Kiểm tra lại trước khi xác nhận."
                : "AI không tìm được thông tin từ ảnh này."
        }
    }

    private func resolveAsTransaction() {
        guard let amount = Int(amountText.filter(\.isNumber)), amount > 0 else { return }
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
            occurredAt: occurredAt,
            note: note,
            bankName: bankName.isEmpty ? nil : bankName,
            source: pending.source,
            imagePath: pending.imagePath,
            dedupKey: Transaction.dedupKey(
                bankName: bankName.isEmpty ? nil : bankName,
                amount: amount,
                occurredAt: occurredAt,
                note: note
            )
        )
        tx.category = selectedCategory
        context.insert(tx)
        pending.resolvedAt = Date()
        pending.resolvedTransaction = tx
        try? context.save()
        dismiss()
    }

    private func resolveAsIgnored() {
        pending.resolvedAt = Date()
        try? context.save()
        dismiss()
    }
}

/// Xem ảnh full-screen.
struct ImageViewer: View {
    let imagePath: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let image = ImageStore.shared?.loadImage(path: imagePath) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Text("Không tải được ảnh")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ảnh gốc")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }
}
