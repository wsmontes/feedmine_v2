// Observable screen value and explicit semantic input forwarding.
// External composition supplies state and owns every execution opportunity.
import Observation
import FeedMineDomain
import FeedMineRuntime

@MainActor
@Observable
public final class FeedScreenStore {
    public private(set) var state: FeedPresentationState
    /// Visual timing only. It never starts work or changes admission/publication.
    public private(set) var isReadingInteractionActive = false
    public func setReadingInteractionActive(_ active: Bool) { isReadingInteractionActive = active }
    @ObservationIgnored
    private let onViewport: @MainActor (ViewportObservation, RunwayActivity) -> Void
    @ObservationIgnored private let onRenderedViewport: (@MainActor (RenderedViewportEvidence, RunwayActivity) -> Void)?
    @ObservationIgnored private var viewportOrdinal: UInt64 = 0
    public private(set) var bookmarkedIDs: Set<PublicationCardID> = []
    /// What this host can actually execute. A card renders only these controls, so a menu item can
    /// never be a dead control while its delivery (T5–T11) has not landed yet.
    public let availableActions: Set<ReaderCardAction>
    /// Destinations this host can present today. The header's menu shows exactly these, and the host can
    /// install a narrower set at runtime: V1 showed two of its entries only inside a search or a filtered
    /// context, and that condition is the host's to state.
    public private(set) var availableDestinations: Set<ReaderDestination>
    /// Reader's search surface state. It is presentation state: the host decides what a submission means
    /// (T6 owns search as a context) and no submission here touches production.
    public private(set) var isSearching = false
    public private(set) var searchQuery = ""
    /// The one transient message the reader is showing. The host states it; the shell owns its lifetime.
    public private(set) var toast: ReaderToastMessage?
    /// Active filter count and bookmark-box selection: filled by T6 and T8. Zero/false means "none",
    /// never a fabricated state, so the header draws no badge until a delivery can prove one.
    public private(set) var filterCount = 0
    /// Whether the reader has committed a search term — V1's condition for saving it as a Smart Bookmark.
    public private(set) var hasCommittedSearch = false
    public private(set) var bookmarkBoxActive = false
    @ObservationIgnored private let onSubmitSearch: @MainActor (String) -> Void
    /// R15: cancelling the search is an intention the host must act on (restore the origin); the store only states it.
    @ObservationIgnored private let onCancelSearch: @MainActor () -> Void
    @ObservationIgnored private let onNavigate: @MainActor (ReaderDestination) -> Void
    @ObservationIgnored private let onAction: @MainActor (ReaderCardActionEvent) -> Void
    /// Onde o viewport desenhado começa, e se o desenho está em **repouso** nele. É o fato que o host usa para
    /// tornar a posição durável na hora; ver `publishPresentedPosition`. Este store não guarda a posição: ele
    /// repassa uma entrada explícita, como todas as outras, e quem é dono do cursor (a sessão) é quem lembra dela.
    @ObservationIgnored private let onPresentedPosition: (@MainActor (PresentationAnchor, Bool) -> Void)?

    /// Publica onde o viewport desenhado começa: o primeiro card cuja borda superior está dentro do viewport, preso
    /// à borda de cima. É uma posição que o leitor realmente teve na tela — inclusive quando a tela se moveu sem
    /// gesto nenhum (uma rolagem de acessibilidade, uma animação do sistema) —, e é ela que a durabilidade grava: o
    /// card em que o leitor *está* não determina o viewport (a distância da linha de referência da captura até a
    /// borda do card não faz parte de um registro que nunca carrega pixels), então uma restauração que o nomeasse
    /// podia desenhar o viewport do card vizinho (medido 2026-10-14, B05).
    ///
    /// `atRest` é o repouso semântico do próprio desenho (sem gesto, sem hold emprestado, sem animação
    /// programática): uma posição sob repouso é uma posição que o leitor realmente segura. Quem decide **quanto**
    /// isso custa é o dono do cursor (`FeedSession.notePresentedPosition(_:atRest:)`): uma posição já durável não é
    /// reescrita, e em movimento a janela declarada em `FeedSession.settledPositionDebounceWindow` segue valendo.
    public func publishPresentedPosition(_ anchor: PresentationAnchor, atRest: Bool) {
        onPresentedPosition?(anchor, atRest)
    }

    /// `onAction` receives one semantic request per user interaction (review F10): the occurrence and
    /// what the reader asked for. No URL, player, pasteboard or sheet crosses into UI; external
    /// composition resolves them from published history.
    public init(onViewport: @escaping @MainActor (ViewportObservation, RunwayActivity) -> Void,
        onRenderedViewport: (@MainActor (RenderedViewportEvidence, RunwayActivity) -> Void)? = nil,
        availableActions: Set<ReaderCardAction> = Set(ReaderCardAction.allCases),
        onAction: @escaping @MainActor (ReaderCardActionEvent) -> Void = { _ in },
        availableDestinations: Set<ReaderDestination> = [],
        onSubmitSearch: @escaping @MainActor (String) -> Void = { _ in },
        onCancelSearch: @escaping @MainActor () -> Void = {},
        onNavigate: @escaping @MainActor (ReaderDestination) -> Void = { _ in },
        onPresentedPosition: (@MainActor (PresentationAnchor, Bool) -> Void)? = nil) {
        state = FeedPresentationState(presentation: nil)
        self.onViewport = onViewport
        self.onRenderedViewport = onRenderedViewport
        self.availableActions = availableActions
        self.onAction = onAction
        self.availableDestinations = availableDestinations
        self.onSubmitSearch = onSubmitSearch
        self.onCancelSearch = onCancelSearch
        self.onNavigate = onNavigate
        self.onPresentedPosition = onPresentedPosition
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
        // The host owns the origin and its checkpoint; the store does not.
        onCancelSearch()
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

    /// The host's own reading of what the reader is doing: how many criteria are applied, and whether a search
    /// is committed. The header badges and V1's two conditional menu entries read exactly these.
    public func installContextFacts(filterCount: Int, hasCommittedSearch: Bool) {
        self.filterCount = max(0, filterCount)
        self.hasCommittedSearch = hasCommittedSearch
    }

    /// Replaces the destinations the menu offers. The entries themselves, their order and their labels stay
    /// V1's; only which of them apply is stated here.
    public func installDestinations(_ destinations: Set<ReaderDestination>) {
        availableDestinations = destinations
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
        // **Só o que a lista desenha é republicado.** A posição do leitor e a proveniência continuam em `state`,
        // que muda a cada avanço; a lista observa os itens, que mudam quando a janela muda. Sem isso, cada avanço
        // re-renderizava a lista inteira — 12–14 vezes por segundo numa rajada (medido no aparelho, 2026-10-14).
        // Princípio do dono: a UI é imediata; o backend corre atrás e se antecipa.
        let rendered = presentationState.presentation?.window.items
        if rendered != renderedItems { renderedItems = rendered ?? [] }
        if received.work != work { work = received.work }
        if presentationState.presentation?.editionID != renderedEditionID {
            renderedEditionID = presentationState.presentation?.editionID
        }
        if presentationState.presentation?.contextKey != renderedContextKey {
            renderedContextKey = presentationState.presentation?.contextKey
        }
    }

    /// O que a lista desenha, publicado **apenas quando muda**. Nenhuma leitura daqui depende da posição do leitor.
    public private(set) var renderedItems: [PresentationCard] = []
    public private(set) var renderedEditionID: FeedEditionID?
    public private(set) var renderedContextKey: ContextKey?
    /// O trabalho que a superfície está relatando, publicado **apenas quando muda** — pela mesma razão: a view lê
    /// isto, e não `state`, para que um avanço não a reavalie.
    public private(set) var work: FeedPresentationState.Work = .idle

    /// Emits one explicit user observation. The external consumer decides how to execute it.
    public func submitViewport(_ observation: ViewportObservation, activity: RunwayActivity,
        rendered: FeedPresentationSnapshot? = nil, reconciliation: Bool = false) {
        if let onRenderedViewport, let rendered {
            viewportOrdinal += 1
            guard let evidence = rendered.evidence(for: observation, ordinal: viewportOrdinal, reconciliation: reconciliation) else { return }
            onRenderedViewport(evidence, activity)
            return
        }
        onViewport(observation, activity)
    }

    /// One semantic request from one admitted card. Only an admitted occurrence may act, and the
    /// external consumer decides how to execute it.
    public func perform(_ event: ReaderCardActionEvent, rendered: FeedPresentationSnapshot? = nil) {
        if let rendered {
            guard let current = state.presentation,
                rendered.contextKey == current.contextKey, rendered.editionID == current.editionID,
                rendered.provenance.sequenceID == current.provenance.sequenceID,
                rendered.provenance.position <= current.provenance.position,
                rendered.window.items.contains(where: { $0.id == event.cardID }) else { return }
        } else {
            guard state.presentation?.window.items.contains(where: { $0.id == event.cardID }) == true else { return }
        }
        guard availableActions.contains(event.action) else { return }
        onAction(event)
    }
}
