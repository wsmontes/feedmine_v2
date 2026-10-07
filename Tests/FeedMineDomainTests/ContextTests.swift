//
// File: ContextTests.swift
// Module: FeedMineDomainTests
//
// Responsibility:
//   Verify context identity, request values and original search queries.
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

final class ContextTests: XCTestCase {
    func testMainContextCodableRoundTrip() throws {
        let context = FeedContext(key: ContextKey(), request: .main)
        XCTAssertEqual(try JSONDecoder().decode(FeedContext.self, from: JSONEncoder().encode(context)), context)
    }

    func testSourceContextPreservesSourceID() throws {
        let sourceID = SourceID()
        let context = FeedContext(key: ContextKey(), request: .source(sourceID))
        let decoded = try JSONDecoder().decode(FeedContext.self, from: JSONEncoder().encode(context))
        XCTAssertEqual(decoded.request, .source(sourceID))
        XCTAssertEqual(decoded.key, context.key)
    }

    func testSearchPreservesOriginalQuery() throws {
        let search = try XCTUnwrap(SearchContext(query: "  Swift  \n"))
        XCTAssertEqual(search.query, "  Swift  \n")
        let context = FeedContext(key: ContextKey(), request: .search(search))
        XCTAssertEqual(try JSONDecoder().decode(FeedContext.self, from: JSONEncoder().encode(context)), context)
    }

    func testSearchRejectsEmptyOrWhitespaceOnlyQueries() {
        for query in ["", " ", "\t\n\r", "\u{00A0}\u{2003}"] {
            XCTAssertNil(SearchContext(query: query))
        }
    }

    func testSearchDecodingEnforcesNonWhitespaceInvariant() {
        let data = Data("{\"query\":\"  \\n\"}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(SearchContext.self, from: data))
    }

    func testContextIdentityIsIndependentOfRequestMeaning() {
        let first = FeedContext(key: ContextKey(), request: .main)
        let second = FeedContext(key: ContextKey(), request: .main)
        XCTAssertEqual(first.request, second.request)
        XCTAssertNotEqual(first.key, second.key)
        XCTAssertNotEqual(first, second)
    }

    func testExplicitContextAndEditorialIDsPreserveRawUUID() throws {
        let raw = UUID()
        let key = ContextKey(rawValue: raw)
        let revisionID = EditorialRevisionID(rawValue: raw)
        XCTAssertEqual(key.rawValue, raw)
        XCTAssertEqual(key.description, raw.uuidString)
        XCTAssertEqual(revisionID.rawValue, raw)
        XCTAssertEqual(revisionID.description, raw.uuidString)
        XCTAssertEqual(try JSONDecoder().decode(EditorialRevisionID.self, from: JSONEncoder().encode(revisionID)), revisionID)
        // Nominally distinct IDs cannot substitute for each other even with the same UUID.
    }
}
