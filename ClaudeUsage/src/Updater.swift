import Foundation
import CryptoKit

// Checks the GitHub repo for a newer version than the one installed.

struct UpdateInfo {
    let version: String
    let notes: [String]
    var dmgURL: URL? = nil          // the release's disk image, when the update comes from a GitHub release
    var sha256: String? = nil       // its expected checksum
    var sigURL: URL? = nil          // detached Ed25519 signature made offline with the release key
}

enum UpdateStatus {
    case idle
    case checking
    case upToDate(Date)
    case available(UpdateInfo)
    case ready(UpdateInfo, URL)          // downloaded and built – restart to install
    case failed(String)
}

private func versionParts(_ v: String) -> [Int] { v.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 } }

/// True when version `a` is newer than `b` (both "major.minor.patch").
func isNewer(_ a: String, than b: String) -> Bool {
    let x = versionParts(a), y = versionParts(b)
    for i in 0..<max(x.count, y.count) {
        let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
        if p != q { return p > q }
    }
    return false
}

enum Updater {
    static let repo = "Ol775/Claude-Usage"
    /// `CUB_PRETEND_VERSION` lets tests act as an older install.
    static var installed: String { Dev.env("CUB_PRETEND_VERSION") ?? AppInfo.version }

    /// Ed25519 public key that every release DMG must be signed with (the private key lives only on the maintainer's Mac,
    /// so a hijacked GitHub account or release can't push an update that installs).
    static let publicKey = "mvj0cA6MApe5fnWjpLxjMsimf1e54B1XawxgjIn8eN0="

    /// Reads a file from the repo's main branch over HTTPS (the repo is public). Used for the change log and prices only,
    /// never for anything that gets installed.
    static func fetch(_ path: String) -> String? {
        guard let url = URL(string: "https://raw.githubusercontent.com/\(repo)/main/\(path)") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 15); req.cachePolicy = .reloadIgnoringLocalCacheData
        let sem = DispatchSemaphore(value: 0)
        var out: String?
        URLSession.shared.dataTask(with: req) { d, r, _ in
            if (r as? HTTPURLResponse)?.statusCode == 200, let d = d { out = String(data: d, encoding: .utf8) }
            sem.signal()
        }.resume()
        sem.wait()
        return out
    }

    /// "1.2.3" – digits and dots only, so a hostile tag can't smuggle odd characters into file names or messages.
    static func isPlainVersion(_ v: String) -> Bool {
        v.range(of: #"^\d{1,4}\.\d{1,4}\.\d{1,4}$"#, options: .regularExpression) != nil
    }

    /// What the release key signs: a label, the version, and the disk image bytes – so a validly signed older image can't be
    /// passed off as a newer release.
    static func signedMessage(version: String, dmg: Data) -> Data { Data("claude-usage-update\nv\(version)\n".utf8) + dmg }

    /// Only these hosts may serve a release download (GitHub and its asset CDN), also after redirects.
    static func isAllowedRedirectHost(_ host: String?) -> Bool {
        guard let h = host?.lowercased() else { return false }
        return h == "github.com" || h.hasSuffix(".githubusercontent.com")
    }

    /// Release downloads must come from this repo's GitHub releases.
    static func isTrustedAsset(_ u: URL) -> Bool {
        u.scheme == "https" && u.host == "github.com" && u.path.hasPrefix("/\(repo)/releases/download/")
    }

    /// True if `signature` (base64) is a valid signature of `data` by the release key.
    static func verifySignature(_ data: Data, base64Signature: String, publicKey key: String = Updater.publicKey) -> Bool {
        guard let k = Data(base64Encoded: key), let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: k),
              let sig = Data(base64Encoded: base64Signature.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return pub.isValidSignature(sig, for: data)
    }

    /// Bullet points from every changelog section newer than the installed version (newest first).
    static func notes(from changelog: String, newerThan installed: String) -> [String] {
        var out: [String] = [], include = false
        for line in changelog.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("## ") {
                let v = line.dropFirst(3).split(separator: " ").first.map(String.init) ?? ""
                include = isNewer(v, than: installed)
            } else if include, line.hasPrefix("- ") { out.append(String(line.dropFirst(2))) }
        }
        return out
    }

    /// The newest GitHub release: version, disk image URL and checksum (from the asset digest or a `.sha256` file).
    static func latestRelease() -> (version: String, dmg: URL?, sha: String?, sig: URL?)? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 15); req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let sem = DispatchSemaphore(value: 0)
        var data: Data?
        URLSession.shared.dataTask(with: req) { d, r, _ in
            if (r as? HTTPURLResponse)?.statusCode == 200 { data = d }
            sem.signal()
        }.resume()
        sem.wait()
        guard let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard isPlainVersion(version) else { return nil }              // only digits and dots: it ends up in file names and UI text
        let assets = json["assets"] as? [[String: Any]] ?? []
        let dmg = assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }
        let dmgURL = (dmg?["browser_download_url"] as? String).flatMap(URL.init(string:)).flatMap { isTrustedAsset($0) ? $0 : nil }
        let sigURL = (assets.first { $0["name"] as? String == (dmg?["name"] as? String ?? "") + ".sig2" }?["browser_download_url"] as? String).flatMap(URL.init(string:)).flatMap { isTrustedAsset($0) ? $0 : nil }
        var sha = (dmg?["digest"] as? String).flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)) : nil }
        if sha == nil, let name = dmg?["name"] as? String,
           let sumURL = (assets.first { $0["name"] as? String == name + ".sha256" }?["browser_download_url"] as? String).flatMap(URL.init(string:)).flatMap({ isTrustedAsset($0) ? $0 : nil }),
           let text = (try? String(contentsOf: sumURL, encoding: .utf8)) {
            sha = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).first.map(String.init)
        }
        return (version, dmgURL, sha?.lowercased(), sigURL)
    }

    /// Blocking check – call from a background queue. GitHub releases are the only source of updates.
    static func check() -> UpdateStatus {
        guard let r = latestRelease() else { return .failed("Couldn’t reach GitHub. Check your internet connection and try again.") }
        let latest = r.version
        guard isPlainVersion(latest) else { return .failed("Unexpected version number on GitHub.") }
        guard isNewer(latest, than: installed) else { return .upToDate(Date()) }
        let notes = fetch("ClaudeUsage/CHANGELOG.md").map { notes(from: $0, newerThan: installed) } ?? []
        return .available(UpdateInfo(version: latest, notes: notes, dmgURL: r.dmg, sha256: r.sha, sigURL: r.sig))
    }
}

// MARK: - Preparing and installing an update (download from GitHub → build → swap in → relaunch)

extension Updater {
    /// Runs a command and returns its exit status (-1 if it couldn't start). Output goes to `log` when given.
    @discardableResult
    static func run(_ exe: String, _ args: [String], cwd: URL? = nil, log: FileHandle? = nil, timeout: TimeInterval = 600, lowPriority: Bool = false) -> Int32 {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        if let cwd = cwd { p.currentDirectoryURL = cwd }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
        p.environment = env
        p.qualityOfService = lowPriority ? .background : .userInitiated      // background builds stay out of the way
        p.standardOutput = log ?? FileHandle.nullDevice; p.standardError = log ?? FileHandle.nullDevice
        guard (try? p.run()) != nil else { return -1 }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if p.isRunning { p.terminate() } }
        p.waitUntilExit()
        return p.terminationStatus
    }

    private static var cachesDir: URL {
        let dir = Dev.env("CUB_CACHE_DIR").map { URL(fileURLWithPath: $0) }       // tests use their own folder
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ClaudeUsage")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return dir
    }

    /// Removes old download folders (but never the one holding an update that's waiting for a restart).
    static func cleanupOldDownloads(keeping keep: URL? = nil) {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: cachesDir.path)) ?? [] where name.hasPrefix("update-") {
            let url = cachesDir.appendingPathComponent(name)
            if let keep = keep, keep.path.hasPrefix(url.path) { continue }
            if let d = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date, Date().timeIntervalSince(d) > 86400 { try? fm.removeItem(at: url) }
        }
    }


    /// Reports download progress and hands back the finished file.
    private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
        static let maxBytes: Int64 = 100_000_000                       // a release is ~2.5 MB; anything near this is wrong
        let onProgress: (Double) -> Void
        var location: URL?, status = 0
        let done = DispatchSemaphore(value: 0)
        init(_ onProgress: @escaping (Double) -> Void) { self.onProgress = onProgress }
        func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite e: Int64) {
            if w > Self.maxBytes || e > Self.maxBytes { t.cancel(); return }                 // size cap
            if e > 0 { onProgress(min(1, Double(w) / Double(e))) }
        }
        func urlSession(_ s: URLSession, task: URLSessionTask, willPerformHTTPRedirection r: HTTPURLResponse, newRequest req: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(req.url?.scheme == "https" && Updater.isAllowedRedirectHost(req.url?.host) ? req : nil)      // only GitHub's own hosts
        }
        func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didFinishDownloadingTo loc: URL) {
            status = (t.response as? HTTPURLResponse)?.statusCode ?? 0
            let keep = FileManager.default.temporaryDirectory.appendingPathComponent("cub-\(UUID().uuidString)")      // the system deletes `loc` when this returns
            if (try? FileManager.default.moveItem(at: loc, to: keep)) != nil { location = keep }
        }
        func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { done.signal() }
    }

    /// Downloads `url` to `dest`, calling `onProgress` (0...1) as bytes arrive. Blocking.
    private static func downloadFile(_ url: URL, to dest: URL, onProgress: @escaping (Double) -> Void) -> Bool {
        let d = DownloadDelegate(onProgress)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 600; config.waitsForConnectivity = false        // never hang for days on a slow drip
        let session = URLSession(configuration: config, delegate: d, delegateQueue: nil)
        session.downloadTask(with: URLRequest(url: url, timeoutInterval: 60)).resume()
        d.done.wait(); session.finishTasksAndInvalidate()
        guard d.status == 200, let loc = d.location else { return false }
        try? FileManager.default.removeItem(at: dest)
        return (try? FileManager.default.moveItem(at: loc, to: dest)) != nil
    }

    /// Checks the downloaded disk image against the release signature and checksum. Returns an error message, or nil if it's genuine.
    private static func verify(_ dmg: URL, _ info: UpdateInfo) -> String? {
        guard let want = info.sha256, !want.isEmpty, let sigURL = info.sigURL else {
            return "This release isn’t signed, so it won’t be installed automatically. Download it from the releases page instead."
        }
        guard let dmgData = try? Data(contentsOf: dmg, options: .alwaysMapped),
              let sigData = fetchData(sigURL, timeout: 20), let sig = String(data: sigData, encoding: .utf8),
              verifySignature(signedMessage(version: info.version, dmg: dmgData), base64Signature: sig) else { return "The download’s signature didn’t check out, so it was discarded." }
        guard SHA256.hash(data: dmgData).map({ String(format: "%02x", $0) }).joined() == want.lowercased() else {
            return "The download didn’t match its checksum, so it was discarded."
        }
        return nil
    }

    /// For copies that can't replace themselves (run from a disk image, or in a folder we can't write to): downloads the
    /// verified installer into Downloads so it can be opened by hand. `fraction` reports 0...1.
    static func downloadOnly(_ info: UpdateInfo, progress: @escaping (String) -> Void, fraction: @escaping (Double) -> Void) -> (file: URL?, error: String?) {
        let fm = FileManager.default
        guard let dmgURL = info.dmgURL, isTrustedAsset(dmgURL) else { return (nil, "This release has no download. Try again later or get it from the releases page.") }
        let root = cachesDir.appendingPathComponent("download-\(Int(Date().timeIntervalSince1970))")
        try? fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: root) }
        progress("Downloading version \(info.version)…")
        let tmp = root.appendingPathComponent("update.dmg")
        guard downloadFile(dmgURL, to: tmp, onProgress: { fraction($0 * 0.9) }) else { return (nil, "Couldn’t download the update.") }
        progress("Verifying…"); fraction(0.95)
        if let e = verify(tmp, info) { return (nil, e) }
        let folder = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? fm.homeDirectoryForCurrentUser
        var dest = folder.appendingPathComponent("Claude-Usage-\(info.version).dmg")
        var n = 1
        while fm.fileExists(atPath: dest.path) { dest = folder.appendingPathComponent("Claude-Usage-\(info.version)-\(n).dmg"); n += 1 }      // never overwrite or delete your files
        guard (try? fm.moveItem(at: tmp, to: dest)) != nil else { return (nil, "Couldn’t save the installer to your Downloads folder.") }
        fraction(1)
        return (dest, nil)
    }

    private static func sha256Hex(of url: URL) -> String? {
        guard let d = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
    }

    /// Fingerprint of the app's executable, stored when an update is prepared and re-checked before it is installed.
    static func executableHash(_ app: URL) -> String? { sha256Hex(of: app.appendingPathComponent("Contents/MacOS/ClaudeUsage")) }

    private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
        func urlSession(_ s: URLSession, task: URLSessionTask, willPerformHTTPRedirection r: HTTPURLResponse, newRequest req: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(req.url?.scheme == "https" && Updater.isAllowedRedirectHost(req.url?.host) ? req : nil)
        }
    }

    private static func fetchData(_ url: URL, timeout: TimeInterval) -> Data? {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config, delegate: RedirectGuard(), delegateQueue: nil)
        let sem = DispatchSemaphore(value: 0)
        var out: Data?
        session.dataTask(with: URLRequest(url: url, timeoutInterval: timeout)) { d, r, _ in
            if (r as? HTTPURLResponse)?.statusCode == 200, let d = d, d.count < 10_000 { out = d }        // a signature is ~90 bytes
            sem.signal()
        }.resume()
        sem.wait(); session.finishTasksAndInvalidate()
        return out
    }

    /// Downloads the release disk image and installs nothing until it passes every check: the release signature
    /// (Ed25519, made offline), its SHA-256, the app's bundle id and version, and its code signature.
    /// `fraction` reports overall progress 0...1 (download 0–0.8, then checks and unpacking).
    static func prepare(_ info: UpdateInfo, lowPriority: Bool = false, progress: @escaping (String) -> Void, fraction: @escaping (Double) -> Void = { _ in }) -> (app: URL?, error: String?) {
        let fm = FileManager.default
        guard let dmgURL = info.dmgURL, isTrustedAsset(dmgURL) else { return (nil, "This release has no download. Try again later or reinstall from the releases page.") }
        guard info.sha256 != nil, info.sigURL != nil else {
            return (nil, "This release isn’t signed, so it won’t be installed automatically. Download it from the releases page instead.")
        }
        let root = cachesDir.appendingPathComponent("update-\(Int(Date().timeIntervalSince1970))")
        do { try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) } catch { return (nil, "Couldn’t create a work folder.") }

        progress("Downloading version \(info.version)…")
        let dmg = root.appendingPathComponent("update.dmg")
        guard downloadFile(dmgURL, to: dmg, onProgress: { fraction($0 * 0.8) }) else { return (nil, "Couldn’t download the update.") }

        progress("Verifying…"); fraction(0.85)
        if let e = verify(dmg, info) { try? fm.removeItem(at: root); return (nil, e) }

        progress("Unpacking…"); fraction(0.9)
        guard let again = sha256Hex(of: dmg), again == info.sha256?.lowercased() else { try? fm.removeItem(at: root); return (nil, "The download changed after it was checked, so it was discarded.") }    // closes the gap between checking and mounting
        let mount = root.appendingPathComponent("mnt")
        try? fm.createDirectory(at: mount, withIntermediateDirectories: true)
        guard run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noverify", "-mountpoint", mount.path]) == 0 else {
            return (nil, "Couldn’t open the downloaded disk image.")
        }
        defer { run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
        let app = root.appendingPathComponent("Claude Usage.app")
        guard run("/usr/bin/ditto", [mount.appendingPathComponent("Claude Usage.app").path, app.path]) == 0 else {
            return (nil, "The disk image didn’t contain the app.")
        }
        fraction(0.96)
        let plist = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard plist?["CFBundleIdentifier"] as? String == "local.claudeusage" else { return (nil, "The download isn’t Claude Usage.") }
        guard plist?["CFBundleShortVersionString"] as? String == info.version else {
            return (nil, "The download held a different version than the release says.")
        }
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) == 0 else { return (nil, "The app’s signature didn’t check out.") }
        try? fm.removeItem(at: dmg)                                  // the verified app is all that's kept
        fraction(1)
        return (app, nil)
    }

    /// Hands a built app to a helper that waits for this app to quit, swaps it in (keeping the old one as a backup)
    /// and relaunches. Returns an error message, or nil once the hand-off has started – the caller should then quit.
    /// `dest` / `relaunch` exist so the flow can be tested without touching the installed app.
    static func apply(_ app: URL, dest: URL = Bundle.main.bundleURL, relaunch: Bool = true) -> String? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: app.path) else { return "The downloaded update is no longer there. Check for updates again." }
        guard app.path.hasPrefix(cachesDir.path + "/"), dest.pathExtension == "app",
              run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) == 0 else { return "The update didn’t pass its final check, so it wasn’t installed." }
        let backup = cachesDir.appendingPathComponent("previous/Claude Usage.app")
        try? fm.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let script = app.deletingLastPathComponent().appendingPathComponent("swap.sh")
        let body = """
        #!/bin/zsh
        # waits for the running app to quit, swaps in the new build (keeping the old one as a backup), then relaunches
        PID="$1"; NEW="$2"; DEST="$3"; BACKUP="$4"; RELAUNCH="$5"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.3; done
        rm -rf "$BACKUP"
        [ -d "$DEST" ] && mv "$DEST" "$BACKUP"
        if cp -R "$NEW" "$DEST"; then
          [ "$RELAUNCH" = "1" ] && open "$DEST"
        else
          [ -d "$BACKUP" ] && mv "$BACKUP" "$DEST"
          [ "$RELAUNCH" = "1" ] && open "$DEST"
        fi
        """
        guard (try? body.write(to: script, atomically: true, encoding: .utf8)) != nil else { return "Couldn’t prepare the installer." }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), app.path, dest.path, backup.path, relaunch ? "1" : "0"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "Couldn’t start the installer." }
        return nil
    }

    /// Prepare and apply in one go (used by the Update Now button and the command-line test).
    static func install(_ info: UpdateInfo, dest: URL = Bundle.main.bundleURL, relaunch: Bool = true, progress: @escaping (String) -> Void, fraction: @escaping (Double) -> Void = { _ in }) -> String? {
        let r = prepare(info, progress: progress, fraction: { fraction($0 * 0.95) })
        guard let app = r.app else { return r.error }
        progress("Installing…"); fraction(0.97)
        let err = apply(app, dest: dest, relaunch: relaunch)
        if err == nil { fraction(1) }
        return err
    }


    // MARK: remembering a downloaded update across restarts

    static func savePrepared(_ info: UpdateInfo, app: URL) {
        UserDefaults.standard.set(["version": info.version, "notes": info.notes, "path": app.path, "hash": executableHash(app) ?? ""] as [String: Any], forKey: "preparedUpdate")
    }
    static func clearPrepared() { UserDefaults.standard.removeObject(forKey: "preparedUpdate") }

    /// A previously downloaded update that's still on disk, still newer than the installed version, inside our own cache
    /// folder, and byte-for-byte the executable that was verified when it was downloaded.
    static func restorePrepared() -> (UpdateInfo, URL)? {
        guard let d = UserDefaults.standard.dictionary(forKey: "preparedUpdate"),
              let version = d["version"] as? String, let path = d["path"] as? String, let hash = d["hash"] as? String, !hash.isEmpty,
              path.hasPrefix(cachesDir.path + "/"), !path.contains(".."),
              isNewer(version, than: installed), FileManager.default.fileExists(atPath: path),
              (NSDictionary(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String) == version,
              executableHash(URL(fileURLWithPath: path)) == hash
        else { clearPrepared(); return nil }
        return (UpdateInfo(version: version, notes: d["notes"] as? [String] ?? []), URL(fileURLWithPath: path))
    }
}
