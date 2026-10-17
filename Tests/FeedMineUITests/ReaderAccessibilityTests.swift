// File: ReaderAccessibilityTests.swift
// Module: FeedMineUITests
// Owns: the F-UI-4/F-UI-5 policy — the frozen V1 ruler, the Dynamic Type reference each role scales
//       against, and the source-level pins that keep fixed point sizes out of card text.
// Does not own: rendering. A resolved point size at accessibility categories needs a running app;
//              that is stated in the hand-off, not claimed here.

import SwiftUI
import XCTest

@testable import FeedMineUI

final class ReaderAccessibilityTests: XCTestCase {

    // MARK: - F-UI-4: the ruler did not move

    /// V1's sizes are the product's ruler. A Dynamic Type fix must add scaling, never change these.
    func testFrozenRulerIsIntact() {
        let expected: [ReaderTypeScale: [ReaderFontRole: CGFloat]] = [
            .small: [.cardTitle: 14, .cardBody: 12, .cardMeta: 11, .cardSummary: 13],
            .medium: [.cardTitle: 17, .cardBody: 13, .cardMeta: 11, .cardSummary: 13],
            .large: [.cardTitle: 20, .cardBody: 15, .cardMeta: 11, .cardSummary: 13],
        ]
        for (scale, roles) in expected {
            for (role, size) in roles {
                XCTAssertEqual(
                    scale.size(for: role), size,
                    "\(scale.rawValue)/\(role.rawValue) moved off V1's ruler")
            }
        }
    }

    /// Every role carries a text style, and it is the one the card text was designed against.
    func testEveryRoleDeclaresADynamicTypeReference() {
        let expected: [ReaderFontRole: Font.TextStyle] = [
            .cardTitle: .headline,
            .cardBody: .callout,
            .cardMeta: .caption2,
            .cardSummary: .footnote,
        ]
        for role in ReaderFontRole.allCases {
            XCTAssertEqual(
                role.textStyle, expected[role],
                "\(role.rawValue) lost its Dynamic Type reference")
        }
    }

    /// The explicit-size entry exists for every role at every scale: it is what the resolver calls.
    /// (`@ScaledMetric` resolves the size at render time; this pins that the ruler feeds it.)
    func testResolverEntryCoversEveryRoleAndScale() {
        let standard = ReaderAppearance.standard
        for scale in ReaderTypeScale.allCases {
            let appearance = ReaderAppearance(
                period: standard.period, paletteFamily: standard.paletteFamily,
                fontStyle: standard.fontStyle, typeScale: scale)
            for role in ReaderFontRole.allCases {
                _ = appearance.font(role, size: scale.size(for: role))
            }
        }
    }

    /// The refactor must not change what renders at the reader's default text size: the role entry and the
    /// explicit-size entry are the same font when the size is the ruler's.
    func testExplicitSizeEntryMatchesTheRoleEntryAtTheRuler() {
        let standard = ReaderAppearance.standard
        for style in ReaderFontStyle.allCases {
            for scale in ReaderTypeScale.allCases {
                let appearance = ReaderAppearance(
                    period: standard.period, paletteFamily: standard.paletteFamily,
                    fontStyle: style, typeScale: scale)
                for role in ReaderFontRole.allCases {
                    XCTAssertEqual(
                        appearance.font(role, size: scale.size(for: role)),
                        appearance.font(role),
                        "\(style.rawValue)/\(scale.rawValue)/\(role.rawValue) changed the default rendering")
                }
            }
        }
    }

    // MARK: - F-UI-4: regression pins

    /// The exact expressions the audit found must not come back. Icons keep fixed sizes; card *text*
    /// does not.
    func testCardTextNoLongerUsesFixedPointSizes() throws {
        let cardView = try source("Sources/FeedMineUI/Cards/FeedItemCardView.swift")
        let rowView = try source("Sources/FeedMineUI/Cards/FeedItemRowView.swift")

        XCTAssertFalse(cardView.contains(".font(.system(size: 11))"), "compact card summary went back to a fixed size")
        XCTAssertFalse(rowView.contains(".font(.system(size: 12))"), "row summary went back to a fixed size")
        XCTAssertFalse(cardView.contains(".font(appearance.font("), "card text bypasses the Dynamic Type resolver")
        XCTAssertFalse(rowView.contains(".font(appearance.font("), "row text bypasses the Dynamic Type resolver")

        XCTAssertTrue(cardView.contains(".readerFont("), "card text must resolve through readerFont")
        XCTAssertTrue(rowView.contains(".readerFont("), "row text must resolve through readerFont")
    }

    // MARK: - F-UI-5: tap target

    func testMinimumTapTargetIsTheHIGValue() {
        XCTAssertGreaterThanOrEqual(
            ReaderAccessibilityMetrics.minimumTapTarget, 44,
            "a control a finger must hit is at least 44×44 pt")
    }

    func testRegionExpansionControlUsesTheMinimumTapTarget() throws {
        let controls = try source("Sources/FeedMineUI/Onboarding/ReaderDiscoveryControls.swift")
        XCTAssertTrue(
            controls.contains("ReaderAccessibilityMetrics.minimumTapTarget"),
            "the language-region chevron went back to a glyph-sized target")
        XCTAssertTrue(controls.contains(".contentShape(Rectangle())"), "the enlarged target must accept hit testing")
    }

    // MARK: - Source access

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/FeedMineUITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }
}
