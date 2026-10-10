// File: ReaderMenu.swift
// Module: FeedMineUI
// Owns: the reader's overflow menu, copied from V1 `Views/FeedScreen.swift` `Menu` (556–635).
// Does not own: the flows. Each entry reports its destination; the host presents it.

import SwiftUI

public struct ReaderMenu: View {
    public let entries: [ReaderMenuEntry]
    public let appearance: ReaderAppearance
    public let onNavigate: (ReaderDestination) -> Void

    public init(entries: [ReaderMenuEntry], appearance: ReaderAppearance,
        onNavigate: @escaping (ReaderDestination) -> Void) {
        self.entries = entries
        self.appearance = appearance
        self.onNavigate = onNavigate
    }

    /// V1's grouping: after "Create Curated Feed" and after the collection block.
    private func isSeparator(after index: Int) -> Bool {
        let separatorsAfter = Set([0, 8])
        return separatorsAfter.contains(index)
    }

    public var body: some View {
        Menu {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                Button(role: entry.isDestructive ? .destructive : nil) {
                    onNavigate(entry.destination)
                } label: {
                    Label(entry.title, systemImage: entry.systemImage)
                }
                if isSeparator(after: index) { Divider() }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .readerHeaderButton(accent: appearance.accent)
        }
        .accessibilityIdentifier("more-menu")
        .accessibilityLabel(String(localized: "Mais"))
    }
}
