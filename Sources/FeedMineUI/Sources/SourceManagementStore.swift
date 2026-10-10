// File: SourceManagementStore.swift
// Module: FeedMineUI
// Owns: the reader's source-management surface as observable values plus the intents that change it.
// Does not own: reading the catalog, persisting a selection or any execution — a backend (Composition)
// implements the protocol below, so UI never imports persistence or a connector.

import Foundation
import Observation
import FeedMineRuntime

/// What the source surface needs from its backend. Every method is async and may throw: the store turns a
/// failure into a stated message instead of leaving the surface silently empty.
public protocol SourceManagementBackend: Sendable {
    func languages() async throws -> [CatalogLanguageSummary]
    func sections() async throws -> [CatalogNodeSummary]
    func countries() async throws -> [CatalogNodeSummary]
    func children(of node: CatalogNodeSummary) async throws -> [CatalogNodeSummary]
    func breadcrumb(of node: CatalogNodeSummary) async throws -> [CatalogNodeSummary]
    func sources(in node: CatalogNodeSummary) async throws -> [CatalogSourceSummary]
    func searchSources(_ query: String) async throws -> [CatalogSourceSummary]
    func countryKeys() async throws -> [Int64: Set<String>]
    /// Each child of a node with its own keys: one call per level, never one per row.
    func childKeys(of node: CatalogNodeSummary) async throws -> [Int64: Set<String>]
    func selection() async throws -> [String]
    func setSelection(_ keys: [String]) async throws
    func setEnabled(node: CatalogNodeSummary, enabled: Bool) async throws
}

@MainActor
@Observable
public final class SourceManagementStore {
    public private(set) var languages: [CatalogLanguageSummary] = []
    public private(set) var sections: [CatalogNodeSummary] = []
    public private(set) var countries: [CatalogNodeSummary] = []
    /// Children of the node the reader opened, with its breadcrumb.
    public private(set) var openNode: CatalogNodeSummary?
    public private(set) var children: [CatalogNodeSummary] = []
    public private(set) var breadcrumb: [CatalogNodeSummary] = []
    public private(set) var sources: [CatalogSourceSummary] = []
    public private(set) var results: [CatalogSourceSummary] = []
    /// Selected catalog keys, exactly as the reader's preferences store them.
    public private(set) var selection: Set<String> = []
    /// Every country's own keys, so a country row can state whether all of its sources are selected.
    public private(set) var countryKeys: [Int64: Set<String>] = [:]
    /// The keys of the open node's children, read with the level so a sub-node row can state its own state.
    public private(set) var nodeChildKeys: [Int64: Set<String>] = [:]
    public private(set) var query = ""
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    /// False when the shipped catalog is missing: the surface says so instead of showing an empty tree.
    public private(set) var hasCatalog = true

    @ObservationIgnored private let backend: SourceManagementBackend

    public init(backend: SourceManagementBackend) { self.backend = backend }

    /// Loads what the surface shows on appear: languages, sections and the current selection.
    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            languages = try await backend.languages()
            sections = try await backend.sections()
            countries = try await backend.countries()
            countryKeys = try await backend.countryKeys()
            selection = Set(try await backend.selection())
            hasCatalog = true
            errorMessage = nil
        } catch {
            // The catalog is an optional shipped asset; its absence is a state, not an empty list.
            hasCatalog = false
            errorMessage = String(localized: "O catálogo de fontes não está disponível.")
        }
    }

    public func search(_ text: String) async {
        query = text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { results = []; return }
        do { results = try await backend.searchSources(trimmed); errorMessage = nil }
        catch { errorMessage = String(localized: "Não foi possível buscar no catálogo.") }
    }

    public func clearSearch() async {
        query = ""
        results = []
    }

    /// Opens a node: its children become the visible level and its sources become the list underneath.
    public func open(_ node: CatalogNodeSummary) async {
        isLoading = true
        defer { isLoading = false }
        do {
            openNode = node
            children = node.hasChildren ? try await backend.children(of: node) : []
            breadcrumb = try await backend.breadcrumb(of: node)
            sources = try await backend.sources(in: node)
            nodeChildKeys = children.isEmpty ? [:] : try await backend.childKeys(of: node)
            errorMessage = nil
        } catch { errorMessage = String(localized: "Não foi possível abrir esta parte do catálogo.") }
    }

    /// Adds or removes one source from the reader's selection. The list is refreshed from the backend, so the
    /// surface never shows an optimistic state the preferences did not accept.
    public func toggle(_ source: CatalogSourceSummary) async {
        let next = selection.contains(source.id)
            ? selection.subtracting([source.id])
            : selection.union([source.id])
        await apply(Array(next))
    }

    /// V1's "whole region on/off".
    public func setEnabled(_ node: CatalogNodeSummary, enabled: Bool) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await backend.setEnabled(node: node, enabled: enabled)
            selection = Set(try await backend.selection())
            /* Refresh the node's own rows so their checkmarks follow the change. */
            if openNode == node { sources = try await backend.sources(in: node) }
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Não foi possível alterar a seleção de fontes.")
        }
    }

    public func isSelected(_ source: CatalogSourceSummary) -> Bool { selection.contains(source.id) }

    /// The sections the open node's own sources are drawn in: V1's grouped list, by the catalog's own
    /// media kind (it has no category column), with the layout as a value.
    public var nodeSections: [NodeSourceSection] {
        NodeSourcesView.sections(sources: sources, selection: selection)
    }

    /// Whether a node is enabled: it has sources and every one of them is selected. A node the catalog placed
    /// no source under is never reported as enabled (V1's `isRegionEnabled` had the same rule by accident of
    /// an empty list).
    public func isNodeEnabled(_ node: CatalogNodeSummary) -> Bool {
        let keys = countryKeys[node.id] ?? nodeChildKeys[node.id] ?? []
        return !keys.isEmpty && keys.allSatisfy(selection.contains)
    }

    private func apply(_ keys: [String]) async {
        do {
            try await backend.setSelection(keys)
            selection = Set(try await backend.selection())
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Não foi possível alterar a seleção de fontes.")
        }
    }
}
