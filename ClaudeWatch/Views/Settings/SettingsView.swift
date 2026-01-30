import SwiftUI
import SwiftData

struct SettingsView: View {
    let pollingService: PollingService
    @AppStorage("pollingInterval") private var pollingInterval = AppConstants.defaultPollingIntervalMinutes
    @Environment(\.modelContext) private var modelContext
    @State private var showResetConfirmation = false
    @State private var resetComplete = false

    var body: some View {
        Form {
            Section("Polling") {
                Stepper("Interval: \(pollingInterval) min", value: $pollingInterval, in: 1...60)
                Text("How often to refresh usage data from local Claude logs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Data") {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Reset Database")
                        Text("Clear all cached usage data. Fresh data will be fetched on next poll.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reset...", role: .destructive) {
                        showResetConfirmation = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 280)
        .onChange(of: pollingInterval) { _, newValue in
            pollingService.updateInterval(newValue)
        }
        .confirmationDialog(
            "Reset Database?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                resetDatabase()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all cached usage data. The app will fetch fresh data on the next poll.")
        }
        .alert("Database Reset", isPresented: $resetComplete) {
            Button("OK") {
                Task {
                    await pollingService.pollNow()
                }
            }
        } message: {
            Text("All data has been cleared. Fetching fresh data now.")
        }
    }

    private func resetDatabase() {
        do {
            try modelContext.delete(model: SessionUsage.self)
            try modelContext.delete(model: ModelUsage.self)
            try modelContext.delete(model: DailyUsage.self)
            try modelContext.save()
            resetComplete = true
        } catch {
            print("Failed to reset database: \(error)")
        }
    }
}
