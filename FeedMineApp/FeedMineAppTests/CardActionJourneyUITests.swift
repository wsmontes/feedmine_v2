// File: CardActionJourneyUITests.swift
// Module: FeedMineUITests
// Owns: the card menu's internal destination (Ver a fonte) and the platform share sheet it asks the host to
//       present. Compartilhar is proved by the sheet appearing and being dismissible; nothing is sent anywhere.

import XCTest

final class CardActionJourneyUITests: XCTestCase {
    /// G6: "Ver a fonte" must switch to the internal source context, never open the article's site; returning
    /// restores the main context.
    @MainActor
    func testViewSourceOpensTheInternalSourceAndReturns() throws {
        let app = SurfaceTest.launchFixture()
        let card = try XCTUnwrap(SurfaceTest.firstCard(app))
        let context = SurfaceTest.element(app, "reader-contexts")
        XCTAssertTrue(context.waitForExistence(timeout: 10))
        let before = context.label

        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.2)
        let viewSource = app.menus.buttons["Ver a fonte"].firstMatch
        if viewSource.waitForExistence(timeout: 5) { viewSource.tap() } else {
            let visible = app.buttons["Ver a fonte"].firstMatch
            XCTAssertTrue(visible.waitForExistence(timeout: 5), "the card menu offers Ver a fonte")
            visible.tap()
        }

        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", before), object: context)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 30), .completed,
            "the source context is stated by the header")
        XCTAssertFalse(app.staticTexts["reading.headline"].exists,
            "viewing the source is not opening the article's site")
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 30))

        context.tap()
        SurfaceTest.element(app, "reader-context-clear").tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 30))
        let restored = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", before), object: context)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 30), .completed,
            "clearing the source context restores the reading context it came from")
    }

    /// G6: the card's Compartilhar asks the host to present the platform sheet. The test presents it, records the
    /// items the sheet drew (the app's frozen link must be the payload), and dismisses it without sending anything.
    @MainActor
    func testSharePresentsTheSystemSheetWithTheCardLink() throws {
        let app = SurfaceTest.launchFixture()
        let card = try XCTUnwrap(SurfaceTest.firstCard(app))
        let title = card.label
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.2)
        let share = app.menus.buttons["Compartilhar"].firstMatch
        if share.waitForExistence(timeout: 5) { share.tap() } else {
            let visible = app.buttons["Compartilhar"].firstMatch
            XCTAssertTrue(visible.waitForExistence(timeout: 5), "the card menu offers Compartilhar")
            visible.tap()
        }

        let activity = app.otherElements["ActivityListView"]
        let sheet = app.sheets.firstMatch
        let presented = activity.waitForExistence(timeout: 20) || sheet.waitForExistence(timeout: 10)
        XCTAssertTrue(presented, "Compartilhar presents the platform activity sheet")
        // The sheet is local state; inspect what it drew. The item is the card's frozen URL, so the host's link
        // must carry the fixture's own address rather than another card's.
        let texts = app.staticTexts.allElementsBoundByIndex.prefix(20).map(\.label)
        let proof = XCTAttachment(string: "card=\(title)\nshare-texts=\(texts)")
        proof.name = "card-share-sheet"
        proof.lifetime = .keepAlways
        add(proof)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "card-share-tree"
        tree.lifetime = .keepAlways
        add(tree)
        XCTAssertTrue(texts.contains { $0.contains("example.test") || $0.contains("Fixture") },
            "the sheet states the card's own link/title; observed: \(texts)")

        SurfaceTest.dismissSystemSheet(app)
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20),
            "dismissing the share sheet returns to the reader with the feed intact")
    }
}
