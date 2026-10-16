//
// File: Content.swift
// Module: FeedMineDomain
//
// Responsibility:
//   Represent canonical accepted content identity, immutable revisions and independent relations.
//
// Owns:
//   ExternalIdentity, OriginRecord, OriginRevision, SourceMembership, ContentRelation, ContentEntity and ContentCluster with their enums.
//   OriginDeclaredInstant and StoryTemporalNature: the temporal evidence vocabulary over those revisions.
//   DeclaredSubjectClaim and StoryDeclaredSubjects: the subject a story's own document declared for it,
//   which is neither the story's identity nor its Source's taxonomy.
//
// Does not own:
//   Protocol parsing, raw protocol models, acquisition provenance, deduplication/clustering algorithms or published history ownership.
//
// Allowed dependencies:
//   Swift standard library and Foundation value types (UUID, Date, URL).
//   No other FeedMine module dependencies.
//
// Architectural invariants:
//   INV-08, INV-12, INV-13; external values are opaque; revisions are immutable; origin removal never deletes published history.
//
// Planned public surface:
//   Phase 1A canonical content values only; no media or interaction models.
//
// Status:
//   Phase 1A canonical domain implementation.
//

import Foundation


/// Semantic role of an opaque external identity.
public enum ExternalIdentityRole: String, Hashable, Codable, Sendable {
    case principal
    case object
    case version
    case alias
    case lookup
}

/// Opaque external identity supplied correctly by the connector.
/// Domain does not parse, trim, lowercase, transform or hash value for canonicalization.
public struct ExternalIdentity: Hashable, Codable, Sendable {
    public let connectorKind: ConnectorKind
    public let namespace: String
    public let value: String
    public let role: ExternalIdentityRole

    public init(
        connectorKind: ConnectorKind,
        namespace: String,
        value: String,
        role: ExternalIdentityRole
    ) {
        self.connectorKind = connectorKind
        self.namespace = namespace
        self.value = value
        self.role = role
    }
}

/// Availability of an origin in canonical supply.
/// A removed/revoked OriginRecord DOES NOT imply deletion of published history.
public enum OriginAvailability: String, Hashable, Codable, Sendable {
    case available
    case updated
    case removed
    case revoked
    case unknown
}

/// FeedMine identity of a logical external object accepted into canonical supply.
/// currentRevisionID is future-facing state, not a rewrite of published history.
/// No SourceID or ProviderID is stored here: membership and revision attribution are separate.
public struct OriginRecord: Hashable, Codable, Sendable {
    public let id: OriginRecordID
    public let externalObjectIdentity: ExternalIdentity
    public let currentRevisionID: OriginRevisionID?
    public let availability: OriginAvailability
    public let firstObservedAt: Date
    public let lastObservedAt: Date

    /// Derived from externalObjectIdentity; never duplicated as independent stored state.
    public var connectorKind: ConnectorKind {
        externalObjectIdentity.connectorKind
    }

    public init(
        id: OriginRecordID,
        externalObjectIdentity: ExternalIdentity,
        currentRevisionID: OriginRevisionID?,
        availability: OriginAvailability,
        firstObservedAt: Date,
        lastObservedAt: Date
    ) {
        self.id = id
        self.externalObjectIdentity = externalObjectIdentity
        self.currentRevisionID = currentRevisionID
        self.availability = availability
        self.firstObservedAt = firstObservedAt
        self.lastObservedAt = lastObservedAt
    }
}

/// Immutable canonical accepted representation of an OriginRecord at a particular state.
/// authoredAt: external/editorial authorship time when known.
/// modifiedAt: external/editorial modification time when known.
/// observedAt: time FeedMine observed this accepted revision; always FeedMine-controlled.
/// Missing authorship remains absent; observedAt never substitutes for authoredAt.
/// The three instants stay distinct and are never interchanged: authoredAt may only ever hold an
/// instant the origin itself declared, and modifiedAt only ever a declared change instant. A claim
/// the observation could not accept is not stored here either (see OriginDeclaredInstant): what the
/// origin claimed is evidence carried beside the accepted value, never a canonical date by itself.
/// searchProjection is the revision's one non-material text fact. A story's declared subjects are stored
/// there as `StoryDeclaredSubjects.canonicalText` (admission states them; a caller may instead supply an
/// opaque value), so the subject evidence survives with the revision it belongs to and is rebuilt from
/// canonical supply alone. It is deliberately not part of the material identity: a declaration is
/// evidence about the story, and no declaration can make a new version of it.
/// headline and primaryLink may be absent. providerID is known canonical revision attribution.
/// When externalVersionIdentity exists, connector consistency with OriginRecord belongs
/// to future admission, not this initializer: only originRecordID is available here;
/// validating the complete record would require lookup/I/O.
public struct OriginRevision: Hashable, Codable, Sendable {
    public let id: OriginRevisionID
    public let originRecordID: OriginRecordID
    public let externalVersionIdentity: ExternalIdentity?
    public let headline: String?
    public let summary: String?
    public let bodyText: String?
    public let authoredAt: Date?
    public let modifiedAt: Date?
    public let observedAt: Date
    public let language: String?
    public let primaryLink: URL?
    public let searchProjection: String?
    public let providerID: ProviderID?

    public init(
        id: OriginRevisionID,
        originRecordID: OriginRecordID,
        externalVersionIdentity: ExternalIdentity?,
        headline: String?,
        summary: String?,
        bodyText: String?,
        authoredAt: Date?,
        modifiedAt: Date?,
        observedAt: Date,
        language: String?,
        primaryLink: URL?,
        searchProjection: String?,
        providerID: ProviderID?
    ) {
        self.id = id
        self.originRecordID = originRecordID
        self.externalVersionIdentity = externalVersionIdentity
        self.headline = headline
        self.summary = summary
        self.bodyText = bodyText
        self.authoredAt = authoredAt
        self.modifiedAt = modifiedAt
        self.observedAt = observedAt
        self.language = language
        self.primaryLink = primaryLink
        self.searchProjection = searchProjection
        self.providerID = providerID
    }
}

/// One temporal instant an origin itself declared for a revision, kept as evidence that is separate
/// from the value canonical supply accepted and from FeedMine's own observation.
///
/// A declared date is the publisher's own statement; it is never an independently verified date.
/// Presence of a declaration is not reliability of it, and this type deliberately carries no score:
/// it states what was claimed and whether the claim could be accepted.
///
/// A claim that lies ahead of the observation instant cannot be the accepted value (an unaccepted
/// future date would pin an item to the top of a recency order forever), so it is kept as
/// `notYetReached` evidence instead of being replaced, silently, by an apparently reliable date.
/// The acceptance rule lives here and nowhere else, so no caller re-derives it.
///
/// TRANSIENT: this value describes the claim while it is still available. It is carried from translation
/// through admission, which validates it and then drops it — canonical supply keeps the accepted instant
/// only — so a stored revision never holds the original declaration.
public struct OriginDeclaredInstant: Hashable, Codable, Sendable {
    /// Exactly what the origin stated. Never rounded, clamped or re-derived.
    public let claimed: Date

    public init(claimed: Date) {
        self.claimed = claimed
    }

    /// The value canonical supply may accept: the claim itself, or the observation instant when the
    /// claim lies ahead of it. Never a value the observation did not reach.
    public func accepted(observingAt observedAt: Date) -> Date {
        min(claimed, observedAt)
    }

    /// Whether this claim lies ahead of the observation instant it was compared against. This
    /// reconstructs the acceptance decision above; it is a stated fact, not a confidence estimate.
    public func consistency(observingAt observedAt: Date) -> OriginDeclaredInstantConsistency {
        claimed > observedAt ? .notYetReached : .consistent
    }
}

/// Whether a declared instant could become the accepted canonical value. Stated as a fact, never scored.
public enum OriginDeclaredInstantConsistency: String, Hashable, Codable, Sendable {
    /// The claim was not ahead of the observation and is the instant the revision carries.
    case consistent
    /// The claim lies ahead of the observation instant: the accepted value is the observation, and
    /// the claim stays recorded rather than passing for a credible date.
    case notYetReached
}

/// Contextual temporal nature of a story: a different dimension from date reliability, and UNKNOWN
/// until real evidence and an approved interpretation rule exist. Age alone, subject, source name,
/// isolated words in the title, or the mere presence of a date are not evidence, and no producer may
/// derive a category from them. Adding a case requires the approved rule that produces it together
/// with the policy version that activates it, so an unknown representation never becomes a presumed
/// category by default.
public enum StoryTemporalNature: String, Hashable, Codable, Sendable {
    case unknown
}

/// Where a story's own document declared one of its subjects: the protocol element that carried it.
///
/// The surface is provenance and part of every identity derived from it. A JSON Feed tag, an Atom `term`
/// inside a named scheme and an RSS `<category>` inside a taxonomy `domain` are different declarations,
/// and nothing here unifies two of them because they read alike. Only *item-level* elements are surfaces:
/// a feed-level category or a catalogue placement is the Source's taxonomy, a different identity, and it
/// never reaches this vocabulary.
public enum DeclaredSubjectSurface: String, Hashable, Codable, Sendable {
    /// An item's own `<category>` element (RSS 2.0 and RSS 1.0/RDF items alike). Its element text is the
    /// declared subject; its optional `domain` attribute names the taxonomy it belongs to.
    case rssItemCategory
    /// An entry's own `atom:category` element. Its `term` attribute is the declared subject; its optional
    /// `scheme` attribute names the taxonomy. The element carries no text of its own.
    case atomEntryCategory
    /// A JSON Feed item's own `tags` entry: a plain text value, in no named taxonomy.
    case jsonFeedItemTag
}

/// One subject a story's own document declared for that story: a topical claim with its provenance.
///
/// This is evidence of a *declaration*, not proof of a subject. The label is the publisher's own text in
/// the publisher's own vocabulary, and nothing here says it is equivalent to a FeedMine taxonomic node
/// (see `DeclaredSubjectEquivalence`). A declaration is not a statement about what the story is about.
///
/// It belongs to the story, not to the feed: it carries no SourceID, no ProviderID and no catalogue
/// placement, and no Source's taxonomy may fill it. A missing declaration stays missing — it is never
/// filled from the feed, the catalogue, the headline or a classifier.
public struct DeclaredSubjectClaim: Hashable, Codable, Sendable {
    /// The protocol element that declared it.
    public let surface: DeclaredSubjectSurface
    /// The taxonomy the publisher named for this declaration, when it named one (RSS `domain`, Atom
    /// `scheme`), with surrounding whitespace removed. nil is "the publisher named none" — never "the
    /// vocabulary is FeedMine's" and never "the same vocabulary as a declaration that named none
    /// elsewhere". A named taxonomy is compared exactly: it is opaque text, not an IRI to normalize.
    public let scheme: String?
    /// The declared text as the document carried it, with runs of whitespace collapsed to one space and
    /// both ends trimmed. A declaration with no text at all is not a claim and has no representation.
    public let label: String

    public init?(surface: DeclaredSubjectSurface, scheme: String? = nil, label: String?) {
        guard let declared = Self.collapsed(label) else { return nil }
        self.surface = surface
        self.scheme = Self.collapsed(scheme)
        self.label = declared
    }

    /// The identity this declaration may carry. See `DeclaredSubjectIdentity` for what equality means.
    public var identity: DeclaredSubjectIdentity {
        DeclaredSubjectIdentity(surface: surface, scheme: scheme, key: Self.folded(label))
    }

    /// Whitespace-collapsed text, or nil when nothing but whitespace was declared.
    private static func collapsed(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return result.isEmpty ? nil : result
    }

    /// Textual normalization only: the Unicode precomposed form and the locale-independent lowercase
    /// mapping. It makes `Sports` and `sports` one declared subject, and it can never make two
    /// differently-spelled subjects one. A stated rule, not a guess about meaning.
    private static func folded(_ label: String) -> String {
        label.precomposedStringWithCanonicalMapping.lowercased()
    }
}

/// The identity one declared subject may carry.
///
/// Equality means exactly this: the same item-level surface, the same named taxonomy (or none on both
/// sides) and text that normalizes the same way. It compares *declarations* in the publisher's own words;
/// it is never a claim that two stories share a concept, and it is derived from nothing else — not from
/// the Source, the catalogue, the headline, a score or a classifier.
public struct DeclaredSubjectIdentity: Hashable, Codable, Sendable {
    public let surface: DeclaredSubjectSurface
    public let scheme: String?
    /// The declared text, precomposed and lowercased. The declared label itself is never rewritten.
    public let key: String

    public init(surface: DeclaredSubjectSurface, scheme: String?, key: String) {
        self.surface = surface
        self.scheme = scheme
        self.key = key
    }
}

/// How far a declared subject's identity reaches in this build. One state exists, and it exists to be
/// read: a declared subject is the publisher's own text and states nothing about FeedMine's taxonomy.
///
/// A canonical taxonomic identifier may only be assigned where a defined, verifiable mapping exists. No
/// such mapping, taxonomy or classification authority exists in this build, so no producer may derive a
/// node from a label — not by word, stem, slug, prefix or resemblance, all of which would be an
/// improvised heuristic and a false identity. Adding a case requires the approved mapping that produces
/// it together with the authority that owns it, so an unmapped declaration never passes for a mapped one.
public enum DeclaredSubjectEquivalence: String, Hashable, Codable, Sendable {
    /// The identity is the declaration itself: same surface, same named taxonomy, same declared text.
    /// Nothing else is claimed — not topical equivalence between stories, and not any catalogue node.
    case declaredLabelOnly
}

/// Why a text in a revision's non-material slot is not the declarations this build writes.
public enum DeclaredSubjectsTextError: Error, Equatable, Sendable {
    /// The text carries this build's marker but was written by another schema version.
    case unsupportedSchemaVersion(Int)
    /// The text carries this build's marker and is not the canonical text of any declarations this build
    /// can produce: truncated, tampered with, or spelled in a way this build never writes.
    case malformedCanonicalText
}

/// Every subject one story's own document declared for it, as one canonical accepted value.
///
/// One set of declarations has exactly one representation: claims are deduplicated by identity and
/// ordered by surface, named taxonomy and normalized text, so the same declarations in any element order
/// — and a repeated declaration — produce the same value and the same `canonicalText`. An empty set is
/// absent: there is no value at all, because absence has no other representation here.
///
/// `canonicalText` is what canonical supply stores beside the revision, in the revision's one
/// non-material text slot (`OriginRevision.searchProjection`), and what this value is rebuilt from on
/// read. The identity a candidate exposes is therefore reconstructed from the canonical fact alone.
///
/// Deliberately not here: a FeedMine node, a confidence, a match against the catalogue, and any inference
/// from the title, the summary or the Source. A claim is only ever what the document declared.
public struct StoryDeclaredSubjects: Hashable, Codable, Sendable {
    /// Bumped only when the canonical *text* changes; every persisted text carries it in its marker.
    public static let currentSchemaVersion = 1
    /// What every canonical text starts with. A text without this marker is not this value's text, and
    /// reads as absence rather than being misread as declarations.
    private static let textPrefix = "feedmine.declared-subjects/"

    /// The story's declared subjects, deduplicated and in canonical order. Never empty.
    public let claims: [DeclaredSubjectClaim]

    public init?(_ claims: [DeclaredSubjectClaim]) {
        let canonical = Self.canonical(claims)
        guard !canonical.isEmpty else { return nil }
        self.claims = canonical
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let claims = try container.decode([DeclaredSubjectClaim].self, forKey: .claims)
        guard let subjects = Self(claims) else {
            throw DecodingError.dataCorruptedError(forKey: .claims, in: container,
                debugDescription: "StoryDeclaredSubjects requires at least one declared subject.")
        }
        self = subjects
    }

    /// The identities these declarations carry, in the same canonical order. This is what a consumer
    /// compares: two stories declare a common subject exactly when these sets intersect.
    public var identities: [DeclaredSubjectIdentity] { claims.map(\.identity) }

    /// How far those identities reach. Only `.declaredLabelOnly` exists in this build.
    public var equivalence: DeclaredSubjectEquivalence { .declaredLabelOnly }

    /// The one text that represents this value: the marker, the schema version and the declarations as
    /// JSON with sorted keys, so the same declarations always produce the same bytes.
    public var canonicalText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self), let json = String(data: data, encoding: .utf8) else {
            // Unreachable for these value types. A marker with no payload is a text this build refuses to
            // read, so an impossible failure can never pass for absence.
            return Self.textPrefix + "\(Self.currentSchemaVersion)|"
        }
        return Self.textPrefix + "\(Self.currentSchemaVersion)|" + json
    }

    /// The declarations a non-material revision text carries.
    ///
    /// nil when the text is not this value's text at all — any value another producer stored in the same
    /// slot reads as absence, never as declarations. A text that carries the marker must be readable;
    /// nothing this build writes may be silently dropped, so an unreadable one is thrown, not ignored.
    public static func decode(canonicalText text: String) throws -> StoryDeclaredSubjects? {
        guard text.hasPrefix(textPrefix) else { return nil }
        let payload = text.dropFirst(textPrefix.count)
        guard let separator = payload.firstIndex(of: "|"),
            let version = Int(payload[payload.startIndex..<separator]) else {
            throw DeclaredSubjectsTextError.malformedCanonicalText
        }
        guard version == currentSchemaVersion else {
            throw DeclaredSubjectsTextError.unsupportedSchemaVersion(version)
        }
        let json = String(payload[payload.index(after: separator)...])
        guard let data = json.data(using: .utf8), let decoded = try? JSONDecoder().decode(Self.self, from: data),
            decoded.canonicalText == text else {
            throw DeclaredSubjectsTextError.malformedCanonicalText
        }
        return decoded
    }

    /// One declaration per identity, in an order that does not depend on the document's element order.
    /// A decoded claim is normalized through the initializer, so a value read back is the same value any
    /// producer would have built.
    private static func canonical(_ claims: [DeclaredSubjectClaim]) -> [DeclaredSubjectClaim] {
        var byIdentity: [DeclaredSubjectIdentity: DeclaredSubjectClaim] = [:]
        for claim in claims {
            guard let normalized = DeclaredSubjectClaim(surface: claim.surface, scheme: claim.scheme,
                label: claim.label) else { continue }
            let identity = normalized.identity
            if let existing = byIdentity[identity],
                existing.label.utf8.lexicographicallyPrecedes(normalized.label.utf8) { continue }
            byIdentity[identity] = normalized
        }
        return byIdentity.values.sorted { left, right in
            if left.surface != right.surface { return left.surface.rawValue < right.surface.rawValue }
            let leftScheme = left.scheme ?? "", rightScheme = right.scheme ?? ""
            if leftScheme != rightScheme { return leftScheme.utf8.lexicographicallyPrecedes(rightScheme.utf8) }
            return left.identity.key.utf8.lexicographicallyPrecedes(right.identity.key.utf8)
        }
    }

    private enum CodingKeys: String, CodingKey { case claims }
}

/// Canonical membership relationship; not operational acquisition provenance.
public enum SourceMembershipKind: String, Hashable, Codable, Sendable {
    case direct
    case derived
}

/// Independent membership of an origin in a Source; one origin may belong to many sources.
/// Operational acquisition provenance will be added separately when AcquisitionTarget exists.
public struct SourceMembership: Hashable, Codable, Sendable {
    public let originRecordID: OriginRecordID
    public let sourceID: SourceID
    public let kind: SourceMembershipKind
    public let firstObservedAt: Date
    public let lastObservedAt: Date

    public init(
        originRecordID: OriginRecordID,
        sourceID: SourceID,
        kind: SourceMembershipKind,
        firstObservedAt: Date,
        lastObservedAt: Date
    ) {
        self.originRecordID = originRecordID
        self.sourceID = sourceID
        self.kind = kind
        self.firstObservedAt = firstObservedAt
        self.lastObservedAt = lastObservedAt
    }
}

/// FeedMine semantic relations, not external protocol verbs.
public enum ContentRelationKind: String, Hashable, Codable, Sendable {
    case replyTo
    case repostOf
    case quoteOf
    case references
}

/// A canonical directed relationship between two origins.
public struct ContentRelation: Hashable, Codable, Sendable {
    public let fromOriginRecordID: OriginRecordID
    public let toOriginRecordID: OriginRecordID
    public let kind: ContentRelationKind

    public init(
        fromOriginRecordID: OriginRecordID,
        toOriginRecordID: OriginRecordID,
        kind: ContentRelationKind
    ) {
        self.fromOriginRecordID = fromOriginRecordID
        self.toOriginRecordID = toOriginRecordID
        self.kind = kind
    }
}

/// Strong equivalence relationship between origins without destroying those origins.
/// Does not replace OriginRecord, erase OriginRevision, change external identity,
/// destroy original evidence or become a global canonical record.
public struct ContentEntity: Hashable, Codable, Sendable {
    public let id: ContentEntityID
    public let originRecordIDs: Set<OriginRecordID>

    public init?(id: ContentEntityID, originRecordIDs: Set<OriginRecordID>) {
        guard !originRecordIDs.isEmpty else { return nil }
        self.id = id
        self.originRecordIDs = originRecordIDs
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(ContentEntityID.self, forKey: .id)
        let origins = try container.decode(Set<OriginRecordID>.self, forKey: .originRecordIDs)
        guard let entity = Self(id: id, originRecordIDs: origins) else {
            throw DecodingError.dataCorruptedError(forKey: .originRecordIDs, in: container, debugDescription: "ContentEntity requires nonempty origins.")
        }
        self = entity
    }
}

/// Soft editorial relationship with confidence, method and version, not equivalence.
/// Does not replace OriginRecord, erase OriginRevision, change external identity,
/// destroy original evidence or become a global canonical record.
public struct ContentCluster: Hashable, Codable, Sendable {
    public let id: ContentClusterID
    public let originRecordIDs: Set<OriginRecordID>
    public let confidence: Double
    public let method: String
    public let version: UInt64

    public init?(
        id: ContentClusterID,
        originRecordIDs: Set<OriginRecordID>,
        confidence: Double,
        method: String,
        version: UInt64
    ) {
        guard !originRecordIDs.isEmpty, (0...1).contains(confidence), !method.isEmpty else {
            return nil
        }
        self.id = id
        self.originRecordIDs = originRecordIDs
        self.confidence = confidence
        self.method = method
        self.version = version
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(ContentClusterID.self, forKey: .id)
        let origins = try container.decode(Set<OriginRecordID>.self, forKey: .originRecordIDs)
        let confidence = try container.decode(Double.self, forKey: .confidence)
        let method = try container.decode(String.self, forKey: .method)
        let version = try container.decode(UInt64.self, forKey: .version)
        guard let cluster = Self(id: id, originRecordIDs: origins, confidence: confidence, method: method, version: version) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "ContentCluster requires nonempty origins, confidence in 0...1 and a nonempty method."))
        }
        self = cluster
    }
}
