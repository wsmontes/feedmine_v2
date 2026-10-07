//
// File: FeedIntentTests.swift
// Module: FeedMineDomainTests
//
// Responsibility:
//   Verify feed-level semantic intentions preserve their payloads.
//
// Owns:
//   Focused context, revision or intent contract tests.
//
// Does not own:
//   Future service behaviors, mocks or generic test frameworks.
//
// Allowed dependencies:
//   XCTest, FeedMineDomain and Foundation encoding/test values.
//
// Architectural invariants:
//   INV-08, INV-10, INV-12; explicit values never execute services.
//
// Planned public surface:
//   Focused context, revision or intent contract tests. No execution API is authorized in this phase.
//
// Status:
//   Phase 1B context and editorial revision value implementation.
//

import Foundation
import XCTest
import FeedMineDomain

final class FeedIntentTests: XCTestCase {
    func testChangeContextCodableRoundTrip() throws {
        let context = FeedContext(key: ContextKey(), request: .main)
        let intent = FeedIntent.changeContext(context)
        XCTAssertEqual(try JSONDecoder().decode(FeedIntent.self, from: JSONEncoder().encode(intent)), .changeContext(context))
    }

    func testRefreshCodableRoundTrip() throws {
        let intent = FeedIntent.refresh
        XCTAssertEqual(try JSONDecoder().decode(FeedIntent.self, from: JSONEncoder().encode(intent)), .refresh)
    }
}
