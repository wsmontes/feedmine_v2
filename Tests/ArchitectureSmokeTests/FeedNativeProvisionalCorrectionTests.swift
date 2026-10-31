#if canImport(UIKit)
import UIKit
import XCTest
import FeedMineDomain
@testable import FeedMineUI

/// P0 / B05: confirm a provisional viewport only after the existing native
/// offset writer has made ONE adjustment and a matching post-write geometry
/// callback has proved the physical result. No second delta is exposed to UI.
@MainActor
final class FeedNativeProvisionalCorrectionTests: XCTestCase {
    private func scroll() -> UIScrollView {
        let view = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 650))
        view.contentSize = CGSize(width: 320, height: 2_000)
        view.contentOffset = CGPoint(x: 0, y: 500)
        return view
    }

    private func geometry(_ id: PublicationCardID, top: CGFloat,
        offset: CGFloat) -> FeedVisualCardGeometry {
        FeedVisualCardGeometry(cardID: id,
            frame: CGRect(x: 0, y: top, width: 320, height: 160),
            offset: offset, height: 650)
    }

    func testExactlyOneNativeWriteAndPostCorrectionProofBeforeAcknowledgement() {
        let reader = PublicationCardID(), extra = PublicationCardID()
        let native = FeedNativeScrollOffset()
        let view = scroll()
        native.scrollView = view
        native.updateWindow([reader])
        XCTAssertFalse(native.observe(geometry(reader, top: 180, offset: 500)))
        let token = UUID()
        XCTAssertTrue(native.beginProvisionalCorrection(transaction: token, witness: reader))
        native.updateWindow([extra, reader])
        XCTAssertTrue(native.observe(geometry(reader, top: 420, offset: 500)))
        XCTAssertEqual(view.contentOffset.y, 740, accuracy: 0.01)
        XCTAssertEqual(native.appliedCount, 1)
        XCTAssertFalse(native.takeProvisionalConfirmation(transaction: token),
            "An offset write without a post-adjustment layout proof cannot commit a visual rail")
        XCTAssertFalse(native.takeProvisionalConfirmation(transaction: UUID()))
        _ = native.observe(geometry(reader, top: 180, offset: 740))
        XCTAssertTrue(native.takeProvisionalConfirmation(transaction: token))
        XCTAssertFalse(native.takeProvisionalConfirmation(transaction: token),
            "The same receipt may not be consumed twice to trigger two commits")
        XCTAssertEqual(native.appliedCount, 1,
            "Confirmation cannot perform a second native offset write")
        XCTAssertEqual(native.measuredCorrections, 1)
    }

    func testGestureBeforeWindowChangeCancelsTokenAndForbidsNativeWrite() {
        let reader = PublicationCardID(), extra = PublicationCardID()
        let native = FeedNativeScrollOffset()
        let view = scroll()
        native.scrollView = view
        native.updateWindow([reader])
        _ = native.observe(geometry(reader, top: 180, offset: 500))
        let token = UUID()
        XCTAssertTrue(native.beginProvisionalCorrection(transaction: token, witness: reader))
        native.setInteractionActive(true)
        native.updateWindow([extra, reader])
        XCTAssertFalse(native.observe(geometry(reader, top: 420, offset: 500)))
        XCTAssertEqual(view.contentOffset.y, 500, accuracy: 0.01)
        XCTAssertEqual(native.appliedCount, 0)
        XCTAssertFalse(native.takeProvisionalConfirmation(transaction: token))
        native.setInteractionActive(false)
        XCTAssertFalse(native.takeProvisionalConfirmation(transaction: token),
            "Gesture cancellation cannot become a delayed idle write")
    }

    func testWrongCardCannotConfirmEvenAfterNativeAdjustment() {
        let reader = PublicationCardID(), extra = PublicationCardID()
        let native = FeedNativeScrollOffset()
        let view = scroll()
        native.scrollView = view
        native.updateWindow([reader])
        _ = native.observe(geometry(reader, top: 180, offset: 500))
        let token = UUID()
        XCTAssertTrue(native.beginProvisionalCorrection(transaction: token, witness: reader))
        native.updateWindow([reader, extra])
        _ = native.observe(geometry(reader, top: 420, offset: 500))
        _ = native.observe(geometry(extra, top: 200, offset: 740))
        XCTAssertFalse(native.takeProvisionalConfirmation(transaction: token))
        _ = native.observe(geometry(reader, top: 180, offset: 740))
        XCTAssertTrue(native.takeProvisionalConfirmation(transaction: token))
    }

    func testCancellationRejectsStaleTokenAndMissingNativeScroll() {
        let native = FeedNativeScrollOffset()
        let reader = PublicationCardID()
        let old = UUID(), next = UUID()
        XCTAssertFalse(native.beginProvisionalCorrection(transaction: old, witness: reader),
            "A missing native scroll view cannot promise an offset correction")
        let view = scroll()
        native.scrollView = view
        XCTAssertTrue(native.beginProvisionalCorrection(transaction: old, witness: reader))
        XCTAssertFalse(native.cancelProvisionalCorrection(transaction: next))
        XCTAssertTrue(native.cancelProvisionalCorrection(transaction: old))
        XCTAssertFalse(native.takeProvisionalConfirmation(transaction: old))
        XCTAssertTrue(native.beginProvisionalCorrection(transaction: next, witness: reader))
        XCTAssertFalse(native.takeProvisionalConfirmation(transaction: old))
        XCTAssertTrue(native.cancelProvisionalCorrection(transaction: next))
        XCTAssertEqual(view.contentOffset.y, 500, accuracy: 0.01)
    }
}
#endif
