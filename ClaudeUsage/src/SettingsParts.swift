import SwiftUI
import Charts
import ServiceManagement

// MARK: - Settings (modelled on System Settings: a categories list on the left, grouped sections on the right)

enum SettingsCategory: String, CaseIterable, Identifiable {
    case account, general, appearance, menuBar, notifications, data, support, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .account: return "Account"
        case .general: return "General"
        case .appearance: return "Appearance"
        case .menuBar: return "Menu Bar"
        case .notifications: return "Notifications"
        case .data: return "Data & Export"
        case .support: return "Help & Legal"
        case .about: return "About"
        }
    }
    var icon: String {
        switch self {
        case .account: return "person.crop.circle.fill"
        case .general: return "gearshape.fill"
        case .appearance: return "paintbrush.fill"
        case .menuBar: return "menubar.rectangle"
        case .notifications: return "bell.badge.fill"
        case .data: return "square.and.arrow.up.fill"
        case .support: return "lifepreserver.fill"
        case .about: return "info.circle.fill"
        }
    }
    var tint: Color {
        switch self {
        case .account: return .blue
        case .general: return Color(white: 0.5)
        case .appearance: return .indigo
        case .menuBar: return .teal
        case .notifications: return .red
        case .data: return .green
        case .support: return .orange
        case .about: return Color(white: 0.45)
        }
    }
    var keywords: String {
        switch self {
        case .account: return "sign in sign out login profile photo avatar claude plan email"
        case .general: return "dock launch login refresh startup"
        case .appearance: return "theme dark light oled black colour color mode orange"
        case .menuBar: return "menu bar icon session weekly percent customise customize preset label tokens reset countdown"
        case .notifications: return "alert warn critical important time sensitive banner threshold quiet hours snooze night"
        case .data: return "export csv copy summary history retention keep delete import settings file backup"
        case .support: return "bug report issue feedback help support terms conditions legal disclaimer privacy licence license warranty"
        case .about: return "version build github source repository coffee donate tip support the developer update beta channel"
        }
    }
}

/// A rounded group of rows with an optional heading and footnote, like a System Settings section.
/// The translation of an English interface string (from `<language>.lproj/Localizable.strings`), or the English itself.
func L(_ s: String) -> String { NSLocalizedString(s, comment: "") }

struct SGroup<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let t = title { Text(L(t)).font(AppFont.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 8) }
            VStack(spacing: 0) { content() }.frame(maxWidth: .infinity).card()
            if let f = footer { Text(L(f)).font(AppFont.caption).foregroundStyle(.secondary).padding(.horizontal, 8).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

struct SRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L(title))
                if let s = subtitle { Text(L(s)).font(AppFont.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

struct SDivider: View {
    var body: some View { Divider().padding(.leading, 14) }
}


/// A segmented choice that is as wide as its labels (so a bigger font or text size never pushes it out of its card). If there still isn't
/// room, it turns into a drop-down menu instead.
struct SegmentedChoice<T: Hashable>: View {
    let options: [T]
    let label: (T) -> String
    @Binding var selection: T
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 2) {
                ForEach(options, id: \.self) { o in
                    Button { selection = o } label: {
                        Text(L(label(o))).font(AppFont.callout).lineLimit(1).fixedSize()
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .foregroundStyle(selection == o ? (scheme == .dark ? Color.black.opacity(0.85) : Color.white) : Color.primary)
                            .background(Capsule().fill(selection == o ? Color.brand : Color.clear))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == o ? .isSelected : [])
                }
            }
            .padding(2).background(Capsule().fill(Color.primary.opacity(0.08))).fixedSize()
            Picker(L(label(selection)), selection: $selection) { ForEach(options, id: \.self) { Text(L(label($0))).tag($0) } }
                .labelsHidden().frame(width: 150)
        }
    }
}
