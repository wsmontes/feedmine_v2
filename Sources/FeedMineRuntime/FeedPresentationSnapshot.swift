// File: FeedPresentationSnapshot.swift
// Module: FeedMineRuntime
// Owns: immutable ready local presentation, finite window and logical anchor.
// Does not own: publication authority, pagination, pixels or mutable session state.

import FeedMineDomain
import FeedMinePublication

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
    init(publishedWindow: FeedWindow) {
        items = publishedWindow.cards.map(PresentationCard.init(publishedCard:))
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

    init(restoredPublication: RestoredPublication) {
        self.init(contextKey: restoredPublication.edition.contextKey,
            editionID: restoredPublication.edition.id, publishedWindow: restoredPublication.window)
    }

    init(contextKey: ContextKey, editionID: FeedEditionID, publishedWindow: FeedWindow) {
        self.contextKey = contextKey
        self.editionID = editionID
        window = FeedWindowSnapshot(publishedWindow: publishedWindow)
    }
}
