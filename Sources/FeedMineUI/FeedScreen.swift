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
    @State private var capture = FeedVisualCapture()

    public init(store: FeedScreenStore, appearance: ReaderAppearance = .standard) {
        self.store = store
        self.appearance = appearance
    }

    public var body: some View {
        if let presentation = store.state.presentation {
            if #available(iOS 18, macOS 15, *) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: FeedDesignTokens.Spacing.section) {
                        ForEach(presentation.window.items) { card in
                            FeedItemView(card: card, appearance: appearance,
                                isBookmarked: store.bookmarkedIDs.contains(card.id),
                                availableActions: store.availableActions,
                                onAction: { store.perform($0) })
                                .onGeometryChange(for: FeedVisualCardGeometry?.self, of: { proxy in
                                    guard let bounds = proxy.bounds(of: .scrollView(axis: .vertical)) else { return nil }
                                    let frame = proxy.frame(in: .scrollView(axis: .vertical))
                                    let local = proxy.frame(in: .named("feed-visual-content"))
                                    return .init(cardID: card.id, frame: frame,
                                        offset: local.minY - frame.minY, height: bounds.height)
                                }) { proof in
                                    guard store.state.presentation?.window == presentation.window,
                                        store.state.presentation?.editionID == presentation.editionID,
                                        store.state.presentation?.contextKey == presentation.contextKey,
                                        let proof, store.state.presentation?.window.items.contains(where: { $0.id == proof.cardID }) == true else { return }
                                    if let event = capture.observeCard(proof,
                                        isLast: store.state.presentation?.window.items.last?.id == proof.cardID) {
                                        store.submitViewport(event.observation, activity: event.activity)
                                    }
                                    if let event = capture.settle() {
                                        store.submitViewport(event.observation, activity: event.activity)
                                    }
                                }
                        }
                    }
                    .modifier(NativeFeedTargets())
                    // U1-F: one FeedScreen for every device; wide displays keep a readable column
                    // instead of stretching editorial text across the window.
                    .frame(maxWidth: FeedDesignTokens.Measurement.readableContentWidth)
                    .frame(maxWidth: .infinity)
                }
                .modifier(NativeFeedViewport(capture: $capture, store: store))
                // T3: work feedback is an overlay of constant height that never takes touches, so the
                // scroll viewport keeps exactly the geometry the reader was admitted into.
                .overlay(alignment: .bottom) {
                    FeedWorkBadge(work: store.state.work)
                        .frame(height: FeedDesignTokens.Measurement.workFeedbackHeight, alignment: .bottom)
                        .allowsHitTesting(false)
                }
            } else {
                // macOS 14 renders local cards without automatic viewport capture.
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: FeedDesignTokens.Spacing.section) {
                        ForEach(presentation.window.items) { card in
                            FeedItemView(card: card, appearance: appearance,
                                isBookmarked: store.bookmarkedIDs.contains(card.id),
                                availableActions: store.availableActions,
                                onAction: { store.perform($0) })
                        }
                    }
                    .padding(FeedDesignTokens.Spacing.page)
                    .frame(maxWidth: FeedDesignTokens.Measurement.readableContentWidth)
                    .frame(maxWidth: .infinity)
                }
                // T3: work feedback is an overlay of constant height that never takes touches, so the
                // scroll viewport keeps exactly the geometry the reader was admitted into.
                .overlay(alignment: .bottom) {
                    FeedWorkBadge(work: store.state.work)
                        .frame(height: FeedDesignTokens.Measurement.workFeedbackHeight, alignment: .bottom)
                        .allowsHitTesting(false)
                }
            }
        } else {
            FeedLoadingView(work: store.state.work)
        }
    }
}

/// Review M17: work that continues after cards are visible is shown without touching the cards.
@MainActor
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
        case .idle, .unavailable, .deferred:
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

// One current visual proof, never a list of cards or a retained presentation.
struct FeedVisualCardGeometry: Equatable, Sendable {
    let cardID: PublicationCardID
    let frame: CGRect
    let offset: CGFloat
    let height: CGFloat
}

// Internal for behavioral architecture tests; no public navigation contract.
struct FeedVisualCapture {
    var reading = false
    var positionID: PublicationCardID?
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
    private var geometryLogged = false
    private var cardLogged = false
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
        cardLogged = false
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
        if !cardLogged {
            Self.trace("native card observed frameY=\(proof.frame.minY) offset=\(proof.offset) height=\(proof.height)")
            cardLogged = true
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

    // Card bounds use the container viewport; visibleRect may also include safe-area insets.
    private func visualGeometry(_ geometry: ScrollGeometry) -> FeedVisualGeometry {
        .init(offset: geometry.contentOffset.y + geometry.contentInsets.top,
            extent: geometry.contentSize.height,
            height: geometry.containerSize.height,
            width: geometry.containerSize.width)
    }

    func body(content: Content) -> some View {
        let presented = store.state.presentation
        return content
            .id(store.state.presentation?.editionID)
            .id(store.state.presentation?.contextKey)
            .scrollPosition(id: Binding(get: { capture.positionID ?? store.state.presentation?.window.anchor.cardID }, set: { id in
                guard let id, store.state.presentation?.window.items.contains(where: { $0.id == id }) == true else { return }
                capture.positionID = id
            }))
            .onScrollPhaseChange { oldPhase, phase, context in
                guard store.state.presentation == presented else { return }
                #if DEBUG
                Logger(subsystem: "com.feedmine.development", category: "native-capture").info("native SwiftUI phase=\(String(describing: oldPhase), privacy: .public)->\(String(describing: phase), privacy: .public)")
                #endif
                let wasReading = oldPhase == .interacting || oldPhase == .decelerating
                let isReading = phase == .interacting || phase == .decelerating
                if (!wasReading && isReading) || phase == .animating || phase == .tracking {
                    capture.invalidateLayout()
                }
                capture.phase(active: (wasReading || isReading) && phase != .animating && phase != .tracking, velocity: context.velocity)
                let geometry = context.geometry
                if let event = capture.observe(visualGeometry(geometry)) {
                    store.submitViewport(event.observation, activity: event.activity)
                }
                capture.reading = isReading
                if phase == .animating || phase == .tracking { capture.invalidateLayout() }
                if phase == .idle, let event = capture.settle() {
                    store.submitViewport(event.observation, activity: event.activity)
                }
            }
            .onScrollGeometryChange(for: FeedVisualGeometry.self, of: { geometry in
                visualGeometry(geometry)
            }) { _, geometry in
                guard store.state.presentation == presented else { return }
                if let event = capture.observe(geometry) {
                    store.submitViewport(event.observation, activity: event.activity)
                }
            }
            .onChange(of: store.state.presentation?.window) { _, _ in capture.invalidateLayout() }
            .onChange(of: store.state.presentation?.editionID) { _, _ in capture = FeedVisualCapture() }
            .onChange(of: store.state.presentation?.contextKey) { _, _ in capture = FeedVisualCapture() }
    }
}

@available(iOS 18, macOS 15, *)
private struct NativeFeedTargets: ViewModifier {
    func body(content: Content) -> some View {
        content.scrollTargetLayout().padding().coordinateSpace(name: "feed-visual-content")
    }
}
