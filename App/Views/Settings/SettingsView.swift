import SwiftUI
import SwiftData
import Photos
import UIKit

/// Tab "Cài đặt": giờ nhắc nhở, tự động quét ảnh, quản lý phân loại.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SpendingCategory.name) private var categories: [SpendingCategory]

    @AppStorage(AppConstants.reviewReminderTimeKey) private var reminderTime = "21:00"
    @AppStorage("autoScanEnabled") private var autoScanEnabled = true

    @State private var showAddCategory = false
    @State private var newCategoryName = ""
    @State private var newCategoryIcon = "tag.fill"
    @State private var newCategoryColor = "#007AFF"
    @State private var permissionDenied = false

    private static let iconChoices: [String] = [
        "tag.fill", "fork.knife", "car.fill", "bag.fill", "doc.text.fill",
        "gamecontroller.fill", "heart.fill", "book.fill", "arrow.left.arrow.right",
        "iphone", "ellipsis.circle", "cart.fill", "airplane", "house.fill", "gift.fill",
    ]

    private var reminderDate: Date {
        let parts = reminderTime.split(separator: ":").compactMap { Int($0) }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = parts.first ?? 21
        comps.minute = parts.count > 1 ? parts[1] : 0
        return Calendar.current.date(from: comps) ?? Date()
    }

    private var reminderBinding: Binding<Date> {
        Binding(
            get: { reminderDate },
            set: { newValue in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                let time = String(format: "%02d:%02d", comps.hour ?? 21, comps.minute ?? 0)
                reminderTime = time
                NotificationScheduler.scheduleDailyReminder(time: time)
            }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                notificationSection
                scanSection
                categorySection
                aboutSection
            }
            .navigationTitle("Cài đặt")
            .sheet(isPresented: $showAddCategory) {
                addCategorySheet
            }
        }
    }

    // MARK: - Sections

    private var notificationSection: some View {
        Section {
            DatePicker(
                "Giờ nhắc tổng kết",
                selection: reminderBinding,
                displayedComponents: .hourAndMinute
            )
        } header: {
            Text("Nhắc nhở cuối ngày")
        } footer: {
            Text("Mỗi ngày đến giờ này app sẽ nhắc bạn xác nhận giao dịch và nhập chi tiền mặt.")
        }
    }

    private var scanSection: some View {
        Section {
            Toggle("Tự động quét ảnh mới", isOn: $autoScanEnabled)
            Button("Cấp lại quyền truy cập ảnh") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            if permissionDenied {
                Label("Chưa cấp quyền — mở Cài đặt hệ thống để cấp.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Thư viện ảnh")
        } footer: {
            Text("Bật để tự động nhận ảnh chụp màn hình giao dịch ngân hàng mới chụp. Ảnh chỉ xử lý trên máy, không gửi đi đâu.")
        }
        .onAppear { refreshPermission() }
    }

    private var categorySection: some View {
        Section("Phân loại chi tiêu") {
            ForEach(categories) { cat in
                HStack {
                    CategoryIconView(category: cat)
                    Text(cat.name)
                    if cat.isDefault {
                        Spacer()
                        Text("Mặc định")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    context.delete(categories[index])
                }
                try? context.save()
            }
            Button {
                showAddCategory = true
            } label: {
                Label("Thêm phân loại", systemImage: "plus")
            }
        }
    }

    private var aboutSection: some View {
        Section("Về app") {
            LabeledContent("Phiên bản", value: versionString)
            LabeledContent("Quyền riêng tư", value: "OCR xử lý hoàn toàn trên thiết bị")
        }
    }

    private var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    // MARK: - Helpers

    private func refreshPermission() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        permissionDenied = !(status == .authorized || status == .limited)
    }

    private var addCategorySheet: some View {
        NavigationStack {
            Form {
                TextField("Tên phân loại", text: $newCategoryName)
                Section {
                    iconPicker
                    ColorPicker("Màu", selection: Binding(
                        get: { Color(hex: newCategoryColor) },
                        set: { newValue in
                            newCategoryColor = ColorHex.from(newValue)
                        }
                    ))
                } header: {
                    Text("Hiển thị")
                }
            }
            .navigationTitle("Phân loại mới")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { showAddCategory = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Thêm") { addCategory() }
                        .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var iconPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(Self.iconChoices, id: \.self) { icon in
                    Button {
                        newCategoryIcon = icon
                    } label: {
                        Image(systemName: icon)
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .background(
                                newCategoryIcon == icon ? Color.accentColor.opacity(0.2) : Color.clear,
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func addCategory() {
        let cat = SpendingCategory(
            name: newCategoryName.trimmingCharacters(in: .whitespaces),
            iconName: newCategoryIcon,
            colorHex: newCategoryColor,
            isDefault: false
        )
        context.insert(cat)
        try? context.save()
        newCategoryName = ""
        showAddCategory = false
    }
}

/// Color → "#RRGGBB" an toàn (không fail).
enum ColorHex {
    static func from(_ color: Color) -> String {
        guard let components = UIColor(color).cgColor.components, components.count >= 3 else {
            return "#007AFF"
        }
        return String(
            format: "#%02X%02X%02X",
            Int(components[0] * 255),
            Int(components[1] * 255),
            Int(components[2] * 255)
        )
    }
}
