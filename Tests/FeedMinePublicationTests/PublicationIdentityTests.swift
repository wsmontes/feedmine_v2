import Foundation
import XCTest
import FeedMineDomain

final class PublicationIdentityTests: XCTestCase {
    func testNominalIDsKeepTheirTypesEvenWithSameRawUUID() {
        let raw = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let edition = FeedEditionID(rawValue: raw)
        let segment = FeedSegmentID(rawValue: raw)
        let card = PublicationCardID(rawValue: raw)
        XCTAssertNotEqual(AnyHashable(edition), AnyHashable(segment))
        XCTAssertNotEqual(AnyHashable(edition), AnyHashable(card))
        XCTAssertNotEqual(AnyHashable(segment), AnyHashable(card))
        XCTAssertEqual(edition.rawValue, raw)
        XCTAssertEqual(segment.rawValue, raw)
        XCTAssertEqual(card.rawValue, raw)
        XCTAssertEqual(edition.description, raw.uuidString)
        XCTAssertEqual(segment.description, raw.uuidString)
        XCTAssertEqual(card.description, raw.uuidString)
    }

    func testIDsRoundTripWithoutChangingIdentity() throws {
        let edition = FeedEditionID()
        let segment = FeedSegmentID()
        let card = PublicationCardID()
        XCTAssertEqual(try JSONDecoder().decode(FeedEditionID.self, from: JSONEncoder().encode(edition)), edition)
        XCTAssertEqual(try JSONDecoder().decode(FeedSegmentID.self, from: JSONEncoder().encode(segment)), segment)
        XCTAssertEqual(try JSONDecoder().decode(PublicationCardID.self, from: JSONEncoder().encode(card)), card)
        XCTAssertNotEqual(FeedEditionID(), FeedEditionID())
        XCTAssertNotEqual(FeedSegmentID(), FeedSegmentID())
        XCTAssertNotEqual(PublicationCardID(), PublicationCardID())
    }
}
