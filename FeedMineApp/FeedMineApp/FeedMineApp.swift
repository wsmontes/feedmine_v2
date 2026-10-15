import SwiftUI
import UniformTypeIdentifiers
import FeedMineUI
import FeedMineDomain
import FeedMinePersistence
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

    /// U1/U2: one typed sheet surface per modal screen the reader can have up, so a second sheet modifier can
    /// never shadow the first. The reader's URL was resolved by the composition, never by a view.
    private enum SheetSurface: Identifiable {
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
    private enum ReaderPage: Equatable {
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
    private enum AppSurface {
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
    /// U2: a reader is pushed over the surface that asked for it, and closing it pops back to that surface.
    private func pushReader(_ page: ReaderPage) { surfaces.append(.reader(page)) }
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
                                            legacyArticles: composition.legacySavedArticles(inBox: Self.boxID(route)),
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
                            legacyArticles: composition.legacySavedArticles(),
                            onOpen: { cardID in composition.association?.openSaved(cardID) })
                    default:
                        // Only destinations the host declares available can be reached (T5 rule).
                        EmptyView()
                    }
                }
                .fullScreenCover(isPresented: $showsOnboarding) { onboardingCover }
                // U2: the reader's own presentation, above whatever surface asked for it.
                .background(ReaderHost(page: readerPage, playback: composition.mediaState.isPlaying,
                    reader: { page, close in AnyView(readerBody(page, close: close)) },
                    onFinish: { finishReader() }))
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
        }
    }


    /// U2: the reader's own presentation. `SFSafariViewController` ends the presentation it is in when its
    /// own close control is used — that is the control's contract — so the reader has to *be* a presentation:
    /// a reader drawn inside the sheet that opened it went down with that sheet (measured: the reader's close
    /// took the boxes sheet, and the saved list with it). This host lives in the app's own hierarchy, never in
    /// the surface that asked for the reader, so that surface survives the reader and is what the reader
    /// returns to. It draws nothing and takes no touch: it is a place, not a surface.
    private struct ReaderHost: UIViewControllerRepresentable {
        /// The reader that is up, if any, plus a token that changes while it is up: the reader's content reads
        /// the live playback state, so the host must re-render it when that state changes instead of keeping the
        /// view it was presented with (a review measured a bar frozen at whatever it was built with).
        let page: ReaderPage?
        let playback: Bool
        let reader: (ReaderPage, @escaping () -> Void) -> AnyView
        let onFinish: () -> Void

        func makeCoordinator() -> Coordinator { Coordinator(reader: reader, onFinish: onFinish) }

        func makeUIViewController(context: Context) -> UIViewController {
            let host = UIViewController()
            host.view.backgroundColor = .clear
            host.view.isUserInteractionEnabled = false
            return host
        }

        func updateUIViewController(_ host: UIViewController, context: Context) {
            context.coordinator.show(page)
        }

        @MainActor
        final class Coordinator {
            private let reader: (ReaderPage, @escaping () -> Void) -> AnyView
            private let onFinish: () -> Void
            private var shown: ReaderPage?
            private weak var presented: UIViewController?

            init(reader: @escaping (ReaderPage, @escaping () -> Void) -> AnyView,
                onFinish: @escaping () -> Void) {
                self.reader = reader
                self.onFinish = onFinish
            }

            /// The reader is presented once per page, and it goes away when the app's state says it is no
            /// longer up. The reader's own close control reports back instead of dismissing the app's state,
            /// so what is cleared is the host's, never the surface the reader was opened from.
            func show(_ page: ReaderPage?) {
                if let page {
                    let content = reader(page) { [weak self] in self?.onFinish() }
                    if shown == page, let host = presented as? UIHostingController<AnyView> {
                        // The same reader, a newer state: re-render its content in place. Re-presenting would
                        // take the reader down and back up, which is exactly what the reader must not see.
                        host.rootView = content
                        return
                    }
                    guard shown != page else { return }
                    shown = page
                    let controller = UIHostingController(rootView: content)
                    controller.modalPresentationStyle = .fullScreen
                    controller.view.backgroundColor = .systemBackground
                    presented = controller
                    open(controller, page: page, tries: 20)
                } else if let controller = presented {
                    shown = nil
                    presented = nil
                    if controller.presentingViewController != nil { controller.dismiss(animated: true) }
                }
            }

            /// The reader is presented from the surface the app has on top, so it covers whatever asked for it
            /// and leaves that surface in place: measured, a presentation from the app's own host behind the
            /// boxes sheet is refused, and the reader has to be the presentation that is up. A presentation
            /// also needs a laid-out app, so the attempt is retried for a moment rather than lost.
            private func open(_ controller: UIViewController, page: ReaderPage, tries: Int) {
                Task { @MainActor in
                    guard tries > 0, shown == page, controller.presentingViewController == nil else { return }
                    guard let presenter = Self.topmost() else {
                        try? await Task.sleep(for: .milliseconds(50))
                        open(controller, page: page, tries: tries - 1)
                        return
                    }
                    presenter.present(controller, animated: true)
                }
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
        ReaderOnboardingView(recipe: .neutral(languages: [Self.deviceLanguage]), isFirstRun: true,
            previewCards: composition.onboardingPreviewCards(),
            topics: options.topics, regions: options.regions, languages: options.languages,
            deviceLanguage: Self.deviceLanguage,
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
            withSubject: withSubject, tipsHidden: composition.editorialTipsHidden,
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
        case .source(let id):
            return composition.feeds.first { $0.sourceID == id }?.displayName
                ?? String(localized: "Uma fonte")
        case .search(let context): return String(localized: "Busca: \(context.query)")
        }
    }
}
