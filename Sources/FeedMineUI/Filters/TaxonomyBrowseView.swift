// File: TaxonomyBrowseView.swift
// Module: FeedMineUI
// Owns: V1's topic browser — drill-down with checkboxes, a root-level search with breadcrumbs, and the
//       "All in this category" row. Copied from `Views/TaxonomyBrowseView.swift`.
// Does not own: the tree (a backend reads it), the selection (the filter draft holds it: V1's `toggleNode`
// selected a *filter criterion*, never a source) or navigation (the host presents this surface).

import SwiftUI
import FeedMineRuntime

/// What the topic browser needs from its backend: values only, one level at a time.
public protocol TaxonomyTreeBackend: Sendable {
    func rootNode() async throws -> CatalogNodeSummary
    func children(of node: CatalogNodeSummary) async throws -> [CatalogNodeSummary]
    func breadcrumb(of node: CatalogNodeSummary) async throws -> [CatalogNodeSummary]
    func search(_ query: String) async throws -> [CatalogNodeSummary]
}

/// One drawn row: the tree value plus whether the reader's draft selected it.
public struct TaxonomyNodeRow: Hashable, Sendable, Identifiable {
    public let id: Int64
    /// The catalog key: the filter draft stores keys, so a selected topic survives a renumbered catalog.
    public let key: String
    public let name: String
    public let feedCount: Int
    public let hasChildren: Bool
    public let isSelected: Bool
    /// The path shown under a search hit (V1 joined ancestors with " › "), empty for a plain row.
    public let breadcrumb: String

    public init(id: Int64, key: String, name: String, feedCount: Int, hasChildren: Bool, isSelected: Bool,
        breadcrumb: String = "") {
        self.id = id; self.key = key; self.name = name; self.feedCount = feedCount
        self.hasChildren = hasChildren; self.isSelected = isSelected; self.breadcrumb = breadcrumb
    }
}

public struct TaxonomyBrowseView: View {
    private let backend: TaxonomyTreeBackend
    @State private var store: ReaderFilterStore
    private let appearance: ReaderAppearance
    private let onClose: () -> Void

    @State private var level: CatalogNodeSummary?
    @State private var children: [CatalogNodeSummary] = []
    @State private var breadcrumb: [CatalogNodeSummary] = []
    @State private var query = ""
    @State private var results: [CatalogNodeSummary] = []
    @State private var errorMessage: String?

    public init(backend: TaxonomyTreeBackend, filterStore: ReaderFilterStore,
        appearance: ReaderAppearance = .standard, onClose: @escaping () -> Void = {}) {
        self.backend = backend
        _store = State(initialValue: filterStore)
        self.appearance = appearance
        self.onClose = onClose
    }

    public var body: some View {
        List {
            if !query.isEmpty {
                Section {
                    ForEach(resultRows) { row in searchRow(row) }
                } header: {
                    Text(String(localized: "Resultados")).font(.caption)
                }
            } else {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField(String(localized: "Buscar tópicos…"), text: $query)
                            .textFieldStyle(.plain)
                            .accessibilityIdentifier("search-topics")
                    }
                }
                if let level, level.id != 0 {
                    Section {
                        Button { toggle(level) } label: { allInCategoryRow(level) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("topic-node-\(level.id)")
                    }
                }
                Section {
                    ForEach(childRows) { row in childRow(row) }
                } header: {
                    if !breadcrumb.isEmpty {
                        Text(breadcrumb.map(\.name).joined(separator: " › ")).font(.caption)
                    }
                }
            }
            if let errorMessage {
                Section { Text(verbatim: errorMessage).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .listStyle(.plain)
        .background(appearance.pageBackground)
        .navigationTitle(String(localized: "Tópicos"))
        .toolbar {
            ToolbarItem(placement: ReaderToolbarPlacement.trailing) {
                Button(String(localized: "Concluir"), action: onClose)
                    .accessibilityIdentifier("topics-done")
                    .accessibilityValue("\(store.draft.taxonomyNodeIDs.count)")
            }
        }
        .task { await loadRoot() }
        .task(id: query) { await searchIfNeeded() }
    }

    // MARK: - Rows (values, so the layout is testable without a store)

    public static func rows(nodes: [CatalogNodeSummary], selected: Set<String>,
        breadcrumbs: [Int64: [String]] = [:]) -> [TaxonomyNodeRow] {
        nodes.map { node in
            TaxonomyNodeRow(id: node.id, key: node.key, name: node.name, feedCount: node.sourceCount,
                hasChildren: node.hasChildren, isSelected: selected.contains(node.key),
                breadcrumb: (breadcrumbs[node.id] ?? []).joined(separator: " › "))
        }
    }

    private var childRows: [TaxonomyNodeRow] {
        Self.rows(nodes: children, selected: selectedKeys)
    }

    private var resultRows: [TaxonomyNodeRow] {
        Self.rows(nodes: results, selected: selectedKeys, breadcrumbs: resultBreadcrumbs)
    }

    /// The draft holds catalog keys, so a selected node survives a catalog rebuild that renumbers ids.
    private var selectedKeys: Set<String> {
        Set(store.draft.taxonomyNodeIDs)
    }

    @State private var resultBreadcrumbs: [Int64: [String]] = [:]

    /// V1's row with children both toggled and navigated: the row selects, the chevron opens the level.
    @ViewBuilder private func childRow(_ row: TaxonomyNodeRow) -> some View {
        if row.hasChildren {
            HStack(spacing: 0) {
                Button { toggle(row) } label: { label(row) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("topic-node-\(row.id)")
                    .accessibilityValue(row.isSelected ? "selected" : "not selected")
                Button {
                    guard let node = children.first(where: { $0.id == row.id }) else { return }
                    Task { await open(node) }
                } label: {
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        .padding(.leading, 8).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("topic-open-\(row.id)")
            }
        } else {
            Button { toggle(row) } label: { label(row) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("topic-node-\(row.id)")
                .accessibilityValue(row.isSelected ? "selected" : "not selected")
        }
    }

    private func searchRow(_ row: TaxonomyNodeRow) -> some View {
        Button {
            toggle(row)
            query = ""
            results = []
        } label: { label(row) }
            .buttonStyle(.plain)
            .accessibilityIdentifier("taxonomy-node-\(row.id)")
            .accessibilityValue(row.isSelected ? "selected" : "not selected")
    }

    private func label(_ row: TaxonomyNodeRow) -> some View {
        HStack {
            Image(systemName: row.isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(row.isSelected ? appearance.accent : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.name)
                if !row.breadcrumb.isEmpty {
                    Text(verbatim: row.breadcrumb).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Text(verbatim: "\(row.feedCount)").font(.caption).foregroundStyle(.secondary)
        }
    }

    /// V1's "All <category>" row: the node itself as a criterion, with its own count.
    private func allInCategoryRow(_ node: CatalogNodeSummary) -> some View {
        HStack {
            Image(systemName: selectedKeys.contains(node.key) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selectedKeys.contains(node.key) ? appearance.accent : Color.secondary)
            Text(verbatim: String(localized: "Tudo em \(node.name)")).fontWeight(.medium)
            Spacer(minLength: 0)
            Text(verbatim: "\(node.sourceCount)").font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Loading and selection

    private func loadRoot() async {
        do {
            let root = try await backend.rootNode()
            level = root
            children = try await backend.children(of: root)
            breadcrumb = []
            errorMessage = nil
        } catch { errorMessage = String(localized: "Não foi possível abrir o catálogo de tópicos.") }
    }

    private func open(_ node: CatalogNodeSummary) async {
        do {
            level = node
            children = try await backend.children(of: node)
            breadcrumb = try await backend.breadcrumb(of: node)
            errorMessage = nil
        } catch { errorMessage = String(localized: "Não foi possível abrir este tópico.") }
    }

    private func searchIfNeeded() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { results = []; resultBreadcrumbs = [:]; return }
        // V1 waited 300 ms before searching; the same courtesy keeps the catalog out of the typing path.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        do {
            let hits = try await backend.search(text)
            results = hits
            var paths: [Int64: [String]] = [:]
            for hit in hits where hit.hasChildren || hit.kind == .topic {
                paths[hit.id] = (try? await backend.breadcrumb(of: hit))?.map(\.name) ?? []
            }
            resultBreadcrumbs = paths
            errorMessage = nil
        } catch { errorMessage = String(localized: "Não foi possível buscar tópicos.") }
    }

    /// Selecting a topic is a *filter criterion* change (V1's `toggleNode`), and V1's row with children both
    /// toggled and navigated: a tap selects, a disclosure opens the level.
    private func toggle(_ row: TaxonomyNodeRow) {
        var next = store.draft.taxonomyNodeIDs
        if next.contains(row.key) { next.remove(row.key) } else { next.insert(row.key) }
        store.select(taxonomyNodeIDs: next)
    }

    private func toggle(_ node: CatalogNodeSummary) {
        var next = store.draft.taxonomyNodeIDs
        if next.contains(node.key) { next.remove(node.key) } else { next.insert(node.key) }
        store.select(taxonomyNodeIDs: next)
    }
}
