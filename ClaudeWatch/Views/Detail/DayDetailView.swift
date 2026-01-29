import SwiftUI
import SwiftData

struct DayDetailView: View {
    let usage: DailyUsage
    let ccUsageService: CCUsageService

    @Environment(\.modelContext) private var modelContext
    @State private var sessions: [SessionDisplayData] = []
    @State private var hourlyData: [ConversationService.HourlyUsage] = []
    @State private var isLoadingSession = false
    @State private var isLoadingHourly = false

    private let conversationService = ConversationService()

    /// Check if this date is today (needs fresh data).
    private var isToday: Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return usage.date == formatter.string(from: Date())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                DailySummaryCard(usage: usage)
                ModelBreakdownChart(breakdowns: usage.modelBreakdowns)
                TokenCategoryChart(usage: usage)

                if isLoadingSession {
                    ProgressView("Loading session data...")
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                } else {
                    SessionBreakdownView(sessions: sessions)
                }

                if isLoadingHourly {
                    ProgressView("Loading hourly data...")
                        .frame(maxWidth: .infinity, minHeight: 150)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                } else {
                    HourlyBreakdownChart(hourlyData: hourlyData)
                }
            }
            .padding()
        }
        .task(id: usage.date) {
            await loadData()
        }
    }

    private func loadData() async {
        guard let date = dateFromString(usage.date) else { return }

        // Load session data - use cache for past days, fetch fresh for today
        isLoadingSession = true

        if !isToday && !usage.sessions.isEmpty {
            // Use cached data for past days
            sessions = usage.sessions.map { SessionDisplayData(from: $0) }
        } else {
            // Fetch fresh data for today or if no cache exists
            do {
                let response = try await ccUsageService.fetchSessions(for: date)
                sessions = response.sessions.map { SessionDisplayData(from: $0) }

                // Cache the session data (only for past days to avoid stale today data)
                if !isToday {
                    cacheSessionData(response.sessions)
                }
            } catch {
                print("Failed to load sessions: \(error)")
                // Fall back to cached data if available
                if !usage.sessions.isEmpty {
                    sessions = usage.sessions.map { SessionDisplayData(from: $0) }
                }
            }
        }
        isLoadingSession = false

        // Load hourly data (always from local files, no caching needed)
        isLoadingHourly = true
        hourlyData = await conversationService.fetchHourlyUsage(for: date)
        isLoadingHourly = false
    }

    private func cacheSessionData(_ entries: [CCSessionEntry]) {
        // Clear existing sessions for this day
        for session in usage.sessions {
            modelContext.delete(session)
        }

        // Add new sessions
        for entry in entries {
            let session = SessionUsage(
                sessionId: entry.sessionId,
                inputTokens: entry.inputTokens,
                outputTokens: entry.outputTokens,
                cacheCreationTokens: entry.cacheCreationTokens,
                cacheReadTokens: entry.cacheReadTokens,
                totalTokens: entry.totalTokens,
                totalCost: entry.totalCost,
                lastActivity: entry.lastActivity,
                modelsUsed: entry.modelsUsed,
                projectPath: entry.projectPath
            )
            usage.sessions.append(session)
        }

        try? modelContext.save()
    }

    private func dateFromString(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }
}
