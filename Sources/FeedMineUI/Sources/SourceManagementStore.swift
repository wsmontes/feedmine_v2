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
    /// Identity of the committed public catalogue snapshot used by new read operations.
    /// Nil for a fixed or absent catalogue; no periodic observer or secondary catalogue state.
    func catalogueFingerprint() async -> String?
    func languages() async throws -> [CatalogLanguageSummary]
    func sections() async throws -> [CatalogNodeSummary]
    func countries() async throws -> [CatalogNodeSummary]
    /// Re-resolve a node from its stable key before using its current child count and metadata.
    /// Default is for immutable fixture backends; the managed backend reads its installed snapshot.
    func currentNode(for node: CatalogNodeSummary) async throws -> CatalogNodeSummary?
    func children(of node: CatalogNodeSummary) async throws -> [CatalogNodeSummary]
    func breadcrumb(of node: CatalogNodeSummary) async throws -> [CatalogNodeSummary]
    func sources(in node: CatalogNodeSummary) async throws -> [CatalogSourceSummary]
    func searchSources(_ query: String) async throws -> [CatalogSourceSummary]
    func countryKeys() async throws -> [Int64: Set<String>]
    /// Each child of a node with its own keys: one call per level, never one per row.
    func childKeys(of node: CatalogNodeSummary) async throws -> [Int64: Set<String>]
    /// What the runtime observed per source (by catalog key). Absent means never attempted — never "healthy".
    func health() async throws -> [String: CatalogSourceHealth]
    func selection() async throws -> [String]
    func setSelection(_ keys: [String]) async throws
    func setEnabled(node: CatalogNodeSummary, enabled: Bool) async throws
    /// V1's "whole region on/off" over the node's *tree*: the shipped catalog places a country's sources under
    /// its topic leaves (`90_countries/algeria/sports/football`), so the reader's toggle must cover everything
    /// placed at any depth beneath the node. A backend that has no tree states what it always did.
    func setEnabledTree(node: CatalogNodeSummary, enabled: Bool) async throws
}

public extension SourceManagementBackend {
    func catalogueFingerprint() async -> String? { nil }
    func currentNode(for node: CatalogNodeSummary) async throws -> CatalogNodeSummary? { node }

    func setEnabledTree(node: CatalogNodeSummary, enabled: Bool) async throws {
        try await setEnabled(node: node, enabled: enabled)
    }
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
    /// The runtime's own health record per catalog key, as the last read saw it.
    public private(set) var health: [String: CatalogSourceHealth] = [:]
    public private(set) var query = ""
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    /// False when the shipped catalog is missing: the surface says so instead of showing an empty tree.
    public private(set) var hasCatalog = true

    @ObservationIgnored private let backend: SourceManagementBackend
    /// The latest requested level, separate from the last successfully published level. A stale
    /// async open must not mutate presentation merely because the previous level is still visible.
    @ObservationIgnored private var requestedNodeKey: String?

    public init(backend: SourceManagementBackend) { self.backend = backend }

    /// Loads what the surface shows on appear: languages, sections and the current selection.
    public func load() async {
        let fingerprint = await backend.catalogueFingerprint()
        isLoading = true
        defer { isLoading = false }
        do {
            let languages = try await backend.languages()
            let sections = try await backend.sections()
            let countries = try await backend.countries()
            let countryKeys = try await backend.countryKeys()
            let selection = Set(try await backend.selection())
            let health = try await backend.health()
            guard await backend.catalogueFingerprint() == fingerprint else { return }
            // Publish one coherent read, never a mix of fields from two catalogue revisions.
            self.languages = languages
            self.sections = sections
            self.countries = countries
            self.countryKeys = countryKeys
            self.selection = selection
            self.health = health
            hasCatalog = true
            errorMessage = nil
        } catch {
            guard await backend.catalogueFingerprint() == fingerprint else { return }
            // The catalog is an optional shipped asset; its absence is a state, not an empty list.
            hasCatalog = false
            errorMessage = String(localized: "O catálogo de fontes não está disponível.")
        }
    }

    public func search(_ text: String) async {
        query = text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { results = []; return }
        let fingerprint = await backend.catalogueFingerprint()
        guard query == text else { return }
        do {
            let found = try await backend.searchSources(trimmed)
            let current = await backend.catalogueFingerprint()
            guard query == text, current == fingerprint else { return }
            results = found
            errorMessage = nil
        } catch {
            let current = await backend.catalogueFingerprint()
            guard query == text, current == fingerprint else { return }
            errorMessage = String(localized: "Não foi possível buscar no catálogo.")
        }
    }

    public func clearSearch() async {
        query = ""
        results = []
    }

    /// An explicit open reads the *current* node by stable key and publishes its complete level.
    /// A catalogue promotion or a newer node request discards the response without retrying; the
    /// previous presentation stays intact until the reader requests another operation.
    public func open(_ node: CatalogNodeSummary) async {
        requestedNodeKey = node.key
        let fingerprint = await backend.catalogueFingerprint()
        guard requestedNodeKey == node.key else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            guard let resolved = try await backend.currentNode(for: node) else {
                let current = await backend.catalogueFingerprint()
                guard requestedNodeKey == node.key, current == fingerprint else { return }
                errorMessage = String(localized: "Não foi possível abrir esta parte do catálogo.")
                return
            }
            // A previously drawn leaf can acquire children in a newer revision.
            let children = resolved.hasChildren ? try await backend.children(of: resolved) : []
            let breadcrumb = try await backend.breadcrumb(of: resolved)
            let sources = try await backend.sources(in: resolved)
            let nodeChildKeys = children.isEmpty ? [:] : try await backend.childKeys(of: resolved)
            let health = try await backend.health()
            let current = await backend.catalogueFingerprint()
            guard requestedNodeKey == node.key, current == fingerprint else { return }
            openNode = resolved
            self.children = children
            self.breadcrumb = breadcrumb
            self.sources = sources
            self.nodeChildKeys = nodeChildKeys
            self.health = health
            errorMessage = nil
        } catch {
            let current = await backend.catalogueFingerprint()
            guard requestedNodeKey == node.key, current == fingerprint else { return }
            errorMessage = String(localized: "Não foi possível abrir esta parte do catálogo.")
        }
    }

    /// Adds or removes one source from the reader's selection. The list is refreshed from the backend, so the
    /// surface never shows an optimistic state the preferences did not accept.
    public func toggle(_ source: CatalogSourceSummary) async {
        let next = selection.contains(source.id)
            ? selection.subtracting([source.id])
            : selection.union([source.id])
        await apply(Array(next))
    }

    /// V1's "whole region on/off". A node row is a region *tree* — the catalog places a country's sources under
    /// its topic leaves — so the control covers everything placed beneath the node, not only at it. The list is
    /// refreshed from the backend, so the surface never shows an optimistic state the preferences did not accept.
    public func setEnabled(_ node: CatalogNodeSummary, enabled: Bool) async {
        let fingerprint = await backend.catalogueFingerprint()
        isLoading = true
        defer { isLoading = false }

        // Commit and confirmation are independent of the fallible catalogue presentation refresh.
        do {
            try await backend.setEnabledTree(node: node, enabled: enabled)
        } catch {
            errorMessage = String(localized: "Não foi possível alterar a seleção de fontes.")
            return
        }

        let confirmedSelection: Set<String>
        do {
            confirmedSelection = Set(try await backend.selection())
        } catch {
            errorMessage = String(localized: "A alteração foi salva, mas não foi possível atualizar a seleção exibida.")
            return
        }
        selection = confirmedSelection
        errorMessage = nil

        // Never hold a captured selection across this suspension and publish it again: another
        // accepted action may persist S2 while the source rows for S1 are being fetched.
        guard openNode?.key == node.key else { return }
        do {
            guard let resolved = try await backend.currentNode(for: node) else { return }
            let refreshedSources = try await backend.sources(in: resolved)
            let current = await backend.catalogueFingerprint()
            guard current == fingerprint, openNode?.key == node.key,
                selection == confirmedSelection else { return }
            openNode = resolved
            sources = refreshedSources
        } catch {
            let current = await backend.catalogueFingerprint()
            guard current == fingerprint, openNode?.key == node.key,
                selection == confirmedSelection else { return }
            // Only the refresh failed. The durable selection write and its confirmation succeeded.
            errorMessage = String(localized: "A seleção foi salva, mas não foi possível atualizar as fontes exibidas.")
        }
    }

    public func isSelected(_ source: CatalogSourceSummary) -> Bool { selection.contains(source.id) }

    /// The sections the open node's own sources are drawn in: V1's grouped list, by the catalog's own
    /// media kind (it has no category column), with the layout as a value.
    public var nodeSections: [NodeSourceSection] {
        NodeSourcesView.sections(sources: sources, selection: selection, health: health)
    }

    /// How many of the sources the runtime attempted are failing right now — V1's "N/M sources responding",
    /// stated only from what was actually observed.
    public var failingSourceCount: Int { health.values.filter { $0.failures > 0 }.count }

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
