# Roadmap: alpha to beta

Claude Usage is currently **alpha**. This is the plan for reaching **beta**. Items are ordered by what blocks a beta release. Nothing here needs a paid account.

## Phase 1: Reliability (blocks beta)

1. ✅ **Release-based updater** (done in 0.9.2). Updates download the release DMG, verify its SHA-256 checksum and swap the app in, with no developer tools needed. It falls back to a source build if the download fails.
2. **Test the paid ChatGPT (Codex) path.** The 5-hour and weekly windows are only verified with demo data. Verify with a paid account, or label the feature experimental until then.
3. ✅ **Resilience to API changes** (done in 0.9.3). Parsing skips unknown fields, and if a response changes shape the app keeps the last reading and says so instead of going blank.
4. 🚧 **Automated tests and CI** (started in 0.9.3). 31 built-in checks (`--selftest`) cover versions, the Claude and ChatGPT parsers, pricing and the forecaster, and a GitHub Actions job builds and runs them on every push. Still to add: log-parser tests with fixture files.
5. **Performance check.** The log scan reads up to a year of logs. Profile CPU, memory and wakeups on a large history, and run the app idle for 24 hours.

## Phase 2: Trust and first run

6. **Low-friction install without Apple signing.**
   - A free Homebrew cask tap (`brew install --cask claude-usage`).
   - `install.sh` clears the quarantine flag.
   - An illustrated Gatekeeper walkthrough in the README.
   - A SHA-256 checksum on every release.
   - The source build stays as the fully transparent route.
7. **Universal build.** Ship arm64 and x86_64 in one DMG.
8. **Onboarding.** A first-run flow that detects whether Claude Code is installed and signed in, with empty states for new users.
9. **Pricing table updates.** Update model prices without a new release, and show a clear "unpriced model" note.
10. **Compatibility.** Test on macOS 13, 14 and 15.

## Phase 3: Polish

11. **Accessibility.** VoiceOver labels, contrast checks in every theme, keyboard navigation.
12. **Launch at login** and a notification settings review, so alerts don't repeat.
13. **Data export** as CSV or JSON from Reports.
14. **In-app "What's new"** after an update, fed from `CHANGELOG.md`.
15. **Opt-in diagnostics log** the user can attach to a bug report.

## Later (not blocking beta)

- Independent sign-in, blocked until Anthropic offers a public OAuth client for third-party apps.
- iCloud folder sync and a WidgetKit widget (widgets need Xcode).
- Localisation.

## Beta exit criteria

- The updater is tested end to end from a release, on a clean Mac without developer tools, with no signing prompts beyond the first launch.
- CI is green, with tests covering the parsers and the predictor.
- No open crash or data-loss bugs for two weeks.
- Paid ChatGPT is verified, or clearly marked experimental.
- A bug has been reported and fixed through the in-app Report a Bug flow.

Ideas or bugs? [Open an issue](https://github.com/Ol775/Claude-Usage/issues/new).
