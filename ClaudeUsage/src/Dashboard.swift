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
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(settings.isOLED ? Color(white: 0.07) : Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(settings.isOLED ? Color(white: 0.20) : Color(nsColor: .separatorColor), lineWidth: 1))
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
                Image(systemName: "sidebar.left").font(.system(size: 16)).foregroundStyle(.secondary).frame(width: 28, height: 28)
                    .padding(.horizontal, 8).padding(.vertical, 4)
            }
            .buttonStyle(.plain).help(narrow ? "Show sidebar labels" : "Collapse to icons")
            .padding(.bottom, 6)

            ForEach(Array(DashTab.allCases.enumerated()), id: \.element.id) { index, tab in
                let selected = store.tab == tab
                Button { store.tab = tab } label: {
                    HStack(spacing: 12) {
                        Image(systemName: tab.icon).font(.system(size: 17)).foregroundStyle(Color.brand).frame(width: 28)
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
                Text("v\(AppInfo.version)").font(.system(size: 9)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude Usage").font(.caption.weight(.semibold))
                    Text("\(AppInfo.display) · build \(AppInfo.build)").font(.caption2).foregroundStyle(.secondary)
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
                Text(store.installMessage).font(.callout)
                Spacer()
                Text("\(Int((store.installProgress * 100).rounded()))%").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
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

/// Shown above every page while an update downloads/installs, and once it is ready: asks for a restart to finish installing it.
struct UpdateBanner: View {
    @ObservedObject var store: Store
    var body: some View {
        if store.installing {
            HStack(spacing: 12) {
                Image(systemName: store.downloadOnly ? "arrow.down.circle.fill" : "arrow.triangle.2.circlepath.circle.fill").font(.title3).foregroundStyle(Color.brand)
                UpdateProgressBar(store: store)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color.brand.opacity(0.14))
            .overlay(Rectangle().fill(Color.brand.opacity(0.4)).frame(height: 1), alignment: .bottom)
        } else if case .ready(let u, _) = store.update, !store.bannerHidden {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill").font(.title3).foregroundStyle(Color.brand)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Version \(u.version) is ready to install").fontWeight(.semibold)
                    Text("Restart Claude Usage to finish updating.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Later") { store.actions.postponeUpdate() }
                Button("Restart Now") { store.actions.applyUpdate() }.buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color.brand.opacity(0.14))
            .overlay(Rectangle().fill(Color.brand.opacity(0.4)).frame(height: 1), alignment: .bottom)
        }
    }
}
