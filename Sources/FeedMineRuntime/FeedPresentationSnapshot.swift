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
    /// A presentation cannot be installed with negative materialization bounds.
    case invalidMaterializationBounds
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
    /// Built with the immutable window, shared by all viewport evidence through value semantics.
    let admittedIDs: Set<PublicationCardID>

    public init?(items: [PresentationCard], anchor: PresentationAnchor) {
        let ids = Set(items.map(\.id))
        guard !items.isEmpty, ids.count == items.count, ids.contains(anchor.cardID) else { return nil }
        self.items = items
        self.admittedIDs = ids
        self.anchor = anchor
    }

    /// FeedWindow already guarantees nonempty unique cards and anchor membership.
    /// The one-to-one projection preserves those invariants and supplied order.
    init(publishedWindow: FeedWindow, decoder: PresentationImageDecoder? = nil,
        reusable: [PublicationCardID: PresentationCard] = [:]) {
        items = publishedWindow.cards.map { reusable[$0.id] ?? PresentationCard(publishedCard: $0, decoder: decoder) }
        admittedIDs = Set(items.map(\.id))
        anchor = Self.anchor(for: publishedWindow.anchor)
    }

    /// The same projection with the pixel decision already made: `items` are exactly the card values the caller
    /// built (some carrying decoded pixels, some released), against the published anchor. A restore that admits a
    /// head wider than the residency band decides per card whether to decode one, which the projection above cannot
    /// express — it is the band, not the window, that owns pixels.
    init?(items: [PresentationCard], publishedAnchor: FeedWindowAnchor) {
        let ids = Set(items.map(\.id))
        guard !items.isEmpty, ids.count == items.count, ids.contains(publishedAnchor.cardID) else { return nil }
        self.items = items
        self.admittedIDs = ids
        self.anchor = Self.anchor(for: publishedAnchor)
    }

    // Membership is entirely derived; comparing or hashing it again adds work without changing identity.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.anchor == rhs.anchor && lhs.items == rhs.items
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(anchor)
        hasher.combine(items)
    }

    private static func anchor(for anchor: FeedWindowAnchor) -> PresentationAnchor {
        PresentationAnchor(cardID: anchor.cardID, placement: anchor.placement == .top ? .top : .center)
    }
}

/// Existence means retained local cards are ready for baseline presentation.
/// An image card is admitted with decoded pixels; outside the pixel band its frozen geometry stays while the bitmap
/// is released, and re-admission reconstructs it before the card is drawn.
public struct FeedPresentationSnapshot: Hashable, Sendable {
    public let contextKey: ContextKey
    public let editionID: FeedEditionID
    public let window: FeedWindowSnapshot
    public let provenance: FeedProjectionProvenance
    /// R03/R04 and restore: cards of this association whose local asset could not be reconstructed. An admitted card
    /// keeps its identity, order, anchor and frozen geometry, and the fact lets the destination gate state
    /// `unavailable` instead of asking for preparation forever. A restore whose durable anchor could not be redrawn
    /// names that card here too, even though it is excluded from the window (the presented anchor is the closest
    /// render-ready card) — the failure is stated, never hidden behind the substitute.
    public let unavailableImageCardIDs: Set<PublicationCardID>
    /// The reader's durable position this presentation could not redraw: the checkpoint's card, when its image
    /// could not be reconstructed and the window had to open on the closest render-ready card. Nil when the
    /// window's anchor is the reader's own position. A surface may state the unavailable position honestly; the
    /// substitute is not the reader's card, and no exact resume can be claimed for it.
    public let unavailablePositionCardID: PublicationCardID?

    init(restoredPublication: RestoredPublication, provenance: FeedProjectionProvenance) {
        self.init(contextKey: restoredPublication.edition.contextKey,
            editionID: restoredPublication.edition.id, publishedWindow: restoredPublication.window, provenance: provenance)
    }

    init(contextKey: ContextKey, editionID: FeedEditionID, publishedWindow: FeedWindow, provenance: FeedProjectionProvenance) {
        self.init(contextKey: contextKey, editionID: editionID, window: FeedWindowSnapshot(publishedWindow: publishedWindow),
            provenance: provenance)
    }

    init(contextKey: ContextKey, editionID: FeedEditionID, window: FeedWindowSnapshot,
        provenance: FeedProjectionProvenance, unavailableImageCardIDs: Set<PublicationCardID> = [],
        unavailablePositionCardID: PublicationCardID? = nil) {
        self.contextKey = contextKey
        self.editionID = editionID
        self.window = window
        self.provenance = provenance
        self.unavailableImageCardIDs = unavailableImageCardIDs
        self.unavailablePositionCardID = unavailablePositionCardID
    }
}

/// Small, non-persisted evidence issued only from a Runtime-produced presentation.
/// It carries IDs/provenance, never pixels, retained history or acquisition authority.
public struct RenderedViewportEvidence: Sendable {
    public let observation: ViewportObservation
    public let isPositionReconciliation: Bool
    let ordinal: UInt64
    let contextKey: ContextKey
    let editionID: FeedEditionID
    let provenance: FeedProjectionProvenance
    let admittedIDs: Set<PublicationCardID>

    public func belongs(to current: FeedPresentationSnapshot) -> Bool {
        contextKey == current.contextKey && editionID == current.editionID &&
            provenance.sequenceID == current.provenance.sequenceID &&
            provenance.position <= current.provenance.position &&
            admittedIDs.contains(observation.anchor.cardID)
    }
}

extension FeedPresentationSnapshot {
    public func evidence(for observation: ViewportObservation, ordinal: UInt64 = 1, reconciliation: Bool = false) -> RenderedViewportEvidence? {
        guard ordinal > 0, window.admittedIDs.contains(observation.anchor.cardID) else { return nil }
        return RenderedViewportEvidence(observation: observation, isPositionReconciliation: reconciliation,
            ordinal: ordinal, contextKey: contextKey,
            editionID: editionID, provenance: provenance, admittedIDs: window.admittedIDs)
    }
}
