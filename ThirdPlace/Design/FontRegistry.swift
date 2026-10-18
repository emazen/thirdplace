import CoreText
import UIKit

/// Registers the bundled variable fonts (Schibsted Grotesk, Geist, Geist Mono; SIL Open Font
/// License, see Resources/Fonts) so SwiftUI can use them by family name.
enum FontRegistry {
    static let display = "Schibsted Grotesk"
    static let body = "Geist"
    static let mono = "Geist Mono"

    static func registerAll() {
        let urls = (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
        for url in Set(urls) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        styleNavigationBars()
    }

    /// Navigation titles don't pick up SwiftUI fonts, so set them through UIKit appearance.
    private static func styleNavigationBars() {
        let ink = UIColor(red: 0x12 / 255, green: 0x12 / 255, blue: 0x12 / 255, alpha: 1)
        let paper = UIColor(red: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF2 / 255, alpha: 1)
        let large = UIFont(name: "SchibstedGrotesk-Regular_SemiBold", size: 34) ?? .systemFont(ofSize: 34, weight: .semibold)
        let inline = UIFont(name: "Geist-SemiBold", size: 17) ?? .systemFont(ofSize: 17, weight: .semibold)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = paper
        appearance.shadowColor = .clear
        appearance.largeTitleTextAttributes = [.font: large, .foregroundColor: ink, .kern: -1.0]
        appearance.titleTextAttributes = [.font: inline, .foregroundColor: ink]
        if let body = UIFont(name: "Geist-Regular", size: 17) {
            appearance.buttonAppearance.normal.titleTextAttributes = [.font: body]
            appearance.backButtonAppearance.normal.titleTextAttributes = [.font: body]
        }
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = ink
    }
}
