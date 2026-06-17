import Foundation
import SwiftData

/// Tracks how far a single `.jsonl` log file has been ingested.
///
/// Claude Code appends to session logs and never rewrites earlier lines, so we only ever
/// need to read the bytes past `byteOffset`. `lastSize` / `lastModified` let a poll skip a
/// file entirely without opening it, and a shrinking `lastSize` signals truncation/rewrite
/// (which forces a full rebuild, since the old contribution can no longer be subtracted).
@Model
final class ParsedFileCursor {
    #Unique<ParsedFileCursor>([\.path])

    var path: String        // absolute path of the .jsonl file (session UUIDs make this stable)
    var byteOffset: Int     // bytes consumed so far; always sits at a line boundary
    var lastSize: Int       // last observed file size, to detect growth vs truncation
    var lastModified: Date  // last observed mtime, a cheap pre-check before opening

    init(path: String, byteOffset: Int, lastSize: Int, lastModified: Date) {
        self.path = path
        self.byteOffset = byteOffset
        self.lastSize = lastSize
        self.lastModified = lastModified
    }
}
