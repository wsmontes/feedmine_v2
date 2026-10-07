//
// File: Content.swift
// Module: FeedMineDomain
//
// Responsibility:
//   Represent canonical accepted content identity, immutable revisions and independent relations.
//
// Owns:
//   ExternalIdentity, OriginRecord, OriginRevision, SourceMembership, ContentRelation, ContentEntity and ContentCluster with their enums.
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
