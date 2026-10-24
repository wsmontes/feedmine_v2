import XCTest
import Foundation
import AVFoundation
import MediaPlayer
import FeedMineDomain
import FeedMineRuntime
@testable import FeedMine

/// The app's player, driven through the same doors the system uses: V1's `AudioPlayerManager` behaviours — the
/// lock screen's own metadata and commands, what an interruption and unplugged headphones do, and the position a
/// reader comes back to.
///
/// The audio is a silent WAV written here, so playback is real (a real `AVPlayer`, a real ducking session) and
/// still has nothing to do with the network or the sound card.
@MainActor
final class PlaybackTests: XCTestCase {
    /// The positions the player was told about, owned by the test.
    private final class Positions: ReaderPlaybackPositions {
        var stored: [PublicationCardID: TimeInterval] = [:]
        private(set) var saved: [(cardID: PublicationCardID, position: TimeInterval)] = []
        private(set) var cleared: [PublicationCardID] = []

        func position(for cardID: PublicationCardID) -> TimeInterval? { stored[cardID] }

        func save(position: TimeInterval, duration: TimeInterval?, for cardID: PublicationCardID) {
            stored[cardID] = position
            saved.append((cardID, position))
        }

        func clear(cardID: PublicationCardID) {
            stored[cardID] = nil
            cleared.append(cardID)
        }
    }

    private func episode(_ id: PublicationCardID = PublicationCardID(), title: String = "Episódio de teste",
        seconds: Int = 30) throws -> ReaderMediaItem {
        ReaderMediaItem(cardID: id, url: try Self.silentWave(seconds: seconds), title: title, mimeType: "audio/wav")
    }

    private static func silentWave(seconds: Int) throws -> URL {
        let sampleRate = 8_000, samples = sampleRate * seconds
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + samples))
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate)); append(UInt16(1)); append(UInt16(8))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(samples))
        data.append(contentsOf: [UInt8](repeating: 128, count: samples))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("feedmine-playback-\(UUID().uuidString).wav")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Waits for a fact the player produces on its own schedule (a time observer, an asset load).
    private func wait(_ seconds: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    /// Playing states the item, and the lock screen gets V1's own dictionary: title, rate, duration and the
    /// reader's key.
    func testPlayingStatesTheItemAndWhatTheLockScreenShows() async throws {
        let positions = Positions()
        let adapter = MediaPlaybackAdapter()
        adapter.positions = positions
        defer { adapter.teardown() }
        let item = try episode(title: "Um episódio")

        try await adapter.play(item)
        XCTAssertEqual(adapter.state.item, item)
        XCTAssertTrue(adapter.state.isPlaying, "the player plays what it was handed")
        let info = try XCTUnwrap(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        XCTAssertEqual(info[MPMediaItemPropertyTitle] as? String, "Um episódio")
        XCTAssertEqual(info[MPMediaItemPropertyArtist] as? String, nil)
        XCTAssertEqual(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 1.0)
        XCTAssertEqual(info[MPMediaItemPropertyAlbumTitle] as? String, "Feedmine")
        XCTAssertEqual(info[MPNowPlayingInfoPropertyAssetURL] as? String, item.url.absoluteString)
        XCTAssertEqual(info[MediaPlaybackAdapter.nowPlayingCardKey] as? String, item.cardID.rawValue.uuidString)

        await adapter.seek(to: 6)
        await adapter.pause()
        XCTAssertFalse(adapter.state.isPlaying)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0)
        XCTAssertTrue(positions.saved.contains { $0.cardID == item.cardID && $0.position == 6 },
            "pausing writes where the reader is — V1 saved on the way out too")
    }

    /// A position past the threshold is resumed; one before it is not (V1's own five seconds).
    func testASavedPositionIsResumedOnlyPastTheThreshold() async throws {
        let positions = Positions()
        let adapter = MediaPlaybackAdapter()
        adapter.positions = positions
        defer { adapter.teardown() }
        let item = try episode()

        positions.stored[item.cardID] = 3
        try await adapter.play(item)
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertLessThan(adapter.state.position, 2,
            "three seconds in is not worth resuming: it plays from the start, at \(adapter.state.position)")

        await adapter.stop()
        positions.stored[item.cardID] = 20
        try await adapter.play(item)
        let resumed = await wait { adapter.state.position >= 19 }
        XCTAssertTrue(resumed,
            "a position past the threshold is where the reader comes back to; at \(adapter.state.position)")
    }

    /// An interruption pauses and states it; when the system says the reader may resume, it resumes.
    func testAnInterruptionPausesAndResumesWhenAllowed() async throws {
        let adapter = MediaPlaybackAdapter()
        adapter.positions = Positions()
        defer { adapter.teardown() }
        try await adapter.play(try episode())

        await adapter.handleInterruption(typeRaw: AVAudioSession.InterruptionType.began.rawValue, optionsRaw: nil)
        XCTAssertFalse(adapter.state.isPlaying, "a call takes the session")
        XCTAssertTrue(adapter.state.item != nil, "and the episode is still the one the reader was on")

        await adapter.handleInterruption(typeRaw: AVAudioSession.InterruptionType.ended.rawValue,
            optionsRaw: AVAudioSession.InterruptionOptions.shouldResume.rawValue)
        XCTAssertTrue(adapter.state.isPlaying, "the system said it may resume")

        await adapter.handleInterruption(typeRaw: AVAudioSession.InterruptionType.ended.rawValue, optionsRaw: 0)
        XCTAssertTrue(adapter.state.isPlaying,
            "an interruption that ends without the option does not pause what is already playing")
    }

    /// Unplugging the headphones pauses, as V1 decided: continuing out loud is the worse surprise.
    func testUnpluggingHeadphonesPauses() async throws {
        let adapter = MediaPlaybackAdapter()
        adapter.positions = Positions()
        defer { adapter.teardown() }
        try await adapter.play(try episode())

        adapter.handleRouteChange(reasonRaw: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue)
        let paused = await wait { !adapter.state.isPlaying }
        XCTAssertTrue(paused, "the episode pauses when the headphones go")

        adapter.handleRouteChange(reasonRaw: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue)
        XCTAssertFalse(adapter.state.isPlaying, "and plugging something in does not start it")
    }

    /// Reaching the end is a state, not an error: the bar stays at the end, the item pauses, and the position the
    /// reader had is cleared — while seeking back into it makes it resumable again.
    func testReachingTheEndClearsThePositionAndSeekingBackRestoresIt() async throws {
        let positions = Positions()
        let adapter = MediaPlaybackAdapter()
        adapter.positions = positions
        defer { adapter.teardown() }
        let item = try episode()

        try await adapter.play(item)
        await adapter.seek(to: 12)
        XCTAssertTrue(positions.saved.contains { $0.cardID == item.cardID && $0.position == 12 })

        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime,
            object: try XCTUnwrap(adapter.currentPlayerItem))
        let cleared = await wait { positions.cleared.contains(item.cardID) }
        XCTAssertTrue(cleared, "reaching the end clears the saved position")
        let stopped = await wait { !adapter.state.isPlaying }
        XCTAssertTrue(stopped, "and the bar stays at the end with the item paused; state: \(adapter.state)")
        XCTAssertTrue(positions.cleared.contains(item.cardID), "a finished episode has no position to come back to")
        XCTAssertFalse(positions.saved.contains { $0.position == 12 && $0.cardID == item.cardID
            && positions.cleared.isEmpty })

        // Seeking back into the last seconds makes it unfinished, and it can be left anywhere again.
        await adapter.seek(to: 8)
        XCTAssertTrue(positions.saved.contains { $0.position == 8 },
            "an episode sought back into is resumeable where the reader left it")
    }

    /// Playing the episode again starts over; playing the same episode does not restart it mid-listen.
    func testReplayingAfterTheEndStartsOverAndReplayingDoesNotRestart() async throws {
        let positions = Positions()
        let adapter = MediaPlaybackAdapter()
        adapter.positions = positions
        defer { adapter.teardown() }
        let item = try episode()

        try await adapter.play(item)
        await adapter.seek(to: 10)
        try await adapter.play(item)
        XCTAssertGreaterThan(adapter.state.position, 9, "the same episode is not restarted by asking for it again")

        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime,
            object: try XCTUnwrap(adapter.currentPlayerItem))
        _ = await wait { !adapter.state.isPlaying }
        try await adapter.play(item)
        XCTAssertLessThan(adapter.state.position, 2, "an episode that had finished starts over")
    }

    /// V1's own two skips and the commands the lock screen carries: what is wired, and what is deliberately not.
    func testTheLockScreensCommandsAreWiredAsV1HadThem() async throws {
        let adapter = MediaPlaybackAdapter()
        adapter.positions = Positions()
        defer { adapter.teardown() }
        try await adapter.play(try episode())

        let center = MPRemoteCommandCenter.shared()
        XCTAssertEqual(center.skipForwardCommand.preferredIntervals, [NSNumber(value: 15)])
        XCTAssertEqual(center.skipBackwardCommand.preferredIntervals, [NSNumber(value: 15)])
        XCTAssertFalse(center.nextTrackCommand.isEnabled, "there is no queue to move through")
        XCTAssertFalse(center.previousTrackCommand.isEnabled)
        XCTAssertTrue(center.playCommand.isEnabled)
        XCTAssertTrue(center.changePlaybackPositionCommand.isEnabled)

        // The function the toggle and pause/play handlers call: a play order while playing must not pause it.
        await adapter.togglePlayPause()
        XCTAssertFalse(adapter.state.isPlaying)
        await adapter.togglePlayPause()
        XCTAssertTrue(adapter.state.isPlaying)
    }

    /// A reader who seeks while the resume is still waiting keeps their own position: the restore is abandoned
    /// instead of dragging them back to where the app remembered.
    func testAReadersSeekAbandonsAPendingRestore() async throws {
        let positions = Positions()
        let adapter = MediaPlaybackAdapter()
        adapter.positions = positions
        defer { adapter.teardown() }
        let item = try episode()
        positions.stored[item.cardID] = 20

        try await adapter.play(item)
        // The restore waits half a second and then for the item to be ready; the reader moves in the meantime.
        try await Task.sleep(for: .milliseconds(150))
        await adapter.seek(to: 4)
        try await Task.sleep(for: .milliseconds(1_200))
        XCTAssertLessThan(adapter.state.position, 6,
            "the reader's own seek wins over the remembered position; at \(adapter.state.position)")
    }

    /// Leaving one episode for another keeps where the reader was in the one they left, without a pause or a stop
    /// in between.
    func testSwitchingEpisodesSavesThePositionOfTheOneLeft() async throws {
        let positions = Positions()
        let adapter = MediaPlaybackAdapter()
        adapter.positions = positions
        defer { adapter.teardown() }
        let first = try episode(title: "A"), second = try episode(title: "B")

        try await adapter.play(first)
        await adapter.seek(to: 13)
        try await adapter.play(second)
        XCTAssertTrue(positions.saved.contains { $0.cardID == first.cardID && $0.position == 13 },
            "the episode the reader left has its position written before the player is handed the next one")
        XCTAssertEqual(adapter.state.item?.cardID, second.cardID)

        // And coming back resumes it, because the switch did not lose it.
        try await adapter.play(first)
        let resumed = await wait { adapter.state.position >= 12 }
        XCTAssertTrue(resumed, "the first episode resumes where it was left; at \(adapter.state.position)")
    }

    /// An end event that is not the current item's cannot complete it: the observer is bound to the item, and a
    /// late event from an episode the reader has left is ignored.
    func testAForeignOrLateEndEventCannotCompleteTheCurrentEpisode() async throws {
        let positions = Positions()
        let adapter = MediaPlaybackAdapter()
        adapter.positions = positions
        defer { adapter.teardown() }
        let first = try episode(title: "A"), second = try episode(title: "B")

        try await adapter.play(first)
        let firstItem = try XCTUnwrap(adapter.currentPlayerItem)
        try await adapter.play(second)
        await adapter.seek(to: 7)

        // The item the reader left reports its end after the fact.
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: firstItem)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(adapter.state.item?.cardID, second.cardID, "the reader is still on the second episode")
        XCTAssertTrue(adapter.state.isPlaying, "and a late event did not pause it")
        XCTAssertEqual(adapter.state.position, 7, accuracy: 0.5, "nor moved it")
        XCTAssertFalse(positions.cleared.contains(second.cardID),
            "and it did not clear the position of the episode they are on")

        // The second episode's own event does complete it.
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime,
            object: try XCTUnwrap(adapter.currentPlayerItem))
        let stopped = await wait { !adapter.state.isPlaying }
        XCTAssertTrue(stopped)
        XCTAssertTrue(positions.cleared.contains(second.cardID))
    }

    /// What the lock screen states includes the program, as V1's own dictionary did.
    func testTheLockScreenStatesTheProgram() async throws {
        let adapter = MediaPlaybackAdapter()
        adapter.positions = Positions()
        defer { adapter.teardown() }
        try await adapter.play(ReaderMediaItem(cardID: PublicationCardID(),
            url: try Self.silentWave(seconds: 2), title: "Episódio 3", mimeType: "audio/wav",
            source: "O Meu Programa"))
        let info = try XCTUnwrap(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        XCTAssertEqual(info[MPMediaItemPropertyArtist] as? String, "O Meu Programa")
        XCTAssertEqual(info[MPMediaItemPropertyTitle] as? String, "Episódio 3")
    }

    /// A refused item never becomes the current one: the episode the reader is hearing keeps playing, and no
    /// position of it is written under the refused card.
    func testARefusedItemLeavesTheCurrentEpisodeAlone() async throws {
        let positions = Positions()
        let adapter = MediaPlaybackAdapter()
        adapter.positions = positions
        defer { adapter.teardown() }
        let playing = try episode(title: "Bom")
        try await adapter.play(playing)
        await adapter.seek(to: 9)

        let broken = ReaderMediaItem(cardID: PublicationCardID(),
            url: URL(string: "https://example.test/not-a-media-file")!, title: "Quebrado",
            mimeType: "audio/wav")
        do {
            try await adapter.play(broken)
            XCTFail("an item that is not playable must be refused")
        } catch {
            // Expected: the caller reports it.
        }
        XCTAssertEqual(adapter.state.item?.cardID, playing.cardID, "the reader is still on the episode they had")
        XCTAssertTrue(adapter.state.isPlaying)
        XCTAssertFalse(positions.saved.contains { $0.cardID == broken.cardID },
            "nothing of the refused card is written")
    }

    /// A refusal the reader must be told about is not wiped by the next tick — the player pauses on it, which
    /// guarantees one.
    func testARefusalIsNotWipedByTheNextTick() async throws {
        let adapter = MediaPlaybackAdapter()
        adapter.positions = Positions()
        defer { adapter.teardown() }
        try await adapter.play(try episode())
        await adapter.reportUnavailable("Sem nada para tocar", item: nil)
        let error = try XCTUnwrap(adapter.state.error)

        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(adapter.state.error, error, "the reason the reader was given must stay stated")
        XCTAssertFalse(adapter.state.isPlaying)
    }

    /// F15 R4: a first play that cannot happen keeps the occurrence and states the reason. The bar is gated on
    /// `state.item != nil`, so the reference is what makes the refusal visible at all; nothing is claimed playing.
    func testAFirstRefusalKeepsTheOccurrenceAndTheReason() async throws {
        let adapter = MediaPlaybackAdapter()
        adapter.positions = Positions()
        defer { adapter.teardown() }
        let item = try episode(title: "Episódio indisponível")
        let reason = String(localized: "Não foi possível tocar esta mídia")

        await adapter.reportUnavailable(reason, item: item)
        XCTAssertEqual(adapter.state.item, item, "the refused occurrence stays the bar's reference")
        XCTAssertEqual(adapter.state.error, reason)
        XCTAssertFalse(adapter.state.isPlaying)
        XCTAssertNil(adapter.currentPlayerItem, "nothing was installed for a payload the player refused")
    }

    /// A refusal never replaces the episode that is already installed: the reader keeps hearing it, and only the
    /// reason is stated.
    func testARefusalWhileSomethingIsInstalledKeepsTheCurrentEpisode() async throws {
        let adapter = MediaPlaybackAdapter()
        adapter.positions = Positions()
        defer { adapter.teardown() }
        let playing = try episode(title: "Bom")
        let refused = try episode(title: "Recusado")
        try await adapter.play(playing)

        await adapter.reportUnavailable("Não foi possível tocar este card", item: refused)
        XCTAssertEqual(adapter.state.item?.cardID, playing.cardID)
        XCTAssertNotNil(adapter.state.error)
        XCTAssertNotNil(adapter.currentPlayerItem)
    }

    /// A terminal item cannot be resumed: the reader's play intent creates a fresh item at the position they had,
    /// keeps the stated reason until playback really happens, and never claims `isPlaying` on the retry itself.
    func testATerminalFailureIsRetriedWithAFreshItemAndTheReasonStaysUntilItPlays() async throws {
        let adapter = MediaPlaybackAdapter()
        adapter.positions = Positions()
        defer { adapter.teardown() }
        let item = try episode(seconds: 30)
        try await adapter.play(item)
        await adapter.seek(to: 7)
        let failedItem = try XCTUnwrap(adapter.currentPlayerItem)

        // The status observation's own path (an item's status cannot be forced from outside AVFoundation).
        adapter.reportItemFailure(nil)
        let reason = try XCTUnwrap(adapter.state.error)
        XCTAssertFalse(adapter.state.isPlaying, "a failure is not a pause the bar may draw as playing")
        XCTAssertEqual(adapter.currentPlayerItem, failedItem, "the failed item stays installed for the reference")

        await adapter.resume()
        XCTAssertNotIdentical(adapter.currentPlayerItem, failedItem,
            "the retry creates a fresh AVPlayerItem instead of resuming a terminal one")
        // The retry may prove playback before `resume()` returns; what it may never do is clear the reason while
        // nothing plays. The old path cleared it and claimed `isPlaying` on the terminal item.
        if adapter.state.error == nil {
            XCTAssertTrue(adapter.state.isPlaying,
                "the reason is cleared only after the player reports playback")
        } else {
            XCTAssertEqual(adapter.state.error, reason,
                "the reason stays stated until the retry proves playback")
            XCTAssertFalse(adapter.state.isPlaying, "a retry does not claim playing before the player says so")
        }

        let playing = await wait { adapter.state.isPlaying && adapter.state.error == nil }
        XCTAssertTrue(playing, "the retry plays, and only then clears the reason; state: \(adapter.state)")
        let resumed = await wait { adapter.state.position >= 6 }
        XCTAssertTrue(resumed,
            "the retry keeps the reader where they were; at \(adapter.state.position)")
    }

    /// Teardown takes the item and the lock screen's dictionary with it: the app's player outlives every surface,
    /// so shutting it down is explicit.
    func testTeardownClearsTheItemAndTheLockScreen() async throws {
        let adapter = MediaPlaybackAdapter()
        adapter.positions = Positions()
        try await adapter.play(try episode())
        XCTAssertNotNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)

        adapter.teardown()
        XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        XCTAssertEqual(adapter.state, .idle)
    }
}
