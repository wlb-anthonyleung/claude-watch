import Foundation

/// Aggregates conversation data by parsing ~/.claude conversation files.
actor ConversationService {
    private let claudeDir: URL

    init() {
        self.claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
    }

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
