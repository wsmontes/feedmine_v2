//
// File: ReaderActionCoordinator.swift
// Module: FeedMineComposition
//
// Responsibility:
// Resolve what a card action *means*, from the card occurrence itself: the frozen target the published card
// carries, never the article's current state. It hands the host a typed target; nothing here opens a URL,
// touches a pasteboard, presents a share sheet or starts a player.
//
// Does not own: the surfaces (the app), playback (a platform adapter), the pasteboard or the share sheet.
import Foundation
import FeedMineDomain
import FeedMinePersistence
import FeedMineRuntime
import FeedMineUI

public enum ReaderActionError: Error, Equatable, Sendable {
    /// The card does not carry this action. Nothing is invented in its place.
    case actionUnavailable(ReaderCardAction)
    /// The card carries the action but its reference cannot be used as it stands.
    case unusableReference(String)
    /// The card exists but is not in published history any more.
    case cardNotFound
}

/// What an action resolves to, before any platform surface touches it.
public enum ReaderActionTarget: Hashable, Sendable {
    /// V1's "open" / "view source": the occurrence's own external target.
    case externalURL(URL)
    /// V1's "copy link": the same target, as the text the reader expects on the clipboard.
    case copiedText(String)
    /// V1's share: the title, the link and the text its templates composed.
    case share(ReaderSharePayload)
    /// V1's media action: the occurrence's own primary media locator, with the kind the catalog declared.
    case media(ReaderMediaTarget)
}

/// One playable occurrence. `mimeType` is what the card carries; the player decides whether it can take it.
public struct ReaderMediaTarget: Hashable, Sendable {
    public let url: URL
    public let mimeType: String?
    public let title: String?

    public init(url: URL, mimeType: String?, title: String?) {
        self.url = url; self.mimeType = mimeType; self.title = title
    }
}

public struct ReaderActionCoordinator: Sendable {
    private let database: RuntimeDatabase

    public init(database: RuntimeDatabase) { self.database = database }

    /// What a card carries right now. Every branch reads the **occurrence's own**
    /// frozen fields, so an article edited after publication still opens, copies and shares the target the card
    /// was published with (PD-1's promise, stated as an action).
    public func perform(_ action: ReaderCardAction, cardID: PublicationCardID) async throws -> ReaderActionTarget {
        let store = PublicationStore(database: database)
        guard let card = try store.card(id: cardID) else { throw ReaderActionError.cardNotFound }
        switch action {
        case .open:
            return .externalURL(try externalURL(of: card, action: action))
        case .viewSource:
            // V1's "View Source" opens the *source* of the card, not the article: that needs the catalog and the
            // target-to-principal mapping, which live with the app. Answering with the article's URL here would
            // be the wrong page, so it is refused.
            throw ReaderActionError.actionUnavailable(action)
        case .copyLink:
            return .copiedText(try externalURL(of: card, action: action).absoluteString)
        case .share:
            return .share(share(of: card, url: try externalURL(of: card, action: action)))
        case .openMedia:
            return .media(try media(of: card))
        case .save, .addSourceToCollection:
            // Both change the reader's own state rather than producing a target (boxes are T8, collections T7):
            // they are the host's to execute, and asking this coordinator for them is a programming error, not
            // a card without an action.
            throw ReaderActionError.actionUnavailable(action)
        }
    }

    /// The occurrence's external target. `primaryActionKind` is part of the card's frozen payload; a card that
    /// carries no usable URL has no `open`, and the host is told so instead of being handed a guess.
    func externalURL(of card: PublicationStore.CardRecord, action: ReaderCardAction) throws -> URL {
        guard card.primaryActionKind == "externalURL" else {
            throw ReaderActionError.actionUnavailable(action)
        }
        guard let reference = card.primaryActionReference, let url = URL(string: reference),
            let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw ReaderActionError.unusableReference(card.primaryActionReference ?? "")
        }
        return url
    }

    /// V1's share payload: the card's own title, its frozen link, and the sentence V1's templates composed.
    func share(of card: PublicationStore.CardRecord, url: URL) -> ReaderSharePayload {
        ReaderSharePayload(title: Self.title(of: card), url: url, source: card.sourceDisplayName)
    }

    /// The occurrence's own playable target. The pipeline states this with the card's action kind
    /// (`mediaPlayback`, a kind `PublicationStore` validates with a URL), so nothing here guesses from a mime
    /// type: a card the pipeline did not mark is reported as unavailable rather than opened on a guess.
    func media(of card: PublicationStore.CardRecord) throws -> ReaderMediaTarget {
        guard card.primaryActionKind == "mediaPlayback", let reference = card.primaryActionReference,
            let url = URL(string: reference) else {
            throw ReaderActionError.actionUnavailable(.openMedia)
        }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw ReaderActionError.unusableReference(reference)
        }
        return ReaderMediaTarget(url: url, mimeType: card.mediaMimeType, title: Self.title(of: card))
    }

    static func title(of card: PublicationStore.CardRecord) -> String? {
        let title = (card.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        let text = (card.primaryText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
