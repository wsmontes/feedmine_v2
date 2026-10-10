// File: ReaderHeader.swift
// Module: FeedMineUI
// Owns: the floating compact header — status chip, search/bookmarks/filter/menu controls and the
//       lens slot — copied from V1 `Views/FeedScreen.swift` `compactHeader` (502–653).
// Does not own: what the controls mean. Every control reports one intent; production never reacts to
// header state (V1 lesson: "resultado de rede/preparação não abre/fecha header ou lens").

import SwiftUI

/// V1's header button: 44×44, accent-tinted circle (V1 `headerButtonStyle(accent:)`).
public struct ReaderHeaderButton: ViewModifier {
    public let accent: Color

    public func body(content: Content) -> some View {
        content
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(accent)
            .frame(width: 44, height: 44)
            .background(accent.opacity(0.1), in: Circle())
    }
}

public extension View {
    func readerHeaderButton(accent: Color) -> some View { modifier(ReaderHeaderButton(accent: accent)) }
}

public struct ReaderHeader<Status: View, Lens: View>: View {
    public let appearance: ReaderAppearance
    public let isSearching: Bool
    /// The host draws the status chip: it owns the source of its facts (V1 `CompactFeedStatus`).
    private let status: Status
    /// The lens the host can currently describe; empty when there is nothing to show.
    private let lens: Lens
    public let bookmarkBoxActive: Bool
    public let filterCount: Int
    public let menuEntries: [ReaderMenuEntry]
    public let onToggleSearch: () -> Void
    public let onBookmarks: () -> Void
    public let onFilters: () -> Void
    public let onNavigate: (ReaderDestination) -> Void

    public init(appearance: ReaderAppearance, isSearching: Bool, bookmarkBoxActive: Bool,
        filterCount: Int, menuEntries: [ReaderMenuEntry],
        onToggleSearch: @escaping () -> Void, onBookmarks: @escaping () -> Void,
        onFilters: @escaping () -> Void, onNavigate: @escaping (ReaderDestination) -> Void,
        @ViewBuilder status: () -> Status, @ViewBuilder lens: () -> Lens) {
        self.appearance = appearance
        self.isSearching = isSearching
        self.bookmarkBoxActive = bookmarkBoxActive
        self.filterCount = filterCount
        self.menuEntries = menuEntries
        self.onToggleSearch = onToggleSearch
        self.onBookmarks = onBookmarks
        self.onFilters = onFilters
        self.onNavigate = onNavigate
        self.status = status()
        self.lens = lens()
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // No identifier on the chip slot: an identifier on a container overrides the ones its
                // children declare (measured 2026-10-09 on the search bar and on this menu).
                status
                Spacer(minLength: 0)
                controls
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) { Divider().opacity(0.3) }

            lens
        }
    }

    private var controls: some View {
        HStack(spacing: 4) {
            Button(action: onToggleSearch) {
                Image(systemName: isSearching ? "magnifyingglass.circle.fill" : "magnifyingglass")
                    .contentTransition(.symbolEffect(.replace))
                    .readerHeaderButton(accent: appearance.accent)
            }
            .accessibilityIdentifier("search-button")
            .accessibilityLabel(isSearching
                ? String(localized: "Fechar busca")
                : String(localized: "Buscar"))

            Button(action: onBookmarks) {
                Image(systemName: bookmarkBoxActive ? "bookmark.fill" : "bookmark")
                    .readerHeaderButton(accent: appearance.accent)
            }
            .accessibilityIdentifier("bookmark-boxes-button")
            .accessibilityLabel(String(localized: "Salvos"))
            .overlay(alignment: .topTrailing) {
                if bookmarkBoxActive {
                    Circle().fill(appearance.accent).frame(width: 6, height: 6)
                }
            }

            Button(action: onFilters) {
                Image(systemName: "line.3.horizontal.decrease")
                    .readerHeaderButton(accent: appearance.accent)
            }
            .accessibilityIdentifier("filter-button")
            .accessibilityLabel(String(localized: "Filtros"))
            .overlay(alignment: .topTrailing) {
                if filterCount > 0 {
                    Text(verbatim: "\(filterCount)")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(appearance.accent, in: Circle())
                }
            }

            menu
        }
    }

    /// V1's ellipsis menu. Only the entries the host offered are drawn (T4's rule: no dead control).
    private var menu: some View {
        Menu {
            ForEach(Array(menuEntries.enumerated()), id: \.element.id) { index, entry in
                if entry.isDestructive {
                    Button(role: .destructive) { onNavigate(entry.destination) } label: {
                        Label(entry.title, systemImage: entry.systemImage)
                    }
                } else {
                    Button { onNavigate(entry.destination) } label: {
                        Label(entry.title, systemImage: entry.systemImage)
                    }
                }
                if index == 0 || index == 8 {
                    Divider()
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .readerHeaderButton(accent: appearance.accent)
        }
        .accessibilityIdentifier("more-menu")
        .accessibilityLabel(String(localized: "Mais"))
    }
}
