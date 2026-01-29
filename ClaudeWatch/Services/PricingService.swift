import Foundation

/// Fetches and caches model pricing data from LiteLLM.
actor PricingService {
    private var pricing: [String: ModelPricing] = [:]
    private var lastFetch: Date?
    private let cacheURL: URL
    private let liteLLMURL = URL(
        string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
    )!

    /// How often to refresh pricing (24 hours)
    private let refreshInterval: TimeInterval = 24 * 60 * 60

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("ClaudeWatch", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        self.cacheURL = appDir.appendingPathComponent("pricing.json")
    }

    // MARK: - Public API

    /// Get pricing, fetching if needed.
    func getPricing() async throws -> [String: ModelPricing] {
        // Return cached if fresh
        if let lastFetch, Date().timeIntervalSince(lastFetch) < refreshInterval, !pricing.isEmpty {
            return pricing
        }

        // Try to load from cache first
        if pricing.isEmpty {
            loadFromCache()
        }

        // Fetch fresh in background if stale
        if lastFetch == nil || Date().timeIntervalSince(lastFetch!) >= refreshInterval {
            do {
                try await fetchFromLiteLLM()
            } catch {
                // If fetch fails but we have cached data, use it
                if !pricing.isEmpty {
                    print("Failed to fetch pricing, using cache: \(error)")
                } else {
                    // Load bundled fallback
                    loadBundledFallback()
                }
            }
        }

        return pricing
    }

    /// Calculate cost for a given model and token usage.
    func calculateCost(model: String, usage: TokenUsage) async -> Double {
        let pricing = (try? await getPricing()) ?? [:]
        guard let modelPricing = resolveModelPricing(model: model, from: pricing) else {
            // Fallback to default Sonnet pricing if model not found
            return calculateWithDefaultPricing(usage: usage)
        }

        return calculateCostWithPricing(usage: usage, pricing: modelPricing)
    }

    // MARK: - Pricing Calculation

    private func calculateCostWithPricing(usage: TokenUsage, pricing: ModelPricing) -> Double {
        var cost = 0.0

        // Input tokens
        cost += Double(usage.inputTokens) * pricing.inputCostPerToken

        // Output tokens
        cost += Double(usage.outputTokens) * pricing.outputCostPerToken

        // Cache creation tokens
        if let cacheCreateCost = pricing.cacheCreationCostPerToken {
            cost += Double(usage.cacheCreationTokens) * cacheCreateCost
        }

        // Cache read tokens
        if let cacheReadCost = pricing.cacheReadCostPerToken {
            cost += Double(usage.cacheReadTokens) * cacheReadCost
        }

        return cost
    }

    private func calculateWithDefaultPricing(usage: TokenUsage) -> Double {
        // Default to Claude Sonnet pricing
        let inputRate = 3e-6
        let outputRate = 15e-6
        let cacheCreateRate = 3.75e-6
        let cacheReadRate = 0.3e-6

        return Double(usage.inputTokens) * inputRate
            + Double(usage.outputTokens) * outputRate
            + Double(usage.cacheCreationTokens) * cacheCreateRate
            + Double(usage.cacheReadTokens) * cacheReadRate
    }

    // MARK: - Model Resolution

    private func resolveModelPricing(model: String, from pricing: [String: ModelPricing]) -> ModelPricing? {
        // Try exact match first
        if let match = pricing[model] {
            return match
        }

        // Try with anthropic prefix
        if let match = pricing["anthropic/\(model)"] {
            return match
        }

        // Try stripping provider prefix
        let stripped = model
            .replacingOccurrences(of: "anthropic/", with: "")
            .replacingOccurrences(of: "anthropic.", with: "")

        if let match = pricing[stripped] {
            return match
        }

        // Try common variations
        let variations = generateModelVariations(model)
        for variation in variations {
            if let match = pricing[variation] {
                return match
            }
        }

        return nil
    }

    private func generateModelVariations(_ model: String) -> [String] {
        var variations: [String] = []
        let base = model
            .replacingOccurrences(of: "anthropic/", with: "")
            .replacingOccurrences(of: "anthropic.", with: "")

        // Add base
        variations.append(base)

        // Add with anthropic prefix
        variations.append("anthropic/\(base)")
        variations.append("anthropic.\(base)")

        // Try bedrock format
        if !base.contains("-v1:0") && !base.contains("-v2:0") {
            variations.append("anthropic.\(base)-v1:0")
            variations.append("anthropic.\(base)-v2:0")
        }

        return variations
    }

    // MARK: - Fetch & Cache

    private func fetchFromLiteLLM() async throws {
        let (data, _) = try await URLSession.shared.data(from: liteLLMURL)
        try parsePricingData(data)
        saveToCache(data)
        lastFetch = Date()
    }

    private func parsePricingData(_ data: Data) throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PricingError.invalidFormat
        }

        var newPricing: [String: ModelPricing] = [:]

        for (modelName, value) in json {
            // Only process Claude/Anthropic models
            guard modelName.lowercased().contains("claude") ||
                  modelName.lowercased().contains("anthropic") else {
                continue
            }

            guard let modelData = value as? [String: Any] else {
                continue
            }

            // Extract pricing fields
            guard let inputCost = modelData["input_cost_per_token"] as? Double,
                  let outputCost = modelData["output_cost_per_token"] as? Double else {
                continue
            }

            let pricing = ModelPricing(
                inputCostPerToken: inputCost,
                outputCostPerToken: outputCost,
                cacheCreationCostPerToken: modelData["cache_creation_input_token_cost"] as? Double,
                cacheReadCostPerToken: modelData["cache_read_input_token_cost"] as? Double,
                inputCostAbove200k: modelData["input_cost_per_token_above_200k_tokens"] as? Double,
                outputCostAbove200k: modelData["output_cost_per_token_above_200k_tokens"] as? Double
            )

            newPricing[modelName] = pricing
        }

        self.pricing = newPricing
    }

    private func loadFromCache() {
        guard FileManager.default.fileExists(atPath: cacheURL.path),
              let data = try? Data(contentsOf: cacheURL) else {
            return
        }

        do {
            try parsePricingData(data)
            // Set lastFetch to file modification date
            if let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
               let modDate = attrs[.modificationDate] as? Date {
                lastFetch = modDate
            }
        } catch {
            print("Failed to load pricing cache: \(error)")
        }
    }

    private func saveToCache(_ data: Data) {
        do {
            try data.write(to: cacheURL)
        } catch {
            print("Failed to save pricing cache: \(error)")
        }
    }

    private func loadBundledFallback() {
        // Hardcoded fallback pricing for common models
        pricing = [
            "claude-sonnet-4-20250514": ModelPricing(
                inputCostPerToken: 3e-6,
                outputCostPerToken: 15e-6,
                cacheCreationCostPerToken: 3.75e-6,
                cacheReadCostPerToken: 0.3e-6,
                inputCostAbove200k: 6e-6,
                outputCostAbove200k: 30e-6
            ),
            "claude-opus-4-5-20251101": ModelPricing(
                inputCostPerToken: 5e-6,
                outputCostPerToken: 25e-6,
                cacheCreationCostPerToken: 6.25e-6,
                cacheReadCostPerToken: 0.5e-6,
                inputCostAbove200k: nil,
                outputCostAbove200k: nil
            ),
            "claude-3-5-sonnet-20241022": ModelPricing(
                inputCostPerToken: 3e-6,
                outputCostPerToken: 15e-6,
                cacheCreationCostPerToken: 3.75e-6,
                cacheReadCostPerToken: 0.3e-6,
                inputCostAbove200k: nil,
                outputCostAbove200k: nil
            )
        ]
        lastFetch = Date.distantPast
    }

    // MARK: - Types

    enum PricingError: Error {
        case invalidFormat
        case networkError(Error)
    }
}

// MARK: - Supporting Types

struct ModelPricing: Codable {
    let inputCostPerToken: Double
    let outputCostPerToken: Double
    let cacheCreationCostPerToken: Double?
    let cacheReadCostPerToken: Double?
    let inputCostAbove200k: Double?
    let outputCostAbove200k: Double?
}

struct TokenUsage {
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }
}
