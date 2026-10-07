import SwiftUI
import Charts
import ServiceManagement

/// "Buy me a coffee" button: a drawn coffee cup on the familiar yellow (not the official artwork).
struct CoffeeButton: View {
    var body: some View {
        Button { NSWorkspace.shared.open(AppInfo.coffeeURL) } label: {
            HStack(spacing: 7) {
                Image(systemName: "cup.and.saucer.fill").font(AppFont.system(size: 14, weight: .semibold))
                Text("Buy me a coffee").font(AppFont.system(size: 13, weight: .bold))
            }
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(Color(red: 1.0, green: 0.867, blue: 0.0)))
        }
        .buttonStyle(.plain).help("buymeacoffee.com/ol775")
    }
}

// MARK: - Account

struct AvatarCircle: View {
    let account: Account
    let photo: NSImage?
    let size: CGFloat
    var body: some View {
        ZStack {
            if account.loggedIn, let p = photo {
                // an accent-coloured backing, so a picture with soft or transparent edges never shows a grey gap inside the circle
                Circle().fill(LinearGradient(colors: [Color.brand.opacity(0.75), Color.brand], startPoint: .top, endPoint: .bottom))
                Image(nsImage: p).resizable().interpolation(.high).scaledToFill()
            } else if account.loggedIn {
                Circle().fill(LinearGradient(colors: [Color.brand.opacity(0.8), Color.brand], startPoint: .top, endPoint: .bottom))
                Text(account.initials).font(AppFont.system(size: size * 0.38, weight: .semibold)).foregroundColor(.white)
            } else {
                Circle().fill(Color.secondary.opacity(0.2))
                Text("?").font(AppFont.system(size: size * 0.38, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: max(1, size / 48)))      // a fine ring, drawn inside the edge
        .shadow(color: .black.opacity(size >= 40 ? 0.22 : 0), radius: size / 24, x: 0, y: size / 48)
        .accessibilityLabel(account.loggedIn ? "Profile picture" : "Not signed in")
    }
}

struct SettingsPage: View {
    @ObservedObject var store: Store
    @ObservedObject var settings: Settings
    @StateObject private var loginBox = Box(SMAppService.mainApp.status == .enabled)
    @StateObject private var showDiagnostics = Box(Dev.env("CUB_SHOW_DIAG") != nil)
    @StateObject private var searchBox = Box("")
    @StateObject private var openLegal = Box(Set<String>())
    @StateObject private var openVersions = Box(Set(Changelog.load().prefix(1).map(\.version)))

    private var matches: [SettingsCategory] {
        let q = searchBox.value.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return SettingsCategory.allCases.filter { $0 != .account } }
        return SettingsCategory.allCases.filter { $0 != .account && ($0.title.lowercased().contains(q) || $0.keywords.contains(q)) }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(store.settingsCategory.title).font(AppFont.largeTitle.bold())
                    detail(store.settingsCategory)
                }
                .padding(28).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: left column

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $searchBox.value).textFieldStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.secondary.opacity(0.15)))

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    profileRow
                    Divider().padding(.vertical, 6)
                    ForEach(matches) { c in categoryRow(c) }
                    if matches.isEmpty { Text("No results").foregroundStyle(.secondary).padding(8) }
                }
            }
        }
        .padding(12).frame(width: 250)
        .background(settings.isOLED ? Color.black : Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }

    private var profileRow: some View {
        let a = store.account, selected = store.settingsCategory == .account
        return Button { store.settingsCategory = .account } label: {
            HStack(spacing: 10) {
                AvatarCircle(account: a, photo: store.photo, size: 42).overlay(Circle().stroke(Color.white.opacity(selected ? 0.9 : 0), lineWidth: 2))
                VStack(alignment: .leading, spacing: 1) {
                    Text(a.loggedIn ? a.name : "Sign in").fontWeight(.semibold).foregroundStyle(selected ? Color.white : Color.primary)
                    Text(a.loggedIn ? (a.plan.isEmpty ? "Claude account" : "Claude \(a.plan)") : "with your Claude account")
                        .font(AppFont.caption).foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? Color.brand : Color.clear))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func categoryRow(_ c: SettingsCategory) -> some View {
        let selected = store.settingsCategory == c
        return Button { store.settingsCategory = c } label: {
            HStack(spacing: 10) {
                Image(systemName: c.icon).font(AppFont.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 6.5, style: .continuous).fill(c.tint.gradient))
                Text(c.title).foregroundStyle(selected ? Color.white : Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Color.brand : Color.clear))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    // MARK: panes

    @ViewBuilder private func detail(_ c: SettingsCategory) -> some View {
        switch c {
        case .account: accountPane
        case .general: generalPane
        case .appearance: appearancePane
        case .menuBar: menuBarPane
        case .notifications: notificationsPane
        case .data: dataPane
        case .support: supportPane
        case .about: aboutPane
        }
    }

    private var accountPane: some View {
        let a = store.account
        return VStack(alignment: .leading, spacing: 22) {
            VStack(spacing: 8) {
                AvatarCircle(account: a, photo: store.photo, size: 96).onTapGesture { if a.loggedIn { store.actions.choosePhoto() } }
                Text(a.loggedIn ? a.name : "Not signed in").font(AppFont.title2.bold())
                if a.loggedIn {
                    Text(a.email).foregroundStyle(.secondary)
                    if !a.plan.isEmpty {
                        Text("Claude \(a.plan) plan").font(AppFont.caption.weight(.semibold)).foregroundStyle(Color.brand)
                            .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(Color.brand.opacity(0.15)))
                    }
                } else {
                    Text("Connect your Claude account to see your session and weekly limits, when they reset, and get alerts before you hit them.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 380)
                }
            }
            .frame(maxWidth: .infinity)

            if a.loggedIn {
                SGroup(title: "Choose a robot", footer: "Stock robot avatars – pick one as your account picture.") {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(62), spacing: 14), count: 6), alignment: .leading, spacing: 14) {
                        ForEach(0..<stockBots.count, id: \.self) { i in
                            Button { store.actions.chooseStock(i) } label: {
                                Image(nsImage: stockAvatarImage(i)).resizable().frame(width: 62, height: 62).clipShape(Circle())
                                    .overlay(Circle().stroke(store.stockIndex == i ? Color.brand : Color(nsColor: .separatorColor), lineWidth: store.stockIndex == i ? 3 : 1).padding(store.stockIndex == i ? -3 : 0))
                            }
                            .buttonStyle(.plain).help(stockBots[i].name)
                        }
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                }
                SGroup(title: "Profile photo", footer: "Your photo stays on this Mac – Claude doesn’t share one.") {
                    SRow(title: store.photo == nil ? "Choose a photo" : "Change photo") {
                        Button(store.photo == nil ? "Choose…" : "Change…") { store.actions.choosePhoto() }
                    }
                    if store.photo != nil { SDivider(); SRow(title: "Remove photo") { Button("Remove") { store.actions.removePhoto() } } }
                }
                SGroup {
                    SRow(title: "Sign out", subtitle: "Also signs out Claude Code – they share one login.") {
                        Button { store.actions.signOut() } label: { Text("Sign Out…").foregroundStyle(Color.danger) }
                    }
                }
                chatgptGroup
            } else {
                SGroup(footer: "Sign-in uses Claude’s official login, through Claude Code.") {
                    if store.loginBusy {
                        SRow(title: "Waiting for your browser…", subtitle: "Finish signing in using the browser window.") {
                            HStack { ProgressView().controlSize(.small); Button("Cancel") { store.actions.cancelSignIn() } }
                        }
                    } else {
                        SRow(title: "Sign in with Claude") {
                            Button("Sign In") { store.actions.signIn() }.buttonStyle(.borderedProminent)
                        }
                    }
                }
                chatgptGroup
            }
        }
    }

    /// Optional ChatGPT usage, read through OpenAI's Codex CLI sign-in (works with free and paid ChatGPT accounts).
    @ViewBuilder private var chatgptGroup: some View {
        let g = store.chatgpt
        SGroup(title: "ChatGPT (experimental)", footer: "Experimental: the paid-plan limits have so far only been checked with sample data, so numbers may be missing or off. Shows your Codex usage limits for a paid ChatGPT plan, using the sign-in saved by OpenAI’s Codex CLI (install with “brew install codex”). Claude Usage only reads it to ask ChatGPT for your limits – it never changes, copies or stores your ChatGPT login.") {
            if !settings.chatgptEnabled {
                SRow(title: "Show ChatGPT usage (experimental)", subtitle: "See your ChatGPT (Codex) limits next to Claude’s. Needs a paid ChatGPT plan. Nothing is read until you connect.") {
                    Button("Connect…") { store.actions.connectChatGPT() }.buttonStyle(.borderedProminent)
                }
            } else if store.chatgptBusy {
                SRow(title: "Waiting for your browser…", subtitle: "Finish signing in to ChatGPT using the browser window.") {
                    HStack { ProgressView().controlSize(.small); Button("Cancel") { store.actions.cancelChatGPT() } }
                }
            } else if g.signedIn {
                SRow(title: g.email.isEmpty ? "Connected to ChatGPT" : g.email, subtitle: g.isFree ? "ChatGPT Free plan – not supported, a paid plan is needed" : (g.plan.isEmpty ? nil : "ChatGPT \(g.plan) plan")) {
                    Button { store.actions.signOutChatGPT() } label: { Text("Sign Out…").foregroundStyle(Color.danger) }
                }
                SDivider()
                SRow(title: "Stop showing ChatGPT", subtitle: "Hides it everywhere. Your ChatGPT sign-in is left as it is.") {
                    Button("Disconnect") { store.actions.disconnectChatGPT() }
                }
            } else {
                SRow(title: g.error ?? "Not signed in to ChatGPT") {
                    HStack { Button("Sign In") { store.actions.connectChatGPT() }.buttonStyle(.borderedProminent); Button("Disconnect") { store.actions.disconnectChatGPT() } }
                }
            }
        }
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 22) {
            SGroup(title: "Startup") {
                SRow(title: "Show in Dock", subtitle: "Turn off to keep the app in the menu bar only.") { Toggle("", isOn: $settings.showInDock).labelsHidden().toggleStyle(.switch) }
                SDivider()
                SRow(title: "Launch at login") {
                    Toggle("", isOn: Binding(
                        get: { loginBox.value },
                        set: { on in
                            do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                            catch { NSSound.beep() }
                            loginBox.value = SMAppService.mainApp.status == .enabled
                        })).labelsHidden().toggleStyle(.switch)
                }
            }
            SGroup(title: "Updates") {
                SRow(title: "Refresh every", subtitle: "How often limits and usage are refreshed.") {
                    Picker("", selection: $settings.refreshMinutes) {
                        Text("1 minute").tag(1); Text("2 minutes").tag(2); Text("5 minutes").tag(5); Text("10 minutes").tag(10)
                    }.labelsHidden().frame(width: 130)
                }
            }
        }
    }

    private var appearancePane: some View {
        VStack(alignment: .leading, spacing: 22) {
            SGroup(title: "Mode") {
                HStack(spacing: 14) {
                    ForEach(AppearanceMode.allCases) { m in modeTile(m) }
                }
                .padding(16).frame(maxWidth: .infinity)
            }
            if settings.appearance == .oled {
                Text("OLED black uses pure black backgrounds – deepest on OLED displays and easy on the battery.").font(AppFont.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
            }
            SGroup(title: "Colour theme") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10, alignment: .top)], alignment: .center, spacing: 14) {       // wraps to more rows when the text is large
                    ForEach(AccentTheme.allCases) { t in
                        Button { settings.theme = t } label: {
                            VStack(spacing: 6) {
                                Circle().fill(Color(nsColor: NSColor(name: nil) { a in a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? t.colors.0 : t.colors.1 }))
                                    .frame(width: 30, height: 30)
                                    .overlay(Circle().stroke(Color.primary.opacity(settings.theme == t ? 0.9 : 0), lineWidth: 2).padding(-4))
                                Text(t.label).font(AppFont.caption2).foregroundStyle(settings.theme == t ? .primary : .secondary).lineLimit(2).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(16).frame(maxWidth: .infinity)
                if settings.theme == .custom {
                    SDivider()
                    SRow(title: "Custom colour", subtitle: "Used for rings, bars, charts and buttons. Lightened in dark mode and deepened in light mode so it stays readable.") {
                        ColorPicker("", selection: Binding(get: { Color(nsColor: colorFromHex(settings.customAccentHex) ?? .orange) },
                                                           set: { settings.customAccentHex = hexFromColor(NSColor($0)); settings.theme = .custom; currentTheme = .custom }), supportsOpacity: false).labelsHidden()
                    }
                }
            }
            SGroup(title: "Font", footer: "\(settings.fontChoice.detail) OpenDyslexic is built in – nothing to install. Applies to the windows; the menu bar and its menu keep the system font.") {
                HStack(spacing: 12) {
                    ForEach(FontChoice.allCases) { c in
                        Button { settings.fontChoice = c } label: {
                            VStack(spacing: 6) {
                                Text("Aa").font(AppFont.make(c, size: 24, weight: .semibold)).frame(height: 34)         // fixed height: OpenDyslexic is taller than the others
                                Text(c.label).font(AppFont.make(.system, size: 10)).foregroundStyle(settings.fontChoice == c ? .primary : .secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 74).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(settings.fontChoice == c ? 0.12 : 0.05)))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.brand.opacity(settings.fontChoice == c ? 0.9 : 0), lineWidth: 2))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(16)
                SDivider()
                SRow(title: "Text size") {
                    SegmentedChoice(options: TextSize.allCases, label: { $0.label }, selection: $settings.textSize)
                }
            }
            SGroup(title: "Cards and name") {
                SRow(title: "Card corners") {
                    SegmentedChoice(options: CardCorners.allCases, label: { $0.label }, selection: $settings.cardCorners)
                }
                SDivider()
                SRow(title: "Greeting name", subtitle: "What the Overview calls you. Leave empty to use the first name from your Claude account.") {
                    TextField("First name", text: $settings.displayName).textFieldStyle(.roundedBorder).frame(width: 180)
                }
            }
        }
    }

    private func modeTile(_ m: AppearanceMode) -> some View {
        let selected = settings.appearance == m
        let fill: AnyShapeStyle
        switch m {
        case .light: fill = AnyShapeStyle(LinearGradient(colors: [Color(white: 0.98), Color(white: 0.86)], startPoint: .top, endPoint: .bottom))
        case .dark: fill = AnyShapeStyle(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.12)], startPoint: .top, endPoint: .bottom))
        case .oled: fill = AnyShapeStyle(Color.black)
        case .system: fill = AnyShapeStyle(LinearGradient(stops: [.init(color: Color(white: 0.96), location: 0.5), .init(color: Color(white: 0.14), location: 0.5)], startPoint: .leading, endPoint: .trailing))
        }
        return Button { settings.appearance = m } label: {
            VStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(fill)
                    RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                    RoundedRectangle(cornerRadius: 3).fill(Color.brand).frame(width: 30, height: 6).offset(y: 6)
                }
                .frame(width: 96, height: 62)
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(selected ? Color.brand : Color.clear, lineWidth: 3).padding(-4))
                Text(m.label).font(AppFont.caption).fontWeight(selected ? .semibold : .regular)
            }
        }.buttonStyle(.plain)
    }

    private var menuBarPane: some View {
        let parts = MenuBarTitle.parts(limits: store.limits, tokensToday: store.snapshot.today.billable, settings: settings, chatgpt: store.chatgpt.limits)
        let showIcon = settings.menuShowIcon || parts.isEmpty
        var preview = Text("")
        for (i, p) in parts.enumerated() {
            if i > 0 { preview = preview + Text("   ") }
            if let l = p.label { preview = preview + Text(l + " ").fontWeight(.semibold) }
            var v = Text(p.value).monospacedDigit()
            if p.isPercent {
                switch settings.menuPercentColour {
                case .critical: if p.hot { v = v.foregroundColor(Color.danger) }
                case .accent: v = v.foregroundColor(p.hot ? Color.danger : Color.brand)
                case .plain: break
                }
            }
            preview = preview + v
        }
        return VStack(alignment: .leading, spacing: 22) {
            SGroup(title: "Preview", footer: "How the menu bar item looks right now.") {
                HStack(spacing: 6) {
                    if showIcon { Image(nsImage: settings.menuIconImage()).foregroundStyle(.primary) }
                    preview.font(AppFont.system(size: 13))
                }
                .padding(18).frame(maxWidth: .infinity)
            }
            SGroup(title: "Presets") {
                HStack(spacing: 10) {
                    ForEach(MenuBarPreset.allCases) { p in
                        Button { settings.apply(p) } label: {
                            VStack(spacing: 2) {
                                Text(p.label).fontWeight(.medium)
                                Text(p.detail).font(AppFont.caption2).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 6)
                        }.buttonStyle(.bordered)
                    }
                }
                .padding(14)
            }
            SGroup(title: "Items", footer: "If you turn everything off, the icon stays so the item never disappears.") {
                SRow(title: "Icon") { Toggle("", isOn: $settings.menuShowIcon).labelsHidden().toggleStyle(.switch) }
                SDivider()
                SRow(title: "Current session", subtitle: "How much of the session limit you’ve used.") { Toggle("", isOn: $settings.menuShowSession).labelsHidden().toggleStyle(.switch) }
                SDivider()
                SRow(title: "Weekly limit", subtitle: "How much of the weekly limit you’ve used.") { Toggle("", isOn: $settings.menuShowWeekly).labelsHidden().toggleStyle(.switch) }
                SDivider()
                SRow(title: "ChatGPT usage (experimental)", subtitle: settings.chatgptEnabled ? "Your ChatGPT limit, shown as G 12%." : "Connect ChatGPT in Settings → Account first.") {
                    Toggle("", isOn: $settings.menuShowChatGPT).labelsHidden().toggleStyle(.switch).disabled(!settings.chatgptEnabled)
                }
                SDivider()
                SRow(title: "Tokens today", subtitle: "Input, output and cache-write tokens used today.") { Toggle("", isOn: $settings.menuShowTokens).labelsHidden().toggleStyle(.switch) }
                SDivider()
                SRow(title: "Session reset countdown", subtitle: "Time until the session limit resets, such as ↻ 1h 30m.") { Toggle("", isOn: $settings.menuShowReset).labelsHidden().toggleStyle(.switch) }
            }
            SGroup(title: "Style", footer: "D is your current session limit and W is the weekly limit.") {
                SRow(title: "Labels") {
                    Picker("", selection: $settings.menuLabelStyle) { ForEach(MenuLabelStyle.allCases) { Text($0.label).tag($0) } }
                        .labelsHidden().frame(width: 190)
                }
                SDivider()
                SRow(title: "Percentage colour") {
                    Picker("", selection: $settings.menuPercentColour) { ForEach(MenuPercentColour.allCases) { Text($0.label).tag($0) } }
                        .labelsHidden().frame(width: 190)
                }
                SDivider()
                SRow(title: "Icon colour", subtitle: "The Claude icon in the menu bar.") {
                    Picker("", selection: $settings.menuIconStyle) { ForEach(MenuIconStyle.allCases) { Text($0.label).tag($0) } }
                        .labelsHidden().frame(width: 250)
                }
                if settings.menuIconStyle == .custom {
                    SDivider()
                    SRow(title: "Custom icon colour", subtitle: "Pick any colour.") {
                        ColorPicker("", selection: Binding(get: { Color(nsColor: colorFromHex(settings.menuIconHex) ?? .orange) },
                                                           set: { settings.menuIconHex = hexFromColor(NSColor($0)) }), supportsOpacity: false).labelsHidden()
                    }
                }
            }
        }
    }

    private var notificationsPane: some View {
        VStack(alignment: .leading, spacing: 22) {
            SGroup(title: "macOS permission") {
                SRow(title: "Notifications: \(store.notifStatus)",
                     subtitle: store.notifBlocked ? "Blocked – alerts appear as an on-screen banner with the app icon instead." : (store.notifStatus == "Allowed" ? nil : "macOS hasn’t been asked yet – choose Allow to turn notifications on.")) {
                    HStack {
                        Image(systemName: store.notifBlocked ? "bell.slash.fill" : "bell.badge.fill").foregroundStyle(store.notifBlocked ? Color.danger : Color.brand)
                        if store.notifStatus != "Allowed" { Button("Allow…") { store.actions.requestNotifications() } }
                        else { Button("Open Settings") { store.actions.openNotificationSettings() } }
                    }
                }
            }
            SGroup(title: "Alerts") {
                SRow(title: "Alert when a limit gets close") { Toggle("", isOn: $settings.notificationsOn).labelsHidden().toggleStyle(.switch) }
                SDivider()
                SRow(title: "Warn when on pace to hit a limit early", subtitle: "Uses your current pace and saved history.") { Toggle("", isOn: $settings.predictiveAlerts).labelsHidden().toggleStyle(.switch) }
                SDivider()
                SRow(title: "Warn at") {
                    HStack { Text("\(settings.warnThreshold)%").monospacedDigit(); Stepper("", value: $settings.warnThreshold, in: 50...95, step: 5).labelsHidden() }
                }
                SDivider()
                SRow(title: "Critical at") {
                    HStack { Text("\(settings.criticalThreshold)%").monospacedDigit(); Stepper("", value: $settings.criticalThreshold, in: 60...99, step: 1).labelsHidden() }
                }
            }
            SGroup(title: "Importance", footer: settings.importance == .normal ? nil :
                    "Important alerts are sent as Time Sensitive, so macOS may show them through Focus modes, and the on-screen banner stays until you click it.") {
                SRow(title: "Mark as important") {
                    Picker("", selection: $settings.importance) { ForEach(NotifImportance.allCases) { Text($0.label).tag($0) } }
                        .labelsHidden().frame(width: 230)
                }
            }
            SGroup(title: "Try it") {
                SRow(title: "Send a test notification") { Button("Send") { store.actions.testNotify() } }
                SDivider()
                SRow(title: "Send a test as important") { Button("Send") { store.actions.testImportant() } }
            }
        }
    }

    private var dataPane: some View {
        VStack(alignment: .leading, spacing: 22) {
            SGroup(title: "Export", footer: "Daily tokens and your limit history are saved as two CSV files in a folder you choose.") {
                SRow(title: "Export data as CSV") { Button("Export…") { store.actions.exportData() } }
            }
            SGroup(title: "Share") {
                SRow(title: "Copy usage summary", subtitle: "Your limits, forecasts and totals as text.") { Button("Copy") { store.actions.copySummary() } }
            }
            SGroup(title: "Saved activity", footer: "Daily activity is stored on this Mac so insights and the yearly view outlast Claude Code’s own log clean-up.") {
                SRow(title: "Days stored") { Text("\(store.snapshot.days.count)").monospacedDigit().foregroundStyle(.secondary) }
            }
            SGroup(title: "Delete", footer: "Erases everything this app stores on your Mac and quits. Your Claude Code and ChatGPT sign-ins and logs are not touched.") {
                SRow(title: "Delete all my data", subtitle: "History, activity, settings, profile photo and event log.") {
                    Button("Delete…", role: .destructive) { store.actions.deleteAllData() }
                }
            }
        }
    }

    private var supportPane: some View {
        VStack(alignment: .leading, spacing: 22) {
            SGroup(title: "Report a bug", footer: "Opens a GitHub page with your app and macOS version filled in. Nothing is sent until you press Submit there. You’ll need a free GitHub account.") {
                SRow(title: "Found a problem?", subtitle: "Tell us what happened and what you expected.") {
                    Button("Report a Bug…") { NSWorkspace.shared.open(Legal.newIssueURL) }.buttonStyle(.borderedProminent)
                }
                SDivider()
                SRow(title: "Diagnostics", subtitle: "App version, macOS version, chip and a few yes/no states. No account details, file paths or usage numbers.") {
                    Button(showDiagnostics.value ? "Hide" : "Preview") { showDiagnostics.value.toggle() }
                    Button("Copy") { Legal.copyDiagnostics() }
                }
                if showDiagnostics.value {
                    Text(Legal.diagnostics).font(AppFont.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                        .padding(.horizontal, 14).padding(.bottom, 10)
                    Text("This is exactly what “Copy” and “Report a Bug” include. It isn’t sent anywhere unless you paste or submit it yourself.")
                        .font(AppFont.caption).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.bottom, 10)
                }
                SDivider()
                SRow(title: "Known issues and requests") { Button("View on GitHub") { NSWorkspace.shared.open(Legal.issuesURL) } }
            }
            SGroup(title: "Terms & legal", footer: "Last updated \(Legal.updated). This is a plain-English summary for a free hobby app, not legal advice.") {
                ForEach(Array(Legal.sections.enumerated()), id: \.element.id) { i, sec in
                    if i > 0 { SDivider() }
                    DisclosureGroup(isExpanded: Binding(
                        get: { openLegal.value.contains(sec.id) },
                        set: { on in if on { openLegal.value.insert(sec.id) } else { openLegal.value.remove(sec.id) } })) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(sec.body.enumerated()), id: \.offset) { _, line in
                                Text(line).font(AppFont.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.top, 6).frame(maxWidth: .infinity, alignment: .leading)
                    } label: { Text(sec.title).fontWeight(.semibold) }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
            }
            Text("Claude Usage is unofficial and not affiliated with or endorsed by Anthropic. Figures and forecasts are estimates.")
                .font(AppFont.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
        }
    }

    private var aboutPane: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84)
                Text("Claude Usage").font(AppFont.title2.bold())
                Text("Version \(AppInfo.version) \(AppInfo.stage)").foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity)
            SGroup {
                SRow(title: "Version") { Text("\(AppInfo.version) \(AppInfo.stage)").foregroundStyle(.secondary) }
                SDivider()
                SRow(title: "Build") { Text(AppInfo.build).foregroundStyle(.secondary).monospacedDigit() }
                SDivider()
                SRow(title: "Source code") { Link(AppInfo.repoURL.absoluteString.replacingOccurrences(of: "https://", with: ""), destination: AppInfo.repoURL) }
            }
            SGroup(footer: "Claude Usage is free and open source. If it saves you from a surprise limit, a coffee helps keep it going – entirely optional.") {
                SRow(title: "Support the developer") { CoffeeButton() }
            }
            updatesGroup
            changelogGroup
            Text("Beta – there may still be rough edges. Limit numbers come from the same source as Claude Code’s /usage. Unofficial – not affiliated with Anthropic.")
                .font(AppFont.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
            HStack(spacing: 14) {
                Button("Terms & Legal") { store.settingsCategory = .support }
                Button("Report a Bug…") { NSWorkspace.shared.open(Legal.newIssueURL) }
            }.buttonStyle(.link).padding(.horizontal, 8)
        }
    }

    @ViewBuilder private var changelogGroup: some View {
        let all = Changelog.load()
        let entries = Array(all.prefix(3))          // the app only shows the last three versions; the rest is on GitHub
        SGroup(title: "Change log", footer: entries.isEmpty ? nil : (all.count > 3 ? "The last 3 of \(all.count) versions, newest first." : "Newest first.")) {
            if entries.isEmpty {
                SRow(title: "Change log unavailable") { EmptyView() }
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
                    if i > 0 { SDivider() }
                    DisclosureGroup(isExpanded: Binding(
                        get: { openVersions.value.contains(e.version) },
                        set: { on in if on { openVersions.value.insert(e.version) } else { openVersions.value.remove(e.version) } })) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(e.items.enumerated()), id: \.offset) { _, item in
                                HStack(alignment: .top, spacing: 8) { Text("•"); Text(item).fixedSize(horizontal: false, vertical: true) }
                                    .font(AppFont.callout).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 6).padding(.leading, 2).frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        HStack(spacing: 8) {
                            Text("Version \(e.version)").fontWeight(.semibold)
                            if e.version == AppInfo.version {
                                Text("CURRENT").font(AppFont.system(size: 9, weight: .bold)).foregroundStyle(Color.brand)
                                    .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Color.brand.opacity(0.18)))
                            }
                            Spacer()
                            Text([e.stage, e.date].filter { !$0.isEmpty }.joined(separator: " · ")).font(AppFont.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
                if all.count > 3 {
                    SDivider()
                    SRow(title: "Full change log") { Button("View on GitHub") { store.actions.openChangelog() } }
                }
            }
        }
    }

    private var updatePending: Bool { switch store.update { case .available, .ready: return true; default: return false } }

    @ViewBuilder private func notesList(_ u: UpdateInfo) -> some View {
        Text("What’s new").font(AppFont.subheadline.weight(.semibold))
        ForEach(Array(u.notes.prefix(6).enumerated()), id: \.offset) { _, n in
            HStack(alignment: .top, spacing: 8) { Text("•"); Text(n).fixedSize(horizontal: false, vertical: true) }.font(AppFont.callout).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var updatesGroup: some View {
        let statusText: String = {
            switch store.update {
            case .idle: return "Not checked yet"
            case .checking: return "Checking…"
            case .upToDate(let d): return "You’re up to date · checked \(d.formatted(date: .omitted, time: .shortened))"
            case .available(let u): return "Version \(u.version) is available"
            case .ready(let u, _): return "Version \(u.version) is ready to install"
            case .failed(let m): return m
            }
        }()
        SGroup(title: "Updates") {
            SRow(title: statusText, subtitle: updatePending ? "You have \(Updater.installed)." : nil) {
                Button("Check Now") { store.actions.checkUpdates() }
            }
            SDivider()
            SRow(title: "Check automatically", subtitle: "Checks GitHub for a newer version every few hours and shows a banner in the app.") {
                Toggle("", isOn: $settings.autoCheckUpdates).labelsHidden().toggleStyle(.switch)
            }
            if store.canInstall {
                SDivider()
                SRow(title: "Download updates in the background", subtitle: "Downloads new versions quietly, then asks you to restart to finish.") {
                    Toggle("", isOn: $settings.autoDownloadUpdates).labelsHidden().toggleStyle(.switch)
                }
            }
            if case .ready(let u, _) = store.update {
                SDivider()
                VStack(alignment: .leading, spacing: 8) {
                    notesList(u)
                    HStack {
                        Button("Restart & Update") { store.actions.applyUpdate() }.buttonStyle(.borderedProminent)
                        Button("View on GitHub") { store.actions.openChangelog() }
                    }.padding(.top, 4)
                    Text("Claude Usage will close and reopen. Your current version is kept as a backup.").font(AppFont.caption).foregroundStyle(.secondary)
                    if let e = store.installError { Text(e).font(AppFont.caption).foregroundStyle(Color.danger).fixedSize(horizontal: false, vertical: true) }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            } else if case .available(let u) = store.update {
                SDivider()
                VStack(alignment: .leading, spacing: 8) {
                    notesList(u)
                    if store.installing {
                        Label("\(store.installMessage) \(Int((store.installProgress * 100).rounded()))% – progress is shown at the top of the window.", systemImage: "arrow.triangle.2.circlepath")
                            .font(AppFont.callout).foregroundStyle(.secondary).padding(.top, 4)       // one progress bar only (the banner above every page)
                    } else if !store.canInstall {
                        if let f = store.downloadedInstaller {
                            Label("Saved \(f.lastPathComponent) to your Downloads folder", systemImage: "checkmark.circle.fill").font(AppFont.callout).padding(.top, 4)
                            HStack {
                                Button("Open Installer") { store.actions.openInstaller() }.buttonStyle(.borderedProminent)
                                Button("Show in Finder") { store.actions.showInstaller() }
                            }
                            Text("Drag Claude Usage onto Applications to finish updating.").font(AppFont.caption).foregroundStyle(.secondary)
                        } else {
                            HStack {
                                Button("Download Update") { store.actions.downloadInstaller() }.buttonStyle(.borderedProminent)
                                Button("View on GitHub") { store.actions.openChangelog() }
                            }.padding(.top, 4)
                            Text("This copy can’t replace itself (it isn’t in a folder it can write to, such as Applications), so it downloads the verified installer for version \(u.version) to your Downloads folder instead.")
                                .font(AppFont.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        HStack {
                            Button("Update Now") { store.actions.installUpdate() }.buttonStyle(.borderedProminent)
                            Button("View on GitHub") { store.actions.openChangelog() }
                            Button("Copy command") { store.actions.copyUpdateCommand() }
                        }.padding(.top, 4)
                        Text("Update Now downloads version \(u.version) from GitHub, checks its signature, swaps it in and relaunches. Your current version is kept as a backup.")
                            .font(AppFont.caption).foregroundStyle(.secondary)
                    }
                    if let e = store.installError { Text(e).font(AppFont.caption).foregroundStyle(Color.danger).fixedSize(horizontal: false, vertical: true) }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
