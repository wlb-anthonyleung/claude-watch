import Foundation

/// Value types exchanged between the `@MainActor` DB layer (`PollingService`) and the
/// parsing actor (`ConversationService`) during incremental ingestion. All are `Sendable`
/// so they cross the actor boundary without data races.

/// A file's ingest position, mirrored from `ParsedFileCursor` for transport.
struct FileCursor: Sendable {
    var byteOffset: Int
    var lastSize: Int
    var lastModified: Date
}

/// Running per-model token totals for a day (cost is derived separately).
struct ModelTokenTotals: Sendable {
    var inputTokens = 0
    var outputTokens = 0
    var cacheCreationTokens = 0
    /// Subset of `cacheCreationTokens` written with a 1-hour TTL (billed at a higher rate).
    var cacheCreation1hTokens = 0
    var cacheReadTokens = 0
}

/// A fully-priced per-model aggregate for a day, ready to persist as a `ModelUsage` row.
struct ModelAggregate: Sendable {
    var modelName: String
    var inputTokens: Int
    var outputTokens: Int
    var cacheCreationTokens: Int
    /// Subset of `cacheCreationTokens` written with a 1-hour TTL.
    var cacheCreation1hTokens: Int
    var cacheReadTokens: Int
    var cost: Double

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }
}

/// A newly-seen dedup key plus the day it belongs to (for pruning).
struct SeenKeyRecord: Sendable {
    let key: String
    let day: String
}

/// The outcome of one incremental ingest pass.
struct IngestResult: Sendable {
    /// Full, recomputed per-model aggregates for every day that gained new entries.
    /// Keyed by `yyyy-MM-dd`. Days with no new data are absent (left untouched in the DB).
    var changedDayAggregates: [String: [ModelAggregate]]

    /// New cursor positions for files that were read this pass, keyed by absolute path.
    var updatedCursors: [String: FileCursor]

    /// Absolute paths of every log file present on disk this pass. Lets the caller
    /// garbage-collect cursors for files that have since been deleted/cleaned up.
    var presentPaths: Set<String>

    /// Dedup keys discovered this pass that must be persisted.
    var newSeenKeys: [SeenKeyRecord]

    /// True if a tracked file shrank (truncation/rewrite): the caller must wipe and rebuild,
    /// since a file's prior contribution to day totals cannot be cheaply subtracted.
    var needsFullRebuild: Bool
}
