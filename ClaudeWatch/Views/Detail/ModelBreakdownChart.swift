import SwiftUI
import Charts

struct ModelBreakdownChart: View {
    let breakdowns: [ModelUsage]

    private var sortedBreakdowns: [ModelUsage] {
        breakdowns.sorted { $0.cost > $1.cost }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cost by Model")
                .font(.headline)

            if breakdowns.isEmpty {
                Text("No model data available.")
                    .foregroundStyle(.secondary)
            } else {
                Chart(sortedBreakdowns, id: \.modelName) { model in
                    BarMark(
                        x: .value("Cost", model.cost),
                        y: .value("Model", Formatters.formatModelName(model.modelName))
                    )
                    .foregroundStyle(by: .value("Model", Formatters.formatModelName(model.modelName)))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text(Formatters.formatCost(model.cost))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisValueLabel {
                            if let cost = value.as(Double.self) {
                                Text(Formatters.formatCost(cost))
                            }
                        }
                        AxisGridLine()
                    }
                }
                .chartLegend(.hidden)
                .frame(height: CGFloat(max(breakdowns.count, 1)) * 50 + 20)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
