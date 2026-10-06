# Roadmap: alpha to beta

Claude Usage is currently **alpha**. This is the plan for reaching **beta**. Items are ordered by what blocks a beta release. Nothing here needs a paid account.

## Phase 1: Reliability (blocks beta)

1. ✅ **Release-based updater** (done in 0.9.2). Updates download the release DMG, verify its SHA-256 checksum and swap the app in, with no developer tools needed. It falls back to a source build if the download fails.
2. **Test the paid ChatGPT (Codex) path.** The 5-hour and weekly windows are only verified with demo data. Verify with a paid account, or label the feature experimental until then.
3. ✅ **Resilience to API changes** (done in 0.9.3). Parsing skips unknown fields, and if a response changes shape the app keeps the last reading and says so instead of going blank.
4. 🚧 **Automated tests and CI** (started in 0.9.3). 31 built-in checks (`--selftest`) cover versions, the Claude and ChatGPT parsers, pricing and the forecaster, and a GitHub Actions job builds and runs them on every push. Still to add: log-parser tests with fixture files.
5. ✅ **Performance check** (done in 0.9.4). On 100 MB of logs a first scan takes about 1.2 s (cached afterwards), peak memory is about 155 MB (down from 187 MB), and the running app idles at 0% CPU. Possible later improvement: parse only the new part of a growing log.

## Phase 2: Trust and first run

6. ✅ **Low-friction install without Apple signing** (done in 0.9.5). A Homebrew tap (`brew install --cask Ol775/tap/claude-usage`) clears the quarantine flag, the terminal installer verifies the checksum, every release ships a `.sha256` file, and the README explains the first-launch prompt. The source build stays as the fully transparent route.
7. ✅ **Universal build** (done in 0.9.5). Releases ship Apple silicon and Intel in one DMG.
8. ✅ **Onboarding** (done in 0.9.6). A first-run welcome card shows what's needed (Claude Code installed, signed in) with the next click; signed-in accounts with no data yet see the normal empty charts.
9. ✅ **Pricing table updates** (done in 0.9.6). Prices live in `ClaudeUsage/pricing.json`; the app checks it once a day, validates it, caches it and merges it over the built-in table. The "no price known" note remains for unknown models.
10. 🚧 **Compatibility.** The app compiles against a macOS 13 target (newer-only APIs are caught at build time), but I've only run it on the newest macOS. Still to do: run it on macOS 13, 14 and 15 (a CI job on those runners would do it).

## Phase 3: Polish

11. 🚧 **Accessibility** (started in 0.9.8). VoiceOver reads limit cards, stat tiles and the menu bar item in plain words, and every theme's colours were checked against the WCAG contrast formula (light-mode colours deepened). Still to do: chart descriptions and a full keyboard-navigation pass.
12. ✅ **Launch at login** is built in (Settings), alerts fire once per event.
13. ✅ **Data export** to CSV is built in (Settings → Data & Export).
14. ✅ **What's new** (done in 0.9.8). A one-time notice after an update, plus the full change log in Settings → About.
15. ✅ **Diagnostics log** (done in 0.9.8). A small local event log (no tokens, emails or usage numbers) is included when you copy diagnostics or report a bug.

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
