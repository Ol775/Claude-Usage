# Security

## Reporting a vulnerability

Please report security problems **privately** through GitHub: [Report a vulnerability](https://github.com/Ol775/Claude-Usage/security/advisories/new). Please don't open a public issue for anything that could put users at risk. Don't include real tokens or personal logs in a report.

Only the latest release is supported while the app is in alpha/beta.

## What the app can access

- **Claude Code's login token**, read from your keychain with `/usr/bin/security`, used only to ask Anthropic for your usage limits (HTTPS to `api.anthropic.com`). macOS may ask you to allow this.
- **Codex's ChatGPT login** (`~/.codex/auth.json`), only if you turn ChatGPT usage on; read-only, used only for `chatgpt.com/backend-api/wham/usage`.
- **Claude Code's logs** (`~/.claude/projects`), read-only, to count tokens.
- **Its own folder** (`~/Library/Application Support/ClaudeUsage`, mode 700): history, preferences and a small event log. No tokens are ever written there.
- Network: Anthropic and (optionally) ChatGPT usage endpoints, GitHub (release check, change log, model prices). Nothing else, and no analytics.

## How updates are trusted

Every release DMG is signed, together with its version number, with an Ed25519 key whose private half is kept offline on the maintainer's Mac, never on GitHub. The app has the public key built in and installs an update only if all of these pass: the download is from this repo's GitHub releases over HTTPS, the signature verifies for exactly that version (so an older signed image can't pass as a newer release), the SHA-256 matches, the app's bundle id and version are right, and its code signature is intact. Downloads have a time and size limit and may only redirect to GitHub's own hosts. An update that fails any check is discarded. The app never builds or runs code from the repository when updating.

The app is ad-hoc signed (no paid Apple Developer ID), so macOS Gatekeeper treats it as unidentified on first launch. The terminal and Homebrew installs verify the SHA-256 of the DMG; the Homebrew cask pins it. If the signing key is ever lost or exposed, a new key will be announced in the releases and the README.

## Hardening already in place

- Programs the app runs (`claude`, `codex`) must be owned by you or root and not writable by others, and system folders are searched first.
- Developer overrides (`CUB_*` variables and test flags) are ignored in the shipped app.
- The self-test suite (`ClaudeUsage --selftest`) covers signature checks, URL validation and executable checks.

## Diagnostics

Settings → Help & Legal shows exactly what "Copy" and "Report a Bug" include before you use them: app version, macOS version, chip, a few yes/no states (Claude Code found/signed in, update state, notifications, ChatGPT on/off) and a short local event log. No account details, file paths, tokens or usage numbers. Nothing is sent automatically.
