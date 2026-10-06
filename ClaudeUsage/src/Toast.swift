import AppKit

/// An on-screen banner with the app icon. Used when macOS notifications are blocked, so alerts are never silently lost.
final class Toast {
    private static var panels: [NSPanel] = []

    static func show(_ title: String, _ body: String, onClick: @escaping () -> Void = {}) {
        DispatchQueue.main.async {
            guard let screen = NSScreen.main else { return }
            let w: CGFloat = 390, h: CGFloat = 86
            let f = screen.visibleFrame
            let y = f.maxY - h - 12 - CGFloat(panels.count) * (h + 8)
            let panel = NSPanel(contentRect: NSRect(x: f.maxX - w - 14, y: y, width: w, height: h),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .statusBar; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.isReleasedWhenClosed = false
            let view = ToastView(frame: NSRect(x: 0, y: 0, width: w, height: h), title: title, body: body)
            view.onClick = { onClick(); dismiss(panel) }
            panel.contentView = view
            panels.append(panel)
            panel.alphaValue = 0; panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.25; panel.animator().alphaValue = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 7) { dismiss(panel) }
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

    init(frame: NSRect, title: String, body: String) {
        super.init(frame: frame)
        material = .hudWindow; blendingMode = .behindWindow; state = .active
        wantsLayer = true; layer?.cornerRadius = 18; layer?.masksToBounds = true
        let icon = NSImageView(frame: NSRect(x: 16, y: (frame.height - 54) / 2, width: 54, height: 54))
        icon.image = NSApp.applicationIconImage; icon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(icon)
        let t = NSTextField(labelWithString: title)
        t.font = .boldSystemFont(ofSize: 14); t.textColor = .labelColor; t.lineBreakMode = .byTruncatingTail
        t.frame = NSRect(x: 82, y: frame.height - 34, width: frame.width - 98, height: 20)
        addSubview(t)
        let b = NSTextField(wrappingLabelWithString: body)
        b.font = .systemFont(ofSize: 12.5); b.textColor = .secondaryLabelColor; b.maximumNumberOfLines = 2
        b.frame = NSRect(x: 82, y: 12, width: frame.width - 98, height: 38)
        addSubview(b)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseDown(with event: NSEvent) { onClick() }
}
