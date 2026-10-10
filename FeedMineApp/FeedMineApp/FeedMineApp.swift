import SwiftUI
import FeedMineUI
import FeedMineDomain

@main
struct FeedMineApp: App {
    @State private var composition = AppComposition()
    /// U1-C: one typed destination model for the destinations that actually exist today. No
    /// booleans per future screen and no placeholder routes for U2–U4 work.
    @State private var presentation: ReaderPresentation?
    /// U2: saved articles are pushed onto the existing navigation stack (they are a screen, not a
    /// sheet) so presenting the reader from a row keeps the list underneath.
    @State private var savedPath: [ReaderDestination] = []
    @State private var searchQuery = ""
    @State private var readerError: String?
    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private enum ReaderDestination: Hashable {
        case saved
    }

    /// U1/U2: one sheet presentation for every modal surface, so a second sheet modifier can never
    /// shadow the first. The reader's URL was resolved by the composition, never by a view.
    private enum ReaderPresentation: Identifiable {
        case sources
        case reader(URL)
        var id: String {
            switch self {
            case .sources: return "sources"
            case .reader(let url): return "reader:" + url.absoluteString
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $savedPath) {
            Group {
                if let association = composition.association {
                    FeedScreen(store: association.store)
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
            .navigationTitle("FeedMine")
            // U1-D: at accessibility text sizes a large title clips on a phone (observed as
            // "FeedMir" in the AX5 screenshot). The inline title stays legible and VoiceOver
            // still reads the product name in full.
            .navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .automatic)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu("Feed") {
                        Button("Principal") { switchContext(.main) }
                        ForEach(composition.feeds, id: \.sourceID) { feed in
                            Button(feed.displayName) { switchContext(.source(feed.sourceID)) }
                        }
                    }.accessibilityIdentifier("reader-contexts")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Salvos") { savedPath.append(.saved) }.accessibilityIdentifier("reader-saved")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fontes") { presentation = .sources }.accessibilityIdentifier("reader-sources")
                }
                ToolbarItem(placement: .bottomBar) {
                    TextField("Buscar no conteúdo local", text: $searchQuery)
                        .accessibilityIdentifier("reader-local-search")
                        .onSubmit { if let query = SearchContext(query: searchQuery) { switchContext(.search(query)) } }
                }
            }
            .sheet(item: $presentation) { presentation in
                switch presentation {
                case .sources:
                    NavigationStack {
                        FeedSourcePicker(options: composition.sourceOptions,
                            onSearch: { query in Task { do { try await composition.searchSources(query) } catch { readerError = String(describing: error) } } },
                            onToggle: { id in Task { do { try await composition.toggleSource(id) } catch { readerError = "Mantenha ao menos uma fonte selecionada." } } })
                        .toolbar { Button("Concluir") { self.presentation = nil } }
                        .task { try? await composition.searchSources("") }
                    }
                case .reader(let url):
                    InAppBrowser(url: url)
                }
            }
            .navigationDestination(for: ReaderDestination.self) { destination in
                switch destination {
                case .saved:
                    FeedSavedListView(articles: composition.association?.savedArticles() ?? [],
                        onOpen: { cardID in composition.association?.openSaved(cardID) })
                }
            }
            .alert("Não foi possível atualizar", isPresented: Binding(get: { readerError != nil }, set: { if !$0 { readerError = nil } })) {
                Button("OK") { readerError = nil }
            } message: { Text(readerError ?? "") }
            }
            .task {
                // U2: the reader stays in the app. The composition resolves the frozen target and
                // hands the URL here; no URL ever comes from a view.
                composition.onExternalURL = { url in presentation = .reader(url) }
                await composition.launch()
            }
            .onChange(of: phase) { _, next in
                if next == .background { Task { await composition.background() } }
                if next == .active { Task { await composition.foreground() } }
            }
        }
    }
    private func switchContext(_ request: FeedContextRequest) {
        Task { do { try await composition.selectContext(request) } catch { readerError = String(describing: error) } }
    }
}
