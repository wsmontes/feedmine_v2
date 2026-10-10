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

    /// A node's catalog id by its stable key, for a caller that navigated by key.
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
        guard let catalog, let preferences else { throw SourceManagementError.catalogUnavailable }
        guard let record = try preferences.load() else { throw SourceManagementError.catalogUnavailable }
        let keys = try catalog.sourceKeys(inNode: nodeID, ceiling: ceiling)
        guard !keys.isEmpty else { throw SourceManagementError.invalidSelection }
        var selection = record.sourceKeys
        if enabled {
            let present = Set(selection)
            selection.append(contentsOf: keys.filter { !present.contains($0) })
        } else {
            let removing = Set(keys)
            selection.removeAll { removing.contains($0) }
            // V2 requires at least one selected source (`ReaderPreferencesStore.validate`). V1 allowed zero and
            // said so with its own empty state; T7 must relax this *together with* that state, not before it.
            guard !selection.isEmpty else { throw SourceManagementError.invalidSelection }
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
