//
// File: FeedNativeScrollTraceTests.swift
// Module: FeedMineAppTests
//
// Responsibility:
//   Hold the `feed-window-proof` trace to the contract its readers already use: the field names, their order,
//   the `;` separators, and measurements a locale-blind parser can read.
//
// Owns:
//   The line's notation. Nothing else.
//
// Does not own:
//   The scroll machinery, the diagnosis journey, or any rendering decision. The line is evidence.
//
// Status:
//   F-UI-1: the line used to be a `LocalizedStringKey` (`Text("…activeLayoutStep=\(value)…")`), so SwiftUI
//   rendered each `CGFloat` with the `\.locale` in effect — `0,000000` on pt-BR, `0.000000` on en-CA, from
//   the same code. `ArticleReadingDiagnosisUITests` reads those fields with `Double(step)`, and
//   `Double("0,000000")` is `nil`, which its parser turns into its own `999` sentinel: a healthy scroll
//   failed the stability gate. The repair serialises the numbers before SwiftUI sees them and draws the line
//   verbatim; these cases fail if a measurement ever goes back through a localised interpolation.
//

import XCTest
import Foundation
import FeedMineDomain
@testable import FeedMineUI

@MainActor
final class FeedNativeScrollTraceTests: XCTestCase {
    /// The measurements that were floats: these are the ones a locale could rewrite.
    private static let floatFields = ["residual", "visualResidual", "activeLayoutStep"]
    /// Every integer field. `installs` is a triple and `ids` a comma-joined list; both are checked apart.
    private static let integerFields = [
        "corrections", "measured", "activeWrites", "activeWindows", "activeLayoutSteps",
        "deferredWindows", "surfaceEvals", "geom", "probes", "guards", "cards", "emits",
        "submits", "geomEvents", "phaseEvents", "scopeReject",
    ]
    /// The whole line, in order. This is the parser's contract, not a detail of this test.
    private static let fields = [
        "ids", "corrections", "residual", "measured", "visualResidual", "activeWrites",
        "activeWindows", "activeLayoutSteps", "activeLayoutStep", "deferredWindows", "surfaceEvals",
        "geom", "probes", "guards", "cards", "emits", "submits", "geomEvents", "phaseEvents",
        "scopeReject", "installs",
    ]

    private static func line() -> String {
        FeedNativeWindowProof.traceLine(
            ids: [PublicationCardID(rawValue: UUID()), PublicationCardID(rawValue: UUID())],
            access: FeedNativeScrollOffset(),
            deferredWindows: 0)
    }

    private static func value(of field: String, in line: String) -> String? {
        let prefix = field + "="
        return line.components(separatedBy: ";")
            .first { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
    }

    /// The interface locale of the run is irrelevant to the line — that is the whole repair. The two locales
    /// that disagreed on the same code are exercised here as the *formatter* under them: pt-BR is what wrote
    /// `0,000000`, en-CA is what wrote `0.000000`, and the trace must be the second one in both.
    func testTraceKeepsNumbersReadableWhenTheInterfaceLocaleIsPortuguese() throws {
        // Recorded, not assumed: this line says which locale the run was actually under.
        print("TRACE_INTERFACE_LOCALE=\(Locale.current.identifier)")
        let portuguese = Locale(identifier: "pt_BR")
        let english = Locale(identifier: "en_CA")
        XCTAssertEqual(String(format: "%.6f", locale: portuguese, 0.0), "0,000000",
            "precondition: pt-BR is the interface locale that changed the separator")
        XCTAssertEqual(String(format: "%.6f", locale: english, 0.0), "0.000000",
            "precondition: en-CA is the locale under which the same trace passed")
        XCTAssertNil(Double("0,000000"),
            "precondition: the diagnosis parser reads the pt-BR rendering as nil, i.e. as its 999 sentinel")
        XCTAssertEqual(Double("0.000000"), 0,
            "precondition: the diagnosis parser reads the en-CA rendering as the measurement")

        let line = Self.line()
        for field in Self.floatFields {
            let value = try XCTUnwrap(Self.value(of: field, in: line), "\(field) must be in the line")
            XCTAssertNotNil(value.range(of: "^[-0-9.]+$", options: .regularExpression),
                "\(field)=\(value) must be dot-decimal: the reader is Double(...), which is locale-blind")
            XCTAssertNil(value.range(of: ","),
                "\(field)=\(value) carries a decimal comma: that is the pt-BR rendering the repair removes")
            XCTAssertNotNil(Double(value), "\(field)=\(value) must parse with Double(...)")
        }
        // The serialiser the line uses, against the rendering the same value used to get from SwiftUI.
        XCTAssertEqual(FeedNativeWindowProof.number(0.5), "0.500000")
        XCTAssertEqual(String(format: "%.6f", locale: portuguese, 0.5), "0,500000",
            "the localized rendering of the very same value: what the line must never contain")
        XCTAssertNotEqual(FeedNativeWindowProof.number(0.5), String(format: "%.6f", locale: portuguese, 0.5))
        XCTAssertEqual(FeedNativeWindowProof.number(0.5), String(format: "%.6f", locale: english, 0.5))
    }

    /// A measurement keeps six decimals and a dot, so magnitudes below one — the ones the stability gate
    /// compares — are stated instead of rounded away.
    func testMeasurementsSerialiseAsSixDecimalsWithADot() {
        XCTAssertEqual(FeedNativeWindowProof.number(0), "0.000000")
        XCTAssertEqual(FeedNativeWindowProof.number(0.5), "0.500000")
        XCTAssertEqual(FeedNativeWindowProof.number(-0.25), "-0.250000")
        XCTAssertEqual(FeedNativeWindowProof.number(12.3456789), "12.345679")
        XCTAssertEqual(Double(FeedNativeWindowProof.number(12.3456789)), 12.345679)
    }

    /// The names, their order and the separators, read the way the diagnosis test reads them: split on `;`,
    /// match on a `field=` prefix.
    func testTraceLineKeepsTheFieldNamesOrderAndSeparators() throws {
        let line = Self.line()
        XCTAssertEqual(line.components(separatedBy: ";").map { String($0.prefix { $0 != "=" }) },
            Self.fields, "the field names and their order are the parsers' contract")

        for field in Self.integerFields {
            let value = try XCTUnwrap(Self.value(of: field, in: line), "\(field) must be in the line")
            XCTAssertNotNil(value.range(of: "^-?[0-9]+$", options: .regularExpression),
                "\(field)=\(value) must be an integer the existing Int(...) readers accept")
            XCTAssertNotNil(Int(value), "\(field)=\(value) must parse with Int(...)")
        }

        let installs = try XCTUnwrap(Self.value(of: "installs", in: line))
        XCTAssertNotNil(installs.range(of: "^-?[0-9]+/-?[0-9]+/-?[0-9]+$", options: .regularExpression),
            "installs=\(installs) must stay the three counters of FeedFlowCounters")

        let identifiers = try XCTUnwrap(Self.value(of: "ids", in: line))
        XCTAssertEqual(identifiers.components(separatedBy: ",").count, 2,
            "the ids are the window, comma-joined: the diagnosis test drops them and compares the rest")
        for identifier in identifiers.components(separatedBy: ",") {
            XCTAssertNotNil(UUID(uuidString: identifier), "\(identifier) must be a UUID string")
        }
    }
}
