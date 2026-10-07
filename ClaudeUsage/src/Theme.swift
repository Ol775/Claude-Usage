import AppKit
import SwiftUI

// MARK: - App info

enum AppInfo {
    /// The official terminal install (checks the DMG checksum, installs to /Applications).
    static let installCommand = "curl -fsSL https://raw.githubusercontent.com/Ol775/Claude-Usage/main/install.sh | zsh"
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1" }
    static var stage: String { Bundle.main.infoDictionary?["ClaudeUsageStage"] as? String ?? "beta" }
    static let repoURL = URL(string: "https://github.com/Ol775/Claude-Usage")!
    static let coffeeURL = URL(string: "https://buymeacoffee.com/ol775")!
    static var display: String { "v\(version) \(stage)" }
}

// MARK: - Themes

/// WCAG contrast ratio between two colours (1–21).
func contrastRatio(_ a: NSColor, _ b: NSColor) -> Double {
    func lum(_ c: NSColor) -> Double {
        guard let s = c.usingColorSpace(.sRGB) else { return 0 }
        func ch(_ x: CGFloat) -> Double { let v = Double(x); return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * ch(s.redComponent) + 0.7152 * ch(s.greenComponent) + 0.0722 * ch(s.blueComponent)
    }
    let x = lum(a), y = lum(b)
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)
}

/// Moves `c` toward `toward` (white or black) until it reaches 4.5:1 against `bg` (WCAG AA for text), so a custom accent stays readable.
func readable(_ c: NSColor, on bg: NSColor, toward: NSColor) -> NSColor {
    var out = c, f: CGFloat = 0
    while contrastRatio(out, bg) < 4.5 && f < 1 { f += 0.05; out = c.blended(withFraction: f, of: toward) ?? c }
    return out
}

enum AccentTheme: String, CaseIterable, Identifiable {
    case claude, blue, green, purple, pink, graphite, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .custom: return "Custom"
        case .claude: return "Claude orange"
        case .blue: return "Ocean blue"
        case .green: return "Forest green"
        case .purple: return "Violet"
        case .pink: return "Rose"
        case .graphite: return "Graphite"
        }
    }
    /// (dark-mode colour, light-mode colour) – dark is brighter, light is deeper, so both stand out from the glass background.
    /// Every light colour is at least 4.5:1 on a white card (3:1 minimum elsewhere); checked with the WCAG contrast formula.
    var colors: (NSColor, NSColor) {
        func c(_ r: Double, _ g: Double, _ b: Double) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
        switch self {
        case .custom:        // your colour, lifted a little for dark mode and deepened for light mode so it stays readable
            let base = colorFromHex(Settings.shared.customAccentHex) ?? c(1.00, 0.55, 0.33)
            return (readable(base.blended(withFraction: 0.18, of: .white) ?? base, on: c(0.16, 0.16, 0.16), toward: .white),
                    readable(base.blended(withFraction: 0.22, of: .black) ?? base, on: .white, toward: .black))
        case .claude: return (c(1.00, 0.55, 0.33), c(0.75, 0.29, 0.09))
        case .blue: return (c(0.36, 0.67, 1.00), c(0.00, 0.37, 0.80))
        case .green: return (c(0.30, 0.85, 0.52), c(0.07, 0.48, 0.24))
        case .purple: return (c(0.72, 0.58, 1.00), c(0.46, 0.22, 0.80))
        case .pink: return (c(1.00, 0.45, 0.65), c(0.77, 0.13, 0.38))
        case .graphite: return (c(0.78, 0.80, 0.84), c(0.30, 0.32, 0.36))
        }
    }
}

/// The typeface used across the dashboard windows. OpenDyslexic is bundled (SIL Open Font License) so it works without installing it.
enum FontChoice: String, CaseIterable, Identifiable {
    case system, rounded, serif, mono, dyslexic
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        case .mono: return "Monospaced"
        case .dyslexic: return "OpenDyslexic"
        }
    }
    var detail: String {
        switch self {
        case .system: return "The standard macOS font."
        case .rounded: return "Softer letter shapes."
        case .serif: return "A traditional serif face."
        case .mono: return "Every character the same width."
        case .dyslexic: return "Weighted letter bottoms to help tell letters apart; designed for readers with dyslexia."
        }
    }
}

enum TextSize: String, CaseIterable, Identifiable {
    case small, standard, large, xlarge
    var id: String { rawValue }
    var label: String { switch self { case .small: return "Small"; case .standard: return "Standard"; case .large: return "Large"; case .xlarge: return "Extra large" } }
    var scale: CGFloat { switch self { case .small: return 0.9; case .standard: return 1; case .large: return 1.15; case .xlarge: return 1.3 } }
}

enum CardCorners: String, CaseIterable, Identifiable {
    case sharp, standard, round
    var id: String { rawValue }
    var label: String { switch self { case .sharp: return "Sharp"; case .standard: return "Standard"; case .round: return "Round" } }
    var radius: CGFloat { switch self { case .sharp: return 6; case .standard: return 14; case .round: return 24 } }
}

/// Colour of the menu bar icon.
enum MenuIconStyle: String, CaseIterable, Identifiable {
    case follow, claude, match, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .follow: return "Follow the colour theme"
        case .claude: return "Claude orange"
        case .match: return "Match the menu bar (black or white)"
        case .custom: return "Custom colour"
        }
    }
}

/// "#RRGGBB" <-> NSColor, for colours the user picks.
func colorFromHex(_ hex: String) -> NSColor? {
    var h = hex.trimmingCharacters(in: .whitespaces); if h.hasPrefix("#") { h.removeFirst() }
    guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
    return NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
}
func hexFromColor(_ c: NSColor) -> String {
    let s = c.usingColorSpace(.sRGB) ?? c
    return String(format: "#%02X%02X%02X", Int((s.redComponent * 255).rounded()), Int((s.greenComponent * 255).rounded()), Int((s.blueComponent * 255).rounded()))
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark, oled
    var id: String { rawValue }
    var label: String {
        switch self { case .system: return "Follow system"; case .light: return "Light"; case .dark: return "Dark"; case .oled: return "OLED black" }
    }
}

enum NotifImportance: String, CaseIterable, Identifiable {
    case normal, critical, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .normal: return "Normal"
        case .critical: return "Important for critical alerts"
        case .all: return "Important for all alerts"
        }
    }
}


var currentTheme: AccentTheme = .claude

/// The accent colour. Dynamic: resolves per appearance and follows the selected theme.
/// There is one colour object per theme (and per custom colour), so when the theme changes SwiftUI sees a different colour and redraws;
/// a single shared dynamic colour would leave some views, and the charts, showing the old accent.
var claudeOrange: NSColor {
    let key = currentTheme.rawValue + (currentTheme == .custom ? Settings.shared.customAccentHex : "")
    if let c = accentColours[key] { return c }
    let (dark, light) = currentTheme.colors
    let c = NSColor(name: nil) { a in a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    accentColours[key] = c
    return c
}
private var accentColours: [String: NSColor] = [:]
let alertRed = NSColor(name: nil) { a in
    a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(srgbRed: 1.00, green: 0.36, blue: 0.33, alpha: 1)
        : NSColor(srgbRed: 0.82, green: 0.12, blue: 0.14, alpha: 1)
}

// MARK: - Settings

final class Settings: ObservableObject {
    static let shared = Settings()
    static var persist = true            // tests/tours turn this off so they never touch real settings
    private let d = UserDefaults.standard
    var onChange: () -> Void = {}

    @Published var appearance: AppearanceMode { didSet { if Settings.persist { d.set(appearance.rawValue, forKey: "appearance") }; applyAppearance(); onChange() } }
    @Published var theme: AccentTheme { didSet { currentTheme = theme; if Settings.persist { d.set(theme.rawValue, forKey: "theme") }; onChange() } }
    @Published var showInDock: Bool { didSet { if Settings.persist { d.set(showInDock, forKey: "showInDock") }; onChange() } }
    @Published var notificationsOn: Bool { didSet { if Settings.persist { d.set(notificationsOn, forKey: "notificationsOn") } } }
    @Published var menuShowIcon: Bool { didSet { save(menuShowIcon, "menuShowIcon"); onChange() } }
    @Published var menuShowSession: Bool { didSet { save(menuShowSession, "menuShowSession"); onChange() } }
    @Published var menuShowWeekly: Bool { didSet { save(menuShowWeekly, "menuShowWeekly"); onChange() } }
    @Published var chatgptEnabled: Bool { didSet { save(chatgptEnabled, "chatgptEnabled"); onChange() } }
    @Published var menuShowChatGPT: Bool { didSet { save(menuShowChatGPT, "menuShowChatGPT"); onChange() } }
    @Published var menuShowTokens: Bool { didSet { save(menuShowTokens, "menuShowTokens"); onChange() } }
    @Published var menuShowReset: Bool { didSet { save(menuShowReset, "menuShowReset"); onChange() } }
    @Published var menuIconStyle: MenuIconStyle { didSet { save(menuIconStyle.rawValue, "menuIconStyle"); onChange() } }
    @Published var menuIconHex: String { didSet { save(menuIconHex, "menuIconHex"); onChange() } }
    @Published var customAccentHex: String { didSet { save(customAccentHex, "customAccentHex"); onChange() } }
    @Published var fontChoice: FontChoice { didSet { save(fontChoice.rawValue, "fontChoice") } }
    @Published var textSize: TextSize { didSet { save(textSize.rawValue, "textSize") } }
    @Published var cardCorners: CardCorners { didSet { save(cardCorners.rawValue, "cardCorners") } }
    @Published var displayName: String { didSet { save(displayName, "displayName") } }
    @Published var menuLabelStyle: MenuLabelStyle { didSet { save(menuLabelStyle.rawValue, "menuLabelStyle"); onChange() } }
    @Published var menuPercentColour: MenuPercentColour { didSet { save(menuPercentColour.rawValue, "menuPercentColour"); onChange() } }
    @Published var autoDownloadUpdates: Bool { didSet { save(autoDownloadUpdates, "autoDownloadUpdates") } }
    @Published var autoCheckUpdates: Bool { didSet { if Settings.persist { d.set(autoCheckUpdates, forKey: "autoCheckUpdates") }; onChange() } }
    @Published var importance: NotifImportance { didSet { if Settings.persist { d.set(importance.rawValue, forKey: "importance") } } }
    @Published var warnThreshold: Int { didSet { if Settings.persist { d.set(warnThreshold, forKey: "warnThreshold") } } }
    @Published var criticalThreshold: Int { didSet { if Settings.persist { d.set(criticalThreshold, forKey: "criticalThreshold") } } }
    @Published var refreshMinutes: Int { didSet { if Settings.persist { d.set(refreshMinutes, forKey: "refreshMinutes") }; onChange() } }
    @Published var predictiveAlerts: Bool { didSet { if Settings.persist { d.set(predictiveAlerts, forKey: "predictiveAlerts") } } }
    @Published var readingsKeepDays: Int { didSet { save(readingsKeepDays, "readingsKeepDays") } }      // limit readings (charts, forecasts): 30–90
    @Published var activityKeepDays: Int { didSet { save(activityKeepDays, "activityKeepDays") } }      // daily activity; 0 = forever
    @Published var quietHoursOn: Bool { didSet { save(quietHoursOn, "quietHoursOn") } }
    @Published var quietStart: Int { didSet { save(quietStart, "quietStart") } }                        // hour of day, 0–23
    @Published var quietEnd: Int { didSet { save(quietEnd, "quietEnd") } }
    @Published var betaUpdates: Bool { didSet { save(betaUpdates, "betaUpdates") } }
    /// Limit alerts are held back until this time ("Snooze 1 hour" on an alert). Not exported.
    @Published var snoozedUntil: Date? { didSet { if Settings.persist { d.set(snoozedUntil, forKey: "snoozedUntil") } } }
    var alertsPaused: Bool { inQuietHours() || (snoozedUntil.map { $0 > Clock.now } ?? false) }

    /// Keeps only known keys with plain values (true/false, numbers, short text), for importing a settings file.
    static func validated(_ raw: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for k in keys {
            if let n = raw[k] as? NSNumber, n.doubleValue.isFinite, abs(n.doubleValue) < 10_000 { out[k] = n }
            else if let t = raw[k] as? String, t.count <= 64 { out[k] = t }
        }
        return out
    }

    /// Every current setting under its preference key (for export) – including ones still at their default.
    var exported: [String: Any] {
        ["appearance": appearance.rawValue, "theme": theme.rawValue, "showInDock": showInDock, "notificationsOn": notificationsOn,
         "predictiveAlerts": predictiveAlerts, "menuShowIcon": menuShowIcon, "menuShowSession": menuShowSession, "menuShowWeekly": menuShowWeekly,
         "chatgptEnabled": chatgptEnabled, "menuShowChatGPT": menuShowChatGPT, "menuShowTokens": menuShowTokens, "menuShowReset": menuShowReset,
         "menuIconStyle": menuIconStyle.rawValue, "menuIconHex": menuIconHex, "customAccentHex": customAccentHex, "fontChoice": fontChoice.rawValue,
         "textSize": textSize.rawValue, "cardCorners": cardCorners.rawValue, "displayName": displayName, "menuLabelStyle": menuLabelStyle.rawValue,
         "menuPercentColour": menuPercentColour.rawValue, "autoDownloadUpdates": autoDownloadUpdates, "autoCheckUpdates": autoCheckUpdates,
         "importance": importance.rawValue, "warnThreshold": warnThreshold, "criticalThreshold": criticalThreshold, "refreshMinutes": refreshMinutes,
         "readingsKeepDays": readingsKeepDays, "activityKeepDays": activityKeepDays, "quietHoursOn": quietHoursOn, "quietStart": quietStart,
         "quietEnd": quietEnd, "betaUpdates": betaUpdates]
    }

    /// Re-reads every preference (after an import) so the whole app updates without a restart.
    func reload() {
        let f = Settings()
        appearance = f.appearance; theme = f.theme; showInDock = f.showInDock; notificationsOn = f.notificationsOn
        predictiveAlerts = f.predictiveAlerts; menuShowIcon = f.menuShowIcon; menuShowSession = f.menuShowSession
        menuShowWeekly = f.menuShowWeekly; chatgptEnabled = f.chatgptEnabled; menuShowChatGPT = f.menuShowChatGPT
        menuShowTokens = f.menuShowTokens; menuShowReset = f.menuShowReset; menuIconStyle = f.menuIconStyle; menuIconHex = f.menuIconHex
        customAccentHex = f.customAccentHex; fontChoice = f.fontChoice; textSize = f.textSize; cardCorners = f.cardCorners
        displayName = f.displayName; menuLabelStyle = f.menuLabelStyle; menuPercentColour = f.menuPercentColour
        autoDownloadUpdates = f.autoDownloadUpdates; autoCheckUpdates = f.autoCheckUpdates; importance = f.importance
        warnThreshold = f.warnThreshold; criticalThreshold = f.criticalThreshold; refreshMinutes = f.refreshMinutes
        readingsKeepDays = f.readingsKeepDays; activityKeepDays = f.activityKeepDays
        quietHoursOn = f.quietHoursOn; quietStart = f.quietStart; quietEnd = f.quietEnd; betaUpdates = f.betaUpdates
    }

    /// Every preference key, for settings export and import (nothing else in UserDefaults is ever exported or accepted).
    static let keys = ["appearance", "theme", "showInDock", "notificationsOn", "predictiveAlerts", "menuShowIcon", "menuShowSession",
        "menuShowWeekly", "chatgptEnabled", "menuShowChatGPT", "menuShowTokens", "menuShowReset", "menuIconStyle", "menuIconHex",
        "customAccentHex", "fontChoice", "textSize", "cardCorners", "displayName", "menuLabelStyle", "menuPercentColour",
        "autoDownloadUpdates", "autoCheckUpdates", "importance", "warnThreshold", "criticalThreshold", "refreshMinutes",
        "readingsKeepDays", "activityKeepDays", "quietHoursOn", "quietStart", "quietEnd", "betaUpdates"]

    /// True while quiet hours are on and `now` falls inside them (the window may cross midnight).
    func inQuietHours(_ now: Date = Clock.now) -> Bool {
        guard quietHoursOn, quietStart != quietEnd else { return false }
        let h = Calendar.current.component(.hour, from: now)
        return quietStart < quietEnd ? (h >= quietStart && h < quietEnd) : (h >= quietStart || h < quietEnd)
    }

    init() {
        appearance = AppearanceMode(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
        theme = AccentTheme(rawValue: d.string(forKey: "theme") ?? "") ?? .claude
        showInDock = d.object(forKey: "showInDock") as? Bool ?? true
        notificationsOn = d.object(forKey: "notificationsOn") as? Bool ?? true
        predictiveAlerts = d.object(forKey: "predictiveAlerts") as? Bool ?? true
        // Menu bar items. Before 0.7 there was a single "display" choice – carry it over once.
        let ud = UserDefaults.standard, old = ud.string(forKey: "menuBarStyle")
        func flag(_ key: String, _ fallback: Bool, from oldValues: [String]? = nil) -> Bool {
            if let v = ud.object(forKey: key) as? Bool { return v }
            if let o = old, let list = oldValues { return list.contains(o) }
            return fallback
        }
        menuShowIcon = flag("menuShowIcon", true)
        menuShowSession = flag("menuShowSession", true, from: ["both", "session"])
        menuShowWeekly = flag("menuShowWeekly", true, from: ["both", "weekly"])
        chatgptEnabled = flag("chatgptEnabled", false)
        menuShowChatGPT = flag("menuShowChatGPT", false)
        menuShowTokens = flag("menuShowTokens", false, from: ["tokens"])
        menuShowReset = flag("menuShowReset", false)
        menuIconStyle = MenuIconStyle(rawValue: ud.string(forKey: "menuIconStyle") ?? "") ?? (flag("menuIconMono", false) ? .match : .follow)     // 0.9 had one "match the menu bar" switch
        menuIconHex = ud.string(forKey: "menuIconHex") ?? "#FF8C54"
        customAccentHex = ud.string(forKey: "customAccentHex") ?? "#7C5CFF"
        fontChoice = FontChoice(rawValue: ud.string(forKey: "fontChoice") ?? "") ?? .system
        textSize = TextSize(rawValue: ud.string(forKey: "textSize") ?? "") ?? .standard
        cardCorners = CardCorners(rawValue: ud.string(forKey: "cardCorners") ?? "") ?? .standard
        displayName = ud.string(forKey: "displayName") ?? ""
        menuLabelStyle = MenuLabelStyle(rawValue: ud.string(forKey: "menuLabelStyle") ?? "") ?? .letters
        menuPercentColour = MenuPercentColour(rawValue: ud.string(forKey: "menuPercentColour") ?? "") ?? .critical
        autoDownloadUpdates = ud.object(forKey: "autoDownloadUpdates") as? Bool ?? true
        autoCheckUpdates = d.object(forKey: "autoCheckUpdates") as? Bool ?? true
        importance = NotifImportance(rawValue: d.string(forKey: "importance") ?? "") ?? .normal
        warnThreshold = min(max(d.object(forKey: "warnThreshold") as? Int ?? 80, 50), 95)          // clamped: values can come from an imported file
        criticalThreshold = min(max(d.object(forKey: "criticalThreshold") as? Int ?? 95, 60), 99)
        refreshMinutes = min(max(d.object(forKey: "refreshMinutes") as? Int ?? 1, 1), 60)
        readingsKeepDays = min(max(d.object(forKey: "readingsKeepDays") as? Int ?? 90, 30), 90)
        activityKeepDays = max(d.object(forKey: "activityKeepDays") as? Int ?? 0, 0)
        quietHoursOn = d.object(forKey: "quietHoursOn") as? Bool ?? false
        quietStart = min(max(d.object(forKey: "quietStart") as? Int ?? 22, 0), 23)
        quietEnd = min(max(d.object(forKey: "quietEnd") as? Int ?? 8, 0), 23)
        betaUpdates = d.object(forKey: "betaUpdates") as? Bool ?? false
        snoozedUntil = d.object(forKey: "snoozedUntil") as? Date
        currentTheme = theme
    }

    /// The menu bar icon in the chosen colour.
    func menuIconImage() -> NSImage {
        switch menuIconStyle {
        case .follow: return menuBarBotImage()
        case .claude: return menuBarBotImage(colour: NSColor(srgbRed: 1.00, green: 0.55, blue: 0.33, alpha: 1))
        case .match: return menuBarBotImage(mono: true)
        case .custom: return menuBarBotImage(colour: colorFromHex(menuIconHex) ?? claudeOrange)
        }
    }

    func applyAppearance() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark, .oled: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
    var isOLED: Bool { appearance == .oled }

    private func save(_ value: Any, _ key: String) { if Settings.persist { d.set(value, forKey: key) } }

    func apply(_ p: MenuBarPreset) {
        switch p {
        case .standard: menuShowIcon = true; menuShowSession = true; menuShowWeekly = true; menuShowTokens = false; menuShowReset = false; menuShowChatGPT = false
        case .compact: menuShowIcon = false; menuShowSession = true; menuShowWeekly = true; menuShowTokens = false; menuShowReset = false; menuShowChatGPT = false
        case .minimal: menuShowIcon = true; menuShowSession = false; menuShowWeekly = false; menuShowTokens = false; menuShowReset = false; menuShowChatGPT = false
        case .everything: menuShowIcon = true; menuShowSession = true; menuShowWeekly = true; menuShowTokens = true; menuShowReset = true; menuShowChatGPT = chatgptEnabled
        }
        menuLabelStyle = .letters; menuPercentColour = .critical
    }
}
