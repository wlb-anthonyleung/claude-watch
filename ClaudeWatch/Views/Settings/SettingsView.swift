import SwiftUI

struct SettingsView: View {
    let pollingService: PollingService
    @AppStorage("pollingInterval") private var pollingInterval = AppConstants.defaultPollingIntervalMinutes

    var body: some View {
        Form {
            Section("Polling") {
                Stepper("Interval: \(pollingInterval) min", value: $pollingInterval, in: 1...60)
                Text("How often to refresh usage data from local Claude logs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 150)
        .onChange(of: pollingInterval) { _, newValue in
            pollingService.updateInterval(newValue)
        }
    }
}
