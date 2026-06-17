import Foundation

enum AppConstants {
    static let defaultPollingIntervalMinutes = 5
    static let detailWindowID = "detail-window"
    /// Days of daily-usage history to retain; `nil` keeps all history forever. ClaudeWatch's
    /// store is the only long-term record — Claude Code deletes old session logs after ~6 weeks —
    /// so we never age-prune by default and let history accumulate beyond the logs' lifetime.
    static let maxHistoryDays: Int? = nil
    /// Days back each poll ingests; `nil` ingests all available history (no lower-bound filter).
    static let rollingFetchDays: Int? = nil
    /// How long message dedup keys are kept. Bounded (unlike history) because Claude Code cleans
    /// up source logs within ~6 weeks, so an older message can never reappear in a new file.
    static let seenKeyRetentionDays = 60
}
