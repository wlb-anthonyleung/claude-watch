# Plan 001 — Initial Architecture & Implementation

## Overview

A native macOS menu bar app that polls `npx ccusage` on a timer and displays Claude API usage metrics. It has two UI surfaces: a quick-glance **menu bar popover** and a full **detail window** with charts and historical data. Usage data is persisted locally via SwiftData.

---

## Project Structure

```text
ClaudeWatch/
├── ClaudeWatchApp.swift              # @main, defines 3 scenes: MenuBarExtra, Window, Settings
├── Info.plist                         # LSUIElement = YES (no dock icon)
│
├── Models/
│   ├── CCUsageResponse.swift          # Codable structs for JSON parsing (transfer objects)
│   ├── DailyUsage.swift               # SwiftData @Model — one row per date
│   └── ModelBreakdown.swift           # SwiftData @Model — one row per model per day
│
├── Services/
│   ├── CCUsageService.swift           # actor — shells out to npx ccusage, parses JSON
│   └── PollingService.swift           # @Observable — timer-based polling + SwiftData upsert
│
├── Views/
│   ├── MenuBar/
│   │   └── MenuBarPopoverView.swift   # Compact popover: today's cost, tokens, model list
│   │
│   ├── Detail/
│   │   ├── DetailWindowView.swift     # NavigationSplitView: sidebar + detail pane
│   │   ├── DailySummaryCard.swift     # Headline metrics card for selected day
│   │   ├── ModelBreakdownChart.swift  # Swift Charts — cost per model
│   │   ├── TokenCategoryChart.swift   # Swift Charts — stacked bar of token types
│   │   ├── CostHistoryChart.swift     # Swift Charts — line chart of cost over time
│   │   └── DayPickerView.swift        # Sidebar list of dates
│   │
│   └── Settings/
│       └── SettingsView.swift         # Polling interval, npx path config
│
├── Utilities/
│   ├── Formatters.swift               # Number/currency/token formatting helpers
│   └── Constants.swift                # App-wide constants
│
└── Assets.xcassets/
```

**18 files total** (16 Swift + Info.plist + asset catalog). No external dependencies.

---

## Data Layer

### JSON Parsing (CCUsageResponse.swift)

Pure `Codable` structs matching the `npx ccusage --json` output: `CCUsageResponse`, `CCDailyEntry`, `CCModelBreakdown`, `CCTotals`. These are transient transfer objects — not persisted.

### Persistence (SwiftData)

- **DailyUsage** — one row per date (unique on `date` string `YYYY-MM-DD`). Fields: all token counts, totalCost, lastUpdated. Has `@Relationship(deleteRule: .cascade)` to `[ModelUsage]`.
- **ModelUsage** — one row per model per day. Fields: modelName, token counts, cost. Inverse relationship to `DailyUsage`.

Upsert strategy: on each poll, fetch by date. If exists, update fields and replace model breakdowns. If not, insert new.

### CCUsageService (actor)

- Runs `npx ccusage --json --since <date> --offline` via Foundation `Process`.
- Augments `PATH` with `/opt/homebrew/bin` and `/usr/local/bin` (GUI apps don't inherit shell PATH).
- Returns parsed `CCUsageResponse`.
- The npx path is configurable via Settings.

---

## Polling

- **PollingService** (`@Observable`) owns a repeating `Timer`.
- On launch + every N minutes (default 5), it calls `CCUsageService` and upserts results.
- Each poll fetches the last 7 days to keep recent history fresh.
- Exposes `isPolling`, `lastPollTime`, `lastError` for UI binding.
- Interval is configurable and changeable at runtime.

---

## UI

### Menu Bar Popover (~280pt wide)

- Today's total cost (large, prominent)
- Total tokens (formatted, e.g. "51.9M")
- Per-model mini list (model name + cost)
- Last updated timestamp + polling status
- Buttons: Refresh Now, Show Details, Settings, Quit

### Detail Window (NavigationSplitView)

- **Sidebar**: Date list with cost badges (last 30+ days)
- **Detail pane** for selected date:
  - `DailySummaryCard` — headline metrics
  - `ModelBreakdownChart` — pie/bar chart of cost by model (Swift Charts)
  - `TokenCategoryChart` — stacked bar of input/output/cache-create/cache-read
  - `CostHistoryChart` — line chart of cost trend over time

### Settings (macOS Settings window)

- Polling interval stepper (1–60 min)
- npx path override text field
- Uses `@AppStorage` for persistence

---

## App Lifecycle

1. Launch as `LSUIElement` agent (no Dock icon).
2. `MenuBarExtra` icon appears in menu bar.
3. `.task` triggers `pollingService.startPolling()` — immediate fetch + timer.
4. Clicking menu bar icon opens popover with today's summary.
5. "Show Details" calls `NSApp.activate(ignoringOtherApps: true)` + `openWindow(id:)`.
6. Closing detail window returns to menu-bar-only mode.
7. "Quit" calls `NSApplication.shared.terminate(nil)`.

---

## Implementation Phases

### Phase 1 — Foundation
1. Create Xcode project (macOS App, SwiftUI, SwiftData, target macOS 15).
2. `Constants.swift`, `Formatters.swift`
3. `CCUsageResponse.swift` (Codable structs)
4. `DailyUsage.swift`, `ModelBreakdown.swift` (SwiftData models)
5. `CCUsageService.swift` (actor, shell out to npx)
6. `ClaudeWatchApp.swift` with `MenuBarExtra` placeholder + `Info.plist`

### Phase 2 — Polling + Persistence
7. `PollingService.swift` — timer, upsert logic
8. Wire into app, verify data flows into SwiftData

### Phase 3 — Popover UI
9. `MenuBarPopoverView.swift` — today's summary with real data

### Phase 4 — Detail Window
10. `DetailWindowView.swift` (NavigationSplitView shell)
11. `DayPickerView.swift` (sidebar)
12. `DailySummaryCard.swift`
13. `ModelBreakdownChart.swift`
14. `TokenCategoryChart.swift`
15. `CostHistoryChart.swift`

### Phase 5 — Settings + Polish
16. `SettingsView.swift`
17. Wire all buttons (Show Details, Settings, Quit)
18. Full lifecycle test

---

## Verification

1. Build and run in Xcode — menu bar icon appears, no Dock icon.
2. Check Console/logs — first poll runs immediately, JSON is parsed, SwiftData records created.
3. Click menu bar icon — popover shows today's cost and token counts.
4. Click "Show Details" — detail window opens in foreground with sidebar and charts.
5. Wait 5 minutes (or change interval to 1 min in Settings) — data refreshes automatically.
6. Click "Refresh Now" — immediate poll, UI updates.
7. Quit and relaunch — historical data persists from SwiftData.

---

## Key Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| npx not found in GUI context | Augment PATH explicitly; expose npx path in Settings |
| Detail window behind other apps | `NSApp.activate(ignoringOtherApps: true)` before `openWindow` |
| No data on first launch | Placeholder text in views; immediate poll on startup |
| ccusage slow or failing | `--offline` flag; error display in UI; manual retry button |
