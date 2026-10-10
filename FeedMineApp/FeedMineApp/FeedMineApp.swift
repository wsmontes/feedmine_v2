import SwiftUI
import UniformTypeIdentifiers
import FeedMineUI
import FeedMineDomain
import FeedMineRuntime

@main
struct FeedMineApp: App {
    @State private var composition = AppComposition()
    /// One typed destination model for the routes that exist today. No booleans per future screen and
    /// no placeholder routes for T6–T11 work.
    @State private var savedPath: [ReaderDestination] = []
    @State private var readerError: String?
    /// The lens hidden by a swipe, keyed by the selection it was hidden for: a new selection shows it again.
    @State private var hiddenLensSignature: String?
    @Environment(\.scenePhase) private var phase

    /// U1/U2: one sheet presentation for every modal surface, so a second sheet modifier can never
    /// shadow the first. The reader's URL was resolved by the composition, never by a view.
    private enum ReaderPresentation: Identifiable {
        case sources
        case bookmarkBoxes
        case collections
        case settings
        case curatedHood
        case export
        case filters
        case reader(URL)
        var id: String {
            switch self {
            case .sources: return "sources"
            case .bookmarkBoxes: return "bookmarkBoxes"
            case .collections: return "collections"
            case .settings: return "settings"
            case .curatedHood: return "curatedHood"
            case .export: return "export"
            case .filters: return "filters"
            case .reader(let url): return "reader:" + url.absoluteString
            }
        }
    }
    @State private var presentation: ReaderPresentation?
    /// T7: the source surface's own navigation and the one store it draws from.
    @State private var sourcesStore: SourceManagementStore?
    @State private var sourcesPath: [SourceRoute] = []
    /// T8: the boxes surface and the two lists it opens (every save, or one box's).
    @State private var boxesStore: BookmarkBoxesStore?
    @State private var libraryPath: [LibraryRoute] = []
    /// T8: the collections surface, and the three library prompts V1 asked with an alert.
    @State private var collectionsStore: CollectionsStore?
    @State private var libraryPrompt: LibraryPrompt?
    /// T9: the link a card asked to share, presented by the platform surface, and the full player.
    @State private var sharedLink: SharedLink?
    @State private var showsPlayer = false
    /// T10: the settings surface and the appearance the reader's preferences imply. The appearance is refreshed
    /// when the reader changes something, when the app comes back, and at launch — a clock moving the palette
    /// never rebuilds a session.
    @State private var settingsStore: ReaderSettingsStore?
    @State private var appearance: ReaderAppearance = .standard
    /// T10: the two tools. The export sheet shows a document the host produced; the import shows what a file
    /// offers before anything is written.
    @State private var exportRequest: ReaderExportRequest = .init(scope: .selection, format: .opml)
    @State private var exportText: String?
    @State private var showsFileImporter = false
    @State private var importPreview: ReaderImportPreview?
    @State private var importIsCommitting = false
    @State private var sharedExport: SharedLink?
    /// T11: the onboarding gate and the curated feed's own hood.
    @State private var showsOnboarding = false
    @State private var showsCuratedHood = false
    @State private var promptName = ""

    /// V1's three library prompts: collect the current sources, save the current context, delete a saved one.
    private enum LibraryPrompt: Identifiable {
        case collectSources
        case saveSmartBookmark
        case deleteSmartFeed
        var id: String {
            switch self {
            case .collectSources: return "collectSources"
            case .saveSmartBookmark: return "saveSmartBookmark"
            case .deleteSmartFeed: return "deleteSmartFeed"
            }
        }
        var title: String {
            switch self {
            case .collectSources: return String(localized: "Reunir estas fontes")
            case .saveSmartBookmark: return String(localized: "Salvar como marcador inteligente")
            case .deleteSmartFeed: return String(localized: "Excluir marcador inteligente")
            }
        }
    }

    /// The lists a box surface can open. A payload-carrying route, because a box is an identity, not a flag.
    enum LibraryRoute: Hashable {
        case savedAll
        case box(String)
    }

    /// The levels under the source surface's root. A typed route, like the app's other destinations.
    enum SourceRoute: Hashable {
        case countries
        case node(CatalogNodeSummary)
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $savedPath) {
                Group {
                    if let association = composition.association {
                        FeedScreen(store: association.store,
                            appearance: appearance,
                            statusChip: AnyView(contextChip(association)),
                            lens: AnyView(filterLens),
                            hasSources: composition.hasSelectedSources,
                            onChooseSources: { presentation = .sources })
                            .id(ObjectIdentifier(association))
                            #if DEBUG
                            .overlay(alignment: .topTrailing) {
                                Text("received=\(association.viewportReceived) completed=\(association.viewportCompleted) backward=\(association.backwardCompleted)")
                                    .font(.system(size: 8)).padding(2).background(.background)
                                    .accessibilityIdentifier("native-viewport-delivery")
                                    .allowsHitTesting(false)
                            }
                            #endif
                    } else if let failure = composition.startupFailure {
                        Text(failure).padding()
                    } else {
                        ProgressView("Abrindo feed local")
                    }
                }
                // T5: the reader draws its own floating header; the navigation bar exists only for
                // pushed destinations, so it stays out of the reading surface.
                // T9: the reader's playback is reported under the feed, in a bar whose height never depends on
                // what it states, so playing an episode cannot move a card.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if composition.mediaState.item != nil {
                        MiniPlayerBar(state: composition.mediaState,
                            onToggle: { Task { await composition.toggleMedia() } },
                            onOpen: { showsPlayer = true })
                    }
                }
                .sheet(isPresented: $showsPlayer) {
                    FullPlayerView(state: composition.mediaState,
                        onToggle: { Task { await composition.toggleMedia() } },
                        onSkip: { seconds in Task { await composition.skipMedia(by: seconds) } },
                        onSeek: { position in Task { await composition.seekMedia(to: position) } },
                        onClose: { showsPlayer = false })
                }
                .toolbar(.hidden, for: .navigationBar)
                .sheet(item: $presentation, onDismiss: {
                    // A selection made in the source surface is adopted when it closes, never mid-list, and the
                    // appearance is re-derived because the settings surface may have changed it.
                    appearance = composition.currentAppearance()
                    Task { await composition.adoptSelectionChange() }
                }) { presentation in
                    switch presentation {
                    case .sources:
                        NavigationStack(path: $sourcesPath) {
                            if let store = sourcesStore {
                                SourceManagementView(store: store,
                                    onOpenNode: { sourcesPath.append(.node($0)) },
                                    onOpenCountries: { sourcesPath.append(.countries) },
                                    onImport: { self.presentation = nil; showsFileImporter = true },
                                    onClose: { self.presentation = nil })
                                    .navigationDestination(for: SourceRoute.self) { route in
                                        switch route {
                                        case .countries:
                                            CountriesListView(store: store,
                                                onOpenNode: { sourcesPath.append(.node($0)) },
                                                onClose: { self.presentation = nil })
                                        case .node(let node):
                                            NodeSourcesView(store: store, node: node,
                                                onOpenNode: { sourcesPath.append(.node($0)) })
                                        }
                                    }
                            } else {
                                ProgressView("Abrindo o catálogo de fontes")
                            }
                        }
                    case .curatedHood:
                        curatedHood
                    case .export:
                        exportSheet
                    case .filters:
                        NavigationStack {
                            FilterSheetView(applying: composition.currentFilter,
                                preset: composition.currentPreset,
                                availableCriteria: ReaderFilterCriterion.enforceable,
                                languages: composition.filterLanguages(),
                                presets: composition.presetRows(),
                                onApply: { filter, preset in
                                    try await composition.applyFilter(filter, preset: preset)
                                },
                                onActivate: { key in try await composition.activateSavedPreset(key) },
                                onDone: { self.presentation = nil })
                        }
                    case .bookmarkBoxes:
                        NavigationStack(path: $libraryPath) {
                            if let store = boxesStore {
                                BookmarkBoxesView(store: store,
                                    onOpenAll: { libraryPath.append(.savedAll) },
                                    onOpenBox: { libraryPath.append(.box($0)) },
                                    onClose: { self.presentation = nil })
                                    .navigationDestination(for: LibraryRoute.self) { route in
                                        FeedSavedListView(
                                            articles: composition.association?.savedArticles(inBox: Self.boxID(route)) ?? [],
                                            onOpen: { composition.association?.openSaved($0) })
                                    }
                            } else {
                                ProgressView("Abrindo as caixas de salvos")
                            }
                        }
                    case .settings:
                        NavigationStack {
                            if let store = settingsStore {
                                ReaderSettingsView(store: store, appearance: appearance,
                                    period: ReaderPeriod.from(hour: Calendar.current.component(.hour, from: Date())),
                                    storageDescription: composition.libraryStorageDescription(),
                                    onClose: { self.presentation = nil })
                            } else {
                                ProgressView("Abrindo os ajustes")
                            }
                        }
                    case .collections:
                        NavigationStack {
                            if let store = collectionsStore {
                                CollectionsView(store: store,
                                    onOpenFeed: { id in
                                        self.presentation = nil
                                        Task { try? await composition.openCollectionFeed(id: id) }
                                    },
                                    onClose: { self.presentation = nil })
                            } else {
                                ProgressView("Abrindo as coleções")
                            }
                        }
                    case .reader(let url):
                        // T9 (V1's own reader): the playback bar stays visible while the reader is open, so an
                        // episode started from a card is still controllable inside the article.
                        VStack(spacing: 0) {
                            InAppBrowser(url: url)
                            if composition.mediaState.item != nil {
                                MiniPlayerBar(state: composition.mediaState,
                                    onToggle: { Task { await composition.toggleMedia() } },
                                    onOpen: { showsPlayer = true })
                                    .background(.ultraThinMaterial)
                            }
                        }
                    }
                }
                .navigationDestination(for: ReaderDestination.self) { destination in
                    switch destination {
                    case .saved:
                        FeedSavedListView(articles: composition.association?.savedArticles() ?? [],
                            onOpen: { cardID in composition.association?.openSaved(cardID) })
                    default:
                        // Only destinations the host declares available can be reached (T5 rule).
                        EmptyView()
                    }
                }
                .fullScreenCover(isPresented: $showsOnboarding) { onboardingCover }
                .sheet(item: $sharedExport) { link in
                    #if os(iOS)
                    ActivityView(url: link.url, subject: link.subject)
                    #else
                    Text(verbatim: link.url.absoluteString).padding()
                    #endif
                }
                .sheet(item: $importPreview) { preview in
                    NavigationStack {
                        ReaderImportPreviewView(preview: preview, isCommitting: importIsCommitting,
                            onCancel: { importPreview = nil },
                            onConfirm: {
                                importIsCommitting = true
                                Task {
                                    let result = await composition.commitImport(preview)
                                    importIsCommitting = false
                                    importPreview = nil
                                    if let result {
                                        associationStoreToast(importSummary(result))
                                    }
                                }
                            })
                    }
                }
                .fileImporter(isPresented: $showsFileImporter,
                    allowedContentTypes: Self.importableTypes) { result in
                    Task { await readImportedFile(result) }
                }
                .sheet(item: $sharedLink) { link in
                    #if os(iOS)
                    ActivityView(url: link.url, subject: link.subject)
                    #else
                    Text(verbatim: link.url.absoluteString).padding()
                    #endif
                }
                .alert(libraryPrompt?.title ?? "", isPresented: Binding(
                    get: { libraryPrompt != nil }, set: { if !$0 { libraryPrompt = nil } })) {
                    if libraryPrompt == .deleteSmartFeed {
                        Button("Excluir", role: .destructive) {
                            Task { try? await composition.deleteCurrentPreset() }
                        }
                    } else {
                        TextField("Nome", text: $promptName)
                        Button("Cancelar", role: .cancel) { libraryPrompt = nil }
                        Button("Salvar") {
                            let name = promptName
                            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            Task {
                                switch libraryPrompt {
                                case .collectSources:
                                    _ = try? composition.collectCurrentSources(named: name)
                                    presentation = .collections
                                case .saveSmartBookmark:
                                    _ = try? await composition.saveCurrentContextAsPreset(named: name,
                                        kind: .smartBookmark)
                                default: break
                                }
                            }
                        }
                    }
                } message: {
                    Text(verbatim: libraryPrompt == .collectSources
                        ? String(localized: "Uma coleção reúne as fontes do que você está lendo agora.")
                        : libraryPrompt == .saveSmartBookmark
                            ? String(localized: "A busca e os filtros atuais ficam guardados com este nome.")
                            : String(localized: "O marcador inteligente guardado com este nome será removido."))
                }
                .alert("Não foi possível atualizar", isPresented: Binding(get: { readerError != nil }, set: { if !$0 { readerError = nil } })) {
                    Button("OK") { readerError = nil }
                } message: { Text(readerError ?? "") }
            }
            .task {
                // U2: the reader stays in the app. The composition resolves the frozen target and
                // hands the URL here; no URL ever comes from a view.
                composition.onExternalURL = { url in presentation = .reader(url) }
                // T9: a card's share action opens the platform sheet; the app presents it, no renderer does.
                composition.onShare = { link in sharedLink = link }
                sourcesStore = composition.makeSourceManagementStore()
                boxesStore = composition.makeBookmarkBoxesStore()
                collectionsStore = composition.makeCollectionsStore()
                settingsStore = composition.makeReaderSettingsStore()
                appearance = composition.currentAppearance()
                // T11: the first launch meets the app (V1 forced it in its own UI tests the same way).
                showsOnboarding = composition.needsOnboarding
                    || ProcessInfo.processInfo.environment["FEEDMINE_ONBOARDING"] == "1"
                // T5: the reader's chrome reports destinations; the host presents the ones it implements.
                composition.onNavigate = { destination in
                    switch destination {
                    case .sources: presentation = .sources
                    case .filters:
                        presentation = .filters
                    case .saved: savedPath.append(.saved)
                    case .bookmarkBoxes: presentation = .bookmarkBoxes
                    case .collections: presentation = .collections
                    case .settings: presentation = .settings
                    case .curatedOnboarding:
                        showsOnboarding = true
                    case .curatedInspector:
                        presentation = .curatedHood
                    case .curatedDeletion:
                        readerError = String(localized: "Excluir este feed curado?")
                    case .export, .collectionExport, .addFeed:
                        exportRequest = ReaderExportRequest(scope: .selection, format: .opml)
                        exportText = composition.exportPreview(exportRequest)
                        presentation = .export
                    case .collectionFromContextPrompt:
                        promptName = ""
                        libraryPrompt = .collectSources
                    case .smartFeedPrompt:
                        promptName = ""
                        libraryPrompt = .saveSmartBookmark
                    case .smartFeedDeletion: libraryPrompt = .deleteSmartFeed
                    default: break
                    }
                }
                await composition.launch()
                #if DEBUG
                // T9 UI evidence: the hook plays a real, silent episode through the real adapter.
                if ProcessInfo.processInfo.environment["FEEDMINE_MEDIA_SIMULATION"] == "1" {
                    await composition.startSimulatedPlayback()
                }
                // T10 UI evidence: a real import preview over a document built here, so the surface and the
                // commit are exercised without a file picker the tests cannot drive.
                if ProcessInfo.processInfo.environment["FEEDMINE_IMPORT_FIXTURE"] == "1",
                    let data = Self.importFixture.data(using: .utf8),
                    let preview = try? await composition.previewImport(data) {
                    importPreview = preview
                }
                #endif
            }
            .onChange(of: phase) { _, next in
                if next == .background { Task { await composition.background() } }
                if next == .active {
                    // T10: the hour can move the palette, so the appearance is re-derived when the reader comes
                    // back. The feed's own identity is untouched.
                    appearance = composition.currentAppearance()
                    Task { await composition.foreground() }
                }
            }
        }
    }


    /// T11: V1's own gate — the reader meets the app before the feed, and what they answer becomes a feed.
    @ViewBuilder private var onboardingCover: some View {
        let options = composition.onboardingOptions()
        ReaderOnboardingView(recipe: .neutral(languages: [Self.deviceLanguage]), isFirstRun: true,
            previewCards: composition.onboardingPreviewCards(),
            topics: options.topics, languages: options.languages,
            deviceLanguage: Self.deviceLanguage,
            onSave: { recipe, name, isBroad in
                Task { await completeOnboarding(with: recipe, named: name, isBroad: isBroad) }
            },
            onClose: {
                composition.completeOnboarding()
                showsOnboarding = false
            })
    }

    /// Saving the Composer's recipe: the feed is stored, activated, and the reader has met the app.
    private func completeOnboarding(with recipe: FeedRecipeDefinition, named name: String, isBroad: Bool) async {
        if let preset = try? composition.saveCuratedFeed(recipe, named: name) {
            try? await composition.activateSavedPreset(preset.key)
        } else if isBroad {
            // "Start broad" with nothing savable is still a start: the reader has met the app either way.
            try? await composition.selectContext(.main)
        }
        composition.completeOnboarding()
        showsOnboarding = false
    }

    private static var deviceLanguage: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    /// T11: V1's "open hood", over the feed the reader is on.
    @ViewBuilder private var curatedHood: some View {
        if let summary = composition.currentCuratedSummary() {
            NavigationStack {
                CuratedFeedInspectorView(summary: summary,
                    onSave: { name in
                        Task {
                            try? await composition.renameCurrentCuratedFeed(to: name)
                            presentation = nil
                        }
                    },
                    onEdit: {
                        presentation = nil
                        showsOnboarding = true
                    },
                    onDelete: {
                        presentation = nil
                        Task { try? await composition.deleteCurrentPreset() }
                    },
                    onClose: { presentation = nil })
            }
        } else {
            ProgressView()
        }
    }

    /// T10: the export sheet — V1's scope × format with a preview of the document it would write.
    @ViewBuilder private var exportSheet: some View {
        let choices = composition.exportChoices()
        NavigationStack {
            ReaderExportView(scopes: choices,
                initial: choices.first { $0.scope == exportRequest.scope } ?? choices.first
                    ?? ReaderExportChoice(id: "selection", title: String(localized: "Minhas fontes"),
                        systemImage: "list.bullet", scope: .selection),
                initialFormat: exportRequest.format,
                previewText: exportText,
                onSelect: { choice, format in
                    exportRequest = ReaderExportRequest(scope: choice.scope, format: format)
                    exportText = composition.exportPreview(exportRequest)
                },
                onShare: { sharedExport = writtenExport() },
                onSave: { sharedExport = writtenExport() },
                onClose: { self.presentation = nil })
        }
    }

    /// The exported file, as the platform share surface takes it: "Save to Files" comes with the same sheet.
    private func writtenExport() -> SharedLink? {
        guard let url = composition.writeExport(exportRequest) else { return nil }
        return SharedLink(url: url, subject: url.lastPathComponent)
    }

    /// A file the reader picked: read it and show what importing it would do. Nothing is written here — the
    /// preview's own confirmation does that.
    private func readImportedFile(_ result: Result<URL, any Error>) async {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            associationStoreToast(String(localized: "Não foi possível ler o arquivo"))
            return
        }
        do { importPreview = try await composition.previewImport(data) }
        catch { associationStoreToast(String(localized: "Não foi possível ler o arquivo")) }
    }

    /// What an import did, in V1's own words.
    private func importSummary(_ result: ReaderImportResult) -> String {
        String(localized: "Importadas \(result.insertedSources) · já suas \(result.alreadySelected) · ignoradas \(result.rejected)")
    }

    /// A message the reader sees, through the feed's own store (V1's own channel for this).
    private func associationStoreToast(_ text: String) {
        composition.association?.store.showToast(text: text, systemImage: "arrow.down.doc")
    }

    /// The file kinds V1's own Info.plist registered for import.
    private static var importableTypes: [UTType] {
        [.xml, UTType(filenameExtension: "opml") ?? .xml]
    }

    /// T10's UI fixture: a small OPML document with one usable feed, one repeat and one unusable address.
    private static let importFixture = """
    <?xml version="1.0" encoding="UTF-8"?>
    <opml version="2.0"><head><title>Fixture</title></head><body>
      <outline text="Ciência">
        <outline type="rss" text="Revista" xmlUrl="https://revista.example/feed"/>
        <outline type="rss" text="Revista de novo" xmlUrl="HTTPS://revista.example/feed/"/>
        <outline type="rss" text="Quebrado" xmlUrl="example.com/sem-esquema"/>
      </outline>
    </body></opml>
    """

    /// The box a library route names, or nil for the all-saved list.
    private static func boxID(_ route: LibraryRoute) -> String? {
        if case .box(let id) = route { return id }
        return nil
    }

    /// T6: the lens states the criteria that are actually applied and removes exactly one per tap; hiding it is
    /// a presentation choice that lasts until the selection changes again.
    @ViewBuilder private var filterLens: some View {
        let filter = composition.currentFilter
        let chips = ReaderFilterLens.chips(filter: filter, preset: composition.currentPreset,
            presetName: nil, searchQuery: nil,
            languageNames: Dictionary(uniqueKeysWithValues: composition.filterLanguages()
                .map { ($0.code, $0.displayName) }))
        if hiddenLensSignature != signature(of: filter, chips) {
            ReaderFilterLens(chips: chips,
                onRemove: { chip in
                    guard let removal = chip.removal else { return }
                    Task { try? await composition.applyFilter(filter.removing(removal),
                        preset: composition.currentPreset) }
                },
                onDismiss: { hiddenLensSignature = signature(of: filter, chips) })
        }
    }

    private func signature(of filter: ReaderFilter, _ chips: [ReaderFilterChip]) -> String {
        chips.map(\.id).joined(separator: "|")
    }

    private func switchContext(_ request: FeedContextRequest) {
        Task { do { try await composition.selectContext(request) } catch { readerError = String(describing: error) } }
    }

    /// T5: the status chip carries the reading context. V1 stated the active context here and the
    /// session's counters live next to it; this keeps the context switcher that U3 introduced (T6
    /// replaces it with the V1 filter/preset surfaces) without inventing navigation chrome.
    @ViewBuilder private func contextChip(_ association: FeedAssociation) -> some View {
        Menu {
            Button("Principal") { switchContext(.main) }
            ForEach(composition.feeds, id: \.sourceID) { feed in
                Button(feed.displayName) { switchContext(.source(feed.sourceID)) }
            }
            if activeContextLabel != nil {
                Divider()
                Button("Mostrar tudo") { switchContext(.main) }
                    .accessibilityIdentifier("reader-context-clear")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "leaf.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(verbatim: "Feedmine").font(.subheadline).fontWeight(.semibold)
                if let label = activeContextLabel {
                    Text(verbatim: "·").font(.caption2).foregroundStyle(.secondary)
                    Text(verbatim: label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("reader-context-label")
                } else if association.active {
                    Text(verbatim: "· \(association.store.state.work.shortDescription)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityIdentifier("reader-contexts")
    }

    private var activeContextLabel: String? {
        switch composition.currentContext {
        case .main: return nil
        case .source(let id): return composition.feeds.first { $0.sourceID == id }?.displayName ?? "Uma fonte"
        case .search(let context): return "Busca: \(context.query)"
        }
    }
}
