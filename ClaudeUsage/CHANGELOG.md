# Changelog

Versions follow `MAJOR.MINOR.PATCH` and are currently **alpha**. Bump `VERSION` (use `./bump.sh`) with every change:
**minor** for new features, **patch** for fixes and polish. The build number is the git commit count and rises automatically.

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
