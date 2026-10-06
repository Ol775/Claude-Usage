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
    static let repo = "Ol775/MacApps"
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
