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
    // When the edition/context replaces FeedVisualCapture, the offset adapter
    // and its counters reset. A process-unique token makes that reset visible
    // instead of mistaking a new adapter's first UIScrollView for the old one.
    let diagnosticCaptureID = UUID().uuidString
    // Debug-only counters: distinguish the native viewport being remounted from a
    // window/anchor change while the same UIScrollView remains attached.
    private(set) var probeMounts = 0
    private(set) var probeUnmounts = 0
    private(set) var distinctScrollViews = 0
    private var lastScrollIdentity: ObjectIdentifier?
    func noteProbeWindowMove(attached: Bool) {
        if attached { probeMounts += 1 } else { probeUnmounts += 1 }
    }
    func noteResolvedScroll(_ scroll: UIScrollView) {
        let identity = ObjectIdentifier(scroll)
        if lastScrollIdentity != identity {
            distinctScrollViews += 1
            lastScrollIdentity = identity
        }
    }
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
    func updateUIView(_ view: Probe, context: Context) {
        // SwiftUI may retain the UIView when a new FeedVisualCapture replaces
        // the old owner. Resolve the same native ancestor for the NEW adapter
        // immediately; waiting for layout leaves a stale or missing scroll proof.
        if view.access !== access {
            view.access.scrollView = nil
            view.access = access
            view.resolveScrollView()
        }
        access.updateWindow(ids)
    }

    final class Probe: UIView {
        var access: FeedNativeScrollOffset
        init(access: FeedNativeScrollOffset) {
            self.access = access
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            #if DEBUG
            access.noteProbeWindowMove(attached: window != nil)
            #endif
            resolveScrollView()
        }
        override func layoutSubviews() { super.layoutSubviews(); resolveScrollView() }
        func resolveScrollView() {
            // A detached UIView may keep its parent chain alive for a moment.
            // Never report that old scroll view as the native current viewport.
            guard window != nil else {
                access.scrollView = nil
                return
            }
            var ancestor = superview
            while let view = ancestor {
                if let scroll = view as? UIScrollView {
                    #if DEBUG
                    access.noteResolvedScroll(scroll)
                    #endif
                    access.scrollView = scroll
                    return
                }
                ancestor = view.superview
            }
            // The probe can be reparented before an ancestor ScrollView exists.
            // layoutSubviews will retry instead of retaining a stale adapter.
            access.scrollView = nil
        }
    }
}
#if DEBUG
struct FeedNativeWindowProof: ViewModifier {
    let ids: [PublicationCardID]
    let access: FeedNativeScrollOffset
    let deferredWindows: Int
    let store: FeedScreenStore
    @Binding var capture: FeedVisualCapture
    /// How many times the feed surface has re-evaluated in this process. DEBUG evidence, deliberately a
    /// plain counter: the number the scroll-stability work is judged by is "how often does the surface
    /// rebuild per fling", and without it that cost is argued instead of measured.
    nonisolated(unsafe) static var surfaceEvaluations = 0
    func body(content: Content) -> some View {
        FeedNativeWindowProof.surfaceEvaluations += 1
        return content.overlay(alignment: .topLeading) {
            if ProcessInfo.processInfo.environment["FEEDMINE_SAFARI_DIAGNOSTIC"] == "1" {
                FeedViewportDiagnosticReadout(access: access, store: store, capture: $capture)
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
            }
            if FeedVisualCapture.tracesCapture {
                Text("ids=\(ids.map { $0.rawValue.uuidString }.joined(separator: ","));corrections=\(access.appliedCount);residual=\(access.maximumResidual);measured=\(access.measuredCorrections);visualResidual=\(access.maximumVisualResidual);activeWrites=\(access.activeWrites);activeWindows=\(access.activeWindowChanges);activeLayoutSteps=\(access.activeLayoutSteps);activeLayoutStep=\(access.maximumActiveLayoutStep);deferredWindows=\(deferredWindows);surfaceEvals=\(FeedNativeWindowProof.surfaceEvaluations);geom=\(FeedVisualCapture.geometryObservations);probes=\(FeedVisualCapture.probeEntries);guards=\(FeedVisualCapture.probeGuards);cards=\(FeedVisualCapture.cardObservations);emits=\(FeedVisualCapture.emissions);submits=\(FeedVisualCapture.submissions);geomEvents=\(FeedVisualCapture.scrollGeometryEvents);phaseEvents=\(FeedVisualCapture.scrollPhaseEvents);scopeReject=\(FeedVisualCapture.scopeRejections);installs=\(FeedFlowCounters.installAttempts)/\(FeedFlowCounters.installAccepts)/\(FeedFlowCounters.installRejects)")
                    .font(.system(size: 1)).frame(width: 1, height: 1).opacity(0)
                    .allowsHitTesting(false).accessibilityIdentifier("feed-window-proof")
            }
        }
    }
}

/// A debug-only accessibility snapshot, computed when XCTest reads the property rather
/// than when SwiftUI last evaluated the view. Motion changes deliberately do not
/// invalidate the FeedScreen: a Text snapshot in its body would be stale by design.
private struct FeedViewportDiagnosticReadout: UIViewRepresentable {
    let access: FeedNativeScrollOffset
    let store: FeedScreenStore
    @Binding var capture: FeedVisualCapture

    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        configure(view)
        return view
    }
    func updateUIView(_ view: Probe, context: Context) { configure(view) }
    private func configure(_ view: Probe) {
        let state = $capture
        view.access = access
        view.store = store
        view.readCapture = { state.wrappedValue }
    }

    final class Probe: UIView {
        var access: FeedNativeScrollOffset?
        var store: FeedScreenStore?
        // FeedVisualCapture is @MainActor; preserve that isolation in the
        // escaping accessibility callback instead of erasing its actor contract.
        var readCapture: (@MainActor () -> FeedVisualCapture)?
        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isAccessibilityElement = true
            accessibilityIdentifier = "native-viewport-diagnosis"
            accessibilityLabel = "Native feed viewport diagnosis"
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

        // This read is passive: it never submits a viewport, changes an offset or
        // triggers publication. The fields isolate mount, window and cursor causes.
        override var accessibilityValue: String? {
            get {
                func card(_ id: PublicationCardID?) -> String { id?.rawValue.uuidString ?? "none" }
                let snapshot = store?.state.presentation
                let window = snapshot?.window
                let visual = readCapture?()
                let native = access?.scrollView
                let offset = native.map { String(format: "%.2f", Double($0.contentOffset.y)) } ?? "none"
                return [
                    "captureInstance=\(access?.diagnosticCaptureID ?? "none")",
                    "probeMounts=\(access?.probeMounts ?? -1)",
                    "probeUnmounts=\(access?.probeUnmounts ?? -1)",
                    "scrollInstances=\(access?.distinctScrollViews ?? -1)",
                    "scrollAttached=\(native?.window != nil)",
                    "scrollIdentity=\(native.map { String(describing: ObjectIdentifier($0)) } ?? "none")",
                    "nativeOffset=\(offset)",
                    "windowItems=\(window?.items.count ?? -1)",
                    "renderedItems=\(store?.renderedItems.count ?? -1)",
                    "windowHead=\(card(window?.items.first?.id))",
                    "windowTail=\(card(window?.items.last?.id))",
                    "windowAnchor=\(card(window?.anchor.cardID))",
                    "windowSequence=\(snapshot?.provenance.sequenceID.uuidString ?? "none")",
                    "windowRevision=\(snapshot.map { String(describing: $0.provenance.position) } ?? "none")",
                    "positionID=\(card(visual?.positionID))",
                    "presentedTop=\(card(visual?.motion.presentedTop))",
                    "acknowledgedTop=\(card(visual?.motion.acknowledgedPresentedTop))",
                    "holding=\(visual?.interaction.isHolding ?? false)"
                ].joined(separator: ";")
            }
            set { /* A diagnostic always reflects current reader state. */ }
        }
    }
}
#endif
#endif
