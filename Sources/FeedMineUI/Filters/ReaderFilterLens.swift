// File: ReaderFilterLens.swift
// Module: FeedMineUI
// Owns: V1's filter lens — one chip per active criterion, each removing its own criterion, and a swipe that
//       hides the bar (`Views/TaxonomyChipBar.swift`, `FilterLensBar`).
// Does not own: applying the result (the host does, as an explicit transition) or the filter itself.

import SwiftUI
import FeedMineDomain
import FeedMineRuntime

/// One drawn chip: what it removes, and how it reads.
public struct ReaderFilterChip: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case preset
        case search
        case region
        case contentType
        case topic
        case language
        case mood
        case exclusions
    }

    public let id: String
    public let kind: Kind
    public let label: String
    public let systemImage: String
    /// What the host must remove: nothing for a search chip (T6's search is a context of its own).
    public let removal: ReaderFilter.Active?

    public init(id: String, kind: Kind, label: String, systemImage: String,
        removal: ReaderFilter.Active?) {
        self.id = id; self.kind = kind; self.label = label; self.systemImage = systemImage
        self.removal = removal
    }
}

public struct ReaderFilterLens: View {
    public let chips: [ReaderFilterChip]
    public let appearance: ReaderAppearance
    public let onRemove: (ReaderFilterChip) -> Void
    public let onDismiss: () -> Void

    public init(chips: [ReaderFilterChip], appearance: ReaderAppearance = .standard,
        onRemove: @escaping (ReaderFilterChip) -> Void, onDismiss: @escaping () -> Void = {}) {
        self.chips = chips
        self.appearance = appearance
        self.onRemove = onRemove
        self.onDismiss = onDismiss
    }

    public var body: some View {
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chips) { chip in
                        Button { onRemove(chip) } label: {
                            HStack(spacing: 4) {
                                Image(systemName: chip.systemImage).font(.caption2)
                                Text(verbatim: chip.label).font(.caption)
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(appearance.accent.opacity(0.1), in: Capsule())
                            .foregroundStyle(appearance.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("lens-chip-\(chip.id)")
                        .accessibilityLabel(String(localized: "Remover \(chip.label)"))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .background(.ultraThinMaterial)
            // The bar's own identity must not replace its chips': a plain identifier on this container would
            // override every `lens-chip-*` inside it (measured), so the chips stay elements of their own.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("reader-filter-lens")
            // V1 hid the bar with a swipe; the same gesture here reports the dismissal, it does not decide it.
            .gesture(DragGesture(minimumDistance: 16)
                .onEnded { value in
                    if abs(value.translation.height) > 12 || abs(value.translation.width) > 24 { onDismiss() }
                })
        }
    }

    /// V1's chips, in its order: preset, search, region, content type, topic, language, mood.
    public static func chips(filter: ReaderFilter, preset: ReaderPresetID, presetName: String? = nil,
        searchQuery: String? = nil, languageNames: [String: String] = [:],
        taxonomyNames: [String: String] = [:], regionNames: [String: String] = [:]) -> [ReaderFilterChip] {
        var chips: [ReaderFilterChip] = []
        if preset != .everything {
            chips.append(.init(id: "preset", kind: .preset, label: presetName ?? preset.identityText,
                systemImage: "sparkles", removal: .preset))
        }
        if let searchQuery, !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chips.append(.init(id: "search", kind: .search, label: searchQuery,
                systemImage: "magnifyingglass", removal: nil))
        }
        for region in filter.regionIDs.sorted() {
            chips.append(.init(id: "region-\(region)", kind: .region,
                label: regionNames[region] ?? region, systemImage: "globe.americas.fill",
                removal: .region(region)))
        }
        if filter.contentType != .all {
            chips.append(.init(id: "content-type", kind: .contentType, label: filter.contentType.rawValue,
                systemImage: filter.contentType.icon, removal: .contentType))
        }
        for node in filter.taxonomyNodeIDs.sorted() {
            chips.append(.init(id: "topic-\(node)", kind: .topic, label: taxonomyNames[node] ?? node,
                systemImage: "tag.fill", removal: .taxonomyNode(node)))
        }
        for language in filter.languages.sorted() {
            chips.append(.init(id: "language-\(language)", kind: .language,
                label: languageNames[language] ?? language, systemImage: "character.bubble.fill",
                removal: .language(language)))
        }
        if filter.mood != .all {
            chips.append(.init(id: "mood", kind: .mood, label: filter.mood.rawValue,
                systemImage: filter.mood.icon, removal: .mood))
        }
        if filter.effectiveExclusionRules != nil {
            chips.append(.init(id: "exclusions", kind: .exclusions,
                label: String(localized: "Filtros de conteúdo"), systemImage: "eye.slash",
                removal: .exclusions))
        }
        return chips
    }
}
