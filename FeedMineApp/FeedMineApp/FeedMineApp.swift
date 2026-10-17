import SwiftUI
import UniformTypeIdentifiers
import FeedMineUI
import FeedMineDomain
import FeedMinePersistence
import FeedMineRuntime
#if os(iOS)
@preconcurrency import BackgroundTasks
import UIKit
#endif

@main
struct FeedMineApp: App {
    @State private var composition: AppComposition
    /// One typed destination model for the routes that exist today. No booleans per future screen and
    /// no placeholder routes for T6–T11 work.
    @State private var savedPath: [ReaderDestination] = []
    @State private var readerError: String?
    /// The lens hidden by a swipe, keyed by the selection it was hidden for: a new selection shows it again.
    @State private var hiddenLensSignature: String?
    @Environment(\.scenePhase) private var phase

    init() {
        #if DEBUG
        // The launch record's clock starts here, at the top of the app's own construction, so every fact it states
        // is "milliseconds since this launch began" — before any view exists and long before the first frame.
        FeedLaunchWitness.arm()
        #endif
        // Register before launch finishes, bound to the very same composition used by the UI.
        // A BG grant never constructs another runtime or invokes cold bootstrap.
        let composition = AppComposition()
        _composition = State(initialValue: composition)
        #if os(iOS)
        Self.registerBackgroundRefresh(for: composition)
        #endif
    }

    #if os(iOS)
    private static func registerBackgroundRefresh(for composition: AppComposition) {
        _ = BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundFeedRefresh.identifier, using: nil) {
            [weak composition] task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            // Only the worker reports completion. Expiration cancels that cooperative task,
            // which observes cancellation before updating any durable verification record.
            let worker = Task {
                let completed = await BackgroundFeedRefresh.run(
                    allowed: {
                        await MainActor.run {
                            UIApplication.shared.backgroundRefreshStatus == .available
                        }
                    },
                    opportunity: { [weak composition] in
                        guard let composition else { return false }
                        return await composition.backgroundRefreshOpportunity()
                    })
                refresh.setTaskCompleted(success: completed)
            }
            refresh.expirationHandler = { worker.cancel() }
        }
    }

    private static func requestBackgroundRefresh() {
        // Only at a lifecycle transition: no timer, polling or immediate resubmission.
        let request = BGAppRefreshTaskRequest(identifier: BackgroundFeedRefresh.identifier)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Scheduling is optional. A refusal does not change the offline reader.
        }
    }
    #endif

    /// U1/U2: one typed sheet surface per modal screen the reader can have up, so a second sheet modifier can
    /// never shadow the first. The reader's URL was resolved by the composition, never by a view.
    enum SheetSurface: Identifiable {
        case sources
        case bookmarkBoxes
        case collections
        case settings
        case curatedHood
        case export
        case filters
        /// V1's "Add Feeds": the reader's own composer for a pasted link.
        case addFeed
        var id: String {
            switch self {
            case .sources: return "sources"
            case .bookmarkBoxes: return "bookmarkBoxes"
            case .collections: return "collections"
            case .settings: return "settings"
            case .curatedHood: return "curatedHood"
            case .export: return "export"
            case .filters: return "filters"
            case .addFeed: return "addFeed"
            }
        }
    }

    /// T9: the article the reader opened. A value: no storage handle, and no URL ever crosses back.
    /// Two ways to read, one presentation: the site in the app's own browser, or text the app already holds.
    enum ReaderPage: Equatable {
        case site(URL)
        case local(FeedReadingContent)
    }

    /// U2: the surfaces the reader has up, oldest first. V1's reader returned to the surface it was opened
    /// from, and one presentation at a time is what makes that possible: a reader drawn inside the boxes
    /// sheet went down with it — measured: the reader's own close control dismissed the *outer* sheet (the
    /// saved list went with it), and a second sheet from the root is refused while one is up. So the sheet
    /// draws a sheet surface and the reader is the app's own presentation *over* the surface that asked for
    /// it, which keeps its state (a pushed list's path, the store it draws from) for the reader to come back
    /// to: a card in the feed returns to the feed, a saved article to the list it was opened from.
    enum AppSurface {
        case sheet(SheetSurface)
        case reader(ReaderPage)
    }
    @State private var surfaces: [AppSurface] = []
    /// The sheet surface on top of the stack, or — while the reader is up — the surface the reader was opened
    /// from, which the reader covers and returns to.
    private var sheetSurface: SheetSurface? {
        for surface in surfaces.reversed() {
            if case .sheet(let sheet) = surface { return sheet }
        }
        return nil
    }
    /// The reader that is up, if any. It is drawn by its own host, never by the sheet.
    private var readerPage: ReaderPage? {
        if case .reader(let page) = surfaces.last { return page }
        return nil
    }
    /// The sheet is bound to the sheet surface on top of the stack: what the app closes is that surface, and a
    /// platform dismissal (the sheet's own swipe) clears it the same way. A reader, if one is up, is its own
    /// presentation and is never taken away by the sheet's.
    private var sheetItem: Binding<SheetSurface?> {
        Binding(get: { sheetSurface },
            set: { item in
                guard item == nil else { return }
                surfaces.removeAll { if case .sheet = $0 { return true }; return false }
            })
    }
    /// A surface the reader's chrome asks for replaces what is up: it is a surface of its own, not a level.
    private func present(_ surface: SheetSurface) { surfaces = [.sheet(surface)] }
    /// U2: a reader is a level over the surface that asked for it, and closing it pops back to that surface.
    private func pushReader(_ page: ReaderPage) { surfaces = Self.pushingReader(page, onto: surfaces) }
    /// U2: one reader at a time. A page the reader's own chrome asks for — the site, from the text the app
    /// already holds — replaces the page that is up instead of adding a level: the reader is one surface drawn
    /// once, and a second level would be a page the host never draws while it holds the app's state, so the
    /// close could only end one of the two. The rule is here, on the app's own surface stack, because that is
    /// what says which surface the reader returns to.
    static func pushingReader(_ page: ReaderPage, onto surfaces: [AppSurface]) -> [AppSurface] {
        if case .reader? = surfaces.last {
            return surfaces.dropLast() + [.reader(page)]
        }
        return surfaces + [.reader(page)]
    }
    /// Closing the surface on top: a reader returns to the surface it was opened from, anything else to the
    /// feed.
    private func popSurface() { if !surfaces.isEmpty { surfaces.removeLast() } }
    /// The reader's own close control came back: the surface it was opened from is what it returns to.
    private func finishReader() { if readerPage != nil { popSurface() } }
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
    @State private var addFeedStore: ReaderAddFeedStore?
    @State private var appearance: ReaderAppearance = .standard
    /// T10: the two tools. The export sheet shows a document the host produced; the import shows what a file
    /// offers before anything is written.
    @State private var exportRequest: ReaderExportRequest = .init(scope: .selection, format: .opml)
    @State private var exportText: String?
    @State private var showsFileImporter = false
    @State private var importPreview: ReaderImportPreview?
    @State private var importIsCommitting = false
    /// T11/NN-08: the reader asked the first contact to import a file. The picker and the preview are presented
    /// by the app's own host — a presentation from behind a `fullScreenCover` is refused — so the gate steps aside
    /// for the file flow and comes back exactly as it was. This says the gate owes the reader that return.
    @State private var onboardingImportPending = false
    /// The document the export sheet asked to share, and the platform surface that presents it. It is the
    /// *sheet's* own presentation, anchored on the sheet (`exportSheet`), not the feed's: the reader asks for it
    /// while the sheet is up, and a surface presented by a presenter that already has one up is deferred.
    @State private var sharedExport: SharedLink?
    /// T11: the onboarding gate and the curated feed's own hood.
    @State private var showsOnboarding = false
    /// What the reader answered in this session, so the block that asked shows the answer — and the way back —
    /// where the question was, without waiting for anything to be reloaded.
    @State private var inFeedAnswers: [String: ReaderPreferenceLevel] = [:]
    /// Hiding the invitations is the reader's own choice and it takes effect at once: the preference is the
    /// record, this is the session's answer to it.
    @State private var editorialTipsHidden = false
    /// What has been offered, on which card, and the cards the reader has really been exposed to. A plain
    /// reference box, not observable state: the decision is taken while the feed is being drawn, and writing
    /// observable state inside a view body is undefined behaviour. Round 10 moved the rules into
    /// `EditorialInvitationCadence`, which states them and can be tested; this holds one instance for the whole
    /// app run, and it keeps one session per context key — so a foreground, an internal session rebuild, and
    /// coming back to a context the reader has already read resume the budget instead of renewing it.
    @State private var cadence = EditorialInvitationCadence()
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
                            onChooseSources: { present(.sources) },
                            onTryAgain: { Task { await composition.refreshFromTheReader() } },
                            // R3: the flow that owns the reader's interests is the existing one.
                            onAdjustInterests: { present(.settings) },
                            editorial: { card, index, previous in
                                editorialInvitation(for: card, index: index, previous: previous,
                                    association: association)
                            })
                            .task(id: association.store.state.presentation?.window) {
                                recordWindowFacts(of: association)
                            }
                            .id(ObjectIdentifier(association))
                            #if DEBUG
                            .overlay(alignment: .topTrailing) {
                                Text("received=\(association.viewportReceived) completed=\(association.viewportCompleted) backward=\(association.backwardCompleted)")
                                    .font(.system(size: 8)).padding(2).background(.background)
                                    .accessibilityIdentifier("native-viewport-delivery")
                                    .allowsHitTesting(false)
                            }
                            // A jornada de fluidez lê aqui a série que o próprio app mediu: o rótulo é o ponto
                            // onde o app declara o que viu, e não uma paráfrase do teste.
                            .overlay(alignment: .topLeading) {
                                FeedFrameEvidenceSurface()
                            }
                            #endif
                    } else if let failure = composition.startupFailure {
                        Text(failure).padding()
                    } else {
                        #if DEBUG
                        // The app's own launch progress, nameable so a journey can assert its absence once the app
                        // is idle (V1 named its own surface the same way).
                        ProgressView("Abrindo feed local")
                            .accessibilityIdentifier("feed-launch-progress")
                        #else
                        ProgressView("Abrindo feed local")
                        #endif
                    }
                }
                #if DEBUG
                // The launch record, published where a journey can read it (the same shape as `feed-window-proof`
                // and `native-viewport-delivery`): invisible, non-interactive. The branch this pass is drawing is
                // stated from the host, which owns that decision; the `U14` boundary keeps effects like this out of
                // the UI module on purpose, and the host is where the branch is decided anyway.
                .overlay(alignment: .bottomLeading) { FeedLaunchWitnessProof(branch: launchBranch) }
                #endif
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
                .sheet(item: sheetItem, onDismiss: {
                    // A selection made in the source surface is adopted when it closes, never mid-list, and the
                    // appearance is re-derived because the settings surface may have changed it.
                    appearance = composition.currentAppearance()
                    Task {
                        await composition.adoptSelectionChange()
                        // The settings' own content filters decide what every surface hides; a change there is a
                        // change to what the session applies, so it is re-applied when that surface closes.
                        await composition.reapplyReaderFilters()
                    }
                }) { surface in
                    switch surface {
                    case .sources:
                        NavigationStack(path: $sourcesPath) {
                            if let store = sourcesStore {
                                SourceManagementView(store: store,
                                    onOpenNode: { sourcesPath.append(.node($0)) },
                                    onOpenCountries: { sourcesPath.append(.countries) },
                                    onImport: { popSurface(); showsFileImporter = true },
                                    onClose: { popSurface() })
                                    .navigationDestination(for: SourceRoute.self) { route in
                                        switch route {
                                        case .countries:
                                            CountriesListView(store: store,
                                                onOpenNode: { sourcesPath.append(.node($0)) },
                                                onClose: { popSurface() })
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
                    case .addFeed:
                        addFeedSheet
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
                                onDone: { popSurface() })
                        }
                    case .bookmarkBoxes:
                        NavigationStack(path: $libraryPath) {
                            if let store = boxesStore {
                                BookmarkBoxesView(store: store,
                                    onOpenAll: { libraryPath.append(.savedAll) },
                                    onOpenBox: { libraryPath.append(.box($0)) },
                                    onClose: { popSurface() })
                                    .navigationDestination(for: LibraryRoute.self) { route in
                                        FeedSavedListView(
                                            articles: composition.association?.savedArticles(inBox: Self.boxID(route)) ?? [],
                                            onOpen: { cardID in composition.association?.openSaved(cardID) })
                                    }
                            } else {
                                ProgressView("Abrindo as caixas de salvos")
                            }
                        }
                    case .settings:
                        NavigationStack {
                            if let store = settingsStore {
                                // The options the discovery preferences offer come from the catalogue itself.
                                let options = composition.onboardingOptions()
                                ReaderSettingsView(store: store, appearance: appearance,
                                    period: ReaderPeriod.from(hour: Calendar.current.component(.hour, from: Date())),
                                    storageDescription: composition.libraryStorageDescription(),
                                    contentFilterStore: composition.makeContentFilterStore(),
                                    discoveryLanguages: options.languages, discoveryTopics: options.topics,
                                    discoveryPlaces: options.regions,
                                    // F02 keeps the reader's ability to state rules once and keep them: a feed of
                                    // their own is created here, and creating never activates it.
                                    onCreateCuratedFeed: { recipe, name in
                                        try? composition.saveCuratedFeed(recipe, named: name)?.key
                                    },
                                    onOpenCuratedFeed: { key in
                                        popSurface()
                                        try? await composition.activateSavedPreset(key)
                                    },
                                    onClose: { popSurface() })
                            } else {
                                ProgressView("Abrindo os ajustes")
                            }
                        }
                    case .collections:
                        NavigationStack {
                            if let store = collectionsStore {
                                CollectionsView(store: store,
                                    onOpenFeed: { id in
                                        popSurface()
                                        Task { try? await composition.openCollectionFeed(id: id) }
                                    },
                                    onClose: { popSurface() })
                            } else {
                                ProgressView("Abrindo as coleções")
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
                // NN-08: the first contact can hand the file flow over to the app's own host, so the picker is
                // presented once the gate is really gone (a presentation from behind it is refused) — and the
                // gate returns when the flow ends.
                .fullScreenCover(isPresented: $showsOnboarding,
                    onDismiss: { presentOnboardingImportIfPending() }) { onboardingCover }
                // U2: the reader's own presentation, above whatever surface asked for it.
                .background(ReaderHost(page: readerPage, playback: composition.mediaState.isPlaying,
                    reader: { page, close in AnyView(readerBody(page, close: close)) },
                    onFinish: { finishReader() }))
                // NN-08: the preview the first contact asked for is gone — confirmed or cancelled — and, if the
                // reader came from the gate, the gate comes back.
                .sheet(item: $importPreview, onDismiss: { resumeOnboardingAfterImport() }) { preview in
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
                    shareSurface(link)
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
                                    present(.collections)
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
                composition.onExternalURL = { url in
                    // U2: the reader is pushed over the surface the reader is on — a card in the feed, or the
                    // saved list inside the boxes sheet — and closing it returns to exactly that surface.
                    // This path is the *explicit* request for the site: a card action, a source page.
                    pushReader(.site(url))
                }
                // U-reading: a card's tap asks the composition where it is read, and the answer may be text the
                // app already holds. Opening it reads nothing: no acquisition, no extraction, no cache.
                composition.onReading = { target in
                    switch target {
                    case .local(let content): pushReader(.local(content))
                    case .site(let url): pushReader(.site(url))
                    }
                }
                // T9: a card's share action opens the platform sheet; the app presents it, no renderer does.
                composition.onShare = { link in sharedLink = link }
                sourcesStore = composition.makeSourceManagementStore()
                boxesStore = composition.makeBookmarkBoxesStore()
                collectionsStore = composition.makeCollectionsStore()
                settingsStore = composition.makeReaderSettingsStore()
                addFeedStore = composition.makeAddFeedStore()
                appearance = composition.currentAppearance()
                // T11: the first launch meets the app. V1 forced the gate in its own UI tests with launch
                // arguments; a run that is testing something *else* says so and keeps the gate out of the way.
                let environment = ProcessInfo.processInfo.environment
                let skipsOnboarding = environment["FEEDMINE_SKIP_ONBOARDING"] == "1"
                showsOnboarding = !skipsOnboarding
                    && (composition.needsOnboarding || environment["FEEDMINE_ONBOARDING"] == "1")
                // T5: the reader's chrome reports destinations; the host presents the ones it implements.
                composition.onNavigate = { destination in
                    switch destination {
                    case .sources: present(.sources)
                    case .filters:
                        present(.filters)
                    case .saved: savedPath.append(.saved)
                    case .bookmarkBoxes: present(.bookmarkBoxes)
                    case .collections: present(.collections)
                    case .settings: present(.settings)
                    case .curatedOnboarding:
                        showsOnboarding = true
                    case .curatedInspector:
                        present(.curatedHood)
                    case .curatedDeletion:
                        readerError = String(localized: "Excluir este feed curado?")
                    case .export, .collectionExport:
                        exportRequest = ReaderExportRequest(scope: .selection, format: .opml)
                        exportText = composition.exportPreview(exportRequest)
                        present(.export)
                    case .addFeed, .addFeedToCollection:
                        // V1's two entries open the same sheet; the collection's own entry starts with that
                        // collection already chosen, which is what its label promises.
                        addFeedStore?.selectedCollectionID = destination == .addFeedToCollection
                            ? collectionPresetID : nil
                        present(.addFeed)
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
                // commit are exercised without a file picker the tests cannot drive. NN-08: while the first
                // contact is up the picker is the gate's own journey, so this launch-time stand-in stays out of it.
                if ProcessInfo.processInfo.environment["FEEDMINE_IMPORT_FIXTURE"] == "1",
                    showsOnboarding == false,
                    let data = Self.importFixture.data(using: .utf8),
                    let preview = try? await composition.previewImport(data) {
                    importPreview = preview
                }
                #endif
            }
            .onChange(of: phase) { _, next in
                if next == .background {
                    #if os(iOS)
                    Self.requestBackgroundRefresh()
                    #endif
                    Task { await composition.background() }
                }
                if next == .active {
                    // T10: the hour can move the palette, so the appearance is re-derived when the reader comes
                    // back. The feed's own identity is untouched.
                    appearance = composition.currentAppearance()
                    Task { await composition.foreground() }
                }
            }
            // Round 10: the invitations come back from the preferences that hid them ("Mostrar sugestões do
            // FeedMine"), and the feed's own session flag is cleared with them — the reader's explicit act, not a
            // timer, is what restores the offers. That single act also clears the penalty the hidden period left
            // behind; the distance already read still counts, so re-enabling never drops a block on the reader.
            .onChange(of: settingsStore?.settings.editorialTipsHidden) { _, hidden in
                guard hidden == false else { return }
                editorialTipsHidden = false
                cadence.reenabled(cardsTraversed: composition.editorialExposure.count)
            }
            // One interface language for the whole app: the bundle's own resolution of the reader's device
            // settings. Copy, dates and numbers all read from it, so a screen cannot mix two languages.
            .environment(\.locale, CatalogLanguageNaming.interfaceLocale)
            // UI-READABILITY-01 (architect, 2026-10-17, route A): 1.0 declares **one** presentation, light.
            // `ReaderAppearance` pins every page tint to a light value per period (`pageTintHex`) and every
            // surface that paints it pairs it with `.foregroundStyle(.primary)`; under a dark device appearance
            // `.primary` resolved to white over those light pages and the heading measured 1.19:1. The declaration
            // belongs to the app's presentation owner — this window's content — so the feed and every SwiftUI
            // presentation over it (the sheets, the covers) inherit it, instead of each surface answering for
            // itself. The reader is the one surface the window does not own: `ReaderHost` presents its controller
            // through UIKit, so that controller states the same declaration where it is made (below).
            // This is not dark mode: it is 1.0 offering a consistent light presentation. Route B (real dark mode,
            // with coherent semantic pairs) is a separate decision and opens no refactor here.
            .preferredColorScheme(.light)
        }
    }


    /// U2: the reader's own presentation. `SFSafariViewController` ends the presentation it is in when its
    /// own close control is used — that is the control's contract — so the reader has to *be* a presentation:
    /// a reader drawn inside the sheet that opened it went down with that sheet (measured: the reader's close
    /// took the boxes sheet, and the saved list with it). This host lives in the app's own hierarchy, never in
    /// the surface that asked for the reader, so that surface survives the reader and is what the reader
    /// returns to. It draws nothing and takes no touch: it is a place, not a surface.
    ///
    /// One page at a time and one presentation of it: the page the reader draws follows the app's own state, and
    /// whether it is really up is only ever what the platform reported. Both matter — a `present` the platform
    /// refuses raises no error and calls no completion, so a host that inferred the reader's state from
    /// `presentingViewController`, or that marked a page shown before it was, left the reader on screen with its
    /// close and its site controls wired to nothing.
    struct ReaderHost: UIViewControllerRepresentable {
        /// The reader that is up, if any, plus a token that changes while it is up: the reader's content reads
        /// the live playback state, so the host must re-render it when that state changes instead of keeping the
        /// view it was presented with (a review measured a bar frozen at whatever it was built with).
        let page: ReaderPage?
        let playback: Bool
        let reader: (ReaderPage, @escaping () -> Void) -> AnyView
        let onFinish: () -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(platform: WindowReaderPresentation(), reader: reader, onFinish: onFinish)
        }

        func makeUIViewController(context: Context) -> UIViewController {
            let host = UIViewController()
            host.view.backgroundColor = .clear
            host.view.isUserInteractionEnabled = false
            return host
        }

        func updateUIViewController(_ host: UIViewController, context: Context) {
            // The app's body rebuilds this representable while the coordinator — and the presentation it owns —
            // stays, so the closures the on-screen reader reports to are refreshed here. A control that kept the
            // closures of the body the host was built with reports to a state that has moved on.
            context.coordinator.refresh(reader: reader, onFinish: onFinish)
            context.coordinator.show(page)
        }

        /// The platform acts this host performs, as one seam. They are one seam because the outcome of a
        /// presentation cannot be taken from anything else the caller is given: UIKit raises no error for a
        /// presentation it refuses and calls no completion either, so the act itself reports it — which is what
        /// lets a refusal be exercised, and a refused page be made again instead of lost.
        @MainActor
        protocol Presentation: AnyObject {
            /// Presents the reader over whatever the app has up, reporting whether the reader really went up.
            func present(_ reader: UIViewController, done: @escaping (Bool) -> Void)
            /// Takes the reader down, through whatever really has it up.
            func dismiss(_ reader: UIViewController)
        }

        /// The app's own window surfaces. The reader is presented from the topmost one, so it covers whatever
        /// asked for it and leaves that surface in place: measured, a presentation from this host — which is
        /// inside the hierarchy, behind the boxes sheet — is refused, and the reader has to be the presentation
        /// that is up.
        @MainActor
        final class WindowReaderPresentation: Presentation {
            /// The surface the reader's presentation was attempted from. It is remembered because the
            /// controller's own `presentingViewController` is nil while a transition is in flight and nil for a
            /// presentation the platform refused: inferring the dismissal from that property is what skipped it.
            private weak var presentedFrom: UIViewController?

            func present(_ reader: UIViewController, done: @escaping (Bool) -> Void) {
                guard let presenter = Self.topmost() else {
                    done(false)
                    return
                }
                presentedFrom = presenter
                presenter.present(reader, animated: true)
                // Where the controller ended up is the only account a refused presentation leaves behind.
                done(presenter.presentedViewController === reader)
            }

            func dismiss(_ reader: UIViewController) {
                guard let owner = Self.owner(of: reader, presentedFrom: presentedFrom) else { return }
                owner.dismiss(animated: true)
            }

            /// What really has the reader up: the controller's own `presentingViewController`, or — while a
            /// transition is in flight — the surface the attempt was made from. Only a surface that really has
            /// this reader is returned: taking down something else a surface has up is not this host's to do.
            static func owner(of reader: UIViewController,
                presentedFrom: UIViewController?) -> UIViewController? {
                guard let owner = reader.presentingViewController ?? presentedFrom else { return nil }
                return owner.presentedViewController === reader ? owner : nil
            }

            /// The topmost surface the app has up: the reader is presented over it, and it is what the reader
            /// returns to.
            private static func topmost() -> UIViewController? {
                let windows = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap(\.windows)
                var controller = windows.first { $0.isKeyWindow }?.rootViewController
                while let presented = controller?.presentedViewController { controller = presented }
                return controller
            }
        }

        @MainActor
        final class Coordinator {
            /// The reader's content and what its chrome reports: both are refreshed by every render of the host,
            /// never kept as the values the coordinator happened to be built with.
            private var reader: (ReaderPage, @escaping () -> Void) -> AnyView
            private var onFinish: () -> Void
            private let platform: Presentation
            /// The page the reader's controller draws — the app's state, not the platform's, and the reason a
            /// page the chrome asks for is a re-render instead of a second presentation.
            private var shown: ReaderPage?
            private weak var presented: UIHostingController<AnyView>?
            /// Whether the platform reported the reader up. Only a report writes this; nothing is inferred from
            /// the controller, because a controller that was refused looks exactly like one that was not asked.
            private var isUp = false
            /// An attempt is being made, and its report is still owed: one at a time, whatever re-renders.
            private var isAttempting = false

            init(platform: Presentation,
                reader: @escaping (ReaderPage, @escaping () -> Void) -> AnyView,
                onFinish: @escaping () -> Void) {
                self.platform = platform
                self.reader = reader
                self.onFinish = onFinish
            }

            /// The closures the reader's own chrome reports to, kept current by the host's own render.
            func refresh(reader: @escaping (ReaderPage, @escaping () -> Void) -> AnyView,
                onFinish: @escaping () -> Void) {
                self.reader = reader
                self.onFinish = onFinish
            }

            /// The reader is one presentation that follows the app's state: the page it draws is the page the
            /// app has up, and it goes away when the app's state says it is no longer up. The reader's own close
            /// control reports back instead of dismissing the app's state, so what is cleared is the host's,
            /// never the surface the reader was opened from.
            func show(_ page: ReaderPage?) {
                guard let page else {
                    dismissReader()
                    return
                }
                let content = reader(page) { [weak self] in self?.onFinish() }
                if let controller = presented {
                    // The reader that is up draws the page the app has now. Presenting again for a new page
                    // would stack a second presentation on the first, and the one underneath would outlive the
                    // app state that put it there.
                    controller.rootView = content
                    shown = page
                    open(controller, page: page, tries: Self.presentationAttempts)
                    return
                }
                let controller = UIHostingController(rootView: content)
                controller.modalPresentationStyle = .fullScreen
                controller.view.backgroundColor = .systemBackground
                // UI-READABILITY-01: the reader is the app's second presentation root, and this controller is
                // where its appearance is declared. The window content's `.preferredColorScheme(.light)` reaches
                // every SwiftUI presentation but not a controller presented through UIKit (`presenter.present`),
                // and a `.preferredColorScheme` inside the reader's own content measured inert here: the page
                // still resolved dark and drew white text over its light tint (1.19:1). The declaration is the
                // same one — the light presentation 1.0 ships — stated where this presentation is made.
                controller.overrideUserInterfaceStyle = .light
                presented = controller
                shown = page
                isUp = false
                open(controller, page: page, tries: Self.presentationAttempts)
            }

            /// The reader goes down when the app's state says it is no longer up, and the platform is asked to
            /// take it down: the dismissal is never inferred from the controller's own state, which reports no
            /// `presentingViewController` for a presentation that was refused.
            private func dismissReader() {
                shown = nil
                isUp = false
                isAttempting = false
                guard let controller = presented else { return }
                presented = nil
                platform.dismiss(controller)
            }

            /// The reader is presented from the surface the app has on top, so it covers whatever asked for it
            /// and leaves that surface in place. It also needs a laid-out app, so an attempt the platform
            /// refused is made again — bounded, on the platform's own report — instead of that page staying
            /// unshowable for the life of the process. Nothing here loops on its own: one attempt runs at a time,
            /// and the chain is as long as it is because the platform refused.
            private func open(_ controller: UIViewController, page: ReaderPage, tries: Int) {
                guard tries > 0, !isUp, !isAttempting, shown == page, presented === controller else { return }
                isAttempting = true
                Task { @MainActor in
                    guard isAttempting, shown == page, presented === controller else {
                        isAttempting = false
                        return
                    }
                    platform.present(controller) { [weak self] isReallyUp in
                        guard let self, self.isAttempting else { return }
                        self.isAttempting = false
                        guard self.shown == page, self.presented === controller else { return }
                        guard !isReallyUp else {
                            self.isUp = true
                            return
                        }
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(50))
                            self.open(controller, page: page, tries: tries - 1)
                        }
                    }
                }
            }

            /// How many times one page's presentation is attempted: a transition in flight settles in a few
            /// frames, and an attempt still refused after a second is not going to take.
            private static let presentationAttempts = 20
        }
    }

    /// T9: the article the reader opened, with the playback bar kept visible inside it (V1's own reader).
    /// U-reading: the same presentation carries the local reading surface, so a card's text and a card's site are
    /// one place to come back from — the surface that asked for them survives either way.
    @ViewBuilder private func readerBody(_ page: ReaderPage, close: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            switch page {
            case .site(let url):
                // SafariServices owns the reader's close control, so its finish comes back here: the host owns the
                // presentation, and the state it was presented from is what goes away.
                InAppBrowser(url: url, onFinish: close)
            case .local(let content):
                let openSite: (() -> Void)? = content.siteURL.map { url in { pushReader(.site(url)) } }
                FeedReadingSurface(content: content, appearance: composition.currentAppearance(),
                    onOpenSite: openSite, onClose: close)
            }
            if composition.mediaState.item != nil {
                MiniPlayerBar(state: composition.mediaState,
                    onToggle: { Task { await composition.toggleMedia() } },
                    onOpen: { showsPlayer = true })
                    .background(.ultraThinMaterial)
            }
        }
    }

    /// T11: V1's own gate — the reader meets the app before the feed, and what they answer becomes a feed.
    @ViewBuilder private var onboardingCover: some View {
        let options = composition.onboardingOptions()
        ReaderOnboardingView(recipe: Self.firstRunDraft(regions: options.regions), isFirstRun: true,
            previewCards: composition.onboardingPreviewCards(),
            topics: options.topics, regions: options.regions, languages: options.languages,
            deviceLanguage: Self.deviceLanguage,
            // NN-08: the reader's own sources can be imported at first contact without becoming a requirement.
            // The file flow (picker → preview → commit) is the app's own, presented by the host, so the gate
            // steps aside for it and this host brings it back when it ends. Asking writes nothing at all.
            onImport: {
                onboardingImportPending = true
                showsOnboarding = false
            },
            // F02: the first run's answers are the reader's discovery profile, and the feed is the destination —
            // no feed is created to be activated, and no name is asked for.
            onSave: { recipe in
                // The reader leaves the first run at once: the answers rebuild the session from the catalogue
                // (a query measured in seconds), and nobody should be held on a cover while that happens.
                showsOnboarding = false
                Task { await composition.completeFirstRun(discovery: recipe) }
            },
            onClose: {
                composition.completeOnboarding()
                showsOnboarding = false
            })
    }

    /// F02: the feed presents what discovery found, and the reader answers **in place**. The invitation appears
    /// where there is something truthful to ask — a card the app itself went and found, about a subject the reader
    /// has not answered about yet — within a **budget over what they were really exposed to**, never in a flood,
    /// and never on the reader's own sources.
    ///
    /// The budget is counted in cards the visual capture actually presented (`EditorialInvitationCadence`), so a
    /// rendered window is not an exposure. `index` — the card's place in the admitted window — deliberately no
    /// longer decides anything: what the reader was exposed to is what counts.
    @MainActor private func editorialInvitation(for card: PresentationCard, index: Int,
        previous: PresentationCard?, association: FeedAssociation) -> AnyView? {
        let tipsHidden = editorialTipsHidden || composition.editorialTipsHidden
        let traversed = composition.editorialExposure.count
        // A session begins when the reader's context changes. A foreground and an internal rebuild of the same
        // context — answering an invitation rebuilds the session — deliberately do not begin one.
        cadence.beginSession(key: composition.currentContextKey, cardsTraversed: traversed)
        cadence.setHidden(tipsHidden)
        // **Where an offer becomes an offer.** The window the feed draws reaches behind and ahead of the reader,
        // so placing a block is not showing it: the card the reader's own position is at is the only one whose
        // block has been met. Counting at placement counted blocks the reader never reached (the ledger's own
        // unit is the cards they really passed), and the frequency clause then read offers that no one saw.
        if let anchorCardID = association.store.state.presentation?.window.anchor.cardID,
            anchorCardID == card.id, let hosted = cadence.hosts[card.id],
            cadence.presented(on: card.id, cardsTraversed: traversed) {
            composition.recordEditorialOffer(subject: hosted.subject, cardsTraversed: traversed,
                offersShown: cadence.offersShown, interval: cadence.interval)
        }
        guard let source = card.sourceID,
            let subject = composition.editorialSubject(for: source, in: association) else {
            return nil
        }
        // Codex's finding 1: a block that was offered keeps its card. The reader answered *there*, and that is
        // where the way back lives.
        if let hosted = cadence.hosts[card.id], hosted.subject == subject.nodeKey {
            // The form travels with the offer: a block that comes back as the full question after the reader met
            // the compact one would be a different offer than the one that was made. The **hidden** state applies
            // here too — a block that was already offered is exactly the one the reader sees when they press
            // "Esconder dicas", and wrapping only the newly offered ones left every visible block reachable
            // (measured on the device, 2026-10-11).
            return presented(invitation(subject, card: card, association: association,
                isCompact: hosted.isCompact), tipsHidden: tipsHidden, on: card.id,
                isCompact: hosted.isCompact)
        }
        // New rows wait for native scrolling to end; existing hosted slots above keep their form.
        guard !association.store.isReadingInteractionActive,
            let reading = association.store.state.presentation,
            let anchorIndex = reading.window.items.firstIndex(where: { $0.id == reading.window.anchor.cardID }),
            index > anchorIndex else { return nil }
        // **Where the feed moves to a subject**, not on a clock: a fixed cadence offered the same subject over and
        // over and, in one whole profile, never offered a second one (the acceptance driver could declare only one
        // of the two answers the benchmark requires).
        if let previous, previous.sourceID == source {
            return nil
        }
        let answered = inFeedAnswers[subject.nodeKey] ?? composition.declaredLevel(forNode: subject.nodeKey)
        // A subject answered in an earlier session is not asked about again; one answered **here** keeps its block,
        // because that block is where the way back lives.
        if answered != nil, inFeedAnswers[subject.nodeKey] == nil {
            return nil
        }
        // The budget: how much was already offered, how many cards the reader has been exposed to since, and
        // whether they asked for the offers to stop. Every refusal is stated by the policy, not by an unnamed
        // `return nil`.
        //
        // A card the reader has **already been exposed to** is not offered on (architect, 2026-10-11): the window
        // the feed renders reaches behind the reader, and a block placed there is one the reader will never see —
        // measured on the real catalogue, where the app's own trace showed the offers being made while the walk
        // never met them. An offer belongs where the reader is going.
        guard !composition.editorialExposure.wasExposed(card.id) else { return nil }
        // The budget's own reason is recorded, not swallowed. A trace that shows only the offers that happened
        // cannot answer the frequency question the PO asked ("did the cadence become a questionnaire?"), and it
        // cannot explain an offer that did *not* arrive — the same kind of gap as B04's unmeasurable idle
        // (QA, 2026-10-14). The reason is the policy's, never an unnamed `return nil`.
        if let refusal = cadence.decision(subject: subject.nodeKey, isAnswered: answered != nil,
            cardsTraversed: traversed) {
            composition.recordEditorialRefusal(refusal: String(describing: refusal), subject: subject.nodeKey,
                cardsTraversed: traversed, offersShown: cadence.offersShown, interval: cadence.interval)
            return nil
        }
        // The session's first offer asks the full question; the ones after it are compact (the same actions in
        // less space), which is what the PO's acceptance criteria asked for in so many words.
        let isCompact = cadence.offersShown > 0
        cadence.offered(subject: subject.nodeKey, on: card.id, cardsTraversed: traversed,
            isCompact: isCompact)
        // Hidden means **invisible**, not removed: the layout slot is the reader's, and taking rows out of the feed
        // moved their anchored card by 128 pt (measured twice). What the reader asked for was to stop seeing the
        // invitations, not to have the feed shift under them. Hidden also leaves the accessibility tree, because a
        // control nobody can see is not a control VoiceOver may offer.
        let block = invitation(subject, card: card, association: association, isCompact: isCompact)
        return presented(block, tipsHidden: tipsHidden, on: card.id, isCompact: isCompact)
    }

    /// A block as the reader has asked for it to be shown. Hidden means invisible **and out of the tree**: a
    /// control nobody can see is not a control VoiceOver may offer, and `accessibilityHidden` alone left the
    /// buttons reachable in the tree (measured on the device, 2026-10-11). The layout slot stays, because moving
    /// rows out of the feed moved the reader's anchored card by 128 pt (measured twice).
    ///
    /// **Absence is not a slot.** Kiro K-06 finding 2: a block that was never offered must return `nil` — a
    /// zero-height child is still a child of the `LazyVStack`, so the stack kept inserting `Spacing.section` for a
    /// slot that does not exist and hiding a block never restored the geometry of "no block". An offered block
    /// that was hidden keeps its slot (the architect's rule: hiding preserves the slot the reader's layout was
    /// built on) — which is exactly the case `slotHeight` answers with a height.
    @MainActor private func presented(_ block: AnyView, tipsHidden: Bool, on card: PublicationCardID,
        isCompact: Bool) -> AnyView? {
        guard tipsHidden else {
            // The block reports the room its content takes while it is really on screen, and it is drawn inside
            // the slot it was given the first time: the reader's layout is theirs, so the block may not pull the
            // cards under it up when its own form changes (answering makes it shorter — measured by B04).
            let measured = cadence.height(of: card)
            let measuredBlock = block.onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                cadence.remember(height: height, of: card, isCompact: isCompact)
            }
            guard let measured else { return AnyView(measuredBlock) }
            return AnyView(measuredBlock.frame(height: measured, alignment: .leading))
        }
        // Nothing of the suggestion is drawn at all: not a control, not a word. Marking a block as hidden left
        // both its buttons and its texts in the accessibility tree (measured on the device, 2026-10-11), and the
        // reader asked for the invitations to stop — so the surface draws the room they took and nothing else.
        // No room taken means no row at all.
        guard let slot = cadence.slotHeight(of: card, isCompact: isCompact) else { return nil }
        return AnyView(Color.clear.frame(height: slot))
    }

    /// The block itself, rendered wherever its host card is. It always reads the *current* answer, so voting and
    /// taking it back are visible without the block moving.
    @MainActor private func invitation(_ subject: AppComposition.EditorialSubject,
        card: PresentationCard, association: FeedAssociation, isCompact: Bool) -> AnyView {
        let answered = inFeedAnswers[subject.nodeKey] ?? composition.declaredLevel(forNode: subject.nodeKey)
        return AnyView(FeedEditorialInvitationView(subjectName: subject.name, nodeKey: subject.nodeKey,
            answered: answered, isCompact: isCompact,
            // The surface shows the answer the app really has: a vote that could not be persisted or applied is
            // taken back on screen, and the failure stays visible in the trace (Codex's finding 4).
            onVote: { level in
                inFeedAnswers[subject.nodeKey] = level
                cadence.answered(subject: subject.nodeKey)
                Task {
                    if await composition.voteOnTopic(nodeKey: subject.nodeKey, level: level) == false {
                        inFeedAnswers[subject.nodeKey] = nil
                    }
                }
            },
            onUndo: {
                inFeedAnswers[subject.nodeKey] = nil
                Task {
                    if await composition.voteOnTopic(nodeKey: subject.nodeKey, level: .neutral) == false {
                        inFeedAnswers[subject.nodeKey] = nil
                    }
                }
            },
            onHide: {
                editorialTipsHidden = true
                cadence.setHidden(true)
                composition.setEditorialTipsHidden(true)
            }))
    }

    /// The facts the invitation depends on, recorded once per window change — off the render path. The cards now
    /// carry their own source, so this is arithmetic over a value, not a database read per card.
    @MainActor private func recordWindowFacts(of association: FeedAssociation) {
        let cards = association.store.state.presentation?.window.items ?? []
        let resolved = cards.compactMap(\.sourceID)
        let withSubject = resolved.filter { composition.editorialSubject(for: $0, in: association) != nil }.count
        composition.recordWindowFacts(cards: cards.count, resolvedSources: resolved.count,
            withSubject: withSubject, knownSubjects: association.subjects.count,
            tipsHidden: composition.editorialTipsHidden,
            traversed: composition.editorialExposure.count, offersShown: cadence.offersShown)
    }

    /// The reader has met the app without answering anything: the shortcut out of the first run.
    private func completeOnboarding() async {
        composition.completeOnboarding()
        showsOnboarding = false
    }

    private static var deviceLanguage: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    /// The first run's opening draft: the language the device reads in, and — when the device states a place it
    /// can trust — the region it is set to. Both are **drafts**: the recipe is written only when the reader
    /// confirms, and the place chip takes the answer back exactly as if the reader had tapped it.
    private static func firstRunDraft(regions: [OnboardingRegion]) -> FeedRecipeDefinition {
        var draft = FeedRecipeDefinition.neutral(languages: [deviceLanguage])
        if let region = DeviceRegionDraft.region(deviceRegion: Locale.current.region?.identifier,
            preferredLanguage: Locale.preferredLanguages.first, among: regions) {
            draft.topicPreferences[region.preferenceKey] = .more
        }
        return draft
    }

    /// T11: V1's "open hood", over the feed the reader is on.
    @ViewBuilder private var curatedHood: some View {
        if let summary = composition.currentCuratedSummary() {
            NavigationStack {
                CuratedFeedInspectorView(summary: summary,
                    onSave: { name in
                        Task {
                            try? await composition.renameCurrentCuratedFeed(to: name)
                            popSurface()
                        }
                    },
                    onEdit: {
                        popSurface()
                        showsOnboarding = true
                    },
                    onDelete: {
                        popSurface()
                        Task { try? await composition.deleteCurrentPreset() }
                    },
                    onClose: { popSurface() })
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
                onClose: { popSurface() })
                // The document is produced by the app's own coordinator, and the sheet is what shows it: it is
                // recomputed here so the preview is never the value a previous opening left behind, and so it is
                // made while the reader is looking at the sheet rather than while the menu was still open.
                .task {
                    // The document is the app's own; it is produced while the reader is on the sheet and retried
                    // until the store answers, so the preview the reader sees is the document, never an empty
                    // value a slower first read left behind.
                    for _ in 0..<20 {
                        exportText = composition.exportPreview(exportRequest)
                        if let text = exportText, !text.isEmpty { return }
                        try? await Task.sleep(for: .milliseconds(150))
                    }
                }
        }
        // The document's own share surface is presented by *this* sheet, not by the feed behind it.
        // `Compartilhar` and `Salvar arquivo` are asked for while the sheet is up, and the platform defers a
        // presentation requested by a presenter that already has one up: with this modifier on the feed's own
        // view, the surface came up only **after** the export sheet was closed — measured 2026-10-16, 4 s
        // later, with the reader's tap having produced nothing in the meantime
        // (`docs/reviews/2026-10-16-superficies-honestas.md` §3, raw log `/tmp/sharecheck-ORCH-repro.log`).
        // Anchored here it is the export sheet's own surface: it goes up over the document the reader asked to
        // share, and leaving it gives the sheet back as it was — the reading point is not the platform's to
        // move.
        .sheet(item: $sharedExport) { link in
            shareSurface(link)
        }
    }

    /// The platform's own share surface for a document or a link this app produced: one adapter, presented by
    /// whichever surface asked for it — the export sheet for the document it shows, the feed for a card's link.
    @ViewBuilder private func shareSurface(_ link: SharedLink) -> some View {
        #if os(iOS)
        ActivityView(url: link.url, subject: link.subject)
        #else
        Text(verbatim: link.url.absoluteString).padding()
        #endif
    }

    /// V1's "Add Feeds" sheet. The store (resolution, storage, collections) belongs to the composition; the
    /// host only draws it and, when it closes, adopts the selection change it produced — the added feeds become
    /// the session's own sources.
    @ViewBuilder private var addFeedSheet: some View {
        if let store = addFeedStore {
            NavigationStack {
                ReaderAddFeedView(store: store, appearance: appearance,
                    targetCollectionName: targetCollectionName, onClose: { popSurface() })
            }
        } else {
            ProgressView("Abrindo as fontes")
        }
    }

    /// The collection the reader is reading, when the menu entry was the collection's own.
    private var targetCollectionName: String? {
        guard case .collection = composition.currentPreset, let id = collectionPresetID else { return nil }
        return collectionsStore?.collections.first { $0.id == id }?.name
    }

    private var collectionPresetID: String? {
        if case .collection(let id) = composition.currentPreset { return id }
        return nil
    }

    /// The exported file, as the platform share surface takes it: "Save to Files" comes with the same sheet.
    private func writtenExport() -> SharedLink? {
        guard let url = composition.writeExport(exportRequest) else { return nil }
        return SharedLink(url: url, subject: url.lastPathComponent)
    }

    /// A file the reader picked: read it and show what importing it would do. Nothing is written here — the
    /// preview's own confirmation does that. Every path that leaves no preview behind gives a gate that asked for
    /// this flow its surface back (NN-08); for every other import it is nothing at all.
    private func readImportedFile(_ result: Result<URL, any Error>) async {
        guard case .success(let url) = result else {
            // The reader dismissed the picker: nothing was read, nothing was written, nothing was completed.
            resumeOnboardingAfterImport()
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            associationStoreToast(String(localized: "Não foi possível ler o arquivo"))
            resumeOnboardingAfterImport()
            return
        }
        do {
            importPreview = try await composition.previewImport(data)
            // A file the app cannot turn into a preview leaves nothing to confirm, so the gate does not wait for
            // a sheet that will never come.
            if importPreview == nil { resumeOnboardingAfterImport() }
        } catch {
            associationStoreToast(String(localized: "Não foi possível ler o arquivo"))
            resumeOnboardingAfterImport()
        }
    }

    /// NN-08: the gate is gone and asked for a file. The picker is presented here — once the cover is really
    /// dismissed — and the DEBUG fixture stands in for the chosen file, through the very same reader an actually
    /// picked file goes through, because a UI test cannot drive the platform's file dialog.
    private func presentOnboardingImportIfPending() {
        guard onboardingImportPending else { return }
        #if DEBUG
        let fixture = ProcessInfo.processInfo.environment["FEEDMINE_IMPORT_FIXTURE"]
        if fixture == "1", let url = Self.onboardingImportFixtureURL() {
            Task { await readImportedFile(.success(url)) }
            return
        }
        if fixture == "cancel" {
            Task { await readImportedFile(.failure(CocoaError(.userCancelled))) }
            return
        }
        #endif
        showsFileImporter = true
    }

    /// NN-08: the file flow the gate asked for ended — the preview was dismissed, the picker was cancelled, or
    /// the file could not be read — and the gate comes back where it was, as the only surface that can complete a
    /// first run. Nothing was written by being here and no first run was completed: the reader still chooses how
    /// their feed begins.
    private func resumeOnboardingAfterImport() {
        guard onboardingImportPending else { return }
        onboardingImportPending = false
        showsOnboarding = true
    }

    #if DEBUG
    /// T10's fixture, written where the app's own import path can read it, so NN-08 walks the reader → preview →
    /// commit path a picked file walks without the file dialog the tests cannot drive.
    private static func onboardingImportFixtureURL() -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("feedmine-import-fixture.opml")
        guard (try? importFixture.write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }
        return url
    }
    #endif

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
                .map { ($0.languageCode, $0.displayName) }))
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
        Task {
            do { try await composition.selectContext(request) }
            catch {
                // R5: a raw error description is diagnostics, never the reader's copy.
                #if DEBUG
                print("context switch failed: \(String(describing: error))")
                #endif
                readerError = String(localized: "Não foi possível mudar de contexto agora.")
            }
        }
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
                // The wordmark is a brand mark, not reader copy: it keeps one line at every Dynamic Type size.
                // Measured at AccessibilityXXXL on 2026-10-17, the text wrapped inside the header's own width and
                // drew as `Fe-` / `ed-` / `min` / `e`; the scale floor keeps the whole word while the reader's
                // category still scales it as far as the header's controls allow.
                Text(verbatim: "Feedmine")
                    .font(.subheadline).fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
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
        case .source(let id):
            return composition.feeds.first { $0.sourceID == id }?.displayName
                ?? String(localized: "Uma fonte")
        case .search(let context): return String(localized: "Busca: \(context.query)")
        }
    }

    #if DEBUG
    /// What this pass of the host's own body is about to draw. The host owns this branch — it holds the association
    /// and the screen's inputs — so the launch record is taken from the same values the screen reads, never from a
    /// second opinion about them: the branch read here and the branch `FeedScreen` draws are one decision.
    private var launchBranch: FeedLaunchWitness.Branch {
        guard let association = composition.association else { return .launchProgress }
        guard composition.hasSelectedSources else { return .notAWaitSurface }
        let rendered = association.store.renderedItems
        guard rendered.isEmpty else { return .cards(rendered.count) }
        return .feedAbsence(Self.absenceKind(association.store.state.work))
    }

    /// The work an absence surface states, as the short token the launch record carries.
    private static func absenceKind(_ work: FeedPresentationState.Work) -> String {
        switch work {
        case .idle, .pending: return "idle"
        case .preparing: return "preparing"
        case .deferred: return "deferred"
        case .unavailable: return "unavailable"
        case .unreachable: return "unreachable"
        case .failed: return "failed"
        case .endOfContent: return "end-of-content"
        }
    }
    #endif
}

#if DEBUG
/// The app's own launch record (`FeedLaunchWitness`) as one accessibility element, so the reopen journey can assert
/// what no post-idle sampling can see: whether the reader's first reading surface in this process was already their
/// feed. Invisible and non-interactive — it draws nothing for the reader, and it changes no layout.
private struct FeedLaunchWitnessProof: View {
    /// The branch this pass of the host is drawing. Stating it here (a declaration in the body, evaluated with the
    /// pass) is what puts the fact on the record.
    let branch: FeedLaunchWitness.Branch

    var body: some View {
        let _: Void = FeedLaunchWitness.note(branch)
        Text(verbatim: FeedLaunchWitness.record)
            .font(.system(size: 1))
            .frame(width: 1, height: 1)
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityIdentifier("feed-launch-record")
    }
}
#endif
