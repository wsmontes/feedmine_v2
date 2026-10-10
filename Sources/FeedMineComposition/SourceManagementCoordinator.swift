// File: SourceManagementCoordinator.swift
// Module: FeedMineComposition
// Owns: the reader-facing catalog surface — languages, the taxonomy tree, countries and source search — and
//       persisting a source selection change.
// Does not own: the catalog file format (Persistence), acquisition, or any view. UI receives values only; no
// GRDB row, reader record or URL crosses this boundary.

import Foundation
import FeedMineDomain
import FeedMinePersistence

/// One language the catalogue declares, as the reader's sheet shows it.
public struct CatalogLanguageSummary: Hashable, Sendable, Identifiable {
    public let code: String
    public let displayName: String
    /// Enabled (selected) sources for this language, and the total the catalog holds.
    public let enabledSources: Int
    public let totalSources: Int
    /// `und`/empty: a bucket, never a choice a reader makes.
    public let isUndeclared: Bool

    public var id: String { code }
    public var primarySubtag: String { String(code.prefix(while: { $0 != "-" && $0 != "_" })).lowercased() }
}

/// One taxonomy node, as the reader's browser shows it.
public struct CatalogNodeSummary: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable {
        case section
        case country
        case topic
        case other
    }

    public let id: Int64
    public let key: String
    public let name: String
    public let kind: Kind
    public let sourceCount: Int
    public let hasChildren: Bool
}

/// One page of catalog values: bounded, with a cursor and a truthful exhaustion flag.
public struct CatalogPage<Value: Hashable & Sendable>: Hashable, Sendable {
    public let values: [Value]
    public let nextCursor: Int64?
    public let exhausted: Bool
}

/// One source the catalog offers, as a row in source management shows it.
public struct CatalogSourceSummary: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let language: String?
    public let mediaKind: String
    public let defaultEnabled: Bool
}

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

    public func countries(after: Int64? = nil, limit: Int = 50) throws -> CatalogPage<CatalogNodeSummary> {
        guard let catalog else { throw SourceManagementError.catalogUnavailable }
        let page = try catalog.countries(after: after, limit: limit)
        return CatalogPage(values: page.nodes.map(Self.summary), nextCursor: page.nextCursor, exhausted: page.exhausted)
    }

    public func nodes(parentID: Int64, after: Int64? = nil, limit: Int = 50) throws -> CatalogPage<CatalogNodeSummary> {
        guard let catalog else { throw SourceManagementError.catalogUnavailable }
        let page = try catalog.nodes(parentID: parentID, after: after, limit: limit)
        return CatalogPage(values: page.nodes.map(Self.summary), nextCursor: page.nextCursor, exhausted: page.exhausted)
    }

    public func breadcrumb(ofNodeID id: Int64) throws -> [CatalogNodeSummary] {
        guard let catalog else { throw SourceManagementError.catalogUnavailable }
        return try catalog.ancestors(ofNodeID: id).map(Self.summary)
    }

    public func searchSources(_ query: String, limit: Int = 50) throws -> [CatalogSourceSummary] {
        guard let catalog else { throw SourceManagementError.catalogUnavailable }
        return try catalog.matchingSources(query: query, limit: limit).map { record in
            CatalogSourceSummary(id: record.key, title: record.title, language: record.language,
                mediaKind: record.mediaKind, defaultEnabled: record.defaultEnabled)
        }
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
