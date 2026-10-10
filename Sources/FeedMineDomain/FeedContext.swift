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
    /// T6: a context is the whole identity, not only its surface. The defaults mean "the plain surface".
    public let preset: ReaderPresetID
    public let filter: ReaderFilter
    public let searchScope: ReaderSearchScope?

    public init(request: FeedContextRequest, preset: ReaderPresetID = .everything,
        filter: ReaderFilter = .unrestricted, searchScope: ReaderSearchScope? = nil) {
        self.request = request
        self.preset = preset
        self.filter = filter
        self.searchScope = searchScope
    }

    public init(key: ContextKey) {
        self.init(request: key.request, preset: key.preset, filter: key.filter,
            searchScope: key.searchScope)
    }

    public var key: ContextKey {
        ContextKey(request: request, preset: preset, filter: filter, searchScope: searchScope)
    }
}

/// Reusable logical request identity, not a session, context instance or publication ID.
/// Search identity uses the original stored query exactly; no normalization or hashing.
///
/// T6: the identity is the *whole* request, not just its surface — the named selection (preset), the
/// reader's normalized filter and (for a search) what it looks through. Every field has the value that
/// means "the default surface", so the unfiltered key is exactly the identity this type had before and
/// existing checkpoints keep matching. Design:
/// `docs/superpowers/specs/2026-10-09-reader-filters-and-context-identity.md` §2.
public struct ContextKey: Hashable, Codable, Sendable {
    /// Bumped only when the identity's *semantics* change; persisted identifiers carry it.
    public static let currentIdentitySchemaVersion = 1

    public let identitySchemaVersion: Int
    public let request: FeedContextRequest
    /// Which named selection the reader is on (V1's `PresetSelector`).
    public let preset: ReaderPresetID
    /// The normalized criteria; `.unrestricted` means the plain surface.
    public let filter: ReaderFilter
    /// Only meaningful for `.search`; absent (nil) everywhere else, and nil means "both".
    public let searchScope: ReaderSearchScope?

    public init(request: FeedContextRequest, preset: ReaderPresetID = .everything,
        filter: ReaderFilter = .unrestricted, searchScope: ReaderSearchScope? = nil,
        identitySchemaVersion: Int = ContextKey.currentIdentitySchemaVersion) {
        self.identitySchemaVersion = identitySchemaVersion
        self.request = request
        self.preset = preset
        self.filter = filter
        switch request {
        case .search:
            self.searchScope = searchScope ?? .both
        case .main, .source:
            // A scope outside a search is not part of any identity: it is dropped, not carried.
            self.searchScope = nil
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(request: try container.decode(FeedContextRequest.self, forKey: .request),
            preset: try container.decodeIfPresent(ReaderPresetID.self, forKey: .preset) ?? .everything,
            filter: try container.decodeIfPresent(ReaderFilter.self, forKey: .filter) ?? .unrestricted,
            searchScope: try container.decodeIfPresent(ReaderSearchScope.self, forKey: .searchScope),
            identitySchemaVersion: try container.decodeIfPresent(Int.self, forKey: .identitySchemaVersion)
                ?? ContextKey.currentIdentitySchemaVersion)
    }

    /// The surface half of the identity, as the durable checkpoint columns have always stored it.
    public var surfaceIdentity: String {
        switch request {
        case .main: "main"
        case .source(let source): "source:" + source.rawValue.uuidString
        case .search(let search): "search:" + search.query
        }
    }

    /// Canonical, deterministic identity text: the whole key, in one opaque string, independent of the
    /// order the reader selected equivalent sets in. This is what durable identifiers must store so that
    /// returning to an identical context recovers its own history (Codex review, 2026-10-09).
    public var canonicalIdentity: String {
        var parts: [String] = ["v\(identitySchemaVersion)", surfaceIdentity]
        parts.append("preset=" + preset.identityText)
        parts.append("filter=" + filter.identityText)
        if let searchScope { parts.append("scope=" + searchScope.rawValue) }
        return parts.joined(separator: "|")
    }

    /// The identity in its reversible persisted form: the whole key as JSON with sorted keys, so the same
    /// request always produces the same bytes and a stored Edition can rebuild its exact key on read
    /// (T6 spec §6).
    public func canonicalJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Rebuilds a key from `canonicalJSON()`. Nil when the payload is absent or malformed.
    public static func fromCanonicalJSON(_ json: String) -> ContextKey? {
        guard !json.isEmpty, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ContextKey.self, from: data)
    }

    /// True when this key describes the plain, unfiltered surface — the identity every checkpoint written
    /// before T6 already has.
    public var isDefaultSurface: Bool {
        preset == .everything && filter.isUnrestricted
    }

    /// Equality *is* identity: two keys that describe the same effective request are one key, even when
    /// their stored values differ in a way that changes nothing (the order of a selected set, exclusions
    /// enabled with no rules, a scope carried on a non-search surface). Durable identifiers are the
    /// canonical text, so in-memory identity must agree with it (Codex review, 2026-10-09).
    public static func == (lhs: ContextKey, rhs: ContextKey) -> Bool {
        lhs.canonicalIdentity == rhs.canonicalIdentity
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(canonicalIdentity)
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
