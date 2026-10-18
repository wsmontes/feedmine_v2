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

public struct ReaderSearchResults: Hashable, Sendable {
    public let query: String
    public let scope: ReaderSearchScope
    /// The completion's identity: a newer search invalidates this one at the surface.
    public let token: UInt64
    public let sources: [ReaderSearchResult]
    public let saved: [ReaderSearchResult]
    public let articles: [ReaderSearchResult]

    public init(query: String, scope: ReaderSearchScope, token: UInt64,
        sources: [ReaderSearchResult], saved: [ReaderSearchResult], articles: [ReaderSearchResult]) {
        self.query = query; self.scope = scope; self.token = token
        self.sources = sources; self.saved = saved; self.articles = articles
    }

    public var isEmpty: Bool { sources.isEmpty && saved.isEmpty && articles.isEmpty }
    public var all: [ReaderSearchResult] { sources + saved + articles }
}
