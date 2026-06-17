import Foundation
import SwiftData

/// A persisted deduplication key (`messageId:requestId`) seen during ingestion.
///
/// The same message can appear in more than one `.jsonl` file (resumed/forked sessions copy
/// history), so byte-offset cursors alone cannot prevent cross-file double counting. Persisting
/// the seen keys matches `ccusage` semantics exactly. `day` is stored so the set can be pruned
/// to the rolling history window alongside the daily rows.
@Model
final class SeenMessageKey {
    #Unique<SeenMessageKey>([\.key])

    var key: String   // "messageId:requestId"
    var day: String   // yyyy-MM-dd of the entry, for windowed pruning

    init(key: String, day: String) {
        self.key = key
        self.day = day
    }
}
