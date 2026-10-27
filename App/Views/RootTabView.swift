import SwiftUI
import SwiftData

/// Các service dùng chung toàn app, khởi tạo 1 lần.
@MainActor @Observable
final class AppServices {
    static let shared: AppServices? = {
        guard let container = try? ModelContainer(
            for: Transaction.self, SpendingCategory.self, MonthlyBudget.self,
            PendingExtraction.self, DayReviewState.self
        ) else { return nil }
        return AppServices(container: container)
    }()

    let pipeline: ExtractionPipeline
    let shareInbox: ShareInboxService
    let photoMonitor: PhotoMonitor
    let processedStore: ProcessedAssetStore
    let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
        let imageStore = ImageStore()
        let store = PendingStore(container: container)
        let processedStore = ProcessedAssetStore()
        pipeline = ExtractionPipeline(imageStore: imageStore, persist: store.persist)
        shareInbox = ShareInboxService(pipeline: pipeline)
        photoMonitor = PhotoMonitor(pipeline: pipeline, processedStore: processedStore)
        self.processedStore = processedStore
    }

    /// Gọi khi scenePhase = .active: drain inbox từ Share Extension + catch-up photo scan
    func activate() {
        Task { await shareInbox.drainInbox() }
        photoMonitor.start()
        photoMonitor.autoScan()
    }

    func deactivate() {
        photoMonitor.stop()
    }
}

struct RootTabView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Giao dịch", systemImage: "list.bullet.rectangle.portrait") }
            StatsView()
                .tabItem { Label("Thống kê", systemImage: "chart.pie.fill") }
            BudgetView()
                .tabItem { Label("Ngân sách", systemImage: "wallet.pass") }
            SettingsView()
                .tabItem { Label("Cài đặt", systemImage: "gearshape.fill") }
        }
    }
}
