import Foundation
import SwiftData

@Model
final class ModelUsage {
    var modelName: String
    var inputTokens: Int
    var outputTokens: Int
    var cacheCreationTokens: Int
    var cacheReadTokens: Int
    var cost: Double

    var dailyUsage: DailyUsage?

    init(modelName: String, inputTokens: Int, outputTokens: Int,
         cacheCreationTokens: Int, cacheReadTokens: Int, cost: Double) {
        self.modelName = modelName
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.cost = cost
    }
}
