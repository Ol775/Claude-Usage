import AppKit

// Menu bar customisation: what the status item shows, and how.

enum MenuLabelStyle: String, CaseIterable, Identifiable {
    case letters, words, none
    var id: String { rawValue }
    var label: String { self == .letters ? "Letters (D, W)" : (self == .words ? "Words (Session, Week)" : "None") }
}

enum MenuPercentColour: String, CaseIterable, Identifiable {
    case critical, accent, plain
    var id: String { rawValue }
    var label: String { self == .critical ? "Red when critical" : (self == .accent ? "Accent colour" : "Plain") }
}

enum MenuBarPreset: String, CaseIterable, Identifiable {
    case standard, compact, minimal, everything
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var detail: String {
        switch self {
        case .standard: return "Icon, D and W"
        case .compact: return "D and W, no icon"
        case .minimal: return "Icon only"
        case .everything: return "All items"
        }
    }
}

/// One piece of the status item text, e.g. "D 31%".
struct TitlePart {
    let label: String?
    let value: String
    let hot: Bool            // at or over the critical threshold
    let isPercent: Bool
}

enum MenuBarTitle {
    /// "1h 30m", "45m", "2d 4h" – time left until `d`.
    static func shortUntil(_ d: Date) -> String {
        let secs = Int(Clock.until(d))
        guard secs > 0 else { return "now" }
        let days = secs / 86400, h = (secs % 86400) / 3600, m = (secs % 3600) / 60
        return days > 0 ? "\(days)d \(h)h" : (h > 0 ? "\(h)h \(m)m" : "\(max(1, m))m")
    }

    /// The text pieces for the current settings. Falls back to today's tokens when limits aren't available
    /// (for example when signed out), so the item is never empty.
    static func parts(limits: [Limit], tokensToday: Int, settings: Settings, chatgpt: [Limit] = []) -> [TitlePart] {
        let sess = limits.first { $0.kind == .session }, week = limits.first { $0.kind == .weekly }
        let critical = Double(settings.criticalThreshold)
        func label(_ k: LimitKind) -> String? {
            switch settings.menuLabelStyle {
            case .letters: return k == .session ? "D" : "W"
            case .words: return k == .session ? "Session" : "Week"
            case .none: return nil
            }
        }
        var out: [TitlePart] = []
        if settings.menuShowSession, let x = sess { out.append(TitlePart(label: label(.session), value: "\(Int(x.percent.rounded()))%", hot: x.percent >= critical, isPercent: true)) }
        if settings.menuShowWeekly, let x = week { out.append(TitlePart(label: label(.weekly), value: "\(Int(x.percent.rounded()))%", hot: x.percent >= critical, isPercent: true)) }
        if settings.menuShowChatGPT, let g = chatgpt.first {
            out.append(TitlePart(label: settings.menuLabelStyle == .none ? nil : (settings.menuLabelStyle == .letters ? "G" : "ChatGPT"), value: "\(Int(g.percent.rounded()))%", hot: g.percent >= critical, isPercent: true))
        }
        if settings.menuShowReset, let r = sess?.resets { out.append(TitlePart(label: nil, value: "↻ " + shortUntil(r), hot: false, isPercent: false)) }
        let wantsLimits = settings.menuShowSession || settings.menuShowWeekly
        let missingLimits = wantsLimits && !out.contains { $0.isPercent }
        if settings.menuShowTokens || missingLimits { out.append(TitlePart(label: nil, value: fmt(tokensToday), hot: false, isPercent: false)) }
        return out
    }
}
