import CoreGraphics
import XCTest
import FeedMineDomain
@testable import FeedMineUI

/// P0 / Issue #7: the visual set is distinct from frozen publication history.
/// Before changing that boundary, protect native offset math for the *same
/// rendered* card, not a fabricated geometry for an unready historical image.
@MainActor
final class RenderReadyOffsetContractTests: XCTestCase {
    private func proof(_ id: PublicationCardID, y: CGFloat, offset: CGFloat = 500,
        viewportHeight: CGFloat = 650) -> FeedVisualCardGeometry {
        FeedVisualCardGeometry(cardID: id,
            frame: CGRect(x: 0, y: y, width: 320, height: 160),
            offset: offset, height: viewportHeight)
    }

    func testIdleReadyInsertionCompensatesUsingAStableRenderedSibling() {
        let first = PublicationCardID()
        let newlyReady = PublicationCardID()
        let reader = PublicationCardID()
        var correction = FeedWindowOffsetCorrection()
        XCTAssertTrue(correction.updateWindow([first, reader]))
        XCTAssertNil(correction.observe(proof(reader, y: 180)))
        XCTAssertEqual(correction.retainedCount, 1)

        // A legitimate later visual admission can only insert a fully ready
        // image above the reader when there is no active gesture.
        XCTAssertTrue(correction.updateWindow([first, newlyReady, reader]))
        XCTAssertEqual(correction.pendingCardID, reader,
            "The witness must be a card that was actually rendered in both windows")
        let movement: CGFloat = 240
        XCTAssertEqual(correction.observe(proof(reader, y: 180 + movement)), movement,
            "The idle native-offset correction should compensate exactly for inserted height")
        XCTAssertNil(correction.pendingCardID,
            "An adjustment witness is consumed exactly once")
        XCTAssertNil(correction.observe(proof(reader, y: 180 + movement)),
            "No repeated offset adjustment on identical geometry")
    }

    func testOrdinaryScrollIsNotMistakenForLayoutInsertion() {
        let first = PublicationCardID()
        let newlyReady = PublicationCardID()
        let reader = PublicationCardID()
        var correction = FeedWindowOffsetCorrection()
        XCTAssertTrue(correction.updateWindow([first, reader]))
        XCTAssertNil(correction.observe(proof(reader, y: 180, offset: 500)))
        XCTAssertTrue(correction.updateWindow([first, newlyReady, reader]))
        XCTAssertEqual(correction.pendingCardID, reader)

        // The reader scrolled forward by 60: viewport Y decreases by 60,
        // native offset increases by 60, content-space Y stays unchanged.
        XCTAssertNil(correction.observe(proof(reader, y: 120, offset: 560)),
            "Reading movement itself must not trigger an offset correction")
        XCTAssertNil(correction.pendingCardID)
    }

    func testActiveGestureCannotAccumulateDeferredOffsetCorrection() {
        let first = PublicationCardID()
        let newlyReady = PublicationCardID()
        let reader = PublicationCardID()
        var correction = FeedWindowOffsetCorrection()
        XCTAssertTrue(correction.updateWindow([first, reader]))
        XCTAssertNil(correction.observe(proof(reader, y: 180)))

        // An active gesture owns its offset. If presentation membership changes,
        // the correction layer must neither queue nor apply an offset write.
        // FeedInteractionPresentation independently holds the original ready IDs;
        // this assertion guards the native correction's complementary boundary.
        XCTAssertTrue(correction.updateWindow([first, newlyReady, reader],
            allowingCorrection: false))
        XCTAssertNil(correction.pendingCardID)
        XCTAssertEqual(correction.retainedCount, 0)
        XCTAssertNil(correction.observe(proof(reader, y: 420)),
            "No delayed native write may race an active user gesture")
    }

    func testSameVisualIDsAcrossProjectionChangesDoNotReanchorReader() {
        let first = PublicationCardID()
        let reader = PublicationCardID()
        let ids = [first, reader]
        var correction = FeedWindowOffsetCorrection()
        XCTAssertTrue(correction.updateWindow(ids))
        XCTAssertNil(correction.observe(proof(reader, y: 180)))
        XCTAssertFalse(correction.updateWindow(ids),
            "Provenance or history changes alone are not a visual-list mutation")
        XCTAssertNil(correction.pendingCardID)
        XCTAssertNil(correction.observe(proof(reader, y: 180)))
    }
}
