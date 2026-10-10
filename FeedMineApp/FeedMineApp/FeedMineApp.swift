import SwiftUI
import FeedMineUI
import FeedMineDomain

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
        case filters
        case reader(URL)
        var id: String {
            switch self {
            case .sources: return "sources"
            case .filters: return "filters"
            case .reader(let url): return "reader:" + url.absoluteString
            }
        }
    }
    @State private var presentation: ReaderPresentation?

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $savedPath) {
                Group {
                    if let association = composition.association {
                        FeedScreen(store: association.store,
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
                .toolbar(.hidden, for: .navigationBar)
                .sheet(item: $presentation) { presentation in
                    switch presentation {
                    case .sources:
                        NavigationStack {
                            FeedSourcePicker(options: composition.sourceOptions,
                                onSearch: { query in Task { do { try await composition.searchSources(query) } catch { readerError = String(describing: error) } } },
                                onToggle: { id in Task { do { try await composition.toggleSource(id) } catch { readerError = "Não foi possível alterar a seleção de fontes." } } })
                            .toolbar { Button("Concluir") { self.presentation = nil } }
                            .task { try? await composition.searchSources("") }
                        }
                    case .filters:
                        NavigationStack {
                            FilterSheetView(applying: composition.currentFilter,
                                preset: composition.currentPreset,
                                availableCriteria: ReaderFilterCriterion.enforceable,
                                languages: composition.filterLanguages(),
                                onApply: { filter, preset in
                                    try await composition.applyFilter(filter, preset: preset)
                                },
                                onDone: { self.presentation = nil })
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
                    default:
                        // Only destinations the host declares available can be reached (T5 rule).
                        EmptyView()
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
                // T5: the reader's chrome reports destinations; the host presents the ones it implements.
                composition.onNavigate = { destination in
                    switch destination {
                    case .sources: presentation = .sources
                    case .filters:
                        presentation = .filters
                    case .bookmarkBoxes, .saved: savedPath.append(.saved)
                    default: break
                    }
                }
                await composition.launch()
            }
            .onChange(of: phase) { _, next in
                if next == .background { Task { await composition.background() } }
                if next == .active { Task { await composition.foreground() } }
            }
        }
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
