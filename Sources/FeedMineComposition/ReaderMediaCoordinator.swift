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

@MainActor
public final class ReaderMediaCoordinator {
    private let database: RuntimeDatabase
    private let player: any ReaderMediaPlaying

    public init(database: RuntimeDatabase, player: any ReaderMediaPlaying) {
        self.database = database
        self.player = player
    }

    public var state: ReaderMediaState { player.state }

    /// V1's own tap behaviour, in one place: the same item toggles, a different one starts.
    public func toggle(cardID: PublicationCardID) async {
        if state.item?.cardID == cardID, state.item != nil {
            if state.isPlaying { await player.pause() } else { await player.resume() }
            return
        }
        do { try await play(cardID: cardID) }
        catch { await player.reportUnavailable(Self.message(for: error)) }
    }

    /// Plays the card's own playable payload. A card that does not carry one is reported, never guessed at.
    public func play(cardID: PublicationCardID) async throws {
        let target = try await ReaderActionCoordinator(database: database).perform(.openMedia, cardID: cardID)
        guard case .media(let media) = target else {
            throw ReaderActionError.actionUnavailable(.openMedia)
        }
        try await player.play(ReaderMediaItem(cardID: cardID, url: media.url, title: media.title,
            mimeType: media.mimeType))
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
