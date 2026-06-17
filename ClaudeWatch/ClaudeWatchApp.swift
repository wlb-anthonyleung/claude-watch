import SwiftUI
import SwiftData
import AppKit
import OSLog

private let storageLogger = Logger(subsystem: "com.claudewatch.app", category: "storage")

@main
struct ClaudeWatchApp: App {
    let modelContainer: ModelContainer
    let pollingService: PollingService
    let ccUsageService: CCUsageService

    init() {
        // Exit early if another instance already owns the store, before opening a
        // second SQLite connection that would surface as "database is locked".
        Self.enforceSingleInstance()

        let container = Self.makeContainer()
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

    // MARK: - Storage Setup

    /// Terminates this process if another instance of the app is already running.
    ///
    /// As an `LSUIElement` menu-bar agent the app can easily be launched twice (during
    /// development, or by the user). Two processes opening the same SQLite store produce
    /// "database is locked" write failures, so we bail out before creating the container.
    private static func enforceSingleInstance() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        // The current process counts as one; >1 means a sibling already holds the store.
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
            exit(0)
        }
    }

    /// Builds the SwiftData container against an app-owned store URL with graceful recovery.
    ///
    /// Failure modes (incompatible schema after a model change, a corrupt/partial store
    /// after a force-quit, an unreadable WAL/SHM sidecar) previously crashed the app at
    /// launch via `try!` — invisible for a menu-bar agent. Since every persisted value is
    /// re-derivable from `~/.claude` on the next poll, destructive recovery is safe: we
    /// delete the store and rebuild. If even that fails we fall back to an in-memory store
    /// so the app still launches and shows live data (just without cross-launch persistence).
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([DailyUsage.self, ModelUsage.self, SessionUsage.self])
        let storeURL = URL.applicationSupportDirectory
            .appending(path: "ClaudeWatch/ClaudeWatch.store")
        try? FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let config = ModelConfiguration(schema: schema, url: storeURL)

        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            storageLogger.error(
                "Store open failed: \(error.localizedDescription, privacy: .public). Rebuilding store; data re-derives from ~/.claude."
            )
            deleteStoreFiles(at: storeURL)
            do {
                return try ModelContainer(for: schema, configurations: config)
            } catch {
                storageLogger.error(
                    "Store rebuild failed: \(error.localizedDescription, privacy: .public). Falling back to in-memory store (no persistence this session)."
                )
                let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                return try! ModelContainer(for: schema, configurations: memoryConfig)
            }
        }
    }

    /// Removes the SwiftData SQLite store and its WAL/SHM sidecars.
    ///
    /// SwiftData names the sidecars by suffixing the store's *last path component*
    /// (`ClaudeWatch.store-wal`, `ClaudeWatch.store-shm`) — a hyphen suffix, not a second
    /// path extension — so they are built by string-appending, not `appendingPathExtension`.
    private static func deleteStoreFiles(at storeURL: URL) {
        let directory = storeURL.deletingLastPathComponent()
        let name = storeURL.lastPathComponent
        let fileManager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fileManager.removeItem(at: directory.appending(path: name + suffix))
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
                .modelContainer(modelContainer)
        }
    }
}
