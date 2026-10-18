import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Light, editorial and restrained: near-black ink on warm-grey paper, hairlines instead
/// of boxes, and a single accent kept for the moment two paths cross.
enum Theme {
    static let paper = Color(hex: 0xF4F4F2)
    static let surface = Color.white
    static let ink = Color(hex: 0x121212)
    static let ink2 = Color(hex: 0x5E5E5B)
    static let ink3 = Color(hex: 0x6A6A66)
    static let mute = Color(hex: 0x8A8984)
    static let rule = Color(hex: 0xE2E1DC)
    static let ruleSoft = Color(hex: 0xECEBE7)
    static let strong = Color(hex: 0xCFCEC8)
    static let wash = Color(hex: 0xECEBE7)
    static let accent = Color(hex: 0xE5481B)

    static let gutter: CGFloat = 24
    static let radius: CGFloat = 20
}

/// Schibsted Grotesk for headlines, Geist for text, Geist Mono for data (coordinates, dates, counts).
enum TPFont {
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .custom(FontRegistry.display, size: size).weight(weight)
    }

    static func body(_ size: CGFloat = 16, weight: Font.Weight = .regular) -> Font {
        .custom(FontRegistry.body, size: size).weight(weight)
    }

    static func mono(_ size: CGFloat = 11, weight: Font.Weight = .regular) -> Font {
        .custom(FontRegistry.mono, size: size).weight(weight)
    }
}
