//
//  Theme.swift
//  Stash
//
//  Light, flat, editorial. One accent colour, hairline rules, big type.
//

import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum Theme {
    static let paper = Color(hex: 0xF4F3F0)
    static let surface = Color.white
    static let ink = Color(hex: 0x111111)
    static let muted = Color(hex: 0x8C8C88)
    static let hairline = Color(hex: 0xE3E2DE)
    static let accent = Color(hex: 0x4B3BFF)
    static let night = Color(hex: 0x1B1B1D)
    static let nightRaised = Color(hex: 0x2A2A2D)
    static let nightMuted = Color(hex: 0x8E8E93)
    static let positive = Color(hex: 0x1F9D55)
    static let warning = Color(hex: 0xD9480F)
    static let radius: CGFloat = 12

    /// Flat, muted cover colours for games without artwork
    static let coverColors: [Color] = [
        Color(hex: 0xE8553D), Color(hex: 0x2F6FDE), Color(hex: 0x1F9D55),
        Color(hex: 0xE3A51A), Color(hex: 0x7A5AF5), Color(hex: 0x222222)
    ]
}

// MARK: - Type

extension Font {
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy) }
    static let eyebrow = Font.system(size: 10.5, weight: .semibold)
}

/// Small uppercase label used above sections and values
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.muted
    init(_ text: String, color: Color = Theme.muted) {
        self.text = text
        self.color = color
    }
    var body: some View {
        Text(text.uppercased()).font(.eyebrow).tracking(1.1).foregroundStyle(color)
    }
}

struct Hairline: View {
    var color: Color = Theme.hairline
    var body: some View { Rectangle().fill(color).frame(height: 1) }
}

extension View {
    /// White card with a hairline border
    func card(radius: CGFloat = Theme.radius) -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.hairline))
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.accent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 36)
            .background(color.opacity(!isEnabled ? 0.35 : configuration.isPressed ? 0.8 : 1),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var dark = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(dark ? Color.white : Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(
                (dark ? Theme.nightRaised : Theme.surface).opacity(configuration.isPressed ? 0.7 : 1),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(dark ? Color.clear : Theme.hairline))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
    }
}

struct TextLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(configuration.isPressed ? Theme.ink : Theme.muted)
            .contentShape(Rectangle())
    }
}

// MARK: - Covers

/// The user's artwork, or a flat colour block set like a book cover
struct CoverArt: View {
    let game: Game
    let image: NSImage?
    var radius: CGFloat = Theme.radius
    var titleSize: CGFloat = 20

    static func color(for game: Game) -> Color {
        if let known = game.knownGame { return known.color }
        let seed = game.name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Theme.coverColors[seed % Theme.coverColors.count]
    }

    /// Exe icons are tiny; only real artwork fills the cover
    private var isArtwork: Bool { (image?.size.width ?? 0) >= 300 }

    var body: some View {
        Color.clear
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                if let image, isArtwork {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack(alignment: .topLeading) {
                        Self.color(for: game)
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text(game.platform.title.uppercased())
                                    .font(.system(size: max(8, titleSize * 0.42), weight: .bold))
                                    .tracking(1)
                                Spacer()
                                if let image {
                                    Image(nsImage: image).resizable().interpolation(.high)
                                        .frame(width: titleSize * 1.3, height: titleSize * 1.3)
                                }
                            }
                            Spacer()
                            Rectangle().fill(.white.opacity(0.6)).frame(height: 1).padding(.bottom, titleSize * 0.4)
                            Text(game.name)
                                .font(.system(size: titleSize, weight: .heavy))
                                .tracking(-0.4)
                                .lineLimit(4)
                                .minimumScaleFactor(0.6)
                        }
                        .foregroundStyle(.white)
                        .padding(titleSize * 0.7)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct CoverThumbnail: View {
    let game: Game
    let image: NSImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(CoverArt.color(for: game))
            .overlay {
                if let image, image.size.width >= 300 {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Text(String(game.name.prefix(1)).uppercased())
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .frame(width: 22, height: 28)
    }
}

// MARK: - Rows

/// Settings row: title and detail on the left, switch on the right
struct SettingToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden().tint(Theme.accent)
        }
        .padding(.vertical, 11)
    }
}

/// Underlined text tabs, like an editorial section index
struct TextTabs<Tab: Hashable>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    let title: (Tab) -> String

    var body: some View {
        HStack(spacing: 22) {
            ForEach(tabs, id: \.self) { tab in
                Button { selection = tab } label: {
                    VStack(spacing: 6) {
                        Text(title(tab))
                            .font(.system(size: 13, weight: selection == tab ? .semibold : .regular))
                            .foregroundStyle(selection == tab ? Theme.ink : Theme.muted)
                        Rectangle().fill(selection == tab ? Theme.ink : .clear).frame(height: 2)
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
