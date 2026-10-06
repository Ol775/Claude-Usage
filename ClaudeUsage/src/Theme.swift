import AppKit
import SwiftUI

// MARK: - App info

enum AppInfo {
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1" }
    static var stage: String { Bundle.main.infoDictionary?["ClaudeUsageStage"] as? String ?? "alpha" }
    static let repoURL = URL(string: "https://github.com/Ol775/Claude-Usage")!
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
    var colors: (NSColor, NSColor) {
        func c(_ r: Double, _ g: Double, _ b: Double) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
        switch self {
        case .claude: return (c(1.00, 0.55, 0.33), c(0.80, 0.31, 0.10))
        case .blue: return (c(0.36, 0.67, 1.00), c(0.00, 0.37, 0.80))
        case .green: return (c(0.30, 0.85, 0.52), c(0.07, 0.50, 0.25))
        case .purple: return (c(0.72, 0.58, 1.00), c(0.46, 0.22, 0.80))
        case .pink: return (c(1.00, 0.45, 0.65), c(0.80, 0.14, 0.40))
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

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case both, session, weekly, tokens, iconOnly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .both: return "Session · Weekly"
        case .session: return "Session only"
        case .weekly: return "Weekly only"
        case .tokens: return "Tokens today"
        case .iconOnly: return "Icon only"
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
    @Published var menuBarStyle: MenuBarStyle { didSet { if Settings.persist { d.set(menuBarStyle.rawValue, forKey: "menuBarStyle") }; onChange() } }
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
        menuBarStyle = MenuBarStyle(rawValue: d.string(forKey: "menuBarStyle") ?? "") ?? .both
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
}
