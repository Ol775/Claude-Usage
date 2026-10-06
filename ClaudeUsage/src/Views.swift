import AppKit

let menuWidth: CGFloat = 340

final class ChartView: NSView {
    let values: [Int]; let title: String; let labels: [String]; let highlight: Int
    init(title: String, values: [Int], labels: [String], highlight: Int) {
        self.title = title; self.values = values; self.labels = labels; self.highlight = highlight
        super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 140))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ r: NSRect) {
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.secondaryLabelColor]
        let mx = max(values.max() ?? 0, 1)
        NSAttributedString(string: title, attributes: [.font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: claudeOrange]).draw(at: NSPoint(x: 16, y: 118))
        let peak = NSAttributedString(string: "peak " + fmt(mx), attributes: small)
        peak.draw(at: NSPoint(x: bounds.width - 16 - peak.size().width, y: 119))
        let left: CGFloat = 16, bottom: CGFloat = 26, top: CGFloat = 108
        let w = bounds.width - 2*left, n = CGFloat(values.count), gap: CGFloat = 2
        let bw = (w - gap*(n-1)) / n
        for (i, v) in values.enumerated() {
            let h = v == 0 ? 1 : max(2, CGFloat(v)/CGFloat(mx) * (top - bottom))
            let rect = NSRect(x: left + CGFloat(i)*(bw+gap), y: bottom, width: bw, height: h)
            NSColor.labelColor.withAlphaComponent(0.10).setFill()
            NSBezierPath(roundedRect: NSRect(x: rect.minX, y: bottom, width: bw, height: top - bottom), xRadius: 2, yRadius: 2).fill()
            (i == highlight ? claudeOrange : claudeOrange.withAlphaComponent(0.7)).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        }
        for (i, t) in labels.enumerated() where !t.isEmpty {
            let a = NSAttributedString(string: t, attributes: small)
            let cx = left + CGFloat(i)*(bw+gap) + bw/2
            a.draw(at: NSPoint(x: min(max(left, cx - a.size().width/2), bounds.width - left - a.size().width), y: 8))
        }
    }
}

final class RowView: NSView {
    init(left: String, right: String = "", sub: String = "", leftBold: Bool = true, size: CGFloat = 13, tint: NSColor = .labelColor) {
        let h: CGFloat = sub.isEmpty ? 28 : 48
        super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: h))
        func label(_ t: String, _ f: NSFont, _ c: NSColor, _ a: NSTextAlignment) -> NSTextField {
            let l = NSTextField(labelWithString: t); l.font = f; l.textColor = c; l.alignment = a
            l.lineBreakMode = .byTruncatingTail; return l
        }
        let top: CGFloat = sub.isEmpty ? 5 : 26
        let l = label(left, leftBold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size), tint, .left)
        l.frame = NSRect(x: 16, y: top, width: menuWidth - 32 - (right.isEmpty ? 0 : 90), height: 17); addSubview(l)
        let r = label(right, .monospacedDigitSystemFont(ofSize: size, weight: leftBold ? .semibold : .regular), leftBold ? claudeOrange : .labelColor, .right)
        r.frame = NSRect(x: menuWidth - 16 - 90, y: top, width: 90, height: 17); addSubview(r)
        if !sub.isEmpty {
            let sl = label(sub, .systemFont(ofSize: 10.5), .secondaryLabelColor, .left)
            sl.frame = NSRect(x: 16, y: 7, width: menuWidth - 32, height: 14); addSubview(sl)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
}


final class AccountView: NSView {
    let account: Account
    init(_ a: Account) { account = a; super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 68)) }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ r: NSRect) {
        drawAvatar(in: NSRect(x: 16, y: 14, width: 40, height: 40), account: account)
        let title = account.loggedIn ? account.name : "Not signed in"
        NSAttributedString(string: title, attributes: [.font: NSFont.boldSystemFont(ofSize: 14), .foregroundColor: NSColor.labelColor]).draw(at: NSPoint(x: 66, y: 34))
        let sub = account.loggedIn ? [account.email, account.plan.isEmpty ? "" : "\(account.plan) plan"].filter { !$0.isEmpty }.joined(separator: " · ") : "Choose “Sign in with Claude…” below"
        NSAttributedString(string: sub, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]).draw(at: NSPoint(x: 66, y: 16))
        if account.loggedIn && !account.plan.isEmpty {
            let b = NSAttributedString(string: account.plan.uppercased(), attributes: [.font: NSFont.boldSystemFont(ofSize: 9), .foregroundColor: claudeOrange])
            let w = b.size().width + 14, rect = NSRect(x: menuWidth - 16 - w, y: 38, width: w, height: 17)
            claudeOrange.withAlphaComponent(0.18).setFill(); NSBezierPath(roundedRect: rect, xRadius: 8.5, yRadius: 8.5).fill()
            b.draw(at: NSPoint(x: rect.minX + 7, y: rect.minY + 3))
        }
    }
}


final class UsageBarView: NSView {
    let limit: Limit, forecast: String, hot: Bool
    init(_ limit: Limit, forecast: String = "", hot: Bool = false) {
        self.limit = limit; self.forecast = forecast; self.hot = hot
        super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: forecast.isEmpty ? 62 : 80))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ r: NSRect) {
        let dy: CGFloat = forecast.isEmpty ? 0 : 18
        let frac = min(max(limit.percent / 100, 0), 1)
        let color = limit.percent >= 95 ? alertRed : claudeOrange
        NSAttributedString(string: limit.name, attributes: [.font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]).draw(at: NSPoint(x: 16, y: 40 + dy))
        let a = NSAttributedString(string: "\(Int(limit.percent.rounded()))%", attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold), .foregroundColor: color])
        a.draw(at: NSPoint(x: menuWidth - 16 - a.size().width, y: 40 + dy))
        let track = NSRect(x: 16, y: 28 + dy, width: menuWidth - 32, height: 8)
        NSColor.labelColor.withAlphaComponent(0.12).setFill(); NSBezierPath(roundedRect: track, xRadius: 4, yRadius: 4).fill()
        if frac > 0 {
            var f = track; f.size.width = max(8, track.width * CGFloat(frac))
            color.setFill(); NSBezierPath(roundedRect: f, xRadius: 4, yRadius: 4).fill()
        }
        NSAttributedString(string: untilText(limit.resets), attributes: [.font: NSFont.systemFont(ofSize: 10.5), .foregroundColor: NSColor.secondaryLabelColor]).draw(at: NSPoint(x: 16, y: 9 + dy))
        if !forecast.isEmpty {
            NSAttributedString(string: forecast, attributes: [.font: NSFont.systemFont(ofSize: 10.5, weight: hot ? .semibold : .regular), .foregroundColor: hot ? alertRed : NSColor.secondaryLabelColor]).draw(at: NSPoint(x: 16, y: 8))
        }
    }
}

/// The menu bar icon: the custom image if one was bundled, otherwise the drawn bot in the accent colour.
func menuBarBotImage() -> NSImage {
    if let url = Bundle.main.url(forResource: "Bot", withExtension: "png"), let img = NSImage(contentsOf: url) {
        img.size = NSSize(width: 18, height: 18); return img
    }
    let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
        drawBot(in: rect.insetBy(dx: 0.5, dy: 0.5), body: claudeOrange, eyes: nil)
        return true
    }
    img.isTemplate = false
    img.accessibilityDescription = "Claude Usage"
    return img
}
