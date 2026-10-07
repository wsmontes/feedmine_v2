import XCTest
import FeedMineDomain
@testable import FeedMinePublication

final class FeedWindowTests: XCTestCase {
    func testAcceptsUniqueCardsPreservingSuppliedOrderAndPlacement() throws {
        let cards = try [2, 0, 1].map { try RestoreFixture.card(index: $0) }
        let editionID = FeedEditionID()
        for placement in [AnchorPlacement.top, .center] {
            let anchor = FeedWindowAnchor(cardID: cards[1].id, placement: placement)
            let window = try XCTUnwrap(FeedWindow(editionID: editionID, cards: cards, anchor: anchor))
            XCTAssertEqual(window.editionID, editionID)
            XCTAssertEqual(window.cards, cards)
            XCTAssertEqual(window.anchor, anchor)
        }
    }

    func testRejectsEmptyCards() {
        XCTAssertNil(FeedWindow(editionID: FeedEditionID(), cards: [],
            anchor: FeedWindowAnchor(cardID: PublicationCardID(), placement: .top)))
    }

    func testRejectsDuplicateOccurrenceEvenWhenAnchorIsUnique() throws {
        let cards = try (0..<2).map { try RestoreFixture.card(index: $0) }
        XCTAssertNil(FeedWindow(editionID: FeedEditionID(), cards: [cards[0], cards[1], cards[1]],
            anchor: FeedWindowAnchor(cardID: cards[0].id, placement: .center)))
        XCTAssertNil(FeedWindow(editionID: FeedEditionID(), cards: [cards[0], cards[0]],
            anchor: FeedWindowAnchor(cardID: cards[0].id, placement: .center)))
    }

    func testRejectsAbsentAnchor() throws {
        XCTAssertNil(FeedWindow(editionID: FeedEditionID(), cards: [try RestoreFixture.card(index: 0)],
            anchor: FeedWindowAnchor(cardID: PublicationCardID(), placement: .top)))
    }
}
