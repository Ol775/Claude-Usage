# Tests

- **Self-tests:** `"Claude Usage.app/Contents/MacOS/ClaudeUsage" --selftest` runs every built-in check (parsers, fixtures, updater rules, forecaster, diagnostics, screenshot comparison). CI runs it on every push.
- **Screenshot tests:** CI renders the main screens (demo data only, light and dark) in a test copy of the app and compares them with the images in `tests/screens/<macOS major version>/`. A screen fails if more than 30 small regions of it changed clearly. Clock readings and axis labels don't trip it.

## Updating the saved screens (only after an intentional design change)

1. Push the change; the CI run uploads the rendered screens as artifacts (`screens-macos-14`, `screens-macos-15`, `screens-macos-latest`).
2. `gh run download <run-id>` and, for each, shrink the images and copy them into the matching folder:
   `sips -Z 1000 <file>.png --out ClaudeUsage/tests/screens/<14|15|26>/<file>.png` (`macos-latest` is currently macOS 26).
3. Commit the new images with the design change.

## Running the screenshot tests locally

Use a throwaway copy so your real app is untouched (the shipped app ignores these developer options):

```sh
cp -R "Claude Usage.app" /tmp/test.app
plutil -replace CFBundleIdentifier -string local.claudeusage.test /tmp/test.app/Contents/Info.plist
codesign --force --sign - /tmp/test.app
CUB_DEMO=1 CUB_SUPPORT_DIR=/tmp/cub-s CUB_CACHE_DIR=/tmp/cub-c CUB_NO_RELAUNCH=1 \
  /tmp/test.app/Contents/MacOS/ClaudeUsage --quiet --render-screens /tmp/screens [--compare tests/screens/<major>]
```

## Accessibility audit

`tests/axaudit.swift` walks the live accessibility tree of a running test copy and lists every control VoiceOver couldn't name. Build it with `swiftc -O tests/axaudit.swift -o build/axaudit`, start a re-identified test copy with `CUB_DEMO=1` (see above), then run `build/axaudit <pid> Settings Notifications` and so on for each tab and settings pane. Only the system stepper arrows (named by macOS itself) should be listed. It needs Accessibility permission for the terminal, so it doesn't run in CI.
