// File: CatalogValues.swift
// Module: FeedMineRuntime
// Owns: the reader-facing catalog values — languages, taxonomy nodes, one page of either, and source summaries.
// Does not own: reading the catalog (Persistence), acquisition, persistence of a selection, or any view. UI
// imports Runtime, so these values must live here and not in Composition.

import Foundation

/// One language the catalogue declares, as the reader's sheet shows it.
public struct CatalogLanguageSummary: Hashable, Sendable, Identifiable {
    public let code: String
    public let displayName: String
    /// Enabled (selected) sources for this language, and the total the catalog holds.
    public let enabledSources: Int
    public let totalSources: Int
    /// `und`/empty: a bucket, never a choice a reader makes.
    public let isUndeclared: Bool

    public init(code: String, displayName: String, enabledSources: Int, totalSources: Int,
        isUndeclared: Bool) {
        self.code = code; self.displayName = displayName; self.enabledSources = enabledSources
        self.totalSources = totalSources; self.isUndeclared = isUndeclared
    }

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

    public init(id: Int64, key: String, name: String, kind: Kind, sourceCount: Int, hasChildren: Bool) {
        self.id = id; self.key = key; self.name = name; self.kind = kind
        self.sourceCount = sourceCount; self.hasChildren = hasChildren
    }
}

/// One page of catalog values: bounded, with a cursor and a truthful exhaustion flag. The cursor is the
/// catalogue's own position type (a node id, a placement position), never a global row number.
public struct CatalogPage<Value: Hashable & Sendable, Cursor: Hashable & Sendable>: Hashable, Sendable {
    public let values: [Value]
    public let nextCursor: Cursor?
    public let exhausted: Bool

    public init(values: [Value], nextCursor: Cursor?, exhausted: Bool) {
        self.values = values; self.nextCursor = nextCursor; self.exhausted = exhausted
    }
}

/// Placement cursor for a node's sources: `(sort_order, source_id)` in the catalogue's own order.
public struct CatalogSourceCursor: Hashable, Sendable {
    public let sortOrder: Int64
    public let sourceID: Int64

    public init(sortOrder: Int64, sourceID: Int64) {
        self.sortOrder = sortOrder
        self.sourceID = sourceID
    }
}

/// One source the catalog offers, as a row in source management shows it.
/// What the runtime observed about one source's own reachability this launch. V1 stated the same column per
/// source (`loader.healthFor`); V2 states the acquisition coordinator's own measured record instead of a
/// second probe of its own.
public struct CatalogSourceHealth: Hashable, Sendable {
    public enum State: Hashable, Sendable {
        /// The last attempt settled without an operational failure.
        case responding
        /// Consecutive failures, and the source is being retried after its backoff window (or is about to be).
        case failing(consecutive: Int)
    }

    public let state: State

    public init(state: State) { self.state = state }

    public var failures: Int {
        if case .failing(let consecutive) = state { return consecutive }
        return 0
    }
}

public struct CatalogSourceSummary: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let language: String?
    public let mediaKind: String
    public let defaultEnabled: Bool

    public init(id: String, title: String, language: String?, mediaKind: String, defaultEnabled: Bool) {
        self.id = id; self.title = title; self.language = language; self.mediaKind = mediaKind
        self.defaultEnabled = defaultEnabled
    }
}


