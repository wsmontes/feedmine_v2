// File: FeedPresentationSnapshot.swift
// Module: FeedMineRuntime
// Owns: immutable ready local presentation, finite window and logical anchor.
// Does not own: publication authority, pagination, pixels or mutable session state.

import Foundation
import FeedMineDomain
import FeedMinePublication

/// Memory-local causal provenance, comparable only within its producing FeedSession.
/// The identifier is equality-only; neither it nor card positions define order.
public struct FeedProjectionProvenance: Hashable, Sendable {
    public let sequenceID: UUID
    public let position: UInt64

    init(sequenceID: UUID, position: UInt64) {
        precondition(position > 0)
        self.sequenceID = sequenceID
        self.position = position
    }

    static func nextPosition(after position: UInt64) throws -> UInt64 {
        let (next, overflow) = position.addingReportingOverflow(1)
        guard !overflow else { throw FeedSessionError.projectionOrderExhausted }
        return next
    }
}

public enum FeedSessionError: Error, Equatable, Sendable {
    case projectionOrderExhausted
}

public enum PresentationAnchorPlacement: String, Hashable, Sendable {
    case top
    case center
}

public struct PresentationAnchor: Hashable, Sendable {
    public let cardID: PublicationCardID
    public let placement: PresentationAnchorPlacement

    public init(cardID: PublicationCardID, placement: PresentationAnchorPlacement) {
        self.cardID = cardID
        self.placement = placement
    }
}

public struct FeedWindowSnapshot: Hashable, Sendable {
    public let items: [PresentationCard]
    public let anchor: PresentationAnchor

    public init?(items: [PresentationCard], anchor: PresentationAnchor) {
        guard !items.isEmpty,
            Set(items.map(\.id)).count == items.count,
            items.contains(where: { $0.id == anchor.cardID }) else { return nil }
        self.items = items
        self.anchor = anchor
    }

    /// FeedWindow already guarantees nonempty unique cards and anchor membership.
    /// The one-to-one projection preserves those invariants and supplied order.
    init(publishedWindow: FeedWindow, decoder: PresentationImageDecoder? = nil,
        reusable: [PublicationCardID: PresentationCard] = [:]) {
        items = publishedWindow.cards.map { reusable[$0.id] ?? PresentationCard(publishedCard: $0, decoder: decoder) }
        let placement: PresentationAnchorPlacement
        switch publishedWindow.anchor.placement {
        case .top: placement = .top
        case .center: placement = .center
        }
        anchor = PresentationAnchor(cardID: publishedWindow.anchor.cardID, placement: placement)
    }
}

/// Existence means retained local cards are ready for baseline presentation.
/// Hero/thumbnail geometry can render placeholders without materialized media.
public struct FeedPresentationSnapshot: Hashable, Sendable {
    public let contextKey: ContextKey
    public let editionID: FeedEditionID
    public let window: FeedWindowSnapshot
    public let provenance: FeedProjectionProvenance

    init(restoredPublication: RestoredPublication, provenance: FeedProjectionProvenance) {
        self.init(contextKey: restoredPublication.edition.contextKey,
            editionID: restoredPublication.edition.id, publishedWindow: restoredPublication.window, provenance: provenance)
    }

    init(contextKey: ContextKey, editionID: FeedEditionID, publishedWindow: FeedWindow, provenance: FeedProjectionProvenance) {
        self.init(contextKey: contextKey, editionID: editionID, window: FeedWindowSnapshot(publishedWindow: publishedWindow),
            provenance: provenance)
    }

    init(contextKey: ContextKey, editionID: FeedEditionID, window: FeedWindowSnapshot, provenance: FeedProjectionProvenance) {
        self.contextKey = contextKey
        self.editionID = editionID
        self.window = window
        self.provenance = provenance
    }
}
