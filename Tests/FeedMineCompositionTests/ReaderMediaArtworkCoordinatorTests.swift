import CoreGraphics
import Foundation
import XCTest
import FeedMineDomain
@testable import FeedMinePersistence
import FeedMineComposition
import FeedMineRuntime

/// The coordinator's half of the cover: it asks the host for the pixels of the occurrence it is about to play,
/// in the same pass that resolves the payload, and never invents one when the host cannot name it.
@MainActor
final class ReaderMediaArtworkCoordinatorTests: XCTestCase {
    private final class FakePlayer: ReaderMediaPlaying {
        var state: ReaderMediaState = .idle
        private(set) var played: [ReaderMediaItem] = []

        func play(_ item: ReaderMediaItem) async throws {
            played.append(item)
            state = ReaderMediaState(item: item, isPlaying: true, position: 0, duration: 120, error: nil)
        }
        func pause() async { state = state.reporting(position: state.position, duration: state.duration, isPlaying: false) }
        func resume() async { state = state.reporting(position: state.position, duration: state.duration, isPlaying: true) }
        func skip(by seconds: TimeInterval) async {}
        func seek(to seconds: TimeInterval) async {}
        func stop() async { state = .idle }
        func reportUnavailable(_ message: String, item: ReaderMediaItem?) async { state = .idle }
    }

    private func card(_ kind: String?, _ reference: String?) -> PublicationStore.CardRecord {
        .init(id: PublicationCardID(), originRecordID: OriginRecordID(), originRevisionID: OriginRevisionID(),
            sourceID: nil, providerID: nil, sourceDisplayName: "Fonte", providerDisplayName: nil,
            contentEntityID: nil, contentClusterID: nil, title: "Episódio", primaryText: " texto ",
            timestampValue: nil, timestampKind: nil, mediaKey: " ", mediaPixelWidth: 300, mediaPixelHeight: 200,
            mediaMimeType: "audio/mpeg", renderLayout: "hero", renderMediaAspectRatio: 1.0,
            primaryActionKind: kind, primaryActionReference: reference)
    }

    private func published(_ cards: [PublicationStore.CardRecord]) throws -> RuntimeDatabase {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let database = try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
        let store = PublicationStore(database: database)
        let revision = EditorialRevision(id: EditorialRevisionID(), contextKey: ContextKey(request: .main),
            catalogGeneration: .init(rawValue: 1), userSelectionVersion: PolicyVersion(rawValue: 1),
            eligibilityPolicyVersion: PolicyVersion(rawValue: 2), scoringPolicyVersion: PolicyVersion(rawValue: 1),
            sequencingPolicyVersion: PolicyVersion(rawValue: 2), exposurePolicyVersion: PolicyVersion(rawValue: 2),
            selectionSchemaVersion: .init(rawValue: 1))
        let edition = PublicationStore.EditionRecord(id: FeedEditionID(), editorialRevision: revision,
            publicationSchemaVersion: 1, selectionSeed: UInt64.max, createdAt: Date(timeIntervalSince1970: 1))
        let segment = PublicationStore.SegmentRecord(id: FeedSegmentID(), editionID: edition.id, ordinal: 0,
            segmentSeed: UInt64.max, publicationSchemaVersion: 1, createdAt: Date(timeIntervalSince1970: 2),
            cardIDs: cards.map(\.id))
        try store.createEdition(edition, firstSegment: segment, cards: cards)
        return database
    }

    private func cover(key: String = "cover") throws -> PresentationImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8,
            bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return PresentationImage.decoded(key: key, cgImage: try XCTUnwrap(context.makeImage()))
    }

    func testTheCoordinatorHandsTheOccurrenceTheArtworkTheHostNamedOnce() async throws {
        let playable = card("mediaPlayback", "https://cdn.example/one.mp3")
        let player = FakePlayer()
        let artwork = try cover(key: "capa-do-episodio")
        var asked: [PublicationCardID] = []
        let coordinator = ReaderMediaCoordinator(database: try published([playable]), player: player,
            artworkProvider: { cardID in
                asked.append(cardID)
                return cardID == playable.id ? artwork : nil
            })

        await coordinator.toggle(cardID: playable.id)
        XCTAssertEqual(player.played.first?.artwork, artwork, "the played occurrence carries its own cover")
        XCTAssertEqual(asked, [playable.id])

        await coordinator.toggle(cardID: playable.id)
        XCTAssertEqual(asked, [playable.id], "pausing/resuming does not resolve the occurrence again")
    }

    /// The host may know some cards and not others: what it cannot name stays nil, and the surfaces show V1's
    /// waveform rather than a cover belonging to another episode.
    func testAHostThatCannotNameTheCardLeavesTheArtworkNil() async throws {
        let playable = card("mediaPlayback", "https://cdn.example/one.mp3")
        let player = FakePlayer()
        let coordinator = ReaderMediaCoordinator(database: try published([playable]), player: player,
            artworkProvider: { _ in nil })

        await coordinator.toggle(cardID: playable.id)
        XCTAssertEqual(player.played.count, 1)
        XCTAssertNil(player.played.first?.artwork)
    }

    /// Compatibility: the existing host passes no provider and nothing about playback changes.
    func testAHostWithoutAProviderPlaysTheSameOccurrenceWithoutArtwork() async throws {
        let playable = card("mediaPlayback", "https://cdn.example/one.mp3")
        let player = FakePlayer()
        let coordinator = ReaderMediaCoordinator(database: try published([playable]), player: player)

        await coordinator.toggle(cardID: playable.id)
        XCTAssertEqual(player.played.first?.cardID, playable.id)
        XCTAssertNil(player.played.first?.artwork)
    }
}
