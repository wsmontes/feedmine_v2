// File: ReaderCardAction.swift
// Module: FeedMineUI
// Owns: the semantic vocabulary a card can produce, each carrying the occurrence it belongs to.
// Does not own: execution. URLs, players, pasteboards and share sheets are resolved outside UI.

import FeedMineDomain

public enum ReaderCardAction: String, CaseIterable, Hashable, Sendable {
    case open
    case save
    case viewSource
    case addSourceToCollection
    case copyLink
    case share
    case openMedia
}

/// One semantic request from one card. The card never resolves a URL, opens a player or touches the
/// pasteboard: it states the occurrence and what the reader asked for.
public struct ReaderCardActionEvent: Hashable, Sendable {
    public let action: ReaderCardAction
    public let cardID: PublicationCardID

    public init(action: ReaderCardAction, cardID: PublicationCardID) {
        self.action = action
        self.cardID = cardID
    }
}
