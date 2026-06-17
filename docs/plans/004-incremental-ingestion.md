# Plan 004 — Incremental Ingestion (Byte-Cursor Parsing)

## Goal

Stop re-parsing the entire `~/.claude/projects` corpus on every poll. Today each poll
reads **~283 MB across 574 files** (median 115 KB, but with individual files up to
**47.6 MB**), and opening a day re-parses everything again — twice. After the
`rollingFetchDays` change from 7 → 90 this is the dominant runtime cost and a likely
aggravator of the SwiftData store contention.

Replace the full re-scan with **incremental ingestion**: parse only the bytes that are
new since the last poll, attribute each new entry to its day, and **increment** the
stored daily totals. Finalized days are parsed exactly once and never touched again.

---

## Key insight: the logs are append-only

Claude Code **appends** new lines to a session's `.jsonl`; it never rewrites earlier
lines. Therefore:

- We can keep a **byte offset per file** and only ever read bytes past it.
- Steady-state cost becomes proportional to *bytes written since the last poll*
  (typically a few hundred KB total), not corpus size, and not even changed-file size.
  The 47 MB active file costs only its newly-appended tail, not 47 MB.
- We never need an explicit "is the day over?" flag. Every entry carries its own
  wall-clock timestamp; a new append always gets *now's* timestamp, so an old day's
  total can never change. Correctness follows from "never read a byte twice" plus
  "route each entry to the day its timestamp names."

### Measured data (2026-06-17)

| metric | value |
|---|---|
| files | 574 |
| total | 283 MB |
| median file | 115 KB |
| p90 / p99 / max | 316 KB / 9.6 MB / 47.6 MB |

The large, *active* files are exactly the case byte-offsets optimize.

---

## Design Decisions (confirmed)

1. **Cross-file dedup:** persist seen `messageId:requestId` keys for exact **ccusage
   parity**. The same message can appear in multiple files (resumed/forked sessions);
   byte-offsets stop intra-file re-reads but not cross-file duplicates.
2. **Cursor storage:** a **SwiftData table**, so cursor advancement and day-total
   increments commit in one transaction — a failed/partial save can never desync the
   cursors from the totals.

---

## New SwiftData Models

```swift
@Model final class ParsedFileCursor {
    #Unique<ParsedFileCursor>([\.path])
    var path: String        // relative path under ~/.claude/projects (sessionId UUIDs are stable)
    var byteOffset: Int     // bytes consumed so far (always at a line boundary)
    var lastSize: Int       // detect growth vs truncation
    var lastModified: Date  // cheap pre-check before opening the file

    init(path: String, byteOffset: Int, lastSize: Int, lastModified: Date) { ... }
}

@Model final class SeenMessageKey {
    #Unique<SeenMessageKey>([\.key])
    var key: String         // "messageId:requestId"
    var day: String         // yyyy-MM-dd, for windowed pruning

    init(key: String, day: String) { ... }
}
```

`DailyUsage` / `ModelUsage` remain the aggregates — they are now **incremented** rather
than rebuilt.

> Schema change note: because Plan 001's store has no migration plan, adding these
> models requires the resilient-container work from the code review (explicit
> `ModelConfiguration` + do/catch + destructive recovery). That is a prerequisite of
> this plan and should land first or in the same change.

---

## Algorithm (per poll)

```
load cursors into [path: ParsedFileCursor]
load seenKeys into Set<String>            // or query lazily per key
perDayModelDelta: [day: [model: TokenDelta]] = [:]

for each file under ~/.claude/projects:
    (size, mtime) = stat(file)            // FileManager resourceValues — no open
    c = cursors[path]
    if c != nil && size == c.lastSize && mtime == c.lastModified:
        continue                          // unchanged — never even open it
    offset = c?.byteOffset ?? 0
    if size < offset:                     // truncated / rotated / recreated (rare)
        markForFullRebuild(path); continue
    handle = FileHandle(forReadingFrom: file)
    handle.seek(toOffset: offset)
    tail = handle.readToEnd()             // only the new bytes
    lastNL = lastIndex(of: '\n', in: tail)   // ignore any partial trailing line
    for each complete line up to lastNL:
        entry = decode(line); skip if no usage / no timestamp
        if let key = entry.dedupeKey, seenKeys.contains(key): continue
        if let key = entry.dedupeKey: seenKeys.insert(key); stageSeenKey(key, day)
        day = localDay(entry.timestamp)
        perDayModelDelta[day][model] += entry.tokens
    newOffset = offset + (lastNL + 1)
    stageCursor(path, byteOffset: newOffset, lastSize: size, lastModified: mtime)

apply perDayModelDelta -> DailyUsage/ModelUsage (increment tokens; recompute cost = Σ tokens × rate)
persist staged cursors + staged seen keys
context.save()                            // cursors + day rows + seen keys atomically
prune SeenMessageKey/DailyUsage older than rollingFetchDays
```

### Correctness details

1. **Partial trailing line.** A poll can catch a file mid-append. Advance the offset
   only to the last complete `\n`; the dangling line is re-read next poll. Off-by-one
   here causes silent token loss or duplication, so it needs a unit test.
2. **Cost is recomputed, not added.** With flat per-token rates, cost is linear in
   tokens. Store per-model token totals (already done) and recompute
   `cost = Σ tokens × rate` after each increment. This also makes the future >200k
   tiered-pricing fix drop in cleanly.
3. **Cross-file dedup.** Persist `messageId:requestId`. Entries lacking both IDs are
   never deduped (matches ccusage).
4. **Truncation / rotation.** `size < byteOffset` (or a changed inode) → the file's old
   contribution can't be cheaply subtracted. Detect it and trigger a scoped full
   rebuild. Rare; cheaper than tracking per-file-per-day contributions.
5. **First run / empty cursor table.** Equivalent to a full parse (offset 0 for every
   file) — unavoidable once, and it populates cursors + totals.

---

## Affected Code

| File | Change |
|---|---|
| `Models/` | add `ParsedFileCursor`, `SeenMessageKey` |
| `ClaudeWatchApp.swift` | resilient `ModelContainer` (prereq); register new models |
| `Services/ConversationService.swift` | new incremental parse path; reuse one decoder; consolidate the duplicate `parseFile`/`parseAllEntries` loops |
| `Services/CCUsageService.swift` | expose an `ingestIncremental()` that returns deltas (or writes via a ModelActor) |
| `Services/PollingService.swift` | call incremental ingest; increment instead of rebuild; prune to window |
| `Views/Detail/DayDetailView.swift` | derive session + hourly from the cached/stored data instead of two fresh full parses |
| `Utilities/Constants.swift` | wire up `maxHistoryDays` pruning |

---

## Out of Scope (tracked separately in the code review)

- Resilient `ModelContainer` + single-instance guard (prerequisite — separate commit).
- Session-cost per-model fix.
- Export error surfacing / `NSApp.mainWindow!` crash.

---

## Test Plan

- Append a line to a fixture file between two ingests → only the new line is counted.
- Append a partial line (no trailing `\n`) → not counted until completed next poll.
- Same `messageId:requestId` in two files → counted once.
- Append entries straddling midnight → split across two days correctly.
- File truncated/shrunk → triggers rebuild, totals stay correct.
- First run with empty cursor table → equals a full parse of the corpus.
