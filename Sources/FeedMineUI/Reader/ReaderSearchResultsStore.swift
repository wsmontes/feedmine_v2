// File: ReaderSearchResultsStore.swift
// Module: FeedMineUI
//
// Responsibility:
// R16: the surface's half of a unified search. A completion is applied only under the token it was started with, so
// a suspended query for an older term/scope can never replace a newer one. The store runs no search and holds no
// canonical data: it presents the typed results the host computed.
//
// Does not own: the authorities, the expression, navigation or acquisition.
import Foundation
import FeedMineDomain

@MainActor
@Observable
public final class ReaderSearchResultsStore {
    public private(set) var results: ReaderSearchResults?
    public private(set) var isSearching = false
    private var token: UInt64 = 0

    public init() {}

    /// Starts a search and returns the identity its completion must carry.
    public func begin() -> UInt64 {
        token += 1
        isSearching = true
        return token
    }

    /// The identity the current page belongs to; the host carries it into continuations.
    public var currentToken: UInt64 { token }

    /// Applies a completion only if it belongs to the newest search.
    @discardableResult
    public func apply(_ completion: ReaderSearchResults) -> Bool {
        guard completion.token == token else { return false }
        results = completion
        isSearching = false
        return true
    }

    /// Installs a page that extends the current one. The same token and query/scope are required; the caller has
    /// already merged the sections (a source page replaces sources, an article page appends articles).
    @discardableResult
    public func applyAppended(_ completion: ReaderSearchResults) -> Bool {
        guard completion.token == token else { return false }
        results = completion
        isSearching = false
        return true
    }

    public func clear() {
        token += 1
        results = nil
        isSearching = false
    }
}
