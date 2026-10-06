import AppKit
import SwiftUI

// MARK: - App info

enum AppInfo {
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1" }
    static var stage: String { Bundle.main.infoDictionary?["ClaudeUsageStage"] as? String ?? "alpha" }
    static let repoURL = URL(string: "https://github.com/Ol775/Claude-Usage")!
    static let coffeeURL = URL(string: "https://buymeacoffee.com/ol775")!
    static var display: String { "v\(version) \(stage)" }
}

// MARK: - Themes

enum AccentTheme: String, CaseIterable, Identifiable {
    case claude, blue, green, purple, pink, graphite
    var id: String { rawValue }
    var label: String {
        switch self {
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
        case .claude: return (c(1.00, 0.55, 0.33), c(0.75, 0.29, 0.09))
        case .blue: return (c(0.36, 0.67, 1.00), c(0.00, 0.37, 0.80))
        case .green: return (c(0.30, 0.85, 0.52), c(0.07, 0.48, 0.24))
        case .purple: return (c(0.72, 0.58, 1.00), c(0.46, 0.22, 0.80))
        case .pink: return (c(1.00, 0.45, 0.65), c(0.77, 0.13, 0.38))
        case .graphite: return (c(0.78, 0.80, 0.84), c(0.30, 0.32, 0.36))
        }
    }
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
let claudeOrange = NSColor(name: nil) { a in
    a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? currentTheme.colors.0 : currentTheme.colors.1
}
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
    @Published var menuIconMono: Bool { didSet { save(menuIconMono, "menuIconMono"); onChange() } }
    @Published var menuLabelStyle: MenuLabelStyle { didSet { save(menuLabelStyle.rawValue, "menuLabelStyle"); onChange() } }
    @Published var menuPercentColour: MenuPercentColour { didSet { save(menuPercentColour.rawValue, "menuPercentColour"); onChange() } }
    @Published var autoDownloadUpdates: Bool { didSet { save(autoDownloadUpdates, "autoDownloadUpdates") } }
    @Published var autoCheckUpdates: Bool { didSet { if Settings.persist { d.set(autoCheckUpdates, forKey: "autoCheckUpdates") }; onChange() } }
    @Published var importance: NotifImportance { didSet { if Settings.persist { d.set(importance.rawValue, forKey: "importance") } } }
    @Published var warnThreshold: Int { didSet { if Settings.persist { d.set(warnThreshold, forKey: "warnThreshold") } } }
    @Published var criticalThreshold: Int { didSet { if Settings.persist { d.set(criticalThreshold, forKey: "criticalThreshold") } } }
    @Published var refreshMinutes: Int { didSet { if Settings.persist { d.set(refreshMinutes, forKey: "refreshMinutes") }; onChange() } }
    @Published var predictiveAlerts: Bool { didSet { if Settings.persist { d.set(predictiveAlerts, forKey: "predictiveAlerts") } } }

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
        menuIconMono = flag("menuIconMono", false)
        menuLabelStyle = MenuLabelStyle(rawValue: ud.string(forKey: "menuLabelStyle") ?? "") ?? .letters
        menuPercentColour = MenuPercentColour(rawValue: ud.string(forKey: "menuPercentColour") ?? "") ?? .critical
        autoDownloadUpdates = ud.object(forKey: "autoDownloadUpdates") as? Bool ?? true
        autoCheckUpdates = d.object(forKey: "autoCheckUpdates") as? Bool ?? true
        importance = NotifImportance(rawValue: d.string(forKey: "importance") ?? "") ?? .normal
        warnThreshold = d.object(forKey: "warnThreshold") as? Int ?? 80
        criticalThreshold = d.object(forKey: "criticalThreshold") as? Int ?? 95
        refreshMinutes = d.object(forKey: "refreshMinutes") as? Int ?? 1
        currentTheme = theme
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
        menuLabelStyle = .letters; menuPercentColour = .critical; menuIconMono = false
    }
}
