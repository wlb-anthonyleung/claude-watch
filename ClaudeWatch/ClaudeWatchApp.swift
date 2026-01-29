import SwiftUI
import SwiftData

@main
struct ClaudeWatchApp: App {
    let modelContainer: ModelContainer
    let pollingService: PollingService
    let ccUsageService: CCUsageService

    init() {
        let container = try! ModelContainer(
            for: DailyUsage.self, ModelUsage.self, SessionUsage.self
        )
        self.modelContainer = container

        let ccService = CCUsageService()
        self.ccUsageService = ccService

        let polling = PollingService(
            ccUsageService: ccService,
            modelContainer: container
        )
        self.pollingService = polling

        // Start polling on app launch
        Task { @MainActor in
            polling.startPolling()
        }
    }

    var body: some Scene {
        MenuBarExtra("Claude Watch", systemImage: "chart.bar.fill") {
            MenuBarPopoverView(pollingService: pollingService)
                .modelContainer(modelContainer)
        }
        .menuBarExtraStyle(.window)

        Window("Claude Watch", id: AppConstants.detailWindowID) {
            DetailWindowView(pollingService: pollingService, ccUsageService: ccUsageService)
                .modelContainer(modelContainer)
                .frame(minWidth: 700, minHeight: 500)
        }
        .defaultSize(width: 900, height: 650)

        Settings {
            SettingsView(pollingService: pollingService)
        }
    }
}
