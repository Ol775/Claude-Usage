import AppKit
import SwiftUI

// Screenshot regression tests. `--render-screens <dir>` draws the main screens (demo data only) to PNG files;
// adding `--compare <baselineDir>` checks them against saved images and exits non-zero if one has changed noticeably.
// Only runs in test copies (see Dev) and only with CUB_DEMO=1, so real account data can never end up in an image.

/// How two PNGs differ: both are cut into the same 68×100 grid of cells (about 30 px each on a full-size render), and each cell's average colour is compared.
/// `changedCells` counts cells that differ clearly, `mean` is the overall average difference (0...1).
/// A clock reading or an anti-aliased edge touches one or two cells; a missing card, a broken layout or wrong colours touch dozens.
struct ScreenDiff { var mean: Double; var changedCells: Int }

func screenDifference(_ a: Data, _ b: Data) -> ScreenDiff? {
    func grid(_ d: Data) -> (px: [UInt8], w: Int, h: Int)? {
        guard let rep = NSBitmapImageRep(data: d), let cg = rep.cgImage else { return nil }
        let w = 68, h = 100          // a fixed grid, so images of different pixel sizes (full-size renders vs smaller saved copies) compare
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (px, w, h)
    }
    guard let x = grid(a), let y = grid(b), x.w == y.w, x.h == y.h else { return nil }
    var total = 0, changed = 0
    for cell in 0..<(x.w * x.h) {
        var d = 0
        for c in 0..<3 { d += abs(Int(x.px[cell * 4 + c]) - Int(y.px[cell * 4 + c])) }
        total += d
        if Double(d) / (3 * 255) > 0.05 { changed += 1 }
    }
    return ScreenDiff(mean: Double(total) / Double(x.w * x.h * 3 * 255), changedCells: changed)
}

extension App {
    /// A screen passes if at most this many cells changed clearly and the overall difference is small (calibrated on repeat runs).
    static let screenMaxChangedCells = 20, screenMaxMean = 0.005

    func runScreenTests(out: URL, baselines: URL?) {
        guard Demo.enabled else { print("Refusing to render without CUB_DEMO=1 (demo data only)."); exit(2) }
        Settings.persist = false; App.notificationsEnabled = false; App.isTour = true
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        refresh()

        let screens: [(String, () -> AnyView)] = [
            ("overview", { AnyView(OverviewView(store: self.store)) }),
            ("reports", { AnyView(ReportsView(store: self.store)) }),
            ("insights", { AnyView(InsightsView(store: self.store)) }),
            ("usage", { AnyView(UsageView(store: self.store)) }),
            ("settings", { self.store.settingsCategory = .about; return AnyView(SettingsPage(store: self.store, settings: self.settings)) }),
        ]
        let modes: [(String, AppearanceMode)] = [("dark", .dark), ("light", .light)]
        let jobs = modes.flatMap { m in screens.map { (name: "\($0.0)-\(m.0)", mode: m.1, view: $0.1) } }
        var failures = 0, compared = 0, skipped = 0

        func step(_ i: Int) {
            guard i < jobs.count else {
                print(failures == 0 ? "OK – \(jobs.count) screens rendered, \(compared) compared, \(skipped) without a baseline" : "\(failures) screen(s) changed")
                exit(failures == 0 ? 0 : 1)
            }
            let job = jobs[i]
            settings.appearance = job.mode
            let w = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 1020, height: 1500), styleMask: [.borderless], backing: .buffered, defer: false)
            let host = NSHostingView(rootView: job.view().frame(width: 1020, height: 1500).background(Color(nsColor: .windowBackgroundColor)))
            w.contentView = host
            w.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                host.layoutSubtreeIfNeeded()
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { print("FAIL \(job.name): couldn't render"); failures += 1; w.orderOut(nil); step(i + 1); return }
                host.cacheDisplay(in: host.bounds, to: rep)
                let png = rep.representation(using: .png, properties: [:]) ?? Data()
                try? png.write(to: out.appendingPathComponent("\(job.name).png"))
                if let base = baselines {
                    if let want = try? Data(contentsOf: base.appendingPathComponent("\(job.name).png")) {
                        compared += 1
                        let d = screenDifference(png, want)
                        if let d = d, d.changedCells <= App.screenMaxChangedCells, d.mean <= App.screenMaxMean { print("ok   \(job.name) (\(d.changedCells) cells changed, mean \(String(format: "%.4f", d.mean)))") }
                        else { failures += 1; print("FAIL \(job.name): \(d.map { "\($0.changedCells) cells changed, mean \(String(format: "%.4f", $0.mean))" } ?? "sizes differ") (limits: \(App.screenMaxChangedCells) cells, mean \(App.screenMaxMean))") }
                    } else { skipped += 1; print("skip \(job.name): no baseline") }
                }
                w.orderOut(nil)
                step(i + 1)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { step(0) }
    }
}
