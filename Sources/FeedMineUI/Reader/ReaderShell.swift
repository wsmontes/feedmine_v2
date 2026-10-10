// File: ReaderShell.swift
// Module: FeedMineUI
// Owns: the reader's chrome — floating header, lens slot, search surface, clipboard banner and toast —
//       copied from V1 `Views/FeedScreen.swift` (ZStack + measured header + `feedTopPadding`).
// Does not own: how the feed is produced, which cards are admitted, or any execution. The store states
// what is available; the shell reports intents through it and starts no work of its own.

import SwiftUI

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

    @State private var headerHeight: CGFloat = ReaderHeaderHeightKey.defaultValue
    @State private var searchDraft: String = ""

    public init(store: FeedScreenStore, appearance: ReaderAppearance,
        @ViewBuilder status: () -> Status, @ViewBuilder lens: () -> Lens,
        @ViewBuilder content: () -> Content) {
        self.store = store
        self.appearance = appearance
        self.status = status()
        self.lens = lens()
        self.content = content()
    }

    /// V1 `feedTopPadding` (478–481): header height, plus the search surface when it is open.
    private var contentTopPadding: CGFloat {
        max(ReaderHeaderHeightKey.defaultValue, headerHeight) + (store.isSearching ? searchBarHeight : 0)
    }

    private var searchBarHeight: CGFloat { 52 }

    public var body: some View {
        ZStack(alignment: .top) {
            appearance.pageBackground.ignoresSafeArea()

            content
                .padding(.top, contentTopPadding)

            VStack(spacing: 0) {
                ReaderHeader(appearance: appearance, isSearching: store.isSearching,
                    bookmarkBoxActive: store.bookmarkBoxActive, filterCount: store.filterCount,
                    menuEntries: store.menuEntries, onToggleSearch: { store.toggleSearch() },
                    onBookmarks: { store.navigate(to: .bookmarkBoxes) },
                    onFilters: { store.navigate(to: .filters) },
                    onNavigate: { store.navigate(to: $0) },
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
