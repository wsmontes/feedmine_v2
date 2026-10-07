import Foundation
import XCTest
import FeedMineDomain
import FeedMinePublication

final class FeedEditionTests: XCTestCase {
    func testEditionDerivesContextAndPreservesHistoryMetadata() {
        let context = FeedContext(request: .source(SourceID()))
        let revision = EditorialRevision(
            id: EditorialRevisionID(), contextKey: context.key,
            catalogGeneration: CatalogGeneration(rawValue: 1),
            userSelectionVersion: PolicyVersion(rawValue: 2),
            eligibilityPolicyVersion: PolicyVersion(rawValue: 3),
            scoringPolicyVersion: PolicyVersion(rawValue: 4),
            sequencingPolicyVersion: PolicyVersion(rawValue: 5),
            exposurePolicyVersion: PolicyVersion(rawValue: 6),
            selectionSchemaVersion: SelectionSchemaVersion(rawValue: 7)
        )
        let id = FeedEditionID()
        let date = Date(timeIntervalSince1970: 100)
        let edition = FeedEdition(id: id, editorialRevision: revision,
            publicationSchemaVersion: PublicationSchemaVersion(rawValue: 8),
            selectionSeed: UInt64.max, createdAt: date)
        XCTAssertEqual(edition.id, id)
        XCTAssertEqual(edition.editorialRevision, revision)
        XCTAssertEqual(edition.contextKey, revision.contextKey)
        XCTAssertEqual(edition.contextKey, context.key)
        XCTAssertEqual(edition.publicationSchemaVersion.rawValue, 8)
        XCTAssertEqual(edition.selectionSeed, UInt64.max)
        XCTAssertEqual(edition.createdAt, date)

        let successor = FeedEdition(id: FeedEditionID(), editorialRevision: revision,
            publicationSchemaVersion: edition.publicationSchemaVersion,
            selectionSeed: edition.selectionSeed, createdAt: date)
        XCTAssertEqual(successor.editorialRevision, edition.editorialRevision)
        XCTAssertNotEqual(successor.id, edition.id)
        XCTAssertNotEqual(successor, edition)
    }

    func testPublicationSchemaVersionOrdersByUnsignedRawValue() {
        XCTAssertLessThan(PublicationSchemaVersion(rawValue: 0), PublicationSchemaVersion(rawValue: UInt64.max))
        XCTAssertGreaterThan(PublicationSchemaVersion(rawValue: 9), PublicationSchemaVersion(rawValue: 8))
        XCTAssertEqual(PublicationSchemaVersion(rawValue: 4), PublicationSchemaVersion(rawValue: 4))
        XCTAssertFalse(PublicationSchemaVersion(rawValue: 4) < PublicationSchemaVersion(rawValue: 4))
    }
}
