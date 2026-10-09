// Real visual inputs terminate at the store callback; executable composition is external.
import SwiftUI
import FeedMineDomain
import FeedMineRuntime

@MainActor
public struct FeedScreen: View {
    private let store: FeedScreenStore
    @State private var capture = FeedVisualCapture()

    public init(store: FeedScreenStore) {
        self.store = store
    }

    public var body: some View {
        if let presentation = store.state.presentation {
            if #available(iOS 18, macOS 15, *) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(presentation.window.items) { card in
                            FeedCardView(card: card)
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
                }
                .modifier(NativeFeedViewport(capture: $capture, store: store))
            } else {
                // macOS 14 renders local cards without automatic viewport capture.
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(presentation.window.items) { card in
                            FeedCardView(card: card)
                        }
                    }
                    .padding()
                }
            }
        } else {
            FeedLoadingView(work: store.state.work)
        }
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
    private var geometryFrom: CGFloat?
    private var geometryTo: CGFloat?
    private var cardFrom: CGFloat?
    private var cardTo: CGFloat?
    private var confirmedOffset: CGFloat?
    private var tailOffset: CGFloat?
    private var settled = false
    private var tailReported = false
    // The native vector orientation remains unverified; nonzero vectors are ambiguous.
    private(set) var velocityUnverified = false

    mutating func phase(active: Bool, velocity: CGVector?) {
        if active && !reading {
            geometryFrom = nil
            geometryTo = nil
            cardFrom = nil
            cardTo = nil
        }
        reading = active
        velocityUnverified = velocity.map { $0.dx != 0 || $0.dy != 0 } ?? false
        if velocityUnverified {
            geometryFrom = nil
            geometryTo = nil
            cardFrom = nil
            cardTo = nil
            confirmedOffset = nil
        }
        if !active { geometryFrom = nil; geometryTo = nil }
    }

    mutating func invalidateLayout() {
        geometry = nil
        visibleProof = nil
        priorProof = nil
        geometryFrom = nil
        geometryTo = nil
        cardFrom = nil
        cardTo = nil
        confirmedOffset = nil
        tailOffset = nil
        settled = false
        tailReported = false
    }

    mutating func observe(_ next: FeedVisualGeometry) -> FeedVisualEvent? {
        let previous = geometry
        geometry = next
        guard let previous else { return nil }
        guard previous.extent == next.extent, previous.height == next.height, previous.width == next.width else {
            invalidateLayout()
            geometry = next
            return nil
        }
        if !reading, next.offset != previous.offset {
            confirmedOffset = nil
            geometryFrom = nil
            geometryTo = nil
            cardFrom = nil
            cardTo = nil
        }
        if reading, !velocityUnverified, next.offset != previous.offset {
            if let from = geometryFrom,
                (previous.offset - from) * (next.offset - previous.offset) < 0 {
                geometryFrom = previous.offset
                cardFrom = nil
                cardTo = nil
            }
            geometryFrom = geometryFrom ?? previous.offset
            geometryTo = next.offset
            confirmedOffset = nil
        }
        return reconsider()
    }

    mutating func observeCard(_ proof: FeedVisualCardGeometry, isLast: Bool = false) -> FeedVisualEvent? {
        let intersects = proof.frame.height > 0 && proof.frame.maxY > 0 && proof.frame.minY < proof.height
        if isLast { tailOffset = intersects ? proof.offset : nil }
        if let old = priorProof, old.cardID == proof.cardID,
            (old.frame.size != proof.frame.size || old.height != proof.height ||
                abs((old.frame.minY + old.offset) - (proof.frame.minY + proof.offset)) > 0.5) {
            confirmedOffset = nil
            geometryFrom = nil
            geometryTo = nil
            cardFrom = nil
            cardTo = nil
        }
        if !velocityUnverified, let old = priorProof, old.cardID == proof.cardID,
            old.frame.size == proof.frame.size, old.height == proof.height,
            old.offset != proof.offset,
            abs((old.frame.minY + old.offset) - (proof.frame.minY + proof.offset)) <= 0.5 {
            if let from = cardFrom,
                (old.offset - from) * (proof.offset - old.offset) < 0 {
                cardFrom = old.offset
            }
            cardFrom = cardFrom ?? old.offset
            cardTo = proof.offset
        }
        // Retain only the reference card, including its last offscreen displacement.
        let reference = min(proof.height / 2, max(0, (geometry?.extent ?? proof.height) - proof.offset - 16.5))
        if intersects, proof.frame.minY - 8 <= reference, proof.frame.maxY + 8 > reference {
            priorProof = proof
            visibleProof = proof
        }
        return reconsider()
    }

    mutating func settle() -> FeedVisualEvent? {
        guard !reading, !settled, let old = lastEmission, old.activity != .stationary,
            let geometry, confirmedOffset == geometry.offset,
            let proof = visibleProof, proof.cardID == old.observation.anchor.cardID,
            abs(proof.offset - geometry.offset) <= 0.5, proof.height == geometry.height else { return nil }
        let event = FeedVisualEvent(observation: old.observation, activity: .stationary)
        lastEmission = event
        settled = true
        return event
    }

    mutating func reconsider() -> FeedVisualEvent? {
        guard !velocityUnverified, let geometry else { return nil }
        if geometryTo == cardTo, geometryTo != nil, geometryFrom != cardFrom {
            // The streams did not observe the same directional interval.
            geometryFrom = nil
            geometryTo = nil
            cardFrom = nil
            cardTo = nil
            return nil
        }
        if let from = geometryFrom, let to = geometryTo, from != to,
            cardFrom == from, cardTo == to, to == geometry.offset {
            direction = to > from ? .forward : .backward
            confirmedOffset = to
            settled = false
            tailReported = false
            geometryFrom = nil
            geometryTo = nil
            cardFrom = nil
            cardTo = nil
        }
        guard let direction, confirmedOffset == geometry.offset,
            let proof = visibleProof, abs(proof.offset - geometry.offset) <= 0.5,
            proof.height == geometry.height else { return nil }
        let activity: RunwayActivity = direction == .forward &&
            (tailOffset == geometry.offset || geometry.offset + geometry.height >= geometry.extent)
            ? .explicitTailApproach : direction
        if settled {
            guard activity == .explicitTailApproach, !tailReported,
                proof.cardID == lastEmission?.observation.anchor.cardID else { return nil }
        }
        if activity == .explicitTailApproach { tailReported = true }
        let event = FeedVisualEvent(observation: .init(anchor: .init(cardID: proof.cardID, placement: .center)), activity: activity)
        guard event != lastEmission else { return nil }
        lastEmission = event
        return event
    }
}

@available(iOS 18, macOS 15, *)
private struct NativeFeedViewport: ViewModifier {
    @Binding var capture: FeedVisualCapture
    let store: FeedScreenStore

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
                let wasReading = oldPhase == .interacting || oldPhase == .decelerating
                let isReading = phase == .interacting || phase == .decelerating
                if (!wasReading && isReading) || phase == .animating || phase == .tracking {
                    capture.invalidateLayout()
                }
                capture.phase(active: (wasReading || isReading) && phase != .animating && phase != .tracking, velocity: context.velocity)
                let geometry = context.geometry
                if let event = capture.observe(.init(offset: geometry.visibleRect.minY,
                    extent: geometry.contentSize.height, height: geometry.visibleRect.height,
                    width: geometry.containerSize.width)) {
                    store.submitViewport(event.observation, activity: event.activity)
                }
                capture.reading = isReading
                if phase == .animating || phase == .tracking { capture.invalidateLayout() }
                if phase == .idle, let event = capture.settle() {
                    store.submitViewport(event.observation, activity: event.activity)
                }
            }
            .onScrollGeometryChange(for: FeedVisualGeometry.self, of: { geometry in
                .init(offset: geometry.visibleRect.minY, extent: geometry.contentSize.height,
                    height: geometry.visibleRect.height, width: geometry.containerSize.width)
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
