//
// File: IdentifierTests.swift
// Module: FeedMineDomainTests
//
// Responsibility:
//   Verify nominal identity generation and stable Codable values.
//
// Owns:
//   Focused value-model invariant verification for Phase 1A.
//
// Does not own:
//   Mocks, generic test helpers or verification of future modules.
//
// Allowed dependencies:
//   FeedMineDomain, XCTest and Foundation test values/encoding.
//
// Architectural invariants:
//   INV-12, INV-13; canonical facts stay independent of protocol implementation.
//
// Planned public surface:
//   Phase 1A domain tests only; no production API.
//
// Status:
//   Phase 1A canonical domain invariant tests.
//

import Foundation
import XCTest
import FeedMineDomain

final class IdentifierTests: XCTestCase {
    // SourceID and ProviderID are nominally distinct: assigning one to the other
    // does not compile. Compile-failing code is intentionally not included.
    func testIndependentIDsAreDifferent() {
        XCTAssertNotEqual(SourceID(), SourceID())
    }

    func testExplicitRawValueAndDescription() {
        let raw = UUID()
        let id = SourceID(rawValue: raw)
        XCTAssertEqual(id.rawValue, raw)
        XCTAssertEqual(id.description, raw.uuidString)
        XCTAssertEqual(id, SourceID(rawValue: raw))
    }

    func testIdentifierCodableRoundTrips() throws {
        let source = SourceID()
        let record = OriginRecordID()
        XCTAssertEqual(try JSONDecoder().decode(SourceID.self, from: JSONEncoder().encode(source)), source)
        XCTAssertEqual(try JSONDecoder().decode(OriginRecordID.self, from: JSONEncoder().encode(record)), record)
    }
}
