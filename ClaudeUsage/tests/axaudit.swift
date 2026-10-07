import AppKit
// Accessibility audit (dev tool): lists buttons, switches, fields and images in a running copy that VoiceOver could not name.
// Build: swiftc -O tests/axaudit.swift -o build/axaudit. The terminal needs Accessibility permission (System Settings → Privacy & Security).
// Run against a re-identified test copy started with CUB_DEMO=1, never the real app: build/axaudit <pid> [button to press …]
// e.g. build/axaudit 1234 Settings Notifications   (presses Settings, then Notifications, then audits the window).
let pid = pid_t(CommandLine.arguments[1])!
guard AXIsProcessTrusted() else { print("NOT TRUSTED: grant Accessibility to the terminal"); exit(2) }
let app = AXUIElementCreateApplication(pid)
func attr(_ e: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil }
var total = 0, unnamed: [String] = [], roles: [String: Int] = [:]
func walk(_ e: AXUIElement, _ path: String, _ depth: Int) {
    guard depth < 40 else { return }
    let role = attr(e, kAXRoleAttribute) as? String ?? "?"
    roles[role, default: 0] += 1; total += 1
    let name = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].compactMap { attr(e, $0) as? String }.first { !$0.isEmpty }
    let interactive = ["AXButton", "AXCheckBox", "AXPopUpButton", "AXTextField", "AXSlider", "AXRadioButton", "AXIncrementor", "AXImage", "AXMenuButton", "AXColorWell", "AXSwitch", "AXToggle"]
    var titled = name != nil
    if !titled, let tui = attr(e, kAXTitleUIElementAttribute) { titled = (attr(tui as! AXUIElement, kAXValueAttribute) as? String).map { !$0.isEmpty } ?? false }
    if interactive.contains(role) && !titled && !path.hasSuffix("AXScrollBar") && !path.hasSuffix("AXWindow") { unnamed.append("\(path)/\(role)") }
    for c in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { walk(c, path + "/" + role, depth + 1) }
}
func find(_ e: AXUIElement, _ label: String, _ d: Int = 0) -> AXUIElement? {
    if d > 40 { return nil }
    let names = [kAXTitleAttribute, kAXDescriptionAttribute].compactMap { attr(e, $0) as? String }
    if (attr(e, kAXRoleAttribute) as? String) == "AXButton", names.contains(label) { return e }
    for c in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { if let f = find(c, label, d + 1) { return f } }
    return nil
}
for label in CommandLine.arguments.dropFirst(2) {
    var hit: AXUIElement?
    for w in (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] { if let f = find(w, label) { hit = f; break } }
    if let h = hit { AXUIElementPerformAction(h, kAXPressAction as CFString); usleep(1_200_000) } else { print("no button:", label) }
}
for w in (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] { walk(w, "", 0) }
print("elements:", total, "unnamed controls:", unnamed.count)
for u in unnamed.prefix(60) { print("  ", u.split(separator: "/").suffix(4).joined(separator: "/")) }
