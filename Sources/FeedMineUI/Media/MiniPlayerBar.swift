//
// File: MiniPlayerBar.swift
// Module: FeedMineUI
//
// Responsibility:
// V1's mini player and its full sheet, as values over `ReaderMediaState`. The bar reserves a **constant** height
// whatever it states — playing, paused, loading or failed — so reporting playback can never change the feed's
// geometry (the same rule T3 states for work feedback).
//
// Does not own: playback (a platform adapter), the item's identity (Composition) or the surface that hosts the
// bar (the app's shell).
import SwiftUI
import FeedMineRuntime

public struct MiniPlayerBar: View {
    private let state: ReaderMediaState
    private let appearance: ReaderAppearance
    /// The host's intents: the bar never reaches a player itself.
    private let onToggle: () -> Void
    private let onOpen: () -> Void

    /// V1's bar height. A constant, not a measurement: the feed above it must not move when the reader plays.
    public static let height: CGFloat = 56

    public init(state: ReaderMediaState, appearance: ReaderAppearance = .standard,
        onToggle: @escaping () -> Void, onOpen: @escaping () -> Void) {
        self.state = state
        self.appearance = appearance
        self.onToggle = onToggle
        self.onOpen = onOpen
    }

    public var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mini-player-toggle")
            .accessibilityLabel(state.isPlaying ? String(localized: "Pausar") : String(localized: "Tocar"))

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: state.item?.title ?? String(localized: "Sem título"))
                        .font(.subheadline)
                        .lineLimit(1)
                        .accessibilityIdentifier("mini-player-title")
                    progress
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let error = state.error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityLabel(error)
            }
        }
        .padding(.horizontal, FeedDesignTokens.Spacing.page)
        .frame(height: Self.height)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
        .accessibilityIdentifier("mini-player")
    }

    @ViewBuilder private var progress: some View {
        if let value = state.progress {
            ProgressView(value: value)
                .progressViewStyle(.linear)
                .tint(appearance.accent)
                .accessibilityIdentifier("mini-player-progress")
        } else {
            // No length yet: V1 showed a moving bar rather than a bar at zero, because zero would claim the
            // item is over.
            ProgressView()
                .progressViewStyle(.linear)
                .tint(appearance.accent)
                .accessibilityIdentifier("mini-player-progress")
        }
    }
}

/// V1's full player, as a sheet: the same intents, plus the two skips and a scrub.
public struct FullPlayerView: View {
    private let state: ReaderMediaState
    private let appearance: ReaderAppearance
    private let onToggle: () -> Void
    private let onSkip: (TimeInterval) -> Void
    private let onSeek: (TimeInterval) -> Void
    private let onClose: () -> Void

    /// V1's own skip step.
    public static let skipInterval: TimeInterval = 15

    public init(state: ReaderMediaState, appearance: ReaderAppearance = .standard,
        onToggle: @escaping () -> Void, onSkip: @escaping (TimeInterval) -> Void,
        onSeek: @escaping (TimeInterval) -> Void, onClose: @escaping () -> Void) {
        self.state = state
        self.appearance = appearance
        self.onToggle = onToggle
        self.onSkip = onSkip
        self.onSeek = onSeek
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
            Text(verbatim: state.item?.title ?? String(localized: "Sem título"))
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 24)
                .accessibilityIdentifier("full-player-title")
            if let error = state.error {
                Text(verbatim: error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("full-player-error")
            }
            scrub
            HStack(spacing: 36) {
                Button { onSkip(-Self.skipInterval) } label: {
                    Image(systemName: "gobackward.15").font(.title)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("full-player-back15")
                Button(action: onToggle) {
                    Image(systemName: state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(appearance.accent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("full-player-toggle")
                Button { onSkip(Self.skipInterval) } label: {
                    Image(systemName: "goforward.15").font(.title)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("full-player-forward15")
            }
            Button(String(localized: "Fechar"), action: onClose)
                .accessibilityIdentifier("full-player-close")
            Spacer()
        }
        .padding(.top, 8)
        .accessibilityIdentifier("full-player")
    }

    @ViewBuilder private var scrub: some View {
        if let duration = state.duration, duration > 0 {
            VStack(spacing: 4) {
                Slider(value: Binding(get: { min(max(0, state.position), duration) },
                    set: { onSeek($0) }), in: 0...duration)
                    .tint(appearance.accent)
                    .accessibilityIdentifier("full-player-scrub")
                HStack {
                    Text(verbatim: Self.clock(state.position))
                    Spacer()
                    Text(verbatim: Self.clock(duration))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            }
        } else {
            Text(verbatim: String(localized: "Carregando…"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// V1's own `m:ss`, and the same for an hour-long episode.
    public static func clock(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let (hours, minutes, secs) = (total / 3600, (total % 3600) / 60, total % 60)
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
