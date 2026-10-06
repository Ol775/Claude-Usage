# MacApps

Small native macOS apps.

## ClaudeUsageBar

Menu bar app showing Claude usage: current session and weekly limits (with reset times),
token totals, 14-day and hourly charts, and notifications at 80/95/100%.

Build: `cd ClaudeUsageBar && ./build.sh`, then copy `ClaudeUsageBar.app` to `/Applications`.

Limits come from Claude Code's login in your own keychain; nothing is stored in this repo.
