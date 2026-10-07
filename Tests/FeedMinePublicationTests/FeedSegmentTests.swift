import Foundation
import XCTest
import FeedMineDomain
import FeedMinePublication

final class FeedSegmentTests: XCTestCase {
    func testNonemptySegmentPreservesSuppliedOrderAndMetadata() throws {
        let first = PublicationCardID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!)
        let second = PublicationCardID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let third = PublicationCardID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        let id = FeedSegmentID()
        let editionID = FeedEditionID()
        let date = Date(timeIntervalSince1970: 200)
        let segment = try XCTUnwrap(FeedSegment(id: id, editionID: editionID,
            ordinal: 7, segmentSeed: UInt64.max,
            publicationSchemaVersion: PublicationSchemaVersion(rawValue: 3),
            createdAt: date, cardIDs: [first, second, third]))
        XCTAssertEqual(segment.id, id)
        XCTAssertEqual(segment.editionID, editionID)
        XCTAssertEqual(segment.ordinal, 7)
        XCTAssertEqual(segment.segmentSeed, UInt64.max)
        XCTAssertEqual(segment.publicationSchemaVersion.rawValue, 3)
        XCTAssertEqual(segment.createdAt, date)
        XCTAssertEqual(segment.cardIDs, [first, second, third])
    }

    func testEmptySegmentIsRejected() {
        XCTAssertNil(FeedSegment(id: FeedSegmentID(), editionID: FeedEditionID(),
            ordinal: 0, segmentSeed: 0,
            publicationSchemaVersion: PublicationSchemaVersion(rawValue: 1),
            createdAt: Date(timeIntervalSince1970: 0), cardIDs: []))
    }

    func testDuplicateCardOccurrenceIsRejectedInsteadOfDeduplicated() {
        let card = PublicationCardID()
        XCTAssertNil(FeedSegment(id: FeedSegmentID(), editionID: FeedEditionID(),
            ordinal: 1, segmentSeed: 0,
            publicationSchemaVersion: PublicationSchemaVersion(rawValue: 1),
            createdAt: Date(timeIntervalSince1970: 0), cardIDs: [card, PublicationCardID(), card]))
    }

    func testSingleCardAndArbitraryOrdinalAreAccepted() throws {
        let card = PublicationCardID()
        let segment = try XCTUnwrap(FeedSegment(id: FeedSegmentID(), editionID: FeedEditionID(),
            ordinal: UInt64.max, segmentSeed: 0,
            publicationSchemaVersion: PublicationSchemaVersion(rawValue: 0),
            createdAt: Date(timeIntervalSince1970: 0), cardIDs: [card]))
        XCTAssertEqual(segment.cardIDs, [card])
        XCTAssertEqual(segment.ordinal, UInt64.max)
    }
}
