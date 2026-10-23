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

    /// The live content origin. A restore measures against it instead of a card proof's own viewport line: the two
    /// are delivered in different passes and the proof may describe a scroll the view has already left.
    var contentOffsetY: CGFloat? { scrollView?.contentOffset.y }

    private var correction = FeedWindowOffsetCorrection()
    private var suppressCorrectionEvents = false
    private var correctedOffset: CGFloat = 0
    private var interactionPhaseActive = false
    func setInteractionActive(_ active: Bool) { interactionPhaseActive = active }
    private var nativeGestureActive: Bool {
        guard let scrollView else { return interactionPhaseActive }
        return interactionPhaseActive || scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
    }
    // Reading this property must not mutate the capture or cancel reader activity.
    var isCorrecting: Bool { suppressCorrectionEvents && !nativeGestureActive }
    /// Uma rolagem animada — programática, de acessibilidade ou do sistema — ainda está a caminho do destino. É o
    /// sinal nativo de que nada do que o desenho mostrar agora é uma posição em repouso: um gesto não aparece aqui
    /// (`isDragging`/`isDecelerating` o dizem), e por isso ele fecha o caso de uma tela que se move **sem** o leitor.
    var isAnimatingScroll: Bool { scrollView?.isScrollAnimating ?? false }
    #if DEBUG
    private(set) var activeWrites = 0
    private(set) var activeWindowChanges = 0
    private(set) var activeLayoutSteps = 0
    private(set) var maximumActiveLayoutStep: CGFloat = 0
    private var gestureProofs: [PublicationCardID: (proof: FeedVisualCardGeometry, nativeOffset: CGFloat)] = [:]
    #endif
    private(set) var appliedCount = 0
    private(set) var maximumResidual: CGFloat = 0
    private var visualWitness: (id: PublicationCardID, expectedY: CGFloat, offset: CGFloat)?
    private(set) var measuredCorrections = 0
    private(set) var maximumVisualResidual: CGFloat = 0
    func updateWindow(_ ids: [PublicationCardID]) {
        let gestureActive = nativeGestureActive
        let changed = correction.updateWindow(ids, allowingCorrection: !gestureActive)
        #if DEBUG
        if changed {
            let kept = Set(ids)
            gestureProofs = gestureProofs.filter { kept.contains($0.key) }
            if gestureActive { activeWindowChanges += 1 }
        }
        #endif
        #if DEBUG
        if FeedVisualCapture.tracesCapture {
            Logger(subsystem: "com.feedmine.development", category: "native-capture").info(
                "offset witness samples=\(self.correction.retainedCount) pending=\(String(describing: self.correction.pendingCardID), privacy: .public) native=\(self.scrollView != nil)")
        }
        #endif
    }
    func cancel(discardingSamples: Bool = true) {
        correction.cancel(discardingSamples: discardingSamples)
        suppressCorrectionEvents = false
        visualWitness = nil
    }
    func observe(_ proof: FeedVisualCardGeometry) -> Bool {
        #if DEBUG
        if FeedVisualCapture.tracesCapture, let scrollView {
            let nativeOffset = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
            if nativeGestureActive, let old = gestureProofs[proof.cardID],
                old.proof.frame.size == proof.frame.size, old.proof.height == proof.height,
                old.proof.frame.maxY > 0, old.proof.frame.minY < proof.height,
                proof.frame.maxY > 0, proof.frame.minY < proof.height,
                abs(old.proof.offset - proof.offset) < 0.5,
                abs(old.nativeOffset - nativeOffset) < 0.5,
                abs(proof.frame.minY - old.proof.frame.minY) > 1 {
                let step = abs(proof.frame.minY - old.proof.frame.minY)
                activeLayoutSteps += 1
                maximumActiveLayoutStep = max(maximumActiveLayoutStep, step)
                Logger(subsystem: "com.feedmine.development", category: "native-capture").info(
                    "active layout step card=\(proof.cardID.rawValue.uuidString, privacy: .public) frameBefore=\(old.proof.frame.minY) frameAfter=\(proof.frame.minY) proofOffsetBefore=\(old.proof.offset) proofOffsetAfter=\(proof.offset) nativeBefore=\(old.nativeOffset) nativeAfter=\(nativeOffset) dragging=\(scrollView.isDragging) decelerating=\(scrollView.isDecelerating)")
            }
            gestureProofs[proof.cardID] = (proof, nativeOffset)
        }
        #endif
        // A gesture owns the native offset. Discard, never postpone, any witness
        // crossing it; keep fresh geometry only for a later independent idle mutation.
        if nativeGestureActive {
            correction.cancel()
            _ = correction.observe(proof)
            suppressCorrectionEvents = false
            visualWitness = nil
            return false
        }
        // Ignore the stale geometry callback carrying the pre-adjustment offset. Measure the
        // same retained card when the layout first reports the actual corrected native offset.
        if let witness = visualWitness, witness.id == proof.cardID,
            abs(proof.offset - witness.offset) < 0.5 {
            maximumVisualResidual = max(maximumVisualResidual, abs(proof.frame.minY - witness.expectedY))
            measuredCorrections += 1
            visualWitness = nil
            // A correção **terminou**: esta é a geometria corrigida, reportada pelo próprio layout. Enquanto a
            // supressão ficasse de pé depois disso — ela só era desfeita por um gesto —, todo callback de carta era
            // consumido aqui e toda mudança de geometria saía pelo ramo de correção, então a captura nunca
            // reaprendia o que o desenho mostrava: a posição do viewport congelava na carta anterior à correção e a
            // durabilidade gravava uma posição que a tela não exibia (medido em B05, 2026-10-14: o cursor durável
            // sete cartas à frente da carta do topo que o driver mediu, e a reabertura desenhando outra tela).
            suppressCorrectionEvents = false
        }
        let prior = correction.pendingProof
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
        #if DEBUG
        if FeedVisualCapture.tracesCapture {
            if scrollView.isDragging || scrollView.isDecelerating { activeWrites += 1 }
            let velocity = scrollView.panGestureRecognizer.velocity(in: scrollView).y
            Logger(subsystem: "com.feedmine.development", category: "native-capture").info(
                "correction input card=\(proof.cardID.rawValue.uuidString, privacy: .public) frameY=\(proof.frame.minY) priorFrameY=\(prior?.frame.minY ?? 0) priorOffset=\(prior?.offset ?? 0) proofOffset=\(proof.offset) nativeOffset=\(before) dragging=\(scrollView.isDragging) tracking=\(scrollView.isTracking) decelerating=\(scrollView.isDecelerating) velocityY=\(velocity) delta=\(delta)")
        }
        #endif
        adjust(by: delta)
        correctedOffset = scrollView.contentOffset.y
        visualWitness = (proof.cardID, proof.frame.minY - delta + proof.offset - before, correctedOffset)
        appliedCount += 1
        maximumResidual = max(maximumResidual, abs(delta - (scrollView.contentOffset.y - before)))
        #if DEBUG
        if FeedVisualCapture.tracesCapture {
            Logger(subsystem: "com.feedmine.development", category: "native-capture").info(
                "window correction card=\(proof.cardID.rawValue.uuidString, privacy: .public) delta=\(delta) offsetBefore=\(before) offsetAfter=\(scrollView.contentOffset.y) draggingAfter=\(scrollView.isDragging) deceleratingAfter=\(scrollView.isDecelerating)")
        }
        #endif
        #if DEBUG
        if FeedVisualCapture.tracesCapture {
            DispatchQueue.main.async { [weak scrollView] in
                guard let scrollView else { return }
                Logger(subsystem: "com.feedmine.development", category: "native-capture").info(
                    "correction next turn offset=\(scrollView.contentOffset.y) dragging=\(scrollView.isDragging) decelerating=\(scrollView.isDecelerating)")
            }
        }
        #endif
        return true
    }
    /// One-shot restore: move the native viewport by the remaining delta once the anchor card has been
    /// aligned. A reader gesture owns the offset; it is never postponed and never pushed back after.
    @discardableResult
    func applyRestoration(_ delta: CGFloat) -> Bool {
        guard delta.isFinite, abs(delta) > 0.5, !nativeGestureActive, let scrollView else { return false }
        let before = scrollView.contentOffset.y
        adjust(by: delta)
        return abs(scrollView.contentOffset.y - before) > 0.01
    }

    private func adjust(by delta: CGFloat) {
        guard let scrollView, delta.isFinite else { return }
        let offset = scrollView.contentOffset
        // Defense at the write boundary as well: no native offset writes during tracking,
        // drag or deceleration, and no timer/queued delta applied after the gesture.
        guard !nativeGestureActive else { return }
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
                if let scroll = view as? UIScrollView {
                    access.scrollView = scroll
                    log(scroll)
                    return
                }
                ancestor = view.superview
            }
        }
        /// TEMPORARY Release liveness diagnostic. Logging only.
        private func log(_ scroll: UIScrollView) {
            NSLog("FEEDMINE_LIVENESS probe scroll=%@ frame=%@ bounds=%@ contentSize=%@ inset=%@ enabled=%d offset=%.2f pan=%ld",
                String(describing: ObjectIdentifier(scroll)), NSStringFromCGRect(scroll.frame),
                NSStringFromCGRect(scroll.bounds), NSStringFromCGSize(scroll.contentSize),
                String(describing: scroll.contentInset), scroll.isScrollEnabled ? 1 : 0,
                scroll.contentOffset.y, scroll.panGestureRecognizer.state.rawValue)
        }
    }
}
#if DEBUG
struct FeedNativeWindowProof: ViewModifier {
    let ids: [PublicationCardID]
    let access: FeedNativeScrollOffset
    let deferredWindows: Int
    /// How many times the feed surface has re-evaluated in this process. DEBUG evidence, deliberately a
    /// plain counter: the number the scroll-stability work is judged by is "how often does the surface
    /// rebuild per fling", and without it that cost is argued instead of measured.
    nonisolated(unsafe) static var surfaceEvaluations = 0
    func body(content: Content) -> some View {
        FeedNativeWindowProof.surfaceEvaluations += 1
        return content.overlay(alignment: .topLeading) {
            if FeedVisualCapture.tracesCapture {
                Text("ids=\(ids.map { $0.rawValue.uuidString }.joined(separator: ","));corrections=\(access.appliedCount);residual=\(access.maximumResidual);measured=\(access.measuredCorrections);visualResidual=\(access.maximumVisualResidual);activeWrites=\(access.activeWrites);activeWindows=\(access.activeWindowChanges);activeLayoutSteps=\(access.activeLayoutSteps);activeLayoutStep=\(access.maximumActiveLayoutStep);deferredWindows=\(deferredWindows);surfaceEvals=\(FeedNativeWindowProof.surfaceEvaluations);geom=\(FeedVisualCapture.geometryObservations);probes=\(FeedVisualCapture.probeEntries);guards=\(FeedVisualCapture.probeGuards);cards=\(FeedVisualCapture.cardObservations);emits=\(FeedVisualCapture.emissions);submits=\(FeedVisualCapture.submissions);geomEvents=\(FeedVisualCapture.scrollGeometryEvents);phaseEvents=\(FeedVisualCapture.scrollPhaseEvents);scopeReject=\(FeedVisualCapture.scopeRejections);installs=\(FeedFlowCounters.installAttempts)/\(FeedFlowCounters.installAccepts)/\(FeedFlowCounters.installRejects)")
                    .font(.system(size: 1)).frame(width: 1, height: 1).opacity(0)
                    .allowsHitTesting(false).accessibilityIdentifier("feed-window-proof")
            }
        }
    }
}
#endif
#endif
