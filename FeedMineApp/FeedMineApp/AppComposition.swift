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

@MainActor
@Observable
final class AppComposition {
    private(set) var association: FeedAssociation?
    private(set) var startupFailure: String?
    private var replacingSession = false
    private let directory: URL
    private(set) var feeds: [TrustedFeed]
    @ObservationIgnored private var preferences: ReaderPreferencesStore?
    /// T6: the active identity — surface, preset, filter and search scope. The plain surface's key equals the
    /// pre-T6 identity, so nothing changes for a reader who never filters.
    private(set) var currentContextKey: ContextKey = ContextKey(request: .main)
    var currentContext: FeedContextRequest { currentContextKey.request }
    var currentFilter: ReaderFilter { currentContextKey.filter }

    /// T7: whether the reader's accepted selection has any sources at all. It is read from the persisted
    /// selection, never from the resolved feed list — an empty selection is a decision, and the reader is
    /// shown the surface that states it and offers the way back.
    var hasSelectedSources: Bool {
        !(preferences.flatMap { try? $0.load() }?.sourceKeys.isEmpty ?? true)
    }
    var currentPreset: ReaderPresetID { currentContextKey.preset }
    private var selectionVersion: UInt64 = 2
    private(set) var sourceOptions: [FeedSourceOption] = []
    @ObservationIgnored private var sourceSearchID = UUID()
    @ObservationIgnored private var sourceChoices: [SourceID: TrustedFeed] = [:]
    private let transportConfiguration: URLSessionConfiguration
    /// U2: set once by the app host; every association receives it so the reader stays in-app.
    var onExternalURL: ((URL) -> Void)?
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

    /// The languages the filter sheet offers, read from the shipped catalog through the T7 surface. The sheet
    /// shows declared codes with their counts and the undeclared bucket last; a missing asset yields none.
    func filterLanguages() -> [CatalogLanguageSummary] {
        guard let association else { return [] }
        let catalogURL = Bundle.main.url(forResource: "catalog", withExtension: "sqlite")
        let coordinator = SourceManagementCoordinator(catalogURL: catalogURL, database: association.database)
        return (try? coordinator.languages()) ?? []
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

    init(directory: URL? = nil, feeds: [TrustedFeed] = TrustedFeed.catalogOrDevelopment(limit: 64),
        transportConfiguration: URLSessionConfiguration? = nil) {
        let support = RuntimeDatabaseLocation.applicationSupport(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]).directory
        #if DEBUG
        let namespace = ProcessInfo.processInfo.environment["FEEDMINE_RUNTIME_NAMESPACE"].flatMap(UUID.init(uuidString:))
        self.directory = directory ?? namespace.map { support.appendingPathComponent($0.uuidString) } ?? support
        #else
        self.directory = directory ?? support
        #endif
        self.feeds = feeds
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
        #endif
        self.transportConfiguration = config
        if feeds.isEmpty { startupFailure = "Não foi possível carregar o catálogo local de fontes." }
        else {
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
                var resolved = try TrustedFeed.resolveAvailable(keys: saved.sourceKeys, fallback: feeds)
                // T7: a selection the reader emptied stays empty — V1 allowed zero sources and said so with its
                // own surface. The fallback repairs a selection whose sources vanished from the catalogue, which
                // is why it needs the saved selection to have had sources in the first place.
                if resolved.isEmpty, !saved.sourceKeys.isEmpty { resolved = feeds }
                if resolved.map(\.principal) != saved.sourceKeys { saved = try preferences.updateSources(resolved.map(\.principal)) }
                if case .source(let id) = saved.activeContext, !resolved.contains(where: { $0.sourceID == id }) {
                    saved = try preferences.setContext(.main)
                }
                self.feeds = resolved
                currentContextKey = saved.activeContextKey
                selectionVersion = saved.selectionVersion
            } catch { startupFailure = "Não foi possível carregar a seleção de fontes: \(error)" }
        }
    }

    func launch() async {
        guard !replacingSession, association == nil, startupFailure == nil else { return }
        let current: FeedAssociation
        do {
            current = try association(contextKey: currentContextKey)
        } catch {
            startupFailure = "Não foi possível abrir o feed local: \(String(describing: error))"
            return
        }
        association = current
        do {
            try await current.launch()
        } catch {
            // An old launch may settle after explicit replacement. Its error belongs to that association.
            guard association === current, current.active else { return }
            startupFailure = "Não foi possível abrir o feed local: \(String(describing: error))"
            current.reportFailure(error)
        }
    }

    func foreground() async {
        guard let association else { return }
        await association.foreground()
    }

    func background() async {
        guard let association else { return }
        await association.background()
    }

    func searchSources(_ query: String) async throws {
        let searchID = UUID()
        sourceSearchID = searchID
        var choices = feeds
        if let url = Bundle.main.url(forResource: "catalog", withExtension: "sqlite") {
            let records = try await Task.detached {
                try LegacyCatalogReader(catalogURL: url).matchingSources(query: query, limit: 50)
            }.value
            choices += records.compactMap { record in
                guard let entry = LegacyCatalogImport.entry(record) else { return nil }
                return TrustedFeed(targetID: entry.targetID, sourceID: entry.source.id, bindingID: entry.bindingID,
                    principal: entry.principal, endpoint: entry.endpoint, displayName: entry.source.displayName)
            }
        }
        guard searchID == sourceSearchID else { return }
        sourceChoices = Dictionary(choices.map { ($0.sourceID, $0) }, uniquingKeysWith: { first, _ in first })
        let selected = Set(feeds.map(\.sourceID))
        sourceOptions = sourceChoices.values.map { .init(id: $0.sourceID, name: $0.displayName, selected: selected.contains($0.sourceID)) }
            .sorted { left, right in left.selected != right.selected ? left.selected : left.name.localizedStandardCompare(right.name) == .orderedAscending }
    }

    func toggleSource(_ sourceID: SourceID) async throws {
        guard !replacingSession else { return }
        replacingSession = true
        defer { replacingSession = false }
        guard let choice = sourceChoices[sourceID], let preferences else { throw ReaderPreferencesError.invalidSelection }
        var next = feeds
        if let index = next.firstIndex(where: { $0.sourceID == sourceID }) { next.remove(at: index) }
        else { next.append(choice) }
        guard !next.isEmpty else { throw ReaderPreferencesError.invalidSelection }
        if let retired = association {
            _ = try await retired.session.checkpointCurrentPosition(at: Date())
            await retired.close()
        }
        association = nil
        let saved = try preferences.updateSources(next.map(\.principal))
        feeds = next
        selectionVersion = saved.selectionVersion
        let request: FeedContextRequest = next.count == 1 ? .source(next[0].sourceID) : .main
        currentContextKey = ContextKey(request: request, preset: currentContextKey.preset,
            filter: currentContextKey.filter)
        _ = try preferences.setContext(currentContextKey)
        let nextAssociation = try association(contextKey: currentContextKey)
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
        let next = try association(contextKey: currentContextKey)
        association = next
        startupFailure = nil
        try await next.launch()
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
        let next = try association(contextKey: key)
        association = next
        startupFailure = nil
        try await next.launch()
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

    /// Opens a collection as its own feed: a session over exactly its sources, with the collection as the
    /// preset of its identity. The reader's own selection is not touched — V1's collection feed behaved the
    /// same way, and a collection is a playlist, not a preference.
    func openCollectionFeed(id: String) async throws {
        guard let library = libraryCoordinator(), let preferences else { return }
        let keys = try library.sourceKeys(inCollection: id)
        let resolved = try TrustedFeed.resolveAvailable(keys: Array(keys), fallback: feeds)
        guard !resolved.isEmpty else { throw ReaderPreferencesError.invalidSelection }
        guard !replacingSession else { return }
        replacingSession = true
        defer { replacingSession = false }
        if let retired = association {
            _ = try await retired.session.checkpointCurrentPosition(at: Date())
            await retired.close()
        }
        association = nil
        // The selection is unchanged on disk; only this session's plan is over the collection's sources.
        let sessionFeeds = feeds
        feeds = resolved
        currentContextKey = ContextKey(request: .main, preset: .collection(id),
            filter: .unrestricted)
        _ = try preferences.setContext(currentContextKey)
        let next = try association(contextKey: currentContextKey, sessionFeeds: resolved)
        association = next
        startupFailure = nil
        try await next.launch()
        // Leaving the collection restores the reader's own selection, which is what the next transition reads.
        feeds = sessionFeeds
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
        _ = try? preferences.setSettings(settings)
    }

    /// What the Composer can offer, from the catalogue the app already reads: its languages, and its own
    /// sections as topics (their keys are the ones a source is placed under, which is what a recipe stores).
    func onboardingOptions() -> (languages: [OnboardingLanguage], topics: [OnboardingTopic]) {
        guard let catalogURL = Bundle.main.url(forResource: "catalog", withExtension: "sqlite"),
            let coordinator = Optional(SourceManagementCoordinator(catalogURL: catalogURL,
                database: libraryDatabase())) else { return ([], []) }
        let languages = ((try? coordinator.languages()) ?? [])
            .filter { !$0.isUndeclared }
            .prefix(12)
            .map { OnboardingLanguage(code: $0.code, name: $0.displayName) }
        let topics = ((try? coordinator.sections()) ?? []).map {
            OnboardingTopic(key: "topic:\($0.key)", name: $0.name)
        }
        return (Array(languages), topics)
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

    /// T10: the settings surface's store, and the appearance the reader's own preferences imply right now.
    func makeReaderSettingsStore() -> ReaderSettingsStore? {
        libraryDatabase().map { ReaderSettingsStore(backend: ReaderSettingsBackendAdapter(database: $0)) }
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
        try? await mediaAdapter.play(.init(cardID: PublicationCardID(), url: url,
            title: String(localized: "Episódio de teste"), mimeType: "audio/wav"))
    }

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
        guard let database = try? RuntimeDatabase(location: RuntimeDatabaseLocation(directory: directory)) else {
            return nil
        }
        return ReaderMediaCoordinator(database: database, player: mediaAdapter)
    }

    /// T7: the source surface's store, over the catalog coordinator. One store per presentation, so its
    /// levels and the reader's selection are one consistent picture while it is open.
    func makeSourceManagementStore() -> SourceManagementStore {
        let catalogURL = Bundle.main.url(forResource: "catalog", withExtension: "sqlite")
        let database = try? RuntimeDatabase(location: RuntimeDatabaseLocation(directory: directory))
        return SourceManagementStore(backend: SourceCatalogBackend(
            coordinator: SourceManagementCoordinator(catalogURL: catalogURL, database: database),
            healthProvider: { await self.sourceHealth() }))
    }

    /// T7: what the runtime observed about each source this launch, keyed by the catalog key the surface
    /// knows. A source it never attempted is absent from the map, so no row claims a state nobody measured.
    func sourceHealth() async -> [String: CatalogSourceHealth] {
        guard let association else { return [:] }
        let observed = await association.coordinator.healthSnapshot()
        guard !observed.isEmpty else { return [:] }
        var health: [String: CatalogSourceHealth] = [:]
        for feed in feeds {
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
        var resolved = (try? TrustedFeed.resolveAvailable(keys: record.sourceKeys, fallback: feeds)) ?? []
        if resolved.isEmpty, !record.sourceKeys.isEmpty { resolved = feeds }
        feeds = resolved
        // One selected source is its own surface, exactly as `toggleSource` decides; a context pointing at a
        // source that is no longer selected would be a fence around nothing.
        let request: FeedContextRequest = resolved.count == 1 ? .source(resolved[0].sourceID) : .main
        currentContextKey = ContextKey(request: request, preset: currentContextKey.preset,
            filter: currentContextKey.filter)
        _ = try? preferences.setContext(currentContextKey)
        do { try await replaceSession() }
        catch { startupFailure = "Não foi possível atualizar a seleção de fontes: \(error)" }
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
        guard let catalogURL = Bundle.main.url(forResource: "catalog", withExtension: "sqlite"),
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
    private func association(contextKey: ContextKey, sessionFeeds: [TrustedFeed]? = nil) throws -> FeedAssociation {
        let (scoring, version) = scoring(for: contextKey)
        return connecting(try FeedAssociation(directory: directory, feeds: sessionFeeds ?? feeds,
            configuration: transportConfiguration, contextKey: contextKey, selectionVersion: selectionVersion,
            scoring: scoring, scoringVersion: version))
    }

    /// Explicit session replacement; no replacement occurs during normal feed opportunities.
    func replaceSession() async throws {
        guard !replacingSession else { return }
        replacingSession = true
        defer { replacingSession = false }
        let retired = association
        association = nil
        if let retired {
            _ = try await retired.session.checkpointCurrentPosition(at: Date())
            await retired.close()
        }
        let next = try association(contextKey: currentContextKey)
        association = next
        startupFailure = nil
        try await next.launch()
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
    @ObservationIgnored private let tidyWaitSeconds: Double
    let acquisition: SyndicationAcquisitionSnapshot
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
    /// reader can reach what the build draws. V1's `addFeed` entries, its "Importar para a coleção" and its
    /// per-collection export stay out: this host has no composer for adding a feed, no collection import, and
    /// its export request names the reader's **selection** — offering "Exportar coleção" would open the wrong
    /// document (a review caught exactly that), and an entry that opens the wrong surface is worse than one
    /// that is not offered. A collection's own export belongs to the collection's surface.
    static let readerDestinations: Set<ReaderDestination> = [.sources, .bookmarkBoxes, .filters,
        .collections, .collectionFromContextPrompt, .smartFeedPrompt, .smartFeedDeletion,
        .curatedOnboarding, .curatedInspector, .curatedDeletion, .export, .settings]

    @ObservationIgnored
    lazy var store: FeedScreenStore = FeedScreenStore(onViewport: { [weak self] observation, activity in
        guard let self else { return }
        Task { await self.viewport(observation, activity: activity) }
    }, availableActions: Self.readerCardActions, onAction: { [weak self] event in
        guard let self, self.active else { return }
        switch event.action {
        case .open: self.open(event.cardID)
        case .save: self.toggleBookmark(event.cardID)
        default: self.perform(event.action, cardID: event.cardID)
        }
    }, availableDestinations: Self.readerDestinations,
        onSubmitSearch: { [weak self] term in self?.onSearch?(term) },
        onNavigate: { [weak self] destination in self?.onNavigate?(destination) })

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
            let catalogURL = Bundle.main.url(forResource: "catalog", withExtension: "sqlite"),
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
        var destinations = Self.readerDestinations
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
    /// T5: the reader shell's intents. The association reports them; the app host presents them.
    @ObservationIgnored var onNavigate: ((ReaderDestination) -> Void)?
    /// T9: the share sheet a card's share action opens. The app presents it; the association never does.
    @ObservationIgnored var onShare: ((SharedLink) -> Void)?
    @ObservationIgnored var onSearch: ((String) -> Void)?

    /// Review F10: resolve the frozen action target from published history and open it.
    /// The URL never crosses the UI boundary; only the card identity does.
    private func open(_ cardID: PublicationCardID) {
        guard active, visible, store.state.presentation?.window.items.contains(where: { $0.id == cardID }) == true else { return }
        guard let url = resolvedExternalURL(cardID) else { return }
        present(url, cardID)
    }

    /// U2: a saved article may sit outside the presented window, so it resolves straight from
    /// published history. The window guard above is unchanged for feed cards.
    func openSaved(_ cardID: PublicationCardID) {
        guard active, let url = resolvedExternalURL(cardID) else { return }
        present(url, cardID)
    }

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

    /// Structural bounds for this association's admitted presentation: a readable prefix and the
    /// reserve the reader may walk into. Frozen when the presentation is installed (plan T2/T3).
    static func presentationBounds(_ contextKey: ContextKey) -> FeedPresentationBounds {
        .init(backwardCapacity: 8, forwardCapacity: 16, contextKey: contextKey)
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
            // F01: the session materializes 16 cards ahead; keep at least that much published.
            reserveCards: 16)!,
            acquisition: .init(targetWorkCapacity: 2, batchCapacityPerNewExecution: 1,
                observationCapacityPerBatch: 32, byteCapacityPerBatch: 1_000_000)!)
    }

    init(directory: URL, feeds: [TrustedFeed], configuration: URLSessionConfiguration,
        contextKey: ContextKey = ContextKey(request: .main), selectionVersion: UInt64 = 2,
        scoring: ResolvedSelectionPolicy.ScoringBehavior = .equal, scoringVersion: UInt64 = 1) throws {
        let db = try RuntimeDatabase(location: .init(directory: directory))
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
        let policy = ResolvedSelectionPolicy(contextKey: revision.contextKey,
            userSelectionVersion: revision.userSelectionVersion, eligibilityPolicyVersion: revision.eligibilityPolicyVersion,
            scoringPolicyVersion: revision.scoringPolicyVersion, sequencingPolicyVersion: revision.sequencingPolicyVersion,
            exposurePolicyVersion: revision.exposurePolicyVersion, selectionSchemaVersion: revision.selectionSchemaVersion,
            eligibility: .selectedSources(Set(feeds.map(\.sourceID))), scoring: scoring, sequencing: sequencing,
            exposure: revision.exposurePolicyVersion >= alternating ? .excludePublishedMaterial : .excludePublishedRevisions)
        // The policy is a fact about this session (T11): what it ranks by, and the versions it was published
        // under. A surface or a test can state it without rebuilding the decision.
        self.policy = policy
        let authority = AcquisitionTargetAuthority(database: db)
        let registrations = try feeds.map { feed in
            let existing = try authority.target(id: feed.targetID)
            let target = try existing ?? authority.register(id: feed.targetID,
                connectorKind: .syndication, authorizedSources: [feed.sourceID])
            let binding = SourceBinding(id: feed.bindingID, sourceID: feed.sourceID,
                externalPrincipal: .init(connectorKind: .syndication,
                    namespace: feed.principal.hasPrefix("http") ? LegacyCatalogImport.principalNamespace : "feedmine-development-rss",
                    value: feed.principal, role: .principal), aliases: [], generation: 1, state: .enabled)!
            return SyndicationTargetRegistration(targetID: target.id, targetGeneration: target.generation,
                endpoint: feed.endpoint, bindings: [binding])!
        }
        let transport = URLSession(configuration: configuration)
        self.transport = transport
        let acquisition = try SyndicationAcquisitionSnapshot(database: db, registrations: registrations,
            session: transport, redirectCapacity: 4)
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
        let device = DeviceMediaConditions.current()
        let readiness = MediaReadiness()
        let fetcher = MediaHTTPFetcher(session: transport)
        let media = MediaPrefetcher(database: db, assetDirectory: assetDirectory, readiness: readiness,
            concurrentDownloadLimit: max(2, ProcessInfo.processInfo.activeProcessorCount / 2),
            fetch: { try await fetcher.fetch($0, byteCeiling: $1) },
            conditions: { rate in DeviceMediaConditions.policy(device: device, measuredBytesPerSecond: rate,
                assetDirectory: assetDirectory) })
        self.media = media
        tidy = MediaTidy(assetDirectory: assetDirectory, prefetcher: media, freeStorageBytes: {
            try? FileManager.default.temporaryDirectory
                .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
        }, usage: { try PublicationStore(database: db).mediaUsage() })
        tidyWaitSeconds = configuration.timeoutIntervalForRequest / 4
        coldRetryFallbackSeconds = configuration.timeoutIntervalForRequest
        let session = FeedSession(publicationHistory: history, imageDecoder: PresentationImageDecoder(
            assetDirectory: assetDirectory, heroMaxPixel: device.heroPixelWidth, thumbnailMaxPixel: device.thumbnailPixelWidth))
        self.session = session
        bounds = Self.presentationBounds(context.key)
        let names = Dictionary(uniqueKeysWithValues: feeds.map { ($0.sourceID, $0.displayName) })
        // T9: the playable payload a card's tap should use, read from the candidate the feed declared.
        let playback: @Sendable (OriginRevisionID) -> URL? = { revision in
            // `try?` flattens the store's own optional: a nil here means "no playable payload declared".
            guard let playable = try? ContentStore(database: db).playbackCandidate(originRevisionID: revision) else {
                return nil
            }
            return playable.remoteURL
        }
        let prepare: @Sendable (SelectionResult) -> LocalPreparedPublication = {
            Self.prepare($0, readiness: readiness, names: names, playback: playback)
        }
        // Bounded wait for media of the supply head: what the runway can afford (one request timeout).
        let mediaWait = configuration.timeoutIntervalForRequest / 4
        maintainTail = { lease in
            try await HiddenTailMaintenance(database: db).run(plan: plan, policy: policy, lease: lease, examinedCapacity: 256,
                prefetch: { revisions in await media.prefetch(revisions, deadline: ProcessInfo.processInfo.systemUptime + mediaWait) },
                prepare: prepare)
        }
        let headProvider = CandidateProvider(contentStore: ContentStore(database: db))
        // Runway: the driver supplies the next editorial candidates for the active context (F05).
        let prepareRunwayMedia: @Sendable ([OriginRevisionID]) async -> Void = { revisions in
            await media.prefetch(revisions, deadline: ProcessInfo.processInfo.systemUptime + mediaWait)
        }
        // First Edition: nothing is published yet, so the context head is exactly what the slice selects.
        let prepareMedia: @Sendable () async -> Void = {
            let head = (try? headProvider.candidates(for: plan, after: nil, examinedCapacity: 32))?.candidates.map(\.originRevisionID) ?? []
            await media.prefetch(head, deadline: ProcessInfo.processInfo.systemUptime + mediaWait)
        }
        let runway = RunwayController(configuration: .init(policyInputs: .init(safetyFactor: 1.2,
            releaseMarginSeconds: 2)!, consumptionSampleLimit: 8, replenishmentSampleLimit: 8,
            // M7: first retry after a failed local slice one second later, doubling per failure.
            localRetryBaseSeconds: 1)!)
        driver = try FeedRunwayDriver(session: session, runway: runway, plan: plan, policy: policy,
            acquisition: acquisition, coordinator: coordinator,
            monotonicNow: { .init(seconds: ProcessInfo.processInfo.systemUptime)! },
            makeSegmentIdentity: { .init(segmentID: FeedSegmentID(), segmentSeed: 1, segmentCreatedAt: Date())! },
            prepare: prepare, prepareMedia: prepareRunwayMedia,
            selectedSourceCoverage: .init(selectedSourceCoverageFor: plan.context.key, editorialRevisionID: plan.revision.id))
        let relay = EvidenceRelay()
        self.relay = relay
        cold = try ColdFeedBootstrap(session: session, plan: plan, policy: policy,
            acquisition: acquisition, coordinator: coordinator, prepare: prepare, prepareMedia: prepareMedia,
            evidence: { await relay.deliver($0) })
        targetNames = Dictionary(uniqueKeysWithValues: feeds.map { ($0.targetID, $0.displayName) })
        let provider = CandidateProvider(contentStore: ContentStore(database: db))
        admittedHeadlines = { (try? provider.candidates(for: plan, after: nil, examinedCapacity: 12))?.candidates.compactMap(\.headline) ?? [] }
    }

    /// PD-5: each card is drawn with a prepared image or designed text-only — never "missing" one.
    /// Attribution (source id/name) is frozen into the card, which also feeds PD-4 adjacency.
    nonisolated private static func prepare(_ selection: SelectionResult, readiness: MediaReadiness,
        names: [SourceID: String], playback: (OriginRevisionID) -> URL? = { _ in nil }) -> LocalPreparedPublication {
        .init(inputs: selection.orderedCandidates.map { candidate in
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
                presentation: readiness.presentation(for: candidate.originRevisionID))
        }, cardIDs: selection.orderedCandidates.map { _ in PublicationCardID() })
    }

    func install(_ received: FeedPresentationState) throws {
        guard active else { throw FeedPresentationStateError.projectionSequenceMismatch }
        try store.install(received)
        store.installBookmarks(try PublicationStore(database: database).bookmarkedCardIDs())
        if let snapshot = store.state.presentation {
            Self.log("installed cards=\(snapshot.window.items.count) edition=\(snapshot.editionID.rawValue) sequence=\(snapshot.provenance.sequenceID) order=\(snapshot.provenance.position)")
        }
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
                backwardCapacity: 8, forwardCapacity: 16)
            try install(FeedPresentationHandoff.receive(coldOutcome: outcome, into: store.state))
            Self.log("cold bootstrap settled")
            if case .published = outcome {} else {
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
            if changed { progress = progress.applying(.admitted(headlines: admittedHeadlines()), at: now) }
        case .preparingMedia:
            break
        case .published(let snapshot):
            progress = progress.applying(.prepared(cards: snapshot.window.items.count), at: now)
            // F06: show the first Edition now; slower feeds keep answering behind the badge.
            do { try install(FeedPresentationHandoff.receive(snapshot: snapshot, into: store.state)) }
            catch { Self.log("early publication rejected") }
        }
        preparation = progress
        do { try install(store.state.reporting(.preparing(progress))) } catch { Self.log("preparation update rejected") }
    }

    func viewport(_ observation: ViewportObservation, activity: RunwayActivity) async {
        do {
            guard active else { throw FeedPresentationStateError.projectionSequenceMismatch }
            #if DEBUG
            viewportReceived += 1
            #endif
            Self.log("viewport forwarded activity=\(activity) anchor=\(observation.anchor.cardID)")
            Self.log("viewport opportunity sent to driver")
            let received = try await FeedPresentationHandoff.submitViewport(observation, activity: activity,
                resources: Self.resources, driver: driver, into: store.state)
            try install(received)
            await scheduleLocalRetryIfNeeded()
            #if DEBUG
            viewportCompleted += 1
            if activity == .backward { backwardCompleted += 1 }
            #endif
            Self.log("Runway opportunity completed activity=\(activity)")
        } catch { reportFailure(error); await scheduleLocalRetryIfNeeded() }
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
            let snapshot = try await driver.drive(resources: Self.resources)
            try install(FeedPresentationHandoff.receive(snapshot: snapshot, into: store.state))
            await scheduleLocalRetryIfNeeded()
        } catch { reportFailure(error); await scheduleLocalRetryIfNeeded() }
    }

    func background() async {
        visible = false
        retryTask?.cancel()
        retryTask = nil
        guard active else { return }
        do {
            _ = try await session.checkpointCurrentPosition(at: Date())
            await driver.markConsumptionInactive()
            Self.log("lifecycle checkpoint")
            let lease = try store.state.presentation.map { try PublicationStore(database: database).hiddenTail(editionID: $0.editionID) } ?? nil
            // PD-5: the screen is not visible now, so the house can be tidied: complete media for
            // the next cards and bring local media under the device-derived budget. Seen and visible
            // cards are never changed.
            let visible = Set(store.state.presentation?.window.items.compactMap { $0.image?.key } ?? [])
            let report = await tidy.run(visibleKeys: visible, supplyHeadLimit: 32,
                deadline: ProcessInfo.processInfo.systemUptime + tidyWaitSeconds)
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
        do { try install(store.state.reporting(.failed(message: "Falha ao atualizar o feed"))) }
        catch { Self.log("failure reporting rejected \(String(describing: error))") }
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

    static func current() -> DeviceMediaConditions {
        if Thread.isMainThread { return MainActor.assumeIsolated { currentOnMain() } }
        return DispatchQueue.main.sync { MainActor.assumeIsolated { currentOnMain() } }
    }

    static func policy(device: DeviceMediaConditions, measuredBytesPerSecond: Double?, assetDirectory: URL) -> MediaPolicy? {
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
            // The wait budget for one image is what the runway already tolerates for one feed request.
            waitBudgetSeconds: 5, freeStorageBytes: free, lowPowerMode: info.isLowPowerModeEnabled, thermal: thermal),
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