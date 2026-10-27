import SwiftUI
import SwiftData
import Photos
import UIKit
import FoundationModels

/// Tab "Cài đặt": giờ nhắc nhở, tự động quét ảnh, quản lý phân loại.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SpendingCategory.name) private var categories: [SpendingCategory]

    @AppStorage(AppConstants.reviewReminderTimeKey) private var reminderTime = "21:00"
    @AppStorage("autoScanEnabled") private var autoScanEnabled = true
    @AppStorage("selectedCoreMLModel") private var selectedCoreMLModel = "TransactionClassifier"

    @State private var showAddCategory = false
    @State private var newCategoryName = ""
    @State private var newCategoryIcon = "tag.fill"
    @State private var newCategoryColor = "#007AFF"
    @State private var permissionDenied = false

    // Rà quét toàn bộ
    @Environment(AppServices.self) private var services
    @State private var fullScanning = false
    @State private var fullScanSummary: PhotoMonitor.FullScanSummary?
    @State private var debugExporting = false
    @State private var cleanupResult: Int?

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
#if DEBUG
                toolsSection
#endif
                aiModelSection
                aiStatusSection
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

    @State private var showClearSuccess = false

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
            
            Button("Xoá lịch sử rà quét (Quét lại từ đầu)") {
                services.processedStore.clear()
                showClearSuccess = true
            }
            .foregroundStyle(.red)
            .alert("Thành công", isPresented: $showClearSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Đã xoá lịch sử quét. Lần bấm 'Rà quét toàn bộ' tiếp theo sẽ đọc lại tất cả ảnh từ đầu.")
            }
            
        } header: {
            Text("Thư viện ảnh")
        } footer: {
            Text("Bật để tự động nhận ảnh chụp màn hình giao dịch ngân hàng mới chụp. Rà quét toàn bộ chỉ lấy ảnh chụp màn hình có dấu hiệu giao dịch (số tiền + tên ngân hàng/chuyển khoản), bỏ qua ảnh thường. Ảnh chỉ xử lý trên máy, không gửi đi đâu.")
        }
        .onAppear { refreshPermission() }
    }

    /// Công cụ debug/dọn dẹp — tách riêng khỏi nhóm quét vì là thao tác đặc biệt.
    @State private var libraryStatsAlert: String?
    @State private var exportCount: Int?
    @State private var classifyScanning = false
    @State private var classifyResult: ClassifyScanResult?

    struct ClassifyScanResult {
        let total: Int
        let transaction: Int
        let other: Int
        let coreMLUsed: Int
        let details: String
    }

    private var aiModelSection: some View {
        Section {
            Picker("Mô hình phân loại", selection: Binding(
                get: { selectedCoreMLModel },
                set: { newValue in
                    selectedCoreMLModel = newValue
                    Task {
                        await services.pipeline.reloadModel()
                    }
                }
            )) {
                Text("ResNet (Mặc định)").tag("TransactionClassifier")
                Text("MobileNet V3 Small").tag("MobileNetV3")
            }
        } header: {
            Text("AI & Mô Hình")
        } footer: {
            Text("Chọn thuật toán nhận diện biên lai. Thay đổi sẽ có tác dụng ở lần quét tiếp theo.")
        }
    }

    private var toolsSection: some View {
        Section {
            // 1. Rà quét & phân loại
            Button {
                startClassifyScan()
            } label: {
                Label(
                    classifyScanning ? "Đang rà quét…" : "Rà quét & phân loại toàn bộ ảnh",
                    systemImage: "eye.trianglebadge.exclamationmark"
                )
            }
            .disabled(classifyScanning)
            if classifyScanning {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            if let r = classifyResult {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("Tổng: \(r.total)", systemImage: "photo.stack")
                        Spacer()
                        Text("Core ML: \(r.coreMLUsed)")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    .font(.footnote)
                    HStack(spacing: 16) {
                        Label("✅ Giao dịch: \(r.transaction)", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                        Label("❌ Khác: \(r.other)", systemImage: "xmark.circle")
                            .foregroundStyle(.orange)
                    }
                    .font(.footnote)
                    if !r.details.isEmpty {
                        Text(r.details)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                // Nén & AirDrop kết quả phân loại
                Button {
                    shareClassifyZip()
                } label: {
                    Label("Nén & Chia sẻ qua AirDrop", systemImage: "square.and.arrow.up")
                }
            }

            Divider()

            // 2. Xuất ảnh debug
            Button {
                startDebugExport()
            } label: {
                Label(
                    debugExporting ? "Đang xuất toàn bộ ảnh…" : "Xuất toàn bộ screenshot + ảnh banking",
                    systemImage: "ladybug"
                )
            }
            .disabled(debugExporting)
            if let count = exportCount {
                Text("✅ Đã xuất \(count) ảnh → Documents/DebugOCR")
                    .font(.footnote)
                    .foregroundStyle(.green)

                // Nén & Share
                Button {
                    shareExportZip()
                } label: {
                    Label("Nén & Chia sẻ qua AirDrop", systemImage: "square.and.arrow.up")
                }
            }

            Divider()

            // 3. Dọn ảnh rác
            Button(role: .destructive) {
                cleanupResult = PendingCleanup.removeUnrelatedUnresolved(context: context)
            } label: {
                Label("Dọn ảnh rác đã nhập (bản cũ)", systemImage: "trash")
            }
            if let cleanupResult {
                Text("Đã xoá \(cleanupResult) ảnh rác khỏi danh sách chờ.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Divider()

            // 4. Dump metadata ảnh (debug)
            Button {
                dumpPhotoMetadata()
            } label: {
                Label("Dump metadata ảnh", systemImage: "doc.text.magnifyingglass")
            }
            
            Divider()

            // 5. Đếm tổng ảnh trong thư viện (debug)
            Button {
                countAllPhotos()
            } label: {
                Label("Đếm tổng số ảnh toàn thư viện", systemImage: "number.circle")
            }
        } header: {
            Text("Công cụ")
        } footer: {
            Text("Rà quét: chạy Core ML + keyword classifier trên toàn bộ screenshot để kiểm tra model. Xuất ảnh: lưu ảnh + OCR ra Documents/DebugOCR.")
        }
        .alert("Thống kê Thư viện ảnh", isPresented: Binding(
            get: { libraryStatsAlert != nil },
            set: { if !$0 { libraryStatsAlert = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            if let msg = libraryStatsAlert {
                Text(msg)
            }
        }
    }

    /// Đếm tổng số ảnh trong thư viện phân chia theo Subtype.
    private func countAllPhotos() {
        Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.includeHiddenAssets = false
            let allAssets = PHAsset.fetchAssets(with: .image, options: options)

            var subtypeCounts: [UInt: Int] = [:]
            allAssets.enumerateObjects { asset, _, _ in
                let subtype = asset.mediaSubtypes.rawValue
                subtypeCounts[subtype, default: 0] += 1
            }

            let sorted = subtypeCounts.sorted { $0.value > $1.value }
            var msg = "Tổng số ảnh trong máy: \(allAssets.count)\n\nPhân bổ theo loại:\n"
            for (subtype, count) in sorted {
                let name: String
                switch subtype {
                case 0: name = "Ảnh thường / Lưu từ app"
                case 4: name = "Screenshot (chụp màn hình)"
                case 8: name = "HDR"
                case 512: name = "Live Photo"
                case 516: name = "Live Photo + Screenshot"
                case 520: name = "Live Photo + HDR"
                default: name = "Loại khác (\(subtype))"
                }
                msg += "- \(name): \(count) ảnh\n"
            }

            msg += "\nApp chỉ lấy \"Screenshot\" và \"Lưu từ app\" (nếu mới chụp/lưu)."

            await MainActor.run {
                self.libraryStatsAlert = msg
            }
        }
    }

    /// Rà quét toàn bộ screenshot → phân loại bằng Core ML + keyword.
    /// Hiển thị kết quả chi tiết để debug model accuracy.
    private func startClassifyScan() {
        guard !classifyScanning else { return }
        classifyScanning = true
        classifyResult = nil
        Task.detached(priority: .userInitiated) {
            let result = await Self.runClassifyScan()
            await MainActor.run {
                classifyResult = result
                classifyScanning = false
            }
        }
    }

    private nonisolated static func runClassifyScan() async -> ClassifyScanResult {
        let fm = FileManager.default
        let docsDir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputDir = docsDir.appendingPathComponent("ClassifyOutput", isDirectory: true)
        let transDir = outputDir.appendingPathComponent("transaction", isDirectory: true)
        let otherDir = outputDir.appendingPathComponent("other", isDirectory: true)

        // Reset output
        try? fm.removeItem(at: outputDir)
        try? fm.createDirectory(at: transDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: otherDir, withIntermediateDirectories: true)

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        var assets: [PHAsset] = []
        PHAsset.fetchAssets(with: .image, options: options).enumerateObjects { asset, _, _ in
            let subtype = asset.mediaSubtypes.rawValue
            if subtype == PHAssetMediaSubtype.photoScreenshot.rawValue || subtype == 0 {
                assets.append(asset)
            }
        }

        let manager = PHImageManager.default()
        let coreML = CoreMLClassifier()
        let ocr = OCRService()
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyyMMdd_HHmmss"

        var transCount = 0
        var otherCount = 0
        var coreMLUsed = 0
        var highConfTrans: [String] = []
        var lowConfItems: [String] = []

        for (index, asset) in assets.enumerated() {
            guard let data = await PhotoMonitor.loadData(for: asset, manager: manager) else { continue }

            var isTransaction = false
            var usedCoreML = false
            var confidence: Float = 0

            // Tầng 0: Core ML
            if let ml = coreML, let result = ml.classify(imageData: data) {
                confidence = result.confidence
                if result.confidence >= CoreMLClassifier.threshold {
                    isTransaction = result.isTransaction
                    usedCoreML = true

                    let dateStr = asset.creationDate.map { dateFmt.string(from: $0) } ?? "?"
                    if result.isTransaction && result.confidence > 0.9 {
                        highConfTrans.append("\(dateStr) (\(Int(result.confidence * 100))%)")
                    }
                    if result.confidence < 0.85 {
                        let label = result.isTransaction ? "GD" : "khác"
                        lowConfItems.append("\(dateStr): \(label) \(Int(result.confidence * 100))%")
                    }
                }
            }

            // Tầng 1: Keyword fallback
            if !usedCoreML {
                if let lines = try? await ocr.recognizeLines(imageData: data) {
                    isTransaction = ImageClassifier.classify(lines: lines) == .transaction
                }
            } else {
                coreMLUsed += 1
            }

            // Lưu ảnh vào thư mục tương ứng
            let dateStr = asset.creationDate.map { dateFmt.string(from: $0) } ?? "unknown"
            let confStr = String(format: "%02d", Int(confidence * 100))
            let destDir = isTransaction ? transDir : otherDir
            let fileName = "\(dateStr)_\(confStr)pct_\(String(format: "%04d", index)).jpg"
            try? data.write(to: destDir.appendingPathComponent(fileName))

            if isTransaction { transCount += 1 } else { otherCount += 1 }
        }

        // Ghi manifest
        let summary = """
        Tổng: \(assets.count)
        Giao dịch: \(transCount)
        Khác: \(otherCount)
        Core ML: \(coreMLUsed)/\(assets.count)
        """
        try? Data(summary.utf8).write(to: outputDir.appendingPathComponent("summary.txt"))

        // Build details
        var details: [String] = []
        if !lowConfItems.isEmpty {
            details.append("⚠️ Tin cậy thấp: " + lowConfItems.prefix(5).joined(separator: ", "))
        }
        if highConfTrans.count > 0 {
            details.append("🎯 GD tin cậy cao: \(highConfTrans.count) ảnh")
        }

        return ClassifyScanResult(
            total: assets.count,
            transaction: transCount,
            other: otherCount,
            coreMLUsed: coreMLUsed,
            details: details.joined(separator: "\n")
        )
    }

    /// Nén ClassifyOutput → .zip → hiện share sheet (AirDrop).
    private func shareClassifyZip() {
        let fm = FileManager.default
        let docsDir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputDir = docsDir.appendingPathComponent("ClassifyOutput", isDirectory: true)
        guard fm.fileExists(atPath: outputDir.path) else { return }

        let zipURL = docsDir.appendingPathComponent("ClassifyOutput.zip")
        try? fm.removeItem(at: zipURL)

        var error: NSError?
        let coordinator = NSFileCoordinator()
        var resultURL: URL?
        coordinator.coordinate(readingItemAt: outputDir, options: .forUploading, error: &error) { tempURL in
            try? fm.copyItem(at: tempURL, to: zipURL)
            resultURL = zipURL
        }
        guard let url = resultURL else { return }

        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = scene.windows.first?.rootViewController else { return }
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = rootVC.view
            popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
        }
        rootVC.present(activityVC, animated: true)
    }

    /// Dump toàn bộ metadata (PHAsset + PHAssetResource + raw EXIF/XMP)
    /// cho toàn bộ ảnh trong 7 ngày gần nhất → share file .txt qua AirDrop.
    private func dumpPhotoMetadata() {
        Task.detached(priority: .userInitiated) {
            var lines: [String] = ["=== PHAsset + PHAssetResource Metadata Dump (7 ngày) ===\n"]

            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!

            // Lấy TẤT CẢ ảnh trong 7 ngày (cả screenshot lẫn ảnh thường)
            let options = PHFetchOptions()
            options.predicate = NSPredicate(
                format: "creationDate >= %@",
                sevenDaysAgo as NSDate
            )
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

            var assets: [PHAsset] = []
            PHAsset.fetchAssets(with: options).enumerateObjects { a, _, _ in assets.append(a) }

            let manager = PHImageManager.default()
            let dateFmt = DateFormatter()
            dateFmt.dateFormat = "yyyy-MM-dd HH:mm:ss"

            for asset in assets {
                let isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
                let dateStr = asset.creationDate.map { dateFmt.string(from: $0) } ?? "?"

                lines.append("========================================")
                lines.append("📷 [\(isScreenshot ? "SCREENSHOT" : "SAVED/PHOTO")] \(dateStr)")
                lines.append("  localIdentifier: \(asset.localIdentifier)")
                lines.append("  mediaType: \(asset.mediaType.rawValue)")
                lines.append("  mediaSubtypes: \(asset.mediaSubtypes.rawValue)")
                lines.append("  sourceType: \(asset.sourceType.rawValue)")
                lines.append("  pixelWidth: \(asset.pixelWidth) x \(asset.pixelHeight)")
                lines.append("  isFavorite: \(asset.isFavorite)")
                lines.append("  isHidden: \(asset.isHidden)")

                // PHAssetResource — có thể có originalFilename, uniformTypeIdentifier
                let resources = PHAssetResource.assetResources(for: asset)
                for (i, res) in resources.enumerated() {
                    lines.append("  --- Resource[\(i)] ---")
                    lines.append("    type: \(res.type.rawValue)")
                    lines.append("    originalFilename: \(res.originalFilename)")
                    lines.append("    uniformTypeIdentifier: \(res.uniformTypeIdentifier)")
                }

                // Đọc raw image data → EXIF + XMP
                if let data = await PhotoMonitor.loadData(for: asset, manager: manager) {
                    if let source = CGImageSourceCreateWithData(data as CFData, nil) {
                        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary? {
                            lines.append("  --- EXIF/ImageIO ---")
                            for (k, v) in props {
                                lines.append("    \(k): \(v)")
                            }
                        }
                    }
                    // Tìm XMP trong raw bytes
                    if let str = String(data: data.prefix(20000), encoding: .ascii) {
                        if let xmpStart = str.range(of: "<x:xmpmeta"),
                           let xmpEnd = str.range(of: "</x:xmpmeta>") {
                            let xmp = String(str[xmpStart.lowerBound...xmpEnd.upperBound])
                            lines.append("  --- XMP ---")
                            lines.append("  \(xmp)")
                        }
                        // Tìm strings liên quan
                        let keywords = ["VCB", "Vietcombank", "bank", "Techcom", "BIDV", "TPBank",
                                       "Momo", "com.", "Software", "Creator", "UserComment"]
                        for kw in keywords {
                            if let range = str.range(of: kw, options: .caseInsensitive) {
                                let lo = str.index(range.lowerBound, offsetBy: -30, limitedBy: str.startIndex) ?? str.startIndex
                                let hi = str.index(range.upperBound, offsetBy: 30, limitedBy: str.endIndex) ?? str.endIndex
                                lines.append("  🔍 Found '\(kw)': ...\(str[lo..<hi])...")
                            }
                        }
                    }
                }
                lines.append("")
            }

            // Ghi file
            let text = lines.joined(separator: "\n")
            let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let outputURL = docsDir.appendingPathComponent("metadata_dump.txt")
            try? Data(text.utf8).write(to: outputURL)

            // Share
            await MainActor.run {
                let activityVC = UIActivityViewController(activityItems: [outputURL], applicationActivities: nil)
                guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let rootVC = scene.windows.first?.rootViewController else { return }
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = rootVC.view
                    popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                }
                rootVC.present(activityVC, animated: true)
            }
        }
    }

    /// Xuất TOÀN BỘ screenshot + ảnh banking ra Documents/DebugOCR.
    /// Sau đó kéo về Mac: devicectl hoặc Finder → copy vào test-image.
    private func startDebugExport() {
        guard !debugExporting else { return }
        debugExporting = true
        exportCount = nil
        Task.detached(priority: .userInitiated) {
            let count = await DebugExportService.exportAllScreenshots()
            await MainActor.run {
                exportCount = count
                debugExporting = false
            }
        }
    }

    /// Nén DebugOCR → .zip → hiện share sheet (AirDrop).
    private func shareExportZip() {
        guard let zipURL = DebugExportService.zipExportFolder() else { return }
        let activityVC = UIActivityViewController(
            activityItems: [zipURL],
            applicationActivities: nil
        )
        // Present share sheet
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = scene.windows.first?.rootViewController else { return }
        // iPad popover
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = rootVC.view
            popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
        }
        rootVC.present(activityVC, animated: true)
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
        Section {
            LabeledContent("Phiên bản", value: versionString)
            LabeledContent("Quyền riêng tư", value: "Xử lý hoàn toàn trên thiết bị")
        } header: {
            Text("Về app")
        }
    }

    private var aiStatusSection: some View {
        Section {
            // Tình trạng chung
            HStack {
                Image(systemName: TransactionParserAI.isAvailable
                      ? "brain.head.profile.fill" : "brain.head.profile")
                    .foregroundStyle(TransactionParserAI.isAvailable ? .green : .orange)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Foundation Models")
                        .font(.headline)
                    Text(TransactionParserAI.availabilityDescription)
                        .font(.subheadline)
                        .foregroundStyle(TransactionParserAI.isAvailable ? .green : .secondary)
                }
            }

            // Core ML model
            LabeledContent {
                statusBadge(CoreMLClassifier() != nil)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Core ML lọc ảnh")
                    Text("Model train sẵn — không cần Apple Intelligence")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Chi tiết từng tầng
            LabeledContent {
                statusBadge(TransactionParserAI.isAvailable)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text("AI bóc tách giao dịch")
                    Text("Số tiền, ngày giờ, ngân hàng, category")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent {
                statusBadge(ImageAIClassifier.isAvailable)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text("AI lọc ảnh giao dịch")
                    Text("Nhận biết screenshot ngân hàng vs chat/quảng cáo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Ngôn ngữ hỗ trợ
            if #available(iOS 26, *) {
                let langs = SystemLanguageModel.default.supportedLanguages
                if !langs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ngôn ngữ hỗ trợ")
                            .font(.subheadline)
                        Text(langs.map { $0.maximalIdentifier }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Fallback info
            if !TransactionParserAI.isAvailable {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Đang dùng bộ lọc từ khoá + regex")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("Bật Apple Intelligence trong Cài đặt → Apple Intelligence & Siri để sử dụng AI on-device.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Trí tuệ nhân tạo")
        } footer: {
            Text("Hai tầng AI on-device (Apple Intelligence): tầng 1 nhận biết ảnh giao dịch, tầng 2 bóc tách thông tin. Dữ liệu không rời thiết bị.")
        }
    }

    @ViewBuilder
    private func statusBadge(_ isOn: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isOn ? .green : .orange)
                .frame(width: 8, height: 8)
            Text(isOn ? "Bật" : "Tắt")
                .font(.subheadline)
                .foregroundStyle(isOn ? .primary : .secondary)
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
