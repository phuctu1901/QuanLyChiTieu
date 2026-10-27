import SwiftUI
import Photos

/// Màn chọn ảnh screenshot từ thư viện: lưới thumbnail, auto-tick ảnh chưa nhập,
/// tick/bỏ tick thủ công, nút "Nhập N ảnh" chạy pipeline.
///
/// Hiệu năng (đối chiếu YPImagePicker / TLPhotoPicker / Apple sample):
/// - `PHCachingImageManager` prefetch theo scroll
/// - `ScrollView + LazyVGrid` (không phải List + LazyVGrid — tránh double-lazy conflict)
/// - Mỗi cell load thumbnail async, cancel khi disappear
/// - `.opportunistic` delivery: degraded nhanh → final sau (không block scroll)
struct PhotoPickView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var assets: [PHAsset] = []
    @State private var selected: Set<String> = []
    @State private var authStatus: PhotoAuthStatus = .notDetermined
    @State private var loading = true
    @State private var ingesting = false
    @State private var ingestProgress = 0
    @State private var ingestTotal = 0
    @State private var doneCount = 0
    @State private var skippedCount = 0
    /// Tab đang xem: chỉ screenshot (mặc định) hay toàn bộ thư viện (chọn tay).
    @State private var showAllPhotos = false
    /// Cache toàn bộ ảnh — load 1 lần khi user sang tab "Tất cả ảnh".
    @State private var allAssets: [PHAsset] = []
    @State private var screenshotAssets: [PHAsset] = []
    @State private var loadedAllOnce = false

    /// Spacing giữa các cell — 1.5pt giống Apple Photos.
    private let gridSpacing: CGFloat = 1.5
    /// Số cột cố định — 4 cột giống Apple Photos / Immich.
    private let columnCount = 4

    var body: some View {
        NavigationStack {
            Group {
                switch authStatus {
                case .notDetermined:
                    ProgressView("Đang xin quyền truy cập ảnh…")
                case .denied:
                    deniedView
                case .limited, .authorized:
                    content
                }
            }
            .navigationTitle("Chọn ảnh giao dịch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if ingesting {
                        ProgressView(value: Double(ingestProgress), total: Double(max(ingestTotal, 1)))
                            .frame(width: 80)
                    } else if !selected.isEmpty {
                        Button("Nhập \(selected.count) ảnh") { ingestSelected() }
                            .disabled(selected.isEmpty)
                    }
                }
            }
        }
        .task { await setup() }
        .onDisappear {
            ThumbnailCacheManager.shared.resetCache()
        }
    }

    // MARK: - Setup

    private func setup() async {
        var status = PhotoLibraryService.authStatus()
        if status == .notDetermined {
            status = await PhotoLibraryService.requestAccess()
        }
        authStatus = status
        guard status == .authorized || status == .limited else {
            loading = false
            return
        }

        let library = PhotoLibraryService(processedStore: services.processedStore)
        let screenshots = library.fetchAllScreenshots()
        screenshotAssets = screenshots
        assets = screenshots

        // Không auto-tick — để user tự chọn ảnh giao dịch.
        // (Auto-tick toàn bộ unprocessed gây chọn hàng trăm ảnh rác: FB, Messenger…)
        selected = []

        loading = false

        // Prefetch batch đầu (visible + upcoming) cho scroll mượt
        let prefetchBatch = Array(screenshots.prefix(60))
        ThumbnailCacheManager.shared.startCaching(assets: prefetchBatch)
    }

    /// Chuyển tab: "Tất cả ảnh" lazy-load toàn bộ thư viện 1 lần.
    private func switchTab(_ showAll: Bool) {
        showAllPhotos = showAll
        if !showAll {
            assets = screenshotAssets
            return
        }
        guard !loadedAllOnce else {
            assets = allAssets
            return
        }
        loadedAllOnce = true
        loading = true
        Task {
            let library = PhotoLibraryService(processedStore: services.processedStore)
            let all = library.fetchAllPhotos()
            allAssets = all
            assets = all
            loading = false
            // Prefetch đầu
            let prefetchBatch = Array(all.prefix(60))
            ThumbnailCacheManager.shared.startCaching(assets: prefetchBatch)
        }
    }

    // MARK: - Views

    private var deniedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Chưa có quyền truy cập thư viện ảnh")
                .font(.headline)
            Button("Mở Cài đặt") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    /// Dùng ScrollView + LazyVGrid (KHÔNG List) — tránh double-lazy conflict gây lag.
    /// Layout kiểu Apple Photos: 4 cột, spacing 1.5pt, edge-to-edge.
    private var content: some View {
        VStack(spacing: 0) {
            pickerTabs
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            if loading {
                Spacer()
                HStack { ProgressView(); Text("Đang tải ảnh…") }
                Spacer()
            } else if assets.isEmpty {
                Spacer()
                Text(showAllPhotos
                     ? "Thư viện không có ảnh nào."
                     : "Không tìm thấy ảnh chụp màn hình nào. Ảnh chụp màn hình được nhận tự động — hoặc sang tab \"Tất cả ảnh\" để chọn tay ảnh bất kỳ.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            } else {
                infoRow
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)

                GeometryReader { geo in
                    let cellSize = (geo.size.width - gridSpacing * CGFloat(columnCount - 1)) / CGFloat(columnCount)
                    let columns = Array(repeating: GridItem(.fixed(cellSize), spacing: gridSpacing), count: columnCount)

                    ScrollView {
                        LazyVGrid(columns: columns, spacing: gridSpacing) {
                            ForEach(assets, id: \.localIdentifier) { asset in
                                ThumbnailCell(
                                    asset: asset,
                                    isSelected: selected.contains(asset.localIdentifier),
                                    isProcessed: services.processedStore.isProcessed(asset.localIdentifier),
                                    cellSize: cellSize
                                ) {
                                    toggle(asset.localIdentifier)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Tab chọn nguồn ảnh: screenshot (mặc định, auto-tick) / toàn bộ thư viện.
    private var pickerTabs: some View {
        Picker("Loại ảnh", selection: Binding(
            get: { showAllPhotos },
            set: { switchTab($0) }
        )) {
            Text("Ảnh chụp màn hình").tag(false)
            Text("Tất cả ảnh").tag(true)
        }
        .pickerStyle(.segmented)
    }

    private var infoRow: some View {
        HStack {
            Label("\(selected.count)/\(assets.count) ảnh", systemImage: "checkmark.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            if selected.isEmpty {
                Button("Chọn tất cả") {
                    selected = Set(assets.map(\.localIdentifier))
                }
                .font(.footnote)
            } else {
                Button("Bỏ chọn hết") { selected = [] }
                    .font(.footnote)
            }
        }
    }

    // MARK: - Actions

    private func toggle(_ id: String) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    private func ingestSelected() {
        let ids = selected
        let byID = Dictionary(uniqueKeysWithValues: assets.map { ($0.localIdentifier, $0) })
        let picked = ids.compactMap { byID[$0] }
        guard !picked.isEmpty else { return }

        ingesting = true
        ingestTotal = picked.count
        ingestProgress = 0
        doneCount = 0

        Task {
            let library = PhotoLibraryService(processedStore: services.processedStore)
            var skipped = 0
            for asset in picked {
                if let data = await library.loadImageData(for: asset) {
                    // Vẫn qua AI classify: ảnh thường (tab Tất cả ảnh) nhiều rác,
                    // AI lọc bớt trước khi tạo pending. Ảnh screenshot đã được auto-tick
                    // theo ProcessedAssetStore nên chủ yếu ảnh thường đi qua đây.
                    let outcome = await services.pipeline.ingest(
                        imageData: data,
                        source: .manualPhoto,
                        skipClassification: false,
                        screenshotTakenAt: asset.creationDate
                    )
                    if outcome == .notTransaction { skipped += 1 }
                    services.processedStore.markProcessed([asset.localIdentifier])
                }
                ingestProgress += 1
            }
            ingesting = false
            doneCount = picked.count - skipped
            skippedCount = skipped
            selected = []
            await MainActor.run { dismiss() }
        }
    }
}

/// Cell riêng biệt kiểu Apple Photos / Immich:
/// - Ảnh vuông, fill cắt giữa, không bo góc
/// - Badge checkmark nhỏ góc dưới phải
/// - Load async + cancel khi disappear
struct ThumbnailCell: View {
    let asset: PHAsset
    let isSelected: Bool
    let isProcessed: Bool
    let cellSize: CGFloat
    let onTap: () -> Void

    @State private var thumbnail: UIImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomTrailing) {
                // Ảnh thumbnail
                Group {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle().fill(Color(.systemGray6))
                    }
                }
                .frame(width: cellSize, height: cellSize)
                .clipped()

                // Overlay mờ khi chọn
                if isSelected {
                    Color.accentColor.opacity(0.15)
                        .frame(width: cellSize, height: cellSize)
                }

                // Badge kiểu Apple Photos
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Circle()
                            .strokeBorder(.white.opacity(0.8), lineWidth: 1.5)
                            .background(Circle().fill(.black.opacity(0.2)))
                            .frame(width: 24, height: 24)
                    }
                }
                .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                .padding(4)
            }
            .opacity(isProcessed && !isSelected ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .task(id: asset.localIdentifier) {
            loadThumbnail()
        }
        .onDisappear {
            cancelLoad()
        }
    }

    private func loadThumbnail() {
        let id = ThumbnailCacheManager.shared.loadThumbnail(for: asset) { image in
            Task { @MainActor in
                if let image {
                    thumbnail = image
                }
            }
        }
        requestID = id
    }

    private func cancelLoad() {
        if let requestID {
            ThumbnailCacheManager.shared.cancelRequest(requestID)
            self.requestID = nil
        }
    }
}
