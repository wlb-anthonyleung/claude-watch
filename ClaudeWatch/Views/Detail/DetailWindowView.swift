import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case overview
    case day(String)
}

struct DetailWindowView: View {
    let pollingService: PollingService
    let ccUsageService: CCUsageService
    @Query(sort: \DailyUsage.date, order: .reverse) private var allUsage: [DailyUsage]
    @State private var selectedItem: SidebarItem? = .overview

    var body: some View {
        NavigationSplitView {
            DayPickerView(allUsage: allUsage, selectedItem: $selectedItem)
        } detail: {
            switch selectedItem {
            case .overview:
                OverviewView(allUsage: allUsage, selectedItem: $selectedItem)
            case .day(let date):
                if let selected = allUsage.first(where: { $0.date == date }) {
                    DayDetailView(usage: selected, ccUsageService: ccUsageService)
                } else {
                    ContentUnavailableView(
                        "No Data",
                        systemImage: "calendar",
                        description: Text("No usage data for this date.")
                    )
                }
            case nil:
                ContentUnavailableView(
                    "Select a Day",
                    systemImage: "calendar",
                    description: Text("Choose a date from the sidebar to view usage details.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await pollingService.pollNow() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(pollingService.isPolling)
            }
        }
        .navigationTitle("Claude Watch")
        .onAppear {
            NSApp.setActivationPolicy(.regular)
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
