import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class PollingService {
    var isPolling = false
    var lastPollTime: Date?
    var lastError: String?
    var pollingIntervalMinutes: Int = AppConstants.defaultPollingIntervalMinutes

    private var timer: Timer?
    private var hasStarted = false
    private let ccUsageService: CCUsageService
    private let modelContainer: ModelContainer

    init(ccUsageService: CCUsageService, modelContainer: ModelContainer) {
        self.ccUsageService = ccUsageService
        self.modelContainer = modelContainer
    }

    func startPolling() {
        guard !hasStarted else { return }
        hasStarted = true
        Task { await pollNow() }
        scheduleTimer()
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func updateInterval(_ minutes: Int) {
        pollingIntervalMinutes = minutes
        stopPolling()
        scheduleTimer()
    }

    func pollNow() async {
        guard !isPolling else { return }
        isPolling = true
        lastError = nil

        do {
            try await ingest()
            lastPollTime = Date()
        } catch {
            lastError = error.localizedDescription
            // Discard any pending changes so the next poll starts from a clean snapshot.
            modelContainer.mainContext.rollback()
        }

        isPolling = false
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = TimeInterval(pollingIntervalMinutes * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.pollNow()
            }
        }
    }

    // MARK: - Incremental Ingestion

    /// Snapshots the current store, ingests only newly-appended log bytes, and applies the
    /// resulting per-day deltas. A detected file truncation triggers a one-time full rebuild.
    private func ingest() async throws {
        let context = modelContainer.mainContext
        let calendar = Calendar.current
        let now = Date()

        let sinceDate = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -(AppConstants.rollingFetchDays - 1), to: now) ?? now
        )
        // Never prune anything still inside the fetch window: a file's cursor advances past a
        // day's bytes, so a pruned-but-still-fetched day could never be rebuilt. Retain at least
        // rollingFetchDays regardless of how maxHistoryDays is set.
        let historyDays = max(AppConstants.maxHistoryDays, AppConstants.rollingFetchDays)
        let pruneDate = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -(historyDays - 1), to: now) ?? now
        )
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let sinceDay = dayFormatter.string(from: sinceDate)
        let pruneDay = dayFormatter.string(from: pruneDate)

        // Snapshot current DB state to feed the parser.
        let cursorRows = try context.fetch(FetchDescriptor<ParsedFileCursor>())
        var cursorMap: [String: FileCursor] = [:]
        for c in cursorRows {
            cursorMap[c.path] = FileCursor(byteOffset: c.byteOffset, lastSize: c.lastSize, lastModified: c.lastModified)
        }

        let dayRows = try context.fetch(FetchDescriptor<DailyUsage>())
        var dayTotals: [String: [String: ModelTokenTotals]] = [:]
        for d in dayRows {
            var models: [String: ModelTokenTotals] = [:]
            for mb in d.modelBreakdowns {
                models[mb.modelName] = ModelTokenTotals(
                    inputTokens: mb.inputTokens,
                    outputTokens: mb.outputTokens,
                    cacheCreationTokens: mb.cacheCreationTokens,
                    cacheReadTokens: mb.cacheReadTokens
                )
            }
            dayTotals[d.date] = models
        }

        let seenRows = try context.fetch(FetchDescriptor<SeenMessageKey>())
        var seenSet = Set<String>(minimumCapacity: seenRows.count)
        for s in seenRows { seenSet.insert(s.key) }

        // With no cursors there is no incremental basis: every file is read from offset 0, so day
        // totals must be rebuilt from scratch. Passing empty existing state (rather than the day
        // rows) is what prevents double-counting — including when upgrading a store written by the
        // earlier, pre-cursor layout, whose day rows would otherwise be added to a full re-parse.
        let fullParse = cursorRows.isEmpty

        var result = await ccUsageService.ingestIncremental(
            existingCursors: cursorMap,
            existingDayTotals: fullParse ? [:] : dayTotals,
            seenKeys: fullParse ? [] : seenSet,
            sinceDay: sinceDay
        )

        if result.needsFullRebuild || fullParse {
            // Rebuild path: wipe derived rows in their own transaction so re-inserting the same
            // #Unique keys can't collide with the rows being deleted. (For a truly fresh store
            // these loops delete nothing.)
            for d in dayRows { context.delete(d) }
            for c in cursorRows { context.delete(c) }
            for s in seenRows { context.delete(s) }
            try context.save()

            if result.needsFullRebuild {
                // A tracked file shrank: the first pass ran against now-stale state, so recompute
                // cleanly from empty. (A fullParse result is already computed from empty above.)
                result = await ccUsageService.ingestIncremental(
                    existingCursors: [:],
                    existingDayTotals: [:],
                    seenKeys: [],
                    sinceDay: sinceDay
                )
            }
            // Every row is now freshly created, in-window, and for a present file — nothing to
            // prune or garbage-collect.
            try apply(result, context: context)
        } else {
            try apply(result, context: context)

            // Prune rows older than the history window. Skip days we just re-priced (they are
            // always >= sinceDay >= pruneDay, but guard explicitly so a future window change
            // can never delete a day apply() just wrote).
            let changedDays = Set(result.changedDayAggregates.keys)
            for d in dayRows where d.date < pruneDay && !changedDays.contains(d.date) {
                context.delete(d)
            }
            for s in seenRows where s.day < pruneDay {
                context.delete(s)
            }
            // Garbage-collect cursors for log files that have since been deleted/cleaned up.
            for c in cursorRows where !result.presentPaths.contains(c.path) {
                context.delete(c)
            }
        }

        try context.save()
    }

    /// Applies one ingest result: upserts changed days, advances cursors, persists new dedup keys.
    private func apply(_ result: IngestResult, context: ModelContext) throws {
        for (date, models) in result.changedDayAggregates {
            let targetDate = date
            let descriptor = FetchDescriptor<DailyUsage>(
                predicate: #Predicate { $0.date == targetDate }
            )
            let usage: DailyUsage
            if let found = try context.fetch(descriptor).first {
                usage = found
                for mb in usage.modelBreakdowns { context.delete(mb) }
                usage.modelBreakdowns = []
            } else {
                usage = DailyUsage(
                    date: date, inputTokens: 0, outputTokens: 0,
                    cacheCreationTokens: 0, cacheReadTokens: 0, totalTokens: 0, totalCost: 0
                )
                context.insert(usage)
            }

            var input = 0, output = 0, cacheCreate = 0, cacheRead = 0, cost = 0.0
            for m in models {
                usage.modelBreakdowns.append(ModelUsage(
                    modelName: m.modelName,
                    inputTokens: m.inputTokens,
                    outputTokens: m.outputTokens,
                    cacheCreationTokens: m.cacheCreationTokens,
                    cacheReadTokens: m.cacheReadTokens,
                    cost: m.cost
                ))
                input += m.inputTokens
                output += m.outputTokens
                cacheCreate += m.cacheCreationTokens
                cacheRead += m.cacheReadTokens
                cost += m.cost
            }
            usage.inputTokens = input
            usage.outputTokens = output
            usage.cacheCreationTokens = cacheCreate
            usage.cacheReadTokens = cacheRead
            usage.totalTokens = input + output + cacheCreate + cacheRead
            usage.totalCost = cost
            usage.lastUpdated = Date()
        }

        for (path, cursor) in result.updatedCursors {
            let targetPath = path
            let descriptor = FetchDescriptor<ParsedFileCursor>(
                predicate: #Predicate { $0.path == targetPath }
            )
            if let existing = try context.fetch(descriptor).first {
                existing.byteOffset = cursor.byteOffset
                existing.lastSize = cursor.lastSize
                existing.lastModified = cursor.lastModified
            } else {
                context.insert(ParsedFileCursor(
                    path: path,
                    byteOffset: cursor.byteOffset,
                    lastSize: cursor.lastSize,
                    lastModified: cursor.lastModified
                ))
            }
        }

        for record in result.newSeenKeys {
            context.insert(SeenMessageKey(key: record.key, day: record.day))
        }
    }
}
