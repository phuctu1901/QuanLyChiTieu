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
    @State private var bankName: String = ""
    @State private var occurredAt: Date = Date()
    @State private var selectedCategory: SpendingCategory?
    @State private var showImage = false
    @State private var loaded = false

    var body: some View {
        Form {
            imageSection
            amountSection
            noteSection
            categorySection
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
                    .disabled(Int(amountText.filter(\.isNumber)) ?? 0 <= 0)
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

    private var amountSection: some View {
        Section("Số tiền") {
            HStack {
                TextField("0", text: $amountText)
                    .keyboardType(.numberPad)
                    .font(.system(size: 28, weight: .bold))
                Text("đ")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            Picker("Hướng", systemImage: "arrow.up.arrow.down", selection: $direction) {
                Text("Chi tiền").tag(Direction.expense)
                Text("Thu tiền").tag(Direction.income)
            }
            .pickerStyle(.segmented)
            DatePicker("Thời điểm", selection: $occurredAt)
            TextField("Ngân hàng", text: $bankName)
        }
    }

    private var noteSection: some View {
        Section("Ghi chú") {
            TextField("Nội dung giao dịch", text: $note, axis: .vertical)
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

    private func loadState() {
        guard !loaded else { return }
        loaded = true
        let parsed = pending.parsed
        if let amount = parsed?.amount {
            amountText = String(amount)
        }
        note = parsed?.note ?? ""
        direction = parsed?.direction ?? .expense
        bankName = parsed?.bankName ?? ""
        occurredAt = parsed?.occurredAt ?? pending.createdAt
        // Gợi ý category theo tên
        if let suggested = parsed?.suggestedCategoryName {
            selectedCategory = categories.first { $0.name == suggested }
        }
    }

    // MARK: - Actions

    private func resolveAsTransaction() {
        guard let amount = Int(amountText.filter(\.isNumber)), amount > 0 else { return }
        let tx = Transaction(
            amount: amount,
            direction: direction,
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
