import SwiftUI
import SwiftData
import UserNotifications

@main
struct QuanLyChiTieuApp: App {
    @Environment(\.scenePhase) private var scenePhase

    private let services: AppServices

    init() {
        NotificationScheduler.requestAuthorization()

        guard let container = try? ModelContainer(
            for: Transaction.self, SpendingCategory.self, MonthlyBudget.self,
            PendingExtraction.self, DayReviewState.self
        ) else {
            fatalError("Không tạo được ModelContainer")
        }
        services = AppServices(container: container)

        // Seed categories mặc định (idempotent)
        CategorySeeder.seedIfNeeded(context: ModelContext(container))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(services)
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
