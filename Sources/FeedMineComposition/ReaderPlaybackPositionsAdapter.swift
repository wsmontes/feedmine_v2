//
// File: ReaderPlaybackPositionsAdapter.swift
// Module: FeedMineComposition
//
// Responsibility:
// The reader's playback positions as the player needs them: synchronous reads and writes over the durable store,
// so a time observer can ask for a position without awaiting anything and the app never touches the database
// itself.
//
// Does not own: the storage (Persistence), the rules about when a position is worth restoring (Runtime, V1's own
// threshold) or playback (the app's adapter).
import Foundation
import FeedMineDomain
import FeedMinePersistence
import FeedMineRuntime

@MainActor
public final class ReaderPlaybackPositionsAdapter: ReaderPlaybackPositions {
    /// The database, opened when first needed: the player is built before the app's composition has a database
    /// handle, and a preview or a test never opens one at all.
    private let database: () -> RuntimeDatabase?
    private var opened: RuntimeDatabase?

    public init(database: @escaping () -> RuntimeDatabase?) { self.database = database }

    public convenience init(database: RuntimeDatabase) { self.init(database: { database }) }

    private var store: PlaybackPositionStore? {
        if let opened { return PlaybackPositionStore(database: opened) }
        guard let next = database() else { return nil }
        opened = next
        return PlaybackPositionStore(database: next)
    }

    public func position(for cardID: PublicationCardID) -> TimeInterval? {
        let position = (try? store?.position(for: cardID))??.position
        return ReaderPlaybackPositionRules.isResumable(position) ? position : nil
    }

    public func save(position: TimeInterval, duration: TimeInterval?, for cardID: PublicationCardID) {
        // Every write is kept: the player already states the cadence (`saveInterval`), and a seek or a pause must
        // land even when it is close to what was written a moment ago.
        guard position > 0 else { return }
        try? store?.save(position, duration: duration, for: cardID)
    }

    public func clear(cardID: PublicationCardID) {
        try? store?.clear(for: cardID)
    }
}
