import Foundation
import SwiftData

@Model
final class ModelUsage {
    var modelName: String
    var inputTokens: Int
    var outputTokens: Int
    var cacheCreationTokens: Int
    /// Subset of `cacheCreationTokens` written with a 1-hour TTL. Persisted so a changed day can
    /// be re-priced from the stored snapshot (1h cache writes cost more than 5-minute ones).
    /// Defaulted for lightweight migration of stores written before this field existed.
    var cacheCreation1hTokens: Int = 0
    var cacheReadTokens: Int
    var cost: Double

    var dailyUsage: DailyUsage?

    init(modelName: String, inputTokens: Int, outputTokens: Int,
         cacheCreationTokens: Int, cacheReadTokens: Int, cost: Double,
         cacheCreation1hTokens: Int = 0) {
        self.modelName = modelName
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheCreation1hTokens = cacheCreation1hTokens
        self.cacheReadTokens = cacheReadTokens
        self.cost = cost
    }
}
