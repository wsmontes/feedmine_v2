// File: ReaderSearchResults.swift
// Module: FeedMineDomain
//
// Responsibility:
// R16: the typed result of one unified search — its expression's text, the scope it ran under, the completion
// identity a newer search invalidates, and results that name the real destination. The host computes it from the
// real authorities; the surface presents it and reports taps.
//
// Does not own: the authorities, navigation, acquisition or publication.
import Foundation

public enum ReaderSearchResultKind: String, Hashable, Sendable {
    case source
    case saved
    case article
}

public enum ReaderSearchDestination: Hashable, Sendable {
    /// A source: opens its context when it is one of the reader's feeds, else the source management surface.
    case source(principal: String, sourceID: SourceID?)
    /// A saved occurrence, opened as reading.
    case savedCard(PublicationCardID)
    /// A locally readable article: its published card when one exists, else the canonical occurrence's source.
    case article(cardID: PublicationCardID?, originRecordID: OriginRecordID)
}

public struct ReaderSearchResult: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: ReaderSearchResultKind
    public let title: String
    public let subtitle: String?
    public let destination: ReaderSearchDestination

    public init(id: String, kind: ReaderSearchResultKind, title: String, subtitle: String?,
        destination: ReaderSearchDestination) {
        self.id = id; self.kind = kind; self.title = title; self.subtitle = subtitle
        self.destination = destination
    }
}

/// Where the next page of local articles starts. The host maps it to its own storage cursor; the surface only
/// carries the fact that the previous page was not the whole universe.
public struct ReaderSearchCursor: Hashable, Sendable {
    public let sortDate: Date
    public let originRecordID: OriginRecordID
    public init(sortDate: Date, originRecordID: OriginRecordID) {
        self.sortDate = sortDate; self.originRecordID = originRecordID
    }
}

/// P07: which local authority could not be queried. A failed authority must never look like an empty one.
public enum ReaderSearchAuthority: String, Hashable, Sendable {
    case catalogue
    case saved
    case content
}

public struct ReaderSearchResults: Hashable, Sendable {
    public let query: String
    public let scope: ReaderSearchScope
    /// The completion's identity: a newer search invalidates this one at the surface.
    public let token: UInt64
    public let sources: [ReaderSearchResult]
    public let saved: [ReaderSearchResult]
    public let articles: [ReaderSearchResult]
    /// P07: the source page is bounded; `true` states that another eligible source exists beyond it.
    public let sourceTruncated: Bool
    /// P07: the article page is a bounded window of the canonical supply; non-nil means it can be advanced.
    public let articleContinuation: ReaderSearchCursor?
    /// P07: authorities that failed. An empty result with a failure is an error, not proof of absence.
    public let failedAuthorities: Set<ReaderSearchAuthority>

    public init(query: String, scope: ReaderSearchScope, token: UInt64,
        sources: [ReaderSearchResult], saved: [ReaderSearchResult], articles: [ReaderSearchResult],
        sourceTruncated: Bool = false, articleContinuation: ReaderSearchCursor? = nil,
        failedAuthorities: Set<ReaderSearchAuthority> = []) {
        self.query = query; self.scope = scope; self.token = token
        self.sources = sources; self.saved = saved; self.articles = articles
        self.sourceTruncated = sourceTruncated
        self.articleContinuation = articleContinuation
        self.failedAuthorities = failedAuthorities
    }

    public var isEmpty: Bool { sources.isEmpty && saved.isEmpty && articles.isEmpty }
    public var hasFailure: Bool { !failedAuthorities.isEmpty }
    public var all: [ReaderSearchResult] { sources + saved + articles }
}
