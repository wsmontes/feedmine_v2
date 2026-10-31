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

    // Simulates an OS-constrained physical move without assuming that
    // UIScrollView's normal setter clamps programmatic offsets.
    private final class LimitedScrollView: UIScrollView {
        var maxAcceptedY: CGFloat = 600
        private(set) var writeCount = 0
        override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
            writeCount += 1
            super.setContentOffset(CGPoint(x: contentOffset.x,
                y: min(contentOffset.y, maxAcceptedY)), animated: animated)
        }
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

    func testForeignWitnessCannotTriggerAutomaticWriteDuringTokenedHandoff() {
        let reader = PublicationCardID(), nearer = PublicationCardID(),
            appended = PublicationCardID()
        let native = FeedNativeScrollOffset()
        let view = scroll()
        native.scrollView = view
        native.updateWindow([reader, nearer])
        _ = native.observe(geometry(reader, top: 180, offset: 500))
        _ = native.observe(geometry(nearer, top: 305, offset: 500))
        let token = UUID()
        XCTAssertTrue(native.beginProvisionalCorrection(transaction: token, witness: reader))
        native.updateWindow([appended, reader, nearer])
        // The automatic correction may prefer the card nearest viewport
        // center, but it must not write for a different transaction witness.
        XCTAssertFalse(native.observe(geometry(nearer, top: 425, offset: 500)))
        XCTAssertEqual(view.contentOffset.y, 500, accuracy: 0.01)
        XCTAssertEqual(native.appliedCount, 0)
        XCTAssertFalse(native.takeProvisionalConfirmation(transaction: token))
    }

    func testSecondWindowMutationCannotProduceASecondTokenedOffsetWrite() {
        let reader = PublicationCardID(), added = PublicationCardID(),
            more = PublicationCardID()
        let native = FeedNativeScrollOffset()
        let view = scroll()
        native.scrollView = view
        native.updateWindow([reader])
        _ = native.observe(geometry(reader, top: 180, offset: 500))
        let token = UUID()
        XCTAssertTrue(native.beginProvisionalCorrection(transaction: token, witness: reader))
        native.updateWindow([added, reader])
        _ = native.observe(geometry(reader, top: 420, offset: 500))
        XCTAssertEqual(native.appliedCount, 1)
        XCTAssertEqual(view.contentOffset.y, 740, accuracy: 0.01)
        // A second publication update before verification must never use
        // the same receipt to apply a second native adjustment.
        native.updateWindow([more, added, reader])
        XCTAssertFalse(native.observe(geometry(reader, top: 510, offset: 740)))
        XCTAssertEqual(native.appliedCount, 1)
        XCTAssertEqual(view.contentOffset.y, 740, accuracy: 0.01)
        XCTAssertFalse(native.takeProvisionalConfirmation(transaction: token))
    }

    func testGestureAfterOffsetWriteInvalidatesUnverifiedReceipt() {
        let reader = PublicationCardID(), added = PublicationCardID()
        let native = FeedNativeScrollOffset()
        let view = scroll()
        native.scrollView = view
        native.updateWindow([reader])
        _ = native.observe(geometry(reader, top: 180, offset: 500))
        let token = UUID()
        XCTAssertTrue(native.beginProvisionalCorrection(transaction: token, witness: reader))
        native.updateWindow([added, reader])
        _ = native.observe(geometry(reader, top: 420, offset: 500))
        XCTAssertEqual(native.appliedCount, 1)
        native.setInteractionActive(true)
        XCTAssertFalse(native.takeProvisionalConfirmation(transaction: token))
        _ = native.observe(geometry(reader, top: 180, offset: 740))
        XCTAssertFalse(native.takeProvisionalConfirmation(transaction: token))
        native.setInteractionActive(false)
        XCTAssertFalse(native.takeProvisionalConfirmation(transaction: token),
            "The host must roll back the physical provisional layout, not commit on gesture")
        XCTAssertEqual(native.appliedCount, 1)
    }

    func testLimitedNativeOffsetCannotMintSuccessfulVisualReceipt() {
        let reader = PublicationCardID(), extra = PublicationCardID()
        let native = FeedNativeScrollOffset()
        let view = LimitedScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 650))
        view.contentSize = CGSize(width: 320, height: 2_000)
        view.contentOffset = CGPoint(x: 0, y: 500)
        native.scrollView = view
        native.updateWindow([reader])
        _ = native.observe(geometry(reader, top: 180, offset: 500))
        let token = UUID()
        XCTAssertTrue(native.beginProvisionalCorrection(transaction: token, witness: reader))
        native.updateWindow([extra, reader])
        _ = native.observe(geometry(reader, top: 420, offset: 500))
        XCTAssertEqual(view.contentOffset.y, 600, accuracy: 0.01)
        XCTAssertEqual(native.appliedCount, 1,
            "A single attempted native write is not proof that the target offset was reached")
        XCTAssertFalse(native.takeProvisionalConfirmation(transaction: token))
        _ = native.observe(geometry(reader, top: 320, offset: 600))
        XCTAssertFalse(native.takeProvisionalConfirmation(transaction: token),
            "An OS-limited write must never be accepted as a complete correction")
    }

    func testStaleProofWithMatchingNumbersCannotConfirmDifferentPhysicalOffset() {
        let reader = PublicationCardID(), extra = PublicationCardID()
        let native = FeedNativeScrollOffset()
        let view = scroll()
        native.scrollView = view
        native.updateWindow([reader])
        _ = native.observe(geometry(reader, top: 180, offset: 500))
        let token = UUID()
        XCTAssertTrue(native.beginProvisionalCorrection(transaction: token, witness: reader))
        native.updateWindow([extra, reader])
        _ = native.observe(geometry(reader, top: 420, offset: 500))
        XCTAssertEqual(view.contentOffset.y, 740, accuracy: 0.01)
        view.contentOffset = CGPoint(x: 0, y: 800)
        _ = native.observe(geometry(reader, top: 180, offset: 740))
        XCTAssertFalse(native.takeProvisionalConfirmation(transaction: token),
            "An outdated geometry payload cannot override the actual UIScrollView position")
    }

    func testAnimatedNativeMovementCannotBeAcknowledgedAsIdle() {
        let reader = PublicationCardID()
        let native = FeedNativeScrollOffset()
        let view = scroll()
        native.scrollView = view
        let token = UUID()
        XCTAssertTrue(native.beginProvisionalCorrection(transaction: token, witness: reader))
        native.cancelProvisionalCorrection(transaction: token)
        XCTAssertFalse(native.takeProvisionalConfirmation(transaction: token))
    }

    func testZeroDisplacementHandoffUsesMeasuredReceiptWithoutOffsetWrite() {
        let reader = PublicationCardID(), appended = PublicationCardID()
        let native = FeedNativeScrollOffset()
        let view = scroll()
        native.scrollView = view
        native.updateWindow([reader])
        _ = native.observe(geometry(reader, top: 180, offset: 500))
        let token = UUID()
        XCTAssertTrue(native.beginProvisionalCorrection(transaction: token, witness: reader))
        native.updateWindow([reader, appended])
        XCTAssertFalse(native.takeProvisionalConfirmation(transaction: token),
            "Changing IDs alone is not a measured physical handoff")
        XCTAssertFalse(native.observe(geometry(reader, top: 180, offset: 500)),
            "No native offset write is needed for a zero-delta window")
        XCTAssertTrue(native.takeProvisionalConfirmation(transaction: token),
            "A new matching post-layout proof must authorize an idle no-op handoff")
        XCTAssertFalse(native.takeProvisionalConfirmation(transaction: token))
        XCTAssertEqual(view.contentOffset.y, 500, accuracy: 0.01)
        XCTAssertEqual(native.appliedCount, 0)
    }

    func testZeroDisplacementReceiptRejectsDifferentCardAndStaleActualOffset() {
        let reader = PublicationCardID(), appended = PublicationCardID()
        let native = FeedNativeScrollOffset()
        let view = scroll()
        native.scrollView = view
        native.updateWindow([reader])
        _ = native.observe(geometry(reader, top: 180, offset: 500))
        let token = UUID()
        XCTAssertTrue(native.beginProvisionalCorrection(transaction: token, witness: reader))
        native.updateWindow([reader, appended])
        _ = native.observe(geometry(appended, top: 240, offset: 500))
        XCTAssertFalse(native.takeProvisionalConfirmation(transaction: token))
        // A stale callback describes the old geometry, but the physical scroll
        // view already moved: only the actual UIKit offset can authorize a proof.
        view.contentOffset = CGPoint(x: 0, y: 540)
        _ = native.observe(geometry(reader, top: 180, offset: 500))
        XCTAssertFalse(native.takeProvisionalConfirmation(transaction: token))
        XCTAssertEqual(native.appliedCount, 0)
    }

    func testReplacedUIScrollViewCannotUseOldProvisionalGeometryOrWrite() {
        let reader = PublicationCardID(), extra = PublicationCardID()
        let native = FeedNativeScrollOffset()
        let old = scroll()
        native.scrollView = old
        native.updateWindow([reader])
        _ = native.observe(geometry(reader, top: 180, offset: 500))
        let token = UUID()
        XCTAssertTrue(native.beginProvisionalCorrection(transaction: token, witness: reader))
        let replacement = scroll()
        native.scrollView = replacement
        native.updateWindow([extra, reader])
        XCTAssertFalse(native.observe(geometry(reader, top: 420, offset: 500)),
            "Old view geometry must not adjust a replacement UIScrollView")
        XCTAssertEqual(replacement.contentOffset.y, 500, accuracy: 0.01)
        XCTAssertEqual(native.appliedCount, 0)
        XCTAssertFalse(native.takeProvisionalConfirmation(transaction: token))
    }

    func testInsetChangedDuringProvisionalCannotConfirmReceipt() {
        let reader = PublicationCardID(), extra = PublicationCardID()
        let native = FeedNativeScrollOffset()
        let view = scroll()
        native.scrollView = view
        native.updateWindow([reader])
        _ = native.observe(geometry(reader, top: 180, offset: 500))
        let token = UUID()
        XCTAssertTrue(native.beginProvisionalCorrection(transaction: token, witness: reader))
        view.contentInset.top = 24
        native.updateWindow([extra, reader])
        XCTAssertFalse(native.observe(geometry(reader, top: 420, offset: 500)))
        XCTAssertEqual(native.appliedCount, 0,
            "An adjusted-content-inset change must invalidate old viewport geometry")
        XCTAssertFalse(native.takeProvisionalConfirmation(transaction: token))
    }

    func testInsetChangeAfterNativeWriteRevokesPostCorrectionReceipt() {
        let reader = PublicationCardID(), extra = PublicationCardID()
        let native = FeedNativeScrollOffset()
        let view = scroll()
        native.scrollView = view
        native.updateWindow([reader])
        _ = native.observe(geometry(reader, top: 180, offset: 500))
        let token = UUID()
        XCTAssertTrue(native.beginProvisionalCorrection(transaction: token, witness: reader))
        native.updateWindow([extra, reader])
        XCTAssertTrue(native.observe(geometry(reader, top: 420, offset: 500)))
        XCTAssertEqual(native.appliedCount, 1)
        view.contentInset.bottom = 30
        _ = native.observe(geometry(reader, top: 180, offset: 740))
        XCTAssertFalse(native.takeProvisionalConfirmation(transaction: token),
            "Even matching card numbers cannot validate a different inset geometry")
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
