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
        let context = FeedContext(request: .main)
        XCTAssertEqual(try JSONDecoder().decode(FeedContext.self, from: JSONEncoder().encode(context)), context)
    }

    func testSourceContextPreservesSourceID() throws {
        let sourceID = SourceID()
        let context = FeedContext(request: .source(sourceID))
        let decoded = try JSONDecoder().decode(FeedContext.self, from: JSONEncoder().encode(context))
        XCTAssertEqual(decoded.request, .source(sourceID))
        XCTAssertEqual(decoded.key, context.key)
    }

    func testSearchPreservesOriginalQuery() throws {
        let search = try XCTUnwrap(SearchContext(query: "  Swift  \n"))
        XCTAssertEqual(search.query, "  Swift  \n")
        let context = FeedContext(request: .search(search))
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

    func testEquivalentMainRequestsHaveSameKey() {
        XCTAssertEqual(FeedContext(request: .main).key, FeedContext(request: .main).key)
    }

    func testSourceIdentityDeterminesLogicalKey() {
        let source = SourceID()
        let first = FeedContext(request: .source(source))
        XCTAssertEqual(first.key, FeedContext(request: .source(source)).key)
        XCTAssertNotEqual(first.key, FeedContext(request: .source(SourceID())).key)
        XCTAssertNotEqual(first.key, FeedContext(request: .main).key)
    }

    func testSearchKeyUsesOriginalQueryExactly() throws {
        let plain = try XCTUnwrap(SearchContext(query: "Swift"))
        let spaced = try XCTUnwrap(SearchContext(query: "  Swift  "))
        let first = FeedContext(request: .search(plain))
        XCTAssertEqual(first.key, FeedContext(request: .search(plain)).key)
        XCTAssertNotEqual(first.key, FeedContext(request: .search(spaced)).key)
        XCTAssertEqual(try JSONDecoder().decode(ContextKey.self, from: JSONEncoder().encode(first.key)), first.key)
    }
}
