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
    /// Destinations this host can present today. The header's menu shows exactly these.
    public let availableDestinations: Set<ReaderDestination>
    /// Reader's search surface state. It is presentation state: the host decides what a submission means
    /// (T6 owns search as a context) and no submission here touches production.
    public private(set) var isSearching = false
    public private(set) var searchQuery = ""
    /// The one transient message the reader is showing. The host states it; the shell owns its lifetime.
    public private(set) var toast: ReaderToastMessage?
    /// Active filter count and bookmark-box selection: filled by T6 and T8. Zero/false means "none",
    /// never a fabricated state, so the header draws no badge until a delivery can prove one.
    public private(set) var filterCount = 0
    public private(set) var bookmarkBoxActive = false
    @ObservationIgnored private let onSubmitSearch: @MainActor (String) -> Void
    @ObservationIgnored private let onNavigate: @MainActor (ReaderDestination) -> Void
    @ObservationIgnored private let onAction: @MainActor (ReaderCardActionEvent) -> Void

    /// `onAction` receives one semantic request per user interaction (review F10): the occurrence and
    /// what the reader asked for. No URL, player, pasteboard or sheet crosses into UI; external
    /// composition resolves them from published history.
    public init(onViewport: @escaping @MainActor (ViewportObservation, RunwayActivity) -> Void,
        availableActions: Set<ReaderCardAction> = Set(ReaderCardAction.allCases),
        onAction: @escaping @MainActor (ReaderCardActionEvent) -> Void = { _ in },
        availableDestinations: Set<ReaderDestination> = [],
        onSubmitSearch: @escaping @MainActor (String) -> Void = { _ in },
        onNavigate: @escaping @MainActor (ReaderDestination) -> Void = { _ in }) {
        state = FeedPresentationState(presentation: nil)
        self.onViewport = onViewport
        self.availableActions = availableActions
        self.onAction = onAction
        self.availableDestinations = availableDestinations
        self.onSubmitSearch = onSubmitSearch
        self.onNavigate = onNavigate
    }

    /// V1's menu order, limited to what this host can present.
    public var menuEntries: [ReaderMenuEntry] {
        ReaderMenuEntry.standard.filter { availableDestinations.contains($0.destination) }
    }

    // MARK: - Reader chrome (T5)

    public func toggleSearch() {
        isSearching.toggle()
        if !isSearching { searchQuery = "" }
    }

    /// One explicit search submission. The host decides what a term means; UI starts no work.
    public func submitSearch(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        searchQuery = trimmed
        guard !trimmed.isEmpty else { return }
        onSubmitSearch(trimmed)
    }

    public func cancelSearch() {
        isSearching = false
        searchQuery = ""
    }

    public func navigate(to destination: ReaderDestination) {
        guard availableDestinations.contains(destination) else { return }
        onNavigate(destination)
    }

    public func showToast(text: String, systemImage: String? = nil) {
        toast = ReaderToastMessage(text: text, systemImage: systemImage)
    }

    public func dismissToast() { toast = nil }

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
