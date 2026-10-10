//
// File: SourceCatalogBackend.swift
// Module: FeedMineComposition
//
// Responsibility:
// The one place where the source surface's protocol (FeedMineUI) meets the catalog coordinator
// (FeedMineComposition): values in, values out, ids translated at this boundary and nowhere above it.
// The store never sees a coordinator, a reader or a database — and the coordinator never sees UI.
//
// Does not own: reading the catalog (Persistence), the selection's storage (Persistence) or any layout.
import Foundation
import FeedMineRuntime
import FeedMineUI

public struct SourceCatalogBackend: SourceManagementBackend {
    private let coordinator: SourceManagementCoordinator
    /// One page per level is enough for a reader's list; the coordinator's own cursor stays available for a
    /// paging surface that needs it (this one states what fits on screen).
    private let limit: Int
    /// What the runtime observed per source. The catalog does not know it; the acquisition coordinator does,
    /// so the app supplies it. The default states nothing — never "healthy".
    private let healthProvider: @Sendable () async -> [String: CatalogSourceHealth]

    public init(coordinator: SourceManagementCoordinator, limit: Int = 500,
        healthProvider: @escaping @Sendable () async -> [String: CatalogSourceHealth] = { [:] }) {
        self.coordinator = coordinator
        self.limit = limit
        self.healthProvider = healthProvider
    }

    public func languages() async throws -> [CatalogLanguageSummary] { try coordinator.languages() }

    public func sections() async throws -> [CatalogNodeSummary] { try coordinator.sections() }

    public func countries() async throws -> [CatalogNodeSummary] {
        try coordinator.countries(limit: limit).values
    }

    public func children(of node: CatalogNodeSummary) async throws -> [CatalogNodeSummary] {
        try coordinator.nodes(parentID: node.id, limit: limit).values
    }

    public func breadcrumb(of node: CatalogNodeSummary) async throws -> [CatalogNodeSummary] {
        try coordinator.breadcrumb(ofNodeID: node.id)
    }

    public func sources(in node: CatalogNodeSummary) async throws -> [CatalogSourceSummary] {
        try coordinator.sources(inNode: node.id, limit: limit).values
    }

    public func searchSources(_ query: String) async throws -> [CatalogSourceSummary] {
        try coordinator.searchSources(query, limit: limit)
    }

    public func countryKeys() async throws -> [Int64: Set<String>] { try coordinator.countryKeys() }

    public func childKeys(of node: CatalogNodeSummary) async throws -> [Int64: Set<String>] {
        try coordinator.keysByParent(nodeID: node.id)
    }

    public func health() async throws -> [String: CatalogSourceHealth] { await healthProvider() }

    public func selection() async throws -> [String] { try coordinator.selection() }

    public func setSelection(_ keys: [String]) async throws { _ = try coordinator.setSelection(keys) }

    public func setEnabled(node: CatalogNodeSummary, enabled: Bool) async throws {
        _ = try coordinator.setEnabled(nodeID: node.id, enabled: enabled)
    }

    public func setEnabledTree(node: CatalogNodeSummary, enabled: Bool) async throws {
        _ = try coordinator.setEnabledTree(nodeID: node.id, enabled: enabled)
    }
}
