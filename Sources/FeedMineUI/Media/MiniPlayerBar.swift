//
// File: MiniPlayerBar.swift
// Module: FeedMineUI
//
// Responsibility:
// V1's mini player and its full sheet, as values over `ReaderMediaState`. The bar reserves a **constant** height
// whatever it states — playing, paused, loading or failed — so reporting playback can never change the feed's
// geometry (the same rule T3 states for work feedback). What V1 had and this draws: the episode's own admitted
// artwork, the program it belongs to, an elapsed clock, the stop that closes playback, and a full player whose
// scrub is a local draft committed only on release, whose menu is the card's real actions.
//
// Does not own: playback (a platform adapter), the item's identity or its cover (Composition/Runtime), or the
// surface that hosts the bar (the app's shell). A control the host cannot execute is not drawn: `onStop` nil
// means no close button, and the menu offers only `availableActions` with an `onAction` to execute them.
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import FeedMineDomain
import FeedMineRuntime

public struct MiniPlayerBar: View {
    private let state: ReaderMediaState
    private let appearance: ReaderAppearance
    /// The host's intents: the bar never reaches a player itself.
    private let onToggle: () -> Void
    private let onOpen: () -> Void
    /// V1's close: stops the episode and takes the bar away. Optional so an existing host compiles unchanged; the
    /// control is drawn only when the host can really stop playback.
    private let onStop: (() -> Void)?

    /// V1's bar height. A constant, not a measurement: the feed above it must not move when the reader plays.
    public static let height: CGFloat = 56

    public init(state: ReaderMediaState, appearance: ReaderAppearance = .standard,
        onToggle: @escaping () -> Void, onOpen: @escaping () -> Void, onStop: (() -> Void)? = nil) {
        self.state = state
        self.appearance = appearance
        self.onToggle = onToggle
        self.onOpen = onOpen
        self.onStop = onStop
    }

    public var body: some View {
        HStack(spacing: 10) {
            ReaderArtworkView(artwork: state.item?.artwork, size: 40, cornerRadius: 6,
                identifier: "mini-player-artwork-image", fallbackIdentifier: "mini-player-artwork-fallback",
                symbolSize: 15, appearance: appearance)
                // V1's whole bar opened the player: the cover is part of that row, not a dead thumbnail.
                .onTapGesture(perform: onOpen)

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: state.item?.title ?? String(localized: "Sem título"))
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityIdentifier("mini-player-title")
                    if let source = state.item?.source, !source.isEmpty {
                        Text(verbatim: source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .accessibilityIdentifier("mini-player-source")
                    }
                    // F15 R4: a refusal is stated in words, not only by the warning glyph — the bar names the
                    // item that could not play and stays the destination to the full player's own reason. The
                    // program stays above it: the reader must still know *what* failed.
                    if let error = state.error {
                        Text(verbatim: error)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .accessibilityIdentifier("mini-player-error")
                    }
                }
                // The row fills the bar: opening the player is the whole bar's own gesture (V1's), and the
                // bar's element then measures the height the bar reserves.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // V1's elapsed clock, in the same monospaced digits so a tick never reflows the row.
            Text(verbatim: FullPlayerView.clock(state.position))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityIdentifier("mini-player-elapsed")

            Button(action: onToggle) {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mini-player-toggle")
            .accessibilityLabel(state.isPlaying ? String(localized: "Pausar") : String(localized: "Tocar"))

            if let onStop {
                Button(action: onStop) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mini-player-stop")
                .accessibilityLabel(String(localized: "Parar reprodução"))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Self.height)
        // The bar's own identity is the **row** that reserves `height`, and nothing else. `.contain` keeps the
        // controls' own elements (`mini-player-toggle`, `mini-player-title`) instead of replacing them — a plain
        // identifier here overrode them (measured).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mini-player")
        // V1 separated the bar with a hairline; the position line does that job and states where the episode is.
        // No length yet keeps V1's moving bar rather than a bar at zero, because zero would claim the item is over.
        .overlay(alignment: .top) {
            progress
        }
        #if DEBUG
        // The bar's own item identity, for the run that has to prove the player is on the card the reader
        // tapped: the title is a string that two cards can share, the published card id is not. Hidden from
        // layout, hit testing and VoiceOver (the same instrument `feed-window-proof` uses for the feed).
        .overlay(alignment: .topLeading) {
            Text(verbatim: state.item?.cardID.rawValue.uuidString ?? "")
                .font(.system(size: 1))
                .frame(width: 1, height: 1)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityIdentifier("mini-player-card")
        }
        #endif
        // V1's glass, applied **outside** the identified row: it is appearance, never the row's height. As a bottom
        // inset its background bleeds into the home-indicator safe area below the bar; identifying the container
        // that carried it reported 90.333 pt for this 56 pt row (56 + 34.333 pt of `safeAreaInset`, measured
        // 2026-10-26 on the `mini-player` frame).
        .background(.ultraThinMaterial, ignoresSafeAreaEdges: .bottom)
    }

    @ViewBuilder private var progress: some View {
        if let value = state.progress {
            ProgressView(value: value)
                .progressViewStyle(.linear)
                .tint(appearance.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 3)
                .clipped()
                .accessibilityIdentifier("mini-player-progress")
        } else {
            ProgressView()
                .progressViewStyle(.linear)
                .tint(appearance.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 3)
                .clipped()
                .accessibilityIdentifier("mini-player-progress")
        }
    }
}

/// V1's full player, as a sheet: the same intents, plus the two skips and a scrub. The artwork takes as much of
/// the height as the sheet can spare and never more than V1's 280 pt, so a compact landscape sheet and an
/// accessibility text size both keep the controls on screen; the content scrolls when the type is larger still.
public struct FullPlayerView: View {
    private let state: ReaderMediaState
    private let appearance: ReaderAppearance
    private let onToggle: () -> Void
    private let onSkip: (TimeInterval) -> Void
    private let onSeek: (TimeInterval) -> Void
    private let onClose: () -> Void
    /// What the host can execute for the playing occurrence, and how it executes it. Both are needed: a menu
    /// entry is drawn only for an action the host declared, and only when the host can run it. V1's own actions
    /// are the card's vocabulary (save/view source/add to collection/copy/share), never a second one.
    private let availableActions: Set<ReaderCardAction>
    private let isBookmarked: Bool
    private let onAction: ((ReaderCardActionEvent) -> Void)?

    /// V1's own skip step.
    public static let skipInterval: TimeInterval = 15
    /// V1's own artwork bound.
    public static let artworkLimit: CGFloat = 280

    /// A dragged position. It belongs to the item that was playing when the drag began, and is committed only
    /// when the reader lets go — the player's own 2 Hz reports never move the thumb under their finger.
    @State private var scrubDraft: TimeInterval?
    @State private var scrubDraftCardID: PublicationCardID?

    public init(state: ReaderMediaState, appearance: ReaderAppearance = .standard,
        onToggle: @escaping () -> Void, onSkip: @escaping (TimeInterval) -> Void,
        onSeek: @escaping (TimeInterval) -> Void, onClose: @escaping () -> Void,
        availableActions: Set<ReaderCardAction> = [], isBookmarked: Bool = false,
        onAction: ((ReaderCardActionEvent) -> Void)? = nil) {
        self.state = state
        self.appearance = appearance
        self.onToggle = onToggle
        self.onSkip = onSkip
        self.onSeek = onSeek
        self.onClose = onClose
        self.availableActions = availableActions
        self.isBookmarked = isBookmarked
        self.onAction = onAction
    }

    public var body: some View {
        VStack(spacing: 0) {
            // V1's Done lived in the toolbar and was reachable whatever the sheet did. A real row above the scroll
            // keeps it out of the artwork's way while staying visible when compact height or accessibility text
            // makes the content scroll.
            HStack {
                Spacer(minLength: 0)
                close
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            GeometryReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: 18) {
                        Capsule()
                            .fill(.secondary.opacity(0.4))
                            .frame(width: 36, height: 5)
                            .padding(.top, 4)

                        ReaderArtworkView(artwork: state.item?.artwork, size: artworkSize(in: proxy.size),
                            cornerRadius: artworkSize(in: proxy.size) * 0.071,
                            identifier: "full-player-artwork-image",
                            fallbackIdentifier: "full-player-artwork-fallback",
                            symbolSize: artworkSize(in: proxy.size) * 0.22, appearance: appearance)
                            .shadow(color: .black.opacity(0.16), radius: 14, y: 8)

                        titleBlock
                        scrub
                        controls
                        menu
                        badge
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: max(0, proxy.size.height - 16), alignment: .center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                    // Same rule as the bar: the sheet's own identity must not replace the skips' and the toggle's.
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("full-player")
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .onChange(of: state.item?.cardID) { _, _ in
            // The reader changed episode (or stopped) while a draft existed: the old timeline has no target.
            scrubDraft = nil
            scrubDraftCardID = nil
        }
    }

    /// A skip is the reader's own move: the draft the thumb was holding is no longer the truth, so it is dropped
    /// before the intent leaves. This is what makes ±15 s act from the position the player reports instead of from a
    /// thumb that is only a preview.
    private func skip(_ seconds: TimeInterval) {
        scrubDraft = nil
        scrubDraftCardID = nil
        onSkip(seconds)
    }

    // MARK: - Blocks

    @ViewBuilder private var titleBlock: some View {
        VStack(spacing: 4) {
            Text(verbatim: state.item?.title ?? String(localized: "Sem título"))
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .accessibilityIdentifier("full-player-title")
            if let source = state.item?.source, !source.isEmpty {
                Text(verbatim: source)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .accessibilityIdentifier("full-player-source")
            }
            if let error = state.error {
                Text(verbatim: error)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("full-player-error")
            }
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder private var scrub: some View {
        if let duration = state.duration, duration.isFinite, duration > 0 {
            VStack(spacing: 6) {
                // A real `UISlider`, not a SwiftUI `Slider`: the release is the fact that commits, and UIKit states
                // it explicitly (`touchUpInside`/`touchUpOutside`/`touchCancel`). SwiftUI's `onEditingChanged` is not
                // delivered for a programmatic or automation-driven set, which is how a draft outlived its gesture
                // and the thumb kept a position the player never took (measured 2026-10-27: 0:17 stayed after ±15 s).
                // A VoiceOver/Switch Control adjustment arrives as `valueChanged` with no touch — a complete intent —
                // and is committed immediately.
                PlayerScrubber(value: sliderValue(duration: duration), range: 0...duration,
                    tint: appearance.accent,
                    itemID: state.item?.cardID,
                    onEditingChanged: { editing in
                        if editing, scrubDraft == nil {
                            // The thumb is the reader's until they let go: seed the draft with the clock that was
                            // showing, bound to the item on screen at that instant.
                            scrubDraft = min(max(0, state.position), duration)
                            scrubDraftCardID = state.item?.cardID
                        }
                    },
                    onCommit: { value in
                        // A commit belongs to the item whose gesture produced it. If the episode changed under the
                        // finger, the draft is abandoned: relabelling it as the current card would seek an episode
                        // the reader never scrubbed.
                        guard scrubDraftCardID == nil || scrubDraftCardID == state.item?.cardID else {
                            scrubDraft = nil
                            scrubDraftCardID = nil
                            return
                        }
                        scrubDraft = value
                        scrubDraftCardID = state.item?.cardID
                        commitScrub(duration: duration)
                    },
                    onAbandon: {
                        // A cancelled gesture is not an intent: the draft goes, the player is not touched.
                        scrubDraft = nil
                        scrubDraftCardID = nil
                    })
                    .frame(height: 31)

                HStack {
                    Text(verbatim: Self.clock(displayedPosition))
                        .accessibilityIdentifier("full-player-position")
                    Spacer()
                    Text(verbatim: Self.clock(duration))
                        .accessibilityIdentifier("full-player-duration")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        } else {
            // The length is the player's fact, never the feed's declared number: until it is known there is no
            // honest scale to drag, and a slider over an invented length would claim one.
            Text(verbatim: state.error == nil
                ? String(localized: "Duração ainda desconhecida")
                : String(localized: "Sem reprodução"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 36) {
            Button { skip(-Self.skipInterval) } label: {
                Image(systemName: "gobackward.15")
                    .font(.title)
                    .frame(width: 56, height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("full-player-back15")
            .accessibilityLabel(Text(verbatim: String(localized: "Voltar 15 segundos")))

            Button(action: onToggle) {
                Image(systemName: state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(appearance.accent)
                    .frame(width: 72, height: 72)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("full-player-toggle")
            .accessibilityLabel(state.isPlaying ? String(localized: "Pausar") : String(localized: "Tocar"))

            Button { skip(Self.skipInterval) } label: {
                Image(systemName: "goforward.15")
                    .font(.title)
                    .frame(width: 56, height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("full-player-forward15")
            .accessibilityLabel(Text(verbatim: String(localized: "Avançar 15 segundos")))
        }
    }

    @ViewBuilder private var menu: some View {
        if !menuActions.isEmpty, let onAction {
            Menu {
                ForEach(menuActions, id: \.self) { action in
                    Button {
                        guard let cardID = state.item?.cardID else { return }
                        onAction(ReaderCardActionEvent(action: action, cardID: cardID))
                    } label: {
                        Label(Self.label(for: action, isBookmarked: isBookmarked),
                            systemImage: Self.symbol(for: action, isBookmarked: isBookmarked))
                    }
                    .accessibilityIdentifier("full-player-action-\(action.rawValue)")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("full-player-menu")
            .accessibilityLabel(Text(verbatim: String(localized: "Mais ações")))
        }
    }

    /// V1's podcast badge, drawn only from the length the **player** measured. A feed-declared duration is not a
    /// player fact and is deliberately not published here.
    @ViewBuilder private var badge: some View {
        if let duration = state.duration, duration.isFinite, duration > 0 {
            HStack(spacing: 4) {
                Image(systemName: "headphones")
                    .font(.caption2)
                Text(verbatim: String(localized: "Podcast") + " · " + Self.clock(duration))
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("full-player-duration-badge")
        }
    }

    private var close: some View {
        Button(String(localized: "Fechar"), action: onClose)
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("full-player-close")
    }

    // MARK: - Scrub

    private var displayedPosition: TimeInterval {
        guard let scrubDraft, scrubDraftCardID == state.item?.cardID else { return state.position }
        return scrubDraft
    }

    private func sliderValue(duration: TimeInterval) -> Binding<Double> {
        Binding(get: {
            ReaderMediaScrub.target(draft: scrubDraft, draftedCard: scrubDraftCardID,
                playingCard: state.item?.cardID, duration: duration)
                ?? min(max(0, state.position), duration)
        }, set: { value in
            scrubDraft = value
            scrubDraftCardID = state.item?.cardID
        })
    }

    /// Commit on release only. The draft is cleared first so a failed/ignored seek cannot leave the thumb on a
    /// position the player never took; the next tick owns the clock again.
    private func commitScrub(duration: TimeInterval) {
        defer {
            scrubDraft = nil
            scrubDraftCardID = nil
        }
        guard let target = ReaderMediaScrub.target(draft: scrubDraft, draftedCard: scrubDraftCardID,
            playingCard: state.item?.cardID, duration: duration) else { return }
        onSeek(target)
    }

    // MARK: - Artwork

    /// The largest square the sheet can spare, never beyond V1's 280 pt. Height leads so a landscape sheet keeps
    /// the scrub and the controls visible; the scroll view remains for accessibility text sizes.
    private func artworkSize(in container: CGSize) -> CGFloat {
        let widthLimit = max(72, container.width - 96)
        let heightLimit = max(72, container.height * 0.42)
        return min(Self.artworkLimit, widthLimit, heightLimit)
    }

    // MARK: - Actions

    private var menuActions: [ReaderCardAction] {
        guard onAction != nil else { return [] }
        return [.save, .viewSource, .addSourceToCollection, .copyLink, .share]
            .filter { availableActions.contains($0) }
    }

    private static func label(for action: ReaderCardAction, isBookmarked: Bool) -> String {
        switch action {
        case .save: return isBookmarked ? String(localized: "Remover dos salvos") : String(localized: "Salvar artigo")
        case .viewSource: return String(localized: "Ver a fonte")
        case .addSourceToCollection: return String(localized: "Adicionar fonte a uma coleção")
        case .copyLink: return String(localized: "Copiar link")
        case .share: return String(localized: "Compartilhar")
        case .open: return String(localized: "Abrir")
        case .openMedia: return String(localized: "Tocar")
        }
    }

    // Menu symbols are V1's card menu, so a reader who learned the card's menu recognizes the player's.
    private static func symbol(for action: ReaderCardAction, isBookmarked: Bool) -> String {
        switch action {
        case .save: return isBookmarked ? "bookmark.slash" : "bookmark"
        case .viewSource: return "rectangle.stack"
        case .addSourceToCollection: return "rectangle.stack.badge.plus"
        case .copyLink: return "doc.on.doc"
        case .share: return "square.and.arrow.up"
        case .open: return "safari"
        case .openMedia: return "play"
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

/// The player's scrub, over `UISlider` so the **release** is an explicit event.
///
/// SwiftUI's `Slider` reports its editing state through a closure that is not delivered for a programmatic or
/// automation-driven value write, which let a draft outlive its gesture: the thumb kept a position the player never
/// took and the clock stopped telling the truth (measured 2026-10-27: 0:17 stayed after ±15 s). UIKit states the
/// events themselves — `touchDown`, `valueChanged`, `touchUpInside`, `touchUpOutside`, `touchCancel` — and an
/// assistive-technology adjustment arrives as `valueChanged` with no touch at all, which is a complete intent and is
/// committed at once. Nothing here infers a release from time.
#if canImport(UIKit)
struct PlayerScrubber: UIViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let tint: Color
    /// The occurrence on screen when this control was built. A gesture carries the identity it started on, so a
    /// release that lands after the episode changed cannot seek the new one.
    let itemID: PublicationCardID?
    /// A drag began (`true`). The reader's thumb owns the clock until the release.
    let onEditingChanged: (Bool) -> Void
    /// The reader's finished intent: a release over the same occurrence, or one discrete accessibility adjustment.
    let onCommit: (Double) -> Void
    /// The gesture was cancelled, or it ended over a different occurrence: the draft is dropped and the player is
    /// not touched.
    let onAbandon: () -> Void

    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider()
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.value = Float(value)
        slider.isContinuous = true
        slider.accessibilityIdentifier = "full-player-scrub"
        slider.accessibilityLabel = String(localized: "Posição da reprodução")
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        // A VoiceOver adjustment is a value change with no touch in flight: it is the reader's whole intent.
        slider.isAccessibilityElement = true
        let coordinator = context.coordinator
        slider.addTarget(coordinator, action: #selector(Coordinator.touchDown), for: .touchDown)
        slider.addTarget(coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        slider.addTarget(coordinator, action: #selector(Coordinator.touchUp(_:)), for: .touchUpInside)
        slider.addTarget(coordinator, action: #selector(Coordinator.touchUp(_:)), for: .touchUpOutside)
        // A cancelled touch is not a release: nothing was chosen.
        slider.addTarget(coordinator, action: #selector(Coordinator.touchCancel(_:)), for: .touchCancel)
        return slider
    }

    func updateUIView(_ slider: UISlider, context: Context) {
        context.coordinator.parent = self
        slider.minimumTrackTintColor = UIColor(tint)
        // Never move the thumb under the reader's finger, and never overwrite a draft with a player report.
        if !slider.isTracking, abs(slider.value - Float(value)) > 0.001 { slider.value = Float(value) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject {
        var parent: PlayerScrubber
        private var isTracking = false
        /// The occurrence the current gesture started on.
        private var touchItem: PublicationCardID?

        init(parent: PlayerScrubber) { self.parent = parent }

        @objc func touchDown() {
            isTracking = true
            touchItem = parent.itemID
            parent.onEditingChanged(true)
        }

        @objc func valueChanged(_ slider: UISlider) {
            let value = Double(slider.value)
            parent.value = value
            guard !isTracking else { return }
            // No touch in flight: an assistive-technology step. It is complete on its own — but only for the
            // occurrence this control is showing.
            guard parent.itemID != nil, touchItem == nil || touchItem == parent.itemID else {
                parent.onAbandon()
                return
            }
            parent.onCommit(value)
        }

        @objc func touchUp(_ slider: UISlider) {
            let started = touchItem
            isTracking = false
            touchItem = nil
            // A release over a different occurrence is not a scrub of it: the episode changed under the finger.
            guard started == nil || started == parent.itemID else {
                parent.onAbandon()
                return
            }
            parent.onCommit(Double(slider.value))
        }

        /// The system cancelled the gesture (incoming call, another gesture taking over). Nothing was chosen.
        @objc func touchCancel(_ slider: UISlider) {
            isTracking = false
            touchItem = nil
            parent.onAbandon()
        }
    }
}
#else
/// macOS/tests: the same contract over the SwiftUI slider. The product path is iOS, where the UIKit control above
/// states the release explicitly; this keeps the package compiling on every platform it targets.
struct PlayerScrubber: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let tint: Color
    let itemID: PublicationCardID?
    let onEditingChanged: (Bool) -> Void
    let onCommit: (Double) -> Void
    let onAbandon: () -> Void

    var body: some View {
        Slider(value: $value, in: range) { editing in
            if editing {
                onEditingChanged(true)
            } else {
                onCommit(value)
            }
        }
        .tint(tint)
        .accessibilityIdentifier("full-player-scrub")
        .accessibilityLabel(Text(verbatim: String(localized: "Posição da reprodução")))
    }
}
#endif
