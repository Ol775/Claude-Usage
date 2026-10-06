# Claude Usage

A native macOS menu bar + desktop app for your Claude usage. The app lives in [`ClaudeUsage/`](ClaudeUsage).

## ClaudeUsage  (v0.8.1 alpha)

A menu bar + desktop app for your Claude usage.

- Real **session** and **weekly** limits with reset times (same numbers as Claude Code's `/usage`)
- **Forecasts** of when you'll hit a limit at your current pace – weekly forecasts also learn from your saved history – plus early-warning notifications
- **Reports**: day / week / month graphs of tokens and limit utilisation, with peaks per session and per week
- **Insights**: heavy and light days, sessions per day/week, messages, tool calls, API-equivalent cost, per-model and per-project usage, and a yearly heatmap
- Activity is saved on your Mac, so history outlives Claude Code's own log clean-up
- Light / Dark / **OLED black** / Follow system, six colour themes (Claude orange by default)
- Menu bar display options, configurable alert thresholds, CSV export, copy-summary, optional local profile photo
- Sign in/out through Claude's official login (via Claude Code)
- **Help & Legal** in Settings: terms, privacy notes and a Report a Bug button
- **Updates**: notifies when a newer version is on GitHub, and **Update Now** downloads it, builds it, swaps it in (keeping a backup) and relaunches – no Terminal needed. `./update.sh` does the same from the command line

Limits come from Claude Code's login in your own keychain; nothing is stored in this repo.
API-equivalent costs use Anthropic's published API prices and are only a guide – a Claude plan isn't billed that way.
Unofficial – not affiliated with Anthropic.

## Install

Requires macOS 13 or later and [Claude Code](https://claude.com/claude-code) signed in on the same Mac (Claude Usage reads its login and logs).

**Option 1 – DMG.** Download `Claude-Usage-<version>.dmg` from the [latest release](https://github.com/Ol775/Claude-Usage/releases/latest), open it and drag *Claude Usage* to *Applications*.

**Option 2 – Terminal.** One line; it downloads the latest DMG, installs to `/Applications` and opens the app:

```sh
curl -fsSL https://raw.githubusercontent.com/Ol775/Claude-Usage/main/install.sh | zsh
```

**Option 3 – Build from source** (needs the Xcode command line tools):

```sh
git clone https://github.com/Ol775/Claude-Usage.git
cd Claude-Usage/ClaudeUsage && ./build.sh      # then copy "Claude Usage.app" to /Applications
./make-dmg.sh                                  # optional: builds dist/Claude-Usage-<version>.dmg
```

### First launch

The app is ad-hoc signed (there's no paid Apple developer certificate), so macOS may refuse to open it the first time. Right-click the app, choose **Open**, then **Open** again. Or run:

```sh
xattr -dr com.apple.quarantine "/Applications/Claude Usage.app"
```

The terminal install does this for you.

### Updating

The app checks GitHub for new versions, downloads and builds them in the background, then asks you to restart. You can also run `./update.sh` from a clone, or just re-run the install command above.

## Reporting bugs

Use **Settings → Help & Legal → Report a Bug** in the app (it fills in your version and macOS), or [open an issue](https://github.com/Ol775/Claude-Usage/issues/new) here. Please don't paste tokens or private logs.

## Privacy and legal

Everything stays on your Mac. The app only talks to Anthropic (for your usage limits) and GitHub (for updates); there are no analytics. Limits come from Claude Code's login in your own keychain, and nothing is stored in this repo. API-equivalent costs use Anthropic's published API prices and are only a guide – a Claude plan isn't billed that way. The full terms are in the app under Settings → Help & Legal.

**Unofficial – not affiliated with or endorsed by Anthropic.** "Claude" and "Anthropic" are trademarks of Anthropic, PBC. Provided as is, with no warranty. This repository doesn't yet include an open-source licence, so all rights are reserved until one is added.
