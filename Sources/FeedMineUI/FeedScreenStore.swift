// Observable screen value and explicit semantic input forwarding.
// External composition supplies state and owns every execution opportunity.
import Observation
import FeedMineDomain
import FeedMineRuntime

@MainActor
@Observable
public final class FeedScreenStore {
    public private(set) var state: FeedPresentationState
    @ObservationIgnored
    private let onViewport: @MainActor (ViewportObservation, RunwayActivity) -> Void
    public private(set) var bookmarkedIDs: Set<PublicationCardID> = []
    @ObservationIgnored private let onBookmark: @MainActor (PublicationCardID) -> Void
    @ObservationIgnored
    private let onOpen: @MainActor (PublicationCardID) -> Void

    /// `onOpen` receives a semantic open intent (review F10). The action target itself never
    /// crosses into UI; external composition resolves it from published history.
    public init(onViewport: @escaping @MainActor (ViewportObservation, RunwayActivity) -> Void,
        onOpen: @escaping @MainActor (PublicationCardID) -> Void = { _ in },
        onBookmark: @escaping @MainActor (PublicationCardID) -> Void = { _ in }) {
        state = FeedPresentationState(presentation: nil)
        self.onViewport = onViewport
        self.onOpen = onOpen
        self.onBookmark = onBookmark
    }

    public func installBookmarks(_ ids: Set<PublicationCardID>) { bookmarkedIDs = ids }
    public func bookmark(_ card: PresentationCard) {
        guard state.presentation?.window.items.contains(where: { $0.id == card.id }) == true else { return }
        onBookmark(card.id)
    }

    /// Receives the value computed by external composition using the existing handoff.
    /// Reception delegates identity rules to the state contract; absence retains visible content.
    /// A rejected snapshot leaves the entire observable value unchanged.
    public func install(_ received: FeedPresentationState) throws {
        let presentationState: FeedPresentationState
        if let snapshot = received.presentation {
            presentationState = try state.receiving(snapshot)
        } else {
            presentationState = state
        }
        state = presentationState.reporting(received.work)
    }

    /// Emits one explicit user observation. The external consumer decides how to execute it.
    public func submitViewport(_ observation: ViewportObservation, activity: RunwayActivity) {
        onViewport(observation, activity)
    }

    /// The reader asked to open a card that offers a primary action.
    public func open(_ card: PresentationCard) {
        guard card.primaryActionKind != nil, state.presentation?.window.items.contains(where: { $0.id == card.id }) == true else { return }
        onOpen(card.id)
    }
}
