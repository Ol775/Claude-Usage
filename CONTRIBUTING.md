# Contributing

Thanks for helping. Bug reports, ideas and pull requests are all welcome.

## Reporting bugs and ideas

Use [Issues](https://github.com/Ol775/Claude-Usage/issues/new/choose). Please don't paste tokens, account details or private logs. For security problems, use the private route in [SECURITY.md](SECURITY.md) instead.

## Building

The app is plain Swift built with `swiftc` (Command Line Tools are enough, no Xcode):

```sh
cd ClaudeUsage
./build.sh
"Claude Usage.app/Contents/MacOS/ClaudeUsage" --selftest
```

Screenshot tests and how to refresh their baselines are described in [`ClaudeUsage/tests/README.md`](ClaudeUsage/tests/README.md).

## Pull requests

- Keep each PR small and focused.
- Run `--selftest` first; CI also runs it on macOS 14, 15 and latest.
- Run `./bump.sh patch "short note"` when you change anything in `src/` or `build.sh`. It updates the version, change log and README, and a pre-commit hook checks it.
- Use `AppFont.*` instead of `.font(.headline)` and similar, so personalisation settings apply.
- Screenshots in the repo use demo data only. Never include real account details.
- No new third-party dependencies without a discussion first.
- The app is macOS only.
