# MacApps

Small native macOS apps.

## ClaudeUsageBar  (v0.1.0 alpha)

Menu bar + desktop app for your Claude usage.

- Real **session** and **weekly** limits with reset times (same numbers as Claude Code's `/usage`)
- **Forecasts** of when you'll hit a limit at your current pace, plus early-warning notifications
- Dashboard with charts: limit forecast, 30-day tokens, hourly, per-model, token breakdown
- Light / Dark / Follow system, six colour themes (Claude orange by default)
- Optional local profile photo; sign in/out through Claude's official login (via Claude Code)

Build: `cd ClaudeUsageBar && ./build.sh`, then copy `ClaudeUsageBar.app` to `/Applications`.
Requires macOS 13+ and the Xcode command line tools. Version lives in `ClaudeUsageBar/VERSION`.

Limits come from Claude Code's login in your own keychain; nothing is stored in this repo.
Unofficial – not affiliated with Anthropic.
