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
    private let onClose: () -> Void

    public init(store: SourceManagementStore, appearance: ReaderAppearance = .standard,
        onOpenNode: @escaping (CatalogNodeSummary) -> Void, onOpenCountries: @escaping () -> Void,
        onClose: @escaping () -> Void = {}) {
        _store = State(initialValue: store)
        self.appearance = appearance
        self.onOpenNode = onOpenNode
        self.onOpenCountries = onOpenCountries
        self.onClose = onClose
    }

    /// V1's footer, with V2's own words for the same fact.
    public static let selectionFooter = String(localized: "Fontes desabilitadas não são consultadas na atualização. As mudanças valem a partir da próxima atualização.")

    public var body: some View {
        List { content }
            .listStyle(Self.listStyle)
            .scrollContentBackground(.hidden)
            .background(appearance.pageBackground)
            .navigationTitle(String(localized: "Fontes"))
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

    @ViewBuilder private var content: some View {
        if store.hasCatalog {
            sectionsSection
            countriesSection
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
