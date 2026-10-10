import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence
import FeedMineComposition
import FeedMineRuntime
import FeedMineUI

/// T9: the reader's playback as the surfaces see it — the card's own tap behaviour, the state the bar draws, and
/// the rule that a card without a payload is reported rather than played.
@MainActor
final class ReaderMediaCoordinatorTests: XCTestCase {
    /// A player with no framework behind it: the state machine is what is under test, and a real player would
    /// only add a sound card to the equation.
    private final class FakePlayer: ReaderMediaPlaying {
        var state: ReaderMediaState = .idle
        private(set) var played: [ReaderMediaItem] = []
        private(set) var pauses = 0, resumes = 0, stops = 0
        private(set) var skips: [TimeInterval] = []
        private(set) var seeks: [TimeInterval] = []
        var refuses = false

        func play(_ item: ReaderMediaItem) async throws {
            if refuses { throw ReaderActionError.actionUnavailable(.openMedia) }
            played.append(item)
            state = ReaderMediaState(item: item, isPlaying: true, position: 0, duration: 120, error: nil)
        }

        func pause() async {
            pauses += 1
            state = state.reporting(position: state.position, duration: state.duration, isPlaying: false)
        }

        func resume() async {
            resumes += 1
            state = state.reporting(position: state.position, duration: state.duration, isPlaying: true)
        }

        func skip(by seconds: TimeInterval) async { skips.append(seconds) }

        func seek(to seconds: TimeInterval) async { seeks.append(seconds) }

        func reportUnavailable(_ message: String) async { state = state.failing(message) }

        func stop() async {
            stops += 1
            state = .idle
        }
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

    /// V1's card behaviour: the same episode toggles, another starts, and the state follows the player.
    func testTappingTheSameCardTogglesAndAnotherStarts() async throws {
        let first = card("mediaPlayback", "https://cdn.example/one.mp3")
        let second = card("mediaPlayback", "https://cdn.example/two.mp3")
        let player = FakePlayer()
        let coordinator = ReaderMediaCoordinator(database: try published([first, second]), player: player)
        await coordinator.toggle(cardID: first.id)
        XCTAssertEqual(player.played.count, 1)
        XCTAssertTrue(coordinator.state.isPlaying)
        XCTAssertEqual(coordinator.state.item?.cardID, first.id)
        XCTAssertEqual(coordinator.state.item?.url, URL(string: "https://cdn.example/one.mp3"))
        await coordinator.toggle(cardID: first.id)
        XCTAssertEqual(player.pauses, 1)
        XCTAssertFalse(coordinator.state.isPlaying)
        XCTAssertEqual(player.played.count, 1, "pausing does not start anything")
        await coordinator.toggle(cardID: first.id)
        XCTAssertEqual(player.resumes, 1)
        XCTAssertTrue(coordinator.state.isPlaying)
        await coordinator.toggle(cardID: second.id)
        XCTAssertEqual(player.played.count, 2, "a different episode starts its own playback")
        XCTAssertEqual(coordinator.state.item?.cardID, second.id)
    }

    /// A card without a playable payload is reported, and the state it leaves behind says why.
    func testACardWithoutPlaybackIsReportedAndNeverPlayed() async throws {
        let article = card("externalURL", "https://example.com/artigo")
        let player = FakePlayer()
        let coordinator = ReaderMediaCoordinator(database: try published([article]), player: player)
        await coordinator.toggle(cardID: article.id)
        XCTAssertTrue(player.played.isEmpty, "nothing was handed to the player")
        XCTAssertNotNil(coordinator.state.error)
        XCTAssertFalse(coordinator.state.isPlaying)
        // And a player that refuses is stated too.
        let playable = card("mediaPlayback", "https://cdn.example/ep.mp3")
        let refusing = FakePlayer()
        refusing.refuses = true
        let other = ReaderMediaCoordinator(database: try published([playable]), player: refusing)
        await other.toggle(cardID: playable.id)
        XCTAssertNotNil(other.state.error)
    }

    /// The intents the surfaces issue reach the player, and progress is a value the bar can draw.
    func testSurfaceIntentsReachThePlayerAndProgressIsAValue() async throws {
        let playable = card("mediaPlayback", "https://cdn.example/ep.mp3")
        let player = FakePlayer()
        let coordinator = ReaderMediaCoordinator(database: try published([playable]), player: player)
        try await coordinator.play(cardID: playable.id)
        await coordinator.skip(by: 15)
        await coordinator.seek(to: 30)
        await coordinator.pause()
        await coordinator.resume()
        await coordinator.stop()
        XCTAssertEqual(player.skips, [15])
        XCTAssertEqual(player.seeks, [30])
        XCTAssertEqual(player.stops, 1)
        XCTAssertEqual(coordinator.state, ReaderMediaState.idle)
        // Progress: a value when the length is known, nil when it is not (V1 drew an indeterminate bar rather
        // than a bar at zero).
        XCTAssertEqual(ReaderMediaState(item: nil, isPlaying: true, position: 30, duration: 120, error: nil).progress,
            0.25)
        XCTAssertNil(ReaderMediaState(item: nil, isPlaying: true, position: 30, duration: nil, error: nil).progress)
        XCTAssertEqual(ReaderMediaState(item: nil, isPlaying: true, position: 500, duration: 120, error: nil).progress,
            1, "a position beyond the length is clamped, never drawn past the end")
        XCTAssertEqual(ReaderMediaState(item: nil, isPlaying: false, position: 0, duration: 0, error: nil).progress, nil)
    }

    /// The full player states the same clock V1 did, including an hour-long episode.
    func testTheFullPlayerClock() {
        XCTAssertEqual(FullPlayerView.clock(0), "0:00")
        XCTAssertEqual(FullPlayerView.clock(59.9), "0:59")
        XCTAssertEqual(FullPlayerView.clock(600), "10:00")
        XCTAssertEqual(FullPlayerView.clock(3661), "1:01:01")
        XCTAssertEqual(FullPlayerView.clock(.nan), "0:00")
        XCTAssertEqual(MiniPlayerBar.height, 56, "the bar's height is a constant, not a measurement")
    }
}
