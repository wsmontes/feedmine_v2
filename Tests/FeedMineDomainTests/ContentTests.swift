//
// File: ContentTests.swift
// Module: FeedMineDomainTests
//
// Responsibility:
//   Verify canonical content facts, optional timestamps and relation invariants.
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

final class ContentTests: XCTestCase {
    func testOriginRecordCodablePreservesIdentityRevisionAvailabilityAndTimes() throws {
        let identity = ExternalIdentity(connectorKind: .syndication, namespace: "objects", value: "Object A", role: .object)
        let record = OriginRecord(id: OriginRecordID(), connectorKind: .syndication, externalObjectIdentity: identity, currentRevisionID: OriginRevisionID(), availability: .revoked, firstObservedAt: Date(timeIntervalSince1970: 100), lastObservedAt: Date(timeIntervalSince1970: 200))
        let decoded = try JSONDecoder().decode(OriginRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded, record)
    }

    func testRevisionKeepsMissingEditorialValuesMissing() throws {
        let observed = Date(timeIntervalSince1970: 300)
        let revision = OriginRevision(id: OriginRevisionID(), originRecordID: OriginRecordID(), externalVersionIdentity: nil, headline: nil, summary: nil, bodyText: "Text", authoredAt: nil, modifiedAt: nil, observedAt: observed, language: nil, primaryLink: nil, searchProjection: nil, providerID: nil)
        let decoded = try JSONDecoder().decode(OriginRevision.self, from: JSONEncoder().encode(revision))
        XCTAssertEqual(decoded, revision)
        XCTAssertNil(decoded.headline)
        XCTAssertNil(decoded.authoredAt)
        XCTAssertNil(decoded.primaryLink)
        XCTAssertNil(decoded.providerID)
        XCTAssertEqual(decoded.observedAt, observed)
    }

    func testRevisionPreservesDistinctTimestampMeaningsAndProvider() throws {
        let authored = Date(timeIntervalSince1970: 10)
        let modified = Date(timeIntervalSince1970: 20)
        let observed = Date(timeIntervalSince1970: 30)
        let version = ExternalIdentity(connectorKind: .syndication, namespace: "versions", value: "  Version A  ", role: .version)
        let revision = OriginRevision(id: OriginRevisionID(), originRecordID: OriginRecordID(), externalVersionIdentity: version, headline: "Title", summary: "Summary", bodyText: "Body", authoredAt: authored, modifiedAt: modified, observedAt: observed, language: "pt", primaryLink: URL(string: "https://example.com/item"), searchProjection: "Title Body", providerID: ProviderID())
        let decoded = try JSONDecoder().decode(OriginRevision.self, from: JSONEncoder().encode(revision))
        XCTAssertEqual(decoded, revision)
        XCTAssertEqual(decoded.authoredAt, authored)
        XCTAssertEqual(decoded.modifiedAt, modified)
        XCTAssertEqual(decoded.observedAt, observed)
        XCTAssertEqual(decoded.providerID, revision.providerID)
    }

    func testOneOriginHasIndependentMembershipsInTwoSources() {
        let recordID = OriginRecordID()
        let first = SourceMembership(originRecordID: recordID, sourceID: SourceID(), kind: .direct, firstObservedAt: Date(timeIntervalSince1970: 10), lastObservedAt: Date(timeIntervalSince1970: 20))
        let second = SourceMembership(originRecordID: recordID, sourceID: SourceID(), kind: .derived, firstObservedAt: Date(timeIntervalSince1970: 30), lastObservedAt: Date(timeIntervalSince1970: 40))
        XCTAssertEqual(first.originRecordID, second.originRecordID)
        XCTAssertNotEqual(first.sourceID, second.sourceID)
        XCTAssertNotEqual(first, second)
    }

    func testEntityRejectsEmptyOriginsAndPreservesNonemptyOrigins() throws {
        let id = ContentEntityID()
        XCTAssertNil(ContentEntity(id: id, originRecordIDs: []))
        let origins: Set<OriginRecordID> = [OriginRecordID(), OriginRecordID()]
        let entity = try XCTUnwrap(ContentEntity(id: id, originRecordIDs: origins))
        XCTAssertEqual(entity.id, id)
        XCTAssertEqual(entity.originRecordIDs, origins)
        XCTAssertEqual(try JSONDecoder().decode(ContentEntity.self, from: JSONEncoder().encode(entity)), entity)
    }

    func testClusterRejectsOnlyInvalidCanonicalInputs() throws {
        let id = ContentClusterID()
        let origins: Set<OriginRecordID> = [OriginRecordID()]
        XCTAssertNil(ContentCluster(id: id, originRecordIDs: [], confidence: 0.5, method: "editorial", version: 0))
        for confidence in [-0.1, 1.1, Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertNil(ContentCluster(id: id, originRecordIDs: origins, confidence: confidence, method: "editorial", version: 0))
        }
        XCTAssertNil(ContentCluster(id: id, originRecordIDs: origins, confidence: 0.5, method: "", version: 0))
        for confidence in [0.0, 0.5, 1.0] {
            let cluster = try XCTUnwrap(ContentCluster(id: id, originRecordIDs: origins, confidence: confidence, method: " ", version: UInt64.max))
            XCTAssertEqual(cluster.originRecordIDs, origins)
            XCTAssertEqual(cluster.confidence, confidence)
            XCTAssertEqual(cluster.method, " ") // No trimming or extra validation is authorized.
            XCTAssertEqual(cluster.version, UInt64.max)
            XCTAssertEqual(try JSONDecoder().decode(ContentCluster.self, from: JSONEncoder().encode(cluster)), cluster)
        }
    }

    func testEntityDecodingRejectsEmptyOrigins() throws {
        let json = "{\"id\":{\"rawValue\":\"\(UUID().uuidString)\"},\"originRecordIDs\":[]}"
        XCTAssertThrowsError(try JSONDecoder().decode(ContentEntity.self, from: Data(json.utf8)))
    }

    func testClusterDecodingEnforcesInitializerInvariants() throws {
        let cluster = try XCTUnwrap(ContentCluster(id: ContentClusterID(), originRecordIDs: [OriginRecordID()], confidence: 0.5, method: "editorial", version: 1))
        let valid = try JSONEncoder().encode(cluster)
        for invalidField in ["originRecordIDs", "confidence", "method"] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
            switch invalidField {
            case "originRecordIDs": object[invalidField] = [] as [String]
            case "confidence": object[invalidField] = 1.1
            default: object[invalidField] = ""
            }
            let invalid = try JSONSerialization.data(withJSONObject: object)
            XCTAssertThrowsError(try JSONDecoder().decode(ContentCluster.self, from: invalid))
        }
    }

    func testAllFourContentRelationsCodableRoundTrip() throws {
        let from = OriginRecordID()
        let to = OriginRecordID()
        for kind: ContentRelationKind in [.replyTo, .repostOf, .quoteOf, .references] {
            let relation = ContentRelation(fromOriginRecordID: from, toOriginRecordID: to, kind: kind)
            XCTAssertEqual(try JSONDecoder().decode(ContentRelation.self, from: JSONEncoder().encode(relation)), relation)
        }
    }
}
