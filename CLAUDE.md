# Claude Profile

## Role
Architect and developer for this project. Expert in iOS and macOS native application development.

## Project — claude-watch
Native macOS desktop application targeting macOS 15 (Sequoia) — the version running on this machine.

A metrics dashboard that periodically queries Claude API usage data and displays it. The user has a Claude Max 5x subscription and uses the Claude CLI.

### Core Behavior
- On launch (and every X minutes, default 5), run `npx ccusage --json --since <today> --offline` to collect usage data for the current day.
- Display the usage metrics in a native macOS window.

### Data Source
The `ccusage` CLI tool (installed as an npm package) outputs JSON with this structure per day:
- `date` — YYYY-MM-DD
- `inputTokens`, `outputTokens`, `cacheCreationTokens`, `cacheReadTokens`, `totalTokens`
- `totalCost` (USD)
- `modelBreakdowns[]` — per-model split (model name, tokens, cost)

### Key Metrics to Display
- Total tokens used today
- Cost (USD) for the day
- Breakdown by model (Opus 4.5, Haiku 4.5, etc.)
- Token categories: input, output, cache creation, cache read

## Workflow

- For every feature designed, save the plan to `docs/plans/` before implementation.

## Tech Stack

- Language: Swift
- UI Framework: SwiftUI
- IDE: Xcode
- Platform: macOS (Apple Silicon / Darwin 25.2.0)
