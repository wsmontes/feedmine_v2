// Visual tokens ported from the v1 design system (DesignTokens / CircadianEngine), resolved as
// compile-time constants so no view body computes palettes, fonts or layout at scroll time.
// v1 lessons kept: warm paper page, accent bar per card, serif headlines, hairline strokes.
// v1 costs dropped: per-period palette recomputation, card shadows, geometry-reader-sized media.
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum FeedDesign {
    // MARK: Spacing and shape (v1 mid-period values: padding 14–22, gap 10–18, radius 10–16)
    public static let cardSpacing: CGFloat = 14
    public static let cardPadding: CGFloat = 16
    public static let cardRadius: CGFloat = 14
    public static let thumbnailSide: CGFloat = 88
    public static let thumbnailRadius: CGFloat = 10
    public static let accentBarWidth: CGFloat = 3
    /// Constant room under the last card for the work badge, so the badge never moves content.
    public static let badgeClearance: CGFloat = 56

    // MARK: Color
    /// v1 warm paper (#FAF8F5) in light; near-black in dark (v1 was light-locked).
    public static let page = dynamic(light: 0xFAF8F5, dark: 0x0E0E10)
    public static let surface = dynamic(light: 0xFFFFFF, dark: 0x1C1C1E)
    public static let hairline = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.07, darkAlpha: 0.10)
    public static let placeholder = dynamic(light: 0xEFEAE3, dark: 0x2A2A2D)
    /// v1 Warm Earth accent (#FF7A45 afternoon value) used for app tint.
    public static let accent = Color(hex: 0xE8663C)

    /// v1 category palette (tech, news, science, design, culture). A source keeps one color for life.
    static let sourcePalette: [Color] = [0x5B7FA5, 0xB8685C, 0x6B9E7A, 0x8B7BA8, 0xC4854A].map { Color(hex: $0) }

    /// Stable color for a source name: FNV-1a over UTF-8 (String.hashValue is seeded per process).
    public static func sourceColor(_ name: String?) -> Color {
        guard let name, !name.isEmpty else { return .secondary }
        var hash: UInt32 = 2_166_136_261
        for byte in name.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return sourcePalette[Int(hash % UInt32(sourcePalette.count))]
    }

    // MARK: Type (v1 used Georgia for card titles; New York via .serif keeps Dynamic Type)
    static func title(_ layout: PresentationCardLayoutStyle) -> Font {
        switch layout {
        case .hero: return .system(.title3, design: .serif).weight(.semibold)
        case .thumbnail: return .system(.headline, design: .serif)
        case .textOnly: return .system(.title2, design: .serif).weight(.semibold)
        }
    }
    static let kicker = Font.caption.weight(.semibold)
    static let summary = Font.subheadline
    static let meta = Font.caption

    private static func dynamic(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgb: dark, alpha: darkAlpha) : UIColor(rgb: light, alpha: lightAlpha)
        })
        #elseif canImport(AppKit)
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(rgb: dark, alpha: darkAlpha) : NSColor(rgb: light, alpha: lightAlpha)
        })
        #else
        return Color(hex: light)
        #endif
    }
}

/// Layout family used only for typography choices.
enum PresentationCardLayoutStyle { case hero, thumbnail, textOnly }

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(rgb: UInt32, alpha: Double) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
    }
}
#elseif canImport(AppKit)
private extension NSColor {
    convenience init(rgb: UInt32, alpha: Double) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
    }
}
#endif
