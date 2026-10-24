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
    /// D2: what the occurrence's own payload is, frozen with the card so a reload does not have to guess it from
    /// the action kind. Nil means the card was published before the fact existed (unknown), never "audio".
    public let mediaIdentity: PublishedMediaIdentity?
    /// P10: the editorial facts this occurrence was published with. Frozen with identity and text; nil for history
    /// written before the facts existed.
    public let diversity: EditorialDiversityFact?

    public init?(
        id: PublicationCardID,
        origin: PublishedOrigin,
        contentEntityID: ContentEntityID?,
        contentClusterID: ContentClusterID?,
        text: PublishedText,
        timestamp: PublishedTimestamp?,
        media: PublishedMediaSet,
        renderContract: RenderContract,
        primaryAction: PublishedPrimaryAction?,
        mediaIdentity: PublishedMediaIdentity? = nil,
        diversity: EditorialDiversityFact? = nil
    ) {
        guard renderContract.layout != .textOnly || media.primary == nil else { return nil }
        // The two facts are one decision: a known audio card carries the in-app player, a known video or empty
        // card never does. Unknown (nil, history written before the fact) stays permitted and stays unknown.
        switch mediaIdentity {
        case .some(.audio):
            guard case .some(.mediaPlayback) = primaryAction else { return nil }
        case .some(.video), .some(.none):
            if case .some(.mediaPlayback) = primaryAction { return nil }
        case nil:
            break
        }
        self.id = id
        self.origin = origin
        self.contentEntityID = contentEntityID
        self.contentClusterID = contentClusterID
        self.text = text
        self.timestamp = timestamp
        self.media = media
        self.renderContract = renderContract
        self.primaryAction = primaryAction
        self.mediaIdentity = mediaIdentity
        self.diversity = diversity
    }
}
