import Foundation

/// Aggregates conversation data by parsing ~/.claude conversation files.
actor ConversationService {
    private let claudeDir: URL
    private let projectsDir: URL
    private let pricingService: PricingService

    init(pricingService: PricingService = PricingService()) {
        let claude = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        self.claudeDir = claude
        self.projectsDir = claude.appendingPathComponent("projects")
        self.pricingService = pricingService
    }

    // MARK: - Public Types

    /// Represents token usage for a specific hour.
    struct HourlyUsage: Identifiable {
        let id = UUID()
        let hour: Int // 0-23
        let inputTokens: Int
        let outputTokens: Int
        let cacheCreationTokens: Int
        let cacheReadTokens: Int

        var totalTokens: Int {
            inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
        }
    }

    /// Represents daily usage with model breakdown.
    struct DailyUsageData: Identifiable {
        let id = UUID()
        let date: String // yyyy-MM-dd
        var inputTokens: Int
        var outputTokens: Int
        var cacheCreationTokens: Int
        var cacheReadTokens: Int
        var totalCost: Double
        var modelBreakdowns: [ModelBreakdownData]

        var totalTokens: Int {
            inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
        }
    }

    /// Represents per-model token breakdown.
    struct ModelBreakdownData: Identifiable {
        let id = UUID()
        let modelName: String
        var inputTokens: Int
        var outputTokens: Int
        var cacheCreationTokens: Int
        var cacheReadTokens: Int
        var cost: Double

        var totalTokens: Int {
            inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
        }
    }

    /// Represents a session (billing window) with aggregated usage.
    struct SessionData: Identifiable {
        let id: String // sessionId
        let projectPath: String
        let displayName: String
        var startTime: Date
        var endTime: Date
        var inputTokens: Int
        var outputTokens: Int
        var cacheCreationTokens: Int
        var cacheReadTokens: Int
        var totalCost: Double
        var modelsUsed: Set<String>

        var totalTokens: Int {
            inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
        }
    }

    /// Fetches hourly token usage for a specific date.
    func fetchHourlyUsage(for date: Date) async -> [HourlyUsage] {
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: date)

        // Find all JSONL files
        let jsonlFiles = findJSONLFiles()

        // Aggregate tokens by hour with deduplication
        var hourlyData: [Int: (input: Int, output: Int, cacheCreate: Int, cacheRead: Int)] = [:]
        for hour in 0..<24 {
            hourlyData[hour] = (0, 0, 0, 0)
        }
        var seenKeys: Set<String> = []

        for fileURL in jsonlFiles {
            await parseFile(fileURL, targetDay: targetDay, into: &hourlyData, seenKeys: &seenKeys)
        }

        return hourlyData.map { hour, data in
            HourlyUsage(
                hour: hour,
                inputTokens: data.input,
                outputTokens: data.output,
                cacheCreationTokens: data.cacheCreate,
                cacheReadTokens: data.cacheRead
            )
        }.sorted { $0.hour < $1.hour }
    }

    // MARK: - Incremental Ingestion

    /// Incrementally ingests new log entries since the last pass.
    ///
    /// For each `.jsonl` under `~/.claude/projects`, this reads only the bytes past the file's
    /// cursor, deduplicates against `seenKeys`, and folds new tokens into `existingDayTotals`.
    /// It returns fully re-priced aggregates for every day that changed, the advanced cursors,
    /// and the newly-seen dedup keys. A first run (empty cursors) reads every file from offset 0.
    ///
    /// - Parameters:
    ///   - existingCursors: prior ingest positions, keyed by absolute file path.
    ///   - existingDayTotals: current cumulative per-day, per-model token totals from the DB.
    ///   - seenKeys: every dedup key already counted (within the rolling window).
    ///   - sinceDay: `yyyy-MM-dd` lower bound; entries older than this are ignored.
    func ingest(
        existingCursors: [String: FileCursor],
        existingDayTotals: [String: [String: ModelTokenTotals]],
        seenKeys: Set<String>,
        sinceDay: String
    ) async -> IngestResult {
        var dayTotals = existingDayTotals
        var seen = seenKeys
        var newKeys: [SeenKeyRecord] = []
        var updatedCursors: [String: FileCursor] = [:]
        var presentPaths: Set<String> = []
        var changedDays: Set<String> = []
        var needsFullRebuild = false

        for fileURL in findProjectJSONLFiles() {
            let path = fileURL.path
            presentPaths.insert(path)

            // The enumerator prefetched these keys, so this reads cached values, not a new syscall.
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = values?.fileSize ?? 0
            let mtime = values?.contentModificationDate ?? .distantPast

            let cursor = existingCursors[path]

            // Unchanged since last pass — skip without opening the file.
            if let cursor, size == cursor.lastSize, mtime == cursor.lastModified {
                continue
            }

            var startOffset = 0
            if let cursor {
                if size < cursor.byteOffset {
                    // File shrank: a counted contribution is gone. Only a full rebuild is correct.
                    needsFullRebuild = true
                    continue
                }
                startOffset = cursor.byteOffset
            }

            let newOffset = parseTail(
                fileURL,
                from: startOffset,
                sinceDay: sinceDay,
                seen: &seen,
                newKeys: &newKeys,
                dayTotals: &dayTotals,
                changedDays: &changedDays
            )
            updatedCursors[path] = FileCursor(byteOffset: newOffset, lastSize: size, lastModified: mtime)
        }

        // Re-price every day that changed, using its full cumulative per-model totals.
        var aggregates: [String: [ModelAggregate]] = [:]
        for day in changedDays {
            guard let models = dayTotals[day] else { continue }
            var list: [ModelAggregate] = []
            for (modelName, totals) in models {
                let cost = await pricingService.calculateCost(
                    model: modelName,
                    usage: TokenUsage(
                        inputTokens: totals.inputTokens,
                        outputTokens: totals.outputTokens,
                        cacheCreationTokens: totals.cacheCreationTokens,
                        cacheReadTokens: totals.cacheReadTokens
                    )
                )
                list.append(ModelAggregate(
                    modelName: modelName,
                    inputTokens: totals.inputTokens,
                    outputTokens: totals.outputTokens,
                    cacheCreationTokens: totals.cacheCreationTokens,
                    cacheReadTokens: totals.cacheReadTokens,
                    cost: cost
                ))
            }
            aggregates[day] = list
        }

        return IngestResult(
            changedDayAggregates: aggregates,
            updatedCursors: updatedCursors,
            presentPaths: presentPaths,
            newSeenKeys: newKeys,
            needsFullRebuild: needsFullRebuild
        )
    }

    /// Reads complete lines appended past `offset`, folding new usage into `dayTotals`.
    ///
    /// Only bytes up to the last newline are consumed; a partial trailing line (the file was
    /// caught mid-append) is left for the next pass. Returns the new, line-aligned byte offset.
    private func parseTail(
        _ fileURL: URL,
        from offset: Int,
        sinceDay: String,
        seen: inout Set<String>,
        newKeys: inout [SeenKeyRecord],
        dayTotals: inout [String: [String: ModelTokenTotals]],
        changedDays: inout Set<String>
    ) -> Int {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return offset }
        defer { try? handle.close() }

        if offset > 0 {
            do { try handle.seek(toOffset: UInt64(offset)) } catch { return offset }
        }
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return offset }

        // Consume only through the last complete line; re-read any partial trailing line next time.
        guard let lastNewline = data.lastIndex(of: 0x0A) else { return offset }
        let consumed = data.distance(from: data.startIndex, to: lastNewline) + 1
        let block = data.prefix(consumed)

        let decoder = JSONDecoder()
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for lineSlice in block.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let entry = try? decoder.decode(ParsedEntry.self, from: Data(lineSlice)),
                  let usage = entry.message?.usage,
                  let timestamp = entry.timestamp,
                  let date = isoFormatter.date(from: timestamp) else {
                continue
            }

            let model = entry.message?.model ?? "unknown"
            // Skip synthetic model (internal Claude Code operations, not real API calls).
            if model == "<synthetic>" { continue }

            let day = dateFormatter.string(from: date)
            // Ignore entries older than the rolling window (relevant only on a first/full pass).
            if day < sinceDay { continue }

            // Deduplicate using messageId + requestId (only when both are present), matching ccusage.
            if let key = entry.dedupeKey {
                if seen.contains(key) { continue }
                seen.insert(key)
                newKeys.append(SeenKeyRecord(key: key, day: day))
            }

            var models = dayTotals[day] ?? [:]
            var totals = models[model] ?? ModelTokenTotals()
            totals.inputTokens += usage.inputTokens ?? 0
            totals.outputTokens += usage.outputTokens ?? 0
            totals.cacheCreationTokens += usage.cacheCreationInputTokens ?? 0
            totals.cacheReadTokens += usage.cacheReadInputTokens ?? 0
            models[model] = totals
            dayTotals[day] = models
            changedDays.insert(day)
        }

        return offset + consumed
    }

    // MARK: - Session Usage

    /// Fetches session usage for a specific date using 5-hour billing windows.
    func fetchSessionUsage(for date: Date) async -> [SessionData] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let jsonlFiles = findJSONLFiles()
        let allEntries = await parseAllEntries(from: jsonlFiles, since: startOfDay)

        // Filter to entries for this day
        let dayEntries = allEntries.filter { entry in
            guard let timestamp = entry.parsedTimestamp else { return false }
            return timestamp >= startOfDay && timestamp < endOfDay
        }

        // Group by session ID
        var sessionMap: [String: [ParsedEntry]] = [:]
        for entry in dayEntries {
            let sessionId = entry.sessionId ?? "unknown"
            sessionMap[sessionId, default: []].append(entry)
        }

        // Build session data
        var sessions: [SessionData] = []

        for (sessionId, entries) in sessionMap {
            let sorted = entries.sorted { ($0.parsedTimestamp ?? .distantPast) < ($1.parsedTimestamp ?? .distantPast) }
            guard let firstEntry = sorted.first,
                  let firstTimestamp = firstEntry.parsedTimestamp,
                  let lastTimestamp = sorted.last?.parsedTimestamp else {
                continue
            }

            // Extract project path from file path or cwd
            let projectPath = firstEntry.cwd ?? extractProjectPath(from: firstEntry)

            var session = SessionData(
                id: sessionId,
                projectPath: projectPath,
                displayName: formatDisplayName(projectPath),
                startTime: firstTimestamp,
                endTime: lastTimestamp,
                inputTokens: 0,
                outputTokens: 0,
                cacheCreationTokens: 0,
                cacheReadTokens: 0,
                totalCost: 0,
                modelsUsed: []
            )

            // Aggregate tokens and models
            for entry in sorted {
                let usage = entry.message?.usage
                session.inputTokens += usage?.inputTokens ?? 0
                session.outputTokens += usage?.outputTokens ?? 0
                session.cacheCreationTokens += usage?.cacheCreationInputTokens ?? 0
                session.cacheReadTokens += usage?.cacheReadInputTokens ?? 0

                if let model = entry.message?.model {
                    session.modelsUsed.insert(model)
                }
            }

            // Calculate cost
            for model in session.modelsUsed {
                // Calculate proportional cost per model (simplified - uses total tokens)
                let tokenUsage = TokenUsage(
                    inputTokens: session.inputTokens,
                    outputTokens: session.outputTokens,
                    cacheCreationTokens: session.cacheCreationTokens,
                    cacheReadTokens: session.cacheReadTokens
                )
                session.totalCost = await pricingService.calculateCost(model: model, usage: tokenUsage)
                break // Use first model's pricing for simplicity
            }

            sessions.append(session)
        }

        return sessions.sorted { $0.totalCost > $1.totalCost }
    }

    // MARK: - Helpers

    private func extractProjectPath(from entry: ParsedEntry) -> String {
        // Try to get from cwd first
        if let cwd = entry.cwd, !cwd.isEmpty {
            return cwd
        }
        return "Unknown Project"
    }

    private func formatDisplayName(_ path: String) -> String {
        // Extract last path component for display
        let url = URL(fileURLWithPath: path)
        return url.lastPathComponent
    }

    // MARK: - Entry Parsing

    private func parseAllEntries(from files: [URL], since: Date) async -> [ParsedEntry] {
        var allEntries: [ParsedEntry] = []
        var seenKeys: Set<String> = []
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for fileURL in files {
            guard let data = try? Data(contentsOf: fileURL),
                  let content = String(data: data, encoding: .utf8) else {
                continue
            }

            let lines = content.components(separatedBy: .newlines)
            let decoder = JSONDecoder()

            for line in lines where !line.isEmpty {
                guard let lineData = line.data(using: .utf8),
                      var entry = try? decoder.decode(ParsedEntry.self, from: lineData) else {
                    continue
                }

                // Only process assistant messages with usage data
                guard entry.message?.usage != nil,
                      let timestamp = entry.timestamp else {
                    continue
                }

                // Parse timestamp
                guard let parsedDate = isoFormatter.date(from: timestamp) else {
                    continue
                }

                entry.parsedTimestamp = parsedDate

                // Filter by date
                guard parsedDate >= since else {
                    continue
                }

                // Deduplicate using messageId + requestId (only when both are present)
                if let key = entry.dedupeKey {
                    if seenKeys.contains(key) {
                        continue
                    }
                    seenKeys.insert(key)
                }
                // Entries without both IDs are never deduplicated (always counted)

                allEntries.append(entry)
            }
        }

        return allEntries
    }

    private func findJSONLFiles() -> [URL] {
        let fm = FileManager.default
        var files: [URL] = []

        guard let enumerator = fm.enumerator(
            at: claudeDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "jsonl" {
                files.append(fileURL)
            }
        }

        return files
    }

    /// Enumerates `.jsonl` files under `~/.claude/projects` only — the conversation logs that
    /// carry usage data. Narrower (and faster) than `findJSONLFiles`, which walks all of `~/.claude`.
    private func findProjectJSONLFiles() -> [URL] {
        let fm = FileManager.default
        var files: [URL] = []

        guard let enumerator = fm.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "jsonl" {
                files.append(fileURL)
            }
        }

        return files
    }

    private func parseFile(
        _ fileURL: URL,
        targetDay: Date,
        into hourlyData: inout [Int: (input: Int, output: Int, cacheCreate: Int, cacheRead: Int)],
        seenKeys: inout Set<String>
    ) async {
        let calendar = Calendar.current

        guard let data = try? Data(contentsOf: fileURL),
              let content = String(data: data, encoding: .utf8) else {
            return
        }

        let lines = content.components(separatedBy: .newlines)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for line in lines where !line.isEmpty {
            guard let lineData = line.data(using: .utf8),
                  let entry = try? decoder.decode(ConversationEntry.self, from: lineData) else {
                continue
            }

            // Only process assistant messages with usage data
            guard let usage = entry.message?.usage,
                  let timestamp = entry.timestamp else {
                continue
            }

            // Parse timestamp
            guard let entryDate = isoFormatter.date(from: timestamp) else {
                continue
            }

            // Check if same day
            guard calendar.isDate(entryDate, inSameDayAs: targetDay) else {
                continue
            }

            // Deduplicate using messageId + requestId (only when both are present)
            if let key = entry.dedupeKey {
                if seenKeys.contains(key) {
                    continue
                }
                seenKeys.insert(key)
            }
            // Entries without both IDs are never deduplicated (always counted)

            let hour = calendar.component(.hour, from: entryDate)

            var current = hourlyData[hour] ?? (0, 0, 0, 0)
            current.input += usage.inputTokens ?? 0
            current.output += usage.outputTokens ?? 0
            current.cacheCreate += usage.cacheCreationInputTokens ?? 0
            current.cacheRead += usage.cacheReadInputTokens ?? 0
            hourlyData[hour] = current
        }
    }
}

// MARK: - Decodable Types for Conversation Entries

private struct ConversationEntry: Decodable {
    let timestamp: String?
    let requestId: String?
    let message: MessageContent?

    /// Unique key for deduplication (messageId + requestId).
    /// Returns nil if either is missing - entries without both IDs are never deduplicated.
    /// This matches ccusage behavior exactly.
    var dedupeKey: String? {
        guard let msgId = message?.id, let reqId = requestId else {
            return nil
        }
        return "\(msgId):\(reqId)"
    }
}

private struct MessageContent: Decodable {
    let id: String?
    let usage: UsageInfo?
}

private struct UsageInfo: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
    }
}

/// Extended entry type for full parsing with session and model info.
private struct ParsedEntry: Decodable {
    let timestamp: String?
    let sessionId: String?
    let cwd: String?
    let requestId: String?
    let message: ParsedMessageContent?
    var parsedTimestamp: Date?

    /// Unique key for deduplication (messageId + requestId).
    /// Returns nil if either is missing - entries without both IDs are never deduplicated.
    /// This matches ccusage behavior exactly.
    var dedupeKey: String? {
        guard let msgId = message?.id, let reqId = requestId else {
            return nil
        }
        return "\(msgId):\(reqId)"
    }

    enum CodingKeys: String, CodingKey {
        case timestamp
        case sessionId
        case cwd
        case requestId
        case message
    }
}

private struct ParsedMessageContent: Decodable {
    let id: String?
    let model: String?
    let usage: UsageInfo?
}
