//
// File: FeedPlan.swift
// Module: FeedMineDomain
//
// Responsibility:
//   Associate a requested context with its explicitly resolved editorial rule identity.
//
// Owns:
//   PolicyVersion, CatalogGeneration, SelectionSchemaVersion, EditorialRevision and FeedPlan.
//
// Does not own:
//   Policy execution, scoring, sequencing, exposure, acquisition, connector checkpoints or render environment identity.
//
// Allowed dependencies:
//   Swift standard library and Foundation value types when needed; no other FeedMine module.
//
// Architectural invariants:
//   INV-08, INV-12, INV-13; editorial rule identity is separate from presentation environment.
//
// Planned public surface:
//   PolicyVersion, CatalogGeneration, SelectionSchemaVersion, EditorialRevision and FeedPlan. No execution API is authorized in this phase.
//
// Status:
//   Phase 1B context and editorial revision value implementation.
//

/// Opaque version of an editorial policy; not a strategy object.
public struct PolicyVersion: Hashable, Codable, Sendable, Comparable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Catalog version; not acquisition checkpoint, SourceBinding generation or database migration.
public struct CatalogGeneration: Hashable, Codable, Sendable, Comparable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Opaque selection schema version; no selection algorithm.
public struct SelectionSchemaVersion: Hashable, Codable, Sendable, Comparable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Concrete editorial rule identity belonging to exactly one ContextKey.
/// ContextKey, catalog generation, user selection, eligibility, scoring, sequencing,
/// exposure and selection schema changes may create a new EditorialRevision.
/// Acquisition policy, network availability, connector implementation, endpoint,
/// checkpoint, retry policy, background scheduling, render environment, Dynamic Type,
/// screen size and media cache changes do not create a revision by themselves.
/// Acquisition strategy may change without changing already-produced history identity.
/// No automatic revision generation or compatibility comparison is performed.
/// RenderEnvironmentRevision is intentionally not part of EditorialRevision.
/// It belongs to a later Runtime/Presentation phase.
public struct EditorialRevision: Hashable, Codable, Sendable {
    public let id: EditorialRevisionID
    public let contextKey: ContextKey
    public let catalogGeneration: CatalogGeneration
    public let userSelectionVersion: PolicyVersion
    public let eligibilityPolicyVersion: PolicyVersion
    public let scoringPolicyVersion: PolicyVersion
    public let sequencingPolicyVersion: PolicyVersion
    public let exposurePolicyVersion: PolicyVersion
    public let selectionSchemaVersion: SelectionSchemaVersion

    public init(
        id: EditorialRevisionID,
        contextKey: ContextKey,
        catalogGeneration: CatalogGeneration,
        userSelectionVersion: PolicyVersion,
        eligibilityPolicyVersion: PolicyVersion,
        scoringPolicyVersion: PolicyVersion,
        sequencingPolicyVersion: PolicyVersion,
        exposurePolicyVersion: PolicyVersion,
        selectionSchemaVersion: SelectionSchemaVersion
    ) {
        self.id = id
        self.contextKey = contextKey
        self.catalogGeneration = catalogGeneration
        self.userSelectionVersion = userSelectionVersion
        self.eligibilityPolicyVersion = eligibilityPolicyVersion
        self.scoringPolicyVersion = scoringPolicyVersion
        self.sequencingPolicyVersion = sequencingPolicyVersion
        self.exposurePolicyVersion = exposurePolicyVersion
        self.selectionSchemaVersion = selectionSchemaVersion
    }
}

/// Explicit context and resolved editorial revision association; only a value, never a service.
/// Valid only when context.key == revision.contextKey.
/// FeedPlan knows no connector, endpoint, AcquisitionTarget, transport request,
/// URLSession or protocol pagination. Future policy objects belong to Editorial.
public struct FeedPlan: Hashable, Codable, Sendable {
    public let context: FeedContext
    public let revision: EditorialRevision

    public init?(context: FeedContext, revision: EditorialRevision) {
        guard context.key == revision.contextKey else { return nil }
        self.context = context
        self.revision = revision
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let context = try container.decode(FeedContext.self, forKey: .context)
        let revision = try container.decode(EditorialRevision.self, forKey: .revision)
        guard let plan = Self(context: context, revision: revision) else {
            throw DecodingError.dataCorruptedError(forKey: .revision, in: container, debugDescription: "EditorialRevision must belong to the requested context key.")
        }
        self = plan
    }

}
