# Claude Watch

**Your Claude usage, always visible. Never wonder about costs again.**

Claude Watch is a native macOS menu bar app that gives you instant visibility into your **Claude Code** usage. Whether you're on a Max subscription or pay-as-you-go, Claude Watch keeps you informed with real-time cost tracking, usage trends, and detailed breakdowns—all accessible with a single click from your menu bar.

> **Note**: Claude Watch tracks usage from [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (the CLI tool) only. It reads local conversation logs from `~/.claude/` — no external dependencies required. Usage from claude.ai or the Claude desktop app is not tracked.

## Why Claude Watch?

- **Instant Visibility** — See today's cost and token usage at a glance, right from your menu bar
- **Track Spending Trends** — 14-day trendline with moving average shows if usage is going up or down
- **Understand Your Usage** — Break down costs by model, session, and hour of day
- **Compare to Yesterday** — Know immediately if you're spending more or less than usual
- **Works Offline** — Data is cached locally, so you can review history anytime
- **Privacy First** — All data stays on your Mac. No accounts, no cloud sync, no tracking
- **Zero Dependencies** — No Node.js, npm, or external CLI tools required

---

## For Users

### Installation

#### Requirements

- macOS 15 (Sequoia) or later
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed and used at least once

That's it! No additional dependencies needed.

#### Install Claude Watch

Download the latest release from the [Releases](https://github.com/wlb-anthonyleung/claude-watch/releases) page, or build from source (see Developer section).

### Getting Started

1. **Launch Claude Watch** — The app runs in your menu bar (no Dock icon)
2. **Click the chart icon** — Opens a popover with today's summary
3. **View Details** — Click "Details" to open the full analytics window
4. **Configure** — Adjust polling interval in Settings

### Features

#### Menu Bar Popover

- Today's total cost with comparison to yesterday (↑/↓ percentage)
- Total tokens used
- Cost breakdown by model
- Quick access to details, settings, and refresh

#### Overview Dashboard

- **14-Day Trend** — Line chart with 3-day moving average
- **Monthly View** — Switch between months to compare usage
- **Daily Cost Chart** — Stacked or grouped view by model
- **Usage Table** — Detailed daily breakdown matching ccusage CLI format
- **Hover for Details** — See exact tokens and cost per model
- **Click to Drill Down** — Click any day to see detailed breakdown
- **Export Data** — Export to CSV or Excel (XLSX) format

#### Day Detail View

- Summary card with all token categories
- Cost breakdown by model (pie chart)
- Token breakdown (input, output, cache creation, cache read)
- Session breakdown — see which projects used the most
- Hourly usage chart — understand your usage patterns

### Settings

| Setting          | Description                   | Default   |
|------------------|-------------------------------|-----------|
| Polling Interval | How often to fetch fresh data | 5 minutes |

---

## For Developers

### Tech Stack

- **Swift 6** with strict concurrency
- **SwiftUI** for all UI
- **SwiftData** for local persistence
- **Swift Charts** for visualizations
- **macOS 15+** (Sequoia)

### Project Structure

```text
ClaudeWatch/
├── ClaudeWatchApp.swift          # App entry point, scenes
├── Models/                       # SwiftData models
│   ├── DailyUsage.swift         # Daily aggregate data
│   ├── ModelUsage.swift         # Per-model breakdown
│   ├── SessionUsage.swift       # Per-session breakdown (cached)
│   └── CCUsageResponse.swift    # Internal data transfer structs
├── Services/
│   ├── CCUsageService.swift     # Aggregates data from ConversationService
│   ├── ConversationService.swift # Parses local JSONL files
│   ├── ExportService.swift      # CSV and XLSX export
│   ├── PricingService.swift     # Fetches/caches model pricing
│   └── PollingService.swift     # Timer-based polling
├── Views/
│   ├── MenuBar/                 # Menu bar popover
│   ├── Detail/                  # Main window views
│   └── Settings/                # Settings view
└── Utilities/
    ├── Formatters.swift         # Number/date formatting
    └── Constants.swift          # App constants
```

### Building from Source

#### Prerequisites

- Xcode 16 or later
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (optional, for regenerating project)

#### Build Steps

```bash
# Clone the repository
git clone https://github.com/wlb-anthonyleung/claude-watch.git
cd claude-watch

# Open in Xcode
open ClaudeWatch.xcodeproj

# Or build from command line
xcodebuild -scheme ClaudeWatch -configuration Release build
```

#### Regenerating the Xcode Project

If you modify `project.yml`:

```bash
xcodegen generate
```

### Architecture Highlights

#### Data Flow

1. **PollingService** triggers data refresh on a timer
2. **ConversationService** parses JSONL files from `~/.claude/`
3. **PricingService** calculates costs using LiteLLM pricing data
4. **CCUsageService** aggregates and formats the data
5. **PollingService** upserts data into SwiftData
6. **Views** query SwiftData and display charts

#### Caching Strategy

- **Daily data**: Fetched via polling, stored in `DailyUsage`
- **Session data**: Fetched on-demand, cached in `SessionUsage` for past days
- **Hourly data**: Parsed from local `~/.claude` JSONL files
- **Pricing data**: Cached locally, refreshed daily from LiteLLM

#### Menu Bar App Lifecycle

- Runs as `LSUIElement` (no Dock icon)
- Uses `MenuBarExtra` with `.window` style for rich popover
- Detail window uses `setActivationPolicy(.regular)` for Cmd+Tab support

---

## For Contributors

We welcome contributions! Here's how to get started.

### Development Setup

1. Fork the repository
2. Clone your fork
3. Open in Xcode and build
4. Make your changes on a feature branch

### Code Style

- Follow Swift API Design Guidelines
- Use `// MARK: -` for section organization
- Keep views focused and extract subviews when they grow
- Use `@Observable` for observable state (not `ObservableObject`)
- Prefer `actor` for thread-safe services

### Testing Changes

1. Build and run the app
2. Verify menu bar icon appears
3. Test popover opens with correct data
4. Test detail window opens and all charts render
5. Test settings changes take effect

### Submitting Changes

1. Create a feature branch: `git checkout -b feature/your-feature`
2. Make your changes with clear commit messages
3. Push to your fork: `git push origin feature/your-feature`
4. Open a Pull Request with:
   - Clear description of changes
   - Screenshots for UI changes
   - Any testing notes

### Areas for Contribution

- **New Charts** — Additional visualizations for usage data
- **Notifications** — Alerts when spending exceeds thresholds
- **Widgets** — macOS widgets for quick stats
- **Localization** — Translations for other languages

### Reporting Issues

Please include:

- macOS version
- Steps to reproduce
- Expected vs actual behavior
- Console logs if applicable

---

## Privacy

Claude Watch respects your privacy:

- **No accounts required** — Just install and use
- **No cloud sync** — All data stored locally in SwiftData
- **No analytics** — We don't track anything
- **Minimal network** — Only fetches pricing data from LiteLLM (public, no auth)
- **Open source** — Audit the code yourself

---

## License

MIT License. See [LICENSE](LICENSE) for details.

---

## Acknowledgments

- [LiteLLM](https://github.com/BerriAI/litellm) — For maintaining public model pricing data
- [Anthropic](https://anthropic.com) — For building Claude

---

Made with Claude Code
