//
// File: PublishedCard.swift
// Module: FeedMinePublication
//
// Responsibility:
//   Freeze self-contained semantic values for deterministic local published presentation.
//
// Owns:
//   Self-contained occurrence snapshot, exact optional text and meaningful timestamp.
//
// Does not own:
//   Live canonical/catalog joins, duplicated history metadata, mutation or rendering execution.
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

import Foundation
import FeedMineDomain
import FeedMineMedia

/// Exact text already chosen for presentation; no normalization or article-only requirements.
public struct PublishedText: Hashable, Sendable {
    public let title: String?
    public let primaryText: String?

    public init(title: String?, primaryText: String?) {
        self.title = title
        self.primaryText = primaryText
    }
}

public enum PublishedTimestampKind: String, Hashable, Sendable {
    case authored
    case modified
    case observed
}

/// Preserves the chosen date's meaning; an observed date never fabricates authorship.
public struct PublishedTimestamp: Hashable, Sendable {
    public let value: Date
    public let kind: PublishedTimestampKind

    public init(value: Date, kind: PublishedTimestampKind) {
        self.value = value
        self.kind = kind
    }
}

/// Frozen published occurrence, presentable after canonical/catalog data disappears.
/// Missing primary bytes or reference uses the hero/thumbnail contract's local placeholder.
/// Historical origin references, attribution and payload never follow upstream updates.
public struct PublishedCard: Hashable, Sendable {
    public let id: PublicationCardID
    public let origin: PublishedOrigin
    public let contentEntityID: ContentEntityID?
    public let contentClusterID: ContentClusterID?
    public let text: PublishedText
    public let timestamp: PublishedTimestamp?
    public let media: PublishedMediaSet
    public let renderContract: RenderContract
    public let primaryAction: PublishedPrimaryAction?

    public init?(
        id: PublicationCardID,
        origin: PublishedOrigin,
        contentEntityID: ContentEntityID?,
        contentClusterID: ContentClusterID?,
        text: PublishedText,
        timestamp: PublishedTimestamp?,
        media: PublishedMediaSet,
        renderContract: RenderContract,
        primaryAction: PublishedPrimaryAction?
    ) {
        guard renderContract.layout != .textOnly || media.primary == nil else { return nil }
        self.id = id
        self.origin = origin
        self.contentEntityID = contentEntityID
        self.contentClusterID = contentClusterID
        self.text = text
        self.timestamp = timestamp
        self.media = media
        self.renderContract = renderContract
        self.primaryAction = primaryAction
    }
}
