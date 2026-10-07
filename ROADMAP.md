# Roadmap

Claude Usage reached **beta** in v0.10.0. This page records what the alpha delivered and lays out the road from beta to a **1.0 production release**. Nothing here needs a paid account unless a section says so. Legend: ✅ done, 🚧 in progress, ⏳ planned.

## Alpha → beta: complete ✅

| # | Item | Result |
|---|------|--------|
| 1 | Release-based updater | Downloads the release DMG, verifies an offline Ed25519 signature bound to the version plus the SHA-256, no developer tools needed, no source-build fallback. |
| 2 | ChatGPT (Codex) usage | Shipped as **experimental**: the paid-plan limits are only verified with sample data. Free plans are unsupported and hidden. |
| 3 | Resilience to API changes | Tolerant parsing; if a response changes shape the app keeps the last reading and says so. |
| 4 | Automated tests and CI | 67 built-in checks (`--selftest`) run by GitHub Actions on every push, on macOS 14, 15 and the latest. |
| 5 | Performance | 100 MB of logs scans in about 1.2 s (cached afterwards), ~155 MB peak memory, 0% CPU idle. |
| 6 | Install without Apple signing | Homebrew tap, checksum-verified terminal installer, checksum and signature on every release. |
| 7 | Universal build | Apple silicon and Intel in one DMG. |
| 8 | Onboarding | First-run welcome card for Claude Code setup and sign-in. |
| 9 | Pricing updates | `pricing.json`, checked daily, validated, cached. |
| 10 | Compatibility | Builds and self-tests on macOS 14, 15 and latest in CI; compiled against a macOS 13 target (not run on 13 itself, GitHub no longer offers a 13 runner). |
| 11 | Accessibility | VoiceOver labels on cards, tiles, charts, tabs and the update bar; WCAG contrast check of every theme; ⌘1–⌘5 switch tabs and ⌘R refreshes. |
| 12 | Notifications and launch at login | Launch at login built in; alert review fixed a bug where a wobbling server reset time could repeat an alert in the same window. |
| 13–16 | Export, What's new, diagnostics, update progress | CSV export; one-time What's new notice; allow-list diagnostics with a Preview; progress bar and a download-only mode for copies that can't self-install. |
| — | Security | Five independent read-only reviews, no secrets and no remote exploits found; all findings fixed. See [SECURITY.md](SECURITY.md). |

## Beta → 1.0: the road to production

Phases can overlap; the order is by what most reduces risk for real users.

### B1. Real-world confidence ⏳
The biggest gap is that most testing happened on one Mac.
- Clean-install and update test on a **second Mac** that has never had developer tools (DMG, Homebrew and terminal installers; update from every earlier beta).
- Run on **macOS 13** hardware or a VM, and on an **Intel** Mac.
- A hands-on **VoiceOver and keyboard-only pass** by a person (the automated labels exist; the experience is untested), plus Reduce Motion, Increase Contrast and larger text.
- **Paid ChatGPT**: verify with a real paid account. If it can't be verified, remove the feature before 1.0 rather than ship it unproven.
- Collect real bug reports from beta users and triage them in GitHub issues with labels and a "known issues" list in the README.

### B2. Quality and maintainability ✅ (done in 0.10.1–0.10.4)
- ✅ **Real-shaped fixtures.** The Claude and ChatGPT response samples in `Fixtures.swift` copy the shapes of the live responses (captured as keys and types only, every value made up). The real Claude response had already grown to 26 top-level fields, so the parser also reads the newer `limits` list as a fallback if the classic `five_hour` and `seven_day` fields ever disappear.
- ✅ **Screenshot regression tests.** CI renders ten screens (five screens, light and dark; the settings screen is the Appearance pane, which does not change with each release) with demo data and a frozen clock, and compares them with saved images per macOS version (14, 15, 26). A screen fails if more than 30 small regions changed; repeat runs differ by 0. See `ClaudeUsage/tests/README.md` for how to refresh the images after a design change.
- ✅ **`Dashboard.swift` split** from 1,512 lines into `Dashboard`, `Overview`, `ProjectionChart`, `UsageView`, `SettingsView` and `SettingsParts`.
- ✅ **Incremental log parsing.** A growing Claude Code log is read from where it stopped last time (same totals on real data, checked against the previous build).
- ✅ **GitHub Actions pinned by commit** with Dependabot keeping them current.
- ✅ **Swift portability.** CI builds on Swift 5.10, 6.1 and 6.3 (the macOS 14, 15 and 26 runners) and has already caught one portability bug.

### B3. Trust, security and distribution ⏳
- **Decide on a paid Apple Developer ID and notarisation** at 1.0 (removes the first-launch prompt; costs $99/yr). Until then the free path stays: Homebrew tap, checksums, offline signature.
- Document a **signing-key rotation and recovery procedure**, with the second backup tested (restore the key from iCloud/Proton and sign a test file).
- Keep the legacy `.sig` for a few more releases, then remove it.
- A **third security review** before 1.0, including a fresh look at install scripts and the Homebrew cask. Re-run it after any change to the updater, diagnostics or install scripts.
- An opt-in **beta/stable update channel** so testers can get betas while everyone else stays on stable.
- Publish a short privacy statement (`PRIVACY.md`) matching the in-app one, and a software bill of materials (the app has no third-party dependencies).

### B4. Product polish ⏳
- Localisation (starting with the strings in Settings and the menu).
- Data controls: a "delete all my data" button, retention settings and settings export/import.
- Notification actions (snooze, open dashboard) and quiet hours.
- ChatGPT graduates from experimental if verified (B1), with a screenshot refresh.
- Optional: a WidgetKit widget and Shortcuts support (these need Xcode, which isn't installed on the build Mac).

### B5. Community and project hygiene ⏳
- `CONTRIBUTING.md`, issue and pull-request templates, and a `CODE_OF_CONDUCT.md`.
- Release notes written for people, generated from the change log, and a support policy (latest release only, how fast security fixes ship).
- A short "how updates are verified" explainer in the README linking to `SECURITY.md`.

## 1.0 production gates

Version 1.0 ships (stage switches to stable, README and in-app wording drop "beta") when all of these hold:
- ⏳ Updates, installs and the first-run experience are verified on a second clean Mac, macOS 13 and an Intel Mac.
- ⏳ CI is green on macOS 14, 15 and latest, and the self-tests plus screenshot tests cover the parsers, forecaster, updater and main screens.
- ⏳ No open high-severity bugs; every known issue is listed.
- ⏳ A third security review finds nothing medium or above outstanding, and the key-rotation procedure has been rehearsed.
- ⏳ ChatGPT is either verified on a paid plan or removed.
- ⏳ The Apple Developer ID decision is made and documented.
- ⏳ README, SECURITY, PRIVACY, CONTRIBUTING and the in-app legal text are current and agree with each other.

## Later (not blocking 1.0)
- Independent sign-in, blocked until Anthropic offers a public OAuth client for third-party apps.
- iCloud folder sync (per-Mac activity files summed together) if there is demand.
- Multiple Claude accounts.

Ideas or bugs? [Open an issue](https://github.com/Ol775/Claude-Usage/issues/new).
