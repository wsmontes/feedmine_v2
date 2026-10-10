// File: CountriesListView.swift
// Module: FeedMineUI
// Owns: V1's country list — a toggle for every country, a total, and the way into one country's detail.
//       Copied from `Views/CountriesListScreen.swift`.
// Does not own: reading the catalog, persisting the selection (the store does) or navigation (the host does).
//
// Difference from V1, deliberate: V1 flipped its toggle optimistically and deferred the store work with
// `DispatchQueue.main.async` to let SwiftUI draw the switch. This view binds the toggle to the store's
// *accepted* selection, so a refused change never shows a state the preferences did not take.

import SwiftUI
import FeedMineRuntime

/// A country row's value, so the layout can be rendered without a store.
public struct CountryRow: Hashable, Sendable, Identifiable {
    public let id: Int64
    public let name: String
    public let slug: String
    public let flag: String
    public let feedCount: Int
    public let isEnabled: Bool

    public init(id: Int64, name: String, slug: String, flag: String, feedCount: Int, isEnabled: Bool) {
        self.id = id; self.name = name; self.slug = slug; self.flag = flag
        self.feedCount = feedCount; self.isEnabled = isEnabled
    }
}

public struct CountriesListView: View {
    @State private var store: SourceManagementStore
    private let appearance: ReaderAppearance
    private let onOpenNode: (CatalogNodeSummary) -> Void
    private let onClose: () -> Void

    public init(store: SourceManagementStore, appearance: ReaderAppearance = .standard,
        onOpenNode: @escaping (CatalogNodeSummary) -> Void, onClose: @escaping () -> Void = {}) {
        _store = State(initialValue: store)
        self.appearance = appearance
        self.onOpenNode = onOpenNode
        self.onClose = onClose
    }

    /// The rows the list draws: countries with their selection state, in the catalog's own order.
    public static func rows(countries: [CatalogNodeSummary], selection: Set<String>, keys: [Int64: Set<String>])
        -> [CountryRow] {
        countries.map { country in
            let slug = Self.slug(country)
            let countryKeys = keys[country.id] ?? []
            // The flag is a display convenience derived from the catalog's own key shape
            // (`countries/<code>`); any other shape says "unknown" with a globe instead of a wrong flag.
            let flag = country.key.hasPrefix("countries/") ? Self.flag(slug) : "🌐"
            return CountryRow(id: country.id, name: country.name, slug: slug, flag: flag,
                feedCount: country.sourceCount,
                isEnabled: !countryKeys.isEmpty && countryKeys.allSatisfy(selection.contains))
        }
    }

    public var body: some View {
        List {
            if !store.hasCatalog {
                Section {
                    Label(String(localized: "O catálogo de fontes não está disponível."),
                        systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("catalog-unavailable")
                }
            } else {
                Section {
                    HStack {
                        Label(String(localized: "Todos os países"), systemImage: "globe.americas.fill")
                            .font(.headline)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { !store.countries.isEmpty && store.countries.allSatisfy(store.isCountryEnabled) },
                            set: { enabled in Task { for country in store.countries { await store.setEnabled(country, enabled: enabled) } } }
                        ))
                        .labelsHidden()
                        .tint(.green)
                        .accessibilityIdentifier("country-toggle-all")
                        // An identifier is for a test; VoiceOver needs a name for the control it lands on.
                        .accessibilityLabel(Text(verbatim: String(localized: "Todos os países")))
                    }
                }
                Section {
                    ForEach(rows) { row in
                        CountryRowView(row: row, appearance: appearance,
                            onOpen: {
                                guard let country = store.countries.first(where: { $0.id == row.id }) else { return }
                                onOpenNode(country)
                            },
                            onToggle: { enabled in
                                guard let country = store.countries.first(where: { $0.id == row.id }) else { return }
                                Task { await store.setEnabled(country, enabled: enabled) }
                            })
                    }
                } footer: {
                    Text(verbatim: String(localized: "\(store.countries.count) países · \(totalFeeds) feeds"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("countries-footer")
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
        .background(appearance.pageBackground)
        .navigationTitle(String(localized: "Países"))
        .toolbar {
            ToolbarItem(placement: ReaderToolbarPlacement.trailing) {
                Button(String(localized: "Concluir"), action: onClose)
                    .accessibilityIdentifier("countries-done")
            }
        }
        .task { if store.languages.isEmpty && store.countries.isEmpty { await store.load() } }
    }

    private var rows: [CountryRow] { store.countryRows }

    /// The catalog key of a country node is `countries/<code>`; the code is its slug, and the flag is the
    /// regional-indicator pair for it. An unknown shape falls back to the node's own key.
    public static func slug(_ country: CatalogNodeSummary) -> String {
        let tail = country.key.split(separator: "/").last.map(String.init) ?? country.key
        return tail.lowercased()
    }

    /// A flag for exactly two ASCII letters, or a globe when the code is not that shape.
    public static func flag(_ slug: String) -> String {
        let letters = Array(slug.uppercased().unicodeScalars)
        guard letters.count == 2, letters.allSatisfy({ (65...90).contains($0.value) }) else { return "🌐" }
        let scalars = letters.compactMap { Unicode.Scalar(127_397 + $0.value) }
        return scalars.count == 2 ? String(String.UnicodeScalarView(scalars)) : "🌐"
    }

    private var totalFeeds: Int {
        store.countries.reduce(0) { $0 + $1.sourceCount }
    }
}

public struct CountryRowView: View {
    public let row: CountryRow
    public let appearance: ReaderAppearance
    public let onOpen: () -> Void
    public let onToggle: (Bool) -> Void

    public var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: row.flag).font(.title2)
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: row.name).font(.body)
                    Text(verbatim: String(localized: "\(row.feedCount) feeds"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("country-\(row.slug)")

            Toggle("", isOn: Binding(get: { row.isEnabled }, set: { onToggle($0) }))
                .labelsHidden()
                .tint(.green)
                .accessibilityIdentifier("country-toggle-\(row.slug)")
                .accessibilityLabel(Text(verbatim: row.name))
                .accessibilityValue(row.isEnabled ? "selected" : "not selected")
        }
    }
}

/// The trailing toolbar slot on each platform, so the same view compiles for iOS and macOS.
enum ReaderToolbarPlacement {
    static var trailing: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .automatic
        #endif
    }
}

public extension SourceManagementStore {
    /// The rows the country list draws, resolving each country's keys once.
    var countryRows: [CountryRow] {
        CountriesListView.rows(countries: countries, selection: selection, keys: countryKeys)
    }

    func isCountryEnabled(_ country: CatalogNodeSummary) -> Bool {
        let keys = countryKeys[country.id] ?? []
        return !keys.isEmpty && keys.allSatisfy(selection.contains)
    }
}
