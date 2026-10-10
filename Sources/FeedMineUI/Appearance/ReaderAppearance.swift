// File: ReaderAppearance.swift
// Module: FeedMineUI
// Owns: the reader's visual system, copied from V1 (`Services/DesignTokens.swift` and the pure
//       values of `Services/CircadianEngine.swift`).
// Does not own: which content is shown, when the appearance changes, or any clock.
//
// V1 decided its palette and typography from the clock (`CircadianEngine` singleton with an hourly
// timer). The transfer keeps the *values* and the reader's explicit preference, and never rebuilds a
// presentation because a clock advanced: `ReaderAppearance` is an immutable value the host supplies.

import SwiftUI

/// Time-of-day palette period. Values copied from V1 `CircadianPeriod`.
public enum ReaderPeriod: String, CaseIterable, Hashable, Sendable {
    case dawn, morning, afternoon, evening, night

    public static func from(hour: Int) -> ReaderPeriod {
        switch hour {
        case 5..<8: .dawn
        case 8..<12: .morning
        case 12..<17: .afternoon
        case 17..<21: .evening
        default: .night
        }
    }

    /// San Francisco weight varies subtly by period (V1).
    public var fontWeight: Font.Weight {
        switch self {
        case .dawn, .night: .light
        case .morning, .evening: .regular
        case .afternoon: .medium
        }
    }

    /// Subtle letter-spacing drift, in points (V1).
    public var letterSpacing: CGFloat {
        switch self {
        case .dawn: 0.3
        case .morning: 0
        case .afternoon: -0.1
        case .evening: 0.1
        case .night: 0.5
        }
    }

    public var cardPadding: CGFloat {
        switch self {
        case .dawn: 16
        case .morning, .afternoon: 14
        case .evening: 18
        case .night: 22
        }
    }

    public var cardGap: CGFloat {
        switch self {
        case .dawn: 16
        case .morning: 12
        case .afternoon: 10
        case .evening: 14
        case .night: 18
        }
    }

    public var cardRadius: CGFloat {
        switch self {
        case .dawn, .morning, .evening: 14
        case .afternoon: 10
        case .night: 16
        }
    }
}

/// Palette families. Accent and page tint tables copied verbatim from V1 `PaletteFamily`.
public enum ReaderPaletteFamily: String, CaseIterable, Hashable, Sendable {
    case warmEarth, coolSky, botanical, lavenderHour, monochrome

    /// V1's accent table, kept as hex so the copied values are assertable and the `Color` derives
    /// from the same single source.
    public func accentHex(for period: ReaderPeriod) -> String {
        switch (self, period) {
        case (.warmEarth, .dawn): "#FFB238"
        case (.warmEarth, .morning): "#FF9A3C"
        case (.warmEarth, .afternoon): "#FF7A45"
        case (.warmEarth, .evening): "#E8483C"
        case (.warmEarth, .night): "#B8403A"
        case (.coolSky, .dawn): "#7BA4C4"
        case (.coolSky, .morning): "#5B8FAD"
        case (.coolSky, .afternoon): "#4A7C9B"
        case (.coolSky, .evening): "#3D5F80"
        case (.coolSky, .night): "#2C3E5A"
        case (.botanical, .dawn): "#7AAA7A"
        case (.botanical, .morning): "#5E9465"
        case (.botanical, .afternoon): "#4A7A4A"
        case (.botanical, .evening): "#3D5E3D"
        case (.botanical, .night): "#2E4A2E"
        case (.lavenderHour, .dawn): "#B8A4C8"
        case (.lavenderHour, .morning): "#9B82B5"
        case (.lavenderHour, .afternoon): "#7E5F9E"
        case (.lavenderHour, .evening): "#684C8A"
        case (.lavenderHour, .night): "#4A3570"
        case (.monochrome, .dawn): "#B0A89E"
        case (.monochrome, .morning): "#9E9690"
        case (.monochrome, .afternoon): "#8C8580"
        case (.monochrome, .evening): "#7A7370"
        case (.monochrome, .night): "#686260"
        }
    }

    public func accent(for period: ReaderPeriod) -> Color { Color(readerHex: accentHex(for: period)) }

    /// Page tint per period (over V1's base #FAF8F5).
    public func pageTintHex(for period: ReaderPeriod) -> String {
        switch period {
        case .dawn, .morning: "#FAF8F5"
        case .afternoon: "#F8F5F0"
        case .evening: "#F5F0E8"
        case .night: "#F0EBE4"
        }
    }

    public func pageTint(for period: ReaderPeriod) -> Color { Color(readerHex: pageTintHex(for: period)) }
}

/// Typography families. Values copied from V1 `FontStyle`.
public enum ReaderFontStyle: String, CaseIterable, Hashable, Sendable {
    case system, newYork, sfMono, georgia
}

/// Type roles. Sizes and weights copied from V1 `FontRole`.
public enum ReaderFontRole: String, CaseIterable, Hashable, Sendable {
    case cardTitle, cardBody, cardMeta, cardSummary

    public var defaultSize: CGFloat {
        switch self {
        case .cardTitle: 17
        case .cardBody: 14
        case .cardMeta: 11
        case .cardSummary: 13
        }
    }

    public var defaultWeight: Font.Weight {
        switch self {
        case .cardTitle: .semibold
        case .cardBody, .cardMeta: .regular
        case .cardSummary: .regular
        }
    }
}

/// The reader's text-size preference (V1 `fontSize`).
public enum ReaderTypeScale: String, CaseIterable, Hashable, Sendable {
    case small, medium, large

    /// V1's per-role overrides: title 14/17/20, body 12/13/15.
    public func size(for role: ReaderFontRole) -> CGFloat {
        switch (role, self) {
        case (.cardTitle, .small): 14
        case (.cardTitle, .medium): 17
        case (.cardTitle, .large): 20
        case (.cardBody, .small): 12
        case (.cardBody, .medium): 13
        case (.cardBody, .large): 15
        default: role.defaultSize
        }
    }
}

/// The immutable visual system one reader session renders with. Frozen when a presentation is
/// admitted: an appearance change is an explicit preference change by the host, never a timer.
public struct ReaderAppearance: Hashable, Sendable {
    public let period: ReaderPeriod
    public let paletteFamily: ReaderPaletteFamily
    public let fontStyle: ReaderFontStyle
    public let typeScale: ReaderTypeScale

    public init(period: ReaderPeriod, paletteFamily: ReaderPaletteFamily, fontStyle: ReaderFontStyle,
        typeScale: ReaderTypeScale) {
        self.period = period
        self.paletteFamily = paletteFamily
        self.fontStyle = fontStyle
        self.typeScale = typeScale
    }

    /// V1's defaults: circadian palette on, warm earth, system font, medium text size.
    public static let standard = ReaderAppearance(period: .morning, paletteFamily: .warmEarth,
        fontStyle: .system, typeScale: .medium)

    // MARK: - Palette
    public var accent: Color { paletteFamily.accent(for: period) }
    public var pageBackground: Color { paletteFamily.pageTint(for: period) }
    public var cardSurface: Color { accent.opacity(0.03) }
    public var cardBorder: Color { accent.opacity(0.06) }
    public var borderWidth: CGFloat { 0.5 }
    public var accentBarWidth: CGFloat { 3 }
    public var accentBarInset: CGFloat { 1 }
    public var separatorOpacity: Double { 0.06 }

    // MARK: - Metrics (V1 values)
    public var cardRadius: CGFloat { period.cardRadius }
    public var landscapeCardRadius: CGFloat { 12 }
    public var cardPadding: CGFloat { period.cardPadding }
    public var cardGap: CGFloat { period.cardGap }
    public var contentPadding: CGFloat { 12 }
    public var landscapeThumbnailSide: CGFloat { 90 }
    /// Compact-row thumbnail reference side (V1 `Measurement.compactThumbnailBase`).
    public var compactThumbnailSide: CGFloat { 88 }
    public var landscapeThumbnailRadius: CGFloat { 8 }
    public var heroAspectRatio: CGFloat { 16.0 / 9.0 }
    public var mediaRadius: CGFloat { 8 }
    public var mediaPlaceholder: Color { .primary.opacity(0.08) }
    public var readOpacity: Double { 0.92 }
    public var overlayBadgeSize: CGFloat { 36 }
    public var overlayBadgePadding: CGFloat { 12 }

    // MARK: - Typography
    public func font(_ role: ReaderFontRole) -> Font {
        let size = typeScale.size(for: role)
        let weight = role.defaultWeight
        switch fontStyle {
        case .system: return .system(size: size, weight: weight)
        case .newYork: return .custom("New York", size: size).weight(weight)
        case .sfMono: return .system(size: size, weight: weight, design: .monospaced)
        case .georgia: return .custom("Georgia", size: size).weight(weight)
        }
    }

    /// V1 applied the period's weight to card titles on top of the role's weight.
    public var titleWeight: Font.Weight { period.fontWeight }
    public var letterSpacing: CGFloat { period.letterSpacing }

    /// HIG tracking for a size (V1 `tracking(for:)`).
    public static func tracking(for size: CGFloat) -> CGFloat {
        switch size {
        case 34...: -1.05
        case 28..<34: -0.80
        case 22..<28: -0.50
        case 20..<22: -0.45
        case 17..<20: -0.43
        case 15..<17: -0.24
        case 13..<15: -0.08
        default: 0.12
        }
    }
}

extension Color {
    /// V1 `Color(hex:)`, kept for the copied palette tables.
    init(readerHex hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0)
    }
}
