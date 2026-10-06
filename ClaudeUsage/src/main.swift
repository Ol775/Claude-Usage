import AppKit
import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

final class App: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let store = Store.shared
    let settings = Settings.shared
    var timer: Timer?
    var refreshing = false
    var lastFetch = Date.distantPast
    var dashboard: NSWindow?
    var loginProcess: Process?
    var shownSignedOutPrompt = false
    static var notificationsEnabled = true      // off in snapshot/tour modes

    /// Ordered so trimming keeps the newest keys (a Set would drop arbitrary ones and re-fire alerts).
    var notified: [String] {
        get { UserDefaults.standard.stringArray(forKey: "notifiedKeys") ?? [] }
        set { UserDefaults.standard.set(Array(newValue.suffix(80)), forKey: "notifiedKeys") }
    }

    // MARK: lifecycle

    func applicationDidFinishLaunching(_ n: Notification) {
        settings.applyAppearance()
        applyPolicy()
        settings.onChange = { [weak self] in DispatchQueue.main.async { self?.applyPolicy(); self?.applyWindowStyle(); self?.scheduleTimer(); self?.build(self?.store.snapshot ?? Snapshot()) } }
        store.actions = Actions(
            signIn: { [weak self] in self?.signIn() }, signOut: { [weak self] in self?.signOut() },
            cancelSignIn: { [weak self] in self?.loginProcess?.terminate() },
            choosePhoto: { [weak self] in self?.choosePhoto() }, removePhoto: { [weak self] in removeAvatar(); self?.photoChanged() },
            refresh: { [weak self] in self?.lastFetch = .distantPast; self?.refresh() },
            testNotify: { [weak self] in self?.notify("Claude Usage", "Notifications are working.") },
            testImportant: { [weak self] in self?.notify("Claude Usage", "This is how an important alert looks.", important: true) },
            openNotificationSettings: {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
            },
            requestNotifications: { [weak self] in self?.requestNotifications() },
            exportData: { [weak self] in self?.exportData() },
            copySummary: { [weak self] in self?.copySummary() })
        installMainMenu()
        if App.notificationsEnabled { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in self?.refreshNotifStatus() } }
        item.button?.image = menuBarBotImage(); item.button?.imagePosition = .imageLeft
        item.button?.attributedTitle = NSAttributedString(string: " …")
        build(Snapshot())

        if CommandLine.arguments.contains("--test-notify") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.notify("Claude Usage", "Notifications are working.") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { exit(0) }
            return
        }
        if CommandLine.arguments.contains("--tour") { startTour(); return }
        if !UserDefaults.standard.bool(forKey: "launchedBefore") {
            UserDefaults.standard.set(true, forKey: "launchedBefore")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.showDashboard(.overview) }
        }
        refresh()
        scheduleTimer()
    }

    func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Double(max(1, settings.refreshMinutes)) * 60, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func applyWindowStyle() { dashboard?.backgroundColor = settings.isOLED ? .black : .windowBackgroundColor }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showDashboard(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applyPolicy() {
        let want: NSApplication.ActivationPolicy = settings.showInDock ? .regular : .accessory
        if NSApp.activationPolicy() != want {
            NSApp.setActivationPolicy(want)
            if want == .regular, dashboard?.isVisible == true { NSApp.activate(ignoringOtherApps: true) }
        }
    }

    // MARK: windows & menus

    @objc func openDashboard() { showDashboard(.overview) }
    @objc func openSettings() { showDashboard(.settings) }
    @objc func openReports() { showDashboard(.reports) }
    @objc func openRepo() { NSWorkspace.shared.open(AppInfo.repoURL) }
    @objc func copySummaryAction() { copySummary() }
    func showDashboard(_ tab: DashTab? = nil) {
        if let t = tab { store.tab = t }
        if dashboard == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1020, height: 720),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "Claude Usage"; w.contentMinSize = NSSize(width: 860, height: 600); w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: DashboardView(store: store))
            if !w.setFrameUsingName("Dashboard") { w.center() }
            w.setFrameAutosaveName("Dashboard")
            dashboard = w
            applyWindowStyle()
        }
        NSApp.activate(ignoringOtherApps: true)
        dashboard?.makeKeyAndOrderFront(nil)
    }

    @objc func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Claude Usage",
            .applicationVersion: "\(AppInfo.version) \(AppInfo.stage)",
            .version: AppInfo.build,
            .credits: NSAttributedString(string: "Shows your Claude session and weekly limits, reset times and usage forecasts.\nAn unofficial app – not affiliated with Anthropic.\n\(AppInfo.repoURL.absoluteString)",
                                         attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])])
    }

    func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        func add(_ m: NSMenu, _ t: String, _ a: Selector, _ k: String, target: AnyObject? = nil) { let i = m.addItem(withTitle: t, action: a, keyEquivalent: k); i.target = target }
        add(appMenu, "About Claude Usage", #selector(showAbout), "", target: self)
        appMenu.addItem(.separator())
        add(appMenu, "Settings…", #selector(openSettings), ",", target: self)
        appMenu.addItem(.separator())
        add(appMenu, "Hide Claude Usage", #selector(NSApplication.hide(_:)), "h")
        add(appMenu, "Quit Claude Usage", #selector(NSApplication.terminate(_:)), "q")
        appItem.submenu = appMenu
        let winItem = NSMenuItem(); main.addItem(winItem)
        let win = NSMenu(title: "Window")
        add(win, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        add(win, "Zoom", #selector(NSWindow.performZoom(_:)), "")
        add(win, "Dashboard", #selector(openDashboard), "0", target: self)
        winItem.submenu = win; NSApp.windowsMenu = win
        NSApp.mainMenu = main
    }

    // MARK: data refresh

    @objc func refreshAction() { lastFetch = .distantPast; refresh() }
    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        let needFetch = Date().timeIntervalSince(lastFetch) > 100
        DispatchQueue.global(qos: .utility).async {
            let s = scan()
            var acct: Account?
            var fetched: (limits: [Limit], error: String?)?
            if needFetch { acct = fetchAccount(); fetched = acct!.loggedIn ? fetchLimits() : ([], "Sign in to see your limits") }
            DispatchQueue.main.async {
                self.refreshing = false
                if let f = fetched, let a = acct {
                    self.lastFetch = Date()
                    self.store.account = a
                    if a.loggedIn { ActivityStore.shared.markSignedIn() }
                    if f.error == nil {
                        self.store.limits = f.limits; self.store.limitError = nil; self.store.stale = false
                        History.shared.record(f.limits); self.store.samples = History.shared.samples
                    } else if f.error?.hasPrefix("Usage unavailable") == true, !self.store.limits.isEmpty {
                        self.store.stale = true            // network blip: keep the last good numbers instead of blanking the UI
                    } else { self.store.limits = []; self.store.limitError = f.error; self.store.stale = false }
                    if !a.loggedIn, !self.shownSignedOutPrompt, App.notificationsEnabled { self.shownSignedOutPrompt = true; self.store.settingsCategory = .account; self.showDashboard(.settings) }
                }
                self.store.snapshot = s; self.store.lastUpdated = Date()
                self.refreshNotifStatus()
                self.build(s)
            }
        }
    }

    // MARK: notifications

    func notify(_ title: String, _ body: String, important: Bool = false) {
        guard App.notificationsEnabled, settings.notificationsOn || title == "Claude Usage" else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { st in
            DispatchQueue.main.async {
                if st.authorizationStatus == .authorized || st.authorizationStatus == .provisional {
                    let c = UNMutableNotificationContent(); c.title = title; c.body = body; c.sound = .default
                    if important { c.interruptionLevel = .timeSensitive; c.relevanceScore = 1; c.subtitle = "Important"; c.threadIdentifier = "claude-usage-important" }
                    center.add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
                } else {
                    // macOS is blocking notifications for this app: show our own banner (with the icon) so the alert isn't lost.
                    Toast.show(title, body, important: important) { [weak self] in self?.showDashboard(.settings) }
                }
            }
        }
    }

    func refreshNotifStatus() {
        guard App.notificationsEnabled else { return }
        UNUserNotificationCenter.current().getNotificationSettings { st in
            DispatchQueue.main.async {
                switch st.authorizationStatus {
                case .authorized, .provisional: self.store.notifStatus = "Allowed"; self.store.notifBlocked = false
                case .denied: self.store.notifStatus = "Blocked"; self.store.notifBlocked = true
                default: self.store.notifStatus = "Not asked yet"; self.store.notifBlocked = false
                }
            }
        }
    }

    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                self.refreshNotifStatus()
                if !granted { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!) }
            }
        }
    }

    // MARK: export & share

    func exportData() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder for the CSV files"; panel.prompt = "Export"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        let s = store.snapshot
        let day = ISO8601DateFormatter(); day.formatOptions = [.withFullDate]
        var daily = "date,tokens\n"
        for (d, v) in zip(s.dailyDates, s.daily) { daily += "\(day.string(from: d)),\(v)\n" }
        let tf = ISO8601DateFormatter()
        var limits = "time,session_percent,session_resets,weekly_percent,weekly_resets\n"
        for x in History.shared.samples {
            limits += "\(tf.string(from: x.t)),\(x.session),\(x.sessionReset.map { tf.string(from: $0) } ?? ""),\(x.weekly),\(x.weeklyReset.map { tf.string(from: $0) } ?? "")\n"
        }
        let a = dir.appendingPathComponent("claude-usage-daily.csv"), b = dir.appendingPathComponent("claude-usage-limits.csv")
        do {
            try daily.write(to: a, atomically: true, encoding: .utf8); try limits.write(to: b, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([a, b])
        } catch {
            let al = NSAlert(); al.messageText = "Couldn’t save the files"; al.informativeText = error.localizedDescription; al.runModal()
        }
    }

    func copySummary() {
        var lines = ["Claude usage – " + Date().formatted(date: .abbreviated, time: .shortened)]
        for l in store.limits where l.kind != .other {
            lines.append("\(l.name): \(Int(l.percent.rounded()))% – \(untilText(l.resets).lowercased())")
            lines.append("  \(Predictor.describe(Predictor.forecast(l, samples: store.samples, activity: store.snapshot.days)))")
        }
        let s = store.snapshot
        lines.append("Today: \(fmt(s.today.billable)) tokens, \(s.messagesToday) responses · 7 days: \(fmt(s.week.billable)) · month: \(fmt(s.month.billable))")
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        Toast.show("Summary copied", "Your usage summary is on the clipboard.")
    }

    func checkLimits() {
        var seen = notified
        func once(_ key: String, _ title: String, _ body: String, critical: Bool = false) {
            guard !seen.contains(key) else { return }
            let important = settings.importance == .all || (settings.importance == .critical && critical)
            seen.append(key); notify(title, body, important: important)
        }
        for l in store.limits where l.kind != .other {
            let reset = l.resets.map { Int($0.timeIntervalSince1970 / 60) } ?? 0
            let pct = Int(l.percent)
            for t in Array(Set([settings.warnThreshold, settings.criticalThreshold, 100])).sorted() where pct >= t {
                let when = untilText(l.resets).replacingOccurrences(of: "Resets", with: "resets")
                once("\(l.name)|\(reset)|\(t)", t >= 100 ? "\(l.name) limit reached" : "\(l.name) at \(t)%", "Usage is \(pct)% – \(when)", critical: t >= settings.criticalThreshold)
            }
            if settings.predictiveAlerts, case .hits(let at, _, _) = Predictor.forecast(l, samples: store.samples, activity: store.snapshot.days) {
                let soon = at.timeIntervalSinceNow < (l.kind == .session ? 3600 : 86400)
                if soon { once("\(l.name)|\(reset)|pace", "On pace to hit your \(l.kind == .session ? "session" : "weekly") limit", Predictor.describe(.hits(at: at, perHour: 0, recent: true)), critical: true) }
            }
        }
        notified = seen
    }

    // MARK: sign in / out / photo

    func signIn() {
        guard let bin = claudeBinary() else {
            let a = NSAlert(); a.messageText = "Claude Code not found"
            a.informativeText = "Sign-in uses Claude’s official login, which comes with Claude Code. Install it (claude.com/claude-code), then try again."
            NSApp.activate(ignoringOtherApps: true); a.runModal(); return
        }
        guard loginProcess == nil else { return }
        let p = Process(); p.executableURL = URL(fileURLWithPath: bin); p.arguments = ["auth", "login"]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        p.environment = env; p.standardOutput = Pipe(); p.standardError = Pipe()
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.loginProcess = nil; self.store.loginBusy = false; self.lastFetch = .distantPast; self.refresh()
                DispatchQueue.global().async {
                    let a = fetchAccount()
                    DispatchQueue.main.async { if a.loggedIn { self.notify("Signed in to Claude", "Welcome, \(a.name). Your limits are now showing in the menu bar.") } }
                }
            }
        }
        do { try p.run(); loginProcess = p; store.loginBusy = true } catch { NSSound.beep() }
    }

    func signOut() {
        let a = NSAlert(); a.messageText = "Sign out of Claude?"
        a.informativeText = "This also signs out Claude Code, because they share one Claude login."
        a.addButton(withTitle: "Sign out"); a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        DispatchQueue.global().async {
            runClaude(["auth", "logout"])
            DispatchQueue.main.async {
                self.store.limits = []; self.store.account = Account(); self.store.limitError = "Sign in to see your limits"
                self.lastFetch = .distantPast; self.refresh()
            }
        }
    }

    func photoChanged() { store.photo = avatarImage; build(store.snapshot) }
    func choosePhoto() {
        let panel = NSOpenPanel()
        panel.title = "Choose a profile photo"; panel.message = "The photo stays on this Mac."
        panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if saveAvatar(from: url) { photoChanged() } else {
            let a = NSAlert(); a.messageText = "Couldn’t use that image"; a.informativeText = "Pick a JPEG, PNG or HEIC photo."; a.runModal()
        }
    }

    // MARK: menu bar menu

    func add(_ m: NSMenu, _ v: NSView) { let i = NSMenuItem(); i.view = v; m.addItem(i) }
    func header(_ m: NSMenu, _ t: String) { add(m, RowView(left: t.uppercased(), leftBold: true, size: 10, tint: claudeOrange)) }
    func block(_ m: NSMenu, _ name: String, _ u: Usage) {
        add(m, RowView(left: name, right: fmt(u.billable),
                       sub: "in \(fmt(u.input)) · out \(fmt(u.output)) · cache write \(fmt(u.cacheWrite)) · cache read \(fmt(u.cacheRead))"))
    }

    func build(_ s: Snapshot) {
        checkLimits()
        let font = NSFont.menuBarFont(ofSize: 0)
        let t = NSMutableAttributedString()
        func piece(_ label: String, _ l: Limit) -> NSAttributedString {
            // "D 17%": the letter is a little bolder; the value turns red at the critical threshold, otherwise it follows the menu bar colour.
            let out = NSMutableAttributedString(string: label + " ", attributes: [.font: NSFont.systemFont(ofSize: font.pointSize, weight: .semibold)])
            var attrs: [NSAttributedString.Key: Any] = [.font: font]
            if l.percent >= Double(settings.criticalThreshold) { attrs[.foregroundColor] = alertRed }
            out.append(NSAttributedString(string: "\(Int(l.percent.rounded()))%", attributes: attrs))
            return out
        }
        func plain(_ x: String) -> NSAttributedString { NSAttributedString(string: x, attributes: [.font: font]) }
        // D = the current session ("day"), W = the weekly limit
        let sess = store.limits.first(where: { $0.kind == .session }), week = store.limits.first(where: { $0.kind == .weekly })
        switch settings.menuBarStyle {
        case .iconOnly: break
        case .tokens: t.append(plain(" " + fmt(s.today.billable)))
        case .session: if let x = sess { t.append(plain(" ")); t.append(piece("D", x)) } else { t.append(plain(" " + fmt(s.today.billable))) }
        case .weekly: if let x = week { t.append(plain(" ")); t.append(piece("W", x)) } else { t.append(plain(" " + fmt(s.today.billable))) }
        case .both:
            if let x = sess { t.append(plain(" ")); t.append(piece("D", x)); if let w = week { t.append(plain("  ")); t.append(piece("W", w)) } }
            else { t.append(plain(" " + fmt(s.today.billable))) }
        }
        item.button?.image = menuBarBotImage(); item.button?.imagePosition = .imageLeft
        item.button?.toolTip = "Claude Usage – D = current session, W = weekly limit"
        item.button?.attributedTitle = t

        let m = NSMenu()
        add(m, AccountView(store.account))
        m.addItem(.separator())
        let main = store.limits.filter { $0.kind != .other }
        if main.isEmpty {
            add(m, RowView(left: store.limitError ?? "Loading limits…", leftBold: false, size: 12, tint: .secondaryLabelColor))
        } else {
            for l in main {
                let f = Predictor.forecast(l, samples: store.samples, activity: store.snapshot.days)
                var hot = false
                switch f { case .hits, .reached: hot = true; default: break }
                add(m, UsageBarView(l, forecast: Predictor.describe(f), hot: hot))
            }
        }
        if store.stale { add(m, RowView(left: "Couldn’t reach Anthropic – showing last reading", leftBold: false, size: 10, tint: .secondaryLabelColor)) }
        m.addItem(.separator())
        block(m, "Today", s.today)
        add(m, RowView(left: "\(s.messagesToday) responses today", leftBold: false, size: 11, tint: .secondaryLabelColor))
        m.addItem(.separator())
        let cal = Calendar.current, df = DateFormatter(); df.dateFormat = "d MMM"
        let days14 = Array(s.daily.suffix(14)), dates14 = Array(s.dailyDates.suffix(14))
        let dl = (0..<days14.count).map { i -> String in
            guard [0, 4, 8, 13].contains(i), i < dates14.count else { return "" }
            return df.string(from: dates14[i])
        }
        let c1 = NSMenuItem(); c1.view = ChartView(title: "Last 14 days", values: days14, labels: dl, highlight: days14.count - 1); m.addItem(c1)
        let hl = (0..<24).map { $0 % 6 == 0 ? String(format: "%02d", $0) : "" }
        let c2 = NSMenuItem(); c2.view = ChartView(title: "Today by hour", values: s.hourly, labels: hl, highlight: cal.component(.hour, from: Date())); m.addItem(c2)
        m.addItem(.separator())
        block(m, "Last 7 days", s.week)
        block(m, "This month", s.month)
        if s.byModelToday.contains(where: { $0.value.billable > 0 }) {
            m.addItem(.separator()); header(m, "Today by model")
            for (k, v) in s.byModelToday.filter({ $0.value.billable > 0 }).sorted(by: { $0.value.billable > $1.value.billable }) {
                add(m, RowView(left: k, right: fmt(v.billable), leftBold: false, size: 12))
            }
        }
        m.addItem(.separator())
        let f = DateFormatter(); f.timeStyle = .short
        add(m, RowView(left: "Updated \(f.string(from: s.updated)) · \(AppInfo.display)", leftBold: false, size: 10, tint: .secondaryLabelColor))
        let d = NSMenuItem(title: "Open Dashboard…", action: #selector(openDashboard), keyEquivalent: "d"); d.target = self; m.addItem(d)
        let rp = NSMenuItem(title: "Open Reports…", action: #selector(openReports), keyEquivalent: "e"); rp.target = self; m.addItem(rp)
        let cs = NSMenuItem(title: "Copy Usage Summary", action: #selector(copySummaryAction), keyEquivalent: "c"); cs.target = self; m.addItem(cs)
        let r = NSMenuItem(title: "Refresh", action: #selector(refreshAction), keyEquivalent: "r"); r.target = self; m.addItem(r)
        let gh = NSMenuItem(title: "GitHub Repository", action: #selector(openRepo), keyEquivalent: ""); gh.target = self; m.addItem(gh)
        let ab = NSMenuItem(title: "About Claude Usage", action: #selector(showAbout), keyEquivalent: ""); ab.target = self; m.addItem(ab)
        m.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = m
    }

    // MARK: screenshot tour (development aid: `--tour` cycles tabs × appearances and writes /tmp/cub_tour.txt)

    func startTour() {
        Settings.persist = false
        showDashboard(.overview)
        refresh()
        var steps: [(AppearanceMode, DashTab, AccentTheme)] = []
        for a in [AppearanceMode.dark, .light] { for t in DashTab.allCases { steps.append((a, t, .claude)) } }
        for t in [DashTab.overview, .reports, .usage, .settings] { steps.append((.oled, t, .claude)) }
        if let n = CommandLine.arguments.first(where: { $0.hasPrefix("--steps=") }).flatMap({ Int($0.dropFirst(8)) }) { steps = Array(steps.prefix(n)) }
        var i = 0
        func finish() { try? "done".write(toFile: "/tmp/cub_tour.txt", atomically: true, encoding: .utf8); DispatchQueue.main.asyncAfter(deadline: .now() + 1) { exit(0) } }
        // Full-height renders of the long pages (a normal window only shows the top), captured from outside by the tour script.
        func tall(_ idx: Int = 0) {
            let shots: [(AppearanceMode, String)] = [(.dark, "insights"), (.light, "insights"), (.oled, "insights")]
            guard idx < shots.count else { finish(); return }
            let (mode, name) = shots[idx]
            settings.appearance = mode
            let w = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 1020, height: 3700), styleMask: [.borderless], backing: .buffered, defer: false)
            w.contentView = NSHostingView(rootView: InsightsView(store: store).frame(width: 1020, height: 3700).background(settings.isOLED ? Color.black : Color(nsColor: .windowBackgroundColor)))
            w.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                try? "\(100 + idx) tall-\(name)-\(mode.rawValue) \(w.windowNumber)".write(toFile: "/tmp/cub_tour.txt", atomically: true, encoding: .utf8)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { w.orderOut(nil); tall(idx + 1) }
            }
        }
        if CommandLine.arguments.contains("--tall-only") { DispatchQueue.main.asyncAfter(deadline: .now() + 6) { tall() }; return }
        func next() {
            guard i < steps.count else { tall(); return }
            let (a, t, th) = steps[i]; i += 1
            settings.appearance = a; settings.theme = th; store.tab = t
            if t == .settings { store.settingsCategory = a == .dark ? .appearance : (a == .light ? .account : .notifications) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                try? "\(i) \(a.rawValue)-\(t.rawValue)-\(th.rawValue) \(self.dashboard?.windowNumber ?? 0)".write(toFile: "/tmp/cub_tour.txt", atomically: true, encoding: .utf8)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { next() }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { next() }
    }
}

// MARK: - entry points

if CommandLine.arguments.contains("--snapshot") {
    // Renders the menu bar menu to /tmp/menu_snapshot_<dark|light>.png without showing it.
    _ = NSApplication.shared
    App.notificationsEnabled = false
    let d = App()
    d.store.account = fetchAccount()
    let fl = fetchLimits(); d.store.limits = fl.limits; d.store.limitError = fl.error
    d.store.samples = History.shared.samples
    d.build(scan())
    // Menu items own and re-frame their views, so detach them first and lay them out in a plain host view.
    let views = (d.item.menu?.items ?? []).map { $0.view ?? NSView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 9)) }
    for i in d.item.menu?.items ?? [] { i.view = nil }
    for (name, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
        let H = views.reduce(0) { $0 + $1.frame.height }
        let host = NSView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: H))
        host.appearance = NSAppearance(named: appearance)
        host.wantsLayer = true
        host.layer?.backgroundColor = (name == "dark" ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.96, alpha: 1)).cgColor
        for v in views { v.removeFromSuperview() }
        var y = H
        for v in views { y -= v.frame.height; v.setFrameOrigin(NSPoint(x: 0, y: y)); host.addSubview(v) }
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/menu_snapshot_\(name).png"))
    }
    exit(0)
}

if CommandLine.arguments.contains("--dump") {
    // Dev aid: prints 30-day totals so they can be cross-checked against the raw logs.
    let snap = scan(), cal = Calendar.current, today = cal.startOfDay(for: Date())
    var t = DayRecord(), active = 0
    for i in 0..<30 {
        let d = cal.date(byAdding: .day, value: -i, to: today)!
        guard let r = snap.days[dayKey(d)] else { continue }
        t.prompts += r.prompts; t.responses += r.responses; t.toolCalls += r.toolCalls; t.sessions += r.sessions
        t.input += r.input; t.output += r.output; t.cacheWrite += r.cacheWrite; t.cacheRead += r.cacheRead; t.cost += r.cost
        if r.billable > 0 { active += 1 }
    }
    print("30d prompts=\(t.prompts) responses=\(t.responses) tools=\(t.toolCalls) sessions=\(t.sessions) active=\(active)")
    print("30d input=\(t.input) output=\(t.output) cacheWrite=\(t.cacheWrite) cacheRead=\(t.cacheRead) cost=\(money(t.cost))")
    print("stored days=\(snap.days.count) unpriced=\(snap.unpricedModels.sorted())")
    exit(0)
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.run()
