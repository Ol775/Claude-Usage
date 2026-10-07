# Releasing and the signing key

For maintainers. Users don't need any of this; see [SECURITY.md](SECURITY.md) for how updates are checked.

## Releasing a version

```sh
cd ClaudeUsage
./bump.sh patch "what changed, written for users"   # or minor for a new feature
./build.sh && "Claude Usage.app/Contents/MacOS/ClaudeUsage" --selftest
git commit -am "…" && git push
./release.sh                                       # optional extra note: ./release.sh "Thanks to … for reporting"
```

`release.sh` refuses to run if the tree is dirty, `main` isn't pushed, or the signing key doesn't match the public key in `src/Updater.swift`. It builds the universal DMG, signs it, publishes the GitHub release and updates the Homebrew cask. The release notes are the version's `CHANGELOG.md` entry, so write change-log notes for people, not for developers.

## Beta releases

`PRERELEASE=1 ./release.sh` publishes a GitHub pre-release. Only copies with **Settings → About → Get beta versions** turned on are offered it; everyone else (and Homebrew) stays on the latest normal release. Bump to a version higher than the current release, as usual. The next normal release reaches beta testers too, because it has a higher version.

## The signing key

- Ed25519 private key at `~/.config/claude-usage/signing.key` (mode 600). Never commit it or upload it anywhere public.
- The public half is `Updater.publicKey` in `ClaudeUsage/src/Updater.swift`. Every installed copy trusts only that key.
- Two backups, in a folder called "Claude Usage Release Key": Proton Drive (end-to-end encrypted) and iCloud Drive (end-to-end encrypted only with Advanced Data Protection).
- Tool: `ClaudeUsage/sign-tool.swift` (`keygen`, `sign`, `sign-update`, `public`, `verify`). Build it with `swiftc -O sign-tool.swift -o build/sign-tool`.

## Restoring the key from a backup

Rehearsed on 2026-10-07 from both backups.

```sh
cd ClaudeUsage && swiftc -O sign-tool.swift -o build/sign-tool
mkdir -p ~/.config/claude-usage && chmod 700 ~/.config/claude-usage
cp "<backup folder>/signing.key" ~/.config/claude-usage/signing.key && chmod 600 ~/.config/claude-usage/signing.key
# 1. The public key must match the one built into the app:
build/sign-tool public ~/.config/claude-usage/signing.key
grep -o 'publicKey = "[^"]*"' src/Updater.swift
# 2. A test signature must verify for the right version and fail for any other:
echo test > /tmp/t.bin
build/sign-tool sign-update ~/.config/claude-usage/signing.key /tmp/t.bin 9.9.9 > /tmp/t.sig2
build/sign-tool verify "<public key>" /tmp/t.bin /tmp/t.sig2 9.9.9   # prints "valid"
build/sign-tool verify "<public key>" /tmp/t.bin /tmp/t.sig2 9.9.8   # must fail
```

Rehearse this once before 1.0 and after changing either backup.

## Planned key rotation (old key still safe)

Installed copies only trust the key they were built with, so the hand-over release must be signed with the **old** key and contain the **new** public key.

1. `build/sign-tool keygen ~/.config/claude-usage/signing-new.key` and note the public key it prints.
2. Back up the new key to both places before going further.
3. Put the new public key in `Updater.publicKey`, bump, build, commit and push.
4. Release with the old key: `ROTATING=1 SIGNING_KEY=~/.config/claude-usage/signing.key ./release.sh "The update signing key has changed."`
5. Move the new key to `~/.config/claude-usage/signing.key` and keep the old one offline for a while. Later releases are signed with the new key.
6. Note the new public key in the release notes and in SECURITY.md.

## Lost or exposed key

The app can't revoke a key on its own, so this needs users to act.

- **Lost** (no backup works): existing installs can't verify any new update. Generate a new key, embed it, release, and tell users in the README and release notes to reinstall once from the DMG, terminal or Homebrew. Updates work again after that.
- **Exposed**: do the same, and also delete the old key everywhere. An attacker would still need control of this GitHub repo's releases to serve a fake update (the app only downloads from them), so also rotate GitHub credentials and check the release history. Publish a security advisory.
