import SwiftUI
import Charts

struct HourlyBreakdownChart: View {
    let hourlyData: [ConversationService.HourlyUsage]

    private var hasData: Bool {
        hourlyData.contains { $0.totalTokens > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By Hour")
                .font(.headline)

            if !hasData {
                Text("No hourly data available.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Chart(hourlyData) { entry in
                    BarMark(
                        x: .value("Hour", formatHour(entry.hour)),
                        y: .value("Tokens", entry.totalTokens)
                    )
                    .foregroundStyle(.blue.gradient)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 12)) { value in
                        AxisValueLabel()
                        AxisGridLine()
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisValueLabel {
                            if let count = value.as(Int.self) {
                                Text(Formatters.formatTokenCount(count))
                            }
                        }
                        AxisGridLine()
                    }
                }
                .frame(height: 180)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func formatHour(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }
}
