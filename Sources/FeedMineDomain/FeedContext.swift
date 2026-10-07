//
// File: FeedContext.swift
// Module: FeedMineDomain
//
// Responsibility:
//   Describe what feed the user wants, independently of acquisition.
//
// Owns:
//   FeedContext, FeedContextRequest and SearchContext.
//
// Does not own:
//   URL, endpoint, connector, HTTP configuration, acquisition target, checkpoint, network status or context lifecycle.
//
// Allowed dependencies:
//   Swift standard library and Foundation value types when needed; no other FeedMine module.
//
// Architectural invariants:
//   INV-10, INV-13; ContextKey is identity; FeedContextRequest is meaning.
//
// Planned public surface:
//   FeedContext, FeedContextRequest and SearchContext. No execution API is authorized in this phase.
//
// Status:
//   Phase 1B context and editorial revision value implementation.
//

import Foundation

/// A stable semantic context instance supplied with an explicit ContextKey.
/// Two contexts may request the same surface while having different keys.
public struct FeedContext: Hashable, Codable, Sendable {
    public let key: ContextKey
    public let request: FeedContextRequest

    public init(key: ContextKey, request: FeedContextRequest) {
        self.key = key
        self.request = request
    }
}

/// Meaning of the requested surface; never how content is acquired.
public enum FeedContextRequest: Hashable, Codable, Sendable {
    case main
    case source(SourceID)
    case search(SearchContext)
}

/// Original search query; trimming determines validity without normalizing stored meaning.
public struct SearchContext: Hashable, Codable, Sendable {
    public let query: String

    public init?(query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        self.query = query
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let query = try container.decode(String.self, forKey: .query)
        guard let search = Self(query: query) else {
            throw DecodingError.dataCorruptedError(forKey: .query, in: container, debugDescription: "SearchContext requires a non-whitespace query.")
        }
        self = search
    }
}
