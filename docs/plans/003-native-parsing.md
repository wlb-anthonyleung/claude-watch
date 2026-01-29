# Plan 003 — Native JSONL Parsing (Remove npx ccusage Dependency)

## Goal

Replace the `npx ccusage` CLI dependency with native Swift parsing. This eliminates the requirement for users to have Node.js installed.

---

## Feasibility Assessment

**Verdict: Highly Feasible**

The ccusage CLI is essentially a JSONL parser with pricing lookup. We already have partial parsing in `ConversationService.swift` for hourly data. Extending this to full daily/session aggregation is straightforward.

| Component | Complexity | Notes |
|-----------|------------|-------|
| JSONL parsing | Low | Already implemented |
| Token extraction | Low | Already implemented |
| Daily aggregation | Low | Sum tokens by date |
| Session aggregation | Medium | 5-hour gap detection logic |
| Pricing calculation | Medium | Fetch/cache LiteLLM data |
| Model name resolution | Low | Simple mapping |

---

## What ccusage Does

### 1. Data Source

Reads JSONL files from:
- `~/.claude/projects/[project-path]/[session-id]/*.jsonl`
- `~/.claude/projects/[project-path]/[session-id]/subagents/*.jsonl`

### 2. JSONL Entry Structure

```json
{
  "type": "assistant",
  "timestamp": "2026-01-24T21:30:46.036Z",
  "sessionId": "uuid",
  "message": {
    "model": "claude-sonnet-4-20250514",
    "usage": {
      "input_tokens": 15000,
      "output_tokens": 500,
      "cache_creation_input_tokens": 0,
      "cache_read_input_tokens": 12000
    }
  }
}
```

Only `type: "assistant"` entries contain usage data.

### 3. Pricing Source

Fetches from LiteLLM's public GitHub:
```
https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json
```

Example pricing entry:
```json
{
  "claude-sonnet-4-20250514": {
    "input_cost_per_token": 3e-6,
    "output_cost_per_token": 15e-6,
    "cache_creation_input_token_cost": 3.75e-6,
    "cache_read_input_token_cost": 0.3e-6
  }
}
```

### 4. Cost Calculation

```
cost = (input_tokens × input_rate)
     + (output_tokens × output_rate)
     + (cache_creation_tokens × cache_creation_rate)
     + (cache_read_tokens × cache_read_rate)
```

### 5. Session Detection

Uses 5-hour billing windows:
- Gap > 5 hours between entries = new session block
- Block start times floored to hour boundary

---

## Implementation Plan

### Phase 1 — Pricing Engine

**New file: `Services/PricingService.swift`**

```swift
actor PricingService {
    private var pricing: [String: ModelPricing] = [:]
    private var lastFetch: Date?

    struct ModelPricing: Codable {
        let inputCostPerToken: Double
        let outputCostPerToken: Double
        let cacheCreationCostPerToken: Double
        let cacheReadCostPerToken: Double
    }

    func fetchPricing() async throws
    func calculateCost(model: String, usage: TokenUsage) -> Double
    func loadCachedPricing() // From UserDefaults or file
    func savePricingCache()
}
```

**Tasks:**
1. Fetch LiteLLM JSON on first launch / daily refresh
2. Parse into `[String: ModelPricing]` dictionary
3. Cache locally for offline use
4. Model name normalization (strip `anthropic/` prefix, handle aliases)

### Phase 2 — Enhanced JSONL Parser

**Modify: `Services/ConversationService.swift`**

Add new methods:
```swift
func fetchDailyUsage(since: Date) async -> [ParsedDailyUsage]
func fetchSessionUsage(for date: Date) async -> [ParsedSessionUsage]
```

**New model: `Models/ParsedUsage.swift`**

```swift
struct ParsedDailyUsage {
    let date: String  // yyyy-MM-dd
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    var totalCost: Double  // Calculated via PricingService
    let modelBreakdowns: [ParsedModelBreakdown]
}

struct ParsedModelBreakdown {
    let modelName: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    var cost: Double
}

struct ParsedSessionUsage {
    let sessionId: String
    let projectPath: String
    let startTime: Date
    let endTime: Date
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    var totalCost: Double
    let modelsUsed: [String]
}
```

**Tasks:**
1. Enumerate all project directories
2. Parse all JSONL files (skip non-assistant entries)
3. Aggregate by date and model
4. Detect session blocks (5-hour gaps)

### Phase 3 — Replace CCUsageService

**Modify: `Services/CCUsageService.swift`**

Replace shell-out logic with native parsing:

```swift
actor CCUsageService {
    private let conversationService: ConversationService
    private let pricingService: PricingService

    func fetchUsage(since: Date) async throws -> CCUsageResponse {
        let dailyUsage = await conversationService.fetchDailyUsage(since: since)
        let pricing = try await pricingService.getPricing()

        // Apply pricing to calculate costs
        // Convert to CCUsageResponse format for compatibility
    }

    func fetchSessions(for date: Date) async throws -> CCSessionResponse {
        let sessions = await conversationService.fetchSessionUsage(for: date)
        // Convert to CCSessionResponse format
    }
}
```

### Phase 4 — Remove npx Dependency

**Delete:**
- npx path setting from `SettingsView.swift`
- `npxPath` from `AppConstants.swift`
- Shell execution code from `CCUsageService.swift`

**Update:**
- README.md — remove ccusage installation requirement
- Settings UI — remove npx path field

---

## File Changes Summary

| File | Action | Description |
|------|--------|-------------|
| `Services/PricingService.swift` | **NEW** | Fetch/cache LiteLLM pricing |
| `Models/ParsedUsage.swift` | **NEW** | Native parsed data structs |
| `Services/ConversationService.swift` | **MODIFY** | Add daily/session parsing |
| `Services/CCUsageService.swift` | **MODIFY** | Replace shell-out with native |
| `Views/Settings/SettingsView.swift` | **MODIFY** | Remove npx path setting |
| `Utilities/Constants.swift` | **MODIFY** | Remove npx constants |
| `README.md` | **MODIFY** | Remove ccusage requirement |

---

## Pricing Cache Strategy

1. **On first launch**: Fetch from LiteLLM, cache to `~/Library/Application Support/ClaudeWatch/pricing.json`
2. **On subsequent launches**: Load from cache, fetch in background if stale (> 24 hours)
3. **Offline fallback**: Bundle a snapshot of pricing data in the app
4. **Manual refresh**: Add "Refresh Pricing" button in Settings

---

## Session Block Algorithm

```swift
func detectSessionBlocks(entries: [JournalEntry]) -> [SessionBlock] {
    let sorted = entries.sorted { $0.timestamp < $1.timestamp }
    var blocks: [SessionBlock] = []
    var currentBlock: SessionBlock?
    let fiveHours: TimeInterval = 5 * 60 * 60

    for entry in sorted {
        if let block = currentBlock {
            let gap = entry.timestamp.timeIntervalSince(block.endTime)
            if gap > fiveHours {
                blocks.append(block)
                currentBlock = SessionBlock(start: entry.timestamp.flooredToHour())
            }
            currentBlock?.add(entry)
        } else {
            currentBlock = SessionBlock(start: entry.timestamp.flooredToHour())
            currentBlock?.add(entry)
        }
    }

    if let block = currentBlock {
        blocks.append(block)
    }

    return blocks
}
```

---

## Model Name Resolution

ccusage handles various model name formats:
- `claude-sonnet-4-20250514`
- `anthropic/claude-sonnet-4-20250514`
- `claude-3-5-sonnet-20241022`

Strategy:
1. Try exact match in pricing dictionary
2. Strip provider prefix (`anthropic/`, `openai/`)
3. Try common aliases
4. Fall back to default Sonnet pricing

---

## Migration Path

To ensure smooth transition:

1. **Phase 1-2**: Implement native parsing alongside existing ccusage
2. **Add feature flag**: `useNativeParsing` in Settings (default: false)
3. **Testing**: Compare native vs ccusage output for accuracy
4. **Phase 3-4**: Once validated, remove ccusage dependency
5. **Release**: Ship with native parsing as default

---

## Benefits

| Before (ccusage) | After (Native) |
|------------------|----------------|
| Requires Node.js + npm | No dependencies |
| Shell subprocess overhead | Direct file access |
| External CLI updates | Self-contained |
| ~100ms per call | ~10ms per call |
| Network for install | Offline capable |

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Pricing data outdated | Bundle fallback + background refresh |
| JSONL format changes | Version detection + graceful fallback |
| Different results than ccusage | Extensive comparison testing |
| Missing edge cases | Study ccusage source thoroughly |

---

## Estimated Effort

| Phase | Scope |
|-------|-------|
| Phase 1 | PricingService — fetch, cache, calculate |
| Phase 2 | Enhanced JSONL parsing — daily, session, model |
| Phase 3 | CCUsageService refactor — use native parsing |
| Phase 4 | Cleanup — remove npx, update docs |

---

## Verification

1. Compare native output to `npx ccusage --json` for same date range
2. Verify daily totals match within $0.01
3. Verify session detection produces same blocks
4. Test offline mode (no network)
5. Test with fresh install (no pricing cache)
6. Test with large history (1000+ JSONL entries)
