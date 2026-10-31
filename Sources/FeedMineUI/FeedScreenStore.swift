// Observable screen value and explicit semantic input forwarding.
// External composition supplies state and owns every execution opportunity.
import Foundation
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
    /// P08: the unified search presentation has one owner of the completion token: `ReaderSearchResultsStore`.
    /// This store states the loading/failure surface and the chosen scope; it never keeps a second token.
    @ObservationIgnored private let searchPresentation = ReaderSearchResultsStore()
    public var searchResults: ReaderSearchResults? { searchPresentation.results }
    public private(set) var isSearchingResults = false
    public private(set) var searchResultsFailed = false
    public private(set) var searchScope: ReaderSearchScope = .both
    @ObservationIgnored private var searchSourcePage = 0
    @ObservationIgnored var onSelectSearchResult: (@MainActor (ReaderSearchResult) -> Void)?
    @ObservationIgnored var onRequestSearchPage: (@MainActor (ReaderSearchResults, ReaderSearchCursor?) -> Void)?
    @ObservationIgnored var onRequestSourcePage: (@MainActor (ReaderSearchResults, Int) -> Void)?
    @ObservationIgnored var onSearchScopeChanged: (@MainActor (ReaderSearchScope) -> Void)?
    @ObservationIgnored var onRequestSearchAgain: (@MainActor () -> Void)?

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
        guard renderedItems.contains(where: { $0.id == anchor.cardID }) else { return }
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
        onPresentedPosition: (@MainActor (PresentationAnchor, Bool) -> Void)? = nil,
        onSelectSearchResult: (@MainActor (ReaderSearchResult) -> Void)? = nil,
        onRequestSearchPage: (@MainActor (ReaderSearchResults, ReaderSearchCursor?) -> Void)? = nil,
        onRequestSourcePage: (@MainActor (ReaderSearchResults, Int) -> Void)? = nil,
        onSearchScopeChanged: (@MainActor (ReaderSearchScope) -> Void)? = nil,
        onRequestSearchAgain: (@MainActor () -> Void)? = nil) {
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
        self.onSelectSearchResult = onSelectSearchResult
        self.onRequestSearchPage = onRequestSearchPage
        self.onRequestSourcePage = onRequestSourcePage
        self.onSearchScopeChanged = onSearchScopeChanged
        self.onRequestSearchAgain = onRequestSearchAgain
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
        searchPresentation.clear()
        isSearchingResults = false
        searchResultsFailed = false
        searchSourcePage = 0
        // The host owns the origin and its durable reading position; the store does not.
        onCancelSearch()
    }

    // MARK: - P08: unified local search presentation

    /// Starts a page and returns the completion identity the host must carry. The page owner increments the token,
    /// so a newer term or scope invalidates every older completion in exactly one place.
    public func beginUnifiedSearch(term: String, scope: ReaderSearchScope) -> UInt64 {
        searchScope = scope
        searchSourcePage = 0
        // P1: a submission rebuilds the association and its store. The new store starts from the durable search
        // context, so the surface is open and carries the term; without this the results existed but the reader
        // saw the ordinary feed.
        isSearching = true
        searchQuery = term
        searchPresentation.clear()
        let token = searchPresentation.begin()
        isSearchingResults = true
        searchResultsFailed = false
        return token
    }

    @discardableResult
    public func applyUnifiedSearch(_ completion: ReaderSearchResults) -> Bool {
        guard searchPresentation.apply(completion) else { return false }
        searchResultsFailed = false
        isSearchingResults = false
        return true
    }

    /// Appends an article continuation to the page being shown.
    @discardableResult
    public func appendSearchPage(_ page: ReaderSearchResults) -> Bool {
        // R16: the page must belong to the completion the surface is showing. Comparing only query and scope
        // would accept a late page from a search that was restarted with the same term.
        guard page.token == searchPresentation.currentToken,
            let current = searchPresentation.results, current.query == page.query,
            current.scope == page.scope else { return false }
        let merged = ReaderSearchResults(query: current.query, scope: current.scope,
            token: searchPresentation.currentToken,
            sources: current.sources, saved: current.saved, articles: current.articles + page.articles,
            sourceTruncated: current.sourceTruncated, articleContinuation: page.articleContinuation,
            failedAuthorities: current.failedAuthorities.union(page.failedAuthorities))
        guard searchPresentation.applyAppended(merged) else { return false }
        searchResultsFailed = false
        isSearchingResults = false
        return true
    }

    /// Replaces the source section with the next bounded page; the article page being shown is untouched.
    @discardableResult
    public func appendSourcePage(_ page: ReaderSearchResults, index: Int) -> Bool {
        // Same identity rule as article pages: a restarted search with the same term must reject the old page.
        guard page.token == searchPresentation.currentToken,
            let current = searchPresentation.results, current.query == page.query,
            current.scope == page.scope else { return false }
        let merged = ReaderSearchResults(query: current.query, scope: current.scope,
            token: searchPresentation.currentToken,
            sources: page.sources, saved: current.saved, articles: current.articles,
            sourceTruncated: page.sourceTruncated, articleContinuation: current.articleContinuation,
            failedAuthorities: current.failedAuthorities.union(page.failedAuthorities))
        guard searchPresentation.applyAppended(merged) else { return false }
        searchSourcePage = index
        searchResultsFailed = false
        isSearchingResults = false
        return true
    }

    public func failUnifiedSearch(token: UInt64) {
        guard token == searchPresentation.currentToken else { return }
        isSearchingResults = false
        searchResultsFailed = true
    }

    public func setSearchScope(_ scope: ReaderSearchScope) {
        guard scope != searchScope else { return }
        searchScope = scope
        onSearchScopeChanged?(scope)
    }

    /// The host refused the durable scope change: the surface returns to the scope the context actually has,
    /// without starting another intention.
    public func restoreSearchScope(_ scope: ReaderSearchScope) {
        searchScope = scope
    }

    public func selectSearchResult(_ result: ReaderSearchResult) {
        onSelectSearchResult?(result)
    }

    /// The identity the current page belongs to; a continuation appends only within it.
    public func currentSearchToken() -> UInt64 { searchPresentation.currentToken }

    public func loadMoreSearchResults() {
        guard let results = searchPresentation.results, let cursor = results.articleContinuation else { return }
        isSearchingResults = true
        onRequestSearchPage?(results, cursor)
    }

    /// P08: a truncated source page is not a dead end; the next page is requested through the same query.
    public func loadMoreSources() {
        guard let results = searchPresentation.results, results.sourceTruncated else { return }
        isSearchingResults = true
        onRequestSourcePage?(results, searchSourcePage + 1)
    }

    public func requestSearchAgain() {
        isSearchingResults = true
        searchResultsFailed = false
        onRequestSearchAgain?()
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
        let priorPresentation = state.presentation
        // A restore that could not redraw the reader's own card states it once, through the existing toast: the
        // screen opened on the closest ready card, and claiming an exact resume would be false. The same position
        // reported again (another projection) does not repeat the notice.
        if let substituted = presentationState.presentation?.unavailablePositionCardID,
            substituted != priorPresentation?.unavailablePositionCardID {
            showToast(text: String(localized: "O card em que você parou não está disponível; abrimos no card mais próximo."),
                systemImage: "exclamationmark.triangle")
        }
        state = presentationState.reporting(received.work)
        // The presentation is the full causal/durable history, not the physical
        // LazyVStack. Only a continuous decoded run containing its *own* anchor
        // may be installed as the first visual window. Never turn a deferred
        // image into a placeholder, join ready siblings across a gap or move a
        // missing saved anchor to another card.
        if presentationState.presentation != priorPresentation {
            let next = presentationState.presentation.flatMap {
                FeedReadyVisualWindow.initial(snapshot: $0)
            }
            let sameScope = renderedEditionID == presentationState.presentation?.editionID &&
                renderedContextKey == presentationState.presentation?.contextKey &&
                physicalWindow?.snapshot.provenance.sequenceID ==
                    presentationState.presentation?.provenance.sequenceID
            if !sameScope || renderedItems.isEmpty {
                // An explicit context/edition replacement has no old reader
                // position to preserve. A deferred durable anchor gets no
                // invented physical target or placeholder cell.
                physicalWindow = next
                renderedItems = next?.cards ?? []
            } else if let next {
                let previousIDs = renderedItems.map(\.id)
                let nextIDs = next.cards.map(\.id)
                // Only append-only or same-ID changes can use the existing
                // automatic native offset contract without a physical rebase.
                // Retain the *old* ready snapshot as visual evidence whenever
                // trim/prepend/re-entry requires a measured handoff.
                if nextIDs.starts(with: previousIDs) {
                    physicalWindow = next
                    if next.cards != renderedItems { renderedItems = next.cards }
                }
            }
        }
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
    /// One physical ownership snapshot, distinct from the authoritative
    /// current semantic state. If a logical projection changes while its
    /// corresponding cells cannot be swapped safely, this is the exact
    /// causal provenance of the cells the user can still see and tap.
    @ObservationIgnored private var physicalWindow: FeedReadyVisualWindow?
    var displayedPresentation: FeedPresentationSnapshot? { physicalWindow?.snapshot }
    /// The only pending native handoff candidate. Derived from the accepted
    /// semantic value, never stored as a second cursor or a second publisher.
    /// An unchanged/append-only ready rail is already handled by install();
    /// trims, prepends and bitmap re-entry need measured physical ownership.
    var pendingNativeReadyWindow: FeedReadyVisualWindow? {
        guard let installed = physicalWindow,
            let latest = state.presentation,
            latest.contextKey == installed.snapshot.contextKey,
            latest.editionID == installed.snapshot.editionID,
            latest.provenance.sequenceID == installed.snapshot.provenance.sequenceID,
            latest.provenance.position > installed.snapshot.provenance.position,
            let candidate = FeedReadyVisualWindow.initial(snapshot: latest),
            !candidate.cards.map(\.id).starts(with: renderedItems.map(\.id))
        else { return nil }
        return candidate
    }

    /// Physical ownership must be pinned to the actual painted cards, not to
    /// state.presentation when the latter has advanced past a trim.
    var installedNativeReadyWindow: FeedReadyVisualWindow? { physicalWindow }

    public private(set) var renderedEditionID: FeedEditionID?
    public private(set) var renderedContextKey: ContextKey?
    public private(set) var work: FeedPresentationState.Work = .idle

    /// D4: the first screen's facts and the decision they feed. One stored value, like the published projection:
    /// the decision is read by the screen and by the host's launch record in the same pass, never through two
    /// opinions. It is not a second presentation — the measured layout, the two sticky facts and the host's own
    /// inputs — and nothing in it executes.
    let firstScreen = FeedFirstScreenFacts()

    /// D4: the surface the feed is drawing, from the facts this store and the screen both own. Pure: it reads the
    /// measured layout, the reported work, the search state, the elapsed wait and the sticky exposure fact.
    public var firstScreenSurface: FeedFirstScreenSurface {
        firstScreen.surface(isSearching: isSearching, cardCount: renderedItems.count, work: work)
    }

    /// Whether the reading surface has been shown (sticky). Observable: the cover leaves on the pass a
    /// **measurement** — not a new card — settles it.
    public var firstScreenReading: Bool { firstScreen.reading }

    /// How long the layout has been without progress. The host reads it to wait out the remainder of the run's
    /// measured tolerance; a new card resets it.
    public var firstScreenWaited: Duration { firstScreen.hold.waited }

    /// The bound captured when the first screen appeared. The host loop uses **this** value for the gate, the
    /// remaining wait and the expiry; a later live composition value cannot renew the hold without a new
    /// appearance (the context reset), which is what `noteFirstScreenAppeared` states.
    public var firstScreenWaitLimit: Duration { firstScreen.maximumWait }

    /// The host's own inputs for the decision, stated when the screen appears and whenever its window becomes empty
    /// again; an empty window is what makes the hold legitimate (a durable restore was never prepared here).
    public func noteFirstScreenAppeared(hasSources: Bool, maximumWait: Duration) {
        firstScreen.hasSources = hasSources
        firstScreen.maximumWait = maximumWait
        if renderedItems.isEmpty { firstScreen.hold.notePreparationShown() }
    }

    /// One laid-out card, as the scroll view measured it. The layout is the evidence, and this is where the decision
    /// is re-made from it: the bottom is in the scroll view's coordinates, so the card's own height and every spacing
    /// above it are already part of the value.
    public func noteFirstScreenLayout(cardID: PublicationCardID, contentBottom: CGFloat, viewportHeight: CGFloat) {
        firstScreen.hold.record(cardID: cardID, contentBottom: contentBottom, viewportHeight: viewportHeight)
        settleFirstScreen()
    }

    /// Re-make the decision after a fact the host states: the screen's appearance, a window that arrived, the work
    /// state that settled, or the host's expiry.
    public func reportFirstScreenSurfaceIfReading() { settleFirstScreen() }

    /// The host states that one operation's tolerance has elapsed for this wait. Sticky and idempotent: the bound is
    /// an expiry, not a value a later pass can un-state.
    public func expireFirstScreenWait() {
        if !firstScreen.waitExpired { firstScreen.waitExpired = true }
    }

    /// The one transition the store owns: the reading surface was shown, and the first exposure is on the record.
    private func settleFirstScreen() {
        guard firstScreenSurface == .reading else { return }
        if !firstScreen.reading { firstScreen.reading = true }
        #if DEBUG
        if !firstScreen.noteRecorded, let coverage = firstScreen.hold.coverage {
            firstScreen.noteRecorded = true
            FeedLaunchWitness.noteFirstExposure(cardCount: coverage.laidOutCards,
                contentBottom: Double(coverage.contentBottom), viewportHeight: Double(coverage.viewportHeight))
        }
        #endif
        // The measurement exists to decide the transition once; a long read must not keep a ledger of cards it will
        // never ask about again.
        if firstScreen.hold.coverage != nil { firstScreen.hold.freeze() }
    }

    /// Emits one explicit user observation. The external consumer decides how to execute it.
    public func submitViewport(_ observation: ViewportObservation, activity: RunwayActivity,
        rendered: FeedPresentationSnapshot? = nil, reconciliation: Bool = false,
        establishesPosition: Bool = false) {
        if let onRenderedViewport, let rendered {
            viewportOrdinal += 1
            guard let evidence = rendered.evidence(for: observation, ordinal: viewportOrdinal,
                reconciliation: reconciliation, establishesPosition: establishesPosition) else { return }
            onRenderedViewport(evidence, activity)
            return
        }
        onViewport(observation, activity)
    }

    /// One semantic request from one admitted card. Only an admitted occurrence may act, and the
    /// external consumer decides how to execute it.
    public func perform(_ event: ReaderCardActionEvent, rendered: FeedPresentationSnapshot? = nil) {
        guard renderedItems.contains(where: { $0.id == event.cardID }) else { return }
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

/// D4: the first screen's facts and its decision. Observable in the two sticky facts (so the screen and the host
/// re-evaluate on the same pass a measurement or the host's expiry settles the transition); the measured layout and
/// the elapsed time are deliberately **not** observable, because the geometry callback writes them while the drawing
/// machinery runs.
@MainActor
@Observable
final class FeedFirstScreenFacts {
    /// The measured layout, the clock and the proof that a preparation surface was really drawn. `@ObservationIgnored`
    /// for the reason above; the store and the screen read it, nothing observes it.
    @ObservationIgnored let hold = FeedFirstScreenHold()
    /// The host's own inputs (D4): whether a selection exists at all, and the bound this run measured for one
    /// operation.
    @ObservationIgnored var hasSources = true
    @ObservationIgnored var maximumWait: Duration = .seconds(5)
    /// The reading surface has been shown. Sticky: it is never taken back.
    var reading = false
    /// The host's fact that the run's bounded maximum wait is over.
    var waitExpired = false
    #if DEBUG
    /// Whether the first exposure was already written to the launch record.
    var noteRecorded = false
    #endif

    /// The decision, from the facts above and the ones the store owns.
    func surface(isSearching: Bool, cardCount: Int, work: FeedPresentationState.Work) -> FeedFirstScreenSurface {
        FeedFirstScreenGate.surface(hasSources: hasSources, isSearching: isSearching,
            preparationShown: hold.preparationShown, cardCount: cardCount, coverage: hold.coverage, work: work,
            // The host's expiry is the bound's own fact; before it, the wait is the measured elapsed time.
            waited: waitExpired ? maximumWait : hold.waited,
            maximumWait: maximumWait, alreadyExposed: reading)
    }
}

/// The first screen's measured facts: what the layout reported, when the cards first arrived, and whether a
/// preparation surface was really drawn before them.
///
/// Deliberately **not** observable (the same rule as `FeedVisualMotion`): a geometry callback writes here while the
/// drawing machinery is running, and making the feed re-evaluate on every measured card would turn the measurement
/// into the cost it exists to avoid. The one transition that needs a new pass — the reading surface being shown — is
/// `FeedFirstScreenFacts.reading`, written once.
@MainActor
final class FeedFirstScreenHold {
    private var contentBottoms: [PublicationCardID: CGFloat] = [:]
    private var viewportHeight: CGFloat = 0
    /// The lowest bottom ever reached. A new card above the line, or a card that shrinks and grows back, does not
    /// buy another stall window: only a real, monotonic advance of the coverage resets the clock.
    private var highWaterBottom: CGFloat = 0
    private var startedAt: Double?
    private let clock: () -> Double
    private(set) var preparationShown = false

    init(clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock
    }
    /// Whether the first exposure was already written to the launch record.
    var noteRecorded = false
    /// Once the decision is made the record is closed: a long read must not pay for a measurement nothing asks about.
    private var frozen = false

    /// How long the layout has been without progress: the last new card or higher bottom reset it. This is the
    /// stall the gate is allowed to wait out, not the total time the preparation has been on screen.
    var waited: Duration {
        guard let startedAt else { return .zero }
        return .seconds(max(0, clock() - startedAt))
    }

    /// The layout as measured so far: distinct cards, the lowest bottom reported, and the viewport they were
    /// measured in. Nil until a card reported with a real viewport.
    var coverage: FeedFirstScreenCoverage? {
        guard let bottom = contentBottoms.values.max() else { return nil }
        return FeedFirstScreenCoverage(laidOutCards: contentBottoms.count, contentBottom: bottom,
            viewportHeight: viewportHeight)
    }

    /// The screen drew a surface that waits: that is what makes holding the transition legitimate.
    func notePreparationShown() { preparationShown = true }

    /// One laid-out card, as the scroll view measured it. The bottom is in viewport coordinates, so the card's own
    /// height and every spacing above it are already part of the value.
    func record(cardID: PublicationCardID, contentBottom: CGFloat, viewportHeight: CGFloat,
        at instant: Double? = nil) {
        guard !frozen, viewportHeight.isFinite, viewportHeight > 0, contentBottom.isFinite else { return }
        self.viewportHeight = viewportHeight
        contentBottoms[cardID] = contentBottom
        // Only a real monotonic advance of the coverage buys more hold time: 510 -> 500 -> 510 does not reset, and
        // an inserted card whose bottom is above the line is not progress even though its ID is new.
        let advanced = contentBottom > highWaterBottom
        if advanced { highWaterBottom = contentBottom }
        if startedAt == nil || advanced {
            startedAt = instant ?? clock()
        }
    }

    /// Stop recording: the transition is decided and the first exposure is stated.
    func freeze() {
        guard !frozen else { return }
        frozen = true
    }
}
