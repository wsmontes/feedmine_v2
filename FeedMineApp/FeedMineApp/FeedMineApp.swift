import SwiftUI
import FeedMineUI
import FeedMineDomain

@main
struct FeedMineApp: App {
    @State private var composition = AppComposition()
    @State private var showingSources = false
    @State private var searchQuery = ""
    @State private var readerError: String?
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            NavigationStack {
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
                    Button("Fontes") { showingSources = true }.accessibilityIdentifier("reader-sources")
                }
                ToolbarItem(placement: .bottomBar) {
                    TextField("Buscar no conteúdo local", text: $searchQuery)
                        .accessibilityIdentifier("reader-local-search")
                        .onSubmit { if let query = SearchContext(query: searchQuery) { switchContext(.search(query)) } }
                }
            }
            .sheet(isPresented: $showingSources) {
                NavigationStack {
                    FeedSourcePicker(options: composition.sourceOptions,
                        onSearch: { query in Task { do { try await composition.searchSources(query) } catch { readerError = String(describing: error) } } },
                        onToggle: { id in Task { do { try await composition.toggleSource(id) } catch { readerError = "Mantenha ao menos uma fonte selecionada." } } })
                    .toolbar { Button("Concluir") { showingSources = false } }
                    .task { try? await composition.searchSources("") }
                }
            }
            .alert("Não foi possível atualizar", isPresented: Binding(get: { readerError != nil }, set: { if !$0 { readerError = nil } })) {
                Button("OK") { readerError = nil }
            } message: { Text(readerError ?? "") }
            }
            .task { await composition.launch() }
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
