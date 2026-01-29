import SwiftUI
import Charts

struct TokenCategoryChart: View {
    let usage: DailyUsage

    private var categories: [(name: String, count: Int, color: Color)] {
        [
            ("Input", usage.inputTokens, .blue),
            ("Output", usage.outputTokens, .green),
            ("Cache Create", usage.cacheCreationTokens, .orange),
            ("Cache Read", usage.cacheReadTokens, .purple),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Token Breakdown")
                .font(.headline)

            Chart(categories, id: \.name) { category in
                BarMark(
                    x: .value("Tokens", category.count),
                    y: .value("Category", category.name)
                )
                .foregroundStyle(category.color)
                .annotation(position: .trailing, alignment: .leading) {
                    Text(Formatters.formatTokenCount(category.count))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisValueLabel {
                        if let count = value.as(Int.self) {
                            Text(Formatters.formatTokenCount(count))
                        }
                    }
                    AxisGridLine()
                }
            }
            .frame(height: 200)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
