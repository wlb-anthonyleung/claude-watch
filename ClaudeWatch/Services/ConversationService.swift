import Foundation

/// Aggregates conversation data by parsing ~/.claude conversation files.
actor ConversationService {
    private let claudeDir: URL
    private let pricingService: PricingService

    init(pricingService: PricingService = PricingService()) {
        self.claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
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

        // Aggregate tokens by hour
        var hourlyData: [Int: (input: Int, output: Int, cacheCreate: Int, cacheRead: Int)] = [:]
        for hour in 0..<24 {
            hourlyData[hour] = (0, 0, 0, 0)
        }

        for fileURL in jsonlFiles {
            await parseFile(fileURL, targetDay: targetDay, into: &hourlyData)
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

    // MARK: - Daily Usage

    /// Fetches daily usage aggregated by date since the given date.
    func fetchDailyUsage(since: Date) async -> [DailyUsageData] {
        let jsonlFiles = findJSONLFiles()
        let entries = await parseAllEntries(from: jsonlFiles, since: since)

        // Group by date
        let calendar = Calendar.current
        var dailyMap: [String: DailyUsageData] = [:]
        var modelMap: [String: [String: ModelBreakdownData]] = [:] // date -> model -> breakdown

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for entry in entries {
            guard let timestamp = entry.parsedTimestamp else { continue }

            let dateStr = dateFormatter.string(from: timestamp)
            let model = entry.message?.model ?? "unknown"

            // Initialize daily entry if needed
            if dailyMap[dateStr] == nil {
                dailyMap[dateStr] = DailyUsageData(
                    date: dateStr,
                    inputTokens: 0,
                    outputTokens: 0,
                    cacheCreationTokens: 0,
                    cacheReadTokens: 0,
                    totalCost: 0,
                    modelBreakdowns: []
                )
                modelMap[dateStr] = [:]
            }

            // Update daily totals
            let usage = entry.message?.usage
            let inputTokens = usage?.inputTokens ?? 0
            let outputTokens = usage?.outputTokens ?? 0
            let cacheCreate = usage?.cacheCreationInputTokens ?? 0
            let cacheRead = usage?.cacheReadInputTokens ?? 0

            dailyMap[dateStr]?.inputTokens += inputTokens
            dailyMap[dateStr]?.outputTokens += outputTokens
            dailyMap[dateStr]?.cacheCreationTokens += cacheCreate
            dailyMap[dateStr]?.cacheReadTokens += cacheRead

            // Update model breakdown
            if modelMap[dateStr]?[model] == nil {
                modelMap[dateStr]?[model] = ModelBreakdownData(
                    modelName: model,
                    inputTokens: 0,
                    outputTokens: 0,
                    cacheCreationTokens: 0,
                    cacheReadTokens: 0,
                    cost: 0
                )
            }
            modelMap[dateStr]?[model]?.inputTokens += inputTokens
            modelMap[dateStr]?[model]?.outputTokens += outputTokens
            modelMap[dateStr]?[model]?.cacheCreationTokens += cacheCreate
            modelMap[dateStr]?[model]?.cacheReadTokens += cacheRead
        }

        // Calculate costs using pricing service
        for dateStr in dailyMap.keys {
            guard var models = modelMap[dateStr] else { continue }

            for modelName in models.keys {
                guard var breakdown = models[modelName] else { continue }
                let tokenUsage = TokenUsage(
                    inputTokens: breakdown.inputTokens,
                    outputTokens: breakdown.outputTokens,
                    cacheCreationTokens: breakdown.cacheCreationTokens,
                    cacheReadTokens: breakdown.cacheReadTokens
                )
                breakdown.cost = await pricingService.calculateCost(model: modelName, usage: tokenUsage)
                models[modelName] = breakdown
            }

            dailyMap[dateStr]?.modelBreakdowns = Array(models.values)
            dailyMap[dateStr]?.totalCost = models.values.reduce(0) { $0 + $1.cost }
        }

        return dailyMap.values.sorted { $0.date < $1.date }
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
                if let parsedDate = isoFormatter.date(from: timestamp) {
                    entry.parsedTimestamp = parsedDate

                    // Filter by date
                    if parsedDate >= since {
                        allEntries.append(entry)
                    }
                }
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

    private func parseFile(
        _ fileURL: URL,
        targetDay: Date,
        into hourlyData: inout [Int: (input: Int, output: Int, cacheCreate: Int, cacheRead: Int)]
    ) async {
        let calendar = Calendar.current

        guard let data = try? Data(contentsOf: fileURL),
              let content = String(data: data, encoding: .utf8) else {
            return
        }

        let lines = content.components(separatedBy: .newlines)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

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
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let entryDate = isoFormatter.date(from: timestamp) else {
                continue
            }

            // Check if same day
            guard calendar.isDate(entryDate, inSameDayAs: targetDay) else {
                continue
            }

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
    let message: MessageContent?
}

private struct MessageContent: Decodable {
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
    let message: ParsedMessageContent?
    var parsedTimestamp: Date?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case sessionId
        case cwd
        case message
    }
}

private struct ParsedMessageContent: Decodable {
    let model: String?
    let usage: UsageInfo?
}
