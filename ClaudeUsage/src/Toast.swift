import AppKit

/// An on-screen banner with the app icon. Used when macOS notifications are blocked, so alerts are never silently lost.
final class Toast {
    private static var panels: [NSPanel] = []

    static func show(_ title: String, _ body: String, important: Bool = false, onClick: @escaping () -> Void = {}) {
        DispatchQueue.main.async {
            guard let screen = NSScreen.main else { return }
            let w: CGFloat = 390, h: CGFloat = 86
            let f = screen.visibleFrame
            let y = f.maxY - h - 12 - CGFloat(panels.count) * (h + 8)
            let panel = NSPanel(contentRect: NSRect(x: f.maxX - w - 14, y: y, width: w, height: h),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .statusBar; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.isReleasedWhenClosed = false
            let view = ToastView(frame: NSRect(x: 0, y: 0, width: w, height: h), title: title, body: body, important: important)
            view.onClick = { onClick(); dismiss(panel) }
            panel.contentView = view
            panels.append(panel)
            panel.alphaValue = 0; panel.orderFrontRegardless()
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: "\(title). \(body)", .priority: important ? NSAccessibilityPriorityLevel.high.rawValue : NSAccessibilityPriorityLevel.medium.rawValue])
            NSAnimationContext.runAnimationGroup { $0.duration = 0.25; panel.animator().alphaValue = 1 }
            if !important { DispatchQueue.main.asyncAfter(deadline: .now() + 7) { dismiss(panel) } }     // important banners stay until clicked
        }
    }

    static func dismiss(_ p: NSPanel) {
        guard panels.contains(where: { $0 === p }) else { return }
        panels.removeAll { $0 === p }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; p.animator().alphaValue = 0 }, completionHandler: { p.orderOut(nil) })
    }
}

final class ToastView: NSVisualEffectView {
    var onClick: () -> Void = {}

    init(frame: NSRect, title: String, body: String, important: Bool = false) {
        super.init(frame: frame)
        material = .hudWindow; blendingMode = .behindWindow; state = .active
        wantsLayer = true; layer?.cornerRadius = 18; layer?.masksToBounds = true
        if important { layer?.borderWidth = 2; layer?.borderColor = alertRed.cgColor }
        let icon = NSImageView(frame: NSRect(x: 16, y: (frame.height - 54) / 2, width: 54, height: 54))
        icon.image = NSApp.applicationIconImage; icon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(icon)
        let t = NSTextField(labelWithString: title)
        t.font = .boldSystemFont(ofSize: 14); t.textColor = .labelColor; t.lineBreakMode = .byTruncatingTail
        t.frame = NSRect(x: 82, y: frame.height - 34, width: frame.width - 98 - (important ? 82 : 0), height: 20)
        addSubview(t)
        if important {
            let tag = NSTextField(labelWithString: "IMPORTANT")
            tag.font = .boldSystemFont(ofSize: 10); tag.textColor = alertRed; tag.alignment = .right
            tag.frame = NSRect(x: frame.width - 100, y: frame.height - 31, width: 84, height: 14); addSubview(tag)
        }
        setAccessibilityLabel("\(important ? "Important: " : "")\(title). \(body)")
        let b = NSTextField(wrappingLabelWithString: body)
        b.font = .systemFont(ofSize: 12.5); b.textColor = .secondaryLabelColor; b.maximumNumberOfLines = 2
        b.frame = NSRect(x: 82, y: 12, width: frame.width - 98, height: 38)
        addSubview(b)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseDown(with event: NSEvent) { onClick() }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityPerformPress() -> Bool { onClick(); return true }
}
