//
// File: ReaderMediaCoordinator.swift
// Module: FeedMineComposition
//
// Responsibility:
// The reader's playback, as the surface sees it: resolve the occurrence's own payload (through T9's action
// coordinator) and hand it to the player, and expose the player's state as a value. The one rule it owns is
// V1's card behaviour — tapping a card that is already playing pauses it, tapping a paused one resumes it, and
// tapping another starts that one.
//
// Does not own: playback itself (a platform adapter), the mini player (UI) or the card's action target.
import Foundation
import FeedMineDomain
import FeedMinePersistence
import FeedMineRuntime
import FeedMineUI

/// What a surface intent produced: nothing the reader has to be told, or the reason it must be (F15 R4). The
/// player owns the state; this is only the host's channel to state a refusal outside the bar (a card with no
/// playable payload has no bar to attach to).
public enum ReaderMediaIntentOutcome: Equatable, Sendable {
    case handled
    case unavailable(String)
}

@MainActor
public final class ReaderMediaCoordinator {
    private let database: RuntimeDatabase
    private let player: any ReaderMediaPlaying

    public init(database: RuntimeDatabase, player: any ReaderMediaPlaying) {
        self.database = database
        self.player = player
    }

    public var state: ReaderMediaState { player.state }

    /// V1's own tap behaviour, in one place: the same item toggles, a different one starts. A refusal is stated by
    /// the player (which keeps the item reference) and returned to the host, which has the surface for a card that
    /// carries nothing playable at all.
    @discardableResult
    public func toggle(cardID: PublicationCardID) async -> ReaderMediaIntentOutcome {
        if state.item?.cardID == cardID, state.item != nil {
            if state.isPlaying { await player.pause() } else { await player.resume() }
            return .handled
        }
        let item: ReaderMediaItem
        do { item = try await mediaItem(cardID: cardID) }
        catch {
            let message = Self.message(for: error)
            await player.reportUnavailable(message, item: nil)
            return .unavailable(message)
        }
        do { try await player.play(item) }
        catch {
            // The occurrence exists but the player refused it: the bar can name it, so it keeps the reference.
            let message = Self.message(for: error)
            await player.reportUnavailable(message, item: item)
            return .unavailable(message)
        }
        return .handled
    }

    /// Plays the card's own playable payload. A card that does not carry one is reported, never guessed at.
    public func play(cardID: PublicationCardID) async throws {
        try await player.play(mediaItem(cardID: cardID))
    }

    /// The occurrence's own playable payload, resolved once per intent.
    private func mediaItem(cardID: PublicationCardID) async throws -> ReaderMediaItem {
        let target = try await ReaderActionCoordinator(database: database).perform(.openMedia, cardID: cardID)
        guard case .media(let media) = target else {
            throw ReaderActionError.actionUnavailable(.openMedia)
        }
        return ReaderMediaItem(cardID: cardID, url: media.url, title: media.title,
            mimeType: media.mimeType, source: media.source)
    }

    public func pause() async { await player.pause() }
    public func resume() async { await player.resume() }
    public func skip(by seconds: TimeInterval) async { await player.skip(by: seconds) }
    public func seek(to seconds: TimeInterval) async { await player.seek(to: seconds) }
    public func stop() async { await player.stop() }

    /// A surface that cannot play states why, in the reader's own words; the player's own errors are already
    /// stated by the adapter.
    private static func message(for error: any Error) -> String {
        switch error {
        case ReaderActionError.actionUnavailable: return String(localized: "Este card não tem o que tocar")
        case ReaderActionError.cardNotFound: return String(localized: "Este card não está mais disponível")
        case ReaderActionError.unusableReference: return String(localized: "Este card não tem o que tocar")
        default: return String(localized: "Não foi possível tocar este card")
        }
    }
}
