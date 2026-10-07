import XCTest
import FeedMineDomain
import FeedMinePublication

final class SessionCursorTests: XCTestCase {
    func testTopCursorPreservesEditionAndCardOccurrence() {
        let edition = FeedEditionID()
        let card = PublicationCardID()
        let cursor = SessionCursor(editionID: edition, anchor: FeedWindowAnchor(cardID: card, placement: .top))
        XCTAssertEqual(cursor.editionID, edition)
        XCTAssertEqual(cursor.anchor.cardID, card)
        XCTAssertEqual(cursor.anchor.placement, .top)
    }

    func testCenterCursorPreservesEditionAndCardOccurrence() {
        let edition = FeedEditionID()
        let card = PublicationCardID()
        let cursor = SessionCursor(editionID: edition, anchor: FeedWindowAnchor(cardID: card, placement: .center))
        XCTAssertEqual(cursor.editionID, edition)
        XCTAssertEqual(cursor.anchor.cardID, card)
        XCTAssertEqual(cursor.anchor.placement, .center)
    }
}
