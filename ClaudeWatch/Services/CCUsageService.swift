import Foundation

enum CCUsageError: Error, LocalizedError {
    case parsingFailure(String)

    var errorDescription: String? {
        switch self {
        case .parsingFailure(let msg): return "Parsing failed: \(msg)"
        }
    }
}

/// Service that provides Claude usage data by parsing local JSONL files.
/// Replaces the previous npx ccusage dependency with native Swift parsing.
actor CCUsageService {
    private let conversationService: ConversationService
    private let pricingService: PricingService

    init() {
        self.pricingService = PricingService()
        self.conversationService = ConversationService(pricingService: pricingService)
    }

    /// Fetches daily usage data since the given date.
    func fetchUsage(since date: Date) async throws -> CCUsageResponse {
        let dailyData = await conversationService.fetchDailyUsage(since: date)

        // Convert to CCUsageResponse format
        let daily = dailyData.map { day in
            CCDailyEntry(
                date: day.date,
                inputTokens: day.inputTokens,
                outputTokens: day.outputTokens,
                cacheCreationTokens: day.cacheCreationTokens,
                cacheReadTokens: day.cacheReadTokens,
                totalTokens: day.totalTokens,
                totalCost: day.totalCost,
                modelsUsed: day.modelBreakdowns.map(\.modelName),
                modelBreakdowns: day.modelBreakdowns.map { breakdown in
                    CCModelBreakdown(
                        modelName: breakdown.modelName,
                        inputTokens: breakdown.inputTokens,
                        outputTokens: breakdown.outputTokens,
                        cacheCreationTokens: breakdown.cacheCreationTokens,
                        cacheReadTokens: breakdown.cacheReadTokens,
                        cost: breakdown.cost
                    )
                }
            )
        }

        // Calculate totals
        let totals = CCTotals(
            inputTokens: daily.reduce(0) { $0 + $1.inputTokens },
            outputTokens: daily.reduce(0) { $0 + $1.outputTokens },
            cacheCreationTokens: daily.reduce(0) { $0 + $1.cacheCreationTokens },
            cacheReadTokens: daily.reduce(0) { $0 + $1.cacheReadTokens },
            totalCost: daily.reduce(0) { $0 + $1.totalCost },
            totalTokens: daily.reduce(0) { $0 + $1.totalTokens }
        )

        return CCUsageResponse(daily: daily, totals: totals)
    }

    /// Fetches session data for a specific date.
    func fetchSessions(for date: Date) async throws -> CCSessionResponse {
        let sessionData = await conversationService.fetchSessionUsage(for: date)

        // Convert to CCSessionResponse format
        let sessions = sessionData.map { session in
            CCSessionEntry(
                sessionId: session.id,
                inputTokens: session.inputTokens,
                outputTokens: session.outputTokens,
                cacheCreationTokens: session.cacheCreationTokens,
                cacheReadTokens: session.cacheReadTokens,
                totalTokens: session.totalTokens,
                totalCost: session.totalCost,
                lastActivity: ISO8601DateFormatter().string(from: session.endTime),
                modelsUsed: Array(session.modelsUsed),
                modelBreakdowns: [], // Session-level model breakdowns not implemented yet
                projectPath: session.projectPath
            )
        }

        // Calculate totals
        let totals = CCTotals(
            inputTokens: sessions.reduce(0) { $0 + $1.inputTokens },
            outputTokens: sessions.reduce(0) { $0 + $1.outputTokens },
            cacheCreationTokens: sessions.reduce(0) { $0 + $1.cacheCreationTokens },
            cacheReadTokens: sessions.reduce(0) { $0 + $1.cacheReadTokens },
            totalCost: sessions.reduce(0) { $0 + $1.totalCost },
            totalTokens: sessions.reduce(0) { $0 + $1.totalTokens }
        )

        return CCSessionResponse(sessions: sessions, totals: totals)
    }

    /// Refreshes pricing data from LiteLLM.
    func refreshPricing() async throws {
        _ = try await pricingService.getPricing()
    }
}
