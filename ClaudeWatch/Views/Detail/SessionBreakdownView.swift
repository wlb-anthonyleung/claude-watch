import SwiftUI

/// Display data for session breakdown, convertible from both CCSessionEntry and SessionUsage.
struct SessionDisplayData: Identifiable {
    let id: String
    let displayName: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let totalTokens: Int
    let totalCost: Double
    let modelsUsed: [String]

    init(from entry: CCSessionEntry) {
        self.id = entry.sessionId
        self.displayName = entry.displayName
        self.inputTokens = entry.inputTokens
        self.outputTokens = entry.outputTokens
        self.cacheCreationTokens = entry.cacheCreationTokens
        self.cacheReadTokens = entry.cacheReadTokens
        self.totalTokens = entry.totalTokens
        self.totalCost = entry.totalCost
        self.modelsUsed = entry.modelsUsed
    }

    init(from usage: SessionUsage) {
        self.id = usage.sessionId
        self.displayName = usage.displayName
        self.inputTokens = usage.inputTokens
        self.outputTokens = usage.outputTokens
        self.cacheCreationTokens = usage.cacheCreationTokens
        self.cacheReadTokens = usage.cacheReadTokens
        self.totalTokens = usage.totalTokens
        self.totalCost = usage.totalCost
        self.modelsUsed = usage.modelsUsed
    }
}

struct SessionBreakdownView: View {
    let sessions: [SessionDisplayData]

    private var sortedSessions: [SessionDisplayData] {
        sessions.sorted { $0.totalCost > $1.totalCost }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By Session")
                .font(.headline)

            if sessions.isEmpty {
                Text("No session data available.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ForEach(sortedSessions) { session in
                    sessionRow(session)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func sessionRow(_ session: SessionDisplayData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.displayName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text(Formatters.formatCost(session.totalCost))
                    .font(.callout.monospacedDigit())
            }

            HStack(spacing: 16) {
                tokenLabel("In", count: session.inputTokens)
                tokenLabel("Out", count: session.outputTokens)
                tokenLabel("Cache", count: session.cacheCreationTokens + session.cacheReadTokens)
                Spacer()
                Text(Formatters.formatTokenCount(session.totalTokens) + " total")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if !session.modelsUsed.isEmpty {
                HStack(spacing: 4) {
                    ForEach(session.modelsUsed, id: \.self) { model in
                        Text(Formatters.formatModelName(model))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func tokenLabel(_ label: String, count: Int) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .foregroundStyle(.tertiary)
            Text(Formatters.formatTokenCount(count))
        }
    }
}
