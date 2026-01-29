import Foundation

struct CCUsageResponse: Codable {
    let daily: [CCDailyEntry]
    let totals: CCTotals
}

struct CCDailyEntry: Codable {
    let date: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let totalTokens: Int
    let totalCost: Double
    let modelsUsed: [String]
    let modelBreakdowns: [CCModelBreakdown]
}

struct CCModelBreakdown: Codable {
    let modelName: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let cost: Double
}

struct CCTotals: Codable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let totalCost: Double
    let totalTokens: Int
}

// MARK: - Session Response

struct CCSessionResponse: Codable {
    let sessions: [CCSessionEntry]
    let totals: CCTotals
}

struct CCSessionEntry: Codable, Identifiable {
    var id: String { sessionId }
    let sessionId: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let totalTokens: Int
    let totalCost: Double
    let lastActivity: String
    let modelsUsed: [String]
    let modelBreakdowns: [CCModelBreakdown]
    let projectPath: String?

    var displayName: String {
        if let path = projectPath, path != "Unknown Project" {
            return path
        }
        // Extract meaningful name from sessionId (path-based)
        let components = sessionId.split(separator: "-")
        if components.count >= 2 {
            return String(components.suffix(2).joined(separator: "/"))
        }
        return sessionId
    }
}
