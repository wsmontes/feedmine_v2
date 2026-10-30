// File: ReaderShell.swift
// Module: FeedMineUI
// Owns: the reader's chrome — floating header, lens slot, search surface and toast —
//       copied from V1 `Views/FeedScreen.swift` (ZStack + measured header + `feedTopPadding`).
// Does not own: how the feed is produced, which cards are admitted, or any execution. The store states
// what is available; the shell reports intents through it and starts no work of its own.

import SwiftUI
import FeedMineDomain

/// The shell's measure of its own floating header, so content keeps exactly that much room.
/// V1 measured the header with a `PreferenceKey` and passed it down as `feedTopPadding`.
private struct ReaderHeaderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 48
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

public struct ReaderShell<Status: View, Lens: View, Content: View>: View {
    public let store: FeedScreenStore
    public let appearance: ReaderAppearance
    /// The host draws the status chip: it owns the source of its facts (V1 `CompactFeedStatus`).
    private let status: Status
    /// The lens the host can currently describe; empty until T6 can describe one.
    private let lens: Lens
    private let content: Content
    private let onManageSourceExclusions: (@MainActor () -> Void)?
    private let onRecoverHistory: (@MainActor () -> Void)?
    private let readingIsPaused: Bool

    @State private var headerHeight: CGFloat = ReaderHeaderHeightKey.defaultValue
    @State private var searchDraft: String = ""

    public init(store: FeedScreenStore, appearance: ReaderAppearance,
        onManageSourceExclusions: (@MainActor () -> Void)? = nil,
        onRecoverHistory: (@MainActor () -> Void)? = nil, readingIsPaused: Bool = false,
        @ViewBuilder status: () -> Status, @ViewBuilder lens: () -> Lens,
        @ViewBuilder content: () -> Content) {
        self.store = store
        self.appearance = appearance
        self.status = status()
        self.lens = lens()
        self.content = content()
        self.onManageSourceExclusions = onManageSourceExclusions
        self.onRecoverHistory = onRecoverHistory
        self.readingIsPaused = readingIsPaused
    }

    /// V1 `feedTopPadding` (478–481): header height, plus the search surface when it is open.
    private var contentTopPadding: CGFloat {
        max(ReaderHeaderHeightKey.defaultValue, headerHeight) + (store.isSearching ? searchBarHeight : 0)
    }

    private var searchBarHeight: CGFloat { 52 }

    public var body: some View {
        ZStack(alignment: .top) {
            appearance.pageBackground.ignoresSafeArea()

            Group {
                // P08: a search is a real surface, not only a context switch. Its results are the typed local
                // authorities' page; the feed stays behind it and a cancel restores the origin.
                if store.isSearching { ReaderSearchResultsView(store: store, appearance: appearance) }
                else { content }
            }
            .padding(.top, contentTopPadding)

            VStack(spacing: 0) {
                ReaderHeader(appearance: appearance, isSearching: store.isSearching,
                    bookmarkBoxActive: store.bookmarkBoxActive, filterCount: store.filterCount,
                    menuEntries: store.menuEntries, onToggleSearch: { store.toggleSearch() },
                    onBookmarks: { store.navigate(to: .bookmarkBoxes) },
                    onFilters: { store.navigate(to: .filters) },
                    onNavigate: { store.navigate(to: $0) },
                    onManageSourceExclusions: onManageSourceExclusions,
                    onRecoverHistory: onRecoverHistory, readingIsPaused: readingIsPaused,
                    status: { status },
                    lens: { lens })
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: ReaderHeaderHeightKey.self, value: proxy.size.height)
                    })
                if store.isSearching { searchBar }
            }
            .onPreferenceChange(ReaderHeaderHeightKey.self) { height in
                // The chrome's own size only — never a signal from production.
                if abs(height - headerHeight) > 0.5 { headerHeight = height }
            }
        }
        .readerToast(store.toast, onDismiss: { store.dismissToast() })
        .onChange(of: store.searchQuery) { _, next in
            if next.isEmpty { searchDraft = "" }
        }
    }

    /// V1 `searchBar` (655–716): field, submit, and the explicit cancel that closes the surface.
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)

            TextField(String(localized: "Adicionar um termo · use -termo para excluir"),
                text: $searchDraft)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit { store.submitSearch(searchDraft) }
                .accessibilityIdentifier("reader-search-field")

            Button(String(localized: "Cancelar")) { store.cancelSearch() }
                .font(.subheadline)
                .accessibilityIdentifier("reader-search-cancel")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        // No container identifier: an identifier on the container overrides its children's, which made
        // the field and the cancel button unreachable (measured 2026-10-09 in the UI test).
        .accessibilityElement(children: .contain)
    }
}

/// P08: the typed page the host computed, presented under the search bar. It starts no work: scope, selection,
/// pagination and retry are reported to the host; the store only holds the page and its completion token.
private struct ReaderSearchResultsView: View {
    let store: FeedScreenStore
    let appearance: ReaderAppearance

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker(String(localized: "Buscar em"), selection: Binding(
                    get: { store.searchScope },
                    set: { store.setSearchScope($0) })) {
                    Text(String(localized: "Tudo")).tag(ReaderSearchScope.both)
                    Text(String(localized: "Fontes")).tag(ReaderSearchScope.sources)
                    Text(String(localized: "Conteúdo")).tag(ReaderSearchScope.contents)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("reader-search-scope")

                if store.isSearchingResults, store.searchResults == nil {
                    ProgressView(String(localized: "Buscando…"))
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if store.searchResultsFailed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "Não foi possível buscar agora"))
                        Button(String(localized: "Tentar novamente")) { store.requestSearchAgain() }
                            .accessibilityIdentifier("reader-search-retry")
                    }
                } else if let results = store.searchResults {
                    if results.isEmpty {
                        Text(String(localized: "Nenhum resultado"))
                            .foregroundStyle(.secondary)
                    }
                    section(String(localized: "Fontes"), results.sources)
                    section(String(localized: "Salvos"), results.saved)
                    section(String(localized: "Conteúdo"), results.articles)
                    if results.hasFailure {
                        Text(String(localized: "Parte dos resultados não pôde ser lida"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if results.sourceTruncated {
                        Button(String(localized: "Carregar mais fontes")) { store.loadMoreSources() }
                            .disabled(store.isSearchingResults)
                            .accessibilityIdentifier("reader-search-more-sources")
                    }
                    if results.articleContinuation != nil {
                        Button(String(localized: "Carregar mais")) { store.loadMoreSearchResults() }
                            .disabled(store.isSearchingResults)
                            .accessibilityIdentifier("reader-search-more")
                    }
                } else {
                    Text(String(localized: "Digite um termo para buscar"))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(FeedDesignTokens.Spacing.page)
        }
        .background(appearance.pageBackground)
        .accessibilityIdentifier("reader-search-results")
    }

    @ViewBuilder
    private func section(_ title: String, _ results: [ReaderSearchResult]) -> some View {
        if !results.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                ForEach(results) { result in
                    Button { store.selectSearchResult(result) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title).foregroundStyle(.primary)
                            if let subtitle = result.subtitle, !subtitle.isEmpty {
                                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("reader-search-result-\(result.id)")
                }
            }
        }
    }
}
