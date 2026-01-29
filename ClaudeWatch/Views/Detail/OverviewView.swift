import SwiftUI
import Charts

struct OverviewView: View {
    let allUsage: [DailyUsage]
    @Binding var selectedItem: SidebarItem?
    @State private var isStacked = true
    @State private var selectedMonth: String
    @State private var hoveredDate: String?

    init(allUsage: [DailyUsage], selectedItem: Binding<SidebarItem?>) {
        self.allUsage = allUsage
        self._selectedItem = selectedItem
        // Default to current month (yyyy-MM)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        self._selectedMonth = State(initialValue: formatter.string(from: Date()))
    }

    /// All distinct months (yyyy-MM) available in the data, sorted descending.
    private var availableMonths: [String] {
        let months = Set(allUsage.map { String($0.date.prefix(7)) })
        return months.sorted(by: >)
    }

    /// Usage entries filtered to the selected month.
    private var monthUsage: [DailyUsage] {
        allUsage
            .filter { $0.date.hasPrefix(selectedMonth) }
            .sorted { $0.date < $1.date }
    }

    private var chartData: [ModelDayEntry] {
        monthUsage.flatMap { day in
            if day.modelBreakdowns.isEmpty {
                return [ModelDayEntry(
                    date: day.date,
                    model: "Unknown",
                    cost: day.totalCost,
                    totalTokens: day.totalTokens
                )]
            }
            return day.modelBreakdowns.map { breakdown in
                let tokens = breakdown.inputTokens + breakdown.outputTokens
                    + breakdown.cacheCreationTokens + breakdown.cacheReadTokens
                return ModelDayEntry(
                    date: day.date,
                    model: Formatters.formatModelName(breakdown.modelName),
                    cost: breakdown.cost,
                    totalTokens: tokens
                )
            }
        }
    }

    private var totalCost: Double {
        monthUsage.reduce(0) { $0 + $1.totalCost }
    }

    private var totalTokens: Int {
        monthUsage.reduce(0) { $0 + $1.totalTokens }
    }

    private var avgDailyCost: Double {
        monthUsage.isEmpty ? 0 : totalCost / Double(monthUsage.count)
    }

    /// Last 14 days of usage for the trendline, sorted chronologically.
    private var last14DaysUsage: [DailyUsage] {
        let sorted = allUsage.sorted { $0.date < $1.date }
        return Array(sorted.suffix(14))
    }

    /// 3-day moving average data points.
    private var movingAverageData: [MovingAveragePoint] {
        let window = 3
        guard last14DaysUsage.count >= window else { return [] }

        var result: [MovingAveragePoint] = []
        for i in (window - 1)..<last14DaysUsage.count {
            let slice = last14DaysUsage[(i - window + 1)...i]
            let avg = slice.reduce(0.0) { $0 + $1.totalCost } / Double(window)
            result.append(MovingAveragePoint(date: last14DaysUsage[i].date, average: avg))
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                trendlineChart
                monthPicker
                summaryRow
                costChart
                usageTable
            }
            .padding()
        }
    }

    // MARK: - Month Picker

    private var monthPicker: some View {
        HStack {
            Button {
                navigateMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(previousMonth == nil)

            Spacer()

            Text(Formatters.formatMonthLabel(selectedMonth))
                .font(.title2.weight(.medium))

            Spacer()

            Button {
                navigateMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(nextMonth == nil)
        }
        .padding(.horizontal, 4)
    }

    private var previousMonth: String? {
        guard let idx = availableMonths.firstIndex(of: selectedMonth),
              idx + 1 < availableMonths.count else { return nil }
        return availableMonths[idx + 1]
    }

    private var nextMonth: String? {
        guard let idx = availableMonths.firstIndex(of: selectedMonth),
              idx > 0 else { return nil }
        return availableMonths[idx - 1]
    }

    private func navigateMonth(by offset: Int) {
        if offset < 0, let prev = previousMonth {
            selectedMonth = prev
        } else if offset > 0, let next = nextMonth {
            selectedMonth = next
        }
    }

    // MARK: - Summary

    private var summaryRow: some View {
        HStack(spacing: 24) {
            summaryItem(title: "Total Cost", value: Formatters.formatCost(totalCost))
            summaryItem(title: "Avg / Day", value: Formatters.formatCost(avgDailyCost))
            summaryItem(title: "Total Tokens", value: Formatters.formatTokenCount(totalTokens))
            summaryItem(title: "Days Tracked", value: "\(monthUsage.count)")
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func summaryItem(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.medium).monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Trendline

    private var trendlineChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("14-Day Trend")
                    .font(.headline)
                Spacer()
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.blue)
                            .frame(width: 8, height: 8)
                        Text("Daily")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(.orange)
                            .frame(width: 16, height: 2)
                        Text("3-Day Avg")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if last14DaysUsage.isEmpty {
                Text("No data available.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart {
                    // Daily cost line
                    ForEach(last14DaysUsage, id: \.date) { day in
                        LineMark(
                            x: .value("Date", day.date),
                            y: .value("Cost", day.totalCost)
                        )
                        .foregroundStyle(.blue.opacity(0.6))
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Date", day.date),
                            y: .value("Cost", day.totalCost)
                        )
                        .foregroundStyle(.blue.opacity(0.1))
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Date", day.date),
                            y: .value("Cost", day.totalCost)
                        )
                        .foregroundStyle(.blue)
                        .symbolSize(30)
                    }

                    // 3-day moving average
                    ForEach(movingAverageData) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("3-Day Avg", point.average),
                            series: .value("Series", "Moving Average")
                        )
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 7)) { value in
                        AxisValueLabel {
                            if let dateStr = value.as(String.self) {
                                Text(Formatters.ddmmDateLabel(dateStr))
                            }
                        }
                        AxisGridLine()
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisValueLabel {
                            if let cost = value.as(Double.self) {
                                Text(Formatters.formatCost(cost))
                            }
                        }
                        AxisGridLine()
                    }
                }
                .frame(height: 150)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Chart

    private var costChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Daily Cost")
                    .font(.headline)
                Spacer()
                Picker("", selection: $isStacked) {
                    Text("Stacked").tag(true)
                    Text("Grouped").tag(false)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            if monthUsage.isEmpty {
                Text("No data for this month.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart(chartData) { entry in
                    if isStacked {
                        BarMark(
                            x: .value("Date", entry.date),
                            y: .value("Cost", entry.cost)
                        )
                        .foregroundStyle(by: .value("Model", entry.model))
                        .opacity(hoveredDate == nil || hoveredDate == entry.date ? 1 : 0.4)
                    } else {
                        BarMark(
                            x: .value("Date", entry.date),
                            y: .value("Cost", entry.cost)
                        )
                        .foregroundStyle(by: .value("Model", entry.model))
                        .position(by: .value("Model", entry.model))
                        .opacity(hoveredDate == nil || hoveredDate == entry.date ? 1 : 0.4)
                    }

                    if let hovered = hoveredDate, hovered == entry.date {
                        RuleMark(x: .value("Date", entry.date))
                            .foregroundStyle(.gray.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .top, alignment: .center, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                tooltipView(for: hovered)
                            }
                    }
                }
                .chartLegend(position: .top, alignment: .leading)
                .chartXSelection(value: $hoveredDate)
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let dateStr = value.as(String.self) {
                                Text(Formatters.ddmmDateLabel(dateStr))
                            }
                        }
                        AxisGridLine()
                    }
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
                .frame(height: 350)
                .onTapGesture {
                    if let date = hoveredDate {
                        selectedItem = .day(date)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Usage Table

    private var usageTable: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Breakdown")
                .font(.headline)

            if monthUsage.isEmpty {
                Text("No data for this month.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                // Table header
                HStack(spacing: 0) {
                    Text("Date")
                        .frame(width: 90, alignment: .leading)
                    Text("Models")
                        .frame(width: 120, alignment: .leading)
                    Text("Input")
                        .frame(width: 70, alignment: .trailing)
                    Text("Output")
                        .frame(width: 70, alignment: .trailing)
                    Text("Cache Create")
                        .frame(width: 90, alignment: .trailing)
                    Text("Cache Read")
                        .frame(width: 90, alignment: .trailing)
                    Text("Total Tokens")
                        .frame(width: 90, alignment: .trailing)
                    Text("Cost (USD)")
                        .frame(width: 80, alignment: .trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

                Divider()

                // Table rows (sorted by date ascending)
                ForEach(monthUsage, id: \.date) { day in
                    Button {
                        selectedItem = .day(day.date)
                    } label: {
                        HStack(spacing: 0) {
                            Text(Formatters.ddmmDateLabel(day.date))
                                .frame(width: 90, alignment: .leading)
                            Text(modelsString(for: day))
                                .frame(width: 120, alignment: .leading)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(Formatters.formatCompactNumber(day.inputTokens))
                                .frame(width: 70, alignment: .trailing)
                            Text(Formatters.formatCompactNumber(day.outputTokens))
                                .frame(width: 70, alignment: .trailing)
                            Text(Formatters.formatCompactNumber(day.cacheCreationTokens))
                                .frame(width: 90, alignment: .trailing)
                            Text(Formatters.formatCompactNumber(day.cacheReadTokens))
                                .frame(width: 90, alignment: .trailing)
                            Text(Formatters.formatCompactNumber(day.totalTokens))
                                .frame(width: 90, alignment: .trailing)
                            Text(Formatters.formatCost(day.totalCost))
                                .frame(width: 80, alignment: .trailing)
                        }
                        .font(.caption.monospacedDigit())
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.primary.opacity(0.001)) // For tap area
                    }
                    .buttonStyle(.plain)

                    if day.date != monthUsage.last?.date {
                        Divider()
                    }
                }

                // Total row
                Divider()
                HStack(spacing: 0) {
                    Text("Total")
                        .frame(width: 90, alignment: .leading)
                    Text("")
                        .frame(width: 120, alignment: .leading)
                    Text(Formatters.formatCompactNumber(monthUsage.reduce(0) { $0 + $1.inputTokens }))
                        .frame(width: 70, alignment: .trailing)
                    Text(Formatters.formatCompactNumber(monthUsage.reduce(0) { $0 + $1.outputTokens }))
                        .frame(width: 70, alignment: .trailing)
                    Text(Formatters.formatCompactNumber(monthUsage.reduce(0) { $0 + $1.cacheCreationTokens }))
                        .frame(width: 90, alignment: .trailing)
                    Text(Formatters.formatCompactNumber(monthUsage.reduce(0) { $0 + $1.cacheReadTokens }))
                        .frame(width: 90, alignment: .trailing)
                    Text(Formatters.formatCompactNumber(totalTokens))
                        .frame(width: 90, alignment: .trailing)
                    Text(Formatters.formatCost(totalCost))
                        .frame(width: 80, alignment: .trailing)
                        .foregroundStyle(.green)
                }
                .font(.caption.weight(.semibold).monospacedDigit())
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func modelsString(for day: DailyUsage) -> String {
        let models = day.modelBreakdowns.map { Formatters.formatModelName($0.modelName) }
        return models.isEmpty ? "Unknown" : models.joined(separator: ", ")
    }

    @ViewBuilder
    private func tooltipView(for date: String) -> some View {
        let entries = chartData.filter { $0.date == date }
        let dayCost = entries.reduce(0) { $0 + $1.cost }

        VStack(alignment: .leading, spacing: 4) {
            Text(Formatters.formatDateString(date))
                .font(.caption.weight(.semibold))

            ForEach(entries.sorted(by: { $0.cost > $1.cost })) { entry in
                HStack(spacing: 4) {
                    Text(entry.model)
                    Spacer()
                    Text(Formatters.formatTokenCount(entry.totalTokens))
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(Formatters.formatCost(entry.cost))
                }
                .font(.caption2.monospacedDigit())
            }

            Divider()

            HStack {
                Text("Total")
                    .font(.caption2.weight(.medium))
                Spacer()
                Text(Formatters.formatCost(dayCost))
                    .font(.caption2.weight(.medium).monospacedDigit())
            }
        }
        .padding(8)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 8))
        .frame(width: 200)
    }
}

struct ModelDayEntry: Identifiable {
    let id = UUID()
    let date: String
    let model: String
    let cost: Double
    let totalTokens: Int
}

struct MovingAveragePoint: Identifiable {
    let id = UUID()
    let date: String
    let average: Double
}
