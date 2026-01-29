import SwiftUI

struct DailySummaryCard: View {
    let usage: DailyUsage

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(Formatters.formatDateString(usage.date))
                    .font(.title2.weight(.medium))
                Spacer()
                Text(Formatters.formatCost(usage.totalCost))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
            }

            HStack(spacing: 24) {
                metricItem(title: "Total Tokens", value: Formatters.formatTokenCount(usage.totalTokens))
                metricItem(title: "Input", value: Formatters.formatTokenCount(usage.inputTokens))
                metricItem(title: "Output", value: Formatters.formatTokenCount(usage.outputTokens))
                metricItem(title: "Cache Create", value: Formatters.formatTokenCount(usage.cacheCreationTokens))
                metricItem(title: "Cache Read", value: Formatters.formatTokenCount(usage.cacheReadTokens))
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func metricItem(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.medium).monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
