import AppKit
import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

final class App: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSMenuDelegate {
    lazy var item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let store = Store.shared
    let settings = Settings.shared
    var timer: Timer?
    var updateTimer: Timer?
    var refreshing = false
    var lastFetch = Date.distantPast
    var dashboard: NSWindow?
    var loginProcess: Process?
    var chatgptProcess: Process?
    var shownSignedOutPrompt = false
    var menuOpen = false, pendingBuild = false, pendingRefresh = false
    var scheduledMinutes = 0, scheduledAutoCheck: Bool?
    static var notificationsEnabled = true      // off in snapshot/tour modes
    static var isTour = false

    /// Ordered so trimming keeps the newest keys (a Set would drop arbitrary ones and re-fire alerts).
    var notified: [String] {
        get { UserDefaults.standard.stringArray(forKey: "notifiedKeys") ?? [] }
        set { UserDefaults.standard.set(Array(newValue.suffix(80)), forKey: "notifiedKeys") }
    }

    // MARK: lifecycle

    func applicationDidFinishLaunching(_ n: Notification) {
        store.canInstall = canSelfUpdate
        Legal.stateProvider = { [weak self] in self?.diagnosticState() ?? [] }
        Pricing.loadCached()          // prices fetched earlier (see Pricing.refreshIfStale) apply from the first scan
        let lastRun = UserDefaults.standard.string(forKey: "lastRunVersion")
        UserDefaults.standard.set(AppInfo.version, forKey: "lastRunVersion")
        if let lastRun = lastRun, isNewer(AppInfo.version, than: lastRun) {          // first launch after an update: say what changed, once
            let first = Changelog.load().first { isNewer($0.version, than: lastRun) }?.items.first
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                self.notify("Updated to Claude Usage \(AppInfo.version)", first ?? "See what’s new in Settings → About.", openAbout: true, system: true)
            }
        }
        // Only one copy should run (a second one would add a second menu bar icon). Test flags (--tour etc.) are exempt.
        if CommandLine.arguments.contains("--quiet") { App.notificationsEnabled = false }
        if !CommandLine.arguments.dropFirst().contains(where: { $0.hasPrefix("--") && $0 != "--quiet" }), let id = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if let other = others.first { other.activate(); exit(0) }
        }
        // Set the Dock icon straight from the bundled icon so a stale macOS icon cache can never show an old one.
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let img = NSImage(contentsOf: url) { NSApp.applicationIconImage = img }
        settings.applyAppearance()
        applyPolicy()
        settings.onChange = { [weak self] in DispatchQueue.main.async { self?.applyPolicy(); self?.applyWindowStyle(); self?.scheduleTimer(); self?.scheduleUpdateChecks(); self?.build(self?.store.snapshot ?? Snapshot()) } }
        store.actions = Actions(
            signIn: { [weak self] in self?.signIn() }, signOut: { [weak self] in self?.signOut() },
            cancelSignIn: { [weak self] in self?.loginProcess?.terminate() },
            connectChatGPT: { [weak self] in self?.connectChatGPT() }, disconnectChatGPT: { [weak self] in self?.disconnectChatGPT() },
            signOutChatGPT: { [weak self] in self?.signOutChatGPT() }, cancelChatGPT: { [weak self] in self?.chatgptProcess?.terminate() },
            choosePhoto: { [weak self] in self?.choosePhoto() }, removePhoto: { [weak self] in removeAvatar(); self?.photoChanged() },
            refresh: { [weak self] in self?.lastFetch = .distantPast; self?.refresh() },
            testNotify: { [weak self] in self?.notify("Claude Usage", "Notifications are working.", system: true) },
            testImportant: { [weak self] in self?.notify("Claude Usage", "This is how an important alert looks.", important: true, system: true) },
            chooseStock: { [weak self] i in setStockAvatar(i); self?.store.stockIndex = i; self?.photoChanged() },
            checkUpdates: { [weak self] in self?.checkForUpdates(manual: true) },
            copyUpdateCommand: { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("cd ~/Projects/MacApps && ./update.sh", forType: .string); Toast.show("Update command copied", "Paste it into Terminal to update Claude Usage.") },
            openChangelog: { NSWorkspace.shared.open(URL(string: AppInfo.repoURL.absoluteString + "/blob/main/ClaudeUsage/CHANGELOG.md")!) },
            installUpdate: { [weak self] in self?.installUpdate() },
            applyUpdate: { [weak self] in self?.applyReadyUpdate() },
            downloadInstaller: { [weak self] in self?.downloadInstaller() },
            showInstaller: { [weak self] in if let f = self?.store.downloadedInstaller { NSWorkspace.shared.activateFileViewerSelecting([f]) } },
            openInstaller: { [weak self] in if let f = self?.store.downloadedInstaller { NSWorkspace.shared.open(f) } },
            postponeUpdate: { [weak self] in self?.store.bannerHidden = true },
            openNotificationSettings: {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
            },
            requestNotifications: { [weak self] in self?.requestNotifications() },
            exportData: { [weak self] in self?.exportData() },
            copySummary: { [weak self] in self?.copySummary() })
        installMainMenu()
        let prepared = Updater.restorePrepared()                         // an update downloaded earlier and not yet installed
        if let (info, app) = prepared { store.update = .ready(info, app) }
        if !App.isTour { DispatchQueue.global(qos: .background).async { Updater.cleanupOldDownloads(keeping: prepared?.1) } }
        if CommandLine.arguments.contains("--dump-update-state") {      // dev aid
            switch store.update { case .ready(let u, let a): print("READY", u.version, a.path); default: print("NOT READY") }
            exit(0)
        }
        if App.notificationsEnabled {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            center.setNotificationCategories([
                UNNotificationCategory(identifier: "UPDATE", actions: [UNNotificationAction(identifier: "update.now", title: "Update Now", options: [.foreground])], intentIdentifiers: [], options: []),
                UNNotificationCategory(identifier: "READY", actions: [UNNotificationAction(identifier: "restart.now", title: "Restart Now", options: [.foreground])], intentIdentifiers: [], options: [])])
        }
        if App.notificationsEnabled { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in self?.refreshNotifStatus() } }
        item.button?.image = menuBarBotImage(); item.button?.imagePosition = .imageLeft
        item.button?.attributedTitle = NSAttributedString(string: " …")
        build(Snapshot())

        if CommandLine.arguments.contains("--test-notify") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.notify("Claude Usage", "Notifications are working.", system: true) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { exit(0) }
            return
        }
        if CommandLine.arguments.contains("--dump-title") {              // dev aid: shows the menu bar text each preset produces
            Settings.persist = false
            refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                for p in MenuBarPreset.allCases {
                    self.settings.apply(p); self.build(self.store.snapshot)
                    print("\(p.rawValue.padding(toLength: 11, withPad: " ", startingAt: 0)) icon=\(self.item.button?.image != nil ? "yes" : "no ") title=\"\(self.item.button?.attributedTitle.string ?? "")\"")
                }
                self.settings.menuLabelStyle = .words; self.settings.menuShowReset = true; self.build(self.store.snapshot)
                print("words+reset  title=\"\(self.item.button?.attributedTitle.string ?? "")\"")
                self.settings.menuShowIcon = false; self.settings.menuShowSession = false; self.settings.menuShowWeekly = false; self.settings.menuShowReset = false; self.settings.menuShowTokens = false; self.build(self.store.snapshot)
                print("all off      icon=\(self.item.button?.image != nil ? "yes" : "no ") (icon must stay so the item is never blank)")
                exit(0)
            }
            return
        }
        if Dev.flag("--render-screens"), let i = CommandLine.arguments.firstIndex(of: "--render-screens"), i + 1 < CommandLine.arguments.count {
            let args = CommandLine.arguments
            let base = args.firstIndex(of: "--compare").flatMap { $0 + 1 < args.count ? URL(fileURLWithPath: args[$0 + 1]) : nil }
            runScreenTests(out: URL(fileURLWithPath: args[i + 1]), baselines: base); return
        }
        if CommandLine.arguments.contains("--tour") { startTour(); return }
        if !UserDefaults.standard.bool(forKey: "launchedBefore") {
            UserDefaults.standard.set(true, forKey: "launchedBefore")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.showDashboard(.overview) }
        }
        refresh()
        scheduleTimer()
        scheduleUpdateChecks()
        if ["--auto-check", "--auto-install", "--auto-apply"].contains(where: CommandLine.arguments.contains) { DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.checkForUpdates(manual: true) } }   // dev aids: test updates end to end
        if settings.autoCheckUpdates { DispatchQueue.main.asyncAfter(deadline: .now() + 20) { self.checkForUpdates(manual: false) } }
    }

    func scheduleTimer() {
        guard timer == nil || scheduledMinutes != settings.refreshMinutes else { return }      // settings changes (theme etc.) must not reset the refresh clock
        scheduledMinutes = settings.refreshMinutes
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
    @objc func reportBug() { NSWorkspace.shared.open(Legal.newIssueURL) }
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
        // Bring the window all the way forward: un-hide / un-minimise, then activate. (On recent macOS a plain
        // activate(ignoringOtherApps:) can leave the window behind other apps.)
        NSApp.unhide(nil)
        if dashboard?.isMiniaturized == true { dashboard?.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        dashboard?.makeKeyAndOrderFront(nil)
        dashboard?.orderFrontRegardless()
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
        guard !refreshing else { pendingRefresh = true; return }
        if Demo.enabled {            // screenshots: made-up data, nothing read from or saved to the real history
            let s = Demo.snapshot()
            if Dev.env("CUB_DEMO_SIGNEDOUT") != nil {      // dev aid: preview the first-run screen
                store.account = Account(); store.limits = []; store.limitError = nil; store.snapshot = s; store.lastUpdated = Date(); build(s); return
            }
            store.account = Demo.account; store.limits = Demo.limits(); store.limitError = nil; store.stale = false
            store.chatgpt = settings.chatgptEnabled ? ChatGPT.demo : ChatGPTState()
            store.gptSamples = settings.chatgptEnabled ? ChatGPT.demoSamples() : []
            store.samples = Demo.samples(); store.snapshot = s; store.lastUpdated = Date()
            build(s); return
        }
        refreshing = true
        DispatchQueue.global(qos: .background).async { Pricing.refreshIfStale() }
        let needFetch = Date().timeIntervalSince(lastFetch) > 100
        let wantGPT = settings.chatgptEnabled
        DispatchQueue.global(qos: .utility).async {
            let s = scan()
            var acct: Account?
            var fetched: (limits: [Limit], error: String?)?
            if needFetch { acct = fetchAccount(); fetched = acct!.loggedIn ? fetchLimits() : ([], "Sign in to see your limits") }
            let gpt: ChatGPTState? = needFetch && wantGPT ? ChatGPT.fetch() : nil
            DispatchQueue.main.async {
                self.refreshing = false
                defer { if self.pendingRefresh { self.pendingRefresh = false; self.refresh() } }
                if let f = fetched, let a = acct {
                    self.lastFetch = Date()
                    self.store.account = a
                    if a.loggedIn { ActivityStore.shared.markSignedIn() }
                    if let e = f.error { AppLog.write("Claude limits: \(e)") }
                    if f.error == nil {
                        self.store.limits = f.limits; self.store.limitError = nil; self.store.stale = false; self.store.staleReason = nil
                        History.shared.record(f.limits); self.store.samples = History.shared.samples
                    } else if f.error?.hasPrefix("Usage unavailable") == true || f.error?.hasPrefix("Usage response not recognised") == true, !self.store.limits.isEmpty {
                        self.store.stale = true            // network blip or changed response: keep the last good numbers instead of blanking the UI
                        self.store.staleReason = f.error?.hasPrefix("Usage response") == true ? "Claude’s usage format changed – showing the last reading. Please update the app or report a bug." : nil
                    } else { self.store.limits = []; self.store.limitError = f.error; self.store.stale = false }
                    if !a.loggedIn, !self.shownSignedOutPrompt, App.notificationsEnabled { self.shownSignedOutPrompt = true; self.store.settingsCategory = .account; self.showDashboard(.settings) }
                }
                if let g = gpt {
                    if let e = g.error, !g.isFree { AppLog.write("ChatGPT limits: \(e)") }
                    if g.limits.isEmpty, g.signedIn, g.error?.hasPrefix("ChatGPT usage") == true, !self.store.chatgpt.limits.isEmpty {
                        self.store.chatgpt.error = g.error          // network blip: keep the last good numbers
                    } else {
                        self.store.chatgpt = g
                        if GPTHistory.shared.record(g.limits) || self.store.gptSamples.isEmpty { self.store.gptSamples = GPTHistory.shared.samples }
                    }
                } else if !wantGPT, self.store.chatgpt.signedIn || self.store.chatgpt.error != nil { self.store.chatgpt = ChatGPTState() }
                self.store.snapshot = s; self.store.lastUpdated = Date()
                self.refreshNotifStatus()
                self.build(s)
            }
        }
    }

    // MARK: notifications

    func notify(_ title: String, _ body: String, important: Bool = false, openAbout: Bool = false, system: Bool = false, ready: Bool = false) {
        guard App.notificationsEnabled, settings.notificationsOn || system else { return }     // `system` notices ignore the limit-alerts switch
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { st in
            DispatchQueue.main.async {
                if st.authorizationStatus == .authorized || st.authorizationStatus == .provisional {
                    let c = UNMutableNotificationContent(); c.title = title; c.body = body; c.sound = .default
                    if ready { c.userInfo = ["open": "about"]; c.categoryIdentifier = "READY" } else if openAbout { c.userInfo = ["open": "about"]; c.categoryIdentifier = "UPDATE" }
                    if important { c.interruptionLevel = .timeSensitive; c.relevanceScore = 1; c.subtitle = "Important"; c.threadIdentifier = "claude-usage-important" }
                    center.add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
                } else {
                    // macOS is blocking notifications for this app: show our own banner (with the icon) so the alert isn't lost.
                    Toast.show(title, body, important: important) { [weak self] in
                        if openAbout { self?.store.settingsCategory = .about }
                        self?.showDashboard(.settings)
                    }
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

    // MARK: updates

    func scheduleUpdateChecks() {
        guard scheduledAutoCheck != settings.autoCheckUpdates else { return }
        scheduledAutoCheck = settings.autoCheckUpdates
        updateTimer?.invalidate(); updateTimer = nil
        guard settings.autoCheckUpdates else { return }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in self?.checkForUpdates(manual: false) }
    }

    /// The short, fixed-vocabulary state lines that go into diagnostics: yes/no flags, counts and enum words only.
    /// Nothing here may include the account, a path, a token or a usage number.
    func diagnosticState() -> [String] {
        let hasSession = store.limits.contains { $0.name == "Current session" }, hasWeekly = store.limits.contains { $0.name == "Weekly – all models" }
        let extra = store.limits.filter { $0.kind == .other }.count
        let fetch: String = {
            guard let e = store.limitError else { return store.stale ? "kept last reading" : "ok" }
            if e.hasPrefix("Usage unavailable") { return "network or server error" }
            if e.hasPrefix("Usage response not recognised") { return "response format changed" }
            if e.hasPrefix("Login expired") { return "login expired" }
            if e.hasPrefix("Sign in") { return "signed out" }
            return "other error"
        }()
        let update: String = {
            switch store.update {
            case .idle, .checking: return "not checked yet"
            case .upToDate: return "up to date"
            case .available: return store.installing ? "downloading" : "available"
            case .ready: return "ready to install"
            case .failed: return "last check failed"
            }
        }()
        return [
            "Claude Code: \(claudeBinary() != nil ? "found" : "not found"), \(store.account.loggedIn ? "signed in" : "signed out")",
            "Limits: session \(hasSession ? "yes" : "no"), weekly \(hasWeekly ? "yes" : "no"), extra \(extra) (fetch: \(fetch))",
            "Updates: \(update); can self-update: \(store.canInstall ? "yes" : "no"); in Applications: \(Bundle.main.bundleURL.path.hasPrefix("/Applications/") ? "yes" : "no")",
            "ChatGPT: \(!settings.chatgptEnabled ? "off" : "on, \(store.chatgpt.signedIn ? "signed in" : "signed out")")",
            "Notifications: \(store.notifStatus)",
        ]
    }

    /// Whether this copy can replace itself: a real .app sitting in a folder we can write to.
    var canSelfUpdate: Bool {
        let url = Bundle.main.bundleURL
        return url.pathExtension == "app" && FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path)
    }

    func checkForUpdates(manual: Bool) {
        if case .ready = store.update {} else { store.update = .checking }          // keep showing a downloaded update while we look again
        DispatchQueue.global(qos: .utility).async {
            let status = Updater.check()
            DispatchQueue.main.async {
                var readyVersion: String?
                if case .ready(let r, _) = self.store.update { readyVersion = r.version }
                switch status {
                case .available(let info):
                    if let rv = readyVersion, !isNewer(info.version, than: rv) {                 // that version is already downloaded
                        if Dev.flag("--auto-apply") { self.applyReadyUpdate() }
                        break
                    }
                    if readyVersion != nil { Updater.clearPrepared() }                           // an even newer one exists
                    self.store.update = status
                    if self.settings.autoDownloadUpdates && self.canSelfUpdate && !App.isTour { self.prepareInBackground(info) }
                    else { self.notifyAvailableOnce(info) }
                default:
                    if case .failed(let m) = status { AppLog.write("Update check: \(m)") }
                    if readyVersion == nil { self.store.update = status }
                }
                self.build(self.store.snapshot)
                if Dev.flag("--auto-install") { self.installUpdate() }
            }
        }
    }

    func notifyAvailableOnce(_ info: UpdateInfo) {
        guard UserDefaults.standard.string(forKey: "notifiedUpdate") != info.version else { return }
        UserDefaults.standard.set(info.version, forKey: "notifiedUpdate")
        notify("Claude Usage \(info.version) is available", info.notes.first ?? "Open Settings → About to see what’s new.", openAbout: true, system: true)
    }

    func notifyReadyOnce(_ info: UpdateInfo) {
        guard UserDefaults.standard.string(forKey: "notifiedReady") != info.version else { return }
        UserDefaults.standard.set(info.version, forKey: "notifiedReady")
        notify("Claude Usage \(info.version) is ready to install", "Restart to finish updating. " + (info.notes.first ?? ""), openAbout: true, system: true, ready: true)
    }

    /// Downloads and builds the new version quietly (low priority), then asks for a restart to install it.
    func prepareInBackground(_ info: UpdateInfo) {
        guard !store.installing else { return }
        store.installing = true; store.downloadOnly = false; store.installProgress = 0
        store.installMessage = "Downloading version \(info.version) in the background…"; store.installError = nil
        DispatchQueue.global(qos: .background).async {
            let r = Updater.prepare(info, lowPriority: true, progress: { m in DispatchQueue.main.async { self.store.installMessage = m } }, fraction: self.reportProgress)
            DispatchQueue.main.async {
                self.store.installing = false
                if let app = r.app {
                    Updater.savePrepared(info, app: app)
                    self.store.update = .ready(info, app); self.store.bannerHidden = false
                    self.notifyReadyOnce(info); self.promptRestart(info)
                    if Dev.flag("--auto-apply") { self.applyReadyUpdate() }
                } else {
                    self.store.installError = r.error
                    AppLog.write("Update download: \(r.error ?? "failed")")
                    self.notifyAvailableOnce(info)               // couldn’t get it quietly – at least say that one exists
                }
                self.build(self.store.snapshot)
            }
        }
    }

    /// If you’re looking at the app when an update becomes ready, ask right away; otherwise the notification, menu and banner do.
    func promptRestart(_ info: UpdateInfo) {
        guard App.notificationsEnabled, let w = dashboard, w.isVisible, NSApp.isActive else { return }
        let a = NSAlert()
        a.messageText = "Claude Usage \(info.version) is ready"
        a.informativeText = "Restart now to finish updating, or choose Later. Your current version is kept as a backup."
        a.addButton(withTitle: "Restart Now"); a.addButton(withTitle: "Later")
        a.beginSheetModal(for: w) { r in if r == .alertFirstButtonReturn { self.applyReadyUpdate() } }
    }

    /// Installs the downloaded update: a helper swaps it in once this app has quit, then reopens it.
    func applyReadyUpdate() {
        guard case .ready(_, let app) = store.update else { return }
        store.installMessage = "Restarting…"
        if let error = Updater.apply(app, relaunch: Dev.env("CUB_NO_RELAUNCH") == nil) { store.installError = error }
        else { Updater.clearPrepared(); NSApp.terminate(nil) }
    }

    /// Downloads, builds and installs in one go (the Update Now button when nothing has been downloaded yet).
    func installUpdate() {
        if case .ready = store.update { applyReadyUpdate(); return }
        guard case .available(let info) = store.update, !store.installing else { return }
        if !canSelfUpdate { downloadInstaller(); return }                    // can't replace ourselves: save the installer instead
        store.installing = true; store.downloadOnly = false; store.installProgress = 0
        store.installMessage = "Starting…"; store.installError = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let error = Updater.install(info, progress: { message in DispatchQueue.main.async { self.store.installMessage = message } }, fraction: self.reportProgress)
            DispatchQueue.main.async {
                if let error = error { self.store.installing = false; self.store.installError = error }
                else { self.store.installMessage = "Restarting…"; self.store.installProgress = 1; NSApp.terminate(nil) }
            }
        }
    }

    /// Download only (this copy can't install itself): saves the verified installer to Downloads, with a progress bar.
    func downloadInstaller() {
        guard case .available(let info) = store.update, !store.installing else { return }
        store.installing = true; store.downloadOnly = true; store.installProgress = 0
        store.installMessage = "Downloading version \(info.version)…"; store.installError = nil; store.downloadedInstaller = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let r = Updater.downloadOnly(info, progress: { m in DispatchQueue.main.async { self.store.installMessage = m } }, fraction: self.reportProgress)
            DispatchQueue.main.async {
                self.store.installing = false
                if let f = r.file { self.store.downloadedInstaller = f; NSWorkspace.shared.activateFileViewerSelecting([f]) }
                else { self.store.installError = r.error; AppLog.write("Installer download: \(r.error ?? "failed")") }
                self.build(self.store.snapshot)
            }
        }
    }

    /// Passes download/install progress to the UI, a few times a second at most so the window isn't flooded.
    private func reportProgress(_ f: Double) {
        DispatchQueue.main.async {
            if abs(f - self.store.installProgress) >= 0.01 || f >= 1 { self.store.installProgress = f }
        }
    }

    @objc func checkUpdatesAction() { store.settingsCategory = .about; showDashboard(.settings); checkForUpdates(manual: true) }
    @objc func openUpdate() { store.settingsCategory = .about; showDashboard(.settings) }
    @objc func applyUpdateAction() { applyReadyUpdate() }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let opensAbout = response.notification.request.content.userInfo["open"] as? String == "about"
        DispatchQueue.main.async {
            if action == "restart.now" { self.applyReadyUpdate() }
            else if action == "update.now" {
                self.store.settingsCategory = .about; self.showDashboard(.settings)
                if case .available = self.store.update { self.installUpdate() }
                else { self.checkForUpdates(manual: true) }      // app was restarted: look again; About then offers the update
            } else if opensAbout { self.store.settingsCategory = .about; self.showDashboard(.settings) }
            else { self.showDashboard(.overview) }
        }
        completionHandler()
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
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
        lines.append("Today: \(fmt(s.today.billable)) tokens, \(plural(s.messagesToday, "response")) · 7 days: \(fmt(s.week.billable)) · month: \(fmt(s.month.billable))")
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
        var windows = UserDefaults.standard.dictionary(forKey: "alertWindows") as? [String: Int] ?? [:]
        defer { UserDefaults.standard.set(windows, forKey: "alertWindows") }
        for l in store.limits where l.kind != .other {
            // The server's reset time can wobble by seconds between fetches; keep one stable id per limit window so an alert fires once.
            let reset = stableWindow(previous: windows[l.name], new: l.resets.map { Int($0.timeIntervalSince1970 / 60) } ?? 0)
            windows[l.name] = reset
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
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\(NSHomeDirectory())/.local/bin"      // fixed order: your own folder last
        p.environment = env; p.standardOutput = Pipe(); p.standardError = Pipe()
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.loginProcess = nil; self.store.loginBusy = false; self.lastFetch = .distantPast; self.refresh()
                DispatchQueue.global().async {
                    let a = fetchAccount()
                    DispatchQueue.main.async { if a.loggedIn { self.notify("Signed in to Claude", "Welcome, \(a.name). Your limits are now showing in the menu bar.", system: true) } }
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

    // MARK: ChatGPT (through OpenAI's Codex CLI sign-in)

    func connectChatGPT() {
        settings.chatgptEnabled = true
        if ChatGPT.hasLogin { lastFetch = .distantPast; refresh(); return }
        guard let bin = ChatGPT.codexBinary() else {
            let a = NSAlert(); a.messageText = "Codex not found"
            a.informativeText = "Claude Usage reads your ChatGPT limits through OpenAI’s Codex CLI sign-in. Install it with “brew install codex” (or from github.com/openai/codex), then press Connect again."
            NSApp.activate(ignoringOtherApps: true); a.runModal(); lastFetch = .distantPast; refresh(); return
        }
        guard chatgptProcess == nil else { return }
        let p = Process(); p.executableURL = URL(fileURLWithPath: bin); p.arguments = ["login"]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\(NSHomeDirectory())/.local/bin"
        p.environment = env; p.standardOutput = Pipe(); p.standardError = Pipe()
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.chatgptProcess = nil; self.store.chatgptBusy = false; self.lastFetch = .distantPast; self.refresh()
            }
        }
        do { try p.run(); chatgptProcess = p; store.chatgptBusy = true } catch { NSSound.beep() }
    }

    func disconnectChatGPT() {
        settings.chatgptEnabled = false; settings.menuShowChatGPT = false
        store.chatgpt = ChatGPTState(); build(store.snapshot)
    }

    func signOutChatGPT() {
        let a = NSAlert(); a.messageText = "Sign out of ChatGPT?"
        a.informativeText = "This also signs out the Codex CLI, because they share one ChatGPT login."
        a.addButton(withTitle: "Sign out"); a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        DispatchQueue.global().async {
            ChatGPT.runCodex(["logout"])
            DispatchQueue.main.async { self.store.chatgpt = ChatGPTState(); self.lastFetch = .distantPast; self.refresh() }
        }
    }

    func photoChanged() { store.photo = avatarImage; store.stockIndex = stockAvatarIndex; build(store.snapshot) }
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
        let parts = MenuBarTitle.parts(limits: store.limits, tokensToday: s.today.billable, settings: settings, chatgpt: store.chatgpt.limits)
        let t = NSMutableAttributedString()
        for (i, part) in parts.enumerated() {
            t.append(NSAttributedString(string: i == 0 ? " " : "  ", attributes: [.font: font]))
            if let label = part.label { t.append(NSAttributedString(string: label + " ", attributes: [.font: NSFont.systemFont(ofSize: font.pointSize, weight: .semibold)])) }
            var attrs: [NSAttributedString.Key: Any] = [.font: font]
            if part.isPercent {
                switch settings.menuPercentColour {
                case .critical: if part.hot { attrs[.foregroundColor] = alertRed }
                case .accent: attrs[.foregroundColor] = part.hot ? alertRed : claudeOrange
                case .plain: break
                }
            }
            t.append(NSAttributedString(string: part.value, attributes: attrs))
        }
        let showIcon = settings.menuShowIcon || parts.isEmpty                       // never leave the status item blank
        if !showIcon, t.length > 0 { t.deleteCharacters(in: NSRange(location: 0, length: 1)) }
        item.button?.image = showIcon ? menuBarBotImage(mono: settings.menuIconMono) : nil
        item.button?.imagePosition = .imageLeft
        item.button?.toolTip = settings.menuLabelStyle == .letters ? "Claude Usage – D = current session, W = weekly limit" : "Claude Usage"
        item.button?.attributedTitle = t
        item.button?.setAccessibilityLabel("Claude Usage")          // VoiceOver reads the limits in words, not the D/W letters
        item.button?.setAccessibilityValue(store.limits.filter { $0.kind != .other }.map { "\($0.name) \(Int($0.percent.rounded())) percent used" }.joined(separator: ", "))

        if menuOpen { pendingBuild = true; return }        // don't swap the menu out from under you while it's open

        let m = NSMenu()
        m.delegate = self
        add(m, AccountView(store.account))
        if case .ready(let u, _) = store.update {
            let up = NSMenuItem(title: "", action: #selector(applyUpdateAction), keyEquivalent: ""); up.target = self
            up.attributedTitle = NSAttributedString(string: "⟳  Restart to update – v\(u.version)", attributes: [.foregroundColor: claudeOrange, .font: NSFont.boldSystemFont(ofSize: 13)])
            m.addItem(up)
        } else if case .available(let u) = store.update {
            let up = NSMenuItem(title: "", action: store.installing ? nil : #selector(openUpdate), keyEquivalent: ""); up.target = self
            up.attributedTitle = NSAttributedString(string: store.installing ? "⬇︎  \(store.downloadOnly ? "Downloading" : "Updating to") v\(u.version)… \(Int((store.installProgress * 100).rounded()))%" : "⬆︎  Update available – v\(u.version)",
                                                    attributes: [.foregroundColor: store.installing ? NSColor.secondaryLabelColor : claudeOrange, .font: NSFont.boldSystemFont(ofSize: 13)])
            m.addItem(up)
        }
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
        if store.stale { add(m, RowView(left: "Couldn’t reach Anthropic – showing the last reading", leftBold: false, size: 10, tint: .secondaryLabelColor)) }
        if settings.chatgptEnabled && !store.chatgpt.isFree {
            m.addItem(.separator())
            header(m, store.chatgpt.planName)
            if store.chatgpt.limits.isEmpty {
                add(m, RowView(left: store.chatgpt.error ?? "Loading ChatGPT limits…", leftBold: false, size: 11, tint: .secondaryLabelColor))
            } else {
                for l in store.chatgpt.limits { add(m, UsageBarView(l)) }
                if let e = store.chatgpt.error { add(m, RowView(left: e, leftBold: false, size: 10, tint: .secondaryLabelColor)) }
            }
        }
        m.addItem(.separator())
        block(m, "Today", s.today)
        add(m, RowView(left: "\(plural(s.messagesToday, "response")) today", leftBold: false, size: 11, tint: .secondaryLabelColor))
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
        let st = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","); st.target = self; m.addItem(st)
        let cs = NSMenuItem(title: "Copy Usage Summary", action: #selector(copySummaryAction), keyEquivalent: "c"); cs.target = self; m.addItem(cs)
        let r = NSMenuItem(title: "Refresh", action: #selector(refreshAction), keyEquivalent: "r"); r.target = self; m.addItem(r)
        let cu = NSMenuItem(title: "Check for Updates…", action: #selector(checkUpdatesAction), keyEquivalent: ""); cu.target = self; m.addItem(cu)
        let gh = NSMenuItem(title: "GitHub Repository", action: #selector(openRepo), keyEquivalent: ""); gh.target = self; m.addItem(gh)
        let rb = NSMenuItem(title: "Report a Bug…", action: #selector(reportBug), keyEquivalent: ""); rb.target = self; m.addItem(rb)
        let ab = NSMenuItem(title: "About Claude Usage", action: #selector(showAbout), keyEquivalent: ""); ab.target = self; m.addItem(ab)
        m.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = m
    }

    func menuWillOpen(_ menu: NSMenu) { menuOpen = true }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false; if pendingBuild { pendingBuild = false; build(store.snapshot) } }

    // MARK: screenshot tour (development aid: `--tour` cycles tabs × appearances and writes /tmp/cub_tour.txt)

    func startTour() {
        Settings.persist = false
        App.notificationsEnabled = false
        App.isTour = true
        if let v = Dev.env("CUB_FAKE_PROGRESS").flatMap(Double.init) {      // dev aid: freeze the UI mid-download (CUB_FAKE_NOINSTALL=1 for the download-only flavour)
            store.update = .available(UpdateInfo(version: "9.9.9", notes: ["A new feature, described in one sentence."]))
            store.installing = true; store.installProgress = v; store.installMessage = "Downloading version 9.9.9…"
            if Dev.env("CUB_FAKE_NOINSTALL") != nil { store.downloadOnly = true; store.canInstall = false }
        } else if Dev.env("CUB_FAKE_NOINSTALL") != nil {                      // dev aid: the 'can't replace itself' About pane
            store.update = .available(UpdateInfo(version: "9.9.9", notes: ["A new feature, described in one sentence."])); store.canInstall = false
        }
        if Dev.env("CUB_FAKE_READY") != nil { store.update = .ready(UpdateInfo(version: "9.9.9", notes: ["A new feature, described in one sentence.", "A fix, described in one sentence."]), URL(fileURLWithPath: "/tmp")) }   // dev aid: preview the restart banner
        showDashboard(.overview)
        checkForUpdates(manual: true)
        refresh()
        var steps: [(AppearanceMode, DashTab, AccentTheme)] = []
        for a in [AppearanceMode.dark, .light] { for t in DashTab.allCases { steps.append((a, t, .claude)) } }
        for t in [DashTab.overview, .reports, .usage, .settings] { steps.append((.oled, t, .claude)) }
        if let n = CommandLine.arguments.first(where: { $0.hasPrefix("--steps=") }).flatMap({ Int($0.dropFirst(8)) }) { steps = Array(steps.prefix(n)) }
        var i = 0
        func finish() { try? "done".write(toFile: "/tmp/cub_tour.txt", atomically: true, encoding: .utf8); DispatchQueue.main.asyncAfter(deadline: .now() + 1) { exit(0) } }
        // Full-height renders of the long pages (a normal window only shows the top), captured from outside by the tour script.
        func tall(_ idx: Int = 0) {
            let shots: [(AppearanceMode, String)] = [(.dark, "about"), (.light, "about")]
            guard idx < shots.count else { finish(); return }
            let (mode, name) = shots[idx]
            settings.appearance = mode
            let w = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 1020, height: 3700), styleMask: [.borderless], backing: .buffered, defer: false)
            store.settingsCategory = SettingsCategory(rawValue: Dev.env("CUB_TALL_CAT") ?? "") ?? .about    // dev aid: pick the settings pane to render
            let pageName = Dev.env("CUB_TALL_PAGE") ?? ""      // dev aid: overview | reports | insights | (settings)
            let page: AnyView = pageName == "overview" ? AnyView(OverviewView(store: store)) : (pageName == "reports" ? AnyView(ReportsView(store: store))
                : (pageName == "insights" ? AnyView(InsightsView(store: store)) : AnyView(SettingsPage(store: store, settings: settings))))
            w.contentView = NSHostingView(rootView: page.frame(width: 1020, height: 3700).background(settings.isOLED ? Color.black : Color(nsColor: .windowBackgroundColor)))
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
            if t == .settings { store.settingsCategory = a == .dark ? .menuBar : (a == .light ? .menuBar : .notifications) }
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

if CommandLine.arguments.contains("--selftest") { exit(runSelfTests()) }

if CommandLine.arguments.contains("--refresh-pricing") {      // dev aid: fetches pricing.json now and reports what was applied
    Pricing.refreshIfStale(force: true)
    print("cached:", FileManager.default.fileExists(atPath: Pricing.cacheURL.path), "models:", Pricing.table.count, "opus-5-5 input:", Pricing.forModel("claude-opus-5-5")?.input ?? -1)
    exit(0)
}

if Dev.flag("--download-update") {
    // Dev aid: runs the download-only flow (verified installer saved to Downloads) and exits.
    guard case .available(let info) = Updater.check() else { print("no update available"); exit(0) }
    let r = Updater.downloadOnly(info, progress: { print("…", $0) }, fraction: { _ in })
    print(r.file.map { "saved \($0.path)" } ?? "FAILED: \(r.error ?? "?")"); exit(r.file == nil ? 1 : 0)
}

if Dev.flag("--install-update") {
    // Dev aid: runs the whole download -> build -> install flow into CUB_INSTALL_DEST (never the installed app) and exits.
    guard case .available(let info) = Updater.check() else { print("no update available"); exit(0) }
    let dest = URL(fileURLWithPath: Dev.env("CUB_INSTALL_DEST") ?? "/tmp/ClaudeUsageUpdateTest.app")
    var lastShown = -1
    if let err = Updater.install(info, dest: dest, relaunch: false, progress: { print("…", $0) }, fraction: { f in let pct = Int(f * 100); if pct / 10 != lastShown / 10 { print("   progress \(pct)%"); lastShown = pct } }) { print("FAILED:", err); exit(1) }
    print("hand-off started for", info.version, "->", dest.path)
    exit(0)
}

if CommandLine.arguments.contains("--check-update") {
    // Dev aid: prints what the update check finds (use CUB_PRETEND_VERSION=0.1.0 to pretend to be an older install).
    print("installed:", Updater.installed)
    switch Updater.check() {
    case .available(let u): print("AVAILABLE", u.version); u.notes.prefix(4).forEach { print("  -", $0) }
    case .upToDate: print("UP TO DATE")
    case .failed(let m): print("FAILED:", m)
    default: break
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
