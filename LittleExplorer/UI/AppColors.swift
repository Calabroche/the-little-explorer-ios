import SwiftUI

/// Mirrors the web app's `tokens.ts` palette. The web uses CSS custom
/// properties that swap based on the `data-dark` attribute on `<html>`;
/// here we use SwiftUI's `Color(light:dark:)` so each token resolves to
/// the right value based on the active color scheme.
enum AppColors {
    // Editorial cream paper / dark counterpart.
    static let cream       = Color(light: "F5EFE6", dark: "1A1816")
    static let creamDark   = Color(light: "EDE5D8", dark: "242220")
    static let creamBorder = Color(light: "E0D5C2", dark: "3A352F")
    static let surface     = Color(light: "FFFCF6", dark: "201E1C")

    // Ink (typography).
    static let ink       = Color(light: "2A2723", dark: "F0EBE2")
    static let inkMid    = Color(light: "5C544A", dark: "B5AFA5")
    static let inkLight  = Color(light: "8A8175", dark: "7A7268")

    // Accents.
    static let terra      = Color(light: "C4602A", dark: "D77441")
    static let terraLight = Color(light: "F3E0CC", dark: "3A2A1F")
    static let green      = Color(light: "6B9A5E", dark: "8AB87B")
    static let greenLight = Color(light: "DCE9D4", dark: "2A3A24")
    static let blue       = Color(light: "4A7A9C", dark: "6B9DBF")

    // Heatmap intensity gradient (mirrors web's intensityColor()).
    static let heat0 = creamDark
    static let heat1 = Color(hex: "F3B585")
    static let heat2 = Color(hex: "E08A4D")
    static let heat3 = Color(hex: "C4602A")
    static let heat4 = Color(hex: "9B3A1A")
}

extension Color {
    /// Hex string → Color. Accepts `RRGGBB` (no `#` prefix).
    init(hex: String) {
        let s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }

    /// Light / dark pair, both as hex strings.
    init(light: String, dark: String) {
        self = Color(UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            var v: UInt64 = 0
            Scanner(string: hex).scanHexInt64(&v)
            let r = CGFloat((v >> 16) & 0xFF) / 255
            let g = CGFloat((v >> 8) & 0xFF) / 255
            let b = CGFloat(v & 0xFF) / 255
            return UIColor(red: r, green: g, blue: b, alpha: 1)
        })
    }
}
