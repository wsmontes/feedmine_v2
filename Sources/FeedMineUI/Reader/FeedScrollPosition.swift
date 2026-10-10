// File: FeedScrollPosition.swift
// Module: FeedMineUI
// Owns: the reader's transient visual position — one reference card plus the offset inside it.
// Does not own: admission authority, production, durable checkpoints or backend provenance.
//
// UI never decides *which* cards are admitted. This value exists so a gesture can be described
// precisely (real movement, a card, an offset inside that card) and so a delivery can prove the
// physical position survived production, background/foreground and layout changes.

import CoreGraphics
import FeedMineDomain
import FeedMineRuntime

public struct FeedScrollPosition: Hashable, Sendable {
    /// The card the reader is looking at, in published order.
    public let cardID: PublicationCardID
    /// How much of that card is already above the viewport's top edge, in points. Zero means the
    /// card's top edge is exactly at the viewport's reference line.
    public let offsetWithinCard: CGFloat
    /// Where the reference line sits inside the viewport.
    public let placement: PresentationAnchorPlacement

    public init?(cardID: PublicationCardID, offsetWithinCard: CGFloat,
        placement: PresentationAnchorPlacement = .center) {
        guard offsetWithinCard.isFinite else { return nil }
        self.cardID = cardID
        self.offsetWithinCard = offsetWithinCard
        self.placement = placement
    }

    /// The position the viewport currently shows for a measured card: how much of its top edge is
    /// above the viewport, clamped to the card's own height so a partly visible card can never
    /// report an offset outside itself.
    public init?(cardID: PublicationCardID, viewportTop: CGFloat, cardTop: CGFloat, cardHeight: CGFloat,
        placement: PresentationAnchorPlacement = .center) {
        guard cardHeight > 0, viewportTop.isFinite, cardTop.isFinite else { return nil }
        self.init(cardID: cardID, offsetWithinCard: min(max(viewportTop - cardTop, 0), cardHeight),
            placement: placement)
    }

    public var anchor: PresentationAnchor {
        PresentationAnchor(cardID: cardID, placement: placement)
    }
}
