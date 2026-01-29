import SwiftUI
import Charts

struct CostHistoryChart: View {
    let allUsage: [DailyUsage]

    @State private var timeRange = 7

    private var filteredUsage: [DailyUsage] {
        let sorted = allUsage.sorted { $0.date < $1.date }
        return Array(sorted.suffix(timeRange))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cost Trend")
                    .font(.headline)
                Spacer()
                Picker("Range", selection: $timeRange) {
                    Text("7d").tag(7)
                    Text("14d").tag(14)
                    Text("30d").tag(30)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            if filteredUsage.isEmpty {
                Text("No historical data available.")
                    .foregroundStyle(.secondary)
                    .frame(height: 200)
            } else {
                Chart(filteredUsage, id: \.date) { usage in
                    LineMark(
                        x: .value("Date", usage.date),
                        y: .value("Cost", usage.totalCost)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.blue)

                    AreaMark(
                        x: .value("Date", usage.date),
                        y: .value("Cost", usage.totalCost)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.blue.opacity(0.1))

                    PointMark(
                        x: .value("Date", usage.date),
                        y: .value("Cost", usage.totalCost)
                    )
                    .foregroundStyle(.blue)
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisValueLabel {
                            if let cost = value.as(Double.self) {
                                Text(Formatters.formatCost(cost))
                            }
                        }
                        AxisGridLine()
                    }
                }
                .frame(height: 200)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
