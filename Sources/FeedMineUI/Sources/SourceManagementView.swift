//
// File: SourceManagementView.swift
// Module: FeedMineUI
//
// Responsibility:
// V1's `Views/SourceManagementView.swift` shell — the reader's entry into the catalog: the catalog's own
// sections with a whole-section toggle, the way into the country list, and the stated cost of the current
// selection. Copied structure, drawn from V2's values.
//
// Deliberate differences from V1, recorded in docs/v1-study/PORT_LOG.md:
// - V1 drew one flat list of every category and every source at once, with a health badge per row and an
//   OPML import/export section. V2 draws the levels the catalog actually has: this entry, then the country
//   list, then a node's own sources (all ported). The health column arrives with the runtime's own
//   availability read, and import/export belongs to T10 — neither is drawn as a dead control here.
// - V1 stated "N of M sources" from its registry's own size. V2 states the enabled count, which the
//   persisted selection makes exact; a total would double-count sources the catalog places under several
//   nodes.
//
// Does not own: reading the catalog, persisting the selection or navigation (the host does).
import SwiftUI
import FeedMineRuntime

public struct SourceManagementView: View {
    @State private var store: SourceManagementStore
    private let appearance: ReaderAppearance
    /// The levels below this one belong to the host's navigation, like every other ported surface.
    private let onOpenNode: (CatalogNodeSummary) -> Void
    private let onOpenCountries: () -> Void
    /// V1 imported OPML from this screen; the file picker is the host's, so the row reports the intent.
    private let onImport: () -> Void
    private let onClose: () -> Void
    private let importedSources: [NodeSourceRow]
    private let onExcludeImportedSource: ((NodeSourceRow) async throws -> Void)?

    public init(store: SourceManagementStore, appearance: ReaderAppearance = .standard,
        onOpenNode: @escaping (CatalogNodeSummary) -> Void, onOpenCountries: @escaping () -> Void,
        onImport: @escaping () -> Void = {}, onClose: @escaping () -> Void = {},
        importedSources: [NodeSourceRow] = [],
        onExcludeImportedSource: ((NodeSourceRow) async throws -> Void)? = nil) {
        _store = State(initialValue: store)
        self.appearance = appearance
        self.onOpenNode = onOpenNode
        self.onOpenCountries = onOpenCountries
        self.onImport = onImport
        self.onClose = onClose
        self.importedSources = importedSources
        self.onExcludeImportedSource = onExcludeImportedSource
    }

    /// V1's footer, with V2's own words for the same fact.
    public static let selectionFooter = String(localized: "Fontes desabilitadas não são consultadas na atualização. As mudanças valem a partir da próxima atualização.")

    public var body: some View {
        List {
            if isSearching {
                searchResultsSection
            } else {
                content
            }
        }
            .listStyle(Self.listStyle)
            .scrollContentBackground(.hidden)
            .background(appearance.pageBackground)
            .navigationTitle(String(localized: "Fontes"))
            // The catalogue could only be walked level by level: the store's search had no surface. A name the
            // reader already knows is now one field away.
            .searchable(text: $searchText, prompt: Text(String(localized: "Buscar fontes")))
            .task(id: searchText) {
                // A short pause so each keystroke does not become a catalogue read; a newer text cancels this one.
                // The first appearance (and every return to this screen) runs this with an empty field: it must not
                // start an intent then, or it would take the feedback lease from the catalogue load running beside it.
                let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    if !store.query.isEmpty { await store.clearSearch() }
                    searchedText = ""
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                await store.search(searchText)
                if !Task.isCancelled { searchedText = searchText }
            }
            .modifier(SourceToolErrorAlert(store: store))
            .toolbar {
                ToolbarItem(placement: ReaderToolbarPlacement.trailing) {
                    Button(String(localized: "Concluir"), action: onClose)
                        .accessibilityIdentifier("sources-done")
                }
            }
            .task { if store.sections.isEmpty && store.countries.isEmpty { await store.load() } }
    }

    #if os(iOS)
    private static let listStyle = InsetGroupedListStyle()
    #else
    private static let listStyle = InsetListStyle()
    #endif

    @State private var searchText = ""
    /// The text whose answer is on screen. While it differs from the field, the answer is still coming.
    @State private var searchedText = ""

    private var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The matching catalogue sources, each with its own toggle — the same row and the same single-key intent the
    /// node level uses, so a source turned on here is turned on everywhere.
    @ViewBuilder private var searchResultsSection: some View {
        Section {
            if searchedText != searchText {
                Text(verbatim: String(localized: "Buscando…"))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("sources-search-pending")
            } else if store.results.isEmpty {
                Text(verbatim: String(localized: "Nenhuma fonte encontrada"))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("sources-search-empty")
            }
            ForEach(searchedText == searchText ? store.results : []) { source in
                NodeSourceRowView(
                    row: NodeSourceRow(id: source.id, title: source.title, detail: source.id,
                        isSelected: store.selection.contains(source.id), health: store.health[source.id]),
                    isSelected: store.selection.contains(source.id),
                    onToggle: { Task { await store.toggle(source) } })
            }
        } header: {
            Text(verbatim: String(localized: "Resultados"))
        }
    }

    @ViewBuilder private var content: some View {
        if !importedSources.isEmpty {
            Section {
                ForEach(importedSources) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: row.title)
                        Text(verbatim: row.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("imported-source-\(row.id)")
                    .modifier(SourceExclusionMenu(row: row, onExclude: onExcludeImportedSource))
                }
            } header: {
                Text(verbatim: String(localized: "Fontes importadas"))
            }
        }
        if store.hasCatalog {
            sectionsSection
            countriesSection
            Section {
                Button(action: onImport) {
                    Label(String(localized: "Importar OPML"), systemImage: "doc.badge.plus")
                }
                .accessibilityIdentifier("sources-import")
            }
            selectionSection
        } else {
            Section {
                Label(String(localized: "O catálogo de fontes não está disponível."),
                    systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("catalog-unavailable")
            }
        }
    }

    @ViewBuilder private var sectionsSection: some View {
        if !store.sections.isEmpty {
            Section {
                ForEach(store.sections) { node in
                    NodeChildRow(child: node, isEnabled: store.isNodeEnabled(node),
                        onOpen: { onOpenNode(node) },
                        onToggle: { enabled in Task { await store.setEnabled(node, enabled: enabled) } })
                }
            } header: {
                Label(verbatim: "\(String(localized: "Seções")) (\(store.sections.count))",
                    systemImage: "square.grid.2x2")
            }
        }
    }

    @ViewBuilder private var countriesSection: some View {
        Section {
            Button {
                onOpenCountries()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "globe.americas.fill")
                        .font(.title3)
                        .foregroundStyle(appearance.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: String(localized: "Todos os países"))
                            .font(.body)
                        Text(verbatim: Self.countryCountText(store.countries.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sources-open-countries")
        }
    }

    @ViewBuilder private var selectionSection: some View {
        Section {
            HStack {
                Text(verbatim: String(localized: "Habilitadas"))
                Spacer()
                Text(verbatim: "\(store.selection.count)")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("sources-enabled-count")
            }
            if !store.health.isEmpty {
                // V1's health summary ("N/M sources responding"), stated from what the runtime observed.
                HStack {
                    Text(verbatim: String(localized: "Fontes com falha"))
                    Spacer()
                    Text(verbatim: "\(store.failingSourceCount)/\(store.health.count)")
                        .foregroundStyle(store.failingSourceCount > 0 ? .red : .secondary)
                        .accessibilityIdentifier("sources-failing-count")
                }
            }
        } footer: {
            Text(verbatim: Self.selectionFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    static func countryCountText(_ count: Int) -> String {
        String(localized: "\(count) países")
    }
}

private extension Label where Title == Text, Icon == Image {
    init(verbatim text: String, systemImage: String) {
        self.init { Text(verbatim: text) } icon: { Image(systemName: systemImage) }
    }
}

/// The source tools' one error surface. `SourceManagementStore` already stated why a toggle, a search or an
/// opening failed, but none of the source screens drew it: a refused toggle just snapped back. Each screen of the
/// stack carries this, because an alert attached to a screen that is not on top is not presented.
struct SourceToolErrorAlert: ViewModifier {
    let store: SourceManagementStore

    func body(content: Content) -> some View {
        content.alert(String(localized: "Não foi possível concluir"), isPresented: Binding(
            get: { store.errorMessage != nil }, set: { if !$0 { store.dismissError() } })) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(verbatim: store.errorMessage ?? "")
        }
    }
}
