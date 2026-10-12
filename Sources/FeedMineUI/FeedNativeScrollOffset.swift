import SwiftUI
#if canImport(UIKit)
import UIKit
import FeedMineDomain
#if DEBUG
import OSLog
#endif
#endif

#if canImport(UIKit)
/// A narrow adapter to the existing native scroll view. It owns no content or navigation.
@MainActor
final class FeedNativeScrollOffset {
    weak var scrollView: UIScrollView?

    private var correction = FeedWindowOffsetCorrection()
    private var suppressCorrectionEvents = false
    private var correctedOffset: CGFloat = 0
    var isCorrecting: Bool {
        if suppressCorrectionEvents, let scrollView,
            (scrollView.isDragging || scrollView.isDecelerating),
            abs(scrollView.contentOffset.y - correctedOffset) > 0.5 {
            suppressCorrectionEvents = false
        }
        return suppressCorrectionEvents
    }
    private(set) var appliedCount = 0
    private(set) var maximumResidual: CGFloat = 0
    private var visualWitness: (id: PublicationCardID, expectedY: CGFloat, offset: CGFloat)?
    private(set) var measuredCorrections = 0
    private(set) var maximumVisualResidual: CGFloat = 0
    func updateWindow(_ ids: [PublicationCardID]) {
        correction.updateWindow(ids)
        #if DEBUG
        if FeedVisualCapture.tracesCapture {
            Logger(subsystem: "com.feedmine.development", category: "native-capture").info(
                "offset witness samples=\(self.correction.retainedCount) pending=\(String(describing: self.correction.pendingCardID), privacy: .public) native=\(self.scrollView != nil)")
        }
        #endif
    }
    func cancel() { correction.cancel(); suppressCorrectionEvents = false }
    func observe(_ proof: FeedVisualCardGeometry) -> Bool {
        // Ignore the stale geometry callback carrying the pre-adjustment offset. Measure the
        // same retained card when the layout first reports the actual corrected native offset.
        if let witness = visualWitness, witness.id == proof.cardID,
            abs(proof.offset - witness.offset) < 0.5 {
            maximumVisualResidual = max(maximumVisualResidual, abs(proof.frame.minY - witness.expectedY))
            measuredCorrections += 1
            visualWitness = nil
        }
        guard let delta = correction.observe(proof) else { return isCorrecting }
        guard let scrollView else {
            #if DEBUG
            if FeedVisualCapture.tracesCapture {
                Logger(subsystem: "com.feedmine.development", category: "native-capture").info("offset witness missing native scroll")
            }
            #endif
            return false
        }
        suppressCorrectionEvents = true
        let before = scrollView.contentOffset.y
        adjust(by: delta)
        correctedOffset = scrollView.contentOffset.y
        visualWitness = (proof.cardID, proof.frame.minY - delta + proof.offset - before, correctedOffset)
        appliedCount += 1
        maximumResidual = max(maximumResidual, abs(delta - (scrollView.contentOffset.y - before)))
        #if DEBUG
        if FeedVisualCapture.tracesCapture {
            Logger(subsystem: "com.feedmine.development", category: "native-capture").info(
                "window correction card=\(proof.cardID.rawValue.uuidString, privacy: .public) delta=\(delta) offsetBefore=\(before) offsetAfter=\(scrollView.contentOffset.y)")
        }
        #endif
        return true
    }
    private func adjust(by delta: CGFloat) {
        guard let scrollView, delta.isFinite else { return }
        let offset = scrollView.contentOffset
        // Preserve a gesture already in progress; only the layout-induced displacement is removed.
        scrollView.setContentOffset(CGPoint(x: offset.x, y: offset.y + delta), animated: false)
    }
}

struct FeedNativeScrollProbe: UIViewRepresentable {
    let access: FeedNativeScrollOffset
    let ids: [PublicationCardID]
    func makeUIView(context: Context) -> Probe { Probe(access: access) }
    func updateUIView(_ view: Probe, context: Context) { view.access = access; access.updateWindow(ids) }

    final class Probe: UIView {
        var access: FeedNativeScrollOffset
        init(access: FeedNativeScrollOffset) {
            self.access = access
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override func didMoveToWindow() { super.didMoveToWindow(); resolveScrollView() }
        override func layoutSubviews() { super.layoutSubviews(); resolveScrollView() }
        private func resolveScrollView() {
            var ancestor = superview
            while let view = ancestor {
                if let scroll = view as? UIScrollView { access.scrollView = scroll; return }
                ancestor = view.superview
            }
        }
    }
}
#if DEBUG
struct FeedNativeWindowProof: ViewModifier {
    let ids: [PublicationCardID]
    let access: FeedNativeScrollOffset
    func body(content: Content) -> some View {
        content.overlay(alignment: .topLeading) {
            if FeedVisualCapture.tracesCapture {
                Text("ids=\(ids.map { $0.rawValue.uuidString }.joined(separator: ","));corrections=\(access.appliedCount);residual=\(access.maximumResidual);measured=\(access.measuredCorrections);visualResidual=\(access.maximumVisualResidual)")
                    .font(.system(size: 1)).frame(width: 1, height: 1).opacity(0)
                    .allowsHitTesting(false).accessibilityIdentifier("feed-window-proof")
            }
        }
    }
}
#endif
#endif
