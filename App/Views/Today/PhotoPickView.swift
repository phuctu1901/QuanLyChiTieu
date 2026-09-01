import SwiftUI
import Photos

/// Màn chọn ảnh screenshot từ thư viện: lưới thumbnail, auto-tick ảnh chưa nhập,
/// tick/bỏ tick thủ công, nút "Nhập N ảnh" chạy pipeline.
struct PhotoPickView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var assets: [PHAsset] = []
    @State private var selected: Set<String> = []
    @State private var thumbnails: [String: UIImage] = [:]
    @State private var authStatus: PhotoAuthStatus = .notDetermined
    @State private var loading = true
    @State private var ingesting = false
    @State private var ingestProgress = 0
    @State private var ingestTotal = 0
    @State private var doneCount = 0

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 4)]

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
        let all = library.fetchAllScreenshots()
        assets = all

        // Auto-tick: ảnh chưa qua pipeline
        let unprocessed = services.processedStore.unprocessed(all.map(\.localIdentifier))
        selected = Set(unprocessed)

        // Load thumbnail song song (mỗi batch nhỏ để không yêu cầu API)
        loading = false
        await loadThumbnails(for: all)
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

    private var content: some View {
        List {
            if loading {
                HStack { ProgressView(); Text("Đang tải ảnh…") }
            } else if assets.isEmpty {
                Text("Không tìm thấy ảnh chụp màn hình nào trong thư viện.")
                    .foregroundStyle(.secondary)
            } else {
                infoRow
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(assets, id: \.localIdentifier) { asset in
                        cell(for: asset)
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            }
        }
    }

    private var infoRow: some View {
        HStack {
            Label("\(selected.count)/\(assets.count) ảnh được chọn", systemImage: "checkmark.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Bỏ chọn hết") { selected = [] }
                .font(.footnote)
        }
    }

    private func cell(for asset: PHAsset) -> some View {
        let id = asset.localIdentifier
        let isOn = selected.contains(id)
        return Button {
            toggle(id)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let thumb = thumbnails[id] {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle().fill(.quaternary)
                            .overlay(ProgressView())
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity)
                .frame(height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Badge đã nhập / chọn
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? .white : .secondary)
                    .shadow(radius: 2)
                    .padding(6)
            }
            .opacity(services.processedStore.isProcessed(id) && !isOn ? 0.55 : 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func toggle(_ id: String) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    private func loadThumbnails(for assets: [PHAsset]) async {
        let library = PhotoLibraryService(processedStore: services.processedStore)
        // Ưu tiên ảnh mới nhất trước
        for asset in assets {
            if let thumb = await library.loadThumbnail(for: asset, side: 240) {
                thumbnails[asset.localIdentifier] = thumb
            }
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
            for asset in picked {
                if let data = await library.loadImageData(for: asset) {
                    _ = await services.pipeline.ingest(imageData: data, source: .manualPhoto)
                    services.processedStore.markProcessed([asset.localIdentifier])
                }
                ingestProgress += 1
            }
            ingesting = false
            doneCount = picked.count
            selected = []
            await MainActor.run { dismissIfNeeded() }
        }
    }

    private func dismissIfNeeded() {
        // Đóng màn sau khi nhập xong
        dismiss()
    }
}
