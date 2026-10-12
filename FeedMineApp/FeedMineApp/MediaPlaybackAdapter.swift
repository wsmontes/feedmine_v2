//
// File: MediaPlaybackAdapter.swift
// Module: FeedMineApp
//
// Responsibility:
// The only place in the app that links a media framework: AVFoundation and MediaPlayer behind the composition's
// own protocol (`ReaderMediaPlaying`), so no renderer and no package target imports or executes playback.
//
// It is V1's `AudioPlayerManager` (498 lines, one global player), ported into the app's own adapter: the audio
// session the episode keeps playing under, the lock screen's own metadata and commands, what an incoming call and
// unplugged headphones do, and the position a reader comes back to. The rules that make those behaviours are
// named where they are applied, and the values (`ReaderPlaybackPositionRules`) are stated once in Runtime.
//
// Does not own: what plays (Composition resolves the occurrence's own payload), the surfaces (UI values), the
// reader's layout, or where a position is stored (a `ReaderPlaybackPositions` the host hands in).
//
// Two recorded differences from V1, both stated rather than silently dropped:
//   - the lock screen carries no artwork and no episode summary. V1 published the image its cache held and the
//     excerpt as `MPMediaItemPropertyComments`; `ReaderMediaItem` carries neither, and publishing the image means
//     handing the player a reference to the local image the card's slot already materialized (never a download);
//   - a position is written through the database on the main actor (V1's `UserDefaults` never touched disk
//     there). The write is one small row every five seconds; if a hitch ever shows up in the player path, it is
//     this call, and the fix is a serial background writer with the in-memory value kept synchronous.
import Foundation
import Observation
import AVFoundation
import MediaPlayer
import FeedMineDomain
import FeedMineRuntime

@MainActor
@Observable
final class MediaPlaybackAdapter: ReaderMediaPlaying {
    private(set) var state: ReaderMediaState = .idle
    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var failureObservation: NSKeyValueObservation?
    @ObservationIgnored private var timeControlObservation: NSKeyValueObservation?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var routeChangeObserver: NSObjectProtocol?
    /// What `MPRemoteCommandCenter` handed back, kept so this adapter can take its own handlers off the shared
    /// center. Today there is one adapter per app; a second one (a preview, a test) would otherwise double-handle
    /// every lock-screen command.
    @ObservationIgnored private var remoteCommandTargets: [(MPRemoteCommand, Any)] = []

    /// Where the reader stopped listening. Nil when the host did not provide one (a preview, a test): the player
    /// then simply has no memory, and says so by never restoring anything.
    @ObservationIgnored var positions: (any ReaderPlaybackPositions)?
    /// The card that reached its end. V1's own guard: only the end event completes an item, and a position is
    /// never saved for one that completed, so pausing in the final seconds keeps a real resume point while
    /// finishing does not resurrect one.
    @ObservationIgnored private var completedCardID: PublicationCardID?
    /// Invalidates callbacks captured by a player/item that has since been replaced or stopped (V1's own
    /// `playbackGeneration`).
    @ObservationIgnored private var generation: UInt64 = 0
    /// Counts the reader's own interactions with the item. A restore that is still waiting can then be abandoned
    /// when the reader seeks in the meantime, instead of dragging them back to where the app remembered.
    @ObservationIgnored private var interactionRevision: UInt64 = 0
    @ObservationIgnored private var lastSavedAt: TimeInterval = 0
    @ObservationIgnored private var lastNowPlayingUpdate: TimeInterval = 0
    /// What the periodic tick is allowed to write: the item and generation its sample belongs to.
    @ObservationIgnored private var tickCardID: PublicationCardID?
    @ObservationIgnored private var tickGeneration: UInt64 = 0

    init() {
        // V1's own cadence: half a second, which is what its scrubber and its five-second save were built on.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
                Task { @MainActor in self?.report(time) }
            }
        configureAudioSession()
        configureRemoteCommands()
        observeAudioSessionNotifications()
    }

    /// The item the reader is on, for a test that must post the event the system posts for it.
    var currentPlayerItem: AVPlayerItem? { player.currentItem }

    /// The end of an item is an event **of that item**: the observer is installed per item in `play(_:)` and
    /// removed with it, so a late event from an episode the reader has left cannot complete the one they are on.
    private func observeEnd(of item: AVPlayerItem, generation: UInt64) {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
            object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation, self.player.currentItem === item else { return }
                self.finished()
            }
        }
    }

    /// The app's player lives as long as the composition does, so teardown is explicit rather than a `deinit`
    /// that a @MainActor class cannot use for its own non-Sendable observers (Swift 6).
    func teardown() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        if let routeChangeObserver { NotificationCenter.default.removeObserver(routeChangeObserver) }
        routeChangeObserver = nil
        failureObservation = nil
        timeControlObservation = nil
        for (command, target) in remoteCommandTargets { command.removeTarget(target) }
        remoteCommandTargets = []
        player.pause()
        player.replaceCurrentItem(with: nil)
        completedCardID = nil
        lastSavedAt = 0
        state = .idle
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Audio session (background playback)

    private func configureAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        // The category and the long-form route policy are V1's; the **mode** is V2's choice — `.spokenAudio` is
        // the documented mode for podcasts and audiobooks, where V1 left it at `.default`.
        try? session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
        #endif
    }

    private func activateSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    // MARK: - Remote commands (lock screen and Control Center)

    /// Installs one handler and keeps the token, so `teardown` can take this adapter's handlers off the shared
    /// center again.
    private func wire(_ command: MPRemoteCommand,
        _ handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) {
        remoteCommandTargets.append((command, command.addTarget(handler: handler)))
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        // A play order is not a toggle: one received while the episode is already playing must not pause it
        // (V1's own S11 note — the lock screen carries both, and they used to fight over the same state).
        wire(center.playCommand) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.state.isPlaying else { return }
                await self.togglePlayPause()
            }
            return .success
        }
        wire(center.pauseCommand) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.state.isPlaying else { return }
                await self.togglePlayPause()
            }
            return .success
        }
        wire(center.togglePlayPauseCommand) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.togglePlayPause() }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        wire(center.skipForwardCommand) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.skip(by: Self.skipInterval) }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        wire(center.skipBackwardCommand) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.skip(by: -Self.skipInterval) }
            return .success
        }
        wire(center.changePlaybackPositionCommand) { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in await self?.seek(to: event.positionTime) }
            return .success
        }
        // There is no queue to move through: V1 disabled these, and so does V2 rather than letting the lock
        // screen draw controls that do nothing.
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
    }

    /// V1's own two skips, and the full player's (`FullPlayerView.skipInterval`).
    static let skipInterval: TimeInterval = 15

    // MARK: - Interruptions and route changes

    private func observeAudioSessionNotifications() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
            object: session, queue: .main) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor [weak self] in await self?.handleInterruption(typeRaw: type, optionsRaw: options) }
        }
        routeChangeObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification,
            object: session, queue: .main) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor [weak self] in self?.handleRouteChange(reasonRaw: reason) }
        }
        #endif
    }

    /// A call or Siri takes the session: the episode pauses and the reader's state says so; when the system says
    /// it may resume, it resumes (V1's `handleInterruption`).
    func handleInterruption(typeRaw: UInt?, optionsRaw: UInt?) async {
        #if os(iOS)
        guard let typeRaw, let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        switch type {
        case .began:
            guard state.isPlaying else { return }
            await pause()
        case .ended:
            guard let optionsRaw,
                AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume),
                state.item != nil, !state.isPlaying else { return }
            await resume()
        @unknown default:
            break
        }
        #endif
    }

    /// Unplugging the headphones pauses: V1 did the same, and continuing out loud is the worse surprise.
    func handleRouteChange(reasonRaw: UInt?) {
        #if os(iOS)
        guard let reasonRaw, let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw),
            reason == .oldDeviceUnavailable, state.isPlaying else { return }
        Task { @MainActor [weak self] in await self?.pause() }
        #endif
    }

    // MARK: - Now Playing

    /// What the lock screen and Control Center state. Throttled to once a second unless forced, because the time
    /// observer ticks twice as often (V1's own `lastNowPlayingUpdate`).
    func updateNowPlaying(force: Bool = false) {
        guard let item = state.item else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        if !force {
            let now = Date().timeIntervalSince1970
            guard now - lastNowPlayingUpdate >= 1 else { return }
            lastNowPlayingUpdate = now
        } else {
            lastNowPlayingUpdate = Date().timeIntervalSince1970
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title ?? String(localized: "Episódio"),
            MPMediaItemPropertyAlbumTitle: "Feedmine",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: state.position,
            MPMediaItemPropertyPlaybackDuration: max(state.duration ?? 0, 1),
            MPNowPlayingInfoPropertyPlaybackRate: state.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyAssetURL: item.url.absoluteString,
            // The reader's own key: a rapid episode switch must not let a stale entry keep the previous item.
            Self.nowPlayingCardKey: item.cardID.rawValue.uuidString,
        ]
        // V1 stated the program as the artist; a card that names none states none, rather than an empty line.
        if let source = item.source, !source.isEmpty { info[MPMediaItemPropertyArtist] = source }
        if let duration = state.duration, duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// V1's private key (`feedmineItemID`), so the same guard reads the same way.
    static let nowPlayingCardKey = "feedmineItemID"

    // MARK: - Playback

    func play(_ item: ReaderMediaItem) async throws {
        let asset = AVURLAsset(url: item.url)
        let playable = try await asset.load(.isPlayable)
        guard playable else {
            // V1's shape: a refused item never becomes the current one. Installing it here would leave the
            // previous episode audible under a bar naming the new one, and the next tick would save that episode's
            // position under the refused card. The caller reports the refusal through `reportUnavailable`.
            throw MediaPlaybackError.notPlayable
        }
        // Re-tapping the item that is already up never restarts it: the reader asked to hear it, not to begin
        // again — and an item that had finished starts over (V1's `prepareCompletedItemForReplay`).
        if state.item?.cardID == item.cardID, player.currentItem != nil {
            if completedCardID == item.cardID { prepareCompletedItemForReplay() }
            activateSession()
            player.play()
            state = state.reporting(position: state.position, duration: state.duration, isPlaying: true)
            updateNowPlaying(force: true)
            return
        }

        // Leaving one episode for another keeps where the reader was: the periodic save is up to five seconds
        // behind, and a switch must not throw those away (V1's `stop()` saved before it tore the player down).
        savePosition()
        generation &+= 1
        let generation = self.generation
        interactionRevision &+= 1
        tickCardID = item.cardID
        tickGeneration = generation
        completedCardID = nil
        lastSavedAt = 0
        activateSession()
        failureObservation = nil
        timeControlObservation = nil
        let playerItem = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: playerItem)
        observeEnd(of: playerItem, generation: generation)
        state = ReaderMediaState(item: item, isPlaying: false, position: 0, duration: nil, error: nil)
        failureObservation = playerItem.observe(\.status, options: [.new]) { [weak self] observed, _ in
            guard observed.status == .failed else { return }
            Task { @MainActor [weak self] in
                // An item the reader has already left cannot report a failure into the one they are on.
                guard let self, self.generation == generation else { return }
                self.state = self.state.failing(observed.error?.localizedDescription
                    ?? String(localized: "Não foi possível tocar esta mídia"))
            }
        }
        // V1 read the playing state from `timeControlStatus`: a player that is waiting to play is not playing.
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new, .initial]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                switch player.timeControlStatus {
                case .playing: self.setPlaying(true)
                case .paused: self.setPlaying(false)
                case .waitingToPlayAtSpecifiedRate: break
                @unknown default: break
                }
            }
        }
        player.play()
        state = state.reporting(position: 0, duration: state.duration, isPlaying: true)
        updateNowPlaying(force: true)
        restorePositionIfNeeded(for: item, generation: generation)
    }

    private func setPlaying(_ playing: Bool) {
        // An item that reached its end stays paused at its end until the reader does something — resuming it or
        // seeking into it clears the marker first. Otherwise the player's own status reports would flip the bar
        // back to "playing" for an episode that is over (V1's end-event rule, made explicit).
        guard completedCardID != state.item?.cardID else { return }
        guard state.isPlaying != playing else { return }
        state = state.reporting(position: state.position, duration: state.duration, isPlaying: playing)
        updateNowPlaying(force: true)
    }

    func pause() async {
        interactionRevision &+= 1
        player.pause()
        state = state.reporting(position: state.position, duration: state.duration, isPlaying: false)
        savePosition()
        updateNowPlaying(force: true)
    }

    func resume() async {
        guard state.item != nil, player.currentItem != nil else { return }
        activateSession()
        if let cardID = state.item?.cardID, completedCardID == cardID { prepareCompletedItemForReplay() }
        player.play()
        state = state.reporting(position: state.position, duration: state.duration, isPlaying: true)
        updateNowPlaying(force: true)
    }

    /// The lock screen's own toggle: play when paused, pause when playing.
    func togglePlayPause() async {
        // A play order for an item that was never chosen has nothing to resume; V1's `guard player != nil`
        // refused it the same way.
        guard state.item != nil, player.currentItem != nil else { return }
        if state.isPlaying { await pause() } else { await resume() }
    }

    func skip(by seconds: TimeInterval) async {
        guard player.currentItem != nil else { return }
        let target = max(0, state.position + seconds)
        await seek(to: target)
    }

    func seek(to seconds: TimeInterval) async {
        await seek(to: seconds, isRestore: false)
    }

    /// One seek, with the distinction that matters: a seek the **reader** asked for abandons any restore still
    /// waiting, so the app cannot drag them back to where it remembered after they moved themselves.
    private func seek(to seconds: TimeInterval, isRestore: Bool) async {
        guard player.currentItem != nil else { return }
        if !isRestore { interactionRevision &+= 1 }
        let generation = self.generation
        let item = state.item
        let clamped = max(0, min(seconds, state.duration ?? seconds))
        // Seeking back into an item that had finished makes it unfinished again (V1's own resurrection rule),
        // and lets it be resumed where it was left.
        if let cardID = state.item?.cardID, completedCardID == cardID,
            state.duration.map({ clamped < max(0, $0 - ReaderPlaybackPositionRules.completionTolerance) }) ?? true {
            completedCardID = nil
            lastSavedAt = 0
            positions?.clear(cardID: cardID)
        }
        await player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        // The seek suspends: the reader may have switched episodes while it ran, and then this seek belongs to
        // the item that is gone — nothing of it is written into the one that is up.
        guard self.generation == generation, player.currentItem != nil, state.item?.cardID == item?.cardID else {
            return
        }
        state = state.reporting(position: clamped, duration: state.duration, isPlaying: state.isPlaying)
        savePosition()
        updateNowPlaying(force: true)
    }

    func reportUnavailable(_ message: String) async {
        player.pause()
        state = state.failing(message)
        updateNowPlaying(force: true)
    }

    func stop() async {
        savePosition()
        generation &+= 1
        completedCardID = nil
        lastSavedAt = 0
        player.pause()
        player.replaceCurrentItem(with: nil)
        state = .idle
        updateNowPlaying(force: true)
    }

    // MARK: - Position

    /// Writes where the reader is. A card that reached its end has no position to come back to, which is what
    /// keeps a stop or a switch from resurrecting one (V1's `savePosition` guard, commented in its own code).
    func savePosition() {
        guard let item = state.item, state.position > 0, completedCardID != item.cardID else { return }
        positions?.save(position: state.position, duration: state.duration, for: item.cardID)
    }

    /// V1 restored a saved position only when it was past its threshold, and half a second after the item was
    /// handed to the player — seeking before the item is ready is a seek into nothing.
    private func restorePositionIfNeeded(for item: ReaderMediaItem, generation: UInt64) {
        guard completedCardID != item.cardID, let saved = positions?.position(for: item.cardID),
            ReaderPlaybackPositionRules.isResumable(saved) else { return }
        let revision = interactionRevision
        Task { @MainActor [weak self] in
            // V1 waited half a second after handing the item to the player; waiting for the item to be *ready*
            // is the honest form of the same thing (a seek into an item that is not ready lands nowhere).
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self else { return }
            // Slow media is exactly the case this feature is for: the wait holds while the readers' own guards
            // hold, and gives up only when the item refuses to become ready.
            for _ in 0..<200 {
                guard self.generation == generation, self.interactionRevision == revision,
                    self.state.item?.cardID == item.cardID, self.completedCardID != item.cardID,
                    self.player.currentItem?.status != .failed else { return }
                if self.player.currentItem?.status == .readyToPlay { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            guard self.generation == generation, self.interactionRevision == revision,
                self.state.item?.cardID == item.cardID, self.completedCardID != item.cardID,
                self.player.currentItem?.status == .readyToPlay else { return }
            await self.seek(to: saved, isRestore: true)
        }
    }

    /// An item that had finished starts over from the beginning, and its saved position goes with the marker.
    private func prepareCompletedItemForReplay() {
        guard let cardID = state.item?.cardID, completedCardID == cardID else { return }
        completedCardID = nil
        positions?.clear(cardID: cardID)
        lastSavedAt = 0
        player.seek(to: .zero)
        state = state.reporting(position: 0, duration: state.duration, isPlaying: state.isPlaying)
    }

    // MARK: - Reports

    private func report(_ time: CMTime) {
        guard state.item != nil else { return }
        // V1 kept its playback error in a field the tick never wrote. A tick that overwrote the refusal would
        // erase the only surface that explains why nothing is playing — and `reportUnavailable` pauses, which
        // guarantees one more tick.
        guard state.error == nil else { return }
        // A tick belongs to the item it was sampled for: the observer lives for the player's life, so a tick
        // queued while the reader was switching must not write the old timeline into the new episode.
        guard state.item?.cardID == tickCardID, generation == tickGeneration else { return }
        let seconds = time.seconds.isFinite ? max(0, time.seconds) : 0
        let duration = player.currentItem?.duration.seconds
        let known = duration.map { $0.isFinite && $0 > 0 ? $0 : nil } ?? nil
        guard completedCardID != state.item?.cardID else { return }
        state = state.reporting(position: seconds, duration: known, isPlaying: player.rate > 0)
        updateNowPlaying()
        if seconds - lastSavedAt >= ReaderPlaybackPositionRules.saveInterval, seconds > 0 {
            savePosition()
            lastSavedAt = seconds
        }
    }

    /// Reaching the end is a state, not an error: the bar stays where it is with the item paused at its end, and
    /// the position the reader had is cleared (V1's end observer).
    private func finished() {
        guard let item = state.item else { return }
        completedCardID = item.cardID
        positions?.clear(cardID: item.cardID)
        lastSavedAt = state.duration ?? state.position
        state = state.reporting(position: state.duration ?? state.position, duration: state.duration,
            isPlaying: false)
        updateNowPlaying(force: true)
    }
}

enum MediaPlaybackError: Error { case notPlayable }
