# Roadmap: alpha to beta

Claude Usage is currently **alpha** (v0.9.13). This is the plan for reaching **beta**, in order of what blocks it. Nothing here needs a paid account. Legend: ✅ done, 🚧 in progress, ⏳ waiting.

## Phase 1: Reliability (blocks beta)

1. ✅ **Release-based updater** (0.9.2, hardened in 0.9.10 and 0.9.13). Updates download the release DMG, verify an offline Ed25519 signature bound to the version plus the SHA-256, and swap the app in, with no developer tools needed. There is no source-build fallback.
2. ⏳ **Test the paid ChatGPT (Codex) path** (deliberately last). The 5-hour and weekly windows are only verified with demo data. Verify with a paid account, or label the feature experimental until then.
3. ✅ **Resilience to API changes** (0.9.3). Parsing skips unknown fields, and if a response changes shape the app keeps the last reading and says so instead of going blank.
4. 🚧 **Automated tests and CI.** 66 built-in checks (`--selftest`) cover versions, update signatures and URL rules, the Claude and ChatGPT parsers, Claude Code log parsing, pricing, the forecaster, diagnostics and the event log. The GitHub Actions workflow that runs them on every push is written (`.pending/ci.yml`) and waits for the `workflow` scope on the GitHub login.
5. ✅ **Performance check** (0.9.4). On 100 MB of logs a first scan takes about 1.2 s (cached afterwards), peak memory is about 155 MB, and the running app idles at 0% CPU. Possible later improvement: parse only the new part of a growing log.

## Security (done, repeat after risky changes)

Five independent read-only reviews so far, all with no secrets found and no remote exploits:

- **0.9.10:** updater and supply chain, credentials and data handling, repository and history. Fixes: offline-signed updates, no source-build fallback, validated and re-checked downloads, safer program lookup, private data folders, developer overrides ignored in the shipped app, `SECURITY.md`, commit history rewritten to use the GitHub noreply email.
- **0.9.13:** diagnostics privacy and the new update code. Fixes: signatures bound to the version, download time and size limits, redirects only to GitHub's hosts, plain `x.y.z` versions only, an installer saved to Downloads that never overwrites files, and a smaller, safer diagnostics report.

See [SECURITY.md](SECURITY.md) for the trust model and how to report a problem privately.

## Phase 2: Trust and first run

6. ✅ **Low-friction install without Apple signing** (0.9.5). A Homebrew tap (`brew install --cask Ol775/tap/claude-usage`) clears the quarantine flag, the terminal installer requires a matching checksum, every release ships checksum and signature files, and the README explains the first-launch prompt. The source build stays as the fully transparent route.
7. ✅ **Universal build** (0.9.5). Releases ship Apple silicon and Intel in one DMG.
8. ✅ **Onboarding** (0.9.6). A first-run welcome card shows what's needed (Claude Code installed, signed in) with the next click.
9. ✅ **Pricing table updates** (0.9.6). Prices live in `ClaudeUsage/pricing.json`; the app checks it once a day, validates it, caches it and merges it over the built-in table. The "no price known" note remains for unknown models.
10. 🚧 **Compatibility.** The app compiles against a macOS 13 target (newer-only APIs are caught at build time), but it has only been run on the newest macOS. Still to do: run it on macOS 13, 14 and 15 (a CI job on those runners would do it).

## Phase 3: Polish

11. 🚧 **Accessibility** (0.9.8). VoiceOver reads limit cards, stat tiles, the update progress bar and the menu bar item in plain words, and every theme's colours were checked against the WCAG contrast formula. Still to do: chart descriptions and a full keyboard-navigation pass.
12. 🚧 **Launch at login** is built in (Settings). Still to do: a review of the notification settings and repeat-alert behaviour.
13. ✅ **Data export** to CSV is built in (Settings → Data & Export).
14. ✅ **What's new** (0.9.8). A one-time notice after an update, plus the full change log in Settings → About.
15. ✅ **Diagnostics** (0.9.8, trimmed in 0.9.13). A short allow-list of facts (app version, macOS version, chip, a few yes/no states and a local event log) with a **Preview** in Settings → Help & Legal showing exactly what Copy and Report a Bug include. No account details, paths, tokens or usage numbers.
16. ✅ **Update progress** (0.9.11). A progress bar for download, verification and install (Settings → About, above every page and in the menu). Copies that can't replace themselves get a **Download Update** button that saves the verified installer to Downloads.

## Later (not blocking beta)

- Independent sign-in, blocked until Anthropic offers a public OAuth client for third-party apps.
- iCloud folder sync and a WidgetKit widget (widgets need Xcode).
- Localisation.
- Drop the legacy `.sig` release file once installs older than 0.9.13 have updated.

## Beta exit criteria

- ✅ The updater is tested end to end from a release, without developer tools. Tested in throwaway copies, including an old 0.9.10 build; still to confirm on a clean second Mac.
- ⏳ CI is green, with tests covering the parsers and the predictor (the tests exist; CI is waiting on the workflow scope).
- ⏳ No open crash or data-loss bugs for two weeks.
- ⏳ Paid ChatGPT is verified, or clearly marked experimental.
- ⏳ A bug has been reported and fixed through the in-app Report a Bug flow.

Ideas or bugs? [Open an issue](https://github.com/Ol775/Claude-Usage/issues/new).
