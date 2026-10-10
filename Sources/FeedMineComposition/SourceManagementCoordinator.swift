// File: SourceManagementCoordinator.swift
// Module: FeedMineComposition
// Owns: the reader-facing catalog surface — languages, the taxonomy tree, countries and source search — and
//       persisting a source selection change.
// Does not own: the catalog file format (Persistence), acquisition, or any view. UI receives values only; no
// GRDB row, reader record or URL crosses this boundary.

import Foundation
import FeedMineDomain
import FeedMinePersistence
import FeedMineRuntime

public enum SourceManagementError: Error, Equatable, Sendable {
    case catalogUnavailable
    case invalidSelection
}

public struct SourceManagementCoordinator: Sendable {
    private let catalog: LegacyCatalogReader?
    private let preferences: ReaderPreferencesStore?

    /// The catalog is an optional shipped asset: without it the surface states its absence instead of
    /// inventing an empty tree.
    public init(catalogURL: URL?, database: RuntimeDatabase?) {
        catalog = catalogURL.flatMap { try? LegacyCatalogReader(catalogURL: $0) }
        preferences = database.map(ReaderPreferencesStore.init(database:))
    }

    public var hasCatalog: Bool { catalog != nil }

    public func languages() throws -> [CatalogLanguageSummary] {
        guard let catalog else { throw SourceManagementError.catalogUnavailable }
        return try catalog.languages().map { record in
            CatalogLanguageSummary(code: record.code, displayName: Self.displayName(record.code),
                enabledSources: record.enabledSources, totalSources: record.totalSources,
                isUndeclared: record.isUndeclared)
        }
    }

    public func sections() throws -> [CatalogNodeSummary] {
        guard let catalog else { throw SourceManagementError.catalogUnavailable }
        return try catalog.sectionNodes().map(Self.summary)
    }

    public func countries(after: Int64? = nil, limit: Int = 50) throws -> CatalogPage<CatalogNodeSummary, Int64> {
        guard let catalog else { throw SourceManagementError.catalogUnavailable }
        let page = try catalog.countries(after: after, limit: limit)
        return CatalogPage(values: page.nodes.map(Self.summary), nextCursor: page.nextCursor, exhausted: page.exhausted)
    }

    public func nodes(parentID: Int64, after: Int64? = nil, limit: Int = 50) throws -> CatalogPage<CatalogNodeSummary, Int64> {
        guard let catalog else { throw SourceManagementError.catalogUnavailable }
        let page = try catalog.nodes(parentID: parentID, after: after, limit: limit)
        return CatalogPage(values: page.nodes.map(Self.summary), nextCursor: page.nextCursor, exhausted: page.exhausted)
    }

    public func breadcrumb(ofNodeID id: Int64) throws -> [CatalogNodeSummary] {
        guard let catalog else { throw SourceManagementError.catalogUnavailable }
        return try catalog.ancestors(ofNodeID: id).map(Self.summary)
    }

    /// Every country's own source keys, in one read, so a list can show each country's state. A country is a
    /// *region tree* (V1's `SourceRegistry`): the shipped catalog places its sources under the country's topic
    /// leaves, so a country's rows are everything placed at any depth beneath it.
    public func countryKeys() throws -> [Int64: Set<String>] {
        guard let catalog else { throw SourceManagementError.catalogUnavailable }
        return try catalog.sourceKeysByNodeInSubtree(kind: LegacyCatalogNodeRecord.countryKind)
            .mapValues(Set.init)
    }

    /// A node's catalog id by its stable key, for a caller that navigated by key.
    /// The keys of every child of a node, for one level's worth of state: a child is a subtree too (V1's
    /// region cascade), so its state is everything placed under it, not only at it. Values only.
    public func keysByParent(nodeID: Int64) throws -> [Int64: Set<String>] {
        guard let catalog else { throw SourceManagementError.catalogUnavailable }
        return try catalog.sourceKeysByParentInSubtree(nodeID: nodeID).mapValues(Set.init)
    }

    public func nodeByKey(_ key: String) throws -> Int64? {
        guard let catalog else { throw SourceManagementError.catalogUnavailable }
        return try catalog.node(key: key)?.id
    }

    public func searchSources(_ query: String, limit: Int = 50) throws -> [CatalogSourceSummary] {
        guard let catalog else { throw SourceManagementError.catalogUnavailable }
        return try catalog.matchingSources(query: query, limit: limit).map { record in
            CatalogSourceSummary(id: record.key, title: record.title, language: record.language,
                mediaKind: record.mediaKind, defaultEnabled: record.defaultEnabled)
        }
    }

    /// One page of a node's sources, in the catalogue's own order for that node.
    public func sources(inNode nodeID: Int64, after: CatalogSourceCursor? = nil, limit: Int = 50)
        throws -> CatalogPage<CatalogSourceSummary, CatalogSourceCursor> {
        guard let catalog else { throw SourceManagementError.catalogUnavailable }
        let page = try catalog.sources(inNode: nodeID,
            after: after.map { (sortOrder: $0.sortOrder, sourceID: $0.sourceID) }, limit: limit)
        return CatalogPage(values: page.records.map(Self.summary),
            nextCursor: page.nextCursor.map { CatalogSourceCursor(sortOrder: $0.sortOrder, sourceID: $0.sourceID) },
            exhausted: page.exhausted)
    }

    /// Enables or disables every source placed in a node — V1's "whole region on/off" — by merging the node's
    /// keys into the reader's own selection. Returns the new selection version.
    @discardableResult
    public func setEnabled(nodeID: Int64, enabled: Bool, ceiling: Int = 500) throws -> UInt64 {
        guard let catalog else { throw SourceManagementError.catalogUnavailable }
        return try apply(enabled: enabled, keys: try catalog.sourceKeys(inNode: nodeID, ceiling: ceiling))
    }

    /// V1's `SourceRegistry.setRegionEnabled`, which cascaded down the region tree: a country's sources are
    /// placed under its topic leaves (`90_countries/algeria/sports/football`) in the shipped catalog, so the
    /// reader's toggle over a region covers everything placed at any depth beneath it.
    @discardableResult
    public func setEnabledTree(nodeID: Int64, enabled: Bool, ceiling: Int = 20_000) throws -> UInt64 {
        guard let catalog else { throw SourceManagementError.catalogUnavailable }
        return try apply(enabled: enabled, keys: try catalog.sourceKeys(inSubtreeOf: nodeID, ceiling: ceiling))
    }

    /// One write for both scopes: the keys are what the catalog answered for the scope, and the reader's own
    /// selection is the only thing that changes.
    private func apply(enabled: Bool, keys: [String]) throws -> UInt64 {
        guard let preferences else { throw SourceManagementError.catalogUnavailable }
        guard let record = try preferences.load() else { throw SourceManagementError.catalogUnavailable }
        guard !keys.isEmpty else { throw SourceManagementError.invalidSelection }
        var selection = record.sourceKeys
        if enabled {
            let present = Set(selection)
            selection.append(contentsOf: keys.filter { !present.contains($0) })
        } else {
            let removing = Set(keys)
            selection.removeAll { removing.contains($0) }
            // V1 allowed zero selected sources and stated it with its own empty surface; `validate` was relaxed
            // together with that surface (`FeedSourcesEmptyStateView`), so disabling the last node is legal and
            // the reader is told what happened instead of being refused.
        }
        do { return try preferences.updateSources(selection).selectionVersion }
        catch { throw SourceManagementError.invalidSelection }
    }

    /// Persists a selection change and returns the new version, so the caller can fence a restore on it.
    /// The catalog offers keys; the reader's durable selection stores them, never catalog integers.
    @discardableResult
    public func setSelection(_ keys: [String]) throws -> UInt64 {
        guard let preferences else { throw SourceManagementError.catalogUnavailable }
        do { return try preferences.updateSources(keys).selectionVersion }
        catch { throw SourceManagementError.invalidSelection }
    }

    public func selection() throws -> [String] {
        guard let preferences else { throw SourceManagementError.catalogUnavailable }
        guard let record = try preferences.load() else { throw SourceManagementError.catalogUnavailable }
        return record.sourceKeys
    }

    /// A reader-facing label for a declared code; an undeclared bucket says so instead of pretending.
    public static func displayName(_ code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return String(localized: "Idioma não declarado") }
        let primary = String(trimmed.prefix(while: { $0 != "-" && $0 != "_" })).lowercased()
        if primary == "und" { return String(localized: "Idioma não declarado") }
        return Locale.current.localizedString(forLanguageCode: primary)?.capitalized ?? code
    }

    private static func summary(_ record: LegacyCatalogSourceRecord) -> CatalogSourceSummary {
        CatalogSourceSummary(id: record.key, title: record.title, language: record.language,
            mediaKind: record.mediaKind, defaultEnabled: record.defaultEnabled)
    }

    private static func summary(_ node: LegacyCatalogNodeRecord) -> CatalogNodeSummary {
        let kind: CatalogNodeSummary.Kind
        switch node.kind {
        case LegacyCatalogNodeRecord.sectionKind: kind = .section
        case LegacyCatalogNodeRecord.countryKind: kind = .country
        case LegacyCatalogNodeRecord.topicKind: kind = .topic
        default: kind = .other
        }
        return CatalogNodeSummary(id: node.id, key: node.key, name: node.name, kind: kind,
            sourceCount: node.sourceCount, hasChildren: node.hasChildren)
    }
}
