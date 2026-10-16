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

@MainActor
@Observable
final class AppComposition {
    private(set) var association: FeedAssociation?
    /// The product-facing message the reader sees when the composition cannot start.
    private(set) var startupFailure: String?
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
    @ObservationIgnored private var catalogueSnapshot: CatalogSnapshot?
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
        if let association, !association.discovery.isEmpty { return true }
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
        association.onSearch = { [weak self] term in self?.submitSearch(term) }
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
    func filterLanguages() -> [CatalogLanguageGroup] {
        guard let association else { return [] }
        let coordinator = SourceManagementCoordinator(catalogURL: catalogueURL, database: association.database)
        return (try? coordinator.languageGroups()) ?? []
    }

    /// T8: the box a new bookmark lands in. Nil in the preferences means the default box, which is what a
    /// library that was never asked for a preference has.
    var preferredBookmarkListID: String {
        (try? preferences?.load())??.preferredBookmarkListID ?? ReaderBookmarkList.defaultID
    }

    /// T5: one search submission is a context change, exactly like the sources menu.
    private func submitSearch(_ term: String) {
        guard let context = SearchContext(query: term) else { return }
        Task { try? await selectContext(.search(context)) }
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
        transportConfiguration: URLSessionConfiguration? = nil) {
        let support = RuntimeDatabaseLocation.applicationSupport(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]).directory
        #if DEBUG
        let namespace = ProcessInfo.processInfo.environment["FEEDMINE_RUNTIME_NAMESPACE"].flatMap(UUID.init(uuidString:))
        self.directory = directory ?? namespace.map { support.appendingPathComponent($0.uuidString) } ?? support
        #else
        self.directory = directory ?? support
        #endif
        self.selectedFeeds = feeds
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
        // activates what exists and lets everything that is not the reader's window continue behind it.
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
        let current: FeedAssociation
        if let warmed = association {
            // The warm launch already built this association **and** installed the reader's own window into it,
            // before this launch drew anything. What is left is everything that is not that window: activation,
            // acquisition, media, the discovery walk — the backend, behind the feed the reader already has.
            current = warmed
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

    func foreground() async {
        guard let association else { return }
        await association.foreground()
        await syncCatalogueIfDue()
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

    func background() async {
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

    /// T6: an explicit filter transition. The selection is persisted first, then the association is rebuilt
    /// around the new identity, so A→B→A finds A's own checkpoint and no old callback can install into B.
    func applyFilter(_ filter: ReaderFilter, preset: ReaderPresetID) async throws {
        let key = ContextKey(request: currentContextKey.request, preset: preset, filter: filter,
            searchScope: currentContextKey.searchScope)
        guard key != currentContextKey else { return }
        currentContextKey = key
        _ = try preferences?.setContext(key)
        // A new overlay selection starts the window again; a selection without overlay criteria has none.
        _ = try preferences?.setFilterExpiry(filterExpiry(renewing: filter, at: Date()))
        try await replaceSession()
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
        if let retired = association {
            _ = try await retired.session.checkpointCurrentPosition(at: Date())
            await retired.close()
        }
        association = nil
        currentContextKey = key
        _ = try preferences.setContext(key)
        let next = try await association(contextKey: key)
        association = next
        startupFailure = nil
        try await next.launch()
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
        return BookmarkBoxesStore(backend: ReaderBookmarkBoxesBackend(database: database))
    }

    /// T8: the collections surface's store, over the same library.
    func makeCollectionsStore() -> CollectionsStore? {
        guard let database = libraryDatabase() else { return nil }
        return CollectionsStore(backend: ReaderCollectionsBackend(database: database))
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
    func completeOnboarding() {
        guard let preferences, let current = try? preferences.load() else { return }
        var settings = current.settings
        settings.hasSeenOnboarding = true
        guard (try? preferences.setSettings(settings)) != nil else { return }
        noteReaderSettingsWritten(settings)
    }

    /// F02's first run: the answers it collects (languages and places) become the reader's **discovery profile** —
    /// a preference, never a context identity — and the feed they enter is built from them. Nothing is created to
    /// be activated and nothing has to be named: the reader enters the feed, and the subjects are answered inside
    /// it. The session is rebuilt so the answers take effect now, not on the next launch; because the identity is
    /// unchanged, that rebuild **restores** the reader's position rather than resetting it.
    func completeFirstRun(discovery recipe: FeedRecipeDefinition) async {
        if let preferences, let current = try? preferences.load() {
            var settings = current.settings
            settings.discoveryProfile = recipe
            settings.hasSeenOnboarding = true
            if (try? preferences.setSettings(settings)) != nil { noteReaderSettingsWritten(settings) }
        }
        try? await replaceSession()
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
        libraryDatabase().map { ReaderSettingsStore(backend: ReaderSettingsBackendAdapter(database: $0)) }
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
        let profile = discoveryProfile(for: applied(initial.key))
        let requestedFingerprint = catalogueSnapshot?.fingerprint
        let discovered = await discoveryFeeds(profile: profile)
        let snapshot = catalogueSnapshot
        // Actor reentrancy can allow an activation *between* returning an old cached pool and
        // resuming this constructor. Do not combine that pool with the replacement snapshot.
        if requestedFingerprint != snapshot?.fingerprint {
            return try await association(contextKey: contextKey)
        }
        let session = try sessionState(for: contextKey)
        if session.key != contextKey {
            currentContextKey = session.key
            _ = try preferences?.setContext(session.key)
        }
        return try makeAssociation(contextKey: session.key, discovered: discovered, profile: profile,
            warmLaunch: false)
    }

    /// The one place an association is built. The **asynchronous** launch and the **warm** launch hand the same
    /// inputs to the same constructor, so there is one shape of session and not two: what differs is only when they
    /// can run (the warm one cannot `await`, because the reader's own window has to exist before the first frame).
    private func makeAssociation(contextKey: ContextKey, discovered: [TrustedFeed],
        profile: ReaderDiscoveryProfile, warmLaunch: Bool) throws -> FeedAssociation {
        let session = try sessionState(for: contextKey)
        if session.key != contextKey {
            currentContextKey = session.key
            _ = try preferences?.setContext(session.key)
        }
        let key = applied(session.key)
        let (scoring, version) = scoring(for: key)
        return connecting(try FeedAssociation(directory: directory, feeds: session.feeds,
            discovery: discovered,
            configuration: transportConfiguration, trace: trace, database: libraryDatabase(),
            discoveryTraversal: discoveryTraversal(for: key, profile: profile, snapshot: catalogueSnapshot),
            contextKey: key, selectionVersion: selectionVersion, scoring: scoring, scoringVersion: version,
            catalogueURL: catalogueSnapshot?.catalogueURL, editorialExposure: editorialExposure,
            discoveryProfile: profile, warmLaunch: warmLaunch))
    }

    /// The association a **warm** launch starts from — the same session `launch()` would build, with the two
    /// differences a first frame demands: it is built **synchronously**, and the pool its profile names is read on
    /// this thread rather than handed to a detached pass. At this moment the main actor is not drawing yet, and the
    /// reader's own window must not wait behind a hop.
    ///
    /// Only a launch the previous interaction made durable takes this path (see the guard in `init`): a launch with
    /// nothing to show keeps the asynchronous path and the preparation surface the doctrine gives it, because
    /// blocking a first run's main actor on a pool read would trade a visible wait for an invisible one.
    private func warmAssociation() throws -> FeedAssociation {
        let initial = try sessionState(for: currentContextKey)
        let profile = discoveryProfile(for: applied(initial.key))
        let discovered = try warmDiscoveryFeeds(profile: profile)
        return try makeAssociation(contextKey: initial.key, discovered: discovered, profile: profile,
            warmLaunch: true)
    }

    /// The pool a profile names, read on the thread that asks — one computation behind both readers of it
    /// (`discoveryFeeds` hands the same call to a detached pass), and the same caches are filled either way, so a
    /// profile never costs the catalogue two reads.
    private func warmDiscoveryFeeds(profile: ReaderDiscoveryProfile) throws -> [TrustedFeed] {
        guard !profile.isEmpty, let snapshot = catalogueSnapshot else { return [] }
        let cacheKey = DiscoveryCacheKey(profile: profile, fingerprint: snapshot.fingerprint)
        if let cached = discoveryCache[cacheKey] { return cached }
        let (entries, subjects) = Self.discoveryPool(profile: profile, catalogueURL: snapshot.catalogueURL)
        let feeds = entries.map(Self.trustedFeed(from:))
        discoveryCache[cacheKey] = feeds
        discoverySubjects = subjects
        return feeds
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

    /// The product's own promise: a reader who named interests gets sources they never named. The pool comes from
    /// the bundled catalogue's labels for the context's profile, is cached per profile (a query, not a per-render
    /// cost), and never changes the context's identity — the reader's checkpoints and position stay where they
    /// were, and the feed simply has more of the open internet to draw from.
    ///
    /// **It does not run on the main actor.** The shipped catalogue is 118 MB and a first-run profile reads
    /// thousands of keys; measured against that file, one pool costs 2,5–2,8 s, which on the main actor is a
    /// frozen first run (the acceptance driver observed the app's main thread busy for 30 s).
    private func discoveryFeeds(profile: ReaderDiscoveryProfile) async -> [TrustedFeed] {
        guard !profile.isEmpty, let snapshot = catalogueSnapshot else { return [] }
        let cacheKey = DiscoveryCacheKey(profile: profile, fingerprint: snapshot.fingerprint)
        if let cached = discoveryCache[cacheKey] { return cached }
        let url = snapshot.catalogueURL
        // One detached pass: the pool query **and** the subject names. Opening the shipped 118 MB catalogue once
        // per node key — which is what asking the catalogue for a name does — put seconds of work on the main
        // actor, right where the reader is waiting for their feed.
        let (entries, subjects) = await Task.detached(priority: .userInitiated) { () -> ([LegacyCatalogEntry],
            [SourceID: AppComposition.EditorialSubject]) in
            Self.discoveryPool(profile: profile, catalogueURL: url)
        }.value
        let feeds = entries.map(Self.trustedFeed(from:))
        discoveryCache[cacheKey] = feeds
        // Work prepared for revision 5 can finish after activation of 6. Keep its keyed result for any
        // context still using 5, but do not let its subjects or feeds become the current authority.
        guard catalogueSnapshot?.fingerprint == snapshot.fingerprint else {
            return await discoveryFeeds(profile: profile)
        }
        discoverySubjects = subjects
        return feeds
    }

    /// The interests a context states, in the catalogue's vocabulary. **The reader's own answers come first**
    /// (F02): the discovery preferences page and the invitations answered inside the feed write them into the
    /// settings, which are behaviour — never a context's identity, so a new answer cannot move the reader out of
    /// what they were reading. A curated feed then states its recipe, and anything else its own lens criteria.
    func discoveryProfile(for key: ContextKey) -> ReaderDiscoveryProfile {
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

    /// A recipe in the catalogue's vocabulary: `topic:<node>` keys, `more` as interest and `less` as exclusion.
    static func discoveryProfile(from recipe: FeedRecipeDefinition) -> ReaderDiscoveryProfile {
        var interested: Set<String> = [], excluded: Set<String> = []
        for (key, level) in recipe.topicPreferences {
            let node = key.hasPrefix("topic:") ? String(key.dropFirst("topic:".count)) : key
            guard !node.isEmpty else { continue }
            if level == .more { interested.insert(node) } else { excluded.insert(node) }
        }
        for (key, level) in recipe.editorialPreferences where level == .less {
            let node = key.hasPrefix("topic:") ? String(key.dropFirst("topic:".count)) : key
            guard !node.isEmpty else { continue }
            excluded.insert(node)
        }
        return ReaderDiscoveryProfile(languages: Set(recipe.languages), topicNodeKeys: interested,
            excludedTopicNodeKeys: excluded)
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
            noteReaderSettingsWritten(settings)
        } catch {
            trace?.record("answer_failed", ["subject": node, "stage": "persist"])
            return false
        }
        trace?.record("answer_applied", ["subject": node, "level": level == .more ? "more" : (level == .less ? "less" : "neutral")])
        // The line is made durable at once: a run that ends before the next viewport event must still be able to
        // show that the reader's answer was applied (architect, 2026-10-11).
        trace?.flush()
        // A construction already in flight must read the answer it now holds. The rebuild loop re-reads the
        // profile, so an answer that lands mid-construction asks for one more pass instead of being built away
        // (Codex's finding 3). Nothing is rebuilt when nothing is being built — which is the case this change
        // exists for: rebuilding the session moved the reader.
        if replacingSession { pendingRebuild = true }
        return true
    }


    /// The facts the feed's own invitation depends on, recorded once per window change — off the render path.
    /// `traversed` is what round 10 needed and nothing measured: the cards the reader **really** passed, which is
    /// the budget's own unit — a rendered window is not a read window.
    func recordWindowFacts(cards: Int, resolvedSources: Int, withSubject: Int, tipsHidden: Bool,
        traversed: Int, offersShown: Int) {
        trace?.record("window", ["cards": String(cards), "resolved_sources": String(resolvedSources),
            "with_subject": String(withSubject), "tips_hidden": String(tipsHidden),
            "known_subjects": String(discoverySubjects.count),
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

    /// A write just happened: the cache now holds exactly what the database holds, without reading it back.
    private func noteReaderSettingsWritten(_ settings: ReaderSettings) {
        readerSettingsSnapshot = settings
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
    @ObservationIgnored private var discoverySubjects: [SourceID: EditorialSubject] = [:]

    /// The subject a card may be asked about, and only when the invitation would be true (Codex's finding 2):
    /// a source the reader **chose** is not discovery, and a subject found under an earlier profile does not belong
    /// to the association being read. Explicit choice takes precedence over what the app went looking for.
    func editorialSubject(for sourceID: SourceID, in association: FeedAssociation) -> EditorialSubject? {
        guard !association.feeds.contains(where: { $0.sourceID == sourceID }) else { return nil }
        guard association.discovery.contains(where: { $0.sourceID == sourceID }) else { return nil }
        return discoverySubjects[sourceID]
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
        noteReaderSettingsWritten(settings)
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

    /// The pool a profile names, over the installed catalogue, with the subjects a card is attributed with — one
    /// computation behind both of its readers: `discoveryFeeds` (the launch that has a loading screen to show, off
    /// the main actor) and `warmDiscoveryFeeds` (a warm launch, which has to have the reader's window before its
    /// first frame and therefore cannot await).
    nonisolated static func discoveryPool(profile: ReaderDiscoveryProfile, catalogueURL: URL)
        -> (entries: [LegacyCatalogEntry], subjects: [SourceID: EditorialSubject]) {
        let pool = (try? ReaderDiscoveryBuilder(catalogURL: catalogueURL).pool(for: profile,
            limit: discoverySourceLimit))?.entries ?? []
        return (pool, subjects(in: pool, catalogURL: catalogueURL))
    }

    static func trustedFeed(from entry: LegacyCatalogEntry) -> TrustedFeed {
        TrustedFeed(targetID: entry.targetID, sourceID: entry.source.id, bindingID: entry.bindingID,
            principal: entry.principal, endpoint: entry.endpoint, displayName: entry.source.displayName)
    }

    /// Profiles already resolved this launch: the catalogue query is done once per profile, and a context
    /// transition that asks for the same profile is free.
    struct DiscoveryCacheKey: Hashable {
        let profile: ReaderDiscoveryProfile
        let fingerprint: String
    }
    @ObservationIgnored private var discoveryCache: [DiscoveryCacheKey: [TrustedFeed]] = [:]

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
            association = nil
            if let retired {
                _ = try await retired.session.checkpointCurrentPosition(at: Date())
                await retired.close()
            }
            let next = try await association(contextKey: currentContextKey)
            association = next
            startupFailure = nil
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
    @ObservationIgnored private let tidy: MediaTidy
    @ObservationIgnored private let mediaWaitBudget: LiveValue<Double>
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
    @ObservationIgnored private let maintainTail: @Sendable (PublicationStore.HiddenTailLease) async throws -> PublicationStore.TailSuccessionResult
    private let cold: ColdFeedBootstrap
    @ObservationIgnored private let relay: EvidenceRelay
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
        guard let self else { return }
        Task { await self.viewport(observation, activity: activity) }
    }, onRenderedViewport: { [weak self] evidence, activity in
        guard let self, self.active else { return }
        Task { await self.viewport(evidence.observation, activity: activity, evidence: evidence) }
    }, availableActions: Self.readerCardActions, onAction: { [weak self] event in
        guard let self, self.active else { return }
        switch event.action {
        case .open: self.open(event.cardID)
        case .save: self.toggleBookmark(event.cardID)
        default: self.perform(event.action, cardID: event.cardID)
        }
    }, availableDestinations: Self.readerDestinations(for: contextKey),
        onSubmitSearch: { [weak self] term in self?.onSearch?(term) },
        onNavigate: { [weak self] destination in self?.onNavigate?(destination) },
        onPresentedPosition: { [weak self] anchor, atRest in
            guard let self, self.active else { return }
            Task { await self.notePresentedPosition(anchor, atRest: atRest) }
        })

    /// T9: the card actions this host executes. Resolution is the action coordinator's (the occurrence's own
    /// frozen target); what happens next — a browser, a clipboard, a share sheet — is here, and nowhere near a
    /// renderer.
    func perform(_ action: ReaderCardAction, cardID: PublicationCardID) {
        Task {
            // "View Source" is the source's own page, resolved here through the catalog: the coordinator refuses
            // it because it needs the mapping this host holds (the card's source id names one of these feeds).
            if action == .viewSource {
                guard let url = sourcePage(for: cardID) else {
                    store.showToast(text: String(localized: "Não foi possível abrir a fonte"),
                        systemImage: "exclamationmark.triangle")
                    return
                }
                present(url, cardID)
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
                        reportFailure(ReaderActionError.unusableReference(text))
                    }
                case .share(let payload):
                    onShare?(SharedLink(url: payload.url, subject: payload.subject))
                case .media:
                    // No card this pipeline publishes carries a playable target yet (PORT_LOG, T9): the surface
                    // states that instead of opening a player on nothing.
                    store.showToast(text: String(localized: "Mídia indisponível nesta compilação"),
                        systemImage: "speaker.slash")
                }
            } catch { reportFailure(error) }
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
            store.installBookmarks(try publication.bookmarkedCardIDs())
        } catch { reportFailure(error) }
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
    let discovery: [TrustedFeed]
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
        return ids
            .compactMap { id -> FeedSavedArticle? in
                guard let card = try? publication.card(id: id) else { return nil }
                let title = card.title ?? card.primaryText ?? ""
                guard !title.isEmpty else { return nil }
                return FeedSavedArticle(id: card.id, title: title, source: card.sourceDisplayName,
                    timestamp: card.timestampValue)
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

    static var resources: FeedRunwayDriverResources {
        .init(runway: .init(localWorkAllowed: true, examinedCandidateCapacity: 32,
            readyProbeBound: 32, readyProbeCeiling: 256, forwardAdvanceProbeBound: 256,
            // F01/§5.3: the reserve exists so the reader can walk into the window the session materialised, so the
            // bootstrap coverage **is** that window — derived here, not restated. `RunwayPolicy` uses it only while
            // consumption/replenishment facts are unknown (Codex's reserve review, 2026-10-10); once they are
            // measured it derives the target from the measured rate and p95, and this number stops applying.
            reserveCards: Self.forwardWindowCards)!,
            acquisition: .init(targetWorkCapacity: 2, batchCapacityPerNewExecution: 1,
                observationCapacityPerBatch: 32, byteCapacityPerBatch: 1_000_000)!)
    }

    init(directory: URL, feeds: [TrustedFeed], discovery: [TrustedFeed] = [], configuration: URLSessionConfiguration,
        trace: RunwayTrace? = nil, database sharedDatabase: RuntimeDatabase? = nil,
        discoveryTraversal: ReaderDiscoveryTraversal? = nil,
        contextKey: ContextKey = ContextKey(request: .main), selectionVersion: UInt64 = 2,
        scoring: ResolvedSelectionPolicy.ScoringBehavior = .equal, scoringVersion: UInt64 = 1,
        catalogueURL: URL?, editorialExposure: EditorialExposureLedger,
        discoveryProfile: ReaderDiscoveryProfile = .init(), warmLaunch: Bool = false) throws {
        self.trace = trace
        self.catalogueURL = catalogueURL
        self.editorialExposure = editorialExposure
        self.discoveryProfile = discoveryProfile
        // The host and its replacement sessions share one writer; retiring async work cannot
        // contend with a preference write through a second pool for the same file.
        let db = try sharedDatabase ?? RuntimeDatabase(location: .init(directory: directory))
        database = db
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
        let sequencingVersion: PolicyVersion
        switch scoring {
        case .equal: sequencingVersion = PolicyVersion(rawValue: 3)
        case .weighted(let weights): sequencingVersion = weights.isEmpty ? PolicyVersion(rawValue: 3) : PolicyVersion(rawValue: 4)
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
        let sequencing = Self.sequencingBehavior(for: revision.sequencingPolicyVersion)
        // What this session may read from: the reader's own selection **plus** the sources discovery found for
        // their profile. The reader's selection stays what it was — the sources screen and the context menu still
        // show exactly what they chose — while the feed is supplied by the open internet the catalogue describes.
        let supply = Self.supply(selection: feeds, discovery: discovery)
        self.discovery = discovery
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
            installation: CatalogInstallation(appDirectory: directory))
        self.acquisition = acquisition
        // H2: a feed that keeps failing cools down for a doubling window that starts at what one
        // failed attempt may already cost (the request timeout) and is capped by the resource
        // timeout. Targets run through a sliding window sized by this device's cores.
        let backoff = AcquisitionBackoffPolicy(baseSeconds: configuration.timeoutIntervalForRequest,
            ceilingSeconds: max(configuration.timeoutIntervalForRequest, configuration.timeoutIntervalForResource))
        let coordinator = acquisition.makeCoordinator(backoff: backoff,
            concurrentTargetLimit: max(2, ProcessInfo.processInfo.activeProcessorCount))
        self.coordinator = coordinator
        // PD-5/PD-6 media pipeline: one download owner, device-measured policy, slot-sized decoding.
        let assetDirectory = directory.appendingPathComponent("Media", isDirectory: true)
        let device = DeviceMediaConditions.currentOnMain()
        let readiness = MediaReadiness()
        let fetcher = MediaHTTPFetcher(session: transport)
        // F06-G/PD-6: one derived tolerance feeds both the preparation window and the byte budget below. The media
        // layer used to be handed a fixed 5 s here while the window was computed elsewhere — two numbers for one
        // fact. The box is what makes them one: the window writes the measured value, and every later policy read
        // (which is how `downloadByteBudget` = measured rate × wait is computed) sees it.
        let mediaWaitBudget = LiveValue(Self.mediaWaitBootstrapSeconds)
        self.mediaWaitBudget = mediaWaitBudget
        let media = MediaPrefetcher(database: db, assetDirectory: assetDirectory, readiness: readiness,
            concurrentDownloadLimit: max(2, ProcessInfo.processInfo.activeProcessorCount / 2),
            fetch: { try await fetcher.fetch($0, byteCeiling: $1) },
            conditions: { rate in DeviceMediaConditions.policy(device: device, measuredBytesPerSecond: rate,
                assetDirectory: assetDirectory, waitBudgetSeconds: mediaWaitBudget.current) })
        self.media = media
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
        let names = LiveValue(Dictionary(uniqueKeysWithValues: supply.map { ($0.sourceID, $0.displayName) }))
        // T9: the playable payload a card's tap should use, read from the candidate the feed declared.
        let playback: @Sendable (OriginRevisionID) -> URL? = { revision in
            // `try?` flattens the store's own optional: a nil here means "no playable payload declared".
            guard let playable = try? ContentStore(database: db).playbackCandidate(originRevisionID: revision) else {
                return nil
            }
            return playable.remoteURL
        }
        // The trace is a value: the preparation closure is `@Sendable` and may run off the main actor.
        let prepare: @Sendable (SelectionResult) -> LocalPreparedPublication = {
            Self.prepare($0, readiness: readiness, names: names.current, trace: trace, playback: playback)
        }
        // The replenishment port. The three points live in the library modules, which must not know the host's
        // trace: one adapter is built here, beside the trace itself, and handed to the owners of the points. With
        // no trace it is `nil`, and the modules behave exactly as they did before the port existed.
        let replenishment: ReplenishmentTrace? = trace.map { sink in
            ReplenishmentTrace { event, fields in sink.record(event, fields) }
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
            return try await HiddenTailMaintenance(database: db).run(plan: plan, policy: policy, lease: lease, examinedCapacity: 256,
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
        driver = try FeedRunwayDriver(session: session, runway: runway, plan: plan, policy: policy,
            acquisition: acquisition, coordinator: coordinator,
            monotonicNow: { .init(seconds: ProcessInfo.processInfo.systemUptime)! },
            makeSegmentIdentity: { .init(segmentID: FeedSegmentID(), segmentSeed: 1, segmentCreatedAt: Date())! },
            prepare: prepare,
            selectedSourceCoverage: .init(selectedSourceCoverageFor: plan.context.key, editorialRevisionID: plan.revision.id),
            readiness: readiness, onDiscoveryPage: onDiscoveryPage, makeMediaOpportunity: makeMediaOpportunity,
            trace: replenishment)
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
            readiness: readiness, onDiscoveryPage: onDiscoveryPage, makeMediaOpportunity: makeMediaOpportunity)
        targetNames = Dictionary(uniqueKeysWithValues: feeds.map { ($0.targetID, $0.displayName) })
        let provider = CandidateProvider(contentStore: ContentStore(database: db))
        admittedHeadlines = { (try? provider.candidates(for: plan, after: nil, examinedCapacity: 12))?.candidates.compactMap(\.headline) ?? [] }
        // The reader's window reaches the screen **here**, before this launch has drawn anything: it is the whole
        // point of a warm start. The handoff and the store keep their own validation, and a later `.initial`
        // admission returns this same projection, so installing it again is a no-op by the store's own rule.
        if let warm {
            try install(FeedPresentationHandoff.receive(snapshot: warm.snapshot, into: store.state))
        }
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

    /// PD-5: each card is drawn with a prepared image or designed text-only — never "missing" one.
    /// Attribution (source id/name) is frozen into the card, which also feeds PD-4 adjacency.
    nonisolated private static func prepare(_ selection: SelectionResult, readiness: MediaReadiness,
        names: [SourceID: String], trace: RunwayTrace? = nil,
        playback: (OriginRevisionID) -> URL? = { _ in nil }) -> LocalPreparedPublication {
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
        return .init(inputs: selection.orderedCandidates.map { candidate in
            let source = candidate.sourceIDs.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }.first { names[$0] != nil }
                ?? candidate.sourceIDs.first
            return .init(origin: .init(originRecordID: candidate.originRecordID, originRevisionID: candidate.originRevisionID,
                sourceID: source, providerID: candidate.providerID, sourceDisplayName: source.flatMap { names[$0] },
                providerDisplayName: nil),
                contentEntityID: nil, contentClusterID: nil,
                // F10/T9: V1's precedence, stated once — an episode plays from the enclosure its feed
                // declared, and every other card opens its article.
                primaryAction: playback(candidate.originRevisionID).map { .mediaPlayback($0) }
                    ?? candidate.primaryLink.map { .externalURL($0) },
                presentation: snapshot[candidate.originRevisionID] ?? .textOnly)
        }, cardIDs: selection.orderedCandidates.map { _ in PublicationCardID() })
    }

    /// The readiness of one candidate, as a fact rather than a feeling: prepared with an image, prepared as text
    /// by decision, or **not ready at all** — the last one is the pending case F06 exists for.
    nonisolated static func readinessLabel(_ readiness: MediaReadiness,
        for revision: OriginRevisionID) -> String {
        if readiness.prepared(revision) != nil { return "prepared" }
        return readiness.isSettled(revision) ? "textOnly" : "pending"
    }

    /// The window the bookmark set was read for. A bookmark belongs to the reader's own cards, and the reader's own
    /// toggle installs the set directly; a scroll advance that moved only the anchor has not changed them. Reading
    /// the database per advance is a synchronous SQLite read on the main actor — exactly what V1's own rule keeps
    /// off the scroll path (`docs/release/review-feed-responsiveness-build-5.md`: nothing per tick that memory can
    /// already answer).
    @ObservationIgnored private var bookmarksReadFor: (edition: FeedEditionID?, context: ContextKey?,
        ids: [PublicationCardID]) = (nil, nil, [])

    /// Mede o que o dono sente e a suíte não vê (decisão de 2026-10-14). O trace da corrida passa a ter, por
    /// segundo, quantos quadros passaram do orçamento e qual foi o pior — o **hitch ratio** que julga cada mudança
    /// de fluidez, em vez de mais uma rodada de testes verdes.
    @ObservationIgnored private lazy var frameMeter = FeedFrameMeter { [weak self] event, fields in
        self?.trace?.record(event, fields)
    }

    func install(_ received: FeedPresentationState) throws {
        FeedFlowCounters.installAttempts += 1
        guard active else { throw FeedPresentationStateError.projectionSequenceMismatch }
        do { try store.install(received); FeedFlowCounters.installAccepts += 1 }
        catch { FeedFlowCounters.installRejects += 1; throw error }
        // O feed está em tela: a partir daqui o intervalo entre quadros é medido e escrito no trace.
        frameMeter.start()
        let installed = store.state.presentation
        let window = (edition: installed?.editionID, context: installed?.contextKey,
            ids: installed?.window.items.map(\.id) ?? [])
        if window != bookmarksReadFor {
            bookmarksReadFor = window
            store.installBookmarks(try PublicationStore(database: database).bookmarkedCardIDs())
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

    /// F05/R4: the runtime — never a reader gesture — extends the admitted window with cards the local
    /// store already published. The anchor, the reading position and every already-admitted card are
    /// preserved; a window with nothing new installs nothing. The evidence callback is synchronous, so
    /// the actor call is scheduled rather than awaited.
    @ObservationIgnored private var growthTask: Task<Void, Never>?
    /// Remaining bounded follow-up attempts after a fresh presentation (R6).
    @ObservationIgnored private var growthFollowUp = 0

    private func schedulePublishedGrowth() {
        growthTask?.cancel()
        growthTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            await self?.growAdmittedWindowIfPublished()
        }
    }

    /// R6: publications arrive in **bursts**, and a burst that lands after the install that followed it would
    /// otherwise never be materialised — measured: the shipped catalogue published 22 cards (segments 1+1+20)
    /// while the window kept the first one, because nothing triggered a later read. Each attempt is a fact (it
    /// asks the session for already-published cards beyond the tail) and the follow-up is bounded and cheap, so
    /// a quiet reserve costs nothing and a burst converges.
    private static let growthFollowUpAttempts = 8
    private static let growthFollowUpSeconds: Double = 0.75

    private func startGrowthFollowUp() {
        growthFollowUp = Self.growthFollowUpAttempts
        schedulePublishedGrowth()
    }

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
            guard growthFollowUp > 0 else { return }
            growthFollowUp -= 1
            growthTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.growthFollowUpSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.growAdmittedWindowIfPublished()
            }
        } catch { reportFailure(error) }
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
        retryTask?.cancel()
        retryTask = nil
        await foreground()
    }

    func launch() async throws {
        guard active, !launching else { return }
        launching = true
        defer { launching = false }
        let restored = try await session.admitPresentation(.initial(bounds))
        if let restored {
            try install(FeedPresentationHandoff.receive(snapshot: restored, into: store.state))
            Self.log("local restore before HTTP")
        } else {
            // PD-3: show real evidence of content arriving while the first Edition is prepared.
            let started = PreparationProgress(startedAt: ProcessInfo.processInfo.systemUptime)
            preparation = started
            try install(store.state.reporting(.preparing(started)))
            relay.receive = { [weak self] in self?.receive($0) }
            defer { relay.receive = nil; preparation = nil }
            Self.log("cold bootstrap started")
            let now = Date()
            let outcome = try await cold.run(identity: .init(editionID: FeedEditionID(), publicationSchemaVersion: .init(rawValue: 1),
                selectionSeed: 1, editionCreatedAt: now, segmentID: FeedSegmentID(), segmentSeed: 1,
                segmentCreatedAt: now, anchorPlacement: .top, checkpointedAt: now)!,
                resources: .init(localExaminedCapacity: 32, acquisition: Self.resources.acquisition)!,
                backwardCapacity: 8, forwardCapacity: 16, keepsAdmittedHead: true)
            try install(FeedPresentationHandoff.receive(coldOutcome: outcome, into: store.state))
            Self.log("cold bootstrap settled")
            if case .published = outcome {
                // R6: the driver's activation below can await media/acquisition for a long time on the shipped
                // catalogue (measured: minutes, while the reserve already held 22 published cards). The window
                // must fill from the publication fact, not from the end of that await.
                startGrowthFollowUp()
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
        let snapshot = try await driver.activateCurrentPresentation(resources: Self.resources)
        try install(FeedPresentationHandoff.receive(snapshot: snapshot, into: store.state))
        try await installSettledEligibleOffer()
        // R5: growth belongs to a *fresh* presentation. A reopen shows exactly what the reader left (S5);
        // the reader's own window is extended later by the opportunities they trigger.
        if restored == nil { startGrowthFollowUp() }
        await scheduleLocalRetryIfNeeded()
    }

    /// Review M7: a stationary reader produces no new observation, so a failed local slice would
    /// otherwise never be retried. One opportunity is scheduled at the controller's eligibility time.
    @ObservationIgnored private var retryTask: Task<Void, Never>?
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
    private func receive(_ evidence: ColdFeedEvidence) {
        guard active, var progress = preparation else { return }
        let now = ProcessInfo.processInfo.systemUptime
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
                // R7: a source that brought supply *is* the publication-completed event — the burst may land
                // after any timed follow-up has finished, so this restarts the bounded chain (it does not
                // cancel it, which is what the first version got wrong).
                startGrowthFollowUp()
            }
        case .preparingMedia:
            break
        case .published(let snapshot):
            progress = progress.applying(.prepared(cards: snapshot.window.items.count), at: now)
            // F06: show the first Edition now; slower feeds keep answering behind the badge.
            do {
                try install(FeedPresentationHandoff.receive(snapshot: snapshot, into: store.state))
                startGrowthFollowUp()
            }
            catch { Self.log("early publication rejected") }
        }
        preparation = progress
        do { try install(store.state.reporting(.preparing(progress))) } catch { Self.log("preparation update rejected") }
    }

    func viewport(_ observation: ViewportObservation, activity: RunwayActivity,
        evidence: RenderedViewportEvidence? = nil) async {
        do {
            guard active else { throw FeedPresentationStateError.projectionSequenceMismatch }
            if let evidence {
                guard let current = store.state.presentation, evidence.belongs(to: current) else { return }
            }
            // F02's budget counts **this** and nothing else: the capture's own proof of the card the reader is
            // at. It is recorded before the handoff, because the reader's exposure happened whether or not the
            // publication side accepted the opportunity.
            if evidence?.isPositionReconciliation != true {
                editorialExposure.expose(observation.anchor.cardID)
                #if DEBUG
                viewportReceived += 1
                #endif
            }
            if evidence?.isPositionReconciliation != true {
                Self.log("viewport forwarded activity=\(activity) anchor=\(observation.anchor.cardID)")
                trace?.record("advance", ["activity": String(describing: activity),
                    "anchor": observation.anchor.cardID.rawValue.uuidString])
                Self.log("viewport opportunity sent to driver")
            }
            let received = try await FeedPresentationHandoff.submitViewport(observation, activity: activity,
                resources: Self.resources, driver: driver, into: store.state, evidence: evidence,
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
            // O fim é decidido **antes** de a janela crescer: se a admissão trouxe cards, o crescimento retrata o
            // fim na mesma oportunidade, em vez de o fim ser reinstalado por cima da retratação (revisão,
            // 2026-10-14).
            try await installSettledEligibleOffer()
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
    }

    func foreground() async {
        visible = true
        do {
            if let edition = store.state.presentation?.editionID {
                try PublicationStore(database: database).setVisibility(editionID: edition, visible: true)
            }
            guard active, !launching else { return }
            if await session.currentPresentation() == nil {
                // Recovery without replacing the association; a presentation that already exists is
                // never extended here — returning to the app shows exactly what the reader left.
                if let restored = try await session.admitPresentation(.restore(bounds)) {
                    try install(FeedPresentationHandoff.receive(snapshot: restored, into: store.state))
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
            let snapshot = try await driver.activateCurrentPresentation(resources: Self.resources)
            try install(FeedPresentationHandoff.receive(snapshot: snapshot, into: store.state))
            // O fim é decidido **antes** de a janela crescer: se a admissão trouxe cards, o crescimento retrata o
            // fim na mesma oportunidade, em vez de o fim ser reinstalado por cima da retratação (revisão,
            // 2026-10-14).
            try await installSettledEligibleOffer()
            await growAdmittedWindowIfPublished()
            await scheduleLocalRetryIfNeeded()
        } catch { reportFailure(error); await scheduleLocalRetryIfNeeded() }
    }

    func background() async {
        visible = false
        retryTask?.cancel()
        retryTask = nil
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
        if let edition = store.state.presentation?.editionID {
            try? PublicationStore(database: database).setVisibility(editionID: edition, visible: true)
        }
        active = false
        visible = false
        retryTask?.cancel()
        await driver.deactivate()
        transport.invalidateAndCancel()
    }

    func reportFailure(_ error: any Error) {
        if let rejection = error as? FeedPresentationStateError {
            Self.log("projection rejected \(rejection)")
            return // typed structural rejection is logged; never install an alternative result/work.
        }
        guard active else { return }
        Self.log("execution failure \(String(describing: error))")
        // PO/R3: a connection failure is stated as such — and only when the transport proved one.
        let work: FeedPresentationState.Work = Self.isConnectionFailure(error)
            ? .unreachable
            : .failed(message: "Falha ao atualizar o feed")
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
            // and the measured rate inside `MediaPolicy.downloadByteBudget`.
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

/// Delivers cold-bootstrap evidence to the main-actor association after it is constructed.
@MainActor
final class EvidenceRelay {
    var receive: ((ColdFeedEvidence) -> Void)?
    func deliver(_ evidence: ColdFeedEvidence) { receive?(evidence) }
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
