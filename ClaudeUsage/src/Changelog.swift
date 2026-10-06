import Foundation

/// One version's entry from CHANGELOG.md (bundled into the app at build time).
struct ChangelogEntry: Identifiable {
    let version: String, stage: String, date: String
    let items: [String]
    var id: String { version }
}

enum Changelog {
    /// Parses lines like `## 0.5.0 – alpha (2026-10-06)` followed by `- bullet` lines. Newest first, as written.
    static func parse(_ text: String) -> [ChangelogEntry] {
        var out: [ChangelogEntry] = []
        var version = "", stage = "", date = "", items: [String] = []
        func flush() { if !version.isEmpty { out.append(ChangelogEntry(version: version, stage: stage, date: date, items: items)) } }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("## ") {
                flush()
                let head = String(line.dropFirst(3))
                version = head.split(separator: " ").first.map(String.init) ?? ""
                stage = head.contains("–") ? (head.split(separator: "–").last?.split(separator: "(").first?.trimmingCharacters(in: .whitespaces) ?? "") : ""
                date = head.split(separator: "(").dropFirst().first?.trimmingCharacters(in: CharacterSet(charactersIn: ") ")) ?? ""
                items = []
            } else if !version.isEmpty, line.hasPrefix("- ") { items.append(String(line.dropFirst(2))) }
        }
        flush()
        return out
    }

    static func load() -> [ChangelogEntry] {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"), let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(text)
    }
}
