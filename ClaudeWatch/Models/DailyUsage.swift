import Foundation
import SwiftData

@Model
final class DailyUsage {
    #Unique<DailyUsage>([\.date])

    var date: String
    var inputTokens: Int
    var outputTokens: Int
    var cacheCreationTokens: Int
    var cacheReadTokens: Int
    var totalTokens: Int
    var totalCost: Double
    var lastUpdated: Date

    @Relationship(deleteRule: .cascade, inverse: \ModelUsage.dailyUsage)
    var modelBreakdowns: [ModelUsage]

    @Relationship(deleteRule: .cascade, inverse: \SessionUsage.dailyUsage)
    var sessions: [SessionUsage]

    init(date: String, inputTokens: Int, outputTokens: Int,
         cacheCreationTokens: Int, cacheReadTokens: Int,
         totalTokens: Int, totalCost: Double) {
        self.date = date
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.totalTokens = totalTokens
        self.totalCost = totalCost
        self.lastUpdated = Date()
        self.modelBreakdowns = []
        self.sessions = []
    }
}
