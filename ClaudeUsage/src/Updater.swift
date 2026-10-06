import Foundation

// Checks the GitHub repo for a newer version than the one installed.

struct UpdateInfo { let version: String; let notes: [String] }

enum UpdateStatus {
    case idle
    case checking
    case upToDate(Date)
    case available(UpdateInfo)
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
            return .failed("Couldn’t reach GitHub. Sign in with the GitHub CLI (gh auth login) or make the repo public.")
        }
        let latest = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !latest.isEmpty, latest.first?.isNumber == true else { return .failed("Unexpected version file on GitHub.") }
        guard isNewer(latest, than: installed) else { return .upToDate(Date()) }
        let notes = fetch("ClaudeUsage/CHANGELOG.md").map { notes(from: $0, newerThan: installed) } ?? []
        return .available(UpdateInfo(version: latest, notes: notes))
    }
}

// MARK: - Installing an update (download from GitHub → build → swap in → relaunch)

extension Updater {
    /// Runs a command and returns its exit status (-1 if it couldn't start). Output goes to `log` when given.
    @discardableResult
    static func run(_ exe: String, _ args: [String], cwd: URL? = nil, log: FileHandle? = nil, timeout: TimeInterval = 600) -> Int32 {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        if let cwd = cwd { p.currentDirectoryURL = cwd }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
        p.environment = env
        p.standardOutput = log ?? FileHandle.nullDevice; p.standardError = log ?? FileHandle.nullDevice
        guard (try? p.run()) != nil else { return -1 }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if p.isRunning { p.terminate() } }
        p.waitUntilExit()
        return p.terminationStatus
    }

    /// Downloads the main branch as a tarball (through the GitHub CLI for a private repo, else the public URL).
    private static func download(to file: URL) -> Bool {
        FileManager.default.createFile(atPath: file.path, contents: nil)
        if let gh = ghBinary(), let out = try? FileHandle(forWritingTo: file) {
            let status = run(gh, ["api", "repos/\(repo)/tarball/main"], log: nil, timeout: 180, stdout: out)
            try? out.close()
            if status == 0, ((try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0) > 1000 { return true }
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

    @discardableResult
    private static func run(_ exe: String, _ args: [String], log: FileHandle?, timeout: TimeInterval, stdout: FileHandle) -> Int32 {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        p.environment = env; p.standardOutput = stdout; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return -1 }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if p.isRunning { p.terminate() } }
        p.waitUntilExit()
        return p.terminationStatus
    }

    static func cleanupOldDownloads() {
        let fm = FileManager.default
        let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ClaudeUsage")
        for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where name.hasPrefix("update-") {
            let url = dir.appendingPathComponent(name)
            if let d = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date, Date().timeIntervalSince(d) > 86400 { try? fm.removeItem(at: url) }
        }
    }

    /// Downloads, builds and hands the new app to a helper that swaps it in once this app has quit.
    /// Returns an error message, or nil once the hand-off has started (the caller should then quit).
    /// `dest` / `relaunch` exist so the flow can be tested without touching the installed app.
    static func install(_ info: UpdateInfo, dest: URL = Bundle.main.bundleURL, relaunch: Bool = true, progress: @escaping (String) -> Void) -> String? {
        let fm = FileManager.default
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ClaudeUsage")
        let root = caches.appendingPathComponent("update-\(Int(Date().timeIntervalSince1970))")
        do { try fm.createDirectory(at: root, withIntermediateDirectories: true) } catch { return "Couldn’t create a work folder." }

        progress("Downloading version \(info.version)…")
        let tar = root.appendingPathComponent("source.tar.gz")
        guard download(to: tar) else { return "Couldn’t download the update from GitHub. Check that the GitHub CLI is signed in (gh auth login)." }

        progress("Unpacking…")
        guard run("/usr/bin/tar", ["-xzf", tar.path, "-C", root.path]) == 0,
              let top = (try? fm.contentsOfDirectory(atPath: root.path))?.first(where: { $0 != "source.tar.gz" && !$0.hasPrefix(".") }) else { return "Couldn’t unpack the download." }
        let src = root.appendingPathComponent(top).appendingPathComponent("ClaudeUsage")
        let got = (try? String(contentsOf: src.appendingPathComponent("VERSION"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard got == info.version else { return "GitHub now has version \(got ?? "?") instead of \(info.version). Check for updates again." }

        guard run("/usr/bin/xcrun", ["--find", "swiftc"]) == 0 else {
            return "Building the update needs Apple’s command line tools. Run “xcode-select --install” in Terminal, then try again."
        }
        progress("Building… this takes about a minute")
        let logURL = caches.appendingPathComponent("last-update.log")
        fm.createFile(atPath: logURL.path, contents: nil)
        let log = try? FileHandle(forWritingTo: logURL)
        let status = run("/bin/zsh", ["build.sh"], cwd: src, log: log, timeout: 900)
        try? log?.close()
        let newApp = src.appendingPathComponent("Claude Usage.app")
        let builtVersion = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
        guard status == 0, builtVersion == info.version else { return "The build failed. Details: \(logURL.path)" }

        progress("Installing…")
        let backup = caches.appendingPathComponent("previous/Claude Usage.app")
        try? fm.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        let script = root.appendingPathComponent("swap.sh")
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
        p.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), newApp.path, dest.path, backup.path, relaunch ? "1" : "0"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "Couldn’t start the installer." }
        return nil
    }
}
