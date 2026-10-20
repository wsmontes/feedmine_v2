import Foundation
import Observation
import OSLog
import Network
import FeedMineMedia
#if canImport(UIKit)
import UIKit
#endif
import FeedMineDomain
import FeedMinePersistence
import FeedMineAcquisition
import FeedMineEditorial
import FeedMinePublication
import FeedMineRuntime
import FeedMineUI
import FeedMineComposition
import FeedMineSyndication

/// R15: a search submission states which half succeeded. A failure before the durable write is not saved; a failure
/// after it is saved but not presented, and the reader can retry without duplicating anything.
enum ReaderSearchFailure: Error, Equatable {
    case unusableQuery
    case notStored(detail: String)
    case storedNotActivated(detail: String)

    var selectionIsSaved: Bool { if case .storedNotActivated = self { true } else { false } }
}

@MainActor
@Observable
final class AppComposition {
    private(set) var association: FeedAssociation?
    /// The product-facing message the reader sees when the composition cannot start.
    private(set) var startupFailure: String?
    /// D7-A: what the V1 upgrade carried and what remains inaccessible, owed to the reader on the first open
    /// after the upgrade. Nil when no upgrade is pending or the reader has already dismissed it.
    private(set) var legacyUpgradeNotice: ReaderLegacyUpgradeReceipt?
    /// The technical detail behind `startupFailure`: it belongs to diagnostics, never to the reader's copy
    /// (R5: a raw error description must not be shown as if it were product language).
    private(set) var startupFailureDetail: String?
    /// R5: the technical detail of a startup failure belongs to diagnostics; this is the same sink the
    /// association logs to.
    nonisolated private static func log(_ value: String) {
        #if DEBUG
        Logger(subsystem: "com.feedmine.development", category: "composition").info("\(value, privacy: .public)")
        #endif
    }
    private var replacingSession = false
    /// The owner's decision of 2026-10-17 (item G): while the app is **active and visible**, the same
    /// `foreground()` path is offered as a drive opportunity once every ≥ 10 s. `inactive()`/`background()` stop it;
    /// it never runs in the background and adds no second pipeline.
    @ObservationIgnored private let foregroundCadence = ForegroundDriveCadence()
    /// Whether the app is active and visible right now — exactly the pair the cadence is allowed to drive under.
    @ObservationIgnored private var foregroundActive = false
    /// One verification shared between foreground and a BGAppRefresh grant.
    @ObservationIgnored private var catalogueSyncInFlight = false
    private let directory: URL
    /// The reader's persisted selection. The active session may instead show a collection.
    private var selectedFeeds: [TrustedFeed]
    var feeds: [TrustedFeed] { association?.feeds ?? selectedFeeds }
    /// The catalogue this launch reads: the URL the app's catalogue owner resolved for it, and the **only**
    /// source of that path in this composition. Before this, each reader re-derived it with the same
    /// `Bundle.main` lookup; one value, taken once at the top of `init`, is what makes the app read what
    /// `CatalogInstallation` verified instead of a lookup that merely happens to name the same file. `nil`
    /// stands for "this build carries no readable catalogue", stated rather than faked.
    @ObservationIgnored private var catalogueSnapshot: CatalogSnapshot? {
        // The language groups the filter lens offers are a fact about **this** asset. Tying the invalidation to
        // the only stored value that names the asset means a future write of the snapshot cannot serve the previous
        // catalogue's groups in silence (an earlier version cleared the cache by hand inside the activation).
        didSet { catalogLanguages = nil }
    }
    private var catalogueURL: URL? { catalogueSnapshot?.catalogueURL }
    @ObservationIgnored private var preferences: ReaderPreferencesStore?
    /// The reader's **real** exposures: the cards the visual capture actually presented as the reader's own
    /// position, in the order they happened. The ledger observes new identities so invitation eligibility can
    /// update; repeated positions are a no-op. It is app-scoped rather than session-scoped: a session rebuilt for
    /// the same context (answering an invitation rebuilds it) must not look like a reader who never read
    /// anything. F02's budget reads it; nothing else does.
    @ObservationIgnored let editorialExposure = EditorialExposureLedger()
    /// T6: the active identity — surface, preset, filter and search scope. The plain surface's key equals the
    /// pre-T6 identity, so nothing changes for a reader who never filters.
    private(set) var currentContextKey: ContextKey = ContextKey(request: .main)
    /// R15: the context the reader came from when a search started. Its own checkpoint (written when the search
    /// session retired it) is the promised position a cancel restores.
    @ObservationIgnored private var searchOrigin: ContextKey?
    var currentContext: FeedContextRequest { currentContextKey.request }
    /// The filter the reader is **editing** — the lens criteria they chose plus whatever words the context
    /// itself carries. It is deliberately *not* the folded one: the sheet and the lens write what they are shown,
    /// and a folded value would persist the reader's global content filters into this context, where they would
    /// survive the master switch that is supposed to mask them. What a session applies is `applied(_:)`, which
    /// adds the global half at the one place a session is built.
    var currentFilter: ReaderFilter { currentContextKey.filter }

    /// Whether an answer arrived while a rebuild was running: the running rebuild repeats for it.
    @ObservationIgnored private var pendingRebuild = false

    /// F05: the evidence a run is judged by, written where the run can find it (beside the runtime database).
    @ObservationIgnored lazy var trace: RunwayTrace? = RunwayTrace(directory: directory)

    /// T7, extended by F02: whether the reader's accepted selection has any sources at all. An empty selection
    /// is a decision and its own surface — **unless** the reader gave discovery something to work with: a
    /// language, a place or a subject. Then the app is going to look, and telling them to go choose sources
    /// would be advice that is not true. Discovery never writes itself into the selection; it is the surface's
    /// question that changes, not the database's answer.
    var hasSelectedSources: Bool {
        if !(preferences.flatMap { try? $0.load() }?.sourceKeys.isEmpty ?? true) { return true }
        // The two arms are one question read from both sides of the query: the sources discovery has already
        // **brought** (a warm launch states them after its first frame, so this is the live fact and not the one
        // the session was built with) and the profile it is working with — which is what this surface can know
        // **before** any pool exists, and the arm that answers for a curated feed whose recipe names the interests.
        if let association, !association.discovery.isEmpty || !association.discoveryProfile.isEmpty {
            return true
        }
        // One small preferences read: the surface asks whether discovery was given something, not what the whole
        // profile resolves to.
        guard let settings = (try? preferences?.load())??.settings else { return false }
        return Self.namesAnything(settings.discoveryProfile)
    }
    var currentPreset: ReaderPresetID { currentContextKey.preset }
    private var selectionVersion: UInt64 = 2
    private(set) var sourceOptions: [FeedSourceOption] = []
    @ObservationIgnored private var sourceSearchID = UUID()
    @ObservationIgnored private var sourceChoices: [SourceID: TrustedFeed] = [:]
    private let transportConfiguration: URLSessionConfiguration
    /// A (spec "Estabilidade de coleta e UI"): the launch's acquisition parallelism, supplied by the host. The
    /// default is the spec's 48; every association this composition builds receives this value, so a cold launch
    /// and every replacement session plan with the same budget.
    @ObservationIgnored var launchSettings: CollectionLaunchSettings = .init()
    /// U2: set once by the app host; every association receives it so the reader stays in-app.
    var onExternalURL: ((URL) -> Void)?
    /// U-reading: the reading the host presents for a card — text the app already holds, or the site. Kept apart
    /// from `onExternalURL` above, which stays the *explicit* request for the browser.
    var onReading: ((FeedReadingTarget) -> Void)?
    /// T9: the share sheet a card's share action opens, presented by the app host.
    var onShare: ((SharedLink) -> Void)?
    /// T9: the reader's playback, app-wide: an episode keeps playing across a context change, a sheet or the
    /// reader closing, which is what V1's singleton did and what a per-association player could not.
    @ObservationIgnored let mediaAdapter = MediaPlaybackAdapter()
    /// T5: set once by the app host; the reader's chrome reports a destination, the host presents it.
    var onNavigate: ((ReaderDestination) -> Void)?
    /// R15: the host restores the search origin; the association only forwards the intention.
    var onCancelSearch: (() -> Void)?

    private func connecting(_ association: FeedAssociation) -> FeedAssociation {
        // T8: where this session's saves land. Resolved per save, so changing the preferred box takes effect
        // without rebuilding the session (it is a preference, not an identity).
        association.preferredBookmarkListID = { [weak self] in
            self?.preferredBookmarkListID ?? ReaderBookmarkList.defaultID
        }
        // T8: the menu this session shows. V1's two conditional entries were offered only inside a search or a
        // context with criteria, and its delete entry only on one of the reader's own presets.
        association.refreshMenuDestinations()
        association.onExternalURL = { [weak self] url in self?.onExternalURL?(url) }
        association.onReading = { [weak self] target in self?.onReading?(target) }
        // T5: the reader shell reports a destination; the host presents it. Nothing is resolved here.
        association.onNavigate = { [weak self] destination in self?.onNavigate?(destination) }
        association.onCancelSearch = { [weak self] in
            guard let self else { return }
            Task { await self.cancelSearch() }
        }
        association.onOpenSource = { [weak self] sourceID in
            guard let self else { return }
            Task {
                do { try await self.selectContext(.source(sourceID)) }
                catch { self.association?.store.showToast(
                    text: String(localized: "Não foi possível abrir a fonte"),
                    systemImage: "exclamationmark.triangle") }
            }
        }
        association.onSearch = { [weak self] term in
            guard let self else { return }
            Task {
                do {
                    try await self.submitSearch(term)
                    // P1: `replaceSession` starts the unified page before the feed launch, so the surface appears
                    // without waiting for the window the reader is not looking at.
                } catch { self.reportSearchFailure(error) }
            }
        }
        association.onSearchResult = { [weak self] result in self?.openSearchResult(result) }
        association.onSearchPage = { [weak self] page, cursor in
            guard let self else { return }
            Task { await self.loadSearchPage(page, cursor: cursor) }
        }
        association.onSearchSourcePage = { [weak self] page, index in
            guard let self else { return }
            Task { await self.loadSearchSourcePage(page, index: index) }
        }
        association.onSearchScope = { [weak self] scope in
            guard let self else { return }
            Task { await self.changeSearchScope(scope) }
        }
        association.onSearchRetry = { [weak self] in
            guard let self else { return }
            Task { await self.rerunUnifiedSearch(scope: nil) }
        }
        association.onShare = { [weak self] link in self?.onShare?(link) }
        // T9: a card's media action is resolved and played through the app-wide player.
        association.onMedia = { [weak self] cardID in
            guard let self else { return }
            Task { await self.media?.toggle(cardID: cardID) }
        }

        return association
    }

    /// The languages the filter sheet offers, read from the shipped catalog through the T7 surface. One row per
    /// language, its regional variants kept as information; a missing asset yields none.
    ///
    /// **Read once per catalogue.** The catalogue's own reader states the contract this follows ("the caller
    /// caches it, because nothing changes under a shipped asset"): the lens asks for these from a view body, so an
    /// uncached read opened a `GRDB` queue on the asset, ran a `GROUP BY` through `sqlite`'s sorter — which spilled
    /// to a temp file — and closed it again on the main actor for **every** body evaluation. Measured on the
    /// Release build during a scroll (macOS `sample`, pid 99368): 64,3% of the main thread's on-CPU samples sat in
    /// `filterLanguages › languageGroups › Row.fetchAll › sqlite3VdbeExec` (`vdbeSorterListToPMA`, `pwrite`,
    /// `pread`), which is what the 80 ms frames and the 241 ms worst frame were made of. A failed or not-yet-
    /// installed catalogue is **not** cached, so the first real answer is the one that sticks.
    @ObservationIgnored private var catalogLanguages: [CatalogLanguageGroup]?

    func filterLanguages() -> [CatalogLanguageGroup] {
        if let catalogLanguages { return catalogLanguages }
        guard let association, let catalogueURL,
            let groups = try? SourceManagementCoordinator(catalogURL: catalogueURL,
                database: association.database).languageGroups()
        else { return [] }
        catalogLanguages = groups
        return groups
    }

    /// T8: the box a new bookmark lands in. Nil in the preferences means the default box, which is what a
    /// library that was never asked for a preference has.
    var preferredBookmarkListID: String {
        (try? preferences?.load())??.preferredBookmarkListID ?? ReaderBookmarkList.defaultID
    }

    /// T5/R15: one search submission is a context change, exactly like the sources menu — with the confirmation
    /// boundary made explicit. The key is persisted first; only then is memory changed and the session rebuilt.
    func submitSearch(_ term: String) async throws {
        guard let context = SearchContext(query: term) else { throw ReaderSearchFailure.unusableQuery }
        let origin = currentContextKey
        let key = ContextKey(request: .search(context), preset: currentContextKey.preset,
            filter: resolvedFilter(at: Date()), searchScope: currentContextKey.searchScope)
        guard let preferences else { throw ReaderSearchFailure.notStored(detail: "missing preferences") }
        do { _ = try preferences.setContext(key) }
        catch { throw ReaderSearchFailure.notStored(detail: String(describing: error)) }
        searchOrigin = origin
        currentContextKey = key
        do { try await replaceSession() }
        catch { throw ReaderSearchFailure.storedNotActivated(detail: String(describing: error)) }
    }

    /// R15: cancelling returns to the exact context the search started from — preset, filter, scope and the
    /// promised position (its own durable checkpoint). A search that was never entered is a no-op.
    func cancelSearch() async {
        guard case .search = currentContextKey.request, let origin = searchOrigin else { return }
        searchOrigin = nil
        do {
            guard let preferences else { throw ReaderPreferencesError.missingPreferences }
            _ = try preferences.setContext(origin)
            currentContextKey = origin
            try await replaceSession()
        } catch {
            // The origin could not be restored; the search stays the durable, presented context and the reader is
            // told so instead of being dropped somewhere invented.
            association?.store.showToast(text: String(localized: "Não foi possível voltar ao feed anterior"),
                systemImage: "exclamationmark.triangle")
        }
    }

    private func reportSearchFailure(_ error: any Error) {
        guard let failure = error as? ReaderSearchFailure else { return }
        switch failure {
        case .unusableQuery:
            association?.store.showToast(text: String(localized: "Digite pelo menos um termo para buscar"),
                systemImage: "magnifyingglass")
        case .notStored:
            association?.store.showToast(text: String(localized: "Não foi possível salvar a busca"),
                systemImage: "exclamationmark.triangle")
        case .storedNotActivated:
            association?.store.showToast(text: String(localized: "A busca foi salva, mas não pôde ser aberta"),
                systemImage: "exclamationmark.triangle")
        }
    }

    // MARK: - P08: unified local search pages and destinations

    /// Runs the first page of the current search context. The token comes from the surface, so a completion that
    /// arrives after a newer term/scope is discarded there.
    private func startUnifiedSearch(_ term: String) async {
        guard let association else { return }
        let scope = currentContextKey.searchScope ?? .both
        let token = association.store.beginUnifiedSearch(term: term, scope: scope)
        let results = await unifiedSearch(term, scope: scope, token: token)
        if association === self.association, let results {
            _ = association.store.applyUnifiedSearch(results)
        } else {
            association.store.failUnifiedSearch(token: token)
        }
    }

    /// Appends one continuation page to the page the surface is showing. The token is the surface's current one, so
    /// a page for an older query can never be appended.
    private func loadSearchPage(_ page: ReaderSearchResults, cursor: ReaderSearchCursor?) async {
        guard let association, let cursor, association.store.currentSearchToken() == page.token else { return }
        let token = association.store.currentSearchToken()
        guard let next = await unifiedSearch(page.query, scope: page.scope, token: token,
            articleAfter: cursor) else {
            association.store.failUnifiedSearch(token: token)
            return
        }
        _ = association.store.appendSearchPage(next)
    }

    /// P08: a truncated source page advances with the same query and token; only the source section changes.
    private func loadSearchSourcePage(_ page: ReaderSearchResults, index: Int) async {
        guard let association, association.store.currentSearchToken() == page.token else { return }
        guard let next = await unifiedSearch(page.query, scope: page.scope, token: page.token,
            sourcePage: index) else {
            association.store.failUnifiedSearch(token: page.token)
            return
        }
        _ = association.store.appendSourcePage(next, index: index)
    }

    /// Re-runs the current search for a new scope or after a failure. A scope is part of the durable search key, so
    /// the key is persisted and the session rebuilt before the new page is requested.
    private func rerunUnifiedSearch(scope: ReaderSearchScope?) async {
        guard let association, case .search(let search) = currentContextKey.request else { return }
        let effective = scope ?? (currentContextKey.searchScope ?? .both)
        let token = association.store.beginUnifiedSearch(term: search.query, scope: effective)
        let results = await unifiedSearch(search.query, scope: effective, token: token)
        if let results { _ = association.store.applyUnifiedSearch(results) }
        else { association.store.failUnifiedSearch(token: token) }
    }

    private func changeSearchScope(_ scope: ReaderSearchScope) async {
        guard case .search = currentContextKey.request, scope != (currentContextKey.searchScope ?? .both) else {
            return
        }
        let key = ContextKey(request: currentContextKey.request, preset: currentContextKey.preset,
            filter: currentContextKey.filter, searchScope: scope)
        // R15: the same durable confirmation the submission uses. A refused write leaves the context and the
        // surface where they were; only a durable key may change the search.
        guard let preferences else {
            association?.store.restoreSearchScope(currentContextKey.searchScope ?? .both)
            reportSearchFailure(ReaderSearchFailure.notStored(detail: "missing preferences"))
            return
        }
        do { _ = try preferences.setContext(key) }
        catch {
            association?.store.restoreSearchScope(currentContextKey.searchScope ?? .both)
            reportSearchFailure(ReaderSearchFailure.notStored(detail: String(describing: error)))
            return
        }
        currentContextKey = key
        do { try await replaceSession() }
        catch {
            association?.store.showToast(text: String(localized: "Não foi possível trocar o escopo da busca"),
                systemImage: "exclamationmark.triangle")
            return
        }
        await rerunUnifiedSearch(scope: scope)
    }

    /// P08: a result opens the destination its authority named, through the existing owners.
    private func openSearchResult(_ result: ReaderSearchResult) {
        guard let association else { return }
        switch result.destination {
        case .source(_, let sourceID):
            if let sourceID {
                Task { [weak self] in
                    do { try await self?.selectContext(.source(sourceID)) }
                    catch {
                        self?.association?.store.showToast(
                            text: String(localized: "Não foi possível abrir a fonte"),
                            systemImage: "exclamationmark.triangle")
                    }
                }
            } else {
                onNavigate?(.sources)
            }
        case .savedCard(let cardID):
            association.openSaved(cardID)
        case .article(let cardID, let originRecordID):
            if let cardID {
                association.openSaved(cardID)
            } else {
                let revision = try? ContentStore(database: association.database)
                    .currentRevision(originRecordID: originRecordID)
                if let url = revision?.primaryLink {
                    onExternalURL?(url)
                } else {
                    association.store.showToast(text: String(localized: "Este conteúdo não está disponível"),
                        systemImage: "exclamationmark.triangle")
                }
            }
        }
    }

    /// F02/B01: **no starter selection.** A reader who has chosen nothing has nothing chosen — the bundled
    /// catalogue is what discovery reads (F01), not a subscription list. Seeding catalogue entries as the reader's
    /// own selection is, literally, the failure the acceptance benchmark names: "o app exibe cards bonitos mas
    /// consulta somente a lista estática de quatro feeds". This default was removed once (PORT_LOG §19), measured,
    /// and restored because an empty selection was then a fatal startup failure; that branch is fixed and the path
    /// is now proven by `CompositionTests.testDiscoveryFeedsAReaderWhoChoseNothing`.
    ///
    /// One exception, and it is not a reintroduction: `TrustedFeed.developmentSelection` is DEBUG-only and behind
    /// `FEEDMINE_USE_DEVELOPMENT_FEEDS`, so the UI tests get a reader with **known** sources without re-walking
    /// discovery. It is deliberately not the catalogue — a test flag may not restore the default this comment
    /// forbids — and normal runs and release builds seed nothing.
    init(directory: URL? = nil, feeds: [TrustedFeed] = TrustedFeed.developmentSelection,
        transportConfiguration: URLSessionConfiguration? = nil,
        discoveryQuery: DiscoveryQuery? = nil,
        monotonicNow: @escaping @Sendable () -> RunwayMonotonicTime = { .init(seconds: ProcessInfo.processInfo.systemUptime)! },
        bookmarkRead: (@Sendable () async throws -> Set<PublicationCardID>)? = nil) {
        let support = RuntimeDatabaseLocation.applicationSupport(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]).directory
        #if DEBUG
        let namespace = ProcessInfo.processInfo.environment["FEEDMINE_RUNTIME_NAMESPACE"].flatMap(UUID.init(uuidString:))
        self.directory = directory ?? namespace.map { support.appendingPathComponent($0.uuidString) } ?? support
        #else
        self.directory = directory ?? support
        #endif
        self.selectedFeeds = feeds
        // The one read of a profile's pool. A test that has to decide **when** a read concludes — A→B with A
        // concluding last — hands its own and controls the interleaving without a sleep; the product hands
        // nothing and gets the detached pass over the shipped catalogue. The same kind of seam the transport
        // already is: what the query returns is a value, and this composition owns when it is adopted.
        self.discoveryQuery = discoveryQuery ?? Self.liveDiscoveryQuery
        self.monotonicNow = monotonicNow
        self.bookmarkRead = bookmarkRead
        let config = transportConfiguration ?? .ephemeral
        if transportConfiguration == nil { config.timeoutIntervalForRequest = 20 }
        #if DEBUG
        // Real transport fault configuration for a network-blocked relaunch; no mock connector.
        if ProcessInfo.processInfo.environment["FEEDMINE_BLOCK_RSS_NETWORK"] == "1" {
            DevelopmentNetworkBlock.apply(to: config)
        }
        // T12: a run that must not touch public RSS says so, and gets the app's own fixtures instead.
        if ProcessInfo.processInfo.environment["FEEDMINE_LOCAL_FEEDS"] == "1" {
            DevelopmentLocalFeeds.apply(to: config)
        }
        // The add-feed UI proof: the site the reader pastes, and the feed it declares, come from the app itself.
        if ProcessInfo.processInfo.environment["FEEDMINE_ADD_FEED_FIXTURE"] == "1" {
            AddFeedFixtureSite.apply(to: config)
        }
        #endif
        self.transportConfiguration = config
        // PD-10: the catalogue is installed **before** anything reads it. `bootstrap()` is synchronous and local
        // (no network, no scheduler), so it belongs at the top of the composition root: it verifies the pair this
        // build ships — the catalogue and the descriptor beside it — records the outcome in the ledger, and every
        // reader below takes this one value. The update opportunity is deliberately not here: whether and when to
        // consult the channel is a foreground decision (`CatalogSyncPolicy`), not a launch step.
        let snapshot = CatalogInstallation(appDirectory: self.directory).bootstrap()
        self.catalogueSnapshot = snapshot
        // The player remembers where the reader stopped; the store opens with the rest of the reader's own state,
        // lazily, so the adapter can be built before the database is (a preview or a test never opens one).
        mediaAdapter.positions = ReaderPlaybackPositionsAdapter(database: { [weak self] in
            self?.libraryDatabase()
        })
        // F02/B01: a reader who has chosen nothing is **not** a failure. The feed can be supplied by discovery,
        // and when it cannot, the empty-sources surface states exactly that. What the app does have to report is a
        // catalogue that cannot be read at all — and the two were the same branch here, which is why a client with
        // an empty selection, a filled discovery profile and a good catalogue published nothing.
        if feeds.isEmpty, snapshot?.catalogueURL == nil {
            startupFailure = "Não foi possível carregar o catálogo local de fontes."
        } else {
            do {
                let database = try RuntimeDatabase(location: .init(directory: self.directory))
                // The same connection serves every library surface: the reader's preferences are read through it
                // here, and an export, a box, a collection or a setting is the same file.
                self.library = database
                let preferences = ReaderPreferencesStore(database: database)
                // OMP C1: the repair path (toggleSource) needs preferences even if resolution fails.
                self.preferences = preferences
                var saved = try preferences.initialize(sourceKeys: feeds.map(\.principal))
                // D7-A: the V1 upgrade runs on the first launch that finds a V1 container in this app's own
                // container, after the preferences row exists (so an enabled V1 source can join the selection)
                // and before any session reads the library. A second launch reads the completed marker and does
                // nothing. Failure is recorded, never translated into an empty/default library.
                let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                switch LegacyV1Upgrade.runAtLaunch(applicationSupport: self.directory,
                    documentsDirectory: documents, into: database) {
                case .upgraded, .alreadyHandled:
                    saved = (try? preferences.load()) ?? saved
                case .failed(let reason):
                    Self.log("legacy V1 upgrade failed: \(reason)")
                case .noLegacyContainer:
                    break
                }
                self.legacyUpgradeNotice = LegacyV1Upgrade.pendingNotice(in: database)
                #if DEBUG
                // T7 UI evidence: launch with no selected source at all, which is a state V1 allowed and
                // stated with its own surface.
                if ProcessInfo.processInfo.environment["FEEDMINE_EMPTY_SELECTION"] == "1" {
                    saved = try preferences.updateSources([])
                }
                #endif
                // PD10-P0D D1: the catalog describes availability, never permission to overwrite
                // a durable choice. Missing keys remain in preferences without version changes.
                let identityStore = ReaderLibraryStore(database: database)
                let resolved = try TrustedFeed.resolveAvailable(keys: saved.sourceKeys, fallback: feeds,
                    readerSources: Self.readerSourceEntries(in: database), catalogueURL: self.catalogueURL,
                    identities: identityStore.sourceLinks())
                try identityStore.rememberResolvedSources(resolved.map {
                    (key: $0.principal, authority: $0.principalNamespace == ReaderSourceIdentity.principalNamespace
                        ? "reader" : "catalog")
                })
                self.selectedFeeds = resolved
                let session = try sessionState(for: saved.activeContextKey)
                // A launch is a boundary like any other transition, and the product's own overlay expiry
                // (four hours) must not outlive it. Without this resolution the app adopted the persisted
                // key verbatim, so an overlay the reader could no longer see stayed in force on every
                // launch and quietly excluded everything the discovery brought: the feed starved with
                // "no stories", launch after launch, with no way out except an explicit surface switch.
                let filter = saved.filterExpiry.resolving(session.key.filter, at: Date())
                let restored = filter == session.key.filter
                    ? session.key
                    : ContextKey(request: session.key.request, preset: session.key.preset,
                        filter: filter, searchScope: session.key.searchScope)
                if restored != saved.activeContextKey {
                    saved = try preferences.setContext(restored)
                }
                currentContextKey = saved.activeContextKey
                selectionVersion = saved.selectionVersion
            } catch {
                startupFailure = "Não foi possível carregar suas fontes."
                startupFailureDetail = String(describing: error)
                Self.log("startup failure loading the source selection: \(String(describing: error))")
            }
        }
        // A warm launch is local (INV-07) — and the reader must not perceive it: when the previous interaction left
        // a durable window, the association is built **here**, synchronously, so this launch's first frame already
        // carries the reader's own feed and no surface is drawn between the launch screen and it. `launch()` then
        // activates what exists and lets everything that is not the reader's window continue behind it — including
        // the pool the profile names, which walks the shipped catalogue and is therefore read **after** that frame
        // (`warmAssociation()` states why, and `launch()` reads it into the association that is already reading).
        //
        // A launch with nothing durable keeps the asynchronous path exactly as it was: its preparation surface is the
        // legitimate one (doctrine item 1 — "the first open may be slow — that is what the loading screen is for"),
        // and the pool its profile names must not block a first run's main actor.
        if startupFailure == nil, hasDurableWindow() {
            association = try? warmAssociation()
        }
    }

    /// Whether the previous interaction left a window at all: two one-row reads, taken only to decide whether this
    /// launch is warm. What a launch can actually restore is answered precisely, and only, by
    /// `FeedSession.warmStart` inside the association.
    private func hasDurableWindow() -> Bool {
        guard let library else { return false }
        let store = SessionStore(database: library)
        // A read that throws is not a durable window: this launch then keeps the asynchronous path, which reports
        // its own failures to the reader.
        return (try? store.checkpoint()) != nil || (try? store.checkpoint(for: currentContextKey)) != nil
    }

    func launch() async {
        guard !replacingSession, startupFailure == nil else { return }
        // P15: the anchor for the launch's own timing. `first_frame` states attach → presented frame; this states
        // when the host started the launch, on the same clock, so a journey reads launch → first presented frame
        // without a console and without guessing a process start from outside the sandbox. It is not the exec
        // instant either: the gap between the process starting and this call stays unmeasured and is not claimed.
        trace?.recordOnce("host_started", key: "host_started",
            ["uptime_s": String(format: "%.3f", ProcessInfo.processInfo.systemUptime)])
        // The anchor is written at once: like `first_frame`, it happens once per process, so waiting for the
        // 64-line batch would lose it on a run that never backgrounds.
        trace?.flush()
        let current: FeedAssociation
        // Whether this launch started from the window the previous interaction left — built synchronously in `init`
        // and therefore without discovery. What discovery brings arrives below, behind that window. (The adoption is
        // idempotent — the read is the one cache and the merge deduplicates — so a repeated call states nothing new.)
        var startedWarm = false
        if let warmed = association {
            // The warm launch already built this association **and** installed the reader's own window into it,
            // before this launch drew anything. What is left is everything that is not that window: activation,
            // acquisition, media, the discovery walk — the backend, behind the feed the reader already has.
            current = warmed
            startedWarm = true
        } else {
            do { current = try await association(contextKey: currentContextKey) }
            catch {
                startupFailure = "Não foi possível abrir o feed local."
                startupFailureDetail = String(describing: error)
                Self.log("startup failure opening the association: \(String(describing: error))")
                return
            }
            association = current
        }
        // Discovery resumes here, as the normal opportunity: the same read the asynchronous launch takes, released
        // **after** the reader's own window is on screen — the criterion forbids work between the launch screen and
        // the feed, not work behind it — and adopted by the association that is already reading it. The walk's own
        // bounded page per opportunity follows from `current.launch()` below.
        //
        // What releases it is this host's first pass that carried the reader's cards (`FeedMineApp.body`'s branch
        // decides it, and this launch runs from that view's task). That is **evaluation of the body**, not a
        // presented frame: nothing here observes a commit of pixels, and a pass whose update is replaced before it
        // is drawn would be counted. The claim this code can carry is therefore the weaker, true one — that no
        // wait surface is drawn between the launch screen and the feed — and the stronger one is left
        // INDETERMINADO (see the report of this gate).
        if startedWarm {
            let key = applied(currentContextKey)
            let profile = discoveryProfile(for: key)
            let fingerprint = catalogueSnapshot?.fingerprint
            let read = await discoveryRead(profile: profile)
            // After the await, before adopting: this launch's own association must still be the one reading, still
            // active, still on the profile and the catalogue revision this read answers for. A read that concludes
            // after the reader moved is stale **for this session** — it keeps its value under its own key in the
            // one cache (`discoveryRead`) and changes nothing here. Without this, a pool prepared for profile A
            // could be published into the session reading B (A→B, A concluding last).
            if let read, association === current, current.active, current.contextKey == key,
                current.discoveryProfile == profile, read.profile == profile,
                read.fingerprint == fingerprint {
                current.adopt(read)
            }
        }
        // P1: the search context must show its page without waiting for the feed window. The launch can wait on
        // acquisition; the durable search is local and is the surface the reader asked for.
        if association === current, case .search(let search) = currentContextKey.request {
            await startUnifiedSearch(search.query)
        }
        do {
            try await current.launch()
        } catch {
            // An old launch may settle after explicit replacement. Its error belongs to that association.
            guard association === current, current.active else { return }
            startupFailure = "Não foi possível abrir o feed local."
            startupFailureDetail = String(describing: error)
            Self.log("startup failure launching the association: \(String(describing: error))")
            current.reportFailure(error)
        }
    }

    /// The app is active and visible: the lifecycle transition. It states the pair the foreground cadence drives
    /// under and arms the cadence, then takes the drive itself. The cadence then repeats **that drive**
    /// (`association.foreground()`) every ≥ 10 s — never this composition pass, whose catalogue check has its own
    /// durable clock and is not a runway opportunity. Only this method sets `foregroundActive`; `inactive()` and
    /// `background()` clear it.
    func foreground() async {
        foregroundActive = true
        await startForegroundCadence()
        guard let association else { return }
        await association.foreground()
        await syncCatalogueIfDue()
    }

    /// `.inactive` is not yet background — the app can still be on screen during an app switch or a system prompt —
    /// but it is not "active and visible" either, and that pair is exactly what the foreground cadence drives
    /// under. The screen's own lifecycle work stays on `background()`.
    func inactive() async {
        foregroundActive = false
        await foregroundCadence.stop()
    }

    private func startForegroundCadence() async {
        await foregroundCadence.start { [weak self] in
            await self?.foregroundCadenceOpportunity()
        }
    }

    /// The cadence's one opportunity: the same feed drive a foreground takes — `association.foreground()`, the path
    /// that re-activates the current presentation through `activateCurrentPresentation`. The catalogue sync stays
    /// out on purpose: it has its own durable clock and is not a runway opportunity. The pair the cadence may run
    /// under is re-checked here, so a wake delivered after `.inactive`/`.background` is dropped instead of undoing
    /// that transition.
    private func foregroundCadenceOpportunity() async {
        guard foregroundActive, let association else { return }
        await association.foreground()
    }

    /// The network opportunity is separate from the local bootstrap and from the first paint. A bundled
    /// snapshot is verified *locally* at launch; it does not count as a successful check of the authority.
    /// The only durable clock/validator is the existing sync record, committed after a successful remote
    /// verification (200 up-to-date, 200 activated, or a consistent conditional 304).
    /// A short iOS grant reuses the existing single-manifest verification, never the potentially
    /// expensive OPML download/compilation. It cannot create an association or rebuild a view.
    func backgroundRefreshOpportunity() async -> Bool {
        #if canImport(UIKit)
        guard UIApplication.shared.backgroundRefreshStatus == .available,
            UIApplication.shared.applicationState == .background else { return false }
        #endif
        guard association?.active == true, !replacingSession, !catalogueSyncInFlight,
            !Task.isCancelled else { return false }
        await syncCatalogueIfDue(installNewRevisions: false)
        return !Task.isCancelled
    }

    private func syncCatalogueIfDue(installNewRevisions: Bool = true) async {
        guard !catalogueSyncInFlight, !Task.isCancelled else { return }
        catalogueSyncInFlight = true
        defer { catalogueSyncInFlight = false }
        let installation = CatalogInstallation(appDirectory: directory)
        let recordURL = installation.directory.appendingPathComponent("sync.json")
        let readRecord: @Sendable () -> CatalogSyncRecord? = { [recordURL] in
            try? JSONDecoder().decode(CatalogSyncRecord.self, from: Data(contentsOf: recordURL))
        }
        let writeRecord: @Sendable (CatalogSyncRecord) -> Void = { [installation, recordURL] record in
            try? FileManager.default.createDirectory(at: installation.directory, withIntermediateDirectories: true)
            try? JSONEncoder().encode(record).write(to: recordURL, options: .atomic)
        }
        // A debug authority is a different channel; never consume or overwrite the published channel's ledger
        // of successful checks. The production authority always uses its own durable record across relaunches.
        let authority = Self.statedCatalogueAuthority()
        let stored = authority == nil ? (readRecord() ?? CatalogSyncRecord()) : CatalogSyncRecord()
        let active = installation.activeSnapshot()
        let consistent = active != nil && stored.verifiedAt != nil
            && stored.verifiedRevision == active?.revision
            && stored.remoteRevision == stored.verifiedRevision
        // An old validator for another revision cannot justify a 304 or a recent-verification skip.
        let decision = CatalogSyncPolicy.decision(record: consistent ? stored : CatalogSyncRecord(), now: Date())
        guard decision.isCheck else {
            if case .skip(let verifiedAt) = decision {
                installation.record(installation.deferredRecord(
                    reason: "verified \(Int(Date().timeIntervalSince(verifiedAt)))s ago; nothing due",
                    kind: "policy"))
            }
            return
        }
        let validator = consistent ? stored.etag : nil
        // Use the composition's existing transport configuration. Tests can exercise the *standard* authority
        // without an environment override; production still uses an ephemeral session with the public URL.
        // The Debug-only local authority is intentionally independent of the RSS transport used by app
        // acceptance tests; only the standard public URL uses the composition's injectable configuration.
        let manifestSession = authority == nil ? URLSession(configuration: transportConfiguration) : .shared
        let channel = CatalogUpdateChannel(manifestURL: authority ?? CatalogUpdateChannel.publicManifestURL,
            session: manifestSession, storedETag: { validator })
        func write(_ outcome: CatalogRevisionRecord.Outcome, _ revision: Int?, _ reason: String, _ kind: String?) {
            installation.record(CatalogRevisionRecord(revision: revision, fingerprint: nil, outcome: outcome,
                reason: reason, kind: kind, at: ISO8601DateFormatter().string(from: Date())))
        }
        // Only the published authority persists sync.json. The test-only authority is intentionally isolated.
        func commit(_ record: CatalogSyncRecord) {
            guard !Task.isCancelled else { return }
            if authority == nil { writeRecord(record) }
        }
        let fetched = await channel.fetch()
        // Expiration cancels URLSession's async request. Never record a successful
        // verification or validator after that cancellation, even if a response raced it.
        guard !Task.isCancelled else { return }
        switch fetched {
        case .notModified:
            guard consistent, validator != nil, let revision = stored.verifiedRevision else {
                write(.deferred, nil, "304 without a matching previously verified snapshot", "policy")
                return
            }
            commit(CatalogSyncRecord(verifiedRevision: revision, verifiedAt: Date(),
                remoteRevision: revision, etag: validator))
            write(.deferred, revision, "manifest unchanged since the last verified check", "policy")
        case .unavailable(let why):
            write(.deferred, nil, "no manifest this time: \(why)", "network")
        case .manifest(let data, let etag):
            guard let remote = try? CatalogManifest.decode(data) else {
                write(.deferred, nil, "the authority's manifest is not readable in the published shape", "payload")
                return
            }
            // An equal revision cannot skip the download on the strength of an invalid public declaration.
            // The public authority publishes OPML inputs only, never the locally derived SQLite artifact.
            if let rejection = CatalogManifest.validate(remote) {
                write(.rejected, remote.revision, rejection.reason, rejection.kind)
                return
            }
            guard remote.catalogueEntry == nil, !remote.opmlEntries.isEmpty else {
                write(.rejected, remote.revision, "public manifest must declare OPML inputs only", "manifest")
                return
            }
            switch CatalogOffer.decide(remote: remote, active: active?.manifest) {
            case .upToDate(let revision):
                // The public OPML declaration matched the installed snapshot; no download or recompilation.
                commit(CatalogSyncRecord(verifiedRevision: revision, verifiedAt: Date(),
                    remoteRevision: revision, etag: etag))
                write(.deferred, revision, "revision \(revision) is already active", "policy")
            case .stale(let revision):
                write(.rejected, revision, "revision \(revision) is older than the active snapshot", "payload")
            case .collision(let revision):
                write(.rejected, revision, "revision \(revision) declares a different snapshot than the active one", "payload")
            case .accept:
                // A newer revision requires OPML downloads and catalogue compilation. Do not
                // start those under a short BG grant or advance the verification clock for them.
                guard installNewRevisions, !Task.isCancelled else { return }
                // Stage and activate before committing either the verifier's clock or its ETag. An interrupted or
                // refused install must be retried on the next opportunity, rather than answered by a stranded 304.
                let updater = CatalogUpdater(installation: installation, channel: channel)
                switch await updater.install(remote) {
                case .activated(let snapshot):
                    // Only work *started after this point* sees the new authority. The association already
                    // presenting cards keeps the snapshot, discovery and publication it was built with.
                    adoptActivatedCatalogue(snapshot)
                    commit(CatalogSyncRecord(verifiedRevision: snapshot.revision, verifiedAt: Date(),
                        remoteRevision: snapshot.revision, etag: etag))
                case .rejected, .unavailable:
                    break // The updater logged the failure; neither the clock nor the ETag advances.
                }
            }
        }
    }

    /// Adopt the installer-verified snapshot for future work. The existing association, its runway and all
    /// admitted cards are intentionally untouched. A selected source stays the reader's own durable choice;
    /// re-resolution merely refreshes its endpoint/metadata when the same canonical key exists in the new
    /// catalogue, without changing stored preferences or inventing a subscription from discovery.
    private func adoptActivatedCatalogue(_ snapshot: CatalogSnapshot) {
        guard catalogueSnapshot?.fingerprint != snapshot.fingerprint else { return }
        catalogueSnapshot = snapshot
        // P0B owns the verified active snapshot and protects the currently displayed association.
        // P0D applies that snapshot only to future operational resolution, reusing personal anchors.
        if let preferences, let database = libraryDatabase() {
            do {
                if let saved = try preferences.load() {
                    let identities = ReaderLibraryStore(database: database)
                    let resolved = try TrustedFeed.resolveAvailable(keys: saved.sourceKeys,
                        fallback: selectedFeeds, readerSources: Self.readerSourceEntries(in: database),
                        catalogueURL: snapshot.catalogueURL, identities: identities.sourceLinks())
                    try identities.rememberResolvedSources(resolved.map {
                        (key: $0.principal,
                            authority: $0.principalNamespace == ReaderSourceIdentity.principalNamespace
                                ? "reader" : "catalog")
                    })
                    selectedFeeds = resolved
                }
            } catch {
                Self.log("catalog activation kept the previous operational selection: \(error)")
            }
        }
        // Do not discard prepared pools/traversals: their existing snapshot identity keeps them reusable for
        // associations still reading that snapshot. Future lookups use the new fingerprint in their key.
        // A source-search begun against the old catalogue is fenced when its detached query returns.
    }

    /// The authority this run consults, when the run states one. `FEEDMINE_CATALOGUE_AUTHORITY` names a manifest
    /// URL for the runs that need an authority of their own — an app test, or a device driven against a server on
    /// the machine that builds it — and it is read in Debug builds only: nothing in a release binary reads the
    /// environment, so the channel PD-10 names cannot be pointed elsewhere from outside the app. Naming another
    /// authority also states that no durable record about the published one decides this pass (see
    /// `syncCatalogueIfDue`): a window, a validator and a revision in `sync.json` belong to the published channel.
    ///
    /// What this seam is *not*: a way to make a production check happen. The daily window
    /// (`CatalogSyncPolicy.verificationWindow`) is unchanged and the published URL is the default; a run that says
    /// nothing behaves exactly as it did before this existed.
    private static func statedCatalogueAuthority() -> URL? {
        #if DEBUG
        return ProcessInfo.processInfo.environment["FEEDMINE_CATALOGUE_AUTHORITY"].flatMap(URL.init(string:))
        #else
        return nil
        #endif
    }

    /// R04: memory pressure is forwarded to the one association; no second residency model is created.
    func trimResidencyForMemoryPressure() async {
        await association?.trimResidencyForMemoryPressure()
    }

    func background() async {
        // The screen is gone: the cadence stops before anything else runs, so no opportunity is offered past this
        // point. (`inactive()` already stopped it on the way here; a direct `.background` still stops it.)
        foregroundActive = false
        await foregroundCadence.stop()
        // V1's own moment for this (`FeedScreen` on `.background`): what the reader was listening to is written
        // before the app can be suspended, so a flush that never comes costs nothing.
        if mediaAdapter.state.item != nil { mediaAdapter.savePosition() }
        guard let association else { return }
        await association.background()
    }

    func searchSources(_ query: String) async throws {
        let searchID = UUID()
        sourceSearchID = searchID
        let snapshot = catalogueSnapshot
        var choices = selectedFeeds
        if let url = snapshot?.catalogueURL {
            let records = try await Task.detached {
                try LegacyCatalogReader(catalogURL: url).matchingSources(query: query, limit: 50)
            }.value
            // Preserve established IDs without reopening the large catalog for every search hit.
            // This uses the already fetched records and the reader's one durable identity authority.
            let links = (try? libraryDatabase().map {
                try ReaderLibraryStore(database: $0).sourceLinks()
            }) ?? [:]
            let imported = Dictionary(readerSourceEntries().map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first })
            choices += records.compactMap { record in
                let link = links[record.key]
                let anchor = link?.anchorKey ?? record.key
                if link?.authority == "reader",
                    let personal = imported[record.key] ?? imported[anchor],
                    let entry = ReaderSourceIdentity.entry(personal, identityKey: anchor) {
                    return TrustedFeed(targetID: entry.targetID, sourceID: entry.source.id,
                        bindingID: entry.bindingID, principal: anchor, endpoint: entry.endpoint,
                        displayName: entry.source.displayName,
                        principalNamespace: ReaderSourceIdentity.principalNamespace)
                }
                return LegacyCatalogImport.entryWithIdentityKey(record, identityKey: anchor).map(Self.trustedFeed(from:))
            }
        }
        guard searchID == sourceSearchID else { return }
        if catalogueSnapshot?.fingerprint != snapshot?.fingerprint {
            // The detached query started under an obsolete snapshot. Repeat against the active revision,
            // rather than installing old options on a newer catalogue or throwing away other useful work.
            try await searchSources(query)
            return
        }
        sourceChoices = Dictionary(choices.map { ($0.sourceID, $0) }, uniquingKeysWith: { first, _ in first })
        let selected = Set(selectedFeeds.map(\.sourceID))
        sourceOptions = sourceChoices.values.map { .init(id: $0.sourceID, name: $0.displayName, selected: selected.contains($0.sourceID)) }
            .sorted { left, right in left.selected != right.selected ? left.selected : left.name.localizedStandardCompare(right.name) == .orderedAscending }
    }

    /// Changing the reader's selection exits a collection: it cannot keep filtering against
    /// collection membership while the newly selected sources belong to the reader's plain feed.
    private func presetAfterSelectionChange() -> ReaderPresetID {
        if case .collection = currentContextKey.preset { return .everything }
        return currentContextKey.preset
    }

    func toggleSource(_ sourceID: SourceID) async throws {
        guard !replacingSession else { return }
        replacingSession = true
        defer { replacingSession = false }
        guard let choice = sourceChoices[sourceID], let preferences else { throw ReaderPreferencesError.invalidSelection }
        var next = selectedFeeds
        let removing = next.firstIndex(where: { $0.sourceID == sourceID })
        if let removing { next.remove(at: removing) }
        else { next.append(choice) }
        guard !next.isEmpty else { throw ReaderPreferencesError.invalidSelection }
        if let retired = association {
            _ = try await retired.session.checkpointCurrentPosition(at: Date())
            await retired.close()
        }
        association = nil
        // D1: only the toggled key changes. Operationally unresolved keys remain durable
        // in preferences; rebuilding from selectedFeeds would silently deselect them.
        let saved = try preferences.changeSources(adding: removing == nil ? [choice.principal] : [],
            removing: removing == nil ? [] : [choice.principal])
        if let database = libraryDatabase() {
            try ReaderLibraryStore(database: database).rememberResolvedSources(next.map {
                (key: $0.principal, authority: $0.principalNamespace == ReaderSourceIdentity.principalNamespace
                    ? "reader" : "catalog")
            })
        }
        selectedFeeds = next
        selectionVersion = saved.selectionVersion
        let request: FeedContextRequest = next.count == 1 ? .source(next[0].sourceID) : .main
        currentContextKey = ContextKey(request: request, preset: presetAfterSelectionChange(),
            filter: currentContextKey.filter)
        _ = try preferences.setContext(currentContextKey)
        let nextAssociation = try await association(contextKey: currentContextKey)
        association = nextAssociation
        startupFailure = nil
        try await nextAssociation.launch()
        try await searchSources("")
    }

    func selectContext(_ request: FeedContextRequest) async throws {
        if case .source(let sourceID) = request, !feeds.contains(where: { $0.sourceID == sourceID }) {
            throw ReaderPreferencesError.invalidSelection
        }
        guard !replacingSession else { return }
        if request == currentContext, association != nil,
            currentContextKey.filter.isUnrestricted, currentContextKey.preset == .everything { return }
        replacingSession = true
        defer { replacingSession = false }
        if let retired = association {
            _ = try await retired.session.checkpointCurrentPosition(at: Date())
            await retired.close()
        }
        association = nil
        // A surface switch is an explicit transition too, so a pending expiry is resolved here.
        currentContextKey = ContextKey(request: request, preset: currentContextKey.preset,
            filter: resolvedFilter(at: Date()))
        _ = try preferences?.setContext(currentContextKey)
        let next = try await association(contextKey: currentContextKey)
        association = next
        startupFailure = nil
        try await next.launch()
        // Answers received during this constructor belong to the finished transition too.
        if pendingRebuild {
            replacingSession = false
            try await replaceSession()
        }
    }

    /// T6: an explicit filter transition. It is a **confirmation boundary**: the selection (identity and overlay
    /// window together, one durable write) is confirmed first, and only then does memory change and the session
    /// get rebuilt. A persistence failure therefore leaves the previous key, the previous expiry and the live
    /// session exactly as they were; a failure after confirmation is reported as such and can be retried, because
    /// the selection it names is already durable.
    func applyFilter(_ filter: ReaderFilter, preset: ReaderPresetID) async throws {
        let key = ContextKey(request: currentContextKey.request, preset: preset, filter: filter,
            searchScope: currentContextKey.searchScope)
        // A confirmed selection whose presentation failed is retried: the live session is not the applied key.
        guard key != currentContextKey || association?.contextKey != applied(key) else { return }
        // A new overlay selection starts the window again; a selection without overlay criteria has none.
        let expiry = filterExpiry(renewing: filter, at: Date())
        do {
            guard let preferences else { throw ReaderPreferencesError.missingPreferences }
            _ = try preferences.setFilterSelection(key, expiry: expiry)
        } catch {
            throw ReaderFilterFailure.persistenceFailed(detail: String(describing: error))
        }
        currentContextKey = key
        do {
            try await replaceSession()
        } catch {
            // The selection is durable and stays identified; the feed was not rebuilt around it.
            throw ReaderFilterFailure.presentationFailed(detail: String(describing: error))
        }
    }

    /// T6: the expiry record for a selection applied now. V1's four-hour rule covers the overlay criteria
    /// (region, taxonomy, language, type, mood); content exclusions are outside it, so a filter that only
    /// excludes keeps no deadline.
    func filterExpiry(renewing filter: ReaderFilter, at now: Date) -> ReaderFilterExpiry {
        let overlayIsSet = !(filter.regionIDs.isEmpty && filter.taxonomyNodeIDs.isEmpty
            && filter.languages.isEmpty && filter.contentType == .all && filter.mood == .all)
        let enabled = preferences.flatMap { try? $0.load() }?.filterExpiry.isEnabled ?? true
        return ReaderFilterExpiry(isEnabled: enabled, startsAt: overlayIsSet ? now : nil)
    }

    /// What an explicit transition applies: a *pending* expiry is resolved here and nowhere else, so a clock
    /// never changes the reader's active presentation (`filterExpiry` is the record, `resolvedFilter` the
    /// decision).
    func resolvedFilter(at now: Date) -> ReaderFilter {
        let record = preferences.flatMap { try? $0.load() }?.filterExpiry ?? .disabled
        return record.resolving(currentFilter, at: now)
    }

    /// The filter an explicit transition will activate, resolving a pending expiry first.
    func transitionFilter(at now: Date = Date()) -> ReaderFilter {
        resolvedFilter(at: now)
    }

    /// T8: the presets the filter sheet offers — V1's two plain entries, then the reader's own: curated
    /// presets, collections and smart bookmarks, in V1's picker order. Each saved one carries the key it
    /// activates, so choosing it is an ordinary T6 transition and never a second feed engine.
    func presetRows() -> [FilterPresetRow] {
        let current = currentContextKey.preset
        var rows: [FilterPresetRow] = [
            FilterPresetRow(id: "everything", preset: .everything, name: String(localized: "Tudo"),
                systemImage: "circle.grid.3x3.fill", isSelected: current == ReaderPresetID.everything),
            FilterPresetRow(id: "lastClicked", preset: .lastClicked, name: String(localized: "Último aberto"),
                systemImage: "clock.arrow.circlepath", isSelected: current == ReaderPresetID.lastClicked),
        ]
        guard let library = libraryCoordinator() else { return rows }
        if let presets = try? library.presets() {
            rows.append(contentsOf: presets.map { preset -> FilterPresetRow in
                let icon = preset.kind == .curatedFeed ? "wand.and.stars" : "sparkles.rectangle.stack"
                return FilterPresetRow(id: preset.presetID.identityText, preset: preset.presetID,
                    name: preset.name, systemImage: icon, isSelected: current == preset.presetID,
                    key: preset.key)
            })
        }
        if let collections = try? library.collections() {
            rows.append(contentsOf: collections.map { collection -> FilterPresetRow in
                let presetID = ReaderPresetID.collection(collection.id)
                return FilterPresetRow(id: presetID.identityText, preset: presetID, name: collection.name,
                    systemImage: "rectangle.stack.fill", isSelected: current == presetID)
            })
        }
        return rows
    }

    /// T8: activating a preset the reader saved. The stored key is the identity — including the search scope it
    /// was born from — so this is T6's transition with that key, and the library is never a second engine.
    /// R20: a hook between persisting the new identity and opening its session. The failure path is the one this
    /// transition must survive; nothing else may observe it, and it never changes a successful activation.
    @ObservationIgnored var beforeBuildingSession: ((ContextKey) throws -> Void)?

    /// Quantas sessões esta composição construiu. Uma substituição constrói uma; a resposta em curso costumava
    /// pedir um segundo passe — e é essa segunda construção que o B04 mediu como movimento do leitor. DEBUG-only,
    /// como o resto da instrumentação: a asserção é sobre reconstrução de sessão, não sobre leituras.
    #if DEBUG
    private(set) var sessionConstructions = 0
    #endif

    func activateSavedPreset(_ key: ContextKey) async throws {
        guard !replacingSession, let preferences else { return }
        // An explicit transition happens when the identity changes *or* when the behaviour does: editing a recipe
        // that leaves the context key alone still changes what the feed ranks, and the running session must not
        // keep publishing under the revision it was built for.
        let (_, version) = scoring(for: key)
        if let current = association, current.contextKey == key,
            current.policy.scoringPolicyVersion.rawValue == version { return }
        replacingSession = true
        defer { replacingSession = false }
        let previous = currentContextKey
        if let retired = association {
            _ = try await retired.session.checkpointCurrentPosition(at: Date())
            await retired.close()
        }
        association = nil
        currentContextKey = key
        do {
            _ = try preferences.setContext(key)
            try beforeBuildingSession?(key)
            let next = try await association(contextKey: key)
            association = next
            startupFailure = nil
            try await next.launch()
        } catch let failure {
            // R20: the durable identity and the opened session are one outcome. A rebuild that threw after the key
            // was written must not leave the reader on an identity with no session: restore the previous context in
            // memory and in the preferences, then reopen it. The caller still receives the original failure.
            await association?.close()
            association = nil
            currentContextKey = previous
            do {
                _ = try preferences.setContext(previous)
                let restored = try await association(contextKey: previous)
                association = restored
                startupFailure = nil
                try await restored.launch()
            } catch {
                startupFailure = "Não foi possível abrir o feed local."
            }
            throw failure
        }
        // Answers received during this constructor belong to the finished transition too.
        if pendingRebuild {
            replacingSession = false
            try await replaceSession()
        }
    }

    /// T8: the bookmark boxes surface's store, over the reader's own library. The composition opens the
    /// database the same way the rest of its surfaces do; there is one file, not a second store.
    func makeBookmarkBoxesStore() -> BookmarkBoxesStore? {
        guard let database = libraryDatabase() else { return nil }
        // R02: a box deletion removes memberships, so the durable box mutation is delivered through the **same**
        // confirmed path a save is: the association moves its revision and the one refresher re-reads the set.
        return BookmarkBoxesStore(backend: ReaderBookmarkBoxesBackend(database: database,
            onConfirmedChange: { [weak self] in
                guard let self else { return }
                await MainActor.run { self.association?.bookmarkMutationConfirmed() }
            }))
    }

    /// T8: the collections surface's store, over the same library.
    func makeCollectionsStore() -> CollectionsStore? {
        guard let database = libraryDatabase() else { return nil }
        return CollectionsStore(backend: ReaderCollectionsBackend(database: database))
    }

    /// R16: the authorities a unified search reads, exposed to the search extension without widening the one
    /// database owner or the resolved catalogue path.
    func searchAuthorities() -> (database: RuntimeDatabase?, catalogue: URL?, feeds: [TrustedFeed]) {
        (libraryDatabase(), catalogueURL, feeds)
    }

    /// One handle on the reader's database for every library surface; the file is opened the way the rest of
    /// the composition opens it. One connection for every library read and write the host performs: opening a
    /// fresh pool per action ran the migrations again and contended with the session's own connections, and a
    /// refused open was swallowed by `try?` — which is how an export could silently become "nothing to export".
    /// A failed open is not remembered, so the next action tries again.
    @ObservationIgnored private var library: RuntimeDatabase?

    private func libraryDatabase() -> RuntimeDatabase? {
        if let library { return library }
        let opened = try? RuntimeDatabase(location: RuntimeDatabaseLocation(directory: directory))
        library = opened
        return opened
    }

    /// The library boundary, for the reader's own actions on it.
    private func libraryCoordinator() -> ReaderLibraryCoordinator? {
        libraryDatabase().map(ReaderLibraryCoordinator.init(database:))
    }

    /// D7-A: the reader dismissed the first-open notice. The durable receipt is the record; the in-memory value
    /// only decides whether this presentation is still owed.
    func acknowledgeLegacyUpgradeNotice() {
        if let database = libraryDatabase() {
            try? ReaderLibraryStore(database: database).markLegacyUpgradeNoticePresented()
        }
        legacyUpgradeNotice = nil
    }

    /// What the first open tells the reader. It states the imported counts and what remains inaccessible in
    /// this build; it never claims the upgrade is complete or that the library was lost.
    var legacyUpgradeNoticeText: String {
        guard let notice = legacyUpgradeNotice else { return "" }
        if notice.status == .unsupported {
            return String(localized: "Encontramos dados da versão anterior, mas este formato de biblioteca não pode ser lido por esta versão. Nada foi alterado no arquivo original.")
        }
        func count(_ category: String) -> Int {
            notice.skips.filter { $0.category == category }.reduce(0) { $0 + $1.count }
        }
        return String(localized: """
            Importados da versão anterior: caixas \(notice.importedBoxes), fontes \(notice.importedSources), \
            coleções \(notice.importedCollections).
            Ainda inacessíveis nesta versão: artigos salvos \(notice.inaccessibleSavedArticles), \
            marcadores inteligentes \(count("smartFeeds")), feeds curados \(count("curatedFeeds")).
            Eles permanecem no arquivo original da versão anterior.
            """)
    }

    /// The reader's own sources — a pasted link, an imported file — as entries a session can be built from.
    /// One table read of a small table, and the same authority (`reader_imported_sources`) the export and the
    /// import preview already read, so a selection, an export and a session can never disagree about which
    /// sources the reader brought.
    static func readerSourceEntries(in database: RuntimeDatabase) -> [ReaderImportEntry] {
        (try? ReaderLibraryStore(database: database).importedSources()) ?? []
    }

    /// V1's own template catalogue, read once: it is a bundled file, not a per-launch read.
    @ObservationIgnored private var contentFilterTemplatesUncached: [ReaderContentFilterTemplate]?

    private var contentFilterTemplates: [ReaderContentFilterTemplate] {
        if let contentFilterTemplatesUncached { return contentFilterTemplatesUncached }
        let templates = ReaderContentFilterCatalog.bundled()
        contentFilterTemplatesUncached = templates
        return templates
    }

    /// The exclusions the reader's own settings state right now.
    private func readerExclusions() -> ReaderContentExclusions {
        guard let database = libraryDatabase(), let settings = try? ReaderSettingsCoordinator(database: database).settings()
        else { return .disabled }
        return ReaderContentFilterPolicy.exclusions(settings: settings, templates: contentFilterTemplates)
    }

    /// The filter as it is applied: the reader's lens criteria, and their content filters.
    private func applied(_ filter: ReaderFilter) -> ReaderFilter {
        filter.replacing(exclusions: ReaderContentFilterPolicy.combining(context: filter.exclusions,
            global: readerExclusions()))
    }

    /// A context key as a session reads it. This is where the reader's content filters enter: every surface —
    /// the plain feed, a single source, a collection, a curated feed — reads the same globals, and the exclusions
    /// the **context** itself carries (a smart bookmark's own words) stay its own. What hides content is the sum
    /// of the two, and the master switch masks only the global half.
    private func applied(_ key: ContextKey) -> ContextKey {
        ContextKey(request: key.request, preset: key.preset, filter: applied(key.filter),
            searchScope: key.searchScope)
    }

    private func readerSourceEntries() -> [ReaderImportEntry] {
        guard let database = libraryDatabase() else { return [] }
        return Self.readerSourceEntries(in: database)
    }

    /// V1's "Reunir estas fontes": a collection built from the sources the reader's context is over, in one
    /// action. V2's context is over the reader's selected sources, so those are what it collects.
    @discardableResult
    func collectCurrentSources(named name: String) throws -> ReaderCollection? {
        guard let library = libraryCoordinator() else { return nil }
        return try library.collectSources(named: name, sourceKeys: feeds.map(\.principal))
    }

    /// V1's "Salvar como marcador inteligente": the context the reader is on, stored under a name, with the
    /// stored key naming its own preset so activating it is an ordinary transition (T6's identity). V1 also
    /// *switched* to the feed it had just saved (`setActivePreset(.smartFeed)`), so the reader sees it.
    @discardableResult
    func saveCurrentContextAsPreset(named name: String, kind: ReaderPreset.Kind) async throws -> ReaderPreset? {
        guard let library = libraryCoordinator() else { return nil }
        let preset = try library.savePreset(named: name, kind: kind, from: currentContextKey)
        try await activateSavedPreset(preset.key)
        return preset
    }

    /// Deletes the preset the reader is on, when it is one of their own. The surface returns to the plain one.
    func deleteCurrentPreset() async throws {
        guard let library = libraryCoordinator() else { return }
        let payload: String?
        switch currentContextKey.preset {
        case .smartFeed(let id), .curatedFeed(let id): payload = id
        default: payload = nil
        }
        guard let payload else { return }
        _ = try library.deletePreset(id: payload)
        try await applyFilter(currentFilter, preset: .everything)
    }

    /// Collection membership is already durable library state, not another mutable feed selection.
    /// Resolve it again for rebuilds and cold restoration of a collection context.
    private func collectionFeeds(id: String) throws -> [TrustedFeed] {
        guard let database = libraryDatabase() else { throw ReaderPreferencesError.invalidSelection }
        let library = ReaderLibraryStore(database: database)
        let keys = try library.sourceKeys(inCollection: id)
        let resolved = try TrustedFeed.resolveAvailable(keys: Array(keys), fallback: selectedFeeds,
            readerSources: readerSourceEntries(), catalogueURL: catalogueURL,
            identities: try library.sourceLinks())
        return resolved
    }

    /// A collection without any available members cannot be the active preset. The same
    /// reconciliation is used on cold restore and on later rebuilds after collection edits.
    private func sessionState(for proposed: ContextKey) throws -> (key: ContextKey, feeds: [TrustedFeed]) {
        let activeFeeds: [TrustedFeed]
        if case .collection(let id) = proposed.preset {
            activeFeeds = try collectionFeeds(id: id)
            if activeFeeds.isEmpty {
                let request: FeedContextRequest = selectedFeeds.count == 1
                    ? .source(selectedFeeds[0].sourceID) : .main
                return (ContextKey(request: request, preset: .everything, filter: proposed.filter,
                    searchScope: proposed.searchScope), selectedFeeds)
            }
        } else {
            activeFeeds = selectedFeeds
        }
        if case .source(let id) = proposed.request,
            !activeFeeds.contains(where: { $0.sourceID == id }) {
            return (ContextKey(request: .main, preset: proposed.preset, filter: proposed.filter,
                searchScope: proposed.searchScope), activeFeeds)
        }
        return (proposed, activeFeeds)
    }

    /// A collection is a session over its own sources, without changing the reader's selection.
    func openCollectionFeed(id: String) async throws {
        guard let preferences else { return }
        guard !(try collectionFeeds(id: id)).isEmpty else { throw ReaderPreferencesError.invalidSelection }
        guard !replacingSession else { return }
        replacingSession = true
        defer { replacingSession = false }
        if let retired = association {
            _ = try await retired.session.checkpointCurrentPosition(at: Date())
            await retired.close()
        }
        association = nil
        // The session exposes its own feeds; the persisted selection is left untouched.
        currentContextKey = ContextKey(request: .main, preset: .collection(id),
            filter: .unrestricted)
        _ = try preferences.setContext(currentContextKey)
        let next = try await association(contextKey: currentContextKey)
        association = next
        startupFailure = nil
        try await next.launch()
    }

    /// T11: the hood of the feed the reader is on, when it is one of their own.
    func currentCuratedSummary() -> CuratedFeedSummary? {
        guard case .curatedFeed(let id) = currentContextKey.preset,
            let preset = try? libraryCoordinator()?.preset(id: id), let recipe = preset.recipe else { return nil }
        return CuratedFeedSummary(name: preset.name, recipe: recipe)
    }

    /// Renaming a curated feed keeps its identity and its recipe: only the name changes.
    func renameCurrentCuratedFeed(to name: String) async throws {
        guard case .curatedFeed(let id) = currentContextKey.preset,
            let coordinator = makeCuratedCoordinator(), let preset = try coordinator.curatedPresets().first(where: { $0.id == id }),
            let recipe = preset.recipe else { return }
        _ = try coordinator.update(preset, recipe: recipe, named: name)
    }

    /// T11: whether the reader still has to meet the app. V1 gated on its own `hasSeenOnboarding`, which T10
    /// brought across as a preference.
    var needsOnboarding: Bool {
        !(((try? preferences?.load())??.settings.hasSeenOnboarding) ?? false)
    }

    /// The reader has met the app: the flag is a preference, and setting it is what a later launch reads.
    /// R18: the caller may only dismiss the first-run surface when this **returns true** — a refused write must not
    /// be presented as a completed onboarding.
    @discardableResult
    func completeOnboarding() -> Bool {
        guard let preferences, let current = try? preferences.load() else { return false }
        var settings = current.settings
        settings.hasSeenOnboarding = true
        guard (try? preferences.setSettings(settings)) != nil else { return false }
        noteReaderSettingsWritten()
        return true
    }

    /// F02's first run: the answers it collects (languages and places) become the reader's **discovery profile** —
    /// a preference, never a context identity — and the feed they enter is built from them. Nothing is created to
    /// be activated and nothing has to be named: the reader enters the feed, and the subjects are answered inside
    /// it. The session is rebuilt so the answers take effect now, not on the next launch; because the identity is
    /// unchanged, that rebuild **restores** the reader's position rather than resetting it.
    @discardableResult
    func completeFirstRun(discovery recipe: FeedRecipeDefinition) async -> Bool {
        var stored = false
        if let preferences, let current = try? preferences.load() {
            var settings = current.settings
            settings.discoveryProfile = recipe
            settings.hasSeenOnboarding = true
            if (try? preferences.setSettings(settings)) != nil { noteReaderSettingsWritten(); stored = true }
        }
        // R18: a refused write keeps the reader in the first run; rebuilding the session would present answers that
        // are not durable.
        guard stored else { return false }
        try? await replaceSession()
        return true
    }

    /// What the Composer can offer, from the catalogue the app already reads: its languages, and its own
    /// sections as topics (their keys are the ones a source is placed under, which is what a recipe stores).
    func onboardingOptions() -> (languages: [OnboardingLanguage], topics: [OnboardingTopic],
        regions: [OnboardingRegion]) {
        guard let catalogURL = catalogueURL,
            let coordinator = Optional(SourceManagementCoordinator(catalogURL: catalogURL,
                database: libraryDatabase())) else { return ([], [], []) }
        let languages = ((try? coordinator.languageGroups()) ?? [])
            .filter { !$0.isUndeclared }
            .prefix(12)
            .map { group in
                OnboardingLanguage(code: group.languageCode, name: group.displayName,
                    availableSources: group.availableSources,
                    variants: group.variants.map {
                        OnboardingLanguageVariant(code: $0.code, label: $0.variantLabel,
                            availableSources: $0.totalSources, hasRegion: $0.hasRegion)
                    })
            }
        let topics = ((try? coordinator.sections()) ?? []).map {
            OnboardingTopic(key: "topic:\($0.key)", name: $0.name)
        }
        // The regions are the catalogue's own country nodes: the benchmark's journey names one, and the pool
        // reads it as a placement like any other interest.
        let regions = ((try? coordinator.countries(limit: 40))?.values ?? []).map {
            OnboardingRegion(key: $0.key, name: $0.name)
        }
        return (Array(languages), topics, Array(regions))
    }

    /// The cards the Welcome and Composer scenes may show: the reader's own published cards, never a fabricated
    /// headline. An empty feed shows the scenes' own abstract panels.
    func onboardingPreviewCards(limit: Int = 6) -> [PresentationCard] {
        Array((association?.store.state.presentation?.window.items ?? []).prefix(limit))
    }

    /// T11: the reader's own curated feed. The Composer hands a recipe over; the coordinator stores it with the
    /// identity it resolves to, and the session ranks by it from then on.
    func makeCuratedCoordinator() -> CuratedFeedCoordinator? {
        libraryDatabase().map(CuratedFeedCoordinator.init(database:))
    }

    func saveCuratedFeed(_ recipe: FeedRecipeDefinition, named name: String) throws -> ReaderPreset? {
        try makeCuratedCoordinator()?.save(recipe, named: name)
    }

    func updateCuratedFeed(_ preset: ReaderPreset, recipe: FeedRecipeDefinition,
        named name: String) throws -> ReaderPreset? {
        try makeCuratedCoordinator()?.update(preset, recipe: recipe, named: name)
    }

    /// T10: the two tools, over the reader's own database. An export writes into the app's documents directory,
    /// which is where a share or a save can find it.
    func makeImportExportCoordinator() -> ReaderImportExportCoordinator? {
        guard let database = libraryDatabase() else { return nil }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Exports", isDirectory: true)
        return ReaderImportExportCoordinator(database: database, exportDirectory: documents)
    }

    /// The lists an export can cover right now: the reader's own sources, every collection and every box.
    func exportChoices() -> [ReaderExportChoice] {
        makeImportExportCoordinator()?.exportChoices() ?? []
    }

    /// The export a card or the menu asked for, as the sheet's text: the host produces and hands it over.
    func exportPreview(_ request: ReaderExportRequest) -> String? {
        try? makeImportExportCoordinator()?.preview(request)
    }

    /// Writes the export and returns where it is, for the platform share surface.
    func writeExport(_ request: ReaderExportRequest) -> URL? {
        try? makeImportExportCoordinator()?.export(request)
    }

    /// Reads an OPML file into what importing it would do. Nothing is written until `commitImport`.
    func previewImport(_ data: Data) async throws -> ReaderImportPreview? {
        try await makeImportExportCoordinator()?.previewImport(data)
    }

    /// Writes the preview's feeds and adopts the selection change they imply, so the session acquires them.
    func commitImport(_ preview: ReaderImportPreview) async -> ReaderImportResult? {
        guard let coordinator = makeImportExportCoordinator() else { return nil }
        let result = try? await coordinator.commitImport(preview)
        await adoptSelectionChange()
        return result
    }

    /// Adding a feed from a link: the reader pastes an address, discovery resolves it into a feed, and the feed
    /// is written to the same place an imported file's feeds go. The resolver is built over the app's own
    /// transport configuration, so a debug run that replaces the network still drives the real discovery code.
    func makeAddFeedStore() -> ReaderAddFeedStore? {
        guard let database = libraryDatabase() else { return nil }
        let resolver = FeedLinkResolver(transport: URLSessionFeedDiscoveryTransport(
            session: URLSession(configuration: transportConfiguration)))
        return ReaderAddFeedStore(backend: ReaderAddFeedAdapter(database: database, resolver: resolver),
            clipboard: {
                #if canImport(UIKit)
                return UIPasteboard.general.string
                #else
                return nil
                #endif
            })
    }

    /// T10: the settings surface's store, and the appearance the reader's own preferences imply right now.
    func makeReaderSettingsStore() -> ReaderSettingsStore? {
        libraryDatabase().map { database in
            ReaderSettingsStore(backend: ReaderSettingsBackendAdapter(database: database) { [weak self] in
                // The one place a settings write refreshes what the feed reads: the snapshot this composition
                // caches for its per-card render path and the per-subject answers cached beside it.
                self?.noteReaderSettingsWritten()
            })
        }
    }

    /// The content filters' own surface: the gate, the templates and the reader's words, over the same
    /// preferences. A change here is a change to what every session hides, so the caller rebuilds the session
    /// when the surface closes — exactly as a filter applied from the sheet does.
    func makeContentFilterStore() -> ReaderContentFilterStore? {
        libraryDatabase().map { database in
            ReaderContentFilterStore(backend: ReaderContentFilterAdapter(database: database,
                templates: contentFilterTemplates))
        }
    }

    /// The appearance this hour implies for the stored preferences. Derived on demand, never kept as state: a
    /// clock moving the palette must not become a second source of truth about how the app looks.
    func currentAppearance() -> ReaderAppearance {
        libraryDatabase().map { ReaderSettingsCoordinator(database: $0).appearance() } ?? .standard
    }

    /// The library file's size, as the settings surface states it.
    func libraryStorageDescription() -> String? {
        let url = directory.appendingPathComponent("runtime.sqlite")
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 else {
            return nil
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// The reader's playback state, as the shell draws it.
    var mediaState: ReaderMediaState { mediaAdapter.state }

    /// T9: the four intents the surfaces issue. They are the coordinator's, wrapped so the shell never holds it.
    func toggleMedia(cardID: PublicationCardID? = nil) async {
        guard let media else { return }
        if let cardID { await media.toggle(cardID: cardID) }
        else if media.state.isPlaying { await media.pause() } else { await media.resume() }
    }

    func skipMedia(by seconds: TimeInterval) async { await media?.skip(by: seconds) }

    func seekMedia(to seconds: TimeInterval) async { await media?.seek(to: seconds) }

    func stopMedia() async { await media?.stop() }

    #if DEBUG
    /// T9 UI evidence: a real, playable episode without a network or a bundled asset. The hook writes a silent
    /// WAV to the app's own temporary directory and plays it through the same adapter a card would use — the bar,
    /// the state machine and AVFoundation are all the real ones.
    func startSimulatedPlayback() async {
        guard let url = try? Self.writeSilentWavefile(seconds: 30) else { return }
        // The identity is fixed: a run that plays, leaves the app and comes back must find the same episode, and
        // that is exactly what the resume path is about (V1 keyed its positions by item id for the same reason).
        try? await mediaAdapter.play(.init(cardID: Self.simulatedEpisodeID, url: url,
            title: String(localized: "Episódio de teste"), mimeType: "audio/wav"))
    }

    /// The simulated episode's own identity, stable across launches of a simulator run.
    static let simulatedEpisodeID = PublicationCardID(rawValue:
        UUID(uuidString: "90000000-0000-4000-8000-000000000001")!)

    private static func writeSilentWavefile(seconds: Int) throws -> URL {
        let sampleRate = 8_000, samples = sampleRate * seconds
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + samples))
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate)); append(UInt16(1)); append(UInt16(8))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(samples))
        data.append(contentsOf: [UInt8](repeating: 128, count: samples))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("feedmine-simulated.wav")
        try data.write(to: url, options: .atomic)
        return url
    }
    #endif

    /// The media coordinator, over the same database file every other surface opens. When the composition
    /// itself failed to open one, the media surface says so instead of pretending to play.
    private var media: ReaderMediaCoordinator? {
        guard let database = libraryDatabase() else { return nil }
        return ReaderMediaCoordinator(database: database, player: mediaAdapter)
    }

    /// The content filters changed (settings or the rules surface): the session is rebuilt, because what it
    /// hides is part of the identity it published under — the same rule the lens criteria follow. Nothing is
    /// erased: the rules stay in the reader's preferences either way.
    func reapplyReaderFilters() async {
        guard association != nil, !replacingSession else { return }
        guard applied(currentContextKey) != association?.contextKey else { return }
        do { try await replaceSession() }
        catch {
            startupFailure = "Não foi possível atualizar seus filtros."
            startupFailureDetail = String(describing: error)
            Self.log("startup failure updating content filters: \(String(describing: error))")
        }
    }

    /// T7: the source surface's store, over the catalog coordinator. One store per presentation, so its
    /// levels and the reader's selection are one consistent picture while it is open.
    func makeSourceManagementStore() -> SourceManagementStore {
        let database = libraryDatabase()
        return SourceManagementStore(backend: SourceCatalogBackend(
            coordinator: SourceManagementCoordinator(
                installation: CatalogInstallation(appDirectory: directory), database: database),
            healthProvider: { await self.sourceHealth() }))
    }

    /// T7: what the runtime observed about each source this launch, keyed by the catalog key the surface
    /// knows. A source it never attempted is absent from the map, so no row claims a state nobody measured.
    func sourceHealth() async -> [String: CatalogSourceHealth] {
        guard let association else { return [:] }
        let observed = await association.coordinator.healthSnapshot()
        guard !observed.isEmpty else { return [:] }
        var health: [String: CatalogSourceHealth] = [:]
        for feed in association.feeds {
            guard let target = observed[feed.targetID] else { continue }
            health[feed.principal] = CatalogSourceHealth(state: target.consecutiveFailures > 0
                ? .failing(consecutive: target.consecutiveFailures)
                : .responding)
        }
        return health
    }

    /// T7: the source surface writes the selection through the coordinator, so the app re-reads the persisted
    /// selection when that surface closes and rebuilds the association only if it actually changed — looking
    /// at the list is not a selection change, and an emptied selection is a state the reader's own surface
    /// states.
    func adoptSelectionChange() async {
        guard let preferences, let record = try? preferences.load() else { return }
        guard record.selectionVersion != selectionVersion else { return }
        selectionVersion = record.selectionVersion
        let links = (try? libraryDatabase().map {
            try ReaderLibraryStore(database: $0).sourceLinks()
        }) ?? [:]
        let resolved = (try? TrustedFeed.resolveAvailable(keys: record.sourceKeys, fallback: selectedFeeds,
            readerSources: readerSourceEntries(), catalogueURL: catalogueURL, identities: links)) ?? []
        if let database = libraryDatabase() {
            try? ReaderLibraryStore(database: database).rememberResolvedSources(resolved.map {
                (key: $0.principal, authority: $0.principalNamespace == ReaderSourceIdentity.principalNamespace
                    ? "reader" : "catalog")
            })
        }
        selectedFeeds = resolved
        // One selected source is its own surface, exactly as `toggleSource` decides; a context pointing at a
        // source that is no longer selected would be a fence around nothing.
        let request: FeedContextRequest = resolved.count == 1 ? .source(resolved[0].sourceID) : .main
        currentContextKey = ContextKey(request: request, preset: presetAfterSelectionChange(),
            filter: currentContextKey.filter)
        _ = try? preferences.setContext(currentContextKey)
        do { try await replaceSession() }
        catch {
            startupFailure = "Não foi possível atualizar suas fontes."
            startupFailureDetail = String(describing: error)
            Self.log("startup failure updating the source selection: \(String(describing: error))")
        }
    }

    /// T11: the ranking this context runs on, and the version that says so. A curated feed's recipe resolves
    /// into multipliers over the *sources'* own identities (the engine sees SourceIDs, the recipe speaks catalog
    /// keys), and its version is derived from the recipe so an edit is a new behaviour for a checkpoint.
    /// What a session ranks by for one context. A context that is not a curated feed ranks equally, under the
    /// baseline behaviour version.
    func scoring(for key: ContextKey) -> (ResolvedSelectionPolicy.ScoringBehavior, UInt64) {
        guard case .curatedFeed(let id) = key.preset,
            let preset = try? libraryCoordinator()?.preset(id: id), let recipe = preset.recipe else {
            return (.equal, 1)
        }
        let version = UInt64(max(1, preset.recipeRevision))
        let multipliers = FeedRecipeResolution.multipliers(for: feedFacts(), recipe: recipe)
        guard !multipliers.isEmpty else { return (.equal, version) }
        let bySource = Dictionary(uniqueKeysWithValues: feeds.compactMap { feed in
            multipliers[feed.principal].map { (feed.sourceID, $0) }
        })
        return bySource.isEmpty ? (.equal, version) : (.weighted(bySource), version)
    }

    /// What the catalogue says about each feed this session reads: the facts a recipe is resolved against.
    func feedFacts() -> [FeedRecipeResolution.SourceFacts] {
        guard let catalogURL = catalogueURL,
            let catalog = try? LegacyCatalogReader(catalogURL: catalogURL) else { return [] }
        return feeds.compactMap { feed in
            guard let record = try? catalog.source(key: feed.principal) else { return nil }
            let host = record.displayHost ?? URL(string: record.requestURL)?.host ?? record.key
            let editorial = FeedEditorialReader.assess(.init(title: record.title,
                description: record.sourceDescription, tags: record.tags, host: host,
                qualityScore: record.qualityScore, activity: record.activity, nature: record.nature))
            return FeedRecipeResolution.SourceFacts(identity: record.key, nodeKeys: record.nodeKeys,
                mediaKind: record.mediaKind, nature: record.nature, qualityScore: record.qualityScore,
                editorial: editorial)
        }
    }

    /// A stable version for a recipe: an FNV-1a over its canonical JSON, so the same recipe is always the same
    /// behaviour and any edit is a different one.
    /// The one place a session is built: every transition ranks with the context's own scoring. A collection's
    /// own feed passes its own sources; everything else is the reader's selection.
    private func association(contextKey: ContextKey) async throws -> FeedAssociation {
        // The detached pool may finish after an activation. It retries for the current fingerprint;
        // resolve the selected sources, policy and traversal *after* that await so they all agree about the
        // authority one new association is using.
        let initial = try sessionState(for: contextKey)
        var profile = discoveryProfile(for: applied(initial.key))
        let requestedFingerprint = catalogueSnapshot?.fingerprint
        var read = await discoveryRead(profile: profile)
        let snapshot = catalogueSnapshot
        // Actor reentrancy can allow an activation *between* returning an old cached pool and
        // resuming this constructor. Do not combine that pool with the replacement snapshot.
        if requestedFingerprint != snapshot?.fingerprint {
            return try await association(contextKey: contextKey)
        }
        // An answer received while the detached read was running is behaviour, not identity (F02): the constructor
        // is a boundary that answer must cross. Capturing the profile before the await and never looking again made
        // the final association read the interests the reader had *before* answering — measured by
        // `testAnswerDuring{Context,Preset,Replace}TransitionIsApplied`, which lands the answer exactly in this
        // window. Bounded: each pass only runs when the profile really changed.
        for _ in 0..<2 {
            let current = discoveryProfile(for: applied(initial.key))
            guard current != profile else { break }
            profile = current
            read = await discoveryRead(profile: profile)
        }
        let session = try sessionState(for: contextKey)
        if session.key != contextKey {
            currentContextKey = session.key
            _ = try preferences?.setContext(session.key)
        }
        return try makeAssociation(contextKey: session.key, profile: profile, read: read, warmLaunch: false)
    }

    /// The one place an association is built. The **asynchronous** launch and the **warm** launch hand the same
    /// inputs to the same constructor, so there is one shape of session and not two: what differs is only when they
    /// can run (the warm one cannot `await`, because the reader's own window has to exist before the first frame)
    /// — and therefore how much of discovery exists when it is built.
    private func makeAssociation(contextKey: ContextKey, profile: ReaderDiscoveryProfile,
        read: DiscoveryRead?, warmLaunch: Bool) throws -> FeedAssociation {
        let session = try sessionState(for: contextKey)
        if session.key != contextKey {
            currentContextKey = session.key
            _ = try preferences?.setContext(session.key)
        }
        let key = applied(session.key)
        let (scoring, version) = scoring(for: key)
        let association = try FeedAssociation(directory: directory, feeds: session.feeds,
            discovery: read?.feeds ?? [], subjects: read?.subjects ?? [:],
            configuration: transportConfiguration, trace: trace, database: libraryDatabase(),
            discoveryTraversal: discoveryTraversal(for: key, profile: profile, snapshot: catalogueSnapshot),
            contextKey: key, selectionVersion: selectionVersion, scoring: scoring, scoringVersion: version,
            catalogueURL: catalogueSnapshot?.catalogueURL, editorialExposure: editorialExposure,
            discoveryProfile: profile, warmLaunch: warmLaunch, launchSettings: launchSettings,
            monotonicNow: monotonicNow, bookmarkRead: bookmarkRead)
        #if DEBUG
        sessionConstructions += 1
        #endif
        return connecting(association)
    }

    /// The association a **warm** launch starts from — the same session `launch()` would build, built
    /// **synchronously** because the reader's own window has to exist before this launch's first frame, and built
    /// over **nothing the catalogue has to be scanned for**.
    ///
    /// A warm launch is local (INV-07). The pool a profile names is not: it is a query that walks the shipped
    /// catalogue until it has `limit × 4` candidates, and against that file it is the largest single cost of the
    /// launch (measured: 2,5–2,8 s for the profile of a first run, more than this machine's whole warm first
    /// frame). Reading it here put that cost **between the launch screen and the reader's own feed**, which is the
    /// one place this criterion forbids work. What discovery brings therefore arrives the way every other
    /// opportunity brings it: behind the reader's window, on the detached pass (`discoveryRead`), adopted by the
    /// running association in `launch()` — and the walk keeps resuming its own bounded page per opportunity.
    ///
    /// Only a launch the previous interaction made durable takes this path (see the guard in `init`): a launch with
    /// nothing to show keeps the asynchronous path and the preparation surface the doctrine gives it.
    private func warmAssociation() throws -> FeedAssociation {
        let initial = try sessionState(for: currentContextKey)
        let profile = discoveryProfile(for: applied(initial.key))
        return try makeAssociation(contextKey: initial.key, profile: profile,
            read: alreadyReadDiscovery(profile: profile), warmLaunch: true)
    }

    /// What **this process** has already read for the profile, and nothing more. It is the same cache
    /// `discoveryRead` fills — there is no second one — so a launch that inherits a pool pays nothing for it,
    /// and a launch that does not simply states no discovery yet.
    private func alreadyReadDiscovery(profile: ReaderDiscoveryProfile) -> DiscoveryRead? {
        guard !profile.isEmpty, let snapshot = catalogueSnapshot else { return nil }
        return discoveryCache[DiscoveryCacheKey(profile: profile, fingerprint: snapshot.fingerprint)]
    }

    /// The walk discovery is on for this context's profile. Bounded by the same rule as the pool: no catalogue, no
    /// profile, no traversal — and an empty profile is "no answers yet", not a reason to invent one.
    private func discoveryTraversal(for key: ContextKey, profile: ReaderDiscoveryProfile,
        snapshot: CatalogSnapshot?) -> ReaderDiscoveryTraversal? {
        guard let snapshot, !profile.isEmpty else { return nil }
        let walk = DiscoveryWalkKey(profile: profile, contextKey: key, catalogue: snapshot.fingerprint)
        if let existing = discoveryTraversals[walk] { return existing }
        let traversal = ReaderDiscoveryTraversal(builder: ReaderDiscoveryBuilder(catalogURL: snapshot.catalogueURL),
            profile: profile, contextKey: key,
            installation: CatalogInstallation(appDirectory: directory))
        discoveryTraversals[walk] = traversal
        return traversal
    }

    /// The one read of a profile's pool — **one result**, with the two facts that say what it is about. It used
    /// to arrive as two pieces of composition state (`discoveryCache` plus a `discoverySubjects` map), so a query
    /// that concluded after the reader had moved answered for the interests they have **now** with the pool of the
    /// interests they had **then**: the map was written by whichever read finished last, and the invitation of the
    /// session being read consulted it. A value cannot do that.
    ///
    /// **It does not run on the main actor.** See `liveDiscoveryQuery` for the measured reason.
    private func discoveryRead(profile: ReaderDiscoveryProfile) async -> DiscoveryRead? {
        guard !profile.isEmpty, let snapshot = catalogueSnapshot else { return nil }
        let cacheKey = DiscoveryCacheKey(profile: profile, fingerprint: snapshot.fingerprint)
        if let cached = discoveryCache[cacheKey] { return cached }
        let url = snapshot.catalogueURL
        let (entries, subjects) = await discoveryQuery(profile, url)
        let read = DiscoveryRead(profile: profile, fingerprint: snapshot.fingerprint,
            entries: entries, subjects: subjects)
        discoveryCache[cacheKey] = read
        // A read prepared for revision 5 can finish after activation of 6. Its keyed result stays valid for any
        // context still reading 5; it simply does not answer for the revision this launch now reads through.
        guard catalogueSnapshot?.fingerprint == snapshot.fingerprint else {
            return await discoveryRead(profile: profile)
        }
        return read
    }

    /// The interests a context states, in the catalogue's vocabulary. **The reader's own answers come first**
    /// (F02): the discovery preferences page and the invitations answered inside the feed write them into the
    /// settings, which are behaviour — never a context's identity, so a new answer cannot move the reader out of
    /// what they were reading. A curated feed then states its recipe, and anything else its own lens criteria.
    func discoveryProfile(for key: ContextKey) -> ReaderDiscoveryProfile {
        #if DEBUG
        // A UI fixture that must stay hermetic: discovery is what reaches arbitrary catalogue sources, and a
        // transition test should not depend on the public network. This switch is DEBUG-only and named for the
        // fixture; release builds never read it.
        if ProcessInfo.processInfo.environment["FEEDMINE_DISABLE_DISCOVERY"] == "1" {
            return ReaderDiscoveryProfile()
        }
        #endif
        if let stored = (try? preferences?.load())??.settings.discoveryProfile, Self.namesAnything(stored) {
            return Self.discoveryProfile(from: stored)
        }
        if case .curatedFeed(let id) = key.preset, let recipe = (try? libraryCoordinator()?.preset(id: id))??.recipe {
            return Self.discoveryProfile(from: recipe)
        }
        return ReaderDiscoveryProfile(languages: key.filter.languages,
            topicNodeKeys: key.filter.taxonomyNodeIDs)
    }

    /// Whether a stored recipe says anything at all: a neutral recipe is "no answers yet", not a profile.
    static func namesAnything(_ recipe: FeedRecipeDefinition) -> Bool {
        !recipe.languages.isEmpty || !recipe.topicPreferences.isEmpty || !recipe.editorialPreferences.isEmpty
    }

    /// A recipe in the catalogue's vocabulary. The rule lives on `ReaderDiscoveryProfile` so the onboarding answer
    /// and the acquisition snapshot read it the same way (and a test can state it without the app host).
    static func discoveryProfile(from recipe: FeedRecipeDefinition) -> ReaderDiscoveryProfile {
        ReaderDiscoveryProfile(recipe: recipe)
    }

    /// F02's in-feed answer: the reader says where to explore more (or less) of, answering a card the app itself
    /// went and found. The answer is a **preference about future discovery**, which is what the block itself
    /// promises ("Sua resposta orienta a busca … nas próximas descobertas"), so it is written and read back — and
    /// the session the reader is **not** rebuilt.
    ///
    /// It used to be: the answer was persisted and then `replaceSession()` ran, which retired the association and
    /// admitted a new one from the checkpoint. That moved the reader: the checkpoint carries a card and a
    /// placement but **no offset inside the card**, so the restore re-anchored as it saw fit (measured on the
    /// device, 2026-10-11: the reader's anchored card moved 139 pt in one run and 912 pt in another, and the whole
    /// point of the answer is that nothing the reader is looking at moves). The admitted window, its edition and
    /// its order were already promised intact — now they are intact because nothing rebuilds them, and the
    /// preference reaches discovery the next time a session is built for this context.
    ///
    /// Returns whether the answer is **really** in effect. Codex's finding 4: swallowing the write let the surface
    /// show an answer that was never persisted — the reader's own action has to be observable.
    @discardableResult
    func voteOnTopic(nodeKey: String, level: ReaderPreferenceLevel) async -> Bool {
        let node = nodeKey.hasPrefix("topic:") ? String(nodeKey.dropFirst("topic:".count)) : nodeKey
        guard !node.isEmpty, let preferences, let current = try? preferences.load() else { return false }
        var settings = current.settings
        // "Neutral" is not an answer: taking one back removes the entry rather than storing a third state the
        // reader never chose.
        settings.discoveryProfile.topicPreferences["topic:\(node)"] = level == .neutral ? nil : level
        do {
            _ = try preferences.setSettings(settings)
            noteReaderSettingsWritten()
        } catch {
            trace?.record("answer_failed", ["subject": node, "stage": "persist"])
            return false
        }
        trace?.record("answer_applied", ["subject": node, "level": level == .more ? "more" : (level == .less ? "less" : "neutral")])
        // The line is made durable at once: a run that ends before the next viewport event must still be able to
        // show that the reader's answer was applied (architect, 2026-10-11).
        trace?.flush()
        // **O leitor não se move por causa de uma resposta, nem quando uma construção está em curso.** A versão
        // anterior pedia um passe extra ao laço quando a resposta chegava com `replacingSession` verdadeiro
        // (`pendingRebuild = true`). Medido no B04 (2026-10-18): a construção em curso terminava **depois** do
        // toque, o passe extra trocava o `FeedAssociation` (novo store, nova `sequenceID`, `position` de volta a 1),
        // o `UIScrollView` era recriado e o offset nativo ia de 2052,3 para 2163,7 — a carta sob o leitor andava
        // 316 pt (610 → 294), e o motorista atribuía o movimento à resposta. A resposta é uma preferência sobre a
        // **próxima** descoberta: a sessão que já está sendo construída não precisa ser reconstruída por ela, e
        // reconstruí-la custa a posição do leitor (o checkpoint carrega carta e colocação, não o offset dentro da
        // carta). Nada é reconstruído por uma resposta, nunca.
        return true
    }


    /// The facts the feed's own invitation depends on, recorded once per window change — off the render path.
    /// `traversed` is what round 10 needed and nothing measured: the cards the reader **really** passed, which is
    /// the budget's own unit — a rendered window is not a read window.
    func recordWindowFacts(cards: Int, resolvedSources: Int, withSubject: Int, knownSubjects: Int,
        tipsHidden: Bool, traversed: Int, offersShown: Int) {
        trace?.record("window", ["cards": String(cards), "resolved_sources": String(resolvedSources),
            "with_subject": String(withSubject), "tips_hidden": String(tipsHidden),
            "known_subjects": String(knownSubjects),
            "cards_traversed": String(traversed), "offers_shown": String(offersShown)])
    }

    /// One line per invitation the feed placed, with the budget that allowed it. The frequency clause round 10
    /// asked for reads this; without it, "uma oferta por assunto" was the only rule anyone could see.
    func recordEditorialOffer(subject: String, cardsTraversed: Int, offersShown: Int, interval: Int) {
        trace?.record("editorial_offer", ["subject": subject, "cards_traversed": String(cardsTraversed),
            "offers_shown": String(offersShown), "interval": String(interval)])
    }

    /// One line per invitation the budget **refused**, with the policy's own reason. The frequency clause is
    /// auditable only if both sides are recorded: without this, the trace shows the offers that happened and says
    /// nothing about the ones that did not (QA, 2026-10-14).
    func recordEditorialRefusal(refusal: String, subject: String, cardsTraversed: Int, offersShown: Int,
        interval: Int) {
        trace?.record("editorial_refusal", ["reason": refusal, "subject": subject,
            "cards_traversed": String(cardsTraversed), "offers_shown": String(offersShown),
            "interval": String(interval)])
    }

    /// The reader's stored settings, read **once** and reused until something writes them.
    ///
    /// V1's own lesson (`docs/release/review-feed-responsiveness-build-5.md`, finding 2): eligibility is an
    /// immutable snapshot, rebuilt only when its revision changes. The feed asks "was this subject answered?" — and
    /// "are the tips hidden?" — for every candidate card of every body evaluation, and answering from SQLite each
    /// time is a synchronous read on the main actor per card per render: measured, `preferences.load()` was reached
    /// once per card through the `||` short-circuit, plus one more per discovery candidate.
    @ObservationIgnored private var readerSettingsSnapshot: ReaderSettings?
    /// The per-subject answer, so a window of five hundred cards asks the database once per subject instead of once
    /// per card. `.neutral` is remembered too: "nothing declared" is an answer worth caching.
    @ObservationIgnored private var declaredLevels: [String: ReaderPreferenceLevel] = [:]

    private func readerSettings() -> ReaderSettings? {
        if let snapshot = readerSettingsSnapshot { return snapshot }
        let settings = (try? preferences?.load())??.settings
        readerSettingsSnapshot = settings
        return settings
    }

    /// A write just happened. The cache is **dropped**, not overwritten with the writer's copy: two writers can
    /// reach the main actor in either order, and a value carried across that boundary can be older than what the
    /// database holds. Invalidation has no order to get wrong; the next read takes the stored value once.
    private func noteReaderSettingsWritten() {
        readerSettingsSnapshot = nil
        declaredLevels.removeAll(keepingCapacity: true)
    }

    /// What the reader has already said about a subject, if anything: the feed does not ask twice. Answered from the
    /// cached settings and remembered per subject — this is called for candidate cards of every render.
    func declaredLevel(forNode nodeKey: String) -> ReaderPreferenceLevel? {
        let node = nodeKey.hasPrefix("topic:") ? String(nodeKey.dropFirst("topic:".count)) : nodeKey
        if let remembered = declaredLevels[node] { return remembered == .neutral ? nil : remembered }
        let level = readerSettings()?.discoveryProfile.topicPreferences["topic:\(node)"] ?? .neutral
        declaredLevels[node] = level
        return level == .neutral ? nil : level
    }

    /// What the feed may invite the reader to explore, per source the app **discovered**: the catalogue's own
    /// section the source is filed under, with the catalogue's own name for it. A source the reader chose
    /// themselves is not offered one — the invitation is about discovery, and discovery is what the app did.
    ///
    /// It belongs to the **session** that did the discovering and lives on it (`FeedAssociation.subjects`): a map
    /// held by the composition was written by whichever query concluded last, so a pool read for the interests the
    /// reader had before could answer the invitations of the session they are reading now.
    ///
    /// The subject a card may be asked about, and only when the invitation would be true (Codex's finding 2):
    /// a source the reader **chose** is not discovery, and a subject found under an earlier profile does not belong
    /// to the association being read. Explicit choice takes precedence over what the app went looking for.
    func editorialSubject(for sourceID: SourceID, in association: FeedAssociation) -> EditorialSubject? {
        guard !association.feeds.contains(where: { $0.sourceID == sourceID }) else { return nil }
        guard association.discovery.contains(where: { $0.sourceID == sourceID }) else { return nil }
        return association.subjects[sourceID]
    }

    /// The reader hid the invitations: a preference, and the settings page is where they come back. Read from the
    /// cached settings, because the feed asks it for every card of the window (the `||` short-circuit only skips it
    /// while the reader's session-local answer is already true).
    var editorialTipsHidden: Bool {
        readerSettings()?.editorialTipsHidden ?? false
    }

    func setEditorialTipsHidden(_ hidden: Bool) {
        guard let preferences, let current = try? preferences.load() else { return }
        var settings = current.settings
        settings.editorialTipsHidden = hidden
        guard (try? preferences.setSettings(settings)) != nil else { return }
        noteReaderSettingsWritten()
    }

    /// What the feed may ask about: a subject with the catalogue's own name for it.
    struct EditorialSubject: Sendable {
        let nodeKey: String
        let name: String
    }

    /// The catalogue's names for the *placements* — one reader, one bounded pass, resolved per key and remembered.
    ///
    /// The subject of an invitation is the **shallowest** placement the catalogue files the source under: a reader
    /// is offered "Religion", not `90_countries/brazil/religion-spirituality/religion`. Coverage is by **entry**,
    /// never by a slice of the key set — a source whose keys happen to sort late is still offered, which is what a
    /// ceiling over sorted keys silently took away from one whole profile.
    nonisolated static func subjects(in entries: [LegacyCatalogEntry], catalogURL: URL,
        ceiling: Int = 120) -> [SourceID: EditorialSubject] {
        var names: [String: String] = [:]
        var subjects: [SourceID: EditorialSubject] = [:]
        guard let reader = try? LegacyCatalogReader(catalogURL: catalogURL) else { return [:] }
        for entry in entries.prefix(ceiling) {
            let keys = entry.nodeKeys.sorted { left, right in
                let leftDepth = left.split(separator: "/").count, rightDepth = right.split(separator: "/").count
                return leftDepth == rightDepth ? left < right : leftDepth < rightDepth
            }
            for key in keys {
                if names[key] == nil { names[key] = (try? reader.node(key: key))??.name }
                guard let name = names[key] else { continue }
                // The same identity the cards carry (`trustedFeed(from:)` takes `source.id`).
                subjects[entry.source.id] = EditorialSubject(nodeKey: key, name: name)
                break
            }
        }
        return subjects
    }

    static func nodeKey(of key: String) -> String {
        key.hasPrefix("topic:") ? String(key.dropFirst("topic:".count)) : key
    }

    /// How many sources one profile may pull out of the catalogue. B01 asks for at least fifty distinct sources
    /// acquired automatically; this is the ceiling the runtime may contact, not a page size.
    /// `nonisolated` because `discoveryPool` is: a constant is not state, and the detached pass that reads it must
    /// not touch the main actor.
    nonisolated static let discoverySourceLimit = 120

    /// The pool a profile names, over the installed catalogue, with the subjects a card is attributed with — the
    /// one computation behind `discoveryRead`, the detached pass every launch reads it through. It is deliberately
    /// on no path that must finish before a first frame: the query walks the shipped catalogue.
    nonisolated static func discoveryPool(profile: ReaderDiscoveryProfile, catalogueURL: URL)
        -> (entries: [LegacyCatalogEntry], subjects: [SourceID: EditorialSubject]) {
        let pool = (try? ReaderDiscoveryBuilder(catalogURL: catalogueURL).pool(for: profile,
            limit: discoverySourceLimit))?.entries ?? []
        return (pool, subjects(in: pool, catalogURL: catalogueURL))
    }

    /// The catalogue read a profile's discovery comes from: what the catalogue offers, and the subject it
    /// attributes to each source it offered. The product's own is the detached pass below; a test that must decide
    /// **when** a read concludes hands its own (see `init`).
    typealias DiscoveryQuery = @Sendable (ReaderDiscoveryProfile, URL) async
        -> (entries: [LegacyCatalogEntry], subjects: [SourceID: EditorialSubject])

    /// The product's read: the pool query **and** the subject names in one detached pass. Opening the shipped
    /// 118 MB catalogue once per node key — which is what asking the catalogue for a name does — put seconds of
    /// work on the main actor, right where the reader waits for their feed. Measured against that file, one pool
    /// costs 2,5–2,8 s, which on the main actor is a frozen first run (the acceptance driver observed the app's
    /// main thread busy for 30 s).
    nonisolated static let liveDiscoveryQuery: DiscoveryQuery = { profile, catalogueURL in
        await Task.detached(priority: .userInitiated) {
            AppComposition.discoveryPool(profile: profile, catalogueURL: catalogueURL)
        }.value
    }
    @ObservationIgnored private let discoveryQuery: DiscoveryQuery
    /// The reader's instant for every runway sample (R01). A test injects a controlled clock, so coalescing
    /// can be proven not to turn the drain's latency into reading velocity; production is the process uptime.
    @ObservationIgnored private let monotonicNow: @Sendable () -> RunwayMonotonicTime
    /// R02's test seam: the durable bookmark read. Nil means the product's detached read over the one library
    /// database; a test suspends it to prove installation never calls it.
    @ObservationIgnored private let bookmarkRead: (@Sendable () async throws -> Set<PublicationCardID>)?

    /// What one profile's query answered, and the two facts the answer is about: the profile it was read for and
    /// the catalogue revision it read. **One value, returned** — it used to arrive as two pieces of composition
    /// state a later query overwrote, so a read prepared for the reader's previous interests could answer for the
    /// ones they have now (A→B with A concluding last). The cache holds this value and nothing else.
    struct DiscoveryRead: Sendable {
        let profile: ReaderDiscoveryProfile
        let fingerprint: String
        let entries: [LegacyCatalogEntry]
        let subjects: [SourceID: EditorialSubject]
        /// The reader's own feed shape of the same entries, derived once: the pool is the entries.
        var feeds: [TrustedFeed] { entries.map(AppComposition.trustedFeed(from:)) }
    }

    /// The reader's own feed shape of one catalogue entry. `nonisolated` because the read value derives it and a
    /// read is not main-actor state: the entries are a value, the mapping is a pure function of them.
    nonisolated static func trustedFeed(from entry: LegacyCatalogEntry) -> TrustedFeed {
        TrustedFeed(targetID: entry.targetID, sourceID: entry.source.id, bindingID: entry.bindingID,
            principal: entry.principal, endpoint: entry.endpoint, displayName: entry.source.displayName)
    }

    /// Profiles already resolved this launch: the catalogue query is done once per profile, and a context
    /// transition that asks for the same profile is free. The cached value **is** the answer — entries, subjects
    /// and its two facts — so reading it again cannot pick up another profile's answer.
    struct DiscoveryCacheKey: Hashable {
        let profile: ReaderDiscoveryProfile
        let fingerprint: String
    }
    @ObservationIgnored private var discoveryCache: [DiscoveryCacheKey: DiscoveryRead] = [:]

    /// The discovery **traversal** for a profile, remembered per profile. A page cursor **is** progress, so it
    /// cannot live in an array handed out once: recreating the traversal on every association would re-find the same
    /// first page forever, which is the "gain over time" this work exists to produce. A different profile is a
    /// different walk (a new object), and the same profile resumes the walk it had.
    ///
    /// The key is the pair, not the profile alone: a traversal carries **one** `contextKey` and
    /// `advanceDiscovery` refuses a context whose key differs, so sharing one walk between two contexts that happen
    /// to share a profile would make the second context's discovery throw instead of advance.
    struct DiscoveryWalkKey: Hashable {
        let profile: ReaderDiscoveryProfile
        let contextKey: ContextKey
        /// The catalogue this walk pages. A new corpus is a different universe, and resuming a cursor across it
        /// would be resuming someone else's walk — `ReaderDiscoveryBuilder` refuses exactly that mismatch, so the
        /// identity belongs here rather than in a retry.
        let catalogue: String
    }
    @ObservationIgnored private var discoveryTraversals: [DiscoveryWalkKey: ReaderDiscoveryTraversal] = [:]

    /// Explicit session replacement; no replacement occurs during normal feed opportunities.
    /// Rebuilds the session around the answers as they are **now**. A second answer that lands while a rebuild is
    /// in flight does not vanish into the early return (Codex's finding 3): it is remembered, and the rebuild that
    /// is running repeats once it finishes, re-reading the settings — so what the reader answered is what the
    /// session reads, not what the settings held when the rebuild started.
    /// The reader asked for a refresh. Their answers are about **discovery**, and a refresh that produces new
    /// cards is exactly where a pending answer has to land: when the stored profile is no longer the one this
    /// session's pool was built from, the session is rebuilt — the reader *asked* for movement here, so a rebuild
    /// is legitimate (product owner, 2026-10-11). Nothing is rebuilt when nothing changed.
    func refreshFromTheReader() async {
        guard let association else { return }
        if association.discoveryProfile == discoveryProfile(for: currentContextKey) {
            await association.retryNow()
            return
        }
        try? await replaceSession()
    }

    func replaceSession() async throws {
        guard !replacingSession else { pendingRebuild = true; return }
        replacingSession = true
        defer { replacingSession = false }
        repeat {
            pendingRebuild = false
            let retired = association
            // Retire the old session only once its last position is durable: a checkpoint refusal leaves the
            // reader's coherent session in place instead of a transition that shows nothing.
            if let retired {
                _ = try await retired.session.checkpointCurrentPosition(at: Date())
                await retired.close()
            }
            association = nil
            let next = try await association(contextKey: currentContextKey)
            association = next
            startupFailure = nil
            // P1: a search context is a surface, not a feed window. Start the unified page as soon as the store
            // exists, before the feed launch (which can wait on acquisition for tens of seconds); otherwise the
            // reader stares at the launch surface while the results are already available.
            if case .search(let search) = currentContextKey.request {
                await startUnifiedSearch(search.query)
            }
            try await next.launch()
        } while pendingRebuild
    }
}

@MainActor
@Observable
final class FeedAssociation {
    let database: RuntimeDatabase
    let session: FeedSession
    let driver: FeedRunwayDriver
    let coordinator: AcquisitionCoordinator
    let media: MediaPrefetcher
    /// Owner directive 2026-10-17 §2: a save prepares the occurrence's media and records what the link can open.
    @ObservationIgnored let savedMedia: SavedMediaCoordinator
    /// P2: a preparation whose durable write was refused has no availability row to read. The failure is kept
    /// here for the session so the saved row states it instead of an older/pending state, and the retry path
    /// clears it when a durable outcome exists.
    private var savedMediaFailures: Set<PublicationCardID> = []
    /// Changes whenever a preparation settles, so the saved surface re-reads the rows it draws.
    private(set) var savedMediaRevision = 0
    @ObservationIgnored private let tidy: MediaTidy
    @ObservationIgnored private let mediaWaitBudget: LiveValue<Double>
    /// P05: the volume capacity is sampled **off** the MainActor at causal lifecycle moments and read here as a
    /// snapshot. The budget getter performs no filesystem I/O, so a viewport opportunity cannot freeze on a disk
    /// query.
    @ObservationIgnored private let storageCapacity = StageStorageCapacity {
        (try? FileManager.default.temporaryDirectory
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage).map { Int64($0) }
    }
    /// P05: useful production measured from concluded publications (cards / elapsed seconds). Nil until a second
    /// publication exists; the policy treats absence as unknown, never as zero.
    @ObservationIgnored private let usefulYield = LiveValue<Double?>(nil)
    @ObservationIgnored private var lastPublication: (at: Double, cards: Int)?
    /// The display name preparation attributes a card with, read at the moment it prepares (`LiveValue`): discovery
    /// reaches a session more than once (the walk's pages while the reader reads, and the pool a warm launch adopts
    /// behind its window), so the map belongs to the association and not to one closure.
    @ObservationIgnored private let names: LiveValue<[SourceID: String]>
    let acquisition: SyndicationAcquisitionSnapshot
    /// F05: the evidence the run is judged by, shared with the host that owns the file.
    let trace: RunwayTrace?
    /// The catalogue this session's host resolved, passed in rather than re-derived: `sourcePage` reads a source's
    /// site from the shipped catalogue, and a second `Bundle.main` lookup here would be a second owner of the same
    /// path — the thing this change exists to remove. No default: a construction that forgets it fails loudly
    /// instead of silently behaving as if the build carried no catalogue.
    let catalogueURL: URL?
    /// F02's exposure ledger, **shared with the composition root**: it is handed in rather than created here
    /// because a session that is rebuilt for the same context (answering an invitation rebuilds it) must not look
    /// to the budget like a reader who has never read anything. The association records into it; the budget that
    /// reads it is the host's.
    let editorialExposure: EditorialExposureLedger
    /// Structural bounds of this association's admitted presentation (plan T2/T3).
    let bounds: FeedPresentationBounds
    /// A: this launch's acquisition parallelism, supplied by the composition that built the association.
    @ObservationIgnored let launchSettings: CollectionLaunchSettings
    @ObservationIgnored private let maintainTail: @Sendable (PublicationStore.HiddenTailLease) async throws -> PublicationStore.TailSuccessionResult
    private let cold: ColdFeedBootstrap
    @ObservationIgnored private let relay: EvidenceRelay
    /// The concluded-publication facts this association acts on (R6-E): the driver's drain and the cold bootstrap
    /// both deliver them here, to the owner of the admitted window.
    ///
    /// Internal, like `driver`, `session` and `bounds`: the app target's tests exercise the recipient's own
    /// validation by handing **this** object the receipt the product would hand it — the product's entry point,
    /// not a second delivery path and not a second owner of the admitted window.
    @ObservationIgnored let publicationRelay: PublicationRelay
    @ObservationIgnored private var preparation: PreparationProgress?
    @ObservationIgnored private let targetNames: [AcquisitionTargetID: String]
    @ObservationIgnored private let admittedHeadlines: @Sendable () -> [String]
    private let transport: URLSession
    private(set) var active = true
    private var launching = false
    /// Available actions are what this host can execute today: opening the frozen target and saving.
    /// The remaining V1 controls appear as their deliveries land (T5 shell/feedback, T9 reader/media),
    /// so a rendered control is never a dead one.
    @ObservationIgnored
    static let readerCardActions: Set<ReaderCardAction> = [.open, .save, .copyLink, .share, .viewSource,
        .openMedia]

    /// Destinations this build can present today: the source sheet and the saved list (V1's bookmark
    /// boxes arrive in T8). The header menu renders exactly these — never a dead item.
    /// The destinations this host can present. `collectionFromContextPrompt` and `smartFeedPrompt` are V1's
    /// two conditional entries; the app narrows them to the contexts where V1 offered them.
    ///
    /// The settings and tools surfaces (T9/T10) are wired in the host — its `onNavigate` presents
    /// `.settings` as the settings sheet and `.export` as the export sheet — so they are offered here, and the
    /// reader can reach what the build draws. V1's "Importar para a coleção" and its per-collection export stay
    /// out: its export request names the reader's **selection** — offering "Exportar coleção" would open the
    /// wrong document (a review caught exactly that), and an entry that opens the wrong surface is worse than
    /// one that is not offered. A collection's own export belongs to the collection's surface.
    ///
    /// Adding a feed by link is offered unconditionally (V1's own menu item); adding **into a collection** is
    /// V1's conditional item and appears only while the reader is reading a collection's own feed.
    static func readerDestinations(for contextKey: ContextKey) -> Set<ReaderDestination> {
        var destinations: Set<ReaderDestination> = [.sources, .bookmarkBoxes, .filters,
            .collections, .collectionFromContextPrompt, .smartFeedPrompt, .smartFeedDeletion,
            .curatedOnboarding, .curatedInspector, .curatedDeletion, .export, .settings, .addFeed]
        if case .collection = contextKey.preset { destinations.insert(.addFeedToCollection) }
        return destinations
    }

    @ObservationIgnored
    lazy var store: FeedScreenStore = FeedScreenStore(onViewport: { [weak self] observation, activity in
        // R01: the callback records one fact and returns. It creates no task per event and awaits no producer;
        // the association's single drain consumes the finite pending summary.
        self?.receiveViewportIngress(observation, activity: activity, evidence: nil)
    }, onRenderedViewport: { [weak self] evidence, activity in
        self?.receiveViewportIngress(evidence.observation, activity: activity, evidence: evidence)
    }, availableActions: Self.readerCardActions, onAction: { [weak self] event in
        guard let self, self.active else { return }
        switch event.action {
        case .open: self.open(event.cardID)
        case .save: self.toggleBookmark(event.cardID)
        default: self.perform(event.action, cardID: event.cardID)
        }
    }, availableDestinations: Self.readerDestinations(for: contextKey),
        onSubmitSearch: { [weak self] term in self?.onSearch?(term) },
        onCancelSearch: { [weak self] in self?.onCancelSearch?() },
        onNavigate: { [weak self] destination in self?.onNavigate?(destination) },
        onPresentedPosition: { [weak self] anchor, atRest in
            // The latest drawn position wins; the same single drain writes it off the callback.
            self?.receivePresentedPositionIngress(anchor, atRest: atRest)
        }, onSelectSearchResult: { [weak self] result in self?.onSearchResult?(result) },
        onRequestSearchPage: { [weak self] page, cursor in self?.onSearchPage?(page, cursor) },
        onRequestSourcePage: { [weak self] page, index in self?.onSearchSourcePage?(page, index) },
        onSearchScopeChanged: { [weak self] scope in self?.onSearchScope?(scope) },
        onRequestSearchAgain: { [weak self] in self?.onSearchRetry?() })

    /// T9: the card actions this host executes. Resolution is the action coordinator's (the occurrence's own
    /// frozen target); what happens next — a browser, a clipboard, a share sheet — is here, and nowhere near a
    /// renderer.
    func perform(_ action: ReaderCardAction, cardID: PublicationCardID) {
        Task {
            // R19: "Ver fonte" is the **internal** source context, not the source's website. The explicit website
            // action is the card's own `.open`/link; the two never substitute for each other.
            if action == .viewSource {
                let card: PublicationStore.CardRecord?
                do { card = try PublicationStore(database: database).card(id: cardID) }
            catch { reportFailure(error, operation: .openCard); return }
                guard let sourceID = card?.sourceID else {
                    store.showToast(text: String(localized: "Esta carta não declara uma fonte"),
                        systemImage: "info.circle")
                    return
                }
                guard feeds.contains(where: { $0.sourceID == sourceID }) else {
                    store.showToast(text: String(localized: "Esta fonte não está no seu feed"),
                        systemImage: "info.circle")
                    return
                }
                guard let onOpenSource else {
                    store.showToast(text: String(localized: "Esta fonte não está no seu feed"),
                        systemImage: "info.circle")
                    return
                }
                onOpenSource(sourceID)
                return
            }
            do {
                switch try await ReaderActionCoordinator(database: database).perform(action, cardID: cardID) {
                case .externalURL(let url):
                    present(url, cardID)
                case .copiedText(let text):
                    if PlatformPasteboard.copy(text) {
                        store.showToast(text: String(localized: "Link copiado"), systemImage: "doc.on.doc")
                    } else {
                        reportFailure(ReaderActionError.unusableReference(text), operation: .copy)
                    }
                case .share(let payload):
                    onShare?(SharedLink(url: payload.url, subject: payload.subject))
                case .media:
                    // D1 (PD-2026-10-20): the card's own playable target is executed, not refused. The channel
                    // already existed and was wired to the app-wide player; the surface simply answered with a
                    // toast. The coordinator owns V1's tap behaviour and states its own reason when the card
                    // carries nothing playable.
                    onMedia?(cardID)
                }
            } catch { reportFailure(error, operation: Self.operation(for: action)) }
        }
    }

    /// V1's "View Source": the *source* of the card, resolved from the shipped catalog through the same
    /// mapping acquisition uses (the card's source id names a trusted feed, whose principal is the catalog key).
    /// Nil when the card, the feed or the catalog entry is missing — the caller states that rather than opening
    /// something else.
    func sourcePage(for cardID: PublicationCardID) -> URL? {
        guard let card = try? PublicationStore(database: database).card(id: cardID),
            let sourceID = card.sourceID, let feed = feeds.first(where: { $0.sourceID == sourceID }),
            let catalogURL = catalogueURL,
            let record = try? LegacyCatalogReader(catalogURL: catalogURL).source(key: feed.principal),
            let site = record.siteURL, let url = URL(string: site), url.scheme?.lowercased() != nil else {
            return nil
        }
        return url
    }

    /// Saving is the reader's own durable state (U2); the occurrence must already be admitted, and it lands in
    /// the box the reader preferred (V1's `preferredBookmarkListID`), which is the default box until they say
    /// otherwise.
    private func toggleBookmark(_ cardID: PublicationCardID) {
        do {
            let publication = PublicationStore(database: database)
            try publication.toggleBookmark(cardID: cardID, in: preferredBookmarkListID(), at: Date())
            // R02: the write above is the confirmation. The set the reader sees is read **off** the main actor by the
            // one refresher, and the revision fence makes any older preparation older than this write.
            bookmarkMutationConfirmed()
            // Owner directive 2026-10-17 §2: the link and its content are one promise. A save starts the
            // occurrence's media preparation and records what the link can open; an unsave clears the claim.
            prepareSavedMediaAndPublish(cardID, announceFailure: false)
        } catch { reportFailure(error, operation: .save) }
    }

    /// P2: every preparation settles into the saved surface. A refused durable write has no row, so its failure
    /// is held for this session and stated on the row; the next attempt either records a durable state or fails
    /// again, never leaving the reader with an older "pending" that nothing backs.
    private func prepareSavedMediaAndPublish(_ cardID: PublicationCardID, announceFailure: Bool) {
        Task { [savedMedia] in
            let state = await savedMedia.prepareSavedMedia(cardID: cardID)
            if state == .failed {
                savedMediaFailures.insert(cardID)
                if announceFailure {
                    store.showToast(text: String(localized: "Não foi possível preparar a mídia salva"),
                        systemImage: "exclamationmark.triangle")
                }
            } else {
                savedMediaFailures.remove(cardID)
                if state == .insufficientSpace {
                    store.showToast(text: String(localized: "Sem espaço para preparar a mídia salva"),
                        systemImage: "externaldrive.badge.exclamationmark")
                }
            }
            savedMediaRevision &+= 1
        }
    }

    /// A relaunch may have inherited saved units whose preparation was interrupted: resume a bounded few so the
    /// availability shown on `Salvos` is the one that was actually reached, not the one a killed attempt assumed.
    func resumeSavedMedia(limit: Int = 8) {
        Task { [savedMedia] in
            await savedMedia.resume(limit: limit)
            savedMediaRevision &+= 1
        }
    }

    /// The reader's retry on one saved row: the same preparation path the save used, so a failure that was
    /// visible becomes an attempt — and only an outcome the store can hold becomes "available offline".
    func retrySavedMedia(_ cardID: PublicationCardID) {
        prepareSavedMediaAndPublish(cardID, announceFailure: true)
    }

    /// T8: which of V1's menu entries apply for this session's context. The entries, their order and their
    /// labels stay V1's (`ReaderMenuEntry.standard`); only which of them apply is decided here.
    func refreshMenuDestinations() {
        var destinations = Self.readerDestinations(for: contextKey)
        let criteria = contextKey.filter.activeCriteria.count
        let committed: Bool = {
            if case .search = contextKey.request { return true }
            return false
        }()
        if !committed, criteria < 2 { destinations.remove(.collectionFromContextPrompt) }
        if !committed { destinations.remove(.smartFeedPrompt) }
        switch contextKey.preset {
        case .smartFeed, .curatedFeed: break
        default: destinations.remove(.smartFeedDeletion)
        }
        // V1 offered the hood and its deletion only while the reader was on a curated feed.
        if !contextKey.preset.isCurated {
            destinations.remove(.curatedInspector)
            destinations.remove(.curatedDeletion)
        }
        store.installDestinations(destinations)
        store.installContextFacts(filterCount: criteria, hasCommittedSearch: committed)
    }

    /// U2: the app host owns presentation. The composition resolves the frozen target; it never
    /// opens a URL itself and never lets one cross the UI boundary.
    @ObservationIgnored var onExternalURL: ((URL) -> Void)?
    /// T8: where a save lands, resolved when the reader saves rather than when the session was built.
    @ObservationIgnored var preferredBookmarkListID: () -> String = { ReaderBookmarkList.defaultID }
    /// T9: a card's media action. The app owns the player, so the association only reports the occurrence.
    @ObservationIgnored var onMedia: ((PublicationCardID) -> Void)?
    /// The identity this session is on. It does not change for the life of the association.
    let contextKey: ContextKey
    /// What this session ranks by: eligibility, scoring (a curated feed's weights), sequencing and exposure.
    let policy: ResolvedSelectionPolicy
    /// The feeds this session was built over: a card's source id names one of them, and its principal is the
    /// catalog key V1's "View Source" needs.
    let feeds: [TrustedFeed]
    /// The sources the catalogue offered for the reader's profile, acquired with the selection but never shown
    /// as the reader's own. Empty for a reader who named no interest.
    ///
    /// It is a fact of the **session**, not of its construction: a warm launch states the pool after the reader's
    /// own window is on screen (`adopt(_:)`), because that read is a scan of the shipped catalogue and
    /// INV-07 gives a warm launch no work before that window. One list, one owner of "what discovery brought".
    private(set) var discovery: [TrustedFeed]
    /// The catalogue's subject for each source discovery brought **to this session**, and nothing from anywhere
    /// else: the invitations the feed places are answered from here. It is stated with the same read that stated
    /// `discovery` — at construction for the asynchronous launch, at `adopt(_:)` for the warm one.
    private(set) var subjects: [SourceID: AppComposition.EditorialSubject]
    /// The profile this session's discovery pool was built from. An explicit refresh compares it with the stored
    /// one: the reader's answers are about discovery, and a refresh the reader asked for is where a pending answer
    /// must land (po, 2026-10-11).
    let discoveryProfile: ReaderDiscoveryProfile

    /// Selection and discovery as one supply, without duplicates: a source the reader picked that discovery also
    /// found is one target, under the selection's own identity.
    static func supply(selection: [TrustedFeed], discovery: [TrustedFeed]) -> [TrustedFeed] {
        guard !discovery.isEmpty else { return selection }
        var seen = Set(selection.map(\.sourceID))
        return selection + discovery.filter { seen.insert($0.sourceID).inserted }
    }
    /// T5: the reader shell's intents. The association reports them; the app host presents them.
    @ObservationIgnored var onNavigate: ((ReaderDestination) -> Void)?
    /// T9: the share sheet a card's share action opens. The app presents it; the association never does.
    @ObservationIgnored var onShare: ((SharedLink) -> Void)?
    @ObservationIgnored var onSearch: ((String) -> Void)?
    /// R15: cancelling a search is the host's intention to restore the origin; the association forwards it.
    @ObservationIgnored var onCancelSearch: (() -> Void)?
    /// R19: "Ver fonte" asks the host for the source's internal context; the association resolves no context.
    @ObservationIgnored var onOpenSource: ((SourceID) -> Void)?
    /// P08: the unified search surface reports selection, pagination, scope and retry to the composition that owns
    /// the local authorities. The association resolves none of them.
    @ObservationIgnored var onSearchResult: ((ReaderSearchResult) -> Void)?
    @ObservationIgnored var onSearchPage: ((ReaderSearchResults, ReaderSearchCursor?) -> Void)?
    @ObservationIgnored var onSearchSourcePage: ((ReaderSearchResults, Int) -> Void)?
    @ObservationIgnored var onSearchScope: ((ReaderSearchScope) -> Void)?
    @ObservationIgnored var onSearchRetry: (() -> Void)?

    /// Review F10: resolve the frozen action target from published history and open it.
    /// The URL never crosses the UI boundary; only the card identity does.
    private func open(_ cardID: PublicationCardID) {
        // The sole caller is the store's validated action callback. Its card may remain drawn in
        // the borrowed gesture window after canonical pruning; do not discard that legitimate tap.
        guard active, visible else { return }
        read(cardID)
    }

    /// U2: a saved article resolves straight from published history; it has no feed-window action gate.
    func openSaved(_ cardID: PublicationCardID) {
        guard active else { return }
        read(cardID)
    }

    /// Where this card is read: here, from text the app already holds, or on the site. The judgement itself is a
    /// pure value (`FeedReadingDecision`); resolving it reads the store and nothing else — no acquisition, no
    /// extraction, no cache, which is the invariant the architect fixed for this surface.
    private func read(_ cardID: PublicationCardID) {
        guard let target = readingTarget(cardID) else { return }
        switch target {
        case .local:
            Self.log("reading card=\(cardID.rawValue) locally")
            onReading?(target)
        case .site(let url):
            present(url, cardID)
        }
    }

    /// One card's stored text, in the terms the reading decision asks for. Nil only when the card itself is
    /// unknown; the revision's own summary, body and link are the source, with the card's rendered values as the
    /// fallback when the revision cannot be read.
    func readingTarget(_ cardID: PublicationCardID) -> FeedReadingTarget? {
        guard let card = try? PublicationStore(database: database).card(id: cardID) else { return nil }
        let revision = try? ContentStore(database: database).originRevision(id: card.originRevisionID)
        return FeedReadingDecision.target(body: revision?.bodyText,
            summary: revision?.summary ?? card.primaryText,
            sourceName: card.sourceDisplayName ?? card.providerDisplayName ?? "",
            headline: card.title ?? revision?.headline ?? card.primaryText ?? "",
            publishedAt: card.timestampValue,
            siteURL: resolvedExternalURL(cardID))
    }

    /// T9/U-reading: the reading the host presents for a card. Deliberately separate from `onExternalURL` above,
    /// which stays an *explicit* request to the site (a card's own action, a source page) — the app's reading
    /// decision must never be confusable with the reader asking for the browser.
    @ObservationIgnored var onReading: ((FeedReadingTarget) -> Void)?

    private func resolvedExternalURL(_ cardID: PublicationCardID) -> URL? {
        guard let card = try? PublicationStore(database: database).card(id: cardID),
            card.primaryActionKind == "externalURL", let reference = card.primaryActionReference,
            let url = URL(string: reference) else { return nil }
        return url
    }

    private func present(_ url: URL, _ cardID: PublicationCardID) {
        onExternalURL?(url)
        Self.log("opened card=\(cardID.rawValue)")
    }

    /// U2: bounded read of the existing bookmark authority for the app host. No second bookmark
    /// store, no schema change: ids come from `bookmarkedCardIDs()` and each row from `card(id:)`.
    func savedArticles(limit: Int = 200) -> [FeedSavedArticle] {
        savedArticles(inBox: nil, limit: limit)
    }

    /// T8: one box's saved articles, or every box when no box is named. Ordering is V1's: newest first, with a
    /// stable tie-break so two rows never swap places between launches.
    func savedArticles(inBox listID: String?, limit: Int = 200) -> [FeedSavedArticle] {
        guard let publication = try? PublicationStore(database: database),
            let ids = try? (listID.map { (try? ReaderLibraryStore(database: database).bookmarkedCardIDs(inList: $0)) }
                ?? publication.bookmarkedCardIDs()) ?? [] else { return [] }
        // One read for every row's persisted availability; the row states what the owner recorded, never a guess
        // made while drawing. A card without a row (written before this build reached it) claims nothing as
        // available: `media_key IS NULL` is a published fact, everything else is pending.
        let recorded = (try? SavedMediaAvailabilityStore(database: database).availabilities()) ?? [:]
        return ids
            .compactMap { id -> FeedSavedArticle? in
                guard let card = try? publication.card(id: id) else { return nil }
                let title = card.title ?? card.primaryText ?? ""
                guard !title.isEmpty else { return nil }
                let availability = FeedSavedArticle.availability(recorded: recorded[id]?.availability,
                    hasPublishedMedia: card.mediaKey != nil, failedInThisSession: savedMediaFailures.contains(id))
                return FeedSavedArticle(id: card.id, title: title, source: card.sourceDisplayName,
                    timestamp: card.timestampValue, availability: availability)
            }
            .sorted { left, right in
                let leftDate = left.timestamp ?? .distantPast
                let rightDate = right.timestamp ?? .distantPast
                if leftDate != rightDate { return leftDate > rightDate }
                return left.id.rawValue.uuidString < right.id.rawValue.uuidString
            }
            .prefix(limit)
            .map { $0 }
    }

    #if DEBUG
    private(set) var viewportReceived = 0
    private(set) var viewportCompleted = 0
    private(set) var backwardCompleted = 0
    #endif

    /// The presentation window's structural capacities: the readable prefix behind the reader and the reserve the
    /// reader may walk into. Frozen when the presentation is installed (plan T2/T3).
    static let backwardWindowCards = 8
    static let forwardWindowCards = 16

    /// Reserva mínima de produto: quantas cartas **apresentáveis** o runway mantém à frente do leitor, com ou sem
    /// medição. O alvo derivado (`taxa × (p95 × 1.2 + 2 s)`) descreve o reabastecimento típico, e uma única
    /// oportunidade mais lenta que o p95 esgotava uma reserva de poucas cartas — o feed chegava ao fim duro e só
    /// depois era repovoado (relatado no aparelho, 2026-10-14). A V1 mantinha um buffer local profundo e não tinha o
    /// sintoma. É um piso de produto, ajustável: 32 ≈ duas telas ≈ 32 s de leitura a 1 card/s.
    static let runwayMinimumReserveCards = 32

    /// Structural bounds for this association's admitted presentation: a readable prefix and the
    /// reserve the reader may walk into. Frozen when the presentation is installed (plan T2/T3).
    ///
    /// `keepsAdmittedHead: true` is the owner's decision of 2026-10-13 (V1's behaviour): the list is still bounded
    /// forward, but a card the reader has passed is never removed, so nothing above the reader changes while they
    /// read and the offset corrector has nothing to hide. The architect's rule (bounded around the anchor in both
    /// directions) remains the library default: `FeedPresentationBounds.keepsAdmittedHead = false`.
    static func presentationBounds(_ contextKey: ContextKey) -> FeedPresentationBounds {
        .init(backwardCapacity: backwardWindowCards, forwardCapacity: forwardWindowCards, contextKey: contextKey,
            keepsAdmittedHead: true)
    }

    /// T6: whether a restored Edition may be shown for the identity the reader is on. It must belong to that
    /// identity — a foreign filter, preset or search scope is a silent swap, even when the policy versions
    /// happen to match — and it must have been published under the current selection, eligibility *and scoring*
    /// policies. The scoring version is what makes an edit to a curated recipe a new behaviour: the Edition
    /// published before the edit ranked by a recipe the reader has since changed, so it is not shown again.
    static func mayShow(_ revision: EditorialRevision, for contextKey: ContextKey,
        selectionVersion: UInt64, eligibilityVersion: UInt64 = 2, scoringVersion: UInt64 = 1) -> Bool {
        revision.contextKey == contextKey
            && revision.userSelectionVersion == PolicyVersion(rawValue: selectionVersion)
            && revision.eligibilityPolicyVersion == PolicyVersion(rawValue: eligibilityVersion)
            && revision.scoringPolicyVersion == PolicyVersion(rawValue: max(1, scoringVersion))
    }

    /// The exact behavior each sequencing policy version names. Explicit, never a threshold: a version this
    /// build does not know must not be silently treated as a later one (R2 review, 2026-10-10). Version 1 and
    /// any unknown version keep the recency order the earliest revisions were published under; v3 is the
    /// unweighted proportional rule and v4 the same rule shaped by the reader's weights.
    static func sequencingBehavior(for version: PolicyVersion) -> ResolvedSelectionPolicy.SequencingBehavior {
        switch version.rawValue {
        case 2: return .recencyAlternatingSources
        case 3: return .recencyAlternatingSourcesBySupplyShare
        case 4: return .recencyAlternatingSourcesByWeightedSupplyShare
        default: return .recencyDescending
        }
    }

    /// D (spec "Estabilidade de coleta e UI"): the catalogue facts the composition orders acquisition by. Keyed
    /// by the same `SourceID` its registrations use. A feed the catalogue does not describe contributes nothing,
    /// and a launch with no readable catalogue contributes nothing at all — the supplied registration order is
    /// then the order the planner receives.
    static func targetSignals(catalogueURL: URL?, feeds: [TrustedFeed]) -> [SourceID: AcquisitionTargetSignal] {
        guard let catalogueURL, let catalogue = try? LegacyCatalogReader(catalogURL: catalogueURL) else { return [:] }
        var signals: [SourceID: AcquisitionTargetSignal] = [:]
        for feed in feeds {
            guard let facts = try? catalogue.rankingFacts(key: feed.principal), facts.hasEvidence else { continue }
            signals[feed.sourceID] = .init(catalogueQualityScore: facts.qualityScore,
                catalogueActivity: facts.activity,
                // No per-target latency is measured yet; the type accepts one, and the score treats absence as
                // neutral rather than inventing a number.
                measuredLatencySeconds: nil)
        }
        return signals
    }

    /// A (spec "Estabilidade de coleta e UI"): the one place this association's planning budgets are chosen.
    /// `initialParallelism` is caller-supplied; `AcquisitionPlanningResources` itself keeps no default (its
    /// contract: "All four resource capacities … have no defaults"). The socket ceiling is applied where the
    /// coordinator is built, from the same settings value.
    var resources: FeedRunwayDriverResources {
        // R09/P05: the opportunity's budgets come from the one policy, fitted to the pressure facts the platform
        // can state now. Nothing measured → the documented bootstrap (48/8/32/1 MB); pressure only reduces, an
        // explicit zero stays zero, and local reading is never turned off. Every fact here is an in-memory snapshot:
        // the volume read happens in `storageCapacity.refresh()` on a background executor.
        let budget = StageBudgetPolicy.budget(pressure: stagePressureFacts(), settings: launchSettings)
        return .init(runway: .init(localWorkAllowed: budget.localWorkAllowed,
            examinedCandidateCapacity: budget.examinedCandidateCapacity,
            readyProbeBound: 32, readyProbeCeiling: 256, forwardAdvanceProbeBound: 256,
            // F01/§5.3: the reserve exists so the reader can walk into the window the session materialised, so the
            // bootstrap coverage **is** that window — derived here, not restated. `RunwayPolicy` uses it only while
            // consumption/replenishment facts are unknown (Codex's reserve review, 2026-10-10); once they are
            // measured it derives the target from the measured rate and p95, and this number stops applying.
            reserveCards: Self.forwardWindowCards)!,
            acquisition: budget.acquisition)
    }

    /// The pressure the platform states now. Thermal, low-power and the network path are in-memory platform facts;
    /// free storage and useful yield are snapshots written by their owners (off the MainActor / on publication).
    /// Absence stays absence, never a guess and never a zero.
    private func stagePressureFacts() -> StagePressureFacts? {
        let thermal: StagePressureFacts.Level
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = .nominal
        case .fair: thermal = .fair
        case .serious: thermal = .serious
        case .critical: thermal = .critical
        @unknown default: thermal = .serious
        }
        let path = NetworkPathObserver.shared.current
        let constrained = path == .constrained || path == .expensive || path == .unavailable
        return .init(thermal: thermal, lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            networkConstrained: constrained, freeStorageBytes: storageCapacity.current,
            usefulCardsPerSecond: usefulYield.current)
    }

    init(directory: URL, feeds: [TrustedFeed], discovery: [TrustedFeed] = [],
        subjects: [SourceID: AppComposition.EditorialSubject] = [:],
        configuration: URLSessionConfiguration,
        trace: RunwayTrace? = nil, database sharedDatabase: RuntimeDatabase? = nil,
        discoveryTraversal: ReaderDiscoveryTraversal? = nil,
        contextKey: ContextKey = ContextKey(request: .main), selectionVersion: UInt64 = 2,
        scoring: ResolvedSelectionPolicy.ScoringBehavior = .equal, scoringVersion: UInt64 = 1,
        catalogueURL: URL?, editorialExposure: EditorialExposureLedger,
        discoveryProfile: ReaderDiscoveryProfile = .init(), warmLaunch: Bool = false,
        launchSettings: CollectionLaunchSettings = .init(),
        monotonicNow: @escaping @Sendable () -> RunwayMonotonicTime = { .init(seconds: ProcessInfo.processInfo.systemUptime)! },
        bookmarkRead: (@Sendable () async throws -> Set<PublicationCardID>)? = nil) throws {
        self.trace = trace
        self.monotonicNow = monotonicNow
        self.catalogueURL = catalogueURL
        self.editorialExposure = editorialExposure
        self.discoveryProfile = discoveryProfile
        self.launchSettings = launchSettings
        // The host and its replacement sessions share one writer; retiring async work cannot
        // contend with a preference write through a second pool for the same file.
        let db = try sharedDatabase ?? RuntimeDatabase(location: .init(directory: directory))
        database = db
        self.bookmarkRead = bookmarkRead ?? {
            try await Task.detached(priority: .userInitiated) {
                try PublicationStore(database: db).bookmarkedCardIDs()
            }.value
        }
        // T8: the context this session reads and writes, kept so the menu can state what applies to it.
        self.contextKey = contextKey
        self.feeds = feeds
        let history = PublicationHistory(database: db)
        let context = FeedContext(key: contextKey)
        let checkpoints = SessionStore(database: db)
        try checkpoints.activateContext(contextKey)
        if let active = try checkpoints.checkpoint() {
            try PublicationStore(database: db).setVisibility(editionID: active.editionID, visible: true)
        }
        var saved = try history.restore(backwardCapacity: 8, forwardCapacity: 16, contextKey: contextKey)
        if let restored = saved, !Self.mayShow(restored.edition.editorialRevision, for: contextKey,
            selectionVersion: selectionVersion, scoringVersion: scoringVersion) {
            // The position goes with the behaviour: the archived checkpoint of this identity holds an Edition
            // published under the policy that just changed, and the runtime would install it as the scope.
            try checkpoints.clearActiveCheckpoint()
            try checkpoints.clearCheckpoint(for: contextKey)
            saved = nil
        }
        let v = PolicyVersion(rawValue: 1)
        // T11: a curated feed's ranking is part of the behavior the Edition was published under, so an edit to
        // the recipe (which keeps the identity) is a new revision and never reuses an older checkpoint.
        let scoringPolicy = PolicyVersion(rawValue: max(1, scoringVersion))
        // Sequencing v3 = the unweighted proportional rule; v4 = the same rule shaped by the reader's
        // weights, declared only when the session actually carries a recipe. Keeping them apart is what lets
        // an Edition published under v3 keep the meaning it was given. Exposure v2 = PD-1 edited articles
        // reappear. A behavior change is a new EditorialRevision, and a restored Edition keeps the behavior
        // its own revision names.
        let alternating = PolicyVersion(rawValue: 2)
        // P10/R17: new Editions state the **supported** sequencing version. Version 5 keeps the same alternation
        // shape the previous versions described (by scoring) and adds the frozen-diversity tie-break; the shape is
        // resolved below, never inferred from a number this build does not know.
        let sequencingVersion = PolicyVersion(rawValue: 5)
        let shapedSequencing: ResolvedSelectionPolicy.SequencingBehavior
        switch scoring {
        case .equal: shapedSequencing = .recencyAlternatingSourcesBySupplyShare
        case .weighted(let weights):
            shapedSequencing = weights.isEmpty ? .recencyAlternatingSourcesBySupplyShare
                : .recencyAlternatingSourcesByWeightedSupplyShare
        }
        let revision = try saved?.edition.editorialRevision ?? EditorialRevision(
            // The revision identity carries every version that changes what an Edition was published
            // under. `PublicationStore.insertEditionAndFirstSegment` rejects a second Edition whose
            // `editorial_revision_id` matches an existing row but whose revision content differs
            // (`editorialRevisionConflict`), so a behavior change that keeps the identity would make the
            // next publication fail on an installation that already has an Edition for this context.
            // Adding the scoring and sequencing versions keeps v2 Editions exactly as they were and gives
            // a v3 Edition its own stable identity — no checkpoint is cleared, no history is rewritten.
            id: .init(rawValue: LegacyCatalogImport.stableUUID(namespace: "feedmine.editorial.context",
                key: try JSONEncoder().encode(contextKey).base64EncodedString() + "|" + String(selectionVersion)
                    + "|scoring:" + String(scoringPolicy.rawValue)
                    + "|sequencing:" + String(sequencingVersion.rawValue))),
            contextKey: context.key, catalogGeneration: .init(rawValue: 1), userSelectionVersion: PolicyVersion(rawValue: selectionVersion),
            eligibilityPolicyVersion: alternating, scoringPolicyVersion: scoringPolicy, sequencingPolicyVersion: sequencingVersion,
            exposurePolicyVersion: alternating, selectionSchemaVersion: .init(rawValue: 1))
        guard let plan = FeedPlan(context: context, revision: revision) else {
            throw FeedRunwayDriverError.policyContextMismatch
        }
        // v5's shape is the one its scoring implies; an older Edition keeps the behavior its own revision named.
        let sequencing = revision.sequencingPolicyVersion.rawValue == 5
            ? shapedSequencing : Self.sequencingBehavior(for: revision.sequencingPolicyVersion)
        // What this session may read from: the reader's own selection **plus** the sources discovery found for
        // their profile. The reader's selection stays what it was — the sources screen and the context menu still
        // show exactly what they chose — while the feed is supplied by the open internet the catalogue describes.
        let supply = Self.supply(selection: feeds, discovery: discovery)
        // What discovery has brought is a session fact, not a construction one: a warm launch starts with none of
        // it (its first frame may not wait for the catalogue) and states it in `adopt(_:)`. The subjects come with
        // it — the catalogue's name for each source the read offered — and they belong to *this* session, which is
        // what keeps a pool read for the reader's earlier interests from answering this session's invitations.
        self.discovery = discovery
        self.subjects = subjects
        let policy = ResolvedSelectionPolicy(contextKey: revision.contextKey,
            userSelectionVersion: revision.userSelectionVersion, eligibilityPolicyVersion: revision.eligibilityPolicyVersion,
            scoringPolicyVersion: revision.scoringPolicyVersion, sequencingPolicyVersion: revision.sequencingPolicyVersion,
            exposurePolicyVersion: revision.exposurePolicyVersion, selectionSchemaVersion: revision.selectionSchemaVersion,
            eligibility: .selectedSources(Set(supply.map(\.sourceID))), scoring: scoring, sequencing: sequencing,
            exposure: revision.exposurePolicyVersion >= alternating ? .excludePublishedMaterial : .excludePublishedRevisions)
        // The policy is a fact about this session (T11): what it ranks by, and the versions it was published
        // under. A surface or a test can state it without rebuilding the decision.
        self.policy = policy
        let authority = AcquisitionTargetAuthority(database: db)
        let registrations = try supply.map { feed in
            let existing = try authority.target(id: feed.targetID)
            let target = try existing ?? authority.register(id: feed.targetID,
                connectorKind: .syndication, authorizedSources: [feed.sourceID])
            let binding = SourceBinding(id: feed.bindingID, sourceID: feed.sourceID,
                externalPrincipal: .init(connectorKind: .syndication,
                    namespace: feed.principalNamespace ?? (feed.principal.hasPrefix("http")
                        ? LegacyCatalogImport.principalNamespace : "feedmine-development-rss"),
                    value: feed.principal, role: .principal), aliases: [], generation: 1, state: .enabled)!
            return SyndicationTargetRegistration(targetID: target.id, targetGeneration: target.generation,
                endpoint: feed.endpoint, bindings: [binding])!
        }
        let transport = URLSession(configuration: configuration)
        self.transport = transport
        // §5.3: discovery is a **traversal**, not a preview — the same object advances page by page across the cold and
        // active drivers, and the targets it registers become eligible inside this snapshot, which is where the
        // authority for them lives. The session's resolved policy keeps saying only what the reader chose.
        // Kiro K-01/K-05 wiring — corrected after the architect's review of PR #3, and he was right: deriving the
        // set from `registrations` means deriving it from the **catalogue**, which is untrusted input. K-01's own
        // note says authorization never derives from catalog or OPML endpoints, and a catalog row naming a LAN
        // host would have been authorized by that alone.
        //
        // What is authorized here is exactly what **this run declares it will fetch**, from inputs the build owns:
        //   * the benchmark transport's origin, named by the run itself (`FEEDMINE_BENCH_TRANSPORT_HOST`, which the
        //     runner sets to this Mac's `host:port` in device mode). The corpus the benchmark injects is served
        //     there, and its catalogue names those endpoints — which is precisely why the catalogue cannot be the
        //     source of the authorization;
        //   * the development feeds this build carries (`TrustedFeed.development`), whose origins are public and
        //     therefore dropped by the filter below — kept in the expression so a future non-public development
        //     feed is authorized by being *declared*, not by being named.
        // A debug build still authorizes only non-public origins (`SyndicationAuthorizedOrigin` refuses public
        // hosts, userinfo, non-HTTP schemes and any URL with a path or query); a Release build authorizes none.
        #if DEBUG
        // **Uma única URL, com esquema, host e porta** (exigência do arquiteto na revisão do PR #3: não um host
        // convertido em HTTP e HTTPS, porque duas URLs derivadas de um nome é exatamente a ambiguidade que a
        // autorização não pode ter). O que a execução nomeia é a origem; portas fora do padrão contam, e um valor
        // só com host — sem esquema ou sem porta — **não autoriza nada**, porque autorizar "o host em qualquer
        // porta e em qualquer esquema" é autorizar mais do que a execução declarou.
        let declared: [URL] = {
            guard let named = ProcessInfo.processInfo.environment["FEEDMINE_BENCH_TRANSPORT_ORIGIN"]?
                .trimmingCharacters(in: .whitespaces), !named.isEmpty else { return [] }
            guard let parts = URLComponents(string: named) else {
                // Diagnóstico **claro** e **sem o valor bruto** (exigência do arquiteto, e o subsistema de log é
                // público): a variável pode carregar credenciais, então o operador fica sabendo o que declarou de
                // errado — e nada do que declarou.
                Self.log("transport origin declared but unparseable as a URL; authorizing nothing (value withheld)")
                return []
            }
            return parts.url.map { [$0] } ?? []
        }()
        // **Rejeita, não sanitiza** (exigência do arquiteto na revisão do PR #3): um valor declarado com caminho,
        // query, fragmento ou credenciais NÃO é limpo até virar origem — é recusado inteiro. Sanear esconderia
        // que a execução declarou algo que não é uma origem, e autorizar o resto seria autorizar mais do que ela
        // disse. Sem esquema http(s), sem host ou sem porta também não autoriza: a porta faz parte da origem.
        let authorizedNonPublicOrigins = declared.compactMap { endpoint -> URL? in
            guard let parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
                let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
                let host = parts.host, !host.isEmpty, parts.port != nil,
                parts.user == nil, parts.password == nil,
                parts.path.isEmpty, parts.query == nil, parts.fragment == nil
            else { return nil }
            guard let origin = parts.url, SyndicationAuthorizedOrigin(origin) != nil else { return nil }
            return origin
        }
        if !declared.isEmpty, authorizedNonPublicOrigins.isEmpty {
            // O caso que o arquiteto nomeou: **presente e inválida**. O diagnóstico diz o que exigimos — esquema,
            // host e porta, sem caminho, query, fragmento ou credenciais — e **não** repete o valor declarado, que
            // pode carregar credenciais e iria para um log público.
            Self.log("transport origin declared but not a usable origin (scheme, host and port required; no path, "
                + "query, fragment or credentials); authorizing no non-public origin")
        }
        #else
        let authorizedNonPublicOrigins: [URL] = []
        #endif
        let acquisition = try SyndicationAcquisitionSnapshot(database: db, registrations: registrations,
            session: transport, redirectCapacity: 4, discovery: discoveryTraversal,
            authorizedNonPublicOrigins: authorizedNonPublicOrigins,
            selectedSourceIDs: Set(feeds.map(\.sourceID)),
            installation: CatalogInstallation(appDirectory: directory),
            targetSignals: Self.targetSignals(catalogueURL: catalogueURL, feeds: supply))
        self.acquisition = acquisition
        // H2: a feed that keeps failing cools down for a doubling window that starts at what one
        // failed attempt may already cost (the request timeout) and is capped by the resource
        // timeout. Targets run through a sliding window sized by the launch's own parallelism,
        // conservatively capped (`CollectionLaunchSettings.maximumConcurrentTargets`) so a bad
        // configuration cannot open 48 sockets at once.
        let backoff = AcquisitionBackoffPolicy(baseSeconds: configuration.timeoutIntervalForRequest,
            ceilingSeconds: max(configuration.timeoutIntervalForRequest, configuration.timeoutIntervalForResource))
        let coordinator = acquisition.makeCoordinator(backoff: backoff,
            concurrentTargetLimit: launchSettings.concurrentTargetLimit)
        self.coordinator = coordinator
        // PD-5/PD-6 media pipeline: one download owner, device-measured policy, slot-sized decoding.
        let assetDirectory = directory.appendingPathComponent("Media", isDirectory: true)
        let device = DeviceMediaConditions.currentOnMain()
        let readiness = MediaReadiness()
        let fetcher = MediaHTTPFetcher(session: transport)
        // F06-G/PD-6: one derived tolerance feeds both the preparation window and the byte budget below. The media
        // layer used to be handed a fixed 5 s here while the window was computed elsewhere — two numbers for one
        // fact. The box is what makes them one: the window writes the measured value, and every later policy read
        // (which is how `MediaPolicy.byteBudget` = measured rate × wait is computed) sees it.
        let mediaWaitBudget = LiveValue(Self.mediaWaitBootstrapSeconds)
        self.mediaWaitBudget = mediaWaitBudget
        // B/§3: the prefetcher is built before the driver exists, so its readiness callback points at this
        // relay; the association points the relay at its own drive opportunity once every stored property is
        // set (below). Nothing here decides anything beyond "a readiness transition happened".
        let readinessRelay = MediaReadinessRelay()
        // The replenishment port. The points live in the library modules, which must not know the host's trace:
        // one adapter is built here, beside the trace itself, and handed to the owners of the points. With no
        // trace it is `nil`, and the modules behave exactly as they did before the port existed. It is built
        // before the media owner because the media preparation path also reports through it (DEBUG only there).
        let replenishment: ReplenishmentTrace? = trace.map { sink in
            ReplenishmentTrace { event, fields in sink.record(event, fields) }
        }
        let media = MediaPrefetcher(database: db, assetDirectory: assetDirectory, readiness: readiness,
            concurrentDownloadLimit: max(2, ProcessInfo.processInfo.activeProcessorCount / 2),
            fetch: { try await fetcher.fetch($0, budget: $1) },
            conditions: { rate in DeviceMediaConditions.policy(device: device, measuredBytesPerSecond: rate,
                assetDirectory: assetDirectory, waitBudgetSeconds: mediaWaitBudget.current) },
            onReadinessChanged: { _ in await readinessRelay.deliver() },
            mediaTrace: replenishment)
        self.media = media
        savedMedia = SavedMediaCoordinator(database: db, assetDirectory: assetDirectory, prefetcher: media)
        tidy = MediaTidy(assetDirectory: assetDirectory, prefetcher: media, freeStorageBytes: {
            try? FileManager.default.temporaryDirectory
                .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
        }, usage: { try PublicationStore(database: db).mediaUsage() })
        coldRetryFallbackSeconds = configuration.timeoutIntervalForRequest
        let imageDecoder = PresentationImageDecoder(assetDirectory: assetDirectory,
            heroMaxPixel: device.heroPixelWidth, thumbnailMaxPixel: device.thumbnailPixelWidth)
        bounds = Self.presentationBounds(context.key)
        // A warm launch is local (INV-07) and the reader must not perceive it: the window the previous interaction
        // left is read and projected **here**, so this association's first frame already carries it and no surface
        // is drawn between the launch screen and the reader's own feed. It is the projection `.initial` performs in
        // `launch()` — the session below adopts this one, so the checkpoint is read once and the sequence continues.
        let warm: FeedSession.WarmStart?
        if warmLaunch {
            warm = try FeedSession.warmStart(publicationHistory: history, imageDecoder: imageDecoder,
                bounds: bounds)
        } else {
            warm = nil
        }
        let session = FeedSession(publicationHistory: history, imageDecoder: imageDecoder, warmStart: warm)
        self.session = session
        // The names preparation reads are **live** (see `LiveValue`): discovery finds sources while the reader
        // reads, so the closure below must consult them at the moment it prepares — not the map that existed here.
        // It is stored as well, because discovery also arrives **after** this association exists: a warm launch
        // adopts its pool behind the reader's own window (`adopt(_:)`).
        let names = LiveValue(Dictionary(uniqueKeysWithValues: supply.map { ($0.sourceID, $0.displayName) }))
        self.names = names
        // T9/D2: the playable payload a card's tap should use, read from the candidate the feed declared. The
        // candidate (not just its URL) is what states whether the enclosure is audio or video.
        let playback: @Sendable (OriginRevisionID) -> MediaCandidate? = { revision in
            // `try?` flattens the store's own optional: a nil here means "no playable payload declared".
            (try? ContentStore(database: db).playbackCandidate(originRevisionID: revision)) ?? nil
        }
        // The trace is a value: the preparation closure is `@Sendable` and may run off the main actor.
        let prepare: @Sendable (SelectionResult) throws -> LocalPreparedPublication = {
            try Self.prepare($0, readiness: readiness, names: names.current, trace: trace, playback: playback)
        }
        // The runway is built before the media closures because they read its **measured** tolerance. §5.3/PD-6:
        // the media window is a per-operation limit, computed from facts this process already measures — the
        // runway's own replenishment p95, which is what one feed request costs on this host — plus the policy
        // choices the runway already carries. `timeoutIntervalForRequest / 4` was a configured fraction of the
        // transport's timeout pretending to be a strategy; PD-6 says the budget is computed, not configured. The
        // request timeout stays as the operational **ceiling** PD-6 rule 4 allows, and before any sample exists the
        // run states its bootstrap tolerance instead of inventing one.
        let policyInputs = RunwayPolicyInputs(safetyFactor: 1.2, releaseMarginSeconds: 2,
            minimumReserveCards: Self.runwayMinimumReserveCards)!
        let runway = RunwayController(configuration: .init(policyInputs: policyInputs, consumptionSampleLimit: 8,
            replenishmentSampleLimit: 8,
            // M7: first retry after a failed local slice one second later, doubling per failure.
            localRetryBaseSeconds: 1)!, trace: replenishment)
        let mediaWaitCeilingSeconds = configuration.timeoutIntervalForRequest
        let mediaWait: @Sendable () async -> Double = { [runway, mediaWaitBudget] in
            let seconds = Self.mediaWaitSeconds(p95Replenishment: await runway.snapshot().replenishment.p95Seconds,
                inputs: policyInputs, transportCeiling: mediaWaitCeilingSeconds)
            // The same number the media byte budget reads: the tolerance is published where the media layer looks
            // for it, so one measured fact governs both how long preparation may wait and how many bytes one image
            // may cost (F06-G: policies change with observed resources, not with arbitrary quantities).
            mediaWaitBudget.set(seconds)
            return seconds
        }
        // Runway: the driver supplies the next editorial candidates for the active context (F05).
        let makeMediaOpportunity: @Sendable () async -> MediaPreparationOpportunity = {
            let startedAt = ProcessInfo.processInfo.systemUptime
            let wait = await mediaWait()
            return MediaPreparationOpportunity(waitSeconds: wait, startedAt: startedAt) { revisions, deadline in
                await media.prefetch(revisions, deadline: deadline)
                // F05/F06: **when a candidate's media becomes ready** is one of the facts a run is judged on — a
                // pending candidate that recovers is exactly what the suspension rule promises. Codex's review: a
                // level-triggered event fires again on later queries and proves nothing; what a run needs is the
                // **transition**, once, for a revision that was not ready before.
                for revision in revisions where readiness.prepared(revision) != nil {
                    trace?.recordOnce("media_ready", key: "ready:\(revision.rawValue.uuidString)",
                        ["revision": revision.rawValue.uuidString])
                }
            }
        }
        maintainTail = { lease in
            let opportunity = await makeMediaOpportunity()
            return try await HiddenTailMaintenance(database: db, trace: replenishment).run(plan: plan, policy: policy, lease: lease, examinedCapacity: 256,
                prefetch: { await opportunity.prepare($0) }, prepare: prepare)
        }
        // §5.3 (Codex's page review): a discovery page updates the **metadata** that preparation consults — the names
        // a card is attributed with — and nothing else. It does not change the resolved policy (what the reader chose
        // stays what they chose), does not publish, and does not schedule acquisition: authorization for the newly
        // registered targets stays inside the acquisition snapshot, where `advanceDiscovery` put them. Both drivers
        // call this, which is what keeps the first screen and the live feed reading one map.
        let onDiscoveryPage: @Sendable ([LegacyCatalogEntry]) async -> Void = { entries in
            guard !entries.isEmpty else { return }
            let discovered = Dictionary(entries.map { ($0.source.id, $0.source.displayName) },
                uniquingKeysWith: { _, later in later })
            names.update { $0.merge(discovered) { _, later in later } }
        }
        // The First Edition needs no separate media door: the opportunity below prepares **exactly the revisions
        // the slice is about to examine** (the bootstrap asks the slice which ones, prepares them, then examines), so
        // the head-fetching closure that used to stand here is gone rather than kept as a second, competing view of
        // what the first screen needs.
        // R6-E: the publication fact gets a channel of its own, built **before** the driver exists. The driver
        // reports every segment a slice concludes; this association — the owner of the admitted list — decides what
        // the window does with it. Nothing can publish before the association exists, so the receiver (set at the
        // end of this initializer) is always in place before the first fact.
        let publicationRelay = PublicationRelay()
        self.publicationRelay = publicationRelay
        driver = try FeedRunwayDriver(session: session, runway: runway, plan: plan, policy: policy,
            acquisition: acquisition, coordinator: coordinator,
            monotonicNow: monotonicNow,
            makeSegmentIdentity: { .init(segmentID: FeedSegmentID(), segmentSeed: 1, segmentCreatedAt: Date())! },
            prepare: prepare,
            selectedSourceCoverage: .init(selectedSourceCoverageFor: plan.context.key, editorialRevisionID: plan.revision.id),
            readiness: readiness, onDiscoveryPage: onDiscoveryPage, makeMediaOpportunity: makeMediaOpportunity,
            trace: replenishment, onPublication: { receipt in await publicationRelay.deliver(receipt) })
        let relay = EvidenceRelay()
        self.relay = relay
        cold = try ColdFeedBootstrap(session: session, plan: plan, policy: policy,
            acquisition: acquisition, coordinator: coordinator, prepare: prepare,
            evidence: { await relay.deliver($0) },
            // F06-A applies to the first screen too, and it was not reaching it: without `readiness` the initial slice
            // had no suspension facts, so every examined candidate was eligible and a story whose image had not
            // arrived could be published as a card missing what PD-5 promises it will have. The opportunity hook is the
            // **same** factory the runway driver uses (one owner for the derived budget, `mediaWaitSeconds`), which
            // is what makes the first screen and the live feed agree on "prepared" — the quality Codex's page review
            // named: two different views of what is ready is how a suspended candidate becomes a text-only card.
            readiness: readiness, trace: replenishment, onDiscoveryPage: onDiscoveryPage,
            makeMediaOpportunity: makeMediaOpportunity)
        targetNames = Dictionary(uniqueKeysWithValues: feeds.map { ($0.targetID, $0.displayName) })
        let provider = CandidateProvider(contentStore: ContentStore(database: db))
        admittedHeadlines = { (try? provider.candidates(for: plan, after: nil, examinedCapacity: 12))?.candidates.compactMap(\.headline) ?? [] }
        // Every stored property is set: the channel's target is this association from here on. It is the same shape
        // the cold evidence relay has, and for the same reason — the driver is built before this object finishes
        // being built, so it holds a value that outlives the initializer and is pointed at the association once
        // there is one.
        publicationRelay.receive = { [weak self] receipt in await self?.publicationConcluded(receipt) }
        // B/§3: every stored property is set, so the media relay can now name this association's own drive
        // opportunity. The transition notifies the runway exactly as a committed acquisition does; the next
        // drive is the existing one, and nothing is published from the callback.
        readinessRelay.install { [weak self] in await self?.noteMediaReadinessChanged() }
        // The reader's window reaches the screen **here**, before this launch has drawn anything: it is the whole
        // point of a warm start. The handoff and the store keep their own validation, and a later `.initial`
        // admission returns this same projection, so installing it again is a no-op by the store's own rule.
        if let warm {
            try install(FeedPresentationHandoff.receive(snapshot: warm.snapshot, into: store.state))
        }
    }

    /// Discovery arriving **after** this association exists, as the normal opportunity of a launch whose first
    /// frame could not wait for it (INV-07: a warm launch is local; the pool a profile names is a scan of the
    /// shipped catalogue, and it is read behind the reader's own window in `AppComposition.launch()`).
    ///
    /// It is the same two steps the walk takes, in the same order:
    ///
    /// 1. **materialize** the entries as supply, through the owner that materializes an examined page
    ///    (`SyndicationAcquisitionSnapshot.adoptDiscovered` → `ReaderDiscoveryTraversal.adopt`), so the sources a
    ///    warm launch read get the durable authority, the generation fence, the enabled check and the endpoint
    ///    snapshot every other discovered target gets — they become *acquirable* and enter the **effective**
    ///    policy (`policyIncludingDiscovery` unions the walk's live source IDs), which is what makes them supply
    ///    instead of decoration. The walk's cursor is untouched: adopting a preview is not evidence that the
    ///    pages in between were examined. A source the authority revoked (or refuted) is not registered at all;
    /// 2. **then** publish what that really installed — the display names preparation attributes a card with,
    ///    which sources discovery brought, and the subject of each — and nothing else. The nominal policy is
    ///    **not** rewritten (it states what the reader chose), nothing is published, no acquisition is scheduled
    ///    here, and the presentation is not reinstalled: the reader's window was installed by this session's
    ///    construction, and the walk's own pages keep being the mechanism an active association advances.
    func adopt(_ read: AppComposition.DiscoveryRead) {
        let installed: [LegacyCatalogEntry]
        do { installed = try acquisition.adoptDiscovered(read.entries) }
        catch {
            Self.log("discovery pool could not be materialized as supply: \(String(describing: error))")
            return
        }
        guard !installed.isEmpty else { return }
        let feeds = installed.map(AppComposition.trustedFeed(from:))
        // The same deduplication the supply uses: one source is one entry, under the identity that reached here
        // first — a source the reader also chose is already theirs and stays theirs.
        var seen = Set(discovery.map(\.sourceID))
        discovery.append(contentsOf: feeds.filter { seen.insert($0.sourceID).inserted })
        names.update { $0.merge(Dictionary(feeds.map { ($0.sourceID, $0.displayName) },
            uniquingKeysWith: { _, later in later })) { _, later in later } }
        // Only what became supply is published as discovered: a revoked source is not a source the app found.
        let installedIDs = Set(installed.map(\.source.id))
        subjects.merge(read.subjects.filter { installedIDs.contains($0.key) }) { _, later in later }
    }

    /// §5.3/PD-6: the media preparation window for one operation, stated once so the precedent is testable.
    /// Unmeasured (cold start, before any replenishment sample exists) → the run's bootstrap tolerance.
    /// Measured → the runway's own tolerance for one feed request, which is the same duration its reserve target
    /// is built from (`p95 × safetyFactor + releaseMarginSeconds`), never above the transport's request ceiling
    /// and never a configured fraction of it.

    /// How long the media tidy may take while the screen is off. Measured, not configured: in the background iOS
    /// reports the allowance it will grant, and the margin that keeps the tidy from being killed mid-eviction is one
    /// media operation's tolerance — the same value the pipeline already uses, not a second number. Outside the
    /// background the system documents the property as meaningless (it reports `greatestFiniteMagnitude`), which is
    /// not an allowance, so the tolerance itself is the bound there.
    static func tidyAllowanceSeconds(backgroundRemaining: TimeInterval, tolerance: Double) -> Double {
        guard backgroundRemaining.isFinite, backgroundRemaining > 0,
            backgroundRemaining < Self.backgroundAllowanceSanityCeiling else { return tolerance }
        return max(0, backgroundRemaining - tolerance)
    }

    /// iOS grants minutes of background work, never hours, so a reported allowance above this is the "not in the
    /// background" sentinel rather than a fact about time. An operational ceiling — which PD-6 rule 4 permits — and
    /// deliberately not a strategy: it decides nothing about the feed.
    static let backgroundAllowanceSanityCeiling: TimeInterval = 600

    /// The tolerance the run states before it has measured one: how long one media operation may take. The media
    /// layer used to carry this number alone, as a literal handed to its conditions; it is stated once here, and both
    /// the preparation window and the media byte budget read it until a replenishment sample exists.
    ///
    /// `nonisolated` on purpose: it is a default argument of `mediaWaitSeconds` below, and a default argument is
    /// evaluated where the function is called — a main-actor-isolated value there is a compile error ("main
    /// actor-isolated default value in a nonisolated context", measured).
    nonisolated static let mediaWaitBootstrapSeconds = 5.0

    nonisolated static func mediaWaitSeconds(p95Replenishment: Double?, inputs: RunwayPolicyInputs,
        transportCeiling: Double, bootstrap: Double = FeedAssociation.mediaWaitBootstrapSeconds) -> Double {
        let ceiling = transportCeiling.isFinite && transportCeiling > 0 ? transportCeiling : bootstrap
        guard let p95 = p95Replenishment, p95.isFinite, p95 > 0 else { return min(bootstrap, ceiling) }
        return min(max(p95 * inputs.safetyFactor + inputs.releaseMarginSeconds, 0), ceiling)
    }

    /// A selected candidate without a presentation is an internal contradiction: it must be loud, never a
    /// silent text-only fallback for an image the card declared.
    nonisolated enum PreparationError: Error, Equatable { case candidateWithoutPresentation(OriginRevisionID) }

    /// PD-5: each card is drawn with a prepared image or designed text-only — never "missing" one.
    /// Attribution (source id/name) is frozen into the card, which also feeds PD-4 adjacency.
    nonisolated private static func prepare(_ selection: SelectionResult, readiness: MediaReadiness,
        names: [SourceID: String], trace: RunwayTrace? = nil,
        playback: (OriginRevisionID) -> MediaCandidate? = { _ in nil }) throws -> LocalPreparedPublication {
        // F06-A: the selection has **already** been restricted to candidates with a legitimate presentation (the
        // slice takes the readiness facts as selection input, before ordering). What arrives here is publishable —
        // and the inputs must stay aligned one-for-one with the selection, or the runtime refuses the batch
        // (`inputCountMismatch`, measured). Suspension belongs to the selection, not to the preparation.
        let snapshot = readiness.presentations(for: selection.orderedCandidates.map(\.originRevisionID))
        for candidate in selection.orderedCandidates {
            let presented = snapshot[candidate.originRevisionID] != nil
            // The readiness a card carries is stated by **one** vocabulary, the same `readinessLabel` the rest of the
            // app reads: prepared (with an image), textOnly (a settlement by decision), pending (nothing yet). This
            // line used to write `presented ? "prepared" : "pending"`, which made "textOnly" unreachable in every
            // trace — a card published as text by decision was recorded as prepared, and the oracle's bucket for it
            // counted zero forever. The presence fact lives in the event name and the reason, not in this label.
            trace?.record(presented ? "candidate" : "suspended", ["revision": candidate.originRevisionID.rawValue.uuidString,
                "readiness": Self.readinessLabel(readiness, for: candidate.originRevisionID),
                // A selected candidate that cannot be presented is an internal contradiction: it must be loud.
                "reason": presented ? "presentable" : "selected-without-presentation"])
        }
        return .init(inputs: try selection.orderedCandidates.map { candidate in
            guard let presentation = snapshot[candidate.originRevisionID] else {
                throw PreparationError.candidateWithoutPresentation(candidate.originRevisionID)
            }
            let source = candidate.sourceIDs.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }.first { names[$0] != nil }
                ?? candidate.sourceIDs.first
            // F10/T9/D2: one decision states both facts — the card's identity (audio, video or none), read from
            // the enclosure's own class, and the one action it may carry. An audio episode plays from its
            // enclosure; a video item opens its article at the origin; anything else opens its article.
            let decision = PublishedMediaDecision.resolve(playback: playback(candidate.originRevisionID),
                link: candidate.primaryLink)
            return .init(origin: .init(originRecordID: candidate.originRecordID, originRevisionID: candidate.originRevisionID,
                sourceID: source, providerID: candidate.providerID, sourceDisplayName: source.flatMap { names[$0] },
                providerDisplayName: nil),
                contentEntityID: nil, contentClusterID: nil,
                primaryAction: decision.primaryAction, mediaIdentity: decision.identity,
                presentation: presentation)
        }, cardIDs: selection.orderedCandidates.map { _ in PublicationCardID() })
    }

    /// The readiness of one candidate, as a fact rather than a feeling: prepared with an image, prepared as text
    /// by decision, or **not ready at all** — the last one is the pending case F06 exists for.
    nonisolated static func readinessLabel(_ readiness: MediaReadiness,
        for revision: OriginRevisionID) -> String {
        if readiness.prepared(revision) != nil { return "prepared" }
        guard readiness.isSettled(revision) else { return "pending" }
        // Settled with a presentation is a declared text card; settled without one is unavailable media, which
        // leaves the publication queue (INV-17). Neither is "prepared".
        return readiness.presentation(for: revision) == .textOnly ? "textOnly" : "unavailable"
    }

    /// Mede o que o dono sente e a suíte não vê (decisão de 2026-10-14). O trace da corrida passa a ter, por
    /// segundo, quantos quadros passaram do orçamento e qual foi o pior — o **hitch ratio** que julga cada mudança
    /// de fluidez, em vez de mais uma rodada de testes verdes.
    ///
    /// O **mesmo tique** carrega a linha da jornada no console do aparelho (ordem do PO, 2026-10-15): o console é o
    /// único canal que uma jornada física tem neste Mac, e um relato do dono precisa deixar rastro. Nada de um
    /// segundo relógio: o amostrador pega carona neste, e é `nil` fora do DEBUG e com a chave desligada.
    @ObservationIgnored private lazy var frameMeter = FeedFrameMeter(
        record: { [weak self] event, fields in
            self?.trace?.record(event, fields)
            // `first_frame` is stated once per process and never repeated, so it cannot wait for the 64-line batch:
            // a run killed before that batch would lose the only fact that says the display had delivered a frame.
            // Every other event repeats by nature; this one does not.
            if event == "first_frame" { self?.trace?.flush() }
        },
        journey: journeySampler())

    /// O amostrador da jornada. `nil` é o caso de Release e o caso de fábrica: o medidor não pergunta nada e não
    /// gasta nada por segundo.
    private func journeySampler() -> (@MainActor (Double) -> String?)? {
        #if DEBUG
        guard FeedJourneyConsole.enabled else { return nil }
        return { [weak self] elapsed in self?.journeyLine(elapsedSeconds: elapsed) }
        #else
        return nil
        #endif
    }

    #if DEBUG
    /// Os fatos de um segundo, lidos dos donos que já os têm: a projeção publicada (as cartas e o tipo de mídia que
    /// cada uma declara), o índice da própria camada de mídia (`media.readiness`), a evidência de pipeline do PD-3
    /// (`preparation`) e os contadores de fluxo que o host já lê. Nenhum contador novo é aberto aqui.
    private func journeyLine(elapsedSeconds: Double) -> String {
        var facts = FeedJourneyConsole.Facts()
        facts.elapsedSeconds = elapsedSeconds
        for card in store.state.presentation?.window.items ?? [] {
            facts.cards += 1
            switch card.layout {
            case .hero: facts.hero += 1
            case .thumbnail: facts.thumbnail += 1
            case .textOnly: facts.textOnly += 1
            }
            // A carta traz os pixels com os quais ela **desenha**; nil é o placeholder congelado do layout (PD-5).
            // É o par que o dono pediu — mídia declarada (`hero + thumb`) contra mídia pronta —, na mesma unidade.
            if card.image != nil { facts.mediaResident += 1 }
        }
        facts.mediaPrepared = media.readiness.preparedCount
        facts.mediaSettled = media.readiness.settledCount
        if let progress = preparation {
            facts.sourcesContacted = progress.sources.count
            facts.sourcesResponded = progress.contributingSources
            facts.sourcesUnreachable = progress.sources.filter { $0.state == .unreachable }.count
        }
        // `preparation` é mantido depois do fim da cadeia fria para a linha poder repetir o último valor
        // conhecido; o que diz se os números ainda estão sendo observados é o relé, desligado junto com ela.
        facts.preparationLive = relay.receive != nil
        facts.installRejects = FeedFlowCounters.installRejects
        return FeedJourneyConsole.line(facts)
    }
    #endif

    /// R02: installation validates and assigns **values**. It performs no storage read, opens no database and awaits
    /// no preparation; the bookmark half is a prepared value whose base is checked against the confirmed revision.
    /// A package prepared before a reader's own save/remove is recognised as older and cannot undo it.
    ///
    /// A window that changed without a prepared bookmark half asks the single bounded refresher for one read; the
    /// position itself is installed immediately, so the reader never waits for the library.
    func install(_ prepared: PreparedFeedInstallation) throws {
        FeedFlowCounters.installAttempts += 1
        guard active else { throw FeedPresentationStateError.projectionSequenceMismatch }
        do { try store.install(prepared.state); FeedFlowCounters.installAccepts += 1 }
        catch { FeedFlowCounters.installRejects += 1; throw error }
        // O feed está em tela: a partir daqui o intervalo entre quadros é medido e escrito no trace.
        frameMeter.start()
        let installed = store.state.presentation
        let window = BookmarkWindowKey(store.state)
        if let bookmarks = prepared.bookmarks {
            if bookmarks.base == bookmarkMutationRevision {
                confirmedBookmarks = bookmarks.ids
                store.installBookmarks(bookmarks.ids)
                bookmarksPreparedFor = window
            } else {
                // The confirmed set is newer than this preparation; it wins, and the window gets one fresh read.
                scheduleBookmarkRefresh()
            }
        } else if window != bookmarksPreparedFor {
            scheduleBookmarkRefresh()
        }
        if let snapshot = installed {
            // Com o diagnóstico ligado, a instalação também diz **quais** cartas ela admitiu, na ordem — é o que
            // permite comparar os IDs antes e depois de cada poda, que o arquiteto pediu ao Kiro para concluir a
            // revisão. Desligado por padrão, como o resto do traço.
            #if DEBUG
            let admittedIDs = ProcessInfo.processInfo.environment["FEEDMINE_TRACE_CAPTURE"] == "1"
                ? " ids=[" + snapshot.window.items.map(\.id.rawValue.uuidString).joined(separator: ",") + "]" : ""
            #else
            let admittedIDs = ""
            #endif
            Self.log("installed cards=\(snapshot.window.items.count) edition=\(snapshot.editionID.rawValue) sequence=\(snapshot.provenance.sequenceID) order=\(snapshot.provenance.position)\(admittedIDs)")
            trace?.record("admitted", ["cards": String(snapshot.window.items.count),
                "edition": snapshot.editionID.rawValue.uuidString,
                "sequence": String(describing: snapshot.provenance.sequenceID),
                "order": String(describing: snapshot.provenance.position),
                // The host installation, told in card ids: `replenishment_concluded` names the head and tail of the
                // segment it published, and these two name what the app actually installed. Admission in the pool
                // is not an offer the reader can reach; this line is where that gap can be measured.
                "head": snapshot.window.items.first?.id.rawValue.uuidString ?? "",
                "tail": snapshot.window.items.last?.id.rawValue.uuidString ?? "",
                "anchor": snapshot.window.anchor.cardID.rawValue.uuidString])
        }
    }

    /// Every caller that carries no bookmark half keeps this spelling: the state is installed exactly as before and
    /// a changed window schedules the one bounded bookmark read.
    func install(_ received: FeedPresentationState) throws {
        try install(PreparedFeedInstallation(state: received))
    }

    /// F05/R4 + R6-E: the runtime — never a reader gesture, never the clock — extends the admitted window with
    /// cards the local store already published. The anchor, the reading position and every already-admitted card
    /// are preserved; a window with nothing new installs nothing.
    ///
    /// Every caller is a **fact**, and the two kinds of caller are the two kinds of fact there are:
    ///
    /// - a concluded publication — the receipt the driver delivers from the drain that executed the slice
    ///   (`publicationConcluded`), and the cold bootstrap's own `.published` (the outcome `launch()` returns and the
    ///   evidence raised while slower feeds still answer);
    /// - a reader opportunity (`viewport`, `foreground`), which is the reader's own and is what carries a reserve
    ///   the reader had no screen for (the hidden tail succeeded in `background()`).
    ///
    /// The bounded chain of timed reads that stood here is **gone**: it could not state when a publication
    /// concluded, so a publication that concluded after it — or while a driver drain awaited media and acquisition
    /// for minutes — had no fact with which to reach the window, and the window kept only the first segment. The
    /// growth itself is unchanged and stays the session's own admission (`FeedPresentationAdmission.publishedGrowth`),
    /// bounded by the frozen forward capacity of the anchor and a no-op when repeated.
    private func growAdmittedWindowIfPublished() async {
        do {
            guard active else { return }
            let admittedBefore = store.state.presentation?.window.items.count
            guard let grown = try await session.admitPresentation(.publishedGrowth) else { return }
            let after = grown.window.items.count
            // R5 evidence: the window's growth is a fact worth stating in the log, because "published but not
            // admitted" is exactly the gap this round exists to close.
            Self.log("published growth: admitted \(admittedBefore ?? 0) -> \(after)")
            if after != admittedBefore {
                try install(FeedPresentationHandoff.receive(snapshot: grown, into: store.state))
                // Cards arrived: whatever end the reader was shown is no longer true.
                if store.state.work == .endOfContent { try install(store.state.reporting(.idle)) }
            }
        } catch { reportFailure(error) }
    }

    /// R6-E: a publication that concluded, stated as the fact it is. The driver delivers the receipt of the segment
    /// its drain just executed, so the window follows the publication at that moment — a launch, a viewport, a
    /// foreground, a retry, or a publication nobody's opportunity followed, which is the case the timed chain could
    /// not serve (the red regression R6-E).
    ///
    /// **O destinatário valida a identidade que o recibo transporta.** O recibo nomeia a edição para a qual ele foi
    /// publicado, e só a edição vigente pode ser admitida: `admitPublishedGrowth` age sobre a edição instalada
    /// *neste instante*, então sem esta verificação um recibo de edição que o leitor já deixou admitiria, na edição
    /// vigente, cartas que só a publicação dela autoriza. O controlador valida o recibo quando conclui a fatia, mas
    /// existe uma suspensão entre essa validação e esta entrega — a checagem do produtor não substitui a do
    /// destinatário. Nada é criado aqui: nem fila, nem estado, nem segundo dono; é a identidade já transportada.
    private func publicationConcluded(_ receipt: PublicationReceipt) async {
        guard active,
            let scope = await session.currentRunwayScope(),
            scope.editionID == receipt.editionID
        else { return }
        Self.log("publication concluded edition=\(receipt.editionID.rawValue.uuidString) "
            + "segment=\(receipt.segmentID.rawValue.uuidString) ordinal=\(receipt.segmentOrdinal)")
        // P05: the stage's **useful** yield is measured where it happens — cards that became a published segment,
        // over the elapsed time since the previous one. Two data points are required; the policy never reads a
        // single sample as a rate.
        let now = monotonicNow().seconds
        if let last = lastPublication {
            let elapsed = now - last.at
            if elapsed > 0, receipt.cardIDs.count > 0 {
                usefulYield.set(Double(receipt.cardIDs.count) / elapsed)
            }
        }
        lastPublication = (now, receipt.cardIDs.count)
        await growAdmittedWindowIfPublished()
    }

    /// B/§3: the prefetcher's transition is a local-supply fact. The driver notifies the runway; it does not
    /// publish, admit or start a second pipeline here.
    private func noteMediaReadinessChanged() async {
        await driver.noteMediaReadinessChanged()
    }

    /// PO 2026-10-14: the end of the reader's eligible offer is stated only from the full settled evidence the
    /// driver reports, and only here — this association owns the one screen value. It states nothing else: a
    /// settled drain that is not the end may only take the end back (a later acquisition means content again),
    /// so every provisional state keeps whatever the reader is already seeing.
    private func installSettledEligibleOffer() async throws {
        #if DEBUG
        // Instrumentation for the end-of-content surface: the real evidence only settles once the engine has
        // exhausted a corpus, which no single device or simulator run reaches. The hook injects the
        // **evidence**, never the state — the rule, the handoff and the surface stay the product's own, and the
        // proof that runs on it is a journey test over the real screen (`FEEDMINE_END_ELIGIBLE_OFFER=1`).
        if ProcessInfo.processInfo.environment["FEEDMINE_END_ELIGIBLE_OFFER"] == "1" {
            let settlement = FeedEligibleOfferSettlement(acquisition: .acceptedUnavailable(.noEligibleTargets),
                localSupplyExhausted: true, nothingInFlight: true, noOutstandingAcquisition: true,
                noStoryAhead: true)
            try install(store.state.reporting(FeedPresentationHandoff.work(settledEligibleOffer: settlement)))
            return
        }
        #endif
        guard let settlement = await driver.settledEligibleOffer() else { return }
        let settled = FeedPresentationHandoff.work(settledEligibleOffer: settlement)
        guard settled == .endOfContent || store.state.work == .endOfContent else { return }
        try install(store.state.reporting(settled))
    }

    /// PO/R3: "Tentar novamente" runs a real attempt, not a repaint: the pending schedule is dropped
    /// and one opportunity goes out now, through the same path the reader's foreground uses.
    func retryNow() async {
        guard active else { return }
        #if DEBUG
        // The deterministic recovery journey: with `FEEDMINE_FAIL_FIRST_FEED_ATTEMPT=1` the app's own fixture
        // transport fails until this point, and the reader's retry is what restores it. In every other run this is
        // a no-op (the flag is off), and no product path reads it.
        DevelopmentLocalFeeds.allowRecovery()
        #endif
        retryTask?.cancel()
        retryTask = nil
        await foreground()
    }

    func launch() async throws {
        guard active, !launching else { return }
        launching = true
        defer { launching = false }
        // P05: the volume capacity is read once, off the MainActor, before the first budget that can use it.
        await storageCapacity.refresh()
        // P06/A10: the first projection the reader sees already carries the durable bookmark set, prepared here
        // **before** installing it. A failed read keeps the previous set (there is none on a first launch) instead
        // of confirming an empty library; the base revision protects a concurrent confirmed toggle.
        let preparedBookmarks = await prepareBookmarksForInstallation()
        let restored = try await session.admitPresentation(.initial(bounds))
        if let restored {
            try install(.init(state: FeedPresentationHandoff.receive(snapshot: restored, into: store.state),
                bookmarks: preparedBookmarks))
            Self.log("local restore before HTTP")
        } else {
            // PD-3: show real evidence of content arriving while the first Edition is prepared.
            let started = PreparationProgress(startedAt: ProcessInfo.processInfo.systemUptime)
            preparation = started
            try install(store.state.reporting(.preparing(started)))
            relay.receive = { [weak self] in await self?.receive($0) }
            // A última evidência de pipeline **fica**: `receive` para de ser chamado quando o relé é desligado, e a
            // linha de jornada do console continua podendo dizer quantas fontes foram contactadas e quantas
            // responderam depois que a cadeia fria terminou (ordem do PO, 2026-10-15). Nada a lê além dela: a tela
            // de preparação é alimentada por `install`, não por esta variável.
            defer { relay.receive = nil }
            Self.log("cold bootstrap started")
            let now = Date()
            let outcome = try await cold.run(identity: .init(editionID: FeedEditionID(), publicationSchemaVersion: .init(rawValue: 1),
                selectionSeed: 1, editionCreatedAt: now, segmentID: FeedSegmentID(), segmentSeed: 1,
                segmentCreatedAt: now, anchorPlacement: .top, checkpointedAt: now)!,
                resources: .init(localExaminedCapacity: 32, acquisition: resources.acquisition)!,
                backwardCapacity: 8, forwardCapacity: 16, keepsAdmittedHead: true)
            try install(.init(state: FeedPresentationHandoff.receive(coldOutcome: outcome, into: store.state),
                bookmarks: preparedBookmarks))
            Self.log("cold bootstrap settled")
            if case .published = outcome {
                // R6/E-F: the bootstrap's own publication is a fact, and the window follows it here — before the
                // driver's activation below, which can await media and acquisition for a long time on the shipped
                // catalogue (measured: minutes, while the reserve already held 22 published cards). Where a
                // publication concludes inside the driver instead, its receipt arrives from there.
                await growAdmittedWindowIfPublished()
            } else {
                // Review F16: no first Edition yet. Recover without a gesture at the earliest fact-based
                // time: a cooling feed's expiry, else one request timeout (what one attempt may cost).
                coldRetryAt = await coordinator.nextCoolingExpiry()
                    ?? ProcessInfo.processInfo.systemUptime + coldRetryFallbackSeconds
                await scheduleLocalRetryIfNeeded()
                return
            }
            coldRetryAt = nil
        }
        let snapshot = try await driver.activateCurrentPresentation(resources: resources)
        try install(.init(state: FeedPresentationHandoff.receive(snapshot: snapshot, into: store.state),
            bookmarks: preparedBookmarks))
        try await installSettledEligibleOffer()
        // R5/S5: nothing is armed here, and nothing needs to be. A reopen shows exactly what the reader left — the
        // window installed above is the projection of their own checkpoint — and the window that does grow is the
        // one a **concluded publication** grows: the driver delivered any receipt of this drain from inside it, and
        // the bootstrap's own publication was followed above. The end of the launch is not a fact about the reserve.
        await scheduleLocalRetryIfNeeded()
    }

    /// Review M7: a stationary reader produces no new observation, so a failed local slice would
    /// otherwise never be retried. One opportunity is scheduled at the controller's eligibility time.
    @ObservationIgnored private var retryTask: Task<Void, Never>?

    // MARK: - Bounded viewport ingress (R01)

    /// One viewport fact as it arrived at the reader's callback, **before** any suspension. `sampledAt` is the
    /// reader's own instant: the runway measures consumption over the intervals between samples, so a fact that is
    /// delivered late by coalescing must still say when the reader produced it. `ordinal` is the ingress order.
    private struct IngressViewportFact: Sendable {
        let observation: ViewportObservation
        let activity: RunwayActivity
        let evidence: RenderedViewportEvidence?
        let sampledAt: RunwayMonotonicTime
        let ordinal: UInt64
        var isReconciliation: Bool { evidence?.isPositionReconciliation == true }
    }

    /// The **finite** summary of one drain's pending work. It is not "the last event": the earliest movement is
    /// kept as the measurement anchor (dropping it would lose the interval the reader's rate is measured over),
    /// the last event is kept as the final position, and the newest of each semantic kind the runway can act on
    /// (reversal, explicit tail approach, rest, local reconciliation) survives even when a later event of another
    /// kind arrives. Every slot holds one fact, so the pending work is bounded by the number of kinds — never by
    /// the size of the burst.
    private struct PendingViewportIngress {
        var firstMovement: IngressViewportFact?
        var latest: IngressViewportFact?
        var latestBackward: IngressViewportFact?
        var latestTailApproach: IngressViewportFact?
        var latestRest: IngressViewportFact?
        var latestReconciliation: IngressViewportFact?
        var presentedPosition: (anchor: PresentationAnchor, atRest: Bool)?

        var isEmpty: Bool {
            firstMovement == nil && latest == nil && latestBackward == nil && latestTailApproach == nil
                && latestRest == nil && latestReconciliation == nil && presentedPosition == nil
        }

        /// What a test can read while the consumer is suspended: the occupied slots, never the burst length.
        var count: Int {
            [firstMovement, latest, latestBackward, latestTailApproach, latestRest, latestReconciliation]
                .compactMap { $0 }.count + (presentedPosition == nil ? 0 : 1)
        }

        mutating func record(_ fact: IngressViewportFact) {
            if fact.isReconciliation {
                latestReconciliation = fact
                return
            }
            if firstMovement == nil { firstMovement = fact }
            latest = fact
            switch fact.activity {
            case .backward: latestBackward = fact
            case .explicitTailApproach: latestTailApproach = fact
            case .stationary: latestRest = fact
            case .forward: break
            }
        }

        mutating func takePresentedPosition() -> (anchor: PresentationAnchor, atRest: Bool)? {
            defer { presentedPosition = nil }
            return presentedPosition
        }

        /// The next fact in reader-time order: the semantic slots are delivered by their own capture instant, so
        /// the runway's strictly increasing `sampledAt` holds even when a burst mixed directions. Ties (the same
        /// instant from the same callback stream) break on the ingress ordinal.
        mutating func takeNext() -> IngressViewportFact? {
            let slots: [IngressViewportFact?] = [firstMovement, latest, latestBackward, latestTailApproach,
                latestRest, latestReconciliation]
            guard let next = slots.compactMap({ $0 })
                .min(by: { ($0.sampledAt.seconds, $0.ordinal) < ($1.sampledAt.seconds, $1.ordinal) }) else {
                return nil
            }
            if firstMovement?.ordinal == next.ordinal { firstMovement = nil }
            if latest?.ordinal == next.ordinal { latest = nil }
            if latestBackward?.ordinal == next.ordinal { latestBackward = nil }
            if latestTailApproach?.ordinal == next.ordinal { latestTailApproach = nil }
            if latestRest?.ordinal == next.ordinal { latestRest = nil }
            if latestReconciliation?.ordinal == next.ordinal { latestReconciliation = nil }
            return next
        }

        mutating func removeAll() {
            firstMovement = nil; latest = nil; latestBackward = nil; latestTailApproach = nil
            latestRest = nil; latestReconciliation = nil; presentedPosition = nil
        }
    }

    /// The reader's facts waiting for the single consumer. `@ObservationIgnored`: ingress bookkeeping must never
    /// re-evaluate a view.
    @ObservationIgnored private var viewportIngress = PendingViewportIngress()
    /// The one consumer of `viewportIngress`. A callback records and returns; it never creates a task per event.
    @ObservationIgnored private var viewportDrain: Task<Void, Never>?
    @ObservationIgnored private var viewportDrainGeneration: UInt64 = 0
    @ObservationIgnored private var ingressOrdinal: UInt64 = 0
    /// Production authorization for the drain. Background ends it (the reader is no longer on screen) and
    /// foreground restores it; `close()` ends it for good through `active`.
    @ObservationIgnored private var ingressAuthorized = true
    /// The reader's instant, as the host defines it. A test injects a controlled clock; production is uptime.
    @ObservationIgnored private let monotonicNow: @Sendable () -> RunwayMonotonicTime

    /// What a test can read while the consumer is suspended (R01): the bounded pending summary, never the burst.
    var pendingViewportIngressCount: Int { viewportIngress.count }

    // MARK: - Prepared bookmark installation (R02)

    /// The durable set the reader confirmed: the last set installed from a read whose base was current, or the one a
    /// confirmed save/box deletion produced. `bookmarkMutationRevision` moves exactly when a mutation commits
    /// durably, which is what lets an older preparation be recognised as older instead of overwriting it.
    @ObservationIgnored private var confirmedBookmarks: Set<PublicationCardID> = []
    @ObservationIgnored private(set) var bookmarkMutationRevision: UInt64 = 0
    /// The single bounded read of the durable set. A projection install never awaits it: installation assigns what
    /// was prepared and a changed window asks for one refresh.
    @ObservationIgnored private var bookmarkRefreshTask: Task<Void, Never>?
    /// The window whose bookmarks are already prepared, so a position without a material difference publishes
    /// nothing and reads nothing while the handoff keeps feeding runway/production.
    @ObservationIgnored private var bookmarksPreparedFor: BookmarkWindowKey?
    /// Reads the durable bookmark set **off the main actor**. A test suspends this to prove installation does not
    /// call it; the product reads through the one library database, detached.
    @ObservationIgnored private let bookmarkRead: @Sendable () async throws -> Set<PublicationCardID>

    /// P06: prepare the bookmark half off the caller, before a new presentation is installed. The revision is read
    /// **before** the storage read, so a toggle confirmed while the read is in flight makes the package older and
    /// it cannot undo that toggle. A failure returns nil: the previous set is kept, never an empty "confirmed" one.
    private func prepareBookmarksForInstallation() async -> PreparedFeedInstallation.Bookmarks? {
        let base = bookmarkMutationRevision
        do { return .init(ids: try await bookmarkRead(), base: base) }
        catch { return nil }
    }

    /// P06: the membership key is O(1). The admitted window only grows or shrinks at its ends (append/prepend) or is
    /// replaced as a whole, so edition, context, count and both endpoints identify it without rebuilding the id
    /// array on every position-only install.
    private struct BookmarkWindowKey: Equatable {
        let editionID: FeedEditionID?
        let contextKey: ContextKey?
        let count: Int
        let first: PublicationCardID?
        let last: PublicationCardID?
        init(_ state: FeedPresentationState) {
            editionID = state.presentation?.editionID
            contextKey = state.presentation?.contextKey
            count = state.presentation?.window.items.count ?? 0
            first = state.presentation?.window.items.first?.id
            last = state.presentation?.window.items.last?.id
        }
    }

    /// A confirmed mutation of the reader's library that can change the bookmark set (a save/remove, a box
    /// deletion). The durable write precedes it; the refresh is the one bounded read, and the revision is the fence
    /// every older preparation is checked against.
    func bookmarkMutationConfirmed() {
        guard active else { return }
        bookmarkMutationRevision &+= 1
        scheduleBookmarkRefresh()
    }

    private func scheduleBookmarkRefresh() {
        guard active, bookmarkRefreshTask == nil else { return }
        let window = BookmarkWindowKey(store.state)
        let base = bookmarkMutationRevision
        let read = bookmarkRead
        bookmarkRefreshTask = Task { [weak self] in
            let ids: Set<PublicationCardID>?
            do { ids = try await read() } catch { ids = nil }
            guard let self else { return }
            self.bookmarkRefreshTask = nil
            guard let ids, self.active else { return }
            if base == self.bookmarkMutationRevision {
                self.confirmedBookmarks = ids
                self.store.installBookmarks(ids)
                self.bookmarksPreparedFor = window
            } else {
                // A newer confirmation exists. Its own request may have coalesced into this read; the stale answer
                // is discarded and the current state is read once more.
                self.scheduleBookmarkRefresh()
            }
        }
    }

    /// R04: the system asks for bytes. Keep the reader's own band and release the rest — identity, order, anchor,
    /// geometry and the durable payload do not change. The trimmed value is installed so the pixels are really let
    /// go (the store holds its own copy of the cards).
    func trimResidencyForMemoryPressure() async {
        do {
            guard try await session.trimResidencyForMemoryPressure() else { return }
            guard let trimmed = await session.currentPresentation() else { return }
            try install(FeedPresentationHandoff.receive(snapshot: trimmed, into: store.state))
        } catch { reportFailure(error) }
    }

    /// Records one viewport fact in the finite summary and lets the **single** consumer do the work. Called from
    /// the store's own callback, so the capture returns immediately and the producer is never awaited here.
    func receiveViewportIngress(_ observation: ViewportObservation, activity: RunwayActivity,
        evidence: RenderedViewportEvidence?) {
        guard active, ingressAuthorized else { return }
        if evidence?.isPositionReconciliation != true {
            // Exposure is a fact of the reader's own callback: coalescing later must not lose the cards the reader
            // actually saw between two delivered opportunities.
            editorialExposure.expose(observation.anchor.cardID)
            #if DEBUG
            viewportReceived += 1
            #endif
        }
        ingressOrdinal &+= 1
        viewportIngress.record(.init(observation: observation, activity: activity, evidence: evidence,
            sampledAt: monotonicNow(), ordinal: ingressOrdinal))
        startViewportDrain()
    }

    /// Records the drawn position. It is a position, not a production opportunity: the latest one wins and is
    /// delivered by the same single consumer.
    func receivePresentedPositionIngress(_ anchor: PresentationAnchor, atRest: Bool) {
        guard active, ingressAuthorized else { return }
        viewportIngress.presentedPosition = (anchor, atRest)
        startViewportDrain()
    }

    private func startViewportDrain() {
        guard viewportDrain == nil, active, ingressAuthorized else { return }
        viewportDrainGeneration &+= 1
        let generation = viewportDrainGeneration
        viewportDrain = Task { [weak self] in
            await self?.consumeViewportIngress()
            guard let self, self.viewportDrainGeneration == generation else { return }
            self.viewportDrain = nil
            // A fact that arrived between the last take and releasing ownership must not be stranded; with no
            // suspension between these lines, the check cannot race an ingress on the main actor.
            if !self.viewportIngress.isEmpty { self.startViewportDrain() }
        }
    }

    /// The single consumer: positions first (they are cheap and idempotent), then the semantic facts in reader-time
    /// order. It stops as soon as the association retires or background revokes production.
    private func consumeViewportIngress() async {
        while true {
            guard active, ingressAuthorized, !Task.isCancelled else { return }
            if let position = viewportIngress.takePresentedPosition() {
                await notePresentedPosition(position.anchor, atRest: position.atRest)
                continue
            }
            guard let fact = viewportIngress.takeNext() else { return }
            await viewport(fact.observation, activity: fact.activity, evidence: fact.evidence,
                sampledAt: fact.sampledAt)
        }
    }

    /// Ends the drain's authorization and its pending work, keeping the **promised drawing position**: the reader's
    /// last presented anchor is delivered before the checkpoint, because a suspension must not lose where they were.
    private func revokeViewportIngress() async {
        ingressAuthorized = false
        viewportDrain?.cancel()
        viewportDrain = nil
        viewportDrainGeneration &+= 1
        if let position = viewportIngress.takePresentedPosition() {
            await notePresentedPosition(position.anchor, atRest: position.atRest)
        }
        viewportIngress.removeAll()
    }
    /// Review F09: only a visible association may drive the feed. Background and close revoke it.
    @ObservationIgnored private var visible = true
    /// F16: when the next cold attempt may run if no first Edition exists yet.
    @ObservationIgnored private var coldRetryAt: Double?
    @ObservationIgnored private var coldRetryFallbackSeconds: Double = 20
    private func scheduleLocalRetryIfNeeded() async {
        retryTask?.cancel()
        retryTask = nil
        let local = await driver.localRetryEligibleAt()?.seconds
        let acquisition = await driver.acquisitionResumeAt()?.seconds
        let cold = await session.currentPresentation() == nil ? coldRetryAt : nil
        // One opportunity at the earliest fact-derived time: a local retry or a feed leaving cooldown.
        guard active, visible, let at = [local, acquisition, cold].compactMap({ $0 }).min() else { return }
        let eligible = RunwayMonotonicTime(seconds: at) ?? RunwayMonotonicTime(seconds: 0)!
        let wait = max(0, eligible.seconds - ProcessInfo.processInfo.systemUptime)
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.scheduledOpportunity()
        }
    }

    /// A timed opportunity runs only if the app is still visible when it fires.
    private func scheduledOpportunity() async {
        guard active, visible, !launching else { return }
        await foreground()
    }

    /// PD-3: reduce pipeline evidence into the preparation screen value.
    private func receive(_ evidence: ColdFeedEvidence) async {
        guard active, var progress = preparation else { return }
        let now = ProcessInfo.processInfo.systemUptime
        // Whether this delivery installed the first Edition — the publication fact whose window follows it.
        var concludedPublication = false
        switch evidence {
        case .contacting(let targets):
            for target in targets {
                progress = progress.applying(.contacting(id: target.rawValue.uuidString,
                    name: targetNames[target] ?? "Fonte"), at: now)
            }
        case .settled(let target, let stop, let changed):
            let reachable: Bool
            if case .operationalFailure = stop { reachable = false } else { reachable = true }
            progress = progress.applying(.settled(id: target.rawValue.uuidString, contributed: changed, reachable: reachable), at: now)
            if changed {
                progress = progress.applying(.admitted(headlines: admittedHeadlines()), at: now)
                // R7-E: a source that brought supply is **not** the publication-completed event, and the earlier
                // claim here ("a source that brought supply *is* the publication-completed event") was false in
                // both directions: `ColdFeedBootstrap.run` raises `.settled` **before** the publication attempt a
                // supply change may open, and it raises it even when no attempt follows (`first.snapshot == nil`
                // already published). Nothing grows the window from a settle: the publication fact is the
                // `.published` case below — the same segment the bootstrap returns as its outcome.
            }
        case .preparingMedia:
            break
        case .published(let snapshot):
            progress = progress.applying(.prepared(cards: snapshot.window.items.count), at: now)
            // F06: show the first Edition now; slower feeds keep answering behind the badge.
            do {
                try install(FeedPresentationHandoff.receive(snapshot: snapshot, into: store.state))
                concludedPublication = true
            }
            catch { Self.log("early publication rejected") }
        }
        // The value and its report are written **before** the growth: a delivery that suspends waiting for the
        // window must not lose a concurrent target's progress (`executeConcurrently` settles several at once).
        preparation = progress
        do { try install(store.state.reporting(.preparing(progress))) } catch { Self.log("preparation update rejected") }
        // R6-E: this case is the publication fact — the snapshot it installed is the outcome of the segment
        // `InitialProductionSlice` published, and the window that already existed for it is filled here, while the
        // slower feeds are still answering behind the badge.
        if concludedPublication { await growAdmittedWindowIfPublished() }
    }

    func viewport(_ observation: ViewportObservation, activity: RunwayActivity,
        evidence: RenderedViewportEvidence? = nil,
        sampledAt: RunwayMonotonicTime? = nil) async {
        do {
            guard active else { throw FeedPresentationStateError.projectionSequenceMismatch }
            if let evidence {
                guard let current = store.state.presentation, evidence.belongs(to: current) else { return }
            }
            // F02's budget counts **this** and nothing else: the capture's own proof of the card the reader is
            // at. It is recorded before the handoff, because the reader's exposure happened whether or not the
            // publication side accepted the opportunity.
            if evidence?.isPositionReconciliation != true {
                // Direct callers keep the exposure fact here; the store path already recorded it at ingress.
                // The ledger is idempotent, so a coalesced fact is never counted twice.
                editorialExposure.expose(observation.anchor.cardID)
            }
            if evidence?.isPositionReconciliation != true {
                Self.log("viewport forwarded activity=\(activity) anchor=\(observation.anchor.cardID)")
                trace?.record("advance", ["activity": String(describing: activity),
                    "anchor": observation.anchor.cardID.rawValue.uuidString])
                Self.log("viewport opportunity sent to driver")
            }
            let received = try await FeedPresentationHandoff.submitViewport(observation, activity: activity,
                resources: resources, driver: driver, into: store.state, evidence: evidence,
                sampledAt: sampledAt,
                onCommitted: { [weak self] committed in
                    await MainActor.run {
                        guard let self, self.active else { return }
                        let received: FeedPresentationState
                        do { received = try FeedPresentationHandoff.receive(snapshot: committed, into: self.store.state) }
                        catch { Self.log("obsolete early viewport projection rejected"); return }
                        do { try self.install(received) }
                        catch { Self.log("obsolete early viewport projection rejected") }
                    }
                })
            guard active else { return }
            // The committed projection may already have been installed while the driver drained work.
            // A late receipt is not a product failure and must not overwrite newer reader input.
            if let candidate = received.presentation, let current = store.state.presentation,
                candidate.provenance.sequenceID == current.provenance.sequenceID,
                candidate.provenance.position < current.provenance.position {
                Self.log("obsolete viewport receipt ignored")
            } else {
                // Republicar por avanço é o que mantém a sessão e a tela no mesmo valor; a **lista** já não re-renderiza
                // por causa disso (ela observa `renderedItems`, não a posição). A supressão desta instalação foi
                // medida e **estrangulou a produção** (2026-10-14): sem instalações o handoff e o runway paravam de
                // ser alimentados.
                try install(received)
            }
            if evidence?.isPositionReconciliation == true {
                Self.log("rendered position reconciled locally")
                return
            }
            // PO 2026-10-14: a leitura que acabou de ser admitida e estabelecida passa a ser **durável** aqui. É
            // este o momento que o fechamento à força usa para voltar ao mesmo card; a janela máxima de perda é a
            // declarada em `FeedSession.settledPositionDebounceWindow`, e a escrita roda no ator da sessão — nunca
            // no corpo de uma view nem no quadro que está sendo desenhado. Um repouso (`stationary`) é o fato que
            // a decisão nomeia e grava na hora; as observações em movimento são as que a janela limita.
            await recordSettledPosition(settled: activity == .stationary)
            // O fim é decidido antes desta leitura: se esta oportunidade trouxer cards, o crescimento retrata o fim
            // em vez de o fim ser reinstalado por cima da retratação (revisão, 2026-10-14). Uma publicação que
            // conclui **dentro** deste drain já cresceu a janela pelo fato (o recibo que o driver entrega), e o fim
            // não volta por cima disso: publicar zera o `readyAhead` da pista e sem ele o settlement não é o fim.
            try await installSettledEligibleOffer()
            // A leitura abaixo é a **oportunidade do leitor**, nunca um relógio: as publicações crescem a janela no
            // fato, e o que ela pega é a reserva cujo fato o leitor não tinha tela para receber — a cauda oculta
            // sucedida no `background()`, publicada com a tela desligada e materializada quando ele volta. Repetir é
            // no-op: a admissão é append-only e limitada pelo teto congelado da âncora.
            await growAdmittedWindowIfPublished()
            await scheduleLocalRetryIfNeeded()
            #if DEBUG
            viewportCompleted += 1
            if activity == .backward { backwardCompleted += 1 }
            #endif
            Self.log("Runway opportunity completed activity=\(activity)")
            // F05: the runway the reader actually has, stated where it can be read over time — the admitted
            // cards the window is holding, beside the activity that opened the opportunity.
            trace?.record("runway_completed", ["activity": String(describing: activity),
                "admitted_cards": String(store.state.presentation?.window.items.count ?? 0)])
            trace?.flush()
        } catch {
            reportFailure(error)
            if evidence?.isPositionReconciliation != true { await scheduleLocalRetryIfNeeded() }
        }
    }

    /// PO 2026-10-14: a última posição **admitida e estabelecida** do leitor vira posição durável — a que um
    /// fechamento à força recupera. O dono do cursor é a sessão (`FeedSession.recordSettledPosition`), que aplica a
    /// janela máxima de perda declarada lá; aqui só se diz **quando**:
    ///
    /// - Depois de a observação do leitor ter sido admitida e instalada, com o fato que o driver já traz —
    ///   `activity == .stationary` é o leitor **chegando ao repouso** (a própria captura emite esse evento uma vez
    ///   por repouso), e um repouso nunca espera a janela.
    /// - E pelo repouso do próprio **desenho** (`FeedScreenStore.publishPresentedPosition(_:atRest:)` →
    ///   `notePresentedPosition`), que é o único caminho por onde uma tela movida **sem** gesto — uma rolagem de
    ///   acessibilidade, uma animação do sistema — vira posição durável: sem ele, o leitor que morre depois de uma
    ///   dessas volta a uma posição que ele já tinha deixado (medido: B05 2026-10-14, o `presentedCard` que o driver
    ///   mediu antes do `terminate` estava a oito cards do cursor durável).
    ///
    /// **O quê** já não é dito aqui: a sessão lembra a posição que o desenho relatou (`notePresentedPosition`) e
    /// grava o card em que o viewport começa, não o card em que o leitor está — ver
    /// `FeedSession.recordSettledPosition(at:settled:)`. Os dois fatos acima chegam ao mesmo dono e ao mesmo
    /// registro, então a observação do leitor e o repouso do desenho não podem discordar sobre a posição.
    ///
    /// A escrita roda no executor do ator da sessão, nunca no caminho de renderização. Uma falha de escrita é
    /// registrada e não interrompe a leitura: o cursor anterior continua descrevendo o leitor, uma janela atrás, e a
    /// próxima observação estabelecida tenta de novo.
    private func recordSettledPosition(settled: Bool) async {
        do {
            report(checkpoint: try await session.recordSettledPosition(at: Date(), settled: settled))
        } catch { Self.log("settled position checkpoint failed \(error)") }
    }

    /// O mesmo dono, o mesmo registro: o app relata **onde o viewport desenhado começa** e se o desenho está em
    /// repouso nele. É por aqui que uma tela movida **sem** gesto — uma rolagem de acessibilidade, uma animação do
    /// sistema — vira posição durável; sem esse fato, o leitor que morre depois de uma dessas volta a uma posição
    /// que já tinha deixado (medido: B05 2026-10-14, o `presentedCard` que o driver mediu antes do `terminate`
    /// estava a oito cards do cursor durável). Em movimento o fato é só lembrado pela sessão, que aplica a janela
    /// máxima de perda declarada lá.
    private func notePresentedPosition(_ anchor: PresentationAnchor, atRest: Bool) async {
        do {
            report(checkpoint: try await session.notePresentedPosition(anchor, atRest: atRest))
        } catch { Self.log("settled position checkpoint failed \(error)") }
    }

    /// O `written` é o único desfecho que custa uma escrita; é ele que entra no registro da corrida, e é a contagem
    /// dessas linhas por minuto de leitura que mede o custo contra o orçamento de fluidez. O `keptExactRecord` é o
    /// outro desfecho que o registro da corrida precisa dizer: uma afirmação incompleta destas associações não
    /// substituiu a carta do topo que o desenho já havia gravado (lead, 2026-10-14).
    private func report(checkpoint recording: SettledPositionRecording?) {
        switch recording {
        case .some(.written(let cardID, let placement)):
            let window = Int(FeedSession.settledPositionDebounceWindow)
            Self.log("settled position checkpoint anchor=\(cardID.rawValue.uuidString) "
                + "placement=\(placement.rawValue) window=\(window)s")
            trace?.record("position_checkpoint", ["anchor": cardID.rawValue.uuidString,
                "placement": placement.rawValue, "window_seconds": String(window)])
        case .some(.keptExactRecord(let cardID)):
            Self.log("settled position kept exact anchor=\(cardID.rawValue.uuidString)")
            trace?.record("position_kept_exact", ["anchor": cardID.rawValue.uuidString])
        case .some(.nothingToRecord), .some(.alreadyDurable), .some(.withinWindow), .none:
            return
        }
        // O registro é durável antes deste evento: se o processo morre antes do próximo flush, um checkpoint que
        // existe no SQLite desaparecia do trace e a reabertura deixava de ter prova. O custo é o mesmo upsert de
        // uma linha, e este caminho escreve no máximo 3 vezes por minuto em movimento (`settledPositionDebounceWindow`).
        trace?.flush()
    }

    /// The feed drive opportunity. Two callers take it, and they are the same path on purpose: the lifecycle's
    /// `.active` transition and the foreground cadence (`ForegroundDriveCadence`, owner's decision of 2026-10-17),
    /// which offers it again every ≥ 10 s while the app is active and visible. Nothing here is a second pipeline, and
    /// a drive with nothing to do is a no-op.
    func foreground() async {
        visible = true
        // A resumed screen starts a new measurement window for useful yield as well.
        lastPublication = nil
        // R01: the reader is back on screen; the single ingress may drive again.
        ingressAuthorized = true
        // P05: a lifecycle opportunity, not a poll: the volume may have changed while the app was away, and the
        // read stays off the MainActor.
        await storageCapacity.refresh()
        // O outro lado do par: `background()` para o medidor com a tela, porque o que interessa é o que o leitor
        // sente enquanto rola. Sem esta linha, a medição só voltava por tabela — pelo `install()` que o restore ou
        // a reativação da apresentação corrente alcançam —, e um foreground que não passa por ali (falha no
        // `activateCurrentPresentation`, early-return durante o launch) deixava o medidor parado pelo resto da vida
        // do processo. A tela está visível: a partir daqui ela é medida. `start()` é idempotente (`guard link ==
        // nil`), então quem já está medindo não paga nada.
        frameMeter.start()
        do {
            if let edition = store.state.presentation?.editionID {
                try PublicationStore(database: database).setVisibility(editionID: edition, visible: true)
            }
            guard active, !launching else { return }
            if await session.currentPresentation() == nil {
                // Recovery without replacing the association; a presentation that already exists is
                // never extended here — returning to the app shows exactly what the reader left.
                if let restored = try await session.admitPresentation(.restore(bounds)) {
                    // P06: the recovering projection is a new window; its bookmark half is prepared before it is
                    // installed, through the same path launch uses.
                    try install(.init(
                        state: FeedPresentationHandoff.receive(snapshot: restored, into: store.state),
                        bookmarks: await prepareBookmarksForInstallation()))
                }
                if await session.currentPresentation() == nil {
                    try await launch()
                    return
                }
            }
            // Um foreground é uma **oportunidade**, não só um evento de ciclo de vida: o consumo foi marcado
            // inativo quando a tela saiu (`markConsumptionInactive`), então a observação do runway está zerada e
            // um `drive` puro não tem fato nenhum para agir — o pipeline ficava morto até o leitor rolar. O
            // mecanismo já existe e é o mesmo do launch/restore: reativar a apresentação corrente devolve ao
            // runway a observação do próprio leitor (`.stationary`, sem gesto, sem mudar a lista admitida) e
            // então o trabalho decide. INV-04: o runway antecipa o consumo; rolar não é o que acorda o pipeline
            // (diretiva de execução V2, linha 86).
            let snapshot = try await driver.activateCurrentPresentation(resources: resources)
            try install(FeedPresentationHandoff.receive(snapshot: snapshot, into: store.state))
            // O fim é decidido antes desta leitura (mesma razão do `viewport`): uma publicação concluída já cresceu a
            // janela pelo fato, e o fim não se reinstala por cima disso.
            try await installSettledEligibleOffer()
            // A mesma oportunidade do leitor que o `viewport` oferece, no outro caminho por onde ele volta à tela: é
            // aqui que a reserva publicada enquanto ele não tinha tela — a cauda oculta sucedida no `background()` —
            // é materializada. A chamada não inventa um fato: o que a autoriza é haver publicação concluída
            // (`admitPresentation(.publishedGrowth)` é um no-op sem espaço), e a cadência de foreground só repete a
            // **oportunidade** — ela nunca é a razão pela qual uma carta entra.
            await growAdmittedWindowIfPublished()
            await scheduleLocalRetryIfNeeded()
        } catch { reportFailure(error); await scheduleLocalRetryIfNeeded() }
    }

    func background() async {
        visible = false
        // P1: a late durable fact must not start a new coverage pass with the foreground resources. The
        // authorized round keeps running; only the door to a new opportunity is closed until foreground.
        await driver.suspendForBackground()
        retryTask?.cancel()
        retryTask = nil
        // Wall-clock gaps are not production time: the next publication must establish a new baseline instead of
        // reading a near-zero yield after the pause as measured throughput.
        lastPublication = nil
        // R01: a suspensão encerra a autorização de produção do ingresso. As oportunidades pendentes não devem
        // rodar fora da tela; a **posição prometida** (o último desenho) é entregue antes do checkpoint, porque
        // ela é onde o leitor estava e não uma oportunidade de produção.
        await revokeViewportIngress()
        // O medidor de quadros para com a tela: o que interessa é o que o leitor sente enquanto rola.
        frameMeter.stop()
        guard active else { return }
        do {
            _ = try await session.checkpointCurrentPosition(at: Date())
            await driver.markConsumptionInactive()
            Self.log("lifecycle checkpoint")
            // What the trace saw leaves with it: a run cut short still says everything it observed.
            trace?.flush()
            let lease = try store.state.presentation.map { try PublicationStore(database: database).hiddenTail(editionID: $0.editionID, protectingThrough: $0.window.items.last?.id) } ?? nil
            // PD-5: the screen is not visible now, so the house can be tidied: complete media for
            // the next cards and bring local media under the device-derived budget. Seen and visible
            // cards are never changed.
            // Saved units first: a save whose preparation was interrupted (or that failed for space) is the
            // reader's explicit intent, and the background window is when the app may work without showing it.
            await savedMedia.resume(limit: 8)
            let visible = Set(store.state.presentation?.window.items.compactMap { $0.image?.key } ?? [])
            // The tidy's budget is what the system actually grants while the screen is off, less one media
            // operation's tolerance as the margin — never `timeoutIntervalForRequest / 4`, which was a configured
            // number standing in for a measured one (PD-6 rule 4 permits operational ceilings; F06-G and the north
            // star permit nothing arbitrary).
            #if canImport(UIKit)
            // The allowance is a **snapshot**: read the clock with it, because a deadline computed from a later clock
            // would silently claim time the system never offered (Codex's review of this line).
            let backgroundRemaining = UIApplication.shared.backgroundTimeRemaining
            let readAt = ProcessInfo.processInfo.systemUptime
            #else
            // No UIKit: nothing to report, so the tolerance is the bound (the same answer an unusable report gets).
            let backgroundRemaining = TimeInterval.greatestFiniteMagnitude
            let readAt = ProcessInfo.processInfo.systemUptime
            #endif
            let allowance = Self.tidyAllowanceSeconds(backgroundRemaining: backgroundRemaining,
                tolerance: mediaWaitBudget.current)
            let report = await tidy.run(visibleKeys: visible, supplyHeadLimit: 32, deadline: readAt + allowance)
            Self.log("tidy evicted=\(report.evictedAssets) reclaimed=\(report.reclaimedBytes) budget=\(report.budgetBytes)")
            if active, !self.visible, let lease {
                let result = try await maintainTail(lease)
                Self.log("hidden tail \(result)")
            }
        } catch { reportFailure(error) }
    }

    func close() async {
        cold.cancel()
        viewportDrain?.cancel()
        viewportDrain = nil
        viewportDrainGeneration &+= 1
        viewportIngress.removeAll()
        if let edition = store.state.presentation?.editionID {
            try? PublicationStore(database: database).setVisibility(editionID: edition, visible: true)
        }
        active = false
        visible = false
        retryTask?.cancel()
        await driver.deactivate()
        // R20: `deactivate` deliberately leaves authorized pulls running (their durable supply still counts).
        // Invalidating the transport before they settle lets a pull create a URL session task on an invalidated
        // session — a hard NSException, not a thrown error. Order retirement: cancel, drain, then invalidate.
        // P01: the media owner shares this transport and used to keep starting queued revisions after close. Its
        // fence is closed before the drain, so a timeout can never license a late start.
        _ = await media.retire()
        _ = await coordinator.settleInFlight()
        transport.invalidateAndCancel()
    }

    /// What the failing operation was. Only a **feed update** may present the feed's own failure state: a save, a
    /// copy, a share or opening a card is a local action, and telling the reader "Falha ao atualizar o feed" for it
    /// is a false statement about what failed (PD-2026-10-20 D5). Local actions state themselves in a toast and
    /// never touch the presented feed, so what the reader already had is not replaced by a report about something
    /// else.
    enum FailureOperation: Equatable {
        case feedRefresh
        case openCard
        case save
        case copy
        case share

        /// The reader's words for this operation's failure. The feed's own message is deliberately absent: it
        /// belongs to `.feedRefresh` only, which is rendered as the feed's work state.
        var statement: String? {
            switch self {
            case .feedRefresh: return nil
            case .openCard: return String(localized: "Não foi possível abrir esta carta")
            case .save: return String(localized: "Não foi possível salvar")
            case .copy: return String(localized: "Não foi possível copiar")
            case .share: return String(localized: "Não foi possível compartilhar")
            }
        }
    }

    /// Which statement a failed card action owes the reader. Only a feed update may speak for the feed; a
    /// copy, a save, a share or opening a card answer for themselves (PD-2026-10-20 D5).
    nonisolated static func operation(for action: ReaderCardAction) -> FailureOperation {
        switch action {
        case .copyLink: return .copy
        case .share: return .share
        case .save: return .save
        case .open, .viewSource, .addSourceToCollection, .openMedia: return .openCard
        }
    }

    func reportFailure(_ error: any Error, operation: FailureOperation = .feedRefresh) {
        if let rejection = error as? FeedPresentationStateError {
            Self.log("projection rejected \(rejection)")
            return // typed structural rejection is logged; never install an alternative result/work.
        }
        guard active else { return }
        Self.log("execution failure \(String(describing: error)) operation=\(String(describing: operation))")
        if let statement = operation.statement {
            store.showToast(text: statement, systemImage: "exclamationmark.triangle")
            return
        }
        // PO/R3: a connection failure is stated as such — and only when the transport proved one.
        let work: FeedPresentationState.Work = Self.isConnectionFailure(error)
            ? .unreachable
            : .failed(message: String(localized: "Falha ao atualizar o feed"))
        do { try install(store.state.reporting(work)) }
        catch { Self.log("failure reporting rejected \(String(describing: error))") }
    }

    /// A transport failure is the only evidence that justifies telling the reader the app could not
    /// connect. URLSession reports most of them under NSURLErrorDomain, but the underlying CFNetwork
    /// stream failures (measured: `kCFErrorDomainCFNetwork` 310 when the transport is refused) arrive
    /// under their own domain, so both are read. Anything else keeps the generic failure message.
    nonisolated private static func isConnectionFailure(_ error: any Error) -> Bool {
        let transportDomains: Set<String> = [NSURLErrorDomain, kCFErrorDomainCFNetwork as String]
        let ns = error as NSError
        if transportDomains.contains(ns.domain) { return true }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError,
            transportDomains.contains(underlying.domain) { return true }
        return error is URLError
    }

    nonisolated private static func log(_ value: String) {
        #if DEBUG
        Logger(subsystem: "com.feedmine.development", category: "composition").info("\(value, privacy: .public)")
        #endif
    }
}

/// PD-6: media conditions measured on this device. Slot widths follow the feed layout
/// (FeedCardView: full-width hero, 88 pt thumbnail) on the actual screen; network path, Low Power
/// Mode, thermal state and free space are sampled whenever a policy is requested.
struct DeviceMediaConditions: Sendable {
    let heroPointWidth: Double
    let thumbnailPointWidth: Double
    let scale: Double
    var heroPixelWidth: Int { Int((heroPointWidth * scale).rounded(.up)) }
    var thumbnailPixelWidth: Int { Int((thumbnailPointWidth * scale).rounded(.up)) }

    @MainActor static func currentOnMain() -> DeviceMediaConditions {
        #if canImport(UIKit)
        let screen = UIScreen.main
        // Feed cards are inset by 16 pt outer padding and 16 pt card padding on each side.
        return .init(heroPointWidth: max(1, screen.bounds.width - 64), thumbnailPointWidth: 88, scale: screen.scale)
        #else
        return .init(heroPointWidth: 600, thumbnailPointWidth: 88, scale: 2)
        #endif
    }

    static func policy(device: DeviceMediaConditions, measuredBytesPerSecond: Double?, assetDirectory: URL,
        waitBudgetSeconds: Double) -> MediaPolicy? {
        let info = ProcessInfo.processInfo
        let thermal: MediaThermalPressure
        switch info.thermalState {
        case .nominal: thermal = .nominal
        case .fair: thermal = .fair
        case .serious: thermal = .serious
        case .critical: thermal = .critical
        @unknown default: thermal = .serious
        }
        let free = try? FileManager.default.temporaryDirectory
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
        guard let conditions = MediaDeviceConditions(heroSlotPointWidth: device.heroPointWidth,
            thumbnailSlotPointWidth: device.thumbnailPointWidth, screenScale: device.scale,
            network: NetworkPathObserver.shared.current, measuredBytesPerSecond: measuredBytesPerSecond,
            // Supplied, never assumed: one image may cost the host as much time as the runway already tolerates for
            // one feed request, and that tolerance is measured (§5.3/PD-6, F06-G). The byte budget follows from it
            // and the measured rate inside `MediaPolicy.byteBudget`.
            waitBudgetSeconds: waitBudgetSeconds, freeStorageBytes: free, lowPowerMode: info.isLowPowerModeEnabled, thermal: thermal),
            // Decode-bomb and stream safety ceilings (v1 hardened: 12 MB, 12k px side, 50 MP).
            let ceilings = MediaSafetyCeilings(maximumDownloadBytes: 12_000_000, maximumPixelSide: 12_000,
                maximumPixelCount: 50_000_000) else { return nil }
        return MediaPolicy(conditions: conditions, ceilings: ceilings)
    }
}

/// Current network path for media decisions (constrained / expensive / unavailable).
final class NetworkPathObserver: @unchecked Sendable {
    static let shared = NetworkPathObserver()
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var path: MediaNetworkPath = .unconstrained

    private init() {
        monitor.pathUpdateHandler = { [weak self] update in
            let value: MediaNetworkPath
            if update.status != .satisfied { value = .unavailable }
            else if update.isConstrained { value = .constrained }
            else if update.isExpensive { value = .expensive }
            else { value = .unconstrained }
            self?.lock.lock(); self?.path = value; self?.lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "feedmine.network-path"))
    }

    var current: MediaNetworkPath {
        lock.lock(); defer { lock.unlock() }
        return path
    }
}

/// Delivers cold-bootstrap evidence to the main-actor association after it is constructed. The delivery is
/// `async` because one of its cases — `.published` — *is* a publication fact, and the window that follows it is the
/// association's own (`growAdmittedWindowIfPublished`): the fact is acted on where it arrives, not scheduled.
@MainActor
final class EvidenceRelay {
    var receive: ((ColdFeedEvidence) async -> Void)?
    func deliver(_ evidence: ColdFeedEvidence) async { await receive?(evidence) }
}

/// Delivers a concluded publication to the main-actor association after it is constructed. The driver executes the
/// slice, so the receipt exists inside its drain; the association owns the admitted list, so the fact crosses to it
/// here. This is the channel the R6-E decision names — `PublicationOutcome.published` and its receipt, the type of
/// fact the publication side already has — and never a trace event, a timer or a queue.
@MainActor
final class PublicationRelay {
    var receive: ((PublicationReceipt) async -> Void)?
    func deliver(_ receipt: PublicationReceipt) async { await receive?(receipt) }
}

/// A value both sides of an `await` boundary need: written by whoever learns it (a discovery page, a measured
/// tolerance) and read **at the moment it is used**, never captured once by a closure that outlives it. A reference
/// type on purpose, a lock on purpose — both sides run off the caller's thread, and `update` is the atomic
/// read-modify-write those cases need.
final class LiveValue<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    var current: Value { lock.lock(); defer { lock.unlock() }; return value }
    func update(_ transform: (inout Value) -> Void) { lock.lock(); defer { lock.unlock() }; transform(&value) }
    func set(_ new: Value) { update { $0 = new } }
}

/// B/§3: the media prefetcher is built before its driver, so its readiness callback must not capture the
/// association. It points here; once every stored property is set, the association installs the one closure this
/// relay will call — the same local-supply notification a committed acquisition gives the runway. Nothing in it
/// decides anything, and it holds no state beyond that closure.
final class MediaReadinessRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var receive: (@Sendable () async -> Void)?
    func install(_ receive: @escaping @Sendable () async -> Void) { lock.withLock { self.receive = receive } }
    func deliver() async {
        let receive = lock.withLock { self.receive }
        await receive?()
    }
}
