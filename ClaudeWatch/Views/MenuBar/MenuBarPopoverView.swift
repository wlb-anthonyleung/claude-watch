import SwiftUI
import SwiftData

struct MenuBarPopoverView: View {
    let pollingService: PollingService
    @Query(sort: \DailyUsage.date, order: .reverse) private var allUsage: [DailyUsage]
    @Environment(\.openWindow) private var openWindow

    private var todayUsage: DailyUsage? {
        let today = Formatters.todayDateString()
        return allUsage.first { $0.date == today }
    }

    private var yesterdayUsage: DailyUsage? {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) else {
            return nil
        }
        let yesterdayString = Formatters.dateString(from: yesterday)
        return allUsage.first { $0.date == yesterdayString }
    }

    /// Percentage change from yesterday. Negative means spending is down.
    private var changeFromYesterday: Int? {
        guard let today = todayUsage, let yesterday = yesterdayUsage, yesterday.totalCost > 0 else {
            return nil
        }
        return Int(((today.totalCost - yesterday.totalCost) / yesterday.totalCost) * 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()

            if let usage = todayUsage {
                todaySummary(usage)
                Divider()
                modelList(usage)
            } else if pollingService.isPolling {
                ProgressView("Fetching usage data...")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                Text("No data for today yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }

            if let error = pollingService.lastError {
                Divider()
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .lineLimit(2)
            }

            Divider()
            actionButtons
        }
        .padding()
        .frame(width: 280)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Text("Claude Watch")
                .font(.headline)
            Spacer()
            if pollingService.isPolling {
                ProgressView()
                    .scaleEffect(0.6)
            }
        }
    }

    private func todaySummary(_ usage: DailyUsage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Formatters.formatDateString(usage.date))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline) {
                Text(Formatters.formatCost(usage.totalCost))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                if let change = changeFromYesterday {
                    HStack(spacing: 2) {
                        Image(systemName: change >= 0 ? "arrow.up" : "arrow.down")
                        Text("\(abs(change))%")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(change >= 0 ? .red : .green)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(Formatters.formatTokenCount(usage.totalTokens))
                        .font(.title3.weight(.medium))
                    Text("tokens")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func modelList(_ usage: DailyUsage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("By Model")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(usage.modelBreakdowns.sorted(by: { $0.cost > $1.cost }), id: \.modelName) { model in
                HStack {
                    Text(Formatters.formatModelName(model.modelName))
                        .font(.callout)
                    Spacer()
                    Text(Formatters.formatCost(model.cost))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 8) {
            if let lastPoll = pollingService.lastPollTime {
                Text("Updated \(lastPoll, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                Button {
                    Task { await pollingService.pollNow() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .disabled(pollingService.isPolling)

                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: AppConstants.detailWindowID)
                } label: {
                    Label("Details", systemImage: "chart.bar.xaxis")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)

            HStack(spacing: 8) {
                SettingsLink {
                    Label("Settings", systemImage: "gear")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
    }
}
