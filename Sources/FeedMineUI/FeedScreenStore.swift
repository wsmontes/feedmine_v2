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
    /// What this host can actually execute. A card renders only these controls, so a menu item can
    /// never be a dead control while its delivery (T5–T11) has not landed yet.
    public let availableActions: Set<ReaderCardAction>
    @ObservationIgnored private let onAction: @MainActor (ReaderCardActionEvent) -> Void

    /// `onAction` receives one semantic request per user interaction (review F10): the occurrence and
    /// what the reader asked for. No URL, player, pasteboard or sheet crosses into UI; external
    /// composition resolves them from published history.
    public init(onViewport: @escaping @MainActor (ViewportObservation, RunwayActivity) -> Void,
        availableActions: Set<ReaderCardAction> = Set(ReaderCardAction.allCases),
        onAction: @escaping @MainActor (ReaderCardActionEvent) -> Void = { _ in }) {
        state = FeedPresentationState(presentation: nil)
        self.onViewport = onViewport
        self.availableActions = availableActions
        self.onAction = onAction
    }

    public func installBookmarks(_ ids: Set<PublicationCardID>) { bookmarkedIDs = ids }

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

    /// One semantic request from one admitted card. Only an admitted occurrence may act, and the
    /// external consumer decides how to execute it.
    public func perform(_ event: ReaderCardActionEvent) {
        guard state.presentation?.window.items.contains(where: { $0.id == event.cardID }) == true else { return }
        guard availableActions.contains(event.action) else { return }
        onAction(event)
    }
}
