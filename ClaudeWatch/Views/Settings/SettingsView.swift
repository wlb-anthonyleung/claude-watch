import SwiftUI

struct SettingsView: View {
    let pollingService: PollingService
    @AppStorage("npxPath") private var npxPath = AppConstants.defaultNpxPath
    @AppStorage("pollingInterval") private var pollingInterval = AppConstants.defaultPollingIntervalMinutes

    var body: some View {
        Form {
            Section("Polling") {
                Stepper("Interval: \(pollingInterval) min", value: $pollingInterval, in: 1...60)
            }
            Section("Advanced") {
                TextField("npx path", text: $npxPath)
                    .textFieldStyle(.roundedBorder)
                Text("Path to the npx binary. Typically /opt/homebrew/bin/npx or /usr/local/bin/npx.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 200)
        .onChange(of: pollingInterval) { _, newValue in
            pollingService.updateInterval(newValue)
        }
        .onChange(of: npxPath) { _, newValue in
            pollingService.updateNpxPath(newValue)
        }
    }
}
