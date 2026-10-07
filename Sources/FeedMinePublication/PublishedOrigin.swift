//
// File: PublishedOrigin.swift
// Module: FeedMinePublication
//
// Responsibility:
//   Freeze self-contained semantic values for deterministic local published presentation.
//
// Owns:
//   Historical origin/revision provenance and separate frozen source/provider attribution.
//
// Does not own:
//   Canonical payload, live attribution lookup or retrospective renaming.
//
// Allowed dependencies:
//   Foundation value types and FeedMineDomain; PublishedCard also uses FeedMineMedia.
//
// Architectural invariants:
//   INV-08, INV-12; published history survives canonical eviction without live joins.
//
// Public surface:
//   Phase 2C immutable semantic values; no Codable storage blobs or execution API.
//
// Status:
//   Phase 2C frozen PublishedCard baseline implemented.
//

import FeedMineDomain

/// IDs are historical provenance; names preserve the exact attribution at publication.
public struct PublishedOrigin: Hashable, Sendable {
    public let originRecordID: OriginRecordID
    public let originRevisionID: OriginRevisionID
    public let sourceID: SourceID?
    public let providerID: ProviderID?
    public let sourceDisplayName: String?
    public let providerDisplayName: String?

    public init(
        originRecordID: OriginRecordID,
        originRevisionID: OriginRevisionID,
        sourceID: SourceID?,
        providerID: ProviderID?,
        sourceDisplayName: String?,
        providerDisplayName: String?
    ) {
        self.originRecordID = originRecordID
        self.originRevisionID = originRevisionID
        self.sourceID = sourceID
        self.providerID = providerID
        self.sourceDisplayName = sourceDisplayName
        self.providerDisplayName = providerDisplayName
    }
}
