import SwiftUI
import SafariServices
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
    /// A filter selection that was durably saved but not presented. The retry uses the existing activation
    /// owner; the alert is above the feed, not behind the closed sheet.
    @State private var filterActivationFailure = false
    /// The filter sheet's draft store. It lives with the **presenter**, not with the sheet: a platform swipe ends
    /// the sheet's view tree before any closure inside it can run, and V1's contract is that going away applies the
    /// dirty parts. Holding it here is what lets the dismissal apply the draft and what keeps the reader's edits
    /// when the durable write refuses them.
    @State private var filterStore: ReaderFilterStore?
    /// Whether the surface being dismissed is the filter sheet, so a dismissal applies **its** draft and closing
    /// another sheet never applies a filter the reader is not editing.
    @State private var filterDismissalAppliesDraft = false
    /// The lens hidden by a swipe, keyed by the selection it was hidden for: a new selection shows it again.
    @State private var hiddenLensSignature: String?
    /// D7-A: whether the reader still owes an acknowledgement for a V1 upgrade. Set once when the surface
    /// appears; cleared only by the reader's own action.
    @State private var showsLegacyUpgradeNotice = false
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
        /// V1's "Criar feed curado": the composer creates a preset without activating it.
        case curatedComposer
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
            case .curatedComposer: return "curatedComposer"
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
    /// Presents the V1-upgrade notice on the window's topmost controller, which is above the reader's own
    /// presented surface. The receipt is recorded **only** by the reader's acknowledgement.
    @MainActor private func presentLegacyUpgradeNoticeIfOwed() {
        guard !showsLegacyUpgradeNotice, let notice = composition.legacyUpgradeNotice else { return }
        showsLegacyUpgradeNotice = true
        LegacyUpgradeNoticePresenter.present(title: String(localized: "Da versão anterior"),
            message: composition.legacyUpgradeNoticeText) { [composition] in
            self.showsLegacyUpgradeNotice = false
            composition.acknowledgeLegacyUpgradeNotice()
            _ = notice
        }
    }

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
        case deleteCuratedFeed
        var id: String {
            switch self {
            case .collectSources: return "collectSources"
            case .saveSmartBookmark: return "saveSmartBookmark"
            case .deleteSmartFeed: return "deleteSmartFeed"
            case .deleteCuratedFeed: return "deleteCuratedFeed"
            }
        }
        var title: String {
            switch self {
            case .collectSources: return String(localized: "Reunir estas fontes")
            case .saveSmartBookmark: return String(localized: "Salvar como marcador inteligente")
            case .deleteSmartFeed: return String(localized: "Excluir marcador inteligente")
            case .deleteCuratedFeed: return String(localized: "Excluir feed curado")
            }
        }
    }

    /// V1's "Criar feed curado": the first-run composer entered directly, saving a preset of the reader's own
    /// without moving the reading. Its failure stays in this sheet so the reader sees it where they acted; the
    /// root error alert is behind a presented sheet and cannot serve this action.
    private struct CuratedComposerSheet: View {
        let composition: AppComposition
        let onClose: () -> Void
        @State private var errorMessage: String?
        @State private var isSaving = false

        var body: some View {
            let options = composition.onboardingOptions()
            NavigationStack {
                VStack(spacing: 0) {
                    if let errorMessage {
                        Text(verbatim: errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .padding(.horizontal, FeedDesignTokens.Spacing.page)
                            .padding(.top, FeedDesignTokens.Spacing.tight)
                            .accessibilityIdentifier("curated-composer-error")
                    }
                    ReaderOnboardingView(
                        recipe: .neutral(languages: AppComposition.suggestedLanguages(from: options.languages),
                            hasLanguageAnswer: true),
                        isFirstRun: false,
                        previewCards: [],
                        topics: options.topics, regions: options.regions, languages: options.languages,
                        isSaving: isSaving,
                        primaryTitle: String(localized: "Salvar feed curado"),
                        onSave: { recipe in save(recipe) },
                        onClose: onClose)
                }
            }
        }

        private func save(_ recipe: FeedRecipeDefinition) {
            isSaving = true
            do {
                if try composition.saveCuratedFeed(recipe, named: String(localized: "Meu feed curado")) != nil {
                    onClose()
                } else {
                    errorMessage = String(localized: "Não foi possível criar o feed curado. Tente novamente.")
                    isSaving = false
                }
            } catch {
                errorMessage = String(localized: "Não foi possível criar o feed curado. Tente novamente.")
                isSaving = false
            }
        }
    }

    /// The filter sheet and the country levels it opens. The navigation state lives with the sheet's own
    /// content: a push inside this host keeps the reader's draft and cannot be lost in a re-render of the
    /// feed's body. The country level mirrors the source sheet's own `SourceRoute`.
    ///
    /// The draft store is handed **in** by the app host: it outlives the sheet (so a refused write keeps the
    /// reader's edits for the next open) and it is what the platform swipe's dismissal applies. Every control
    /// that closes this surface — the sheet's toolbar, the node level's Concluído — goes through `close()`, which
    /// is the store's own `dismiss()`: one path, idempotent, no double apply.
    private struct FilterSurfaceHost: View {
        let composition: AppComposition
        let filterStore: ReaderFilterStore
        let store: SourceManagementStore?
        let onDone: () -> Void
        let onActivationFailure: () -> Void
        @State private var path: [SourceRoute] = []
        @State private var applyFailure: String?
        @State private var closing = false

        var body: some View {
            NavigationStack(path: $path) {
                FilterSheetView(store: filterStore,
                    languages: composition.filterLanguages(),
                    presets: composition.presetRows(),
                    onActivate: { key in try await composition.activateSavedPreset(key) },
                    onShowCountries: { path.append(.countries) },
                    onDone: onDone,
                    onClose: close)
                    .navigationDestination(for: SourceRoute.self) { route in
                        if let store {
                            switch route {
                            case .countries:
                                CountriesListView(store: store,
                                    onOpenNode: { path.append(.node($0)) },
                                    onClose: { path.removeAll() })
                            case .node(let node):
                                // The filter sheet keeps only its own navigation: opening a source there would
                                // close this sheet and discard the reader's draft, which is outside F12.
                                NodeSourcesView(store: store, node: node,
                                    onOpenNode: { path.append(.node($0)) },
                                    onClose: { Task { await close() } })
                            }
                        } else {
                            ProgressView("Abrindo o catálogo de fontes")
                        }
                    }
            }
            .alert(String(localized: "Filtro"), isPresented: Binding(
                get: { applyFailure != nil }, set: { if !$0 { applyFailure = nil } })) {
                Button("OK") { applyFailure = nil }
            } message: {
                Text(applyFailure ?? "")
            }
        }

        /// V1's `onDisappear`: going away applies the dirty parts. A clean draft closes without a durable write;
        /// a failure keeps the sheet and the draft, and states which failure happened. Serialized, so a second
        /// request while the first is in flight neither applies twice nor closes a sheet that said it failed.
        @MainActor private func close() async {
            guard !closing else { return }
            closing = true
            defer { closing = false }
            do {
                let applied = try await filterStore.dismiss()
                // A duplicate request that found the first apply in flight must not close the sheet.
                guard applied || !filterStore.isDirty else { return }
                onDone()
            } catch let failure as ReaderFilterFailure {
                applyFailure = failure.readerMessage
            } catch {
                applyFailure = String(localized: "Não foi possível salvar o filtro. Tente novamente.")
            }
        }
    }

    /// The filter sheet and its country tree. Extracted for the same reason as the other sheets: one case of a
    /// large presentation switch stays a named expression, and the compiler type-checks it on its own.
    @ViewBuilder private var filterSurface: some View {
        if let filterStore {
            FilterSurfaceHost(composition: composition, filterStore: filterStore, store: sourcesStore,
                onDone: { popSurface() },
                onActivationFailure: { filterActivationFailure = true })
        } else {
            ProgressView("Abrindo os filtros")
        }
    }

    /// Opening the filter surface is also the moment its store is reconciled with the selection the reader is on.
    /// The store is reused across opens: a clean draft follows the applied selection, a dirty one is kept — that is
    /// what a refused dismissal left behind, and `isStale` is what the sheet states about it.
    @MainActor private func openFilters() {
        if let existing = filterStore {
            existing.hydrate(applying: composition.currentFilter, preset: composition.currentPreset)
        } else {
            filterStore = ReaderFilterStore(applying: composition.currentFilter,
                preset: composition.currentPreset,
                availableCriteria: ReaderFilterCriterion.enforceable,
                onApply: { filter, preset in
                    try await composition.applyFilterFromSheet(filter, preset: preset) {
                        filterActivationFailure = true
                    }
                })
        }
        filterDismissalAppliesDraft = true
        present(.filters)
    }

    /// A dismissal the sheet itself cannot observe: the platform swipe ends the sheet's view tree, so V1's
    /// `onDisappear` runs here, on the store that outlived it. The dirty parts are applied once; a refused write
    /// keeps the draft for the next open and states its failure above the feed, because the sheet is gone. A
    /// saved-but-not-presented selection is the existing retry alert's, not a second message.
    @MainActor private func applyDismissedFilterDraft() async {
        guard let filterStore, filterStore.isDirty else { return }
        do {
            _ = try await filterStore.dismiss()
        } catch let failure as ReaderFilterFailure {
            if !failure.selectionIsSaved {
                composition.association?.store.showToast(text: failure.readerMessage,
                    systemImage: "exclamationmark.triangle")
            }
        } catch {
            composition.association?.store.showToast(
                text: String(localized: "Não foi possível salvar o filtro. Tente novamente."),
                systemImage: "exclamationmark.triangle")
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
                            hasSources: composition.surfaceHasSources,
                            onChooseSources: { present(.sources) },
                            onTryAgain: { Task { await composition.refreshFromTheReader() } },
                            // R3: the flow that owns the reader's interests is the existing one.
                            onAdjustInterests: { present(.settings) },
                            editorial: { card, index, previous in
                                editorialInvitation(for: card, index: index, previous: previous,
                                    association: association)
                            })
                            // D4: the first screen's lifecycle is the host's, not the renderer's. The screen draws
                            // `FeedScreenStore.firstScreenSurface`; here the host states the facts that decide it
                            // (a window that was really prepared, the exposure, the run's bounded maximum wait) and
                            // keeps the launch record in step with the surface that is actually drawn.
                            .onAppear {
                                prepareFirstScreen(of: association)
                                reportFirstScreenSurface(of: association)
                            }
                            .onChange(of: association.store.renderedItems.isEmpty) { _, empty in
                                if empty { prepareFirstScreen(of: association) }
                                reportFirstScreenSurface(of: association)
                            }
                            .onChange(of: association.store.work) { _, _ in
                                reportFirstScreenSurface(of: association)
                            }
                            .onChange(of: association.store.isSearching) { _, _ in
                                reportFirstScreenSurface(of: association)
                            }
                            // The measured tolerance is a **stall** bound: the clock is reset by every new card or
                            // lower layout. The loop waits the remainder of the current stall; a normal first
                            // screen keeps producing cards (one at 5 s, ten at 11.8 s), so it reaches coverage
                            // without exposing a single card. A held/trickle pipeline that stops producing ends
                            // here with the real cards on screen, never behind an opaque cover forever.
                            .task(id: association.store.firstScreenSurface) {
                                guard association.store.firstScreenSurface == .preparation else { return }
                                // One captured limit for the whole wait: the gate stored it at appearance, and a
                                // later live composition value must not renew the hold without a context reset.
                                let limit = association.store.firstScreenWaitLimit
                                while !Task.isCancelled,
                                    association.store.firstScreenSurface == .preparation {
                                    let remaining = limit - association.store.firstScreenWaited
                                    if remaining > .zero { try? await Task.sleep(for: remaining) }
                                    guard !Task.isCancelled,
                                        association.store.firstScreenSurface == .preparation else { return }
                                    guard association.store.firstScreenWaited >= limit else {
                                        continue // a card arrived during the sleep and reset the stall clock
                                    }
                                    association.store.expireFirstScreenWait()
                                    reportFirstScreenSurface(of: association)
                                    return
                                }
                            }
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
                    // V1's `onDisappear`: a filter sheet the platform dismissed (the swipe) still applies the
                    // draft it was editing. The store outlived the sheet, so the same one path runs — a clean
                    // draft writes nothing, and the buttons' own close already applied it.
                    let closedFilters = filterDismissalAppliesDraft
                    filterDismissalAppliesDraft = false
                    Task {
                        // The filter sheet's country level toggles the *selection*, so it is adopted before the
                        // draft is applied: the filter's own confirmation then rebuilds on the new selection.
                        await composition.adoptSelectionChange()
                        if closedFilters {
                            await applyDismissedFilterDraft()
                        } else {
                            // The settings' own content filters decide what every surface hides; a change there is
                            // a change to what the session applies, so it is re-applied when that surface closes.
                            await composition.reapplyReaderFilters()
                        }
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
                                                onOpenNode: { sourcesPath.append(.node($0)) },
                                                onOpenSource: { openSourceRow($0) },
                                                onClose: { popSurface() })
                                        }
                                    }
                            } else {
                                ProgressView("Abrindo o catálogo de fontes")
                            }
                        }
                    case .curatedHood:
                        curatedHood
                    case .curatedComposer:
                        CuratedComposerSheet(composition: composition, onClose: { popSurface() })
                    case .addFeed:
                        addFeedSheet
                    case .export:
                        exportSheet
                    case .filters:
                        filterSurface
                    case .bookmarkBoxes:
                        NavigationStack(path: $libraryPath) {
                            if let store = boxesStore {
                                BookmarkBoxesView(store: store,
                                    onOpenAll: { libraryPath.append(.savedAll) },
                                    onOpenBox: { libraryPath.append(.box($0)) },
                                    onClose: { popSurface() })
                                    .navigationDestination(for: LibraryRoute.self) { route in
                                        let _ = composition.association?.savedMediaRevision
                                        FeedSavedListView(
                                            read: composition.association?.readSavedArticles(inBox: Self.boxID(route)) ?? .failed,
                                            onOpen: { cardID in composition.association?.openSaved(cardID) },
                                            onRetry: { cardID in composition.association?.retrySavedMedia(cardID) })
                                            .task { composition.association?.resumeSavedMedia() }
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
                        let _ = composition.association?.savedMediaRevision
                        FeedSavedListView(read: composition.association?.readSavedArticles() ?? .failed,
                            onOpen: { cardID in composition.association?.openSaved(cardID) },
                            onRetry: { cardID in composition.association?.retrySavedMedia(cardID) })
                            .task { composition.association?.resumeSavedMedia() }
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
                    if libraryPrompt == .deleteSmartFeed || libraryPrompt == .deleteCuratedFeed {
                        Button("Cancelar", role: .cancel) { libraryPrompt = nil }
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
                            : libraryPrompt == .deleteCuratedFeed
                                ? String(localized: "O feed curado será removido. As fontes continuam selecionadas.")
                                : String(localized: "O marcador inteligente guardado com este nome será removido."))
                }
                .alert("Não foi possível atualizar", isPresented: Binding(get: { readerError != nil }, set: { if !$0 { readerError = nil } })) {
                    Button("OK") { readerError = nil }
                } message: { Text(readerError ?? "") }
                .alert("Filtro salvo", isPresented: $filterActivationFailure) {
                    Button("Tentar novamente") {
                        Task {
                            do {
                                try await composition.activateConfirmedFilter()
                                filterActivationFailure = false
                            } catch {
                                filterActivationFailure = true
                            }
                        }
                    }
                    Button("OK", role: .cancel) { filterActivationFailure = false }
                } message: {
                    Text(verbatim: String(localized:
                        "O filtro foi salvo, mas ainda não foi aplicado. Você pode tentar novamente."))
                }
            }
            // D7-A: the first open after a V1 upgrade states what was carried and what this build still
            // cannot open. Dismissing it records the presentation; the receipt keeps the counts.
            // D7-A: the notice is presented by the host's own topmost view controller, not by a SwiftUI alert.
            // Measured in the rehearsal: an alert hosted in this hierarchy is painted **behind** the reader's
            // presented controller, so the reader saw it for under a second and every tap landed on the reader's
            // own button behind it. `.task` covers the receipt that is already loaded; `.onChange` covers the one
            // that loads after this surface first appears.
            .task { presentLegacyUpgradeNoticeIfOwed() }
            .onChange(of: composition.legacyUpgradeNotice != nil) { _, _ in
                presentLegacyUpgradeNoticeIfOwed()
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
                        openFilters()
                    case .saved: savedPath.append(.saved)
                    case .bookmarkBoxes: present(.bookmarkBoxes)
                    case .collections: present(.collections)
                    case .settings: present(.settings)
                    case .curatedOnboarding:
                        present(.curatedComposer)
                    case .curatedInspector:
                        present(.curatedHood)
                    case .curatedDeletion:
                        libraryPrompt = .deleteCuratedFeed
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
            // R04: the system's memory-pressure signal keeps the reader's own band and releases the rest. It is a
            // residency fact, not a presentation change: identity, order, anchor and geometry stay.
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                Task { await composition.trimResidencyForMemoryPressure() }
            }
            .onChange(of: phase) { _, next in
                if next == .inactive {
                    // `.inactive` is the first half of leaving the screen: the foreground cadence stops here, before
                    // the app can be suspended. The session's own lifecycle work stays on `.background`.
                    Task { await composition.inactive() }
                }
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
    /// Presents the one-time V1-upgrade notice above whatever the app is showing — including presentations that
/// happen *after* the notice (the reader takes the topmost controller within a second of launch, and an alert
/// presented before it is covered by it: measured 2026-10-20, the alert was drawn at 0.3 s and gone under the
/// reader's surface by 0.9 s, with every tap landing on the reader's own button). A dedicated window at alert
/// level is above every controller presentation and survives the content swaps that happen during launch.
@MainActor
enum LegacyUpgradeNoticePresenter {
    private static var current: NoticeWindow?
    /// What the reader's acknowledgement owes: recorded once, cleared with the window. The alert's only action
    /// and the test both go through `acknowledge()`, so the end of the notice is one route.
    private static var pendingAcknowledge: (() -> Void)?

    /// The one platform act: raising the alert in the notice's own window. UIKit raises no error and calls no
    /// completion for a presentation it refuses, so the act reports its outcome on the next turn of the runloop —
    /// the first moment at which the presented controller is really the alert or really nothing. A test replaces
    /// it to exercise the refusal, which a working screen cannot stage; production uses the default below.
    static var presentAlert: @MainActor (UIViewController, UIAlertController,
        @MainActor @escaping (Bool) -> Void) -> Void = {
        host, alert, done in
        host.present(alert, animated: true)
        Task { @MainActor in done(host.presentedViewController === alert) }
    }

    static func present(title: String, message: String, onAcknowledge: @escaping () -> Void) {
        guard current == nil else { return }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let window = NoticeWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        pendingAcknowledge = onAcknowledge
        let host = NoticeHost(
            onAcknowledge: { acknowledge() },
            onRefusal: { [weak window] in
                // A window at alert level that never raised its alert is a transparent full-screen shell: it takes
                // every touch in the app, the reader's own controls included. If the alert could not be raised the
                // window must go. The notice is not recorded — only the reader's acknowledgement writes the
                // receipt — so it stays owed and is offered again on the next launch.
                window?.isHidden = true
                current = nil
                pendingAcknowledge = nil
            })
        window.rootViewController = host
        window.frame = scene.coordinateSpace.bounds
        window.isHidden = false
        current = window
        host.showNotice(title: title, message: message)
    }

    /// Takes the notice down without recording it. This is the one dismissal route: the reader's own
    /// acknowledgement above and a test that has to leave the scene as it found it both go through it.
    static func dismiss() {
        current?.isHidden = true
        current = nil
        pendingAcknowledge = nil
    }

    /// The reader's own acknowledgement: take the notice down and record what it owed. This is the alert's only
    /// action and the test's route, so "Entendi ends the notice" is exercised without a second implementation.
    static func acknowledge() {
        current?.isHidden = true
        current = nil
        let owed = pendingAcknowledge
        pendingAcknowledge = nil
        owed?()
    }

    /// The notice is informational: its alert accepts clicks while this window is not key (measured), and the
    /// reader's presenter takes the key window's topmost controller. Keeping the notice out of key ownership
    /// makes it impossible for the reader to be presented inside a window that later hides.
    final class NoticeWindow: UIWindow {
        override var canBecomeKey: Bool { false }
    }

    /// The window's content: a transparent host that raises one alert and reports the reader's own
    /// acknowledgement. Nothing here decides *when* the notice is owed; the app's receipt state does. A refused
    /// alert is reported, never assumed: the host is the only owner of the window that could block the app.
    final class NoticeHost: UIViewController {
        private let onAcknowledge: () -> Void
        private let onRefusal: () -> Void
        private var presented = false

        init(onAcknowledge: @escaping () -> Void, onRefusal: @escaping () -> Void = {}) {
            self.onAcknowledge = onAcknowledge
            self.onRefusal = onRefusal
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
        }

        func showNotice(title: String, message: String) {
            guard !presented else { return }
            presented = true
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "Entendi"), style: .cancel) { [weak self] _ in
                self?.onAcknowledge()
            })
            LegacyUpgradeNoticePresenter.presentAlert(self, alert) { [weak self] isUp in
                guard let self, !isUp else { return }
                self.presented = false
                self.onRefusal()
            }
        }
    }
}

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
            /// returns to. The site presentation is made from it too: SFSafariViewController is presented
            /// modally, as Apple requires, never embedded.
            static func topmost() -> UIViewController? {
                let windows = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap(\.windows)
                var controller = windows.first { $0.isKeyWindow }?.rootViewController
                while let presented = controller?.presentedViewController { controller = presented }
                return controller
            }
        }

        @MainActor
        final class Coordinator: NSObject, SFSafariViewControllerDelegate {
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
            /// The site page is its own modal presentation. Apple requires SFSafariViewController to be
            /// presented, never embedded in another controller's hierarchy; the text page's hosting controller
            /// cannot host it. The site therefore covers the reader's text page and ends the reader when its own
            /// close control reports back — the product's "site replaces the text; closing returns to the feed".
            private var site: SFSafariViewController?
            private var siteURL: URL?
            /// A site presentation attempt is in flight; one at a time, whatever re-renders.
            private var siteRaising = false
            /// The site the app state asks for. A retry only belongs to this request; closing the reader or
            /// changing page invalidates it.
            private var requestedSite: URL?
            /// The site whose attempts were exhausted. It blocks render-driven retries for that same request;
            /// clearing the request (close, local page, a different site) clears it.
            private var refusedSite: URL?
            /// One site presentation chain at a time: a render during an attempt or its pending retry must not
            /// start a second budget. Only the chain itself clears this (success, exhaustion, teardown).
            private var sitePending = false
            /// Bumped by every teardown: a pending retry that captured an older generation is dropped.
            private var siteGeneration = 0
            /// The one platform act that raises the site page. It is a seam for the same reason as `Presentation`:
            /// a test can see the modal presentation and its presenter without a Safari view service. Production
            /// presents with the platform's own modal presentation, as Apple requires.
            typealias SiteAct = (SFSafariViewController, URL, UIViewController,
                @escaping (Bool) -> Void) -> Void
            private let raiseSite: SiteAct

            init(platform: Presentation,
                reader: @escaping (ReaderPage, @escaping () -> Void) -> AnyView,
                onFinish: @escaping () -> Void,
                raiseSite: @escaping SiteAct = { safari, _, presenter, done in
                    presenter.present(safari, animated: true)
                    // A refused presentation leaves no error; where the controller ended up is its account.
                    done(presenter.presentedViewController === safari)
                }) {
                self.platform = platform
                self.reader = reader
                self.onFinish = onFinish
                self.raiseSite = raiseSite
                super.init()
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
                switch page {
                case .site(let url):
                    requestedSite = url
                    showSite(url)
                case .local:
                    requestedSite = nil
                    refusedSite = nil
                    showLocal(page)
                }
            }

            /// The text page: the reader's own hosting controller, presented full screen.
            private func showLocal(_ page: ReaderPage) {
                // The local page and the site never coexist: a page the chrome asks for replaces the one up.
                dismissSite()
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

            /// The site page: SFSafariViewController presented modally with the default style, as Apple
            /// requires, from the surface that asked for the reader. It is not a child of the reader's hosting
            /// controller and the text page is taken down while it is up — the site replaces the text. Its own
            /// close control reports through the delegate; finishing ends the reader and returns to the surface
            /// that opened it. Playback lives in the composition, so audio and system controls continue.
            private func showSite(_ url: URL, tries: Int? = nil, retry: Bool = false) {
                let tries = tries ?? Self.presentationAttempts
                if refusedSite != url { refusedSite = nil }
                guard refusedSite != url else { return }
                if site != nil, siteURL == url { return }
                if !retry, sitePending { return }
                dismissSite()
                // Presenting from the reader that is already up keeps the two presentations sequential: UIKit
                // refuses a present made while a dismissal is in flight, so the text page is not taken down
                // first. It stays underneath, invisible under Safari; the reader's own dismissal happens after
                // Safari reports its close, through `onFinish` → `dismissReader`.
                guard let presenter = presented ?? WindowReaderPresentation.topmost() else { return }
                let configuration = SFSafariViewController.Configuration()
                configuration.entersReaderIfAvailable = false
                let controller = SFSafariViewController(url: url, configuration: configuration)
                controller.delegate = self
                controller.dismissButtonStyle = .close
                controller.preferredControlTintColor = .tintColor
                site = controller
                siteURL = url
                sitePending = true
                raise(controller, url, presenter, tries: tries)
            }

            /// The site's presentation is made on the platform's own turn and reports whether it really went up.
            /// A refusal raises no error and calls no completion, so a page the chrome asks for is attempted
            /// again — bounded, on the platform's own report — instead of being stranded behind a stale `site`.
            private func raise(_ controller: SFSafariViewController, _ url: URL,
                _ presenter: UIViewController, tries: Int) {
                guard tries > 0, !siteRaising, site === controller, siteURL == url else { return }
                siteRaising = true
                Task { @MainActor in
                    guard siteRaising, site === controller else {
                        siteRaising = false
                        return
                    }
                    raiseSite(controller, url, presenter) { [weak self] isUp in
                        guard let self, self.siteRaising else { return }
                        self.siteRaising = false
                        guard self.site === controller, self.siteURL == url else { return }
                        guard !isUp else {
                            self.sitePending = false
                            return
                        }
                        self.site = nil
                        self.siteURL = nil
                        let generation = self.siteGeneration
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(50))
                            guard self.siteGeneration == generation, self.requestedSite == url,
                                self.site == nil, self.siteURL == nil else {
                                self.sitePending = false
                                return
                            }
                            guard tries > 1 else {
                                // The budget is spent: the reader ends through its existing finish route, so the
                                // surface it was opened from is back and the same card can ask again. No control
                                // is left visible while ignoring the URL.
                                self.refusedSite = url
                                self.sitePending = false
                                self.onFinish()
                                return
                            }
                            self.showSite(url, tries: tries - 1, retry: true)
                        }
                    }
                }
            }

            private func dismissSite() {
                siteRaising = false
                sitePending = false
                siteGeneration &+= 1
                guard let controller = site else { return }
                site = nil
                siteURL = nil
                controller.dismiss(animated: false)
            }

            /// The reader goes down when the app's state says it is no longer up, and the platform is asked to
            /// take it down: the dismissal is never inferred from the controller's own state, which reports no
            /// `presentingViewController` for a presentation that was refused.
            private func dismissReader() {
                requestedSite = nil
                refusedSite = nil
                shown = nil
                isUp = false
                isAttempting = false
                dismissSite()
                guard let controller = presented else { return }
                presented = nil
                platform.dismiss(controller)
            }

            /// Safari's own close control: the reader asked to leave the site. Safari dismisses itself after the
            /// delegate returns; the reader state is cleared only after that dismissal completes, so the host
            /// never asks a dismissing presentation to take its presenter down at the same time.
            nonisolated func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
                MainActor.assumeIsolated {
                    guard site === controller else { return }
                    // Apple's delegate contract: cleanup here, and the view controller is dismissed afterwards.
                    // No second dismissal is asked for, and the reader's state is not chained to a completion
                    // UIKit does not owe for a dismissal it is already making.
                    site = nil
                    siteURL = nil
                    siteRaising = false
                    sitePending = false
                    requestedSite = nil
                    onFinish()
                }
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
    /// U-reading: the local reading surface. The site is not content of this page: SFSafariViewController must be
    /// presented modally (Apple's contract), so `ReaderHost` presents it as its own modal and this page never
    /// embeds it.
    @ViewBuilder private func readerBody(_ page: ReaderPage, close: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            switch page {
            case .site:
                // Unreachable: the host draws only the local page and presents the site itself.
                EmptyView()
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
        // F02 §2.1: the language question starts from the device's own languages when the catalogue carries them,
        // clearly editable — a suggestion, never an imposition. It is also what makes "Começar amplo" a usable
        // entry: a first run that names no language leaves the discovery profile empty, and the feed would open on
        // the empty-selection surface instead of discovering anything.
        //
        // The seed is the answer the host proposes, so it is marked as answered even when the device language is
        // not among the offered chips: the surface then shows "Todos os idiomas" selected, and both broad actions
        // save that state instead of writing "no answer yet" over it.
        ReaderOnboardingView(
            recipe: .neutral(languages: AppComposition.suggestedLanguages(from: options.languages),
                hasLanguageAnswer: true),
            isFirstRun: true,
            previewCards: composition.onboardingPreviewCards(),
            topics: options.topics, regions: options.regions, languages: options.languages,
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
                Task {
                    // R18: the gate closes in the composition only when the answers are durable.
                    if await composition.completeFirstRun(discovery: recipe) {
                        showsOnboarding = false
                    } else {
                        readerError = String(localized: "Não foi possível salvar suas respostas. Tente novamente.")
                    }
                }
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

    /// D4: the facts the first-screen decision needs from the host — whether a selection exists at all, and the bound
    /// this run measured for one operation. Stated when the screen appears and whenever the window becomes empty
    /// again; an empty window is what makes the hold legitimate (a durable restore was never prepared on this
    /// screen). The decision itself is `FeedScreenStore.firstScreenSurface`, which the screen draws and this host's
    /// launch record reads.
    @MainActor private func prepareFirstScreen(of association: FeedAssociation) {
        association.store.noteFirstScreenAppeared(hasSources: composition.surfaceHasSources,
            maximumWait: composition.firstScreenWait)
    }

    /// The reading surface is on screen: state it where the launch record and the durability of the decision read it.
    /// Called after every fact that can settle the question (appearance, a window arrival, the work state, the
    /// search state, and the host's bounded wait).
    @MainActor private func reportFirstScreenSurface(of association: FeedAssociation) {
        association.store.reportFirstScreenSurfaceIfReading()
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
        // R18: the surface closes only when the flag is durable; a refused write is reported, not claimed.
        if composition.completeOnboarding() {
            showsOnboarding = false
        } else {
            readerError = String(localized: "Não foi possível concluir o primeiro passo. Tente novamente.")
        }
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
        let selection = composition.filterSelectionForLens()
        let filter = selection.filter
        let chips = ReaderFilterLens.chips(filter: filter, preset: selection.preset,
            presetName: nil, searchQuery: nil,
            languageNames: Dictionary(uniqueKeysWithValues: composition.filterLanguages()
                .map { ($0.languageCode, $0.displayName) }))
        if hiddenLensSignature != signature(of: filter, chips) {
            ReaderFilterLens(chips: chips, isInteractive: !selection.isPending,
                onRemove: { chip in
                    guard !selection.isPending, let removal = chip.removal else { return }
                    Task {
                        do {
                            // V1's preset chip removes the *preset*, not a filter criterion
                            // (`TaxonomyChipBar`: `setActivePreset(.everything)`). The filter's own criteria
                            // keep their own chips and stay applied.
                            if removal == .preset {
                                try await composition.applyFilter(filter, preset: .everything)
                            } else {
                                try await composition.applyFilter(filter.removing(removal),
                                    preset: composition.currentPreset)
                            }
                        } catch {
                            // R5: a raw error description is diagnostics, never the reader's copy. The failure
                            // states whether the selection was saved, so a confirmed-but-not-presented filter
                            // is never reported as "nothing happened".
                            #if DEBUG
                            print("filter removal failed: \(String(describing: error))")
                            #endif
                            readerError = (error as? ReaderFilterFailure)?.readerMessage
                                ?? String(localized: "Não foi possível aplicar o filtro agora.")
                        }
                    }
                },
                onDismiss: { hiddenLensSignature = signature(of: filter, chips) })
        }
    }

    private func signature(of filter: ReaderFilter, _ chips: [ReaderFilterChip]) -> String {
        chips.map(\.id).joined(separator: "|")
    }

    /// F12/UX12-B: opens one source's own feed from its taxonomy row. The row carries the catalogue key, which
    /// **is** the source's principal, so the destination is the reader's own resolved feed: no identity is derived
    /// here and nothing is matched by title or URL shape. The sources path is deliberately kept, so reopening the
    /// surface returns to the same node; the reader's selection is untouched. An unselected source reaches this
    /// call too (`NodeSourceRowView` draws the open control independently of the toggle): opening it shows only its
    /// own local memberships and never enables its endpoint.
    @MainActor private func openSourceRow(_ row: NodeSourceRow) {
        Task {
            var opened = false
            do {
                opened = try await composition.openSourceFeed(forKey: row.id)
            } catch {
                #if DEBUG
                print("source open failed: \(String(describing: error))")
                #endif
            }
            // Opening finishes first, then the sheet closes: the dismiss path adopts the selection again and
            // would otherwise race this transition (`replacingSession`) and refuse a legitimate tap.
            popSurface()
            if !opened {
                // A selected key the catalogue can no longer resolve is not a silent no-op: the reader asked
                // for a source and is told it could not be opened.
                readerError = String(localized: "Não foi possível abrir o feed desta fonte.")
            }
        }
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
                // The wordmark is chrome, not reading text: it names the app and the reader never reads content
                // through it. Left to scale to the accessibility categories it wrapped into three lines and took
                // the header over — measured on the Release build at `accessibility-extra-extra-extra-large`
                // (screenshot in `docs/reviews/evidence/2026-10-18-release-hitch/`), where "Feedmine" covered the
                // whole chrome row. Capped at the default body size and kept on one line; every content text on the
                // screen keeps scaling.
                Text(verbatim: "Feedmine").font(.subheadline).fontWeight(.semibold)
                    .lineLimit(1)
                    .dynamicTypeSize(.xSmall ... .large)
                // The handoff marker belongs to every filter context, including source/search, whose label
                // previously won the slot and hid the fact that the screen still shows the prior feed.
                if composition.isFilterHandoffPending {
                    Text(verbatim: String(localized: "· Feed anterior"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("reader-context-prior")
                        .accessibilityLabel(Text(verbatim: String(localized:
                            "Feed anterior; a nova seleção está sendo apresentada")))
                } else if let label = activeContextLabel {
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
        // A replacement owns the session: the control states that it is busy and is not offered as actionable,
        // instead of accepting a tap the composition cannot start.
        .disabled(composition.contextSwitchInProgress)
        .accessibilityValue(composition.contextSwitchInProgress
            ? Text("Mudando de contexto")
            : Text(verbatim: ""))
    }

    private var activeContextLabel: String? {
        switch composition.currentContext {
        case .main: return nil
        case .source:
            // One owner names the destination: the live feed, the row this session opened, or — after a relaunch —
            // the attribution the feed itself published. The chip and the cards state the same fact (F12/R1, D2).
            return composition.sourceContextDisplayName ?? String(localized: "Uma fonte")
        case .search(let context): return String(localized: "Busca: \(context.query)")
        }
    }

    #if DEBUG
    /// What this pass of the host's own body is about to draw. The host owns this branch — it holds the association
    /// and the screen's inputs — so the launch record is taken from the same values the screen reads, never from a
    /// second opinion about them: the branch read here and the branch `FeedScreen` draws are one decision.
    private var launchBranch: FeedLaunchWitness.Branch {
        guard let association = composition.association else { return .launchProgress }
        guard composition.surfaceHasSources else { return .notAWaitSurface }
        // D4: the branch is the surface the screen is drawing, read from the **one** decision both sides share
        // (`FeedScreenStore.firstScreenSurface`). Cards that are still behind the preparation cover are not on
        // screen, so they are not stated as cards; a search draws its own results surface and is not a wait.
        switch association.store.firstScreenSurface {
        case .search, .sourcesEmpty:
            return .notAWaitSurface
        case .preparation, .absence:
            return .feedAbsence(Self.absenceKind(association.store.state.work))
        case .reading:
            let rendered = association.store.renderedItems
            guard !rendered.isEmpty else {
                return .feedAbsence(Self.absenceKind(association.store.state.work))
            }
            return .cards(rendered.count)
        }
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
