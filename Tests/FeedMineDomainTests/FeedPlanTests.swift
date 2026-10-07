//
// File: FeedPlanTests.swift
// Module: FeedMineDomainTests
//
// Responsibility:
//   Verify opaque version ordering and explicit context/revision preservation.
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

final class FeedPlanTests: XCTestCase {
    func testVersionValuesCompareByRawUnsignedValue() {
        XCTAssertLessThan(PolicyVersion(rawValue: 0), PolicyVersion(rawValue: UInt64.max))
        XCTAssertEqual(PolicyVersion(rawValue: 7), PolicyVersion(rawValue: 7))
        XCTAssertFalse(PolicyVersion(rawValue: 7) < PolicyVersion(rawValue: 7))
        XCTAssertGreaterThan(CatalogGeneration(rawValue: 9), CatalogGeneration(rawValue: 8))
        XCTAssertEqual(CatalogGeneration(rawValue: 0), CatalogGeneration(rawValue: 0))
        XCTAssertFalse(CatalogGeneration(rawValue: 0) < CatalogGeneration(rawValue: 0))
        XCTAssertLessThan(SelectionSchemaVersion(rawValue: 4), SelectionSchemaVersion(rawValue: 5))
        XCTAssertEqual(SelectionSchemaVersion(rawValue: UInt64.max), SelectionSchemaVersion(rawValue: UInt64.max))
        XCTAssertFalse(SelectionSchemaVersion(rawValue: 5) < SelectionSchemaVersion(rawValue: 4))
    }

    func testEditorialRevisionRoundTripPreservesDistinctPolicyComponents() throws {
        let revision = EditorialRevision(id: EditorialRevisionID(), contextKey: FeedContext(request: .main).key, catalogGeneration: CatalogGeneration(rawValue: 1), userSelectionVersion: PolicyVersion(rawValue: 2), eligibilityPolicyVersion: PolicyVersion(rawValue: 3), scoringPolicyVersion: PolicyVersion(rawValue: 4), sequencingPolicyVersion: PolicyVersion(rawValue: 5), exposurePolicyVersion: PolicyVersion(rawValue: 6), selectionSchemaVersion: SelectionSchemaVersion(rawValue: 8))
        let decoded = try JSONDecoder().decode(EditorialRevision.self, from: JSONEncoder().encode(revision))
        XCTAssertEqual(decoded.id, revision.id)
        XCTAssertEqual(decoded.catalogGeneration.rawValue, 1)
        XCTAssertEqual(decoded.userSelectionVersion.rawValue, 2)
        XCTAssertEqual(decoded.eligibilityPolicyVersion.rawValue, 3)
        XCTAssertEqual(decoded.scoringPolicyVersion.rawValue, 4)
        XCTAssertEqual(decoded.sequencingPolicyVersion.rawValue, 5)
        XCTAssertEqual(decoded.exposurePolicyVersion.rawValue, 6)
        XCTAssertEqual(decoded.contextKey, FeedContext(request: .main).key)
        XCTAssertEqual(decoded.selectionSchemaVersion.rawValue, 8)
    }

    func testFeedPlanPreservesExactlyContextAndEditorialRevision() throws {
        let context = FeedContext(request: .source(SourceID()))
        let revision = EditorialRevision(id: EditorialRevisionID(), contextKey: context.key, catalogGeneration: CatalogGeneration(rawValue: 11), userSelectionVersion: PolicyVersion(rawValue: 12), eligibilityPolicyVersion: PolicyVersion(rawValue: 13), scoringPolicyVersion: PolicyVersion(rawValue: 14), sequencingPolicyVersion: PolicyVersion(rawValue: 15), exposurePolicyVersion: PolicyVersion(rawValue: 16), selectionSchemaVersion: SelectionSchemaVersion(rawValue: 18))
        let plan = try XCTUnwrap(FeedPlan(context: context, revision: revision))
        XCTAssertEqual(plan.context, context)
        XCTAssertEqual(plan.revision, revision)
        let decoded = try JSONDecoder().decode(FeedPlan.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(decoded.context, context)
        XCTAssertEqual(decoded.revision, revision)
        XCTAssertNil(FeedPlan(context: FeedContext(request: .main), revision: revision))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as? [String: Any])
        var revisionObject = try XCTUnwrap(object["revision"] as? [String: Any])
        revisionObject["contextKey"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ContextKey(request: .main)))
        object["revision"] = revisionObject
        XCTAssertThrowsError(try JSONDecoder().decode(FeedPlan.self, from: JSONSerialization.data(withJSONObject: object)))
    }
}
