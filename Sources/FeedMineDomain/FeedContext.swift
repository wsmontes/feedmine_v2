//
// File: FeedContext.swift
// Module: FeedMineDomain
//
// Responsibility:
//   Describe what feed the user wants, independently of acquisition.
//
// Owns:
//   FeedContext, ContextKey, FeedContextRequest and SearchContext.
//
// Does not own:
//   URL, endpoint, connector, HTTP configuration, acquisition target, checkpoint, network status or context lifecycle.
//
// Allowed dependencies:
//   Swift standard library and Foundation value types when needed; no other FeedMine module.
//
// Architectural invariants:
//   INV-10, INV-13; ContextKey is reusable logical identity for the semantic request.
//
// Planned public surface:
//   FeedContext, ContextKey, FeedContextRequest and SearchContext. No execution API is authorized in this phase.
//
// Status:
//   Phase 1B context and editorial revision value implementation.
//

import Foundation

/// A requested logical context; equivalent requests produce equal reusable keys.
public struct FeedContext: Hashable, Codable, Sendable {
    public let request: FeedContextRequest

    public init(request: FeedContextRequest) {
        self.request = request
    }

    public var key: ContextKey {
        ContextKey(request: request)
    }
}

/// Reusable logical request identity, not a session, context instance or publication ID.
/// Search identity uses the original stored query exactly; no normalization or hashing.
public struct ContextKey: Hashable, Codable, Sendable {
    public let request: FeedContextRequest

    public init(request: FeedContextRequest) {
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
