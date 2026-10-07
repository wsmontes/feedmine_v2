// File: FeedWindow.swift
// Module: FeedMinePublication
// Owns: bounded immutable semantic projection over retained published history.
// Does not own: pagination, total history counts, mutation or acquisition.

import FeedMineDomain

/// A finite snapshot; bounded window does not mean bounded feed.
/// Supplied order is published history and the anchor remains exactly as supplied.
public struct FeedWindow: Hashable, Sendable {
    public let editionID: FeedEditionID
    public let cards: [PublishedCard]
    public let anchor: FeedWindowAnchor

    public init?(editionID: FeedEditionID, cards: [PublishedCard], anchor: FeedWindowAnchor) {
        guard !cards.isEmpty,
            Set(cards.map(\.id)).count == cards.count,
            cards.contains(where: { $0.id == anchor.cardID }) else { return nil }
        self.editionID = editionID
        self.cards = cards
        self.anchor = anchor
    }
}
