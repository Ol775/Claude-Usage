# Privacy

Last updated 7 October 2026. This matches the text in the app under Settings → Help & Legal → Privacy and your data.

**Short version:** Claude Usage works on your Mac. The developer runs no servers, receives no analytics and collects no data about you.

## What stays on your Mac

Your usage history, saved activity, settings and profile photo are stored only in `~/Library/Application Support/ClaudeUsage` (folder mode 700) and the app's preferences. No tokens are ever written there. Settings → Data lets you choose how long daily activity (forever by default) and limit readings (up to 90 days) are kept. **Export settings** writes your preferences, and nothing else, to a file you choose.

## What the app reads

- **Claude Code's logs** in `~/.claude/projects`, read-only, to count tokens and estimate cost.
- **Claude Code's sign-in token** from your keychain. It is used only to ask Anthropic for your usage limits. The app never stores it, logs it or sends it anywhere else.
- **Codex's ChatGPT login** (`~/.codex/auth.json`), only if you turn ChatGPT usage on (experimental, paid plans only). It is read-only and used only to ask ChatGPT for your usage limits. The app never changes, refreshes, copies or stores that login and does not read your chats.

## Network requests

The app makes up to three kinds of request, and nothing else:

1. **Anthropic** (`api.anthropic.com`) for your usage limits.
2. **ChatGPT** (`chatgpt.com`) for your ChatGPT limits, only if you connect it.
3. **GitHub** to check for and download updates, the change log and model prices.

## Reports and diagnostics

Nothing is sent automatically. "Copy" and "Report a Bug" show exactly what they include before you use them: app version, macOS version, chip, a few yes/no states and a short local event log. No account details, file paths, tokens or usage numbers. "Report a Bug" opens a pre-filled GitHub page that you review and submit yourself.

## Deleting your data

Quit the app and remove the `ClaudeUsage` folder in `~/Library/Application Support`. Or use Settings → Data → Delete all my data, which erases the folder and the app's preferences and quits. Your Claude Code and ChatGPT sign-ins and logs are never touched.

## Questions

Open an [issue](https://github.com/Ol775/Claude-Usage/issues/new), or report anything security-related privately as described in [SECURITY.md](SECURITY.md).
