// Real visual inputs terminate at the store callback; executable composition is external.
import SwiftUI
#if DEBUG
import OSLog
#endif
import FeedMineDomain
import FeedMineRuntime

@MainActor
public struct FeedScreen: View {
    private let store: FeedScreenStore
    /// The frozen visual system for this session. It is an immutable host input, never internal
    /// observable state: an appearance change is an explicit decision, not an effect of this view.
    private let appearance: ReaderAppearance
    /// The host's own status chip (V1's `CompactFeedStatus` equivalent). Nil renders the delivery's
    /// default, which states only what the presentation value knows.
    private let customStatusChip: AnyView?
    /// The host's filter lens (V1's chip bar). Nil draws nothing above the feed.
    private let lens: AnyView?
    /// Whether the reader's accepted selection has any sources at all, and what to do about it. It is the
    /// host's fact: this view owns no selection. An empty selection is not a preparation and not a failure —
    /// it is V1's own empty surface, so it takes precedence over both.
    private let hasSources: Bool
    private let onChooseSources: @MainActor () -> Void
    /// R3: the host's recovery actions for the absence surface. "Tentar novamente" runs a real
    /// attempt and "Ajustar interesses" opens the flow that owns the reader's interests; this view
    /// executes neither.
    private let onTryAgain: @MainActor () -> Void
    private let onAdjustInterests: @MainActor () -> Void
    /// The host's editorial row: offered between cards, and only where the host says there is something truthful
    /// to ask. Nil — or a nil answer for a card — draws nothing, so the feed surface never invents an offer.
    private let editorial: (@MainActor (PresentationCard, Int, PresentationCard?) -> AnyView?)?
    @State private var capture = FeedVisualCapture()

    public init(store: FeedScreenStore, appearance: ReaderAppearance = .standard,
        statusChip: AnyView? = nil, lens: AnyView? = nil, hasSources: Bool = true,
        onChooseSources: @escaping @MainActor () -> Void = {},
        onTryAgain: @escaping @MainActor () -> Void = {},
        onAdjustInterests: @escaping @MainActor () -> Void = {},
        editorial: (@MainActor (PresentationCard, Int, PresentationCard?) -> AnyView?)? = nil) {
        self.store = store
        self.appearance = appearance
        self.customStatusChip = statusChip
        self.lens = lens
        self.hasSources = hasSources
        self.onChooseSources = onChooseSources
        self.onTryAgain = onTryAgain
        self.onAdjustInterests = onAdjustInterests
        self.editorial = editorial
    }

    public var body: some View {
        // The reader's chrome belongs to the feed surface: before the first presentation there is no
        // feed to read, so the preparation state keeps its own full-screen surface (V1 too drew its
        // header for the session, and T11 owns the preparation experience).
        if !hasSources {
            // V1 drew this surface instead of the feed, with the reader's chrome: nothing is being prepared,
            // so there is no progress to state.
            ReaderShell(store: store, appearance: appearance, status: { statusChip },
                lens: { if let lens { lens } }) {
                FeedSourcesEmptyStateView(appearance: appearance, onChooseSources: onChooseSources)
            }
        } else if store.state.presentation != nil {
            ReaderShell(store: store, appearance: appearance, status: { statusChip },
                lens: { if let lens { lens } }) {
                feedBody
            }
        } else {
            FeedLoadingView(work: store.state.work, onTryAgain: { onTryAgain() },
                onAdjustInterests: { onAdjustInterests() })
        }
    }

    /// The chip states the reader's situation. The host can replace it (T5 hook) because the host owns
    /// the counters; this default states only what the presentation value knows.
    @ViewBuilder private var statusChip: some View {
        if let customStatusChip { customStatusChip } else { FeedWorkBadge(work: store.state.work) }
    }

    private var workFeedback: some View { FeedWorkFeedback(work: store.state.work) }

    @ViewBuilder private var feedBody: some View {
        if let presentation = capture.interaction.presentation(for: store) {
            if #available(iOS 18, macOS 15, *) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: FeedDesignTokens.Spacing.section) {
                        ForEach(Array(presentation.window.items.enumerated()), id: \.element.id) { index, card in
                          // A Group is transparent for layout: the card keeps the geometry the capture measures,
                          // and the host's row is simply the next child of the stack.
                            Group {
                              FeedItemView(card: card, appearance: appearance,
                                isBookmarked: store.bookmarkedIDs.contains(card.id),
                                availableActions: store.availableActions,
                                onAction: { store.perform($0, rendered: presentation) })
                                .onGeometryChange(for: FeedVisualCardGeometry?.self, of: { proxy in
                                    guard let bounds = proxy.bounds(of: .scrollView(axis: .vertical)) else { return nil }
                                    let frame = proxy.frame(in: .scrollView(axis: .vertical))
                                    let local = proxy.frame(in: .named("feed-visual-content"))
                                    return .init(cardID: card.id, frame: frame,
                                        offset: local.minY - frame.minY, height: bounds.height)
                                }) { proof in
                                    guard capture.interaction.presentation(for: store)?.window == presentation.window,
                                        store.state.presentation?.editionID == presentation.editionID,
                                        store.state.presentation?.contextKey == presentation.contextKey,
                                        let proof, presentation.window.items.contains(where: { $0.id == proof.cardID }) else { return }
                                    #if canImport(UIKit)
                                    if capture.nativeScrollOffset.observe(proof) {
                                        return
                                    }
                                    #endif
                                    if let event = capture.observeCard(proof,
                                        isLast: store.state.presentation?.window.items.last?.id == proof.cardID) {
                                        store.submitViewport(event.observation, activity: event.activity, rendered: presentation)
                                    }
                                    if let event = capture.settle() {
                                        store.submitViewport(event.observation, activity: event.activity, rendered: presentation)
                                    }
                                }
                            if let row = editorial?(card, index, index > 0 ? presentation.window.items[index - 1] : nil) { row }
                          }
                        }
                    }
                    #if canImport(UIKit)
                    .background(FeedNativeScrollProbe(access: capture.nativeScrollOffset, ids: presentation.window.items.map(\.id)))
                    #endif
                    .modifier(NativeFeedTargets())
                    // U1-F: one FeedScreen for every device; wide displays keep a readable column
                    // instead of stretching editorial text across the window.
                    .frame(maxWidth: FeedDesignTokens.Measurement.readableContentWidth)
                    .frame(maxWidth: .infinity)
                }
                .modifier(NativeFeedViewport(capture: $capture, store: store, presented: presentation))
                #if DEBUG && canImport(UIKit)
                .modifier(FeedNativeWindowProof(ids: presentation.window.items.map(\.id), access: capture.nativeScrollOffset, deferredWindows: capture.interaction.deferredWindows))
                #endif
                // T3: work feedback is an overlay of constant height that never takes touches, so the
                // scroll viewport keeps exactly the geometry the reader was admitted into.
                .overlay(alignment: .bottom) { workFeedback }
            } else {
                // macOS 14 renders local cards without automatic viewport capture.
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: FeedDesignTokens.Spacing.section) {
                        ForEach(Array(presentation.window.items.enumerated()), id: \.element.id) { index, card in
                            Group {
                                FeedItemView(card: card, appearance: appearance,
                                    isBookmarked: store.bookmarkedIDs.contains(card.id),
                                    availableActions: store.availableActions,
                                    onAction: { store.perform($0, rendered: presentation) })
                                if let row = editorial?(card, index, index > 0 ? presentation.window.items[index - 1] : nil) { row }
                            }
                        }
                    }
                    .padding(FeedDesignTokens.Spacing.page)
                    .frame(maxWidth: FeedDesignTokens.Measurement.readableContentWidth)
                    .frame(maxWidth: .infinity)
                }
                // T3: work feedback is an overlay of constant height that never takes touches, so the
                // scroll viewport keeps exactly the geometry the reader was admitted into.
                .overlay(alignment: .bottom) { workFeedback }
            }
        } else {
            FeedLoadingView(work: store.state.work, onTryAgain: { onTryAgain() },
                onAdjustInterests: { onAdjustInterests() })
        }
    }
}

/// Reserved, non-interactive work feedback (T3): constant height, no hit testing, so reporting work can
/// never change the scroll geometry the reader was admitted into.
@MainActor
struct FeedWorkFeedback: View {
    let work: FeedPresentationState.Work
    var body: some View {
        FeedWorkBadge(work: work)
            .frame(height: FeedDesignTokens.Measurement.workFeedbackHeight, alignment: .bottom)
            .allowsHitTesting(false)
    }
}

/// Review M17: work that continues after cards are visible is shown without touching the cards.
struct FeedWorkBadge: View {
    let work: FeedPresentationState.Work
    var body: some View {
        switch work {
        case .pending, .preparing:
            Label("Buscando novidades", systemImage: "arrow.triangle.2.circlepath")
                .modifier(BadgeStyle())
        case .failed(let message):
            Label { Text(verbatim: message) } icon: { Image(systemName: "exclamationmark.triangle") }
                .modifier(BadgeStyle())
        case .idle, .unavailable, .deferred, .unreachable:
            EmptyView()
        }
    }
}

private struct BadgeStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.font(FeedDesignTokens.Typography.badge)
            .padding(.horizontal, FeedDesignTokens.Spacing.normal)
            .padding(.vertical, FeedDesignTokens.Spacing.compact)
            .background(.thinMaterial, in: Capsule())
            .padding(.bottom, FeedDesignTokens.Spacing.compact)
    }
}

// Small derived geometry only: no published window, presentation or durable identity owner.
struct FeedVisualGeometry: Equatable {
    let offset: CGFloat
    let extent: CGFloat
    let height: CGFloat
    let width: CGFloat

    init(offset: CGFloat, extent: CGFloat, height: CGFloat, width: CGFloat = 0) {
        self.offset = offset
        self.extent = extent
        self.height = height
        self.width = width
    }
}

struct FeedVisualEvent: Equatable {
    let observation: ViewportObservation
    let activity: RunwayActivity
}

// One current visual proof and one borrowed render window for an active interaction.
// The store remains the sole canonical presentation; this never admits or retains history.
struct FeedVisualCardGeometry: Equatable, Sendable {
    let cardID: PublicationCardID
    let frame: CGRect
    let offset: CGFloat
    let height: CGFloat
}

// Internal for behavioral architecture tests; no public navigation contract.
@MainActor
struct FeedVisualCapture {
    #if canImport(UIKit)
    let nativeScrollOffset = FeedNativeScrollOffset()
    #endif
    var interaction = FeedInteractionPresentation()
    var renderOwner: ObjectIdentifier?
    var reading = false
    var positionID: PublicationCardID?
    var readerCardID: PublicationCardID?
    private(set) var direction: RunwayActivity?
    private(set) var geometry: FeedVisualGeometry?
    private(set) var lastEmission: FeedVisualEvent?
    private var visibleProof: FeedVisualCardGeometry?
    private(set) var priorProof: FeedVisualCardGeometry?
    // Each stream contributes its own latest direction; endpoints are not synchronized.
    private var geometryMotion: RunwayActivity?
    private var cardMotion: RunwayActivity?
    private var confirmedOffset: CGFloat?
    private var tailOffset: CGFloat?
    private var settled = false
    private var tailReported = false
    // Diagnostic only: an unverified vector is never a direction authority or a global veto.
    private(set) var velocityUnverified = false
    #if DEBUG
    /// Traço de diagnóstico do capture, **desligado por padrão** (ordem do arquiteto): liga com
    /// `FEEDMINE_TRACE_CAPTURE=1`. A medição de posição precisa dele; a operação normal não paga o custo — uma
    /// corrida de UI com o traço ligado passa de 1,4 milhão de linhas de log.
    static let tracesCapture = ProcessInfo.processInfo.environment["FEEDMINE_TRACE_CAPTURE"] == "1"
    private var geometryLogged = false
    #endif

    mutating func phase(active: Bool, velocity: CGVector?) {
        if active && !reading {
            geometryMotion = nil
            cardMotion = nil
        }
        reading = active
        velocityUnverified = velocity.map { $0.dx != 0 || $0.dy != 0 } ?? false
        #if DEBUG
        Self.trace("native phase active=\(active) velocityUnverified=\(velocityUnverified) vector=\(String(describing: velocity))")
        #endif
    }

    /// Transient visual position of the reader: one card and how much of it is above the viewport.
    /// UI state only — it never decides admission (the session does) and is never persisted.
    var position: FeedScrollPosition? {
        guard let proof = visibleProof else { return nil }
        return FeedScrollPosition(cardID: proof.cardID, viewportTop: 0, cardTop: proof.frame.minY,
            cardHeight: proof.height)
    }

    mutating func invalidateLayout() {
        geometry = nil
        visibleProof = nil
        priorProof = nil
        geometryMotion = nil
        cardMotion = nil
        confirmedOffset = nil
        tailOffset = nil
        settled = false
        tailReported = false
        #if DEBUG
        geometryLogged = false
        #endif
    }

    mutating func observe(_ next: FeedVisualGeometry) -> FeedVisualEvent? {
        #if DEBUG
        if !geometryLogged {
            Self.trace("native geometry offset=\(next.offset) extent=\(next.extent) height=\(next.height)")
            geometryLogged = true
        }
        #endif
        let previous = geometry
        geometry = next
        guard let previous else { return nil }
        guard previous.extent == next.extent, previous.height == next.height, previous.width == next.width else {
            invalidateLayout()
            geometry = next
            return nil
        }
        if next.offset != previous.offset {
            confirmedOffset = nil
            if reading {
                geometryMotion = next.offset > previous.offset ? .forward : .backward
            } else {
                geometryMotion = nil
                cardMotion = nil
            }
        }
        return reconsider()
    }

    mutating func observeCard(_ proof: FeedVisualCardGeometry, isLast: Bool = false) -> FeedVisualEvent? {
        #if DEBUG
        // Traço por carta e por leitura, com o id, **só com a flag de diagnóstico ligada**: a coordenada de conteúdo
        // (`frameY + offset`) é imune ao gesto, então uma descontinuidade nela é o deslocamento causado pela
        // ATUALIZAÇÃO da janela — a referência que o arquiteto definiu, medida sem estimar alturas.
        if Self.tracesCapture {
            Self.trace("native card observed id=\(proof.cardID.rawValue.uuidString) frameY=\(proof.frame.minY) "
                + "offset=\(proof.offset) height=\(proof.height)")
        }
        #endif
        let intersects = proof.frame.height > 0 && proof.frame.maxY > 0 && proof.frame.minY < proof.height
        if isLast { tailOffset = intersects ? proof.offset : nil }
        if let old = priorProof, old.cardID == proof.cardID {
            let stable = old.frame.size == proof.frame.size && old.height == proof.height &&
                abs((old.frame.minY + old.offset) - (proof.frame.minY + proof.offset)) <= 0.5
            if !stable {
                confirmedOffset = nil
                geometryMotion = nil
                cardMotion = nil
            } else if old.frame.minY != proof.frame.minY, reading || geometryMotion != nil {
                cardMotion = proof.frame.minY < old.frame.minY ? .forward : .backward
            }
        }
        // Only one actual reference card; its invariant content coordinate distinguishes layout.
        let reference = min(proof.height / 2, max(0, (geometry?.extent ?? proof.height) - proof.offset - 16.5))
        if intersects, proof.frame.minY - 8 <= reference, proof.frame.maxY + 8 > reference {
            priorProof = proof
            visibleProof = proof
        } else if visibleProof?.cardID == proof.cardID {
            visibleProof = nil
        }
        return reconsider()
    }

    mutating func settle() -> FeedVisualEvent? {
        guard !reading, !settled, let old = lastEmission, old.activity != .stationary,
            let geometry, confirmedOffset == geometry.offset,
            let proof = visibleProof, proof.cardID == old.observation.anchor.cardID,
            proof.height == geometry.height else { return nil }
        let event = FeedVisualEvent(observation: old.observation, activity: .stationary)
        lastEmission = event
        readerCardID = event.observation.anchor.cardID
        settled = true
        #if DEBUG
        Self.trace("semantic viewport emitted activity=stationary anchor=\(proof.cardID)")
        #endif
        return event
    }

    mutating func reconsider() -> FeedVisualEvent? {
        guard let geometry else { return nil }
        if let global = geometryMotion, let visual = cardMotion, global == visual {
            direction = global
            confirmedOffset = geometry.offset
            settled = false
            tailReported = false
            geometryMotion = nil
            cardMotion = nil
        }
        guard let direction, confirmedOffset == geometry.offset,
            let proof = visibleProof, proof.height == geometry.height else { return nil }
        // A late tail may upgrade the same anchor. An older tail cannot upgrade a newer anchor.
        let tailVisible = tailOffset.map { $0 >= proof.offset } ?? false
        let activity: RunwayActivity = direction == .forward &&
            (tailVisible || geometry.offset + geometry.height >= geometry.extent)
            ? .explicitTailApproach : direction
        if settled {
            guard activity == .explicitTailApproach, !tailReported,
                proof.cardID == lastEmission?.observation.anchor.cardID else { return nil }
        }
        if activity == .explicitTailApproach { tailReported = true }
        let event = FeedVisualEvent(observation: .init(anchor: .init(cardID: proof.cardID, placement: .center)), activity: activity)
        guard event != lastEmission else { return nil }
        lastEmission = event
        readerCardID = event.observation.anchor.cardID
        #if DEBUG
        Self.trace("semantic viewport emitted activity=\(activity) anchor=\(proof.cardID)")
        #endif
        return event
    }

    #if DEBUG
    private static func trace(_ value: String) {
        Logger(subsystem: "com.feedmine.development", category: "native-capture").info("\(value, privacy: .public)")
    }
    #endif

}

@available(iOS 18, macOS 15, *)
private struct NativeFeedViewport: ViewModifier {
    @Binding var capture: FeedVisualCapture
    let store: FeedScreenStore
    let presented: FeedPresentationSnapshot?

    private var matchesScope: Bool {
        guard let current = store.state.presentation, let presented else { return false }
        return capture.renderOwner == ObjectIdentifier(store) &&
            capture.interaction.presentation(for: store)?.window == presented.window &&
            current.contextKey == presented.contextKey && current.editionID == presented.editionID &&
            current.provenance.sequenceID == presented.provenance.sequenceID
    }

    // Card bounds use the container viewport; visibleRect may also include safe-area insets.
    private func visualGeometry(_ geometry: ScrollGeometry) -> FeedVisualGeometry {
        .init(offset: geometry.contentOffset.y + geometry.contentInsets.top,
            extent: geometry.contentSize.height,
            height: geometry.containerSize.height,
            width: geometry.containerSize.width)
    }

    func body(content: Content) -> some View {
        return content
            .id(store.state.presentation?.editionID)
            .id(store.state.presentation?.contextKey)
            .scrollPosition(id: Binding(get: { capture.positionID ?? presented?.window.anchor.cardID }, set: { id in
                guard matchesScope, let id, presented?.window.items.contains(where: { $0.id == id }) == true else { return }
                capture.positionID = id
                capture.readerCardID = id
            }))
            .onScrollPhaseChange { oldPhase, phase, context in
                guard matchesScope else { return }
                #if DEBUG
                if FeedVisualCapture.tracesCapture {
                    Logger(subsystem: "com.feedmine.development", category: "native-capture").info("native SwiftUI phase=\(String(describing: oldPhase), privacy: .public)->\(String(describing: phase), privacy: .public)")
                }
                #endif
                if phase != .idle {
                    capture.interaction.begin(presented, owner: ObjectIdentifier(store))
                } else {
                    let reader = capture.position?.cardID ?? capture.readerCardID
                    if capture.interaction.isHolding, let reader, let presented, let current = store.state.presentation,
                        !current.window.items.contains(where: { $0.id == reader }) {
                        store.submitViewport(.init(anchor: .init(cardID: reader, placement: .top)),
                            activity: .stationary, rendered: presented, reconciliation: true)
                    }
                    capture.interaction.end(afterReading: reader, store: store)
                }
                store.setReadingInteractionActive(phase != .idle || capture.interaction.isHolding)
                #if canImport(UIKit)
                capture.nativeScrollOffset.setInteractionActive(phase != .idle)
                #endif
                let wasReading = oldPhase == .interacting || oldPhase == .decelerating
                let isReading = phase == .interacting || phase == .decelerating
                #if canImport(UIKit)
                if phase == .tracking { capture.nativeScrollOffset.cancel(discardingSamples: false) }
                else if capture.nativeScrollOffset.isCorrecting {
                    capture.reading = isReading
                    capture.invalidateLayout()
                    _ = capture.observe(visualGeometry(context.geometry))
                    return
                }
                #endif
                if (!wasReading && isReading) || phase == .animating || phase == .tracking {
                    capture.invalidateLayout()
                }
                capture.phase(active: (wasReading || isReading) && phase != .animating && phase != .tracking, velocity: context.velocity)
                let geometry = context.geometry
                if let event = capture.observe(visualGeometry(geometry)) {
                    store.submitViewport(event.observation, activity: event.activity, rendered: presented)
                }
                capture.reading = isReading
                if phase == .animating || phase == .tracking { capture.invalidateLayout() }
                if phase == .idle, let event = capture.settle() {
                    store.submitViewport(event.observation, activity: event.activity, rendered: presented)
                }
            }
            .onScrollGeometryChange(for: FeedVisualGeometry.self, of: { geometry in
                visualGeometry(geometry)
            }) { _, geometry in
                guard matchesScope else { return }
                #if canImport(UIKit)
                if capture.nativeScrollOffset.isCorrecting {
                    capture.invalidateLayout()
                    _ = capture.observe(geometry)
                    return
                }
                #endif
                if let event = capture.observe(geometry) {
                    store.submitViewport(event.observation, activity: event.activity, rendered: presented)
                }
            }
            .onChange(of: presented?.window) { old, new in
                // A new layout must establish a fresh viewport proof. Native offset correction
                // is handled independently, before card geometry becomes a reader event.
                capture.invalidateLayout()
            }
            .onChange(of: store.state.presentation?.window) { _, _ in
                capture.interaction.noteIncoming(store)
            }
            .onChange(of: ObjectIdentifier(store), initial: true) { _, _ in
                capture.renderOwner = ObjectIdentifier(store)
            }
            .onDisappear {
                guard matchesScope else { return }
                capture.interaction.end()
                store.setReadingInteractionActive(false)
                #if canImport(UIKit)
                capture.nativeScrollOffset.setInteractionActive(false)
                capture.nativeScrollOffset.cancel()
                #endif
            }
            .onChange(of: ObjectIdentifier(store)) { _, _ in
                capture = FeedVisualCapture()
                capture.renderOwner = ObjectIdentifier(store)
                store.setReadingInteractionActive(false)
            }
            .onChange(of: store.state.presentation?.editionID) { _, _ in
                capture = FeedVisualCapture()
                capture.renderOwner = ObjectIdentifier(store)
                store.setReadingInteractionActive(false)
            }
            .onChange(of: store.state.presentation?.contextKey) { _, _ in
                capture = FeedVisualCapture()
                capture.renderOwner = ObjectIdentifier(store)
                store.setReadingInteractionActive(false)
            }
    }
}

@available(iOS 18, macOS 15, *)
private struct NativeFeedTargets: ViewModifier {
    func body(content: Content) -> some View {
        content.scrollTargetLayout().padding().coordinateSpace(name: "feed-visual-content")
    }
}
