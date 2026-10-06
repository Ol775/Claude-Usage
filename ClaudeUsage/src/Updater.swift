import Foundation

// Checks the GitHub repo for a newer version than the one installed.

struct UpdateInfo { let version: String; let notes: [String] }

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
    static var installed: String { ProcessInfo.processInfo.environment["CUB_PRETEND_VERSION"] ?? AppInfo.version }

    private static func ghBinary() -> String? {
        ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "\(NSHomeDirectory())/.local/bin/gh"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Reads a file from the repo's main branch. Uses the GitHub CLI when it's installed (that works for a private
    /// repo with your own login); otherwise tries the public raw URL (works once the repo is public).
    static func fetch(_ path: String) -> String? {
        if let gh = ghBinary() {
            let p = Process(); p.executableURL = URL(fileURLWithPath: gh)
            p.arguments = ["api", "repos/\(repo)/contents/\(path)", "--jq", ".content"]
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
            p.environment = env
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
            if (try? p.run()) != nil {
                DispatchQueue.global().asyncAfter(deadline: .now() + 20) { if p.isRunning { p.terminate() } }
                let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
                if p.terminationStatus == 0,
                   let b64 = String(data: data, encoding: .utf8),
                   let decoded = Data(base64Encoded: b64.trimmingCharacters(in: .whitespacesAndNewlines), options: .ignoreUnknownCharacters),
                   let text = String(data: decoded, encoding: .utf8) { return text }
            }
        }
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

    /// Blocking check – call from a background queue.
    static func check() -> UpdateStatus {
        guard let raw = fetch("ClaudeUsage/VERSION") else {
            return .failed("Couldn’t reach GitHub. Check your internet connection and try again.")
        }
        let latest = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !latest.isEmpty, latest.first?.isNumber == true else { return .failed("Unexpected version file on GitHub.") }
        guard isNewer(latest, than: installed) else { return .upToDate(Date()) }
        let notes = fetch("ClaudeUsage/CHANGELOG.md").map { notes(from: $0, newerThan: installed) } ?? []
        return .available(UpdateInfo(version: latest, notes: notes))
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

    /// Downloads the main branch as a tarball (through the GitHub CLI if it’s signed in, else the public URL).
    private static func download(to file: URL) -> Bool {
        FileManager.default.createFile(atPath: file.path, contents: nil)
        if let gh = ghBinary(), let out = try? FileHandle(forWritingTo: file) {
            let p = Process(); p.executableURL = URL(fileURLWithPath: gh); p.arguments = ["api", "repos/\(repo)/tarball/main"]
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
            p.environment = env; p.standardOutput = out; p.standardError = FileHandle.nullDevice
            if (try? p.run()) != nil {
                DispatchQueue.global().asyncAfter(deadline: .now() + 180) { if p.isRunning { p.terminate() } }
                p.waitUntilExit()
            }
            try? out.close()
            if p.terminationStatus == 0, ((try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0) > 1000 { return true }
        }
        guard let url = URL(string: "https://github.com/\(repo)/archive/refs/heads/main.tar.gz") else { return false }
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        URLSession.shared.downloadTask(with: URLRequest(url: url, timeoutInterval: 120)) { tmp, resp, _ in
            if (resp as? HTTPURLResponse)?.statusCode == 200, let tmp = tmp { try? FileManager.default.removeItem(at: file); ok = (try? FileManager.default.moveItem(at: tmp, to: file)) != nil }
            sem.signal()
        }.resume()
        sem.wait()
        return ok
    }

    private static var cachesDir: URL {
        if let o = ProcessInfo.processInfo.environment["CUB_CACHE_DIR"] { return URL(fileURLWithPath: o) }       // tests use their own folder
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ClaudeUsage")
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

    /// Downloads and builds the update, but does not install it. Returns the built app, or an error message.
    static func prepare(_ info: UpdateInfo, lowPriority: Bool = false, progress: @escaping (String) -> Void) -> (app: URL?, error: String?) {
        let fm = FileManager.default
        let root = cachesDir.appendingPathComponent("update-\(Int(Date().timeIntervalSince1970))")
        do { try fm.createDirectory(at: root, withIntermediateDirectories: true) } catch { return (nil, "Couldn’t create a work folder.") }

        progress("Downloading version \(info.version)…")
        let tar = root.appendingPathComponent("source.tar.gz")
        guard download(to: tar) else { return (nil, "Couldn’t download the update from GitHub. Check your internet connection and try again.") }

        progress("Unpacking…")
        guard run("/usr/bin/tar", ["-xzf", tar.path, "-C", root.path], lowPriority: lowPriority) == 0,
              let top = (try? fm.contentsOfDirectory(atPath: root.path))?.first(where: { $0 != "source.tar.gz" && !$0.hasPrefix(".") }) else { return (nil, "Couldn’t unpack the download.") }
        let src = root.appendingPathComponent(top).appendingPathComponent("ClaudeUsage")
        let got = (try? String(contentsOf: src.appendingPathComponent("VERSION"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard got == info.version else { return (nil, "GitHub now has version \(got ?? "?") instead of \(info.version). Check for updates again.") }

        guard run("/usr/bin/xcrun", ["--find", "swiftc"]) == 0 else {
            return (nil, "Building the update needs Apple’s command line tools. Run “xcode-select --install” in Terminal, then try again.")
        }
        progress("Building… this takes about a minute")
        let logURL = cachesDir.appendingPathComponent("last-update.log")
        fm.createFile(atPath: logURL.path, contents: nil)
        let log = try? FileHandle(forWritingTo: logURL)
        let status = run("/bin/zsh", ["build.sh"], cwd: src, log: log, timeout: 900, lowPriority: lowPriority)
        try? log?.close()
        let app = src.appendingPathComponent("Claude Usage.app")
        let built = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
        guard status == 0, built == info.version else { return (nil, "The build failed. Details: \(logURL.path)") }
        return (app, nil)
    }

    /// Hands a built app to a helper that waits for this app to quit, swaps it in (keeping the old one as a backup)
    /// and relaunches. Returns an error message, or nil once the hand-off has started – the caller should then quit.
    /// `dest` / `relaunch` exist so the flow can be tested without touching the installed app.
    static func apply(_ app: URL, dest: URL = Bundle.main.bundleURL, relaunch: Bool = true) -> String? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: app.path) else { return "The downloaded update is no longer there. Check for updates again." }
        let backup = cachesDir.appendingPathComponent("previous/Claude Usage.app")
        try? fm.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
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
    static func install(_ info: UpdateInfo, dest: URL = Bundle.main.bundleURL, relaunch: Bool = true, progress: @escaping (String) -> Void) -> String? {
        let r = prepare(info, progress: progress)
        guard let app = r.app else { return r.error }
        progress("Installing…")
        return apply(app, dest: dest, relaunch: relaunch)
    }

    // MARK: remembering a downloaded update across restarts

    static func savePrepared(_ info: UpdateInfo, app: URL) {
        UserDefaults.standard.set(["version": info.version, "notes": info.notes, "path": app.path] as [String: Any], forKey: "preparedUpdate")
    }
    static func clearPrepared() { UserDefaults.standard.removeObject(forKey: "preparedUpdate") }

    /// A previously downloaded update that's still on disk and still newer than the installed version.
    static func restorePrepared() -> (UpdateInfo, URL)? {
        guard let d = UserDefaults.standard.dictionary(forKey: "preparedUpdate"),
              let version = d["version"] as? String, let path = d["path"] as? String,
              isNewer(version, than: installed), FileManager.default.fileExists(atPath: path),
              (NSDictionary(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String) == version
        else { clearPrepared(); return nil }
        return (UpdateInfo(version: version, notes: d["notes"] as? [String] ?? []), URL(fileURLWithPath: path))
    }
}
