# Plan 002 — Enhancements Beyond Initial Implementation

This document describes features and improvements added after the initial architecture (Plan 001) was implemented.

---

## Summary of Enhancements

| Category | Feature |
|----------|---------|
| Menu Bar Popover | Comparison to yesterday with arrow + percentage |
| Overview | Month-based filtering with navigation |
| Overview | Hover tooltips on bar charts |
| Overview | Click-to-navigate from chart to day detail |
| Overview | 14-day trendline with 3-day moving average |
| Day Detail | Session breakdown view |
| Day Detail | Hourly usage breakdown chart |
| Data Layer | Session data caching in SwiftData |
| UX | Cmd+Tab support via activation policy switching |
| Performance | Polling only on startup + interval (not on popover open) |

---

## 1. Menu Bar Popover Enhancements

### Comparison to Yesterday
- Shows percentage change from yesterday's cost
- Visual indicator: `↑ 45%` (red) or `↓ 23%` (green)
- Calculation: `((today - yesterday) / yesterday) * 100`

---

## 2. Overview Screen Enhancements

### Month-Based Filtering
- Replaced "last 31 days" with month selector
- Navigation arrows to move between months
- Defaults to current month on launch

### Interactive Bar Charts
- **Hover tooltips**: Shows tokens and cost per model for hovered date
- **Click-to-navigate**: Clicking a bar navigates to that day's detail view
- Legend moved above chart for better visibility
- X-axis date format: `dd-MM`

### 14-Day Trendline
- Line chart showing daily cost over last 14 days
- Area fill beneath the line for visual weight
- Point markers for each day

### 3-Day Moving Average
- Smooths daily volatility to show underlying trend
- Displayed as orange dashed line overlay
- Custom legend showing both Daily and 3-Day Avg series

---

## 3. Day Detail View Enhancements

### Session Breakdown
- Shows usage broken down by Claude Code session
- Displays: session name, cost, token counts (in/out/cache), models used
- Sorted by cost (highest first)

### Hourly Usage Chart
- Bar chart showing token usage by hour of day
- Data sourced from local `~/.claude` JSONL files via `ConversationService`

---

## 4. Data Layer Enhancements

### Session Data Caching
New SwiftData model: `SessionUsage`

```text
SessionUsage
├── sessionId: String
├── inputTokens, outputTokens, cacheCreationTokens, cacheReadTokens: Int
├── totalTokens: Int
├── totalCost: Double
├── lastActivity: String
├── modelsUsed: [String]
├── projectPath: String?
└── dailyUsage: DailyUsage? (inverse relationship)
```

**Caching Strategy**:
- **Past days**: Fetch once from `npx ccusage session`, cache in SwiftData, reuse on subsequent views
- **Today**: Always fetch fresh data (still accumulating)
- Falls back to cached data if fetch fails

### Reduced npx Dependency
- Session data cached locally after first fetch
- Hourly data read directly from local JSONL files (no npx call needed)
- Daily aggregate data still fetched via polling

---

## 5. UX Improvements

### Cmd+Tab Support
- Detail window sets `NSApp.setActivationPolicy(.regular)` on appear
- Reverts to `.accessory` on disappear
- Allows switching back to detail window via Cmd+Tab

### Polling Optimization
- Polling starts once at app launch (in `ClaudeWatchApp.init`)
- Removed `.task` trigger from popover view
- Added `hasStarted` guard to prevent duplicate polling
- Opening menu bar popover no longer triggers refresh

---

## 6. New Files Added

| File | Purpose |
|------|---------|
| `SessionUsage.swift` | SwiftData model for cached session data |
| `SessionBreakdownView.swift` | View showing session-level usage breakdown |
| `HourlyBreakdownChart.swift` | Bar chart of hourly token usage |
| `DayDetailView.swift` | Wrapper view that loads session + hourly data |
| `ConversationService.swift` | Parses local JSONL files for hourly data |

---

## 7. Modified Files

| File | Changes |
|------|---------|
| `DailyUsage.swift` | Added `sessions: [SessionUsage]` relationship |
| `CCUsageResponse.swift` | Added `CCSessionResponse`, `CCSessionEntry` types |
| `CCUsageService.swift` | Added `fetchSessions(for:)` method |
| `OverviewView.swift` | Month picker, trendline, moving average, tooltips, click navigation |
| `MenuBarPopoverView.swift` | Yesterday comparison, removed polling trigger |
| `PollingService.swift` | Added `hasStarted` guard |
| `ClaudeWatchApp.swift` | Added `SessionUsage` to ModelContainer, start polling in init |
| `DetailWindowView.swift` | Pass `ccUsageService` to `DayDetailView`, activation policy |

---

## 8. Architecture Decisions

### SessionDisplayData Pattern
Created a display struct that both `CCSessionEntry` (from API) and `SessionUsage` (from cache) can convert to:

```swift
struct SessionDisplayData: Identifiable {
    init(from entry: CCSessionEntry) { ... }
    init(from usage: SessionUsage) { ... }
}
```

This allows `SessionBreakdownView` to work with either fresh or cached data without knowing the source.

### Hourly Data from Local Files
Rather than adding another `npx ccusage` command, hourly data is parsed directly from Claude's local JSONL conversation logs. This:
- Avoids additional subprocess overhead
- Works offline
- Provides more granular data than the ccusage CLI exposes
