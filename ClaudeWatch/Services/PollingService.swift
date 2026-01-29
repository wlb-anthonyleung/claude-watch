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
            // Use startOfDay to ensure we capture all entries from the first day
            let rawDate = Calendar.current.date(
                byAdding: .day, value: -(AppConstants.rollingFetchDays - 1), to: Date()
            )!
            let sinceDate = Calendar.current.startOfDay(for: rawDate)
            let response = try await ccUsageService.fetchUsage(since: sinceDate)
            try persistResponse(response)
            lastPollTime = Date()
        } catch {
            lastError = error.localizedDescription
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

    private func persistResponse(_ response: CCUsageResponse) throws {
        let context = modelContainer.mainContext

        for entry in response.daily {
            let dateToMatch = entry.date
            let predicate = #Predicate<DailyUsage> { usage in
                usage.date == dateToMatch
            }
            let descriptor = FetchDescriptor<DailyUsage>(predicate: predicate)
            let existing = try context.fetch(descriptor)

            let usage: DailyUsage
            if let found = existing.first {
                usage = found
                usage.inputTokens = entry.inputTokens
                usage.outputTokens = entry.outputTokens
                usage.cacheCreationTokens = entry.cacheCreationTokens
                usage.cacheReadTokens = entry.cacheReadTokens
                usage.totalTokens = entry.totalTokens
                usage.totalCost = entry.totalCost
                usage.lastUpdated = Date()

                for breakdown in usage.modelBreakdowns {
                    context.delete(breakdown)
                }
                usage.modelBreakdowns = []
            } else {
                usage = DailyUsage(
                    date: entry.date,
                    inputTokens: entry.inputTokens,
                    outputTokens: entry.outputTokens,
                    cacheCreationTokens: entry.cacheCreationTokens,
                    cacheReadTokens: entry.cacheReadTokens,
                    totalTokens: entry.totalTokens,
                    totalCost: entry.totalCost
                )
                context.insert(usage)
            }

            for mb in entry.modelBreakdowns {
                let modelUsage = ModelUsage(
                    modelName: mb.modelName,
                    inputTokens: mb.inputTokens,
                    outputTokens: mb.outputTokens,
                    cacheCreationTokens: mb.cacheCreationTokens,
                    cacheReadTokens: mb.cacheReadTokens,
                    cost: mb.cost
                )
                usage.modelBreakdowns.append(modelUsage)
            }
        }

        try context.save()
    }
}
