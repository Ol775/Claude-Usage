import SwiftUI
import Charts
import ServiceManagement

// MARK: - State shared between the app delegate (AppKit) and the dashboard (SwiftUI)

struct Actions {
    var signIn: () -> Void = {}
    var signOut: () -> Void = {}
    var cancelSignIn: () -> Void = {}
    var connectChatGPT: () -> Void = {}
    var disconnectChatGPT: () -> Void = {}
    var signOutChatGPT: () -> Void = {}
    var cancelChatGPT: () -> Void = {}
    var choosePhoto: () -> Void = {}
    var removePhoto: () -> Void = {}
    var refresh: () -> Void = {}
    var testNotify: () -> Void = {}
    var testImportant: () -> Void = {}
    var chooseStock: (Int) -> Void = { _ in }
    var checkUpdates: () -> Void = {}
    var copyUpdateCommand: () -> Void = {}
    var openChangelog: () -> Void = {}
    var installUpdate: () -> Void = {}
    var applyUpdate: () -> Void = {}
    var downloadInstaller: () -> Void = {}
    var showInstaller: () -> Void = {}
    var openInstaller: () -> Void = {}
    var postponeUpdate: () -> Void = {}
    var openNotificationSettings: () -> Void = {}
    var requestNotifications: () -> Void = {}
    var exportData: () -> Void = {}
    var copySummary: () -> Void = {}
}

enum DashTab: String, CaseIterable, Identifiable {
    case overview, reports, insights, usage, settings
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.50percent"
        case .reports: return "chart.xyaxis.line"
        case .insights: return "lightbulb"
        case .usage: return "chart.bar.xaxis"
        case .settings: return "gearshape"
        }
    }
}

final class Store: ObservableObject {
    static let shared = Store()
    @Published var tab: DashTab = .overview
    @Published var settingsCategory: SettingsCategory = .general
    @Published var snapshot = Snapshot()
    @Published var limits: [Limit] = []
    @Published var limitError: String?
    @Published var stale = false
    @Published var staleReason: String?       // set when the last reading is kept because the response changed shape
    @Published var account = Account()
    @Published var chatgpt = ChatGPTState()
    @Published var chatgptBusy = false
    @Published var gptSamples: [GPTSample] = GPTHistory.shared.samples
    @Published var samples: [Sample] = []
    @Published var loginBusy = false
    @Published var photo: NSImage? = avatarImage
    @Published var lastUpdated: Date?
    @Published var notifStatus = "Checking…"
    @Published var notifBlocked = false
    @Published var stockIndex: Int? = stockAvatarIndex
    @Published var update: UpdateStatus = .idle
    @Published var installing = false
    @Published var installMessage = ""
    @Published var whatsNew: String?                    // one-time banner after an update
    @Published var installProgress = 0.0                // 0...1 while an update downloads, verifies and installs
    @Published var downloadOnly = false                 // this copy can't replace itself, so the update is saved to Downloads instead
    @Published var downloadedInstaller: URL?
    @Published var canInstall = true
    @Published var installError: String?
    @Published var bannerHidden = false
    var actions = Actions()
}

/// Local UI state without @State (the SDK's @State macro needs a compiler plugin that command-line builds don't have).
final class Box<T>: ObservableObject {
    @Published var value: T
    init(_ v: T) { value = v }
}

extension Color {
    static var brand: Color { Color(nsColor: claudeOrange) }
    static var danger: Color { Color(nsColor: alertRed) }
    /// ChatGPT green for its chart lines; deeper in light mode so it stays readable on white.
    static var gpt: Color {
        Color(nsColor: NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(srgbRed: 0.063, green: 0.639, blue: 0.498, alpha: 1) : NSColor(srgbRed: 0.03, green: 0.50, blue: 0.38, alpha: 1)
        })
    }
}

struct CardStyle: ViewModifier {
    @ObservedObject var settings = Settings.shared
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: settings.cardCorners.radius, style: .continuous).fill(settings.isOLED ? Color(white: 0.07) : Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: settings.cardCorners.radius, style: .continuous).stroke(settings.isOLED ? Color(white: 0.20) : Color(nsColor: .separatorColor), lineWidth: 1))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}

// MARK: - Shell

struct DashboardView: View {
    @ObservedObject var store: Store
    @ObservedObject var settings = Settings.shared
    @StateObject private var collapsed = Box(UserDefaults.standard.bool(forKey: "sidebarCollapsed") || Dev.env("CUB_COLLAPSED") == "1")

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(store: store, collapsed: collapsed, settings: settings)
            Divider()
            VStack(spacing: 0) {
                UpdateBanner(store: store)
                Group {
                switch store.tab {
                case .overview: OverviewView(store: store)
                case .reports: ReportsView(store: store)
                case .insights: InsightsView(store: store)
                case .usage: UsageView(store: store)
                case .settings: SettingsPage(store: store, settings: settings)
                }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(settings.isOLED ? Color.black : Color(nsColor: .windowBackgroundColor))
        }
        .background(settings.isOLED ? Color.black : Color(nsColor: .windowBackgroundColor))
        .tint(.brand)
        .font(AppFont.body)
        .id("\(settings.fontChoice.rawValue)-\(settings.textSize.rawValue)-\(settings.theme.rawValue)-\(settings.theme == .custom ? settings.customAccentHex : "")")      // rebuild everything when the typeface, text size or accent colour changes (dynamic colours are otherwise cached by SwiftUI)
        .frame(minWidth: 860, minHeight: 600)
    }
}

/// Sidebar that collapses to a slim icon rail instead of disappearing, so the sections stay one click away.
struct SidebarView: View {
    @ObservedObject var store: Store
    @ObservedObject var collapsed: Box<Bool>
    @ObservedObject var settings: Settings

    var body: some View {
        let narrow = collapsed.value
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { collapsed.value.toggle() }
                UserDefaults.standard.set(collapsed.value, forKey: "sidebarCollapsed")
            } label: {
                Image(systemName: "sidebar.left").font(AppFont.system(size: 16)).foregroundStyle(.secondary).frame(width: 28, height: 28)
                    .padding(.horizontal, 8).padding(.vertical, 4)
            }
            .buttonStyle(.plain).help(narrow ? "Show sidebar labels" : "Collapse to icons")
            .padding(.bottom, 6)

            ForEach(Array(DashTab.allCases.enumerated()), id: \.element.id) { index, tab in
                let selected = store.tab == tab
                Button { store.tab = tab } label: {
                    HStack(spacing: 12) {
                        Image(systemName: tab.icon).font(AppFont.system(size: 17)).foregroundStyle(Color.brand).frame(width: 28)
                        if !narrow { Text(tab.title).fontWeight(selected ? .semibold : .regular).foregroundStyle(.primary); Spacer(minLength: 0) }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? (settings.isOLED ? Color(white: 0.16) : Color.brand.opacity(0.18)) : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("\(tab.title) (⌘\(index + 1))")
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                .accessibilityLabel(tab.title).accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer()
            if narrow {
                VStack(spacing: 6) {
                    AvatarCircle(account: store.account, photo: store.photo, size: 34)
                    Text("v\(AppInfo.version)").font(AppFont.system(size: 9)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    AvatarCircle(account: store.account, photo: store.photo, size: 48)        // your profile picture, above the app name
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Claude Usage").font(AppFont.caption.weight(.semibold))
                        Text("\(AppInfo.display) · build \(AppInfo.build)").font(AppFont.caption2).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 8).padding(.bottom, 4)
            }
        }
        .padding(10)
        .frame(width: narrow ? 66 : 204)
        .frame(maxHeight: .infinity)
        .background(settings.isOLED ? Color.black : Color(nsColor: .controlBackgroundColor).opacity(0.6))
    }
}

/// A hand-drawn progress bar (the system one ignores our accent colour in dark mode) with the step and percentage.
struct UpdateProgressBar: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(store.installMessage).font(AppFont.callout)
                Spacer()
                Text("\(Int((store.installProgress * 100).rounded()))%").font(AppFont.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule().fill(Color.brand).frame(width: max(8, g.size.width * CGFloat(min(max(store.installProgress, 0), 1))))
                        .animation(.easeOut(duration: 0.25), value: store.installProgress)
                }
            }.frame(height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(store.downloadOnly ? "Downloading update" : "Updating Claude Usage")
        .accessibilityValue("\(store.installMessage), \(Int((store.installProgress * 100).rounded())) percent")
    }
}

/// The one place updates show up, inside the app (no system notifications or pop-up alerts): above every page it shows an update that
/// is available, one that is downloading, one that is ready to restart, and – once, after updating – what's new.
struct UpdateBanner: View {
    @ObservedObject var store: Store

    private func bar<Content: View>(_ icon: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(AppFont.title3).foregroundStyle(Color.brand)
            content()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.brand.opacity(0.14))
        .overlay(Rectangle().fill(Color.brand.opacity(0.4)).frame(height: 1), alignment: .bottom)
    }

    private func titled(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).fontWeight(.semibold)
            Text(detail).font(AppFont.caption).foregroundStyle(.secondary).lineLimit(2)
        }
    }

    var body: some View {
        if store.installing {
            bar(store.downloadOnly ? "arrow.down.circle.fill" : "arrow.triangle.2.circlepath.circle.fill") { UpdateProgressBar(store: store) }
        } else if case .ready(let u, _) = store.update, !store.bannerHidden {
            bar("arrow.triangle.2.circlepath.circle.fill") {
                titled("Version \(u.version) is ready to install", "Restart Claude Usage to finish updating. Your current version is kept as a backup.")
                Spacer()
                Button("Later") { store.actions.postponeUpdate() }
                Button("Restart Now") { store.actions.applyUpdate() }.buttonStyle(.borderedProminent)
            }
        } else if case .available(let u) = store.update, !store.bannerHidden {
            bar("arrow.down.circle.fill") {
                titled("Version \(u.version) is available", store.canInstall ? (u.notes.first ?? "A newer version is ready to download.") : "This copy can’t replace itself, so it saves the installer to Downloads.")
                Spacer()
                Button("Later") { store.actions.postponeUpdate() }
                Button(store.canInstall ? "Update Now" : "Download") { store.canInstall ? store.actions.installUpdate() : store.actions.downloadInstaller() }.buttonStyle(.borderedProminent)
            }
        } else if let text = store.whatsNew {
            bar("sparkles") {
                Text(text).lineLimit(2)
                Spacer()
                Button("What’s new") { store.settingsCategory = .about; store.tab = .settings; store.whatsNew = nil }
                Button { store.whatsNew = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Dismiss").accessibilityLabel("Dismiss")
            }
        }
    }
}
