import SwiftUI

struct DayPickerView: View {
    let allUsage: [DailyUsage]
    @Binding var selectedItem: SidebarItem?

    var body: some View {
        List(selection: $selectedItem) {
            Section {
                Label("Overview", systemImage: "chart.bar.xaxis")
                    .tag(SidebarItem.overview)
            }

            Section("By Day") {
                ForEach(allUsage, id: \.date) { usage in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(Formatters.formatDateString(usage.date))
                                .font(.callout)
                            Text(Formatters.formatTokenCount(usage.totalTokens) + " tokens")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Formatters.formatCost(usage.totalCost))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .tag(SidebarItem.day(usage.date))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240)
    }
}
