# Changelog

Versions follow `MAJOR.MINOR.PATCH` and are currently **alpha**. Bump `VERSION` (use `./bump.sh`) with every change:
**minor** for new features, **patch** for fixes and polish. The build number is the git commit count and rises automatically.

## 0.9.12 – alpha (2026-10-06)
- Diagnostics now include a few yes/no states (Claude Code found/signed in, which limits were read and why a fetch failed, update state, notifications, ChatGPT on/off and paid/free) and Settings → Help & Legal can preview exactly what is included before you copy it or report a bug. Nothing includes account details, file paths or usage numbers

## 0.9.11 – alpha (2026-10-06)
- Updates now show a progress bar for download, verification and install (in Settings → About, above every page and in the menu); copies that can't replace themselves (run from a disk image or a read-only folder) get a Download Update button that saves the verified installer to Downloads, with its own progress bar

## 0.9.10 – alpha (2026-10-06)
- Security hardening from an independent review: updates must carry a valid offline Ed25519 signature plus checksum (a hijacked GitHub account can no longer push an update), the source-build fallback and GitHub CLI use are gone, update downloads are validated and re-checked before install, only safely-owned claude/codex programs are run, app data folders are private, developer overrides are ignored in the shipped app. Added SECURITY.md

## 0.9.9 – alpha (2026-10-06)
- Self-tests now also cover Claude Code log parsing (44 checks)

## 0.9.8 – alpha (2026-10-06)
- Accessibility: VoiceOver reads limit cards, stat tiles and the menu bar item in words; deeper light-mode colours for better contrast. A one-time What's new notice after an update. A small local event log (no tokens or usage numbers) is included in Copy diagnostics and bug reports

## 0.9.7 – alpha (2026-10-06)
- Dev flag --refresh-pricing

## 0.9.6 – alpha (2026-10-06)
- First-run welcome card when Claude Code isn't set up or signed in; model prices can now be updated from pricing.json without an app release (checked daily, validated, cached)

## 0.9.5 – alpha (2026-10-06)
- Releases are now universal (Apple silicon and Intel); Homebrew install (brew install --cask Ol775/tap/claude-usage); the terminal installer verifies the checksum

## 0.9.4 – alpha (2026-10-06)
- Scanning large Claude Code histories uses less memory (log files are memory-mapped; peak down about 17% on 100 MB of logs)

## 0.9.3 – alpha (2026-10-06)
- Added built-in self-tests (--selftest) and a GitHub Actions build; if Claude or ChatGPT change their usage format the app now keeps the last reading and says so instead of going blank

## 0.9.2 – alpha (2026-10-06)
- Updates now download the release disk image and verify its checksum, so they work without developer tools (falls back to building from source)

## 0.9.1 – alpha (2026-10-06)
- ChatGPT is now hidden everywhere (Overview, menu bar menu, charts) on a free plan; Settings → Account explains that free plans aren't supported

## 0.9.0 – alpha (2026-10-06)
- Added optional ChatGPT (Codex) usage for paid plans: connect through OpenAI's Codex sign-in to see its limits on the Overview, in the menu bar menu, as a menu bar item and on the forecast and report charts. Free plans aren't supported
- Added a Buy me a coffee button in Settings → About

## 0.8.3 – alpha (2026-10-06)
- Fixed the extra weekly limit bars (Opus, Sonnet) showing blue instead of Claude orange in dark and OLED modes

## 0.8.2 – alpha (2026-10-06)
- Added a demo-data mode used to make the README screenshots

## 0.8.1 – alpha (2026-10-06)
- Update and error messages no longer mention a private repo; the repository is now public

## 0.8.0 – alpha (2026-10-06)
- Added Help & Legal in Settings (terms of use, accuracy and privacy notes, unofficial-app disclaimer) and a Report a Bug button that opens a pre-filled GitHub issue; Report a Bug also added to the menu bar menu

## 0.7.1 – alpha (2026-10-06)
- Test release for trying the background update download and restart prompt (no functional changes)

## 0.7.0 – alpha (2026-10-06)
- Updates download in the background and ask for a restart to finish (banner, menu item, notification with Restart Now)
- Full menu bar customisation: choose the items, label style, percentage colour and icon style, with presets and a live preview
- Fixed a false "on pace to hit your weekly limit" warning: a short busy stretch was being stretched across the whole week; the weekly forecast now uses the whole week plus your usual weekly pattern
- Fixed the menu bar menu being rebuilt while it was open, a second copy of the app adding a second menu bar icon, update notices being hidden when limit alerts were off, and "Allow…" not showing before macOS had been asked about notifications
- Grammar and wording fixes (1 response, 1 day…), a stale sign-in hint in the menu, and a Settings… menu item

## 0.6.1 – alpha (2026-10-06)
- Change log in About shows only the last 3 versions (full history on GitHub)

## 0.6.0 – alpha (2026-10-06)
- Change log in Settings → About (every version, newest first); repository renamed to Claude-Usage

## 0.5.0 – alpha (2026-10-06)
- In-app updates: Update Now downloads the new version from GitHub, builds it, swaps it in (keeping a backup) and relaunches; the update notification has an Update Now button

## 0.4.0 – alpha (2026-10-06)
- Notifies when a newer version is available on GitHub (Settings → About shows what's new; ../update.sh installs it); robot-themed stock avatars for the account picture

## 0.3.3 – alpha (2026-10-06)
- Dock icon is set from the bundled icon at launch, so a stale macOS icon cache can't show an old one

## 0.3.2 – alpha (2026-10-06)
- Dashboard now comes to the front when opened from the Dock or menu; README version heading stays in sync (bump.sh updates it)

## 0.3.1 – alpha (2026-10-06)
- Settings toggles are now switches like System Settings

## 0.3.0 – alpha (2026-10-06)
- Account moved into Settings; Settings redesigned like System Settings (categories list, search, grouped sections, appearance tiles); app icon now matches the menu bar bot (orange bot on a dark tile)

## 0.2.0 – alpha (2026-10-06)
- New original bot icon for the app and the menu bar (drop your own art at `assets/bot.png` to replace it)
- Menu bar now reads `D 00%  W 00%` (D = current session, W = weekly)
- Sidebar collapses to an icon rail instead of hiding, so the sections stay visible
- Notifications can be marked as important (Time Sensitive; on-screen banner stays until clicked)
- GitHub repository link in Settings, the menu and the About panel
- Version bump process: `bump.sh`, this changelog, and a commit check that requires a version bump with code changes

## 0.1.0 – alpha (2026-10-06)
- Renamed to Claude Usage; dashboard with Overview, Reports, Insights, Usage, Account and Settings
- Session and weekly limits with reset times and forecasts (weekly forecast learns from saved history)
- Light, Dark, OLED black and Follow system; six colour themes; saved activity history; CSV export
