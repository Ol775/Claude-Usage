# MacApps

Small native macOS apps.

## ClaudeUsage  (v0.4.0 alpha)

A menu bar + desktop app for your Claude usage.

- Real **session** and **weekly** limits with reset times (same numbers as Claude Code's `/usage`)
- **Forecasts** of when you'll hit a limit at your current pace – weekly forecasts also learn from your saved history – plus early-warning notifications
- **Reports**: day / week / month graphs of tokens and limit utilisation, with peaks per session and per week
- **Insights**: heavy and light days, sessions per day/week, messages, tool calls, API-equivalent cost, per-model and per-project usage, and a yearly heatmap
- Activity is saved on your Mac, so history outlives Claude Code's own log clean-up
- Light / Dark / **OLED black** / Follow system, six colour themes (Claude orange by default)
- Menu bar display options, configurable alert thresholds, CSV export, copy-summary, optional local profile photo
- Sign in/out through Claude's official login (via Claude Code)

Build: `cd ClaudeUsage && ./build.sh`, then copy `Claude Usage.app` to `/Applications`.
Requires macOS 13+ and the Xcode command line tools. The version lives in `ClaudeUsage/VERSION`.

Limits come from Claude Code's login in your own keychain; nothing is stored in this repo.
API-equivalent costs use Anthropic's published API prices and are only a guide – a Claude plan isn't billed that way.
Unofficial – not affiliated with Anthropic.
