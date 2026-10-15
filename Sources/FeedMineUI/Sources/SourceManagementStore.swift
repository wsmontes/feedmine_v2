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
    /// Incremental source intent; production backend merges within ReaderPreferencesStore.database.write.
    func setSourceEnabled(_ key: String, enabled: Bool) async throws
    func setSelection(_ keys: [String]) async throws
    func setEnabled(node: CatalogNodeSummary, enabled: Bool) async throws
    /// V1's "whole region on/off" over the node's *tree*: the shipped catalog places a country's sources under
    /// its topic leaves (`90_countries/algeria/sports/football`), so the reader's toggle must cover everything
    /// placed at any depth beneath the node. A backend that has no tree states what it always did.
    func setEnabledTree(node: CatalogNodeSummary, enabled: Bool) async throws
}

private enum SourceSelectionCapabilityUnavailable: Error { case incremental }

public extension SourceManagementBackend {
    func catalogueFingerprint() async -> String? { nil }
    func setSourceEnabled(_ key: String, enabled: Bool) async throws {
        // Existing fixture backends may model absolute writes, but the real catalog backend
        // must implement the transactional incremental owner. Avoid a silent read/write fallback.
        throw SourceSelectionCapabilityUnavailable.incremental
    }
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
    // Identity is scoped to publishing observable results, never to scheduling, persistence or acquisition.
    // One monotonic sequence, with independent leases per kind of presentation.
    @ObservationIgnored private var nextPublicationID: UInt64 = 0
    @ObservationIgnored private var loadID: UInt64 = 0
    @ObservationIgnored private var searchID: UInt64 = 0
    @ObservationIgnored private var openID: UInt64 = 0
    @ObservationIgnored private var mutationID: UInt64 = 0
    @ObservationIgnored private var selectionReadID: UInt64 = 0
    @ObservationIgnored private var feedbackID: UInt64 = 0
    @ObservationIgnored private var loadingID: UInt64 = 0

    private func newID() -> UInt64 {
        nextPublicationID &+= 1
        return nextPublicationID
    }

    private func beginIntent() -> UInt64 {
        let id = newID()
        feedbackID = id
        return id
    }

    /// The only ordinary selection-publication path: read preferences after the relevant awaits.
    /// The last read to *begin* wins publication; a late, older read cannot overwrite it.
    private func publishPersistedSelection() async throws -> UInt64? {
        let id = newID()
        selectionReadID = id
        let persisted = Set(try await backend.selection())
        guard selectionReadID == id else { return nil }
        selection = persisted
        return id
    }

    public init(backend: SourceManagementBackend) { self.backend = backend }

    /// Loads what the surface shows on appear: languages, sections and the current selection.
    public func load() async {
        let id = beginIntent()
        loadID = id
        let fingerprint = await backend.catalogueFingerprint()
        guard loadID == id else { return }
        loadingID = id
        isLoading = true
        defer { if loadingID == id { isLoading = false } }
        do {
            let languages = try await backend.languages()
            let sections = try await backend.sections()
            let countries = try await backend.countries()
            let countryKeys = try await backend.countryKeys()
            let health = try await backend.health()
            let readID = newID()
            selectionReadID = readID
            let selected = Set(try await backend.selection())
            let current = await backend.catalogueFingerprint()
            guard loadID == id, selectionReadID == readID, current == fingerprint else { return }
            self.languages = languages
            self.sections = sections
            self.countries = countries
            self.countryKeys = countryKeys
            selection = selected
            self.health = health
            hasCatalog = true
            if feedbackID == id { errorMessage = nil }
        } catch {
            let current = await backend.catalogueFingerprint()
            guard loadID == id, current == fingerprint else { return }
            hasCatalog = false
            if feedbackID == id {
                errorMessage = String(localized: "O catálogo de fontes não está disponível.")
            }
        }
    }

    public func search(_ text: String) async {
        let id = beginIntent()
        searchID = id
        query = text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { results = []; return }
        let fingerprint = await backend.catalogueFingerprint()
        guard searchID == id else { return }
        do {
            let found = try await backend.searchSources(trimmed)
            let current = await backend.catalogueFingerprint()
            guard searchID == id, current == fingerprint else { return }
            results = found
            if feedbackID == id { errorMessage = nil }
        } catch {
            let current = await backend.catalogueFingerprint()
            guard searchID == id, current == fingerprint, feedbackID == id else { return }
            errorMessage = String(localized: "Não foi possível buscar no catálogo.")
        }
    }

    public func clearSearch() async {
        let id = beginIntent()
        searchID = id
        query = ""
        results = []
    }

    /// The node is resolved by key at the active revision. An obsolete or superseded
    /// answer (including its error) never replaces another operation's publication.
    public func open(_ node: CatalogNodeSummary) async {
        let id = beginIntent()
        openID = id
        let fingerprint = await backend.catalogueFingerprint()
        guard openID == id else { return }
        loadingID = id
        isLoading = true
        defer { if loadingID == id { isLoading = false } }
        do {
            guard let resolved = try await backend.currentNode(for: node) else {
                let current = await backend.catalogueFingerprint()
                guard openID == id, current == fingerprint, feedbackID == id else { return }
                errorMessage = String(localized: "Não foi possível abrir esta parte do catálogo.")
                return
            }
            let children = resolved.hasChildren ? try await backend.children(of: resolved) : []
            let breadcrumb = try await backend.breadcrumb(of: resolved)
            let sources = try await backend.sources(in: resolved)
            let nodeChildKeys = children.isEmpty ? [:] : try await backend.childKeys(of: resolved)
            let health = try await backend.health()
            let current = await backend.catalogueFingerprint()
            guard openID == id, current == fingerprint else { return }
            openNode = resolved
            self.children = children
            self.breadcrumb = breadcrumb
            self.sources = sources
            self.nodeChildKeys = nodeChildKeys
            self.health = health
            if feedbackID == id { errorMessage = nil }
        } catch {
            let current = await backend.catalogueFingerprint()
            guard openID == id, current == fingerprint, feedbackID == id else { return }
            errorMessage = String(localized: "Não foi possível abrir esta parte do catálogo.")
        }
    }

    /// A toggle changes only this key. The UI supplies a desired action, never an absolute
    /// replacement computed from an old, potentially incomplete selection.
    public func toggle(_ source: CatalogSourceSummary) async {
        await apply(key: source.id, enabled: !selection.contains(source.id))
    }

    /// A subtree intent is merged transactionally by ReaderPreferencesStore. The persisted
    /// selection is re-read AFTER any potentially slow catalogue refresh; old errors/rows lose
    /// their publication lease, but a completed write is never undone.
    public func setEnabled(_ node: CatalogNodeSummary, enabled: Bool) async {
        let id = beginIntent()
        mutationID = id
        let fingerprint = await backend.catalogueFingerprint()
        loadingID = id
        isLoading = true
        defer { if loadingID == id { isLoading = false } }

        do {
            try await backend.setEnabledTree(node: node, enabled: enabled)
        } catch {
            guard feedbackID == id else { return }
            errorMessage = String(localized: "Não foi possível alterar a seleção de fontes.")
            return
        }

        // The refresh is optional and fallible; its success says nothing about persistence.
        let visibleKey = openNode?.key
        let openedLease = openID
        var refreshedNode: CatalogNodeSummary?
        var refreshedSources: [CatalogSourceSummary]?
        var refreshError = false
        if visibleKey == node.key {
            do {
                refreshedNode = try await backend.currentNode(for: node)
                if let refreshedNode { refreshedSources = try await backend.sources(in: refreshedNode) }
            } catch { refreshError = true }
        }

        let selectionRead: UInt64
        do {
            guard let read = try await publishPersistedSelection() else { return }
            selectionRead = read
        } catch {
            guard feedbackID == id else { return }
            errorMessage = String(localized: "A alteração foi salva, mas não foi possível atualizar a seleção exibida.")
            return
        }
        let current = await backend.catalogueFingerprint()
        guard mutationID == id, selectionReadID == selectionRead, openID == openedLease,
            current == fingerprint, openNode?.key == visibleKey else { return }
        if let refreshedNode, let refreshedSources {
            openNode = refreshedNode
            sources = refreshedSources
        }
        if feedbackID == id {
            errorMessage = refreshError
                ? String(localized: "A seleção foi salva, mas não foi possível atualizar as fontes exibidas.")
                : nil
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

    /// The incremental source write is atomic in ReaderPreferencesStore; only display
    /// confirmation runs asynchronously. Completion order may differ from commit order.
    private func apply(key: String, enabled: Bool) async {
        let id = beginIntent()
        mutationID = id
        do {
            try await backend.setSourceEnabled(key, enabled: enabled)
        } catch {
            guard feedbackID == id else { return }
            errorMessage = String(localized: "Não foi possível alterar a seleção de fontes.")
            return
        }
        do {
            guard try await publishPersistedSelection() != nil else { return }
            if feedbackID == id { errorMessage = nil }
        } catch {
            guard feedbackID == id else { return }
            errorMessage = String(localized: "A alteração foi salva, mas não foi possível atualizar a seleção exibida.")
        }
    }
}
