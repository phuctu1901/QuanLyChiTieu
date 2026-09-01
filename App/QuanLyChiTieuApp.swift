import SwiftUI
import SwiftData
import UserNotifications

@main
struct QuanLyChiTieuApp: App {
    @Environment(\.scenePhase) private var scenePhase

    private let services: AppServices

    /// Tạo container với URL tường minh trong Application Support của app
    /// (tránh CoreData rơi vào App Group container bị sandbox chặn khi chưa provisioning).
    static func makeContainer() -> ModelContainer? {
        let supportURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        let storeURL = supportURL.appendingPathComponent("QuanLyChiTieu.store")

        let config = ModelConfiguration(url: storeURL)
        return try? ModelContainer(
            for: Transaction.self, SpendingCategory.self, MonthlyBudget.self,
            PendingExtraction.self, DayReviewState.self,
            configurations: config
        )
    }

    init() {
        NotificationScheduler.requestAuthorization()

        guard let container = Self.makeContainer() else {
            fatalError("Không tạo được ModelContainer")
        }
        services = AppServices(container: container)

        // Seed categories mặc định (idempotent)
        CategorySeeder.seedIfNeeded(context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(services)
                .onAppear {
                    // scenePhase có thể đã .active trước khi onChange kịp đăng ký
                    // (launch trực tiếp) → kích hoạt lần đầu tại đây.
                    services.activate()
                }
        }
        .modelContainer(services.container)
        .onChange(of: scenePhase) { _, phase in
            MainActor.assumeIsolated {
                switch phase {
                case .active:
                    services.activate()
                case .background:
                    services.deactivate()
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
        }
    }
}
