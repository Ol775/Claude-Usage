import Foundation
import AppKit

/// Legal text and bug-report helpers shown in Settings → Help & Legal.
enum Legal {
    struct Section: Identifiable { let id: String, title: String, body: [String] }

    static let updated = "7 October 2026"

    static let sections: [Section] = [
        Section(id: "about", title: "About this app", body: [
            "Claude Usage is an independent, unofficial app. It is not made, endorsed or supported by Anthropic.",
            "“Claude”, “Claude Code” and “Anthropic” are trademarks of Anthropic, PBC. “ChatGPT”, “Codex” and “OpenAI” are trademarks of OpenAI. They are used here only to say what the app works with, and the app isn’t affiliated with either company.",
            "The OpenDyslexic font is included under the SIL Open Font License 1.1 (© Abbie Gonzalez). Its licence ships inside the app and is listed in THIRD_PARTY.md in the repository.",
        ]),
        Section(id: "terms", title: "Terms of use", body: [
            "By using Claude Usage you agree to these terms. If you don’t agree, please stop using the app and delete it.",
            "The app is free, beta software. It is provided “as is” and “as available”, with no warranty of any kind, whether express or implied. That includes fitness for a particular purpose, accuracy and uninterrupted operation.",
            "To the fullest extent the law allows, the developer is not liable for any loss or damage that comes from using the app. That includes lost work, unexpected charges, missed or wrong alerts, and anything that follows from relying on a figure or forecast it shows.",
            "You are responsible for using the app in line with Anthropic’s own terms, policies and usage rules for your Claude account and Claude Code.",
            "The app may change, stop working or be withdrawn at any time, for example if Anthropic changes the service it reads from.",
        ]),
        Section(id: "accuracy", title: "Accuracy of figures", body: [
            "Session and weekly limits come from the same Anthropic service that Claude Code’s /usage command reads, and ChatGPT limits come from the service OpenAI’s Codex CLI uses. Neither is a public, documented API, so the figures may change, be delayed or be wrong.",
            "Forecasts, “on pace” warnings and reset predictions are estimates based on your recent activity. They are not guarantees.",
            "Costs shown are API-equivalent estimates worked out from public list prices and the logs on your Mac. They are not what your plan bills, and they are not an invoice or a financial record.",
            "Token and message counts come from Claude Code’s local log files, which Claude Code may change or delete. Don’t rely on them for accounting or billing.",
        ]),
        Section(id: "privacy", title: "Privacy and your data", body: [
            "Claude Usage works on your Mac. Your usage history, saved activity, settings and profile photo are stored only on this Mac, in Application Support/ClaudeUsage and the app’s preferences.",
            "The app reads Claude Code’s log files in ~/.claude/projects, and the sign-in token Claude Code keeps in your keychain. The token is used only to ask Anthropic for your usage limits. It is never stored by the app, logged or sent anywhere else.",
            "ChatGPT usage is experimental, optional and off until you connect it in Settings → Account. It needs a paid ChatGPT plan, and it shows your Codex usage limits. When it’s on, the app reads the sign-in that OpenAI’s Codex CLI saves in ~/.codex/auth.json and uses it only to ask ChatGPT for your usage limits. It never changes, refreshes, copies or stores that login, and it does not read your chats.",
            "The app makes up to three kinds of network request: to Anthropic, for your usage limits; to ChatGPT, for your ChatGPT limits, only if you connect it; and to GitHub, to check for and download updates. The developer runs no servers, receives no analytics, and collects no data about you.",
            "Reports and diagnostics leave your Mac only when you choose to send them. “Report a Bug” opens a pre-filled GitHub page that you review and submit yourself.",
            "You can delete everything the app stores with Settings → Data → Delete all my data, or by quitting it and removing the ClaudeUsage folder in ~/Library/Application Support.",
        ]),
        Section(id: "updates", title: "Updates and open source", body: [
            "Updates are downloaded from the project’s GitHub releases. Each release is signed with a key held only by the developer, and the app installs an update only if its signature, checksum and contents check out. Installing one replaces the app with the new version and keeps the old one as a backup in your Caches folder.",
            "Only install updates from a source you trust. The source code is available for you to read at the link under About, and SECURITY.md in the repository explains how updates are verified.",
        ]),
    ]

    /// Supplies the app's current yes/no states for diagnostics (set at launch; see `AppDelegate.diagnosticState`).
    /// Each line is built from a fixed vocabulary (booleans, counts, enum words), never from account, path or usage data.
    static var stateProvider: () -> [String] = { [] }

    /// Facts that help diagnose a bug. No account details, file paths or usage numbers.
    /// (Recent events are short status messages such as "Usage unavailable (HTTP 500)", with the home folder shortened to ~.)
    static var diagnostics: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let os = "\(v.majorVersion).\(v.minorVersion)"            // version only: the build string adds little and is more identifying
        return """
        App: Claude Usage \(AppInfo.version) \(AppInfo.stage) (build \(AppInfo.build))
        macOS: \(os)
        Chip: \(chip)
        \(stateProvider().joined(separator: "\n"))
        Recent events:
        \(AppLog.recent())
        """
    }

    private static var chip: String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        let s = String(cString: buf)
        return s.isEmpty ? "unknown" : s
    }

    static var issueTemplate: String {
        """
        ## What happened


        ## What I expected


        ## Steps to reproduce
        1.

        ## Details (added by the app, edit freely)
        ```
        \(diagnostics.replacingOccurrences(of: "```", with: "\u{27}\u{27}\u{27}"))
        ```
        """
    }

    static var newIssueURL: URL {
        var c = URLComponents(string: AppInfo.repoURL.absoluteString + "/issues/new")!
        let enc: (String) -> String = { $0.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) ?? "" }   // encodes + & # and newlines
        c.percentEncodedQuery = "title=\(enc("Bug: "))&body=\(enc(issueTemplate))"
        return c.url ?? AppInfo.repoURL
    }

    static var issuesURL: URL { AppInfo.repoURL.appendingPathComponent("issues") }

    static func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics, forType: .string)
    }
}


/// A small rolling log of problems (failed fetches, update errors) kept on this Mac only. It never holds tokens, emails or
/// usage numbers, and it is only shared if you paste the diagnostics into a bug report.
enum AppLog {
    static var url: URL { supportDir().appendingPathComponent("app.log") }
    private static var lastWritten: [String: Date] = [:]
    private static let lock = NSLock()

    static func write(_ message: String) {
        lock.lock(); defer { lock.unlock() }
        var clean = message.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        if NSUserName().count >= 4 { clean = clean.replacingOccurrences(of: NSUserName(), with: "<user>", options: .caseInsensitive) }     // very short names would mangle ordinary words
        clean = String(clean.unicodeScalars.map { $0.properties.isWhitespace ? " " : $0 }.map(Character.init))        // no line breaks or control layout
        guard !clean.isEmpty else { return }
        if let t = lastWritten[clean], Date().timeIntervalSince(t) < 3600 { return }      // the same problem is logged at most once an hour, even when two alternate
        lastWritten[clean] = Date()
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(clean)\n"
        var text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        text += line
        if text.utf8.count > 100_000 { text = String(text.split(separator: "\n", omittingEmptySubsequences: true).suffix(300).joined(separator: "\n")) + "\n" }
        try? text.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func recent(_ n: Int = 15) -> String {
        let lines = ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n").suffix(n)
        return lines.isEmpty ? "(none)" : lines.joined(separator: "\n")
    }
}
