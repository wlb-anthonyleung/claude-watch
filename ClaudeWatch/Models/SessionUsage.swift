import Foundation
import SwiftData

@Model
final class SessionUsage {
    var sessionId: String
    var inputTokens: Int
    var outputTokens: Int
    var cacheCreationTokens: Int
    var cacheReadTokens: Int
    var totalTokens: Int
    var totalCost: Double
    var lastActivity: String
    var modelsUsed: [String]
    var projectPath: String?

    var dailyUsage: DailyUsage?

    init(sessionId: String, inputTokens: Int, outputTokens: Int,
         cacheCreationTokens: Int, cacheReadTokens: Int,
         totalTokens: Int, totalCost: Double, lastActivity: String,
         modelsUsed: [String], projectPath: String?) {
        self.sessionId = sessionId
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.totalTokens = totalTokens
        self.totalCost = totalCost
        self.lastActivity = lastActivity
        self.modelsUsed = modelsUsed
        self.projectPath = projectPath
    }

    var displayName: String {
        if let path = projectPath, path != "Unknown Project" {
            return path
        }
        let components = sessionId.split(separator: "-")
        if components.count >= 2 {
            return String(components.suffix(2).joined(separator: "/"))
        }
        return sessionId
    }
}
