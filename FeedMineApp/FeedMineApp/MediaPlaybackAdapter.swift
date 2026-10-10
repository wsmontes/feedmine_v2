//
// File: MediaPlaybackAdapter.swift
// Module: FeedMineApp
//
// Responsibility:
// The only place in the app that links a media framework: AVFoundation behind the composition's own protocol
// (`ReaderMediaPlaying`), so no renderer and no package target imports or executes playback.
//
// Does not own: what plays (Composition resolves the occurrence's own payload), the surfaces (UI values) or the
// reader's layout.
import Foundation
import Observation
import AVFoundation
import FeedMineRuntime

@MainActor
@Observable
final class MediaPlaybackAdapter: ReaderMediaPlaying {
    private(set) var state: ReaderMediaState = .idle
    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var failureObservation: NSKeyValueObservation?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    init() {
        // One periodic observer for the whole session: it reports position and duration for whatever is playing.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
                Task { @MainActor in self?.report(time) }
            }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.finished() }
        }
        #if os(iOS)
        // V1 configured the session so an episode keeps playing with the silent switch on and in the background.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    /// The app's player lives as long as the composition does, so teardown is explicit rather than a `deinit`
    /// that a @MainActor class cannot use for its own non-Sendable observers (Swift 6).
    func teardown() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player.replaceCurrentItem(with: nil)
    }

    func play(_ item: ReaderMediaItem) async throws {
        let asset = AVURLAsset(url: item.url)
        let playable = try await asset.load(.isPlayable)
        guard playable else {
            state = ReaderMediaState(item: item, isPlaying: false, position: 0, duration: nil,
                error: String(localized: "Não foi possível tocar esta mídia"))
            throw MediaPlaybackError.notPlayable
        }
        statusObservation = nil
        failureObservation = nil
        let playerItem = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: playerItem)
        state = ReaderMediaState(item: item, isPlaying: false, position: 0, duration: nil, error: nil)
        failureObservation = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in
                self?.state = (self?.state ?? .idle).failing(item.error?.localizedDescription
                    ?? String(localized: "Não foi possível tocar esta mídia"))
            }
        }
        player.play()
        state = state.reporting(position: 0, duration: state.duration, isPlaying: true)
    }

    func pause() async {
        player.pause()
        state = state.reporting(position: state.position, duration: state.duration, isPlaying: false)
    }

    func resume() async {
        guard state.item != nil, player.currentItem != nil else { return }
        player.play()
        state = state.reporting(position: state.position, duration: state.duration, isPlaying: true)
    }

    func skip(by seconds: TimeInterval) async {
        guard player.currentItem != nil else { return }
        let target = max(0, state.position + seconds)
        await seek(to: target)
    }

    func seek(to seconds: TimeInterval) async {
        guard player.currentItem != nil else { return }
        let clamped = max(0, min(seconds, state.duration ?? seconds))
        await player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        state = state.reporting(position: clamped, duration: state.duration, isPlaying: state.isPlaying)
    }

    func reportUnavailable(_ message: String) async {
        player.pause()
        state = state.failing(message)
    }

    func stop() async {
        player.pause()
        player.replaceCurrentItem(with: nil)
        state = .idle
    }

    private func report(_ time: CMTime) {
        guard state.item != nil else { return }
        let seconds = time.seconds.isFinite ? max(0, time.seconds) : 0
        let duration = player.currentItem?.duration.seconds
        let known = duration.map { $0.isFinite && $0 > 0 ? $0 : nil } ?? nil
        state = state.reporting(position: seconds, duration: known, isPlaying: player.rate > 0)
    }

    /// Reaching the end is a state, not an error: the bar stays where it is with the item paused at its end.
    private func finished() {
        state = state.reporting(position: state.duration ?? state.position, duration: state.duration,
            isPlaying: false)
    }
}

enum MediaPlaybackError: Error { case notPlayable }
