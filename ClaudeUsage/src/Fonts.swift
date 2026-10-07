import SwiftUI
import CoreText

/// Fonts for the dashboard windows. Every `.font(...)` in the SwiftUI screens goes through here so the typeface (including the bundled
/// OpenDyslexic) and the text size you pick in Settings → Appearance apply everywhere. The menu bar and its drop-down menu keep the
/// system font so they stay compact.
enum AppFont {
    static var choice: FontChoice { Settings.shared.fontChoice }
    static var scale: CGFloat { Settings.shared.textSize.scale }

    /// Makes the bundled OpenDyslexic available to this app (it is not installed system-wide). Safe to call more than once.
    static func registerBundled() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for f in files where f.pathExtension == "otf" || f.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(f as CFURL, .process, nil)
        }
    }

    private static func isHeavy(_ w: Font.Weight) -> Bool { w == .semibold || w == .bold || w == .heavy || w == .black }

    static func system(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        make(choice, size: size * scale, weight: weight, design: design)
    }

    /// A specific typeface at an exact size (used for the previews in Settings, which show each choice in its own font).
    static func make(_ choice: FontChoice, size s: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        switch choice {
        case .system: return .system(size: s, weight: weight, design: design)
        case .rounded: return .system(size: s, weight: weight, design: .rounded)
        case .serif: return .system(size: s, weight: weight, design: .serif)
        case .mono: return .system(size: s, weight: weight, design: .monospaced)
        case .dyslexic: return .custom(isHeavy(weight) ? "OpenDyslexic-Bold" : "OpenDyslexic-Regular", fixedSize: s)
        }
    }

    // macOS text styles, as sizes
    static var largeTitle: Font { system(size: 26) }
    static var title: Font { system(size: 22) }
    static var title2: Font { system(size: 17) }
    static var title3: Font { system(size: 15) }
    static var headline: Font { system(size: 13, weight: .semibold) }
    static var body: Font { system(size: 13) }
    static var callout: Font { system(size: 12) }
    static var subheadline: Font { system(size: 11) }
    static var footnote: Font { system(size: 10) }
    static var caption: Font { system(size: 10) }
    static var caption2: Font { system(size: 10) }
}
