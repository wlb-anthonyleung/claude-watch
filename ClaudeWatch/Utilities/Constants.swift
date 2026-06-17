import Foundation

enum AppConstants {
    static let defaultPollingIntervalMinutes = 5
    static let detailWindowID = "detail-window"
    /// Days of history retained in the store. Effective retention is clamped to at least
    /// `rollingFetchDays` (see PollingService) so ingested-but-pruned days can't be lost.
    static let maxHistoryDays = 90
    /// How many days back each poll ingests. Must be <= maxHistoryDays for that to take effect.
    static let rollingFetchDays = 90
}
