import Foundation
import XCTest
import FeedMineUI

/// UI-READABILITY-01 — the a-priori contrast guard for the reader's palette.
///
/// The hole this closes: `FeedMineAppTests/CompositionTests`
/// (`testU1TokenPaletteAdaptsToAppearanceWithoutAnOverlay`) resolves only `FeedDesignTokens.Palette`
/// and **never** `ReaderAppearance.pageBackground`, so the palette the reader actually paints had no
/// ratio assertion anywhere — not in unit tests, not in the app suite. That is how a 1.19:1 pairing
/// shipped: `pageTintHex` is pinned to a light value for every period and every surface painting it
/// pairs it with `.foregroundStyle(.primary)`, which under a dark device appearance resolved to white.
/// This test resolves the tables `ReaderAppearance.pageBackground` and `.cardSurface` are built from
/// (`ReaderPaletteFamily.pageTintHex(for:)`, `accentHex(for:)`) and requires WCAG 2.x AA against the
/// ink a light presentation gives `.primary` — no simulator, no pixels, no build of the app.
///
/// The other half of the fix (the presentation declaration itself, `.preferredColorScheme(.light)` on
/// the window and `overrideUserInterfaceStyle = .light` on the reader's controller) is covered on the
/// rendered surfaces by `FeedMineUITests/AppearanceLegibilityUITests`, which reads the real pixels in
/// a dark environment. The two are complementary: that test fails if the pin is removed; this one
/// fails if the palette ever pairs a light page with an ink that cannot be read on it.
final class ReaderPaletteContrastTests: XCTestCase {
    /// Every pairing below is normal-size text — a 17 pt semibold card title, a 13–15 pt body or an
    /// 11 pt meta line. None is the WCAG "large text" exception (18 pt regular / 14 pt bold), so the
    /// bar is AA for normal text, 4.5:1; no pairing in this file is allowed the 3:1 bar.
    private static let normalTextMinimum = 4.5

    /// `.primary` under the light presentation the 1.0 declares. `UIColor.label` resolves to opaque
    /// black in a light trait collection, and the shipped measurement quotes exactly that label
    /// (`docs/evidence/2026-10-17-ui-readability-01/measurement.md`).
    private static let inkHex = "#000000"

    /// The ink the defect shipped: `.primary` under a dark device appearance, i.e. white.
    private static let retiredInkHex = "#FFFFFF"

    /// `ReaderAppearance.cardSurface` is `accent.opacity(0.03)`; the surface is that accent laid over
    /// the page tint, so the ratio is computed on the composite, not on either colour alone.
    private static let cardSurfaceAccentOpacity = 0.03

    // MARK: - Guard

    /// For every period × every palette family, the ink over the page tint and over the card surface
    /// clears AA for normal text. This is the assertion that would have failed before the 1.19:1
    /// pairing ever reached a simulator.
    func testEveryPeriodAndFamilyClearsAAWithTheInkALightPresentationGivesPrimary() {
        for period in ReaderPeriod.allCases {
            for family in ReaderPaletteFamily.allCases {
                let pair = colors(period: period, family: family)
                let ink = Self.rgb(Self.inkHex)
                let pageRatio = Self.contrast(pair.page, ink)
                let cardRatio = Self.contrast(pair.card, ink)
                print(Self.line(period: period, family: family, pair: pair,
                    inkHex: Self.inkHex, pageRatio: pageRatio, cardRatio: cardRatio))
                XCTAssertGreaterThanOrEqual(pageRatio, Self.normalTextMinimum,
                    "\(family.rawValue)/\(period.rawValue): .primary (\(Self.inkHex)) over page tint "
                        + "\(pair.pageHex) is \(Self.ratio(pageRatio)):1")
                XCTAssertGreaterThanOrEqual(cardRatio, Self.normalTextMinimum,
                    "\(family.rawValue)/\(period.rawValue): .primary (\(Self.inkHex)) over cardSurface "
                        + "(accent \(pair.accentHex) at 3 % over \(pair.pageHex)) is "
                        + "\(Self.ratio(cardRatio)):1")
            }
        }
    }

    /// The guard's own failing case, kept in the suite so the passing test above cannot be vacuous: the
    /// retired white ink must be *rejected* by the same computation and the same bar, and the night page
    /// must reproduce the defect's measured 1.19:1. A contrast function that returned a constant would
    /// fail here even if it passed the guard.
    func testTheGuardRejectsTheRetiredWhiteInkPairing() {
        var lowest = Double.greatestFiniteMagnitude
        for period in ReaderPeriod.allCases {
            for family in ReaderPaletteFamily.allCases {
                let pair = colors(period: period, family: family)
                let white = Self.rgb(Self.retiredInkHex)
                let pageRatio = Self.contrast(pair.page, white)
                let cardRatio = Self.contrast(pair.card, white)
                print(Self.line(period: period, family: family, pair: pair,
                    inkHex: Self.retiredInkHex, pageRatio: pageRatio, cardRatio: cardRatio))
                XCTAssertLessThan(pageRatio, Self.normalTextMinimum,
                    "\(family.rawValue)/\(period.rawValue): the retired white ink over page tint "
                        + "\(pair.pageHex) must fail AA, measured \(Self.ratio(pageRatio)):1")
                XCTAssertLessThan(cardRatio, Self.normalTextMinimum,
                    "\(family.rawValue)/\(period.rawValue): the retired white ink over cardSurface "
                        + "must fail AA, measured \(Self.ratio(cardRatio)):1")
                if period == .night, family == .warmEarth {
                    XCTAssertEqual(pageRatio, 1.19, accuracy: 0.005,
                        "the shipped defect measured 1.19:1 — white over #F0EBE4")
                }
                lowest = min(lowest, pageRatio)
            }
        }
        XCTAssertLessThan(lowest, 1.2, "the retired pairing is nowhere near AA")
    }

    // MARK: - The tables the appearance draws from

    /// Builds the two surfaces `ReaderAppearance` paints, through the appearance value and the hex
    /// tables it exposes, so a change to either name is a compile error here, not a silent drift.
    private struct Pairing {
        let pageHex: String
        let accentHex: String
        let page: RGB
        let card: RGB
    }

    private func colors(period: ReaderPeriod, family: ReaderPaletteFamily) -> Pairing {
        let appearance = ReaderAppearance(period: period, paletteFamily: family,
            fontStyle: .system, typeScale: .medium)
        let pageHex = appearance.paletteFamily.pageTintHex(for: appearance.period)
        let accentHex = appearance.paletteFamily.accentHex(for: appearance.period)
        let page = Self.rgb(pageHex)
        let card = Self.composite(Self.rgb(accentHex), over: page,
            alpha: Self.cardSurfaceAccentOpacity)
        return Pairing(pageHex: pageHex, accentHex: accentHex, page: page, card: card)
    }

    // MARK: - WCAG 2.x

    /// One sRGB colour, components in 0…1 — the space WCAG relative luminance is defined in.
    private struct RGB {
        let r: Double
        let g: Double
        let b: Double
    }

    /// Same parse as `Color(readerHex:)` in production: the palette's hex strings are the single source
    /// of the tokens, so the ratio is computed from the exact bytes the app draws.
    private static func rgb(_ hex: String) -> RGB {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        return RGB(r: Double((value >> 16) & 0xFF) / 255.0,
            g: Double((value >> 8) & 0xFF) / 255.0,
            b: Double(value & 0xFF) / 255.0)
    }

    /// Source-over compositing in sRGB, the space `Color.opacity` blends in: the card surface is the
    /// accent at 3 % laid over the page tint.
    private static func composite(_ top: RGB, over bottom: RGB, alpha: Double) -> RGB {
        RGB(r: alpha * top.r + (1 - alpha) * bottom.r,
            g: alpha * top.g + (1 - alpha) * bottom.g,
            b: alpha * top.b + (1 - alpha) * bottom.b)
    }

    /// WCAG 2.x relative luminance (threshold 0.03928, exponent 2.4).
    private static func relativeLuminance(_ color: RGB) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
    }

    /// WCAG 2.x contrast ratio, ordered light over dark.
    private static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let first = relativeLuminance(a)
        let second = relativeLuminance(b)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private static func ratio(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func line(period: ReaderPeriod, family: ReaderPaletteFamily, pair: Pairing,
        inkHex: String, pageRatio: Double, cardRatio: Double) -> String {
        String(format: "UI-READABILITY-01 %-9@ %-12@ ink %@ | page %@ %@:1 | cardSurface(accent %@) %@:1",
            period.rawValue, family.rawValue, inkHex, pair.pageHex, ratio(pageRatio),
            pair.accentHex, ratio(cardRatio))
    }
}
