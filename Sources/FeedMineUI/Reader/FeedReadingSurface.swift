//
// File: FeedReadingSurface.swift
// Module: FeedMineUI
// Owns: the local reading surface — what the reader sees when the app already holds text worth reading.
// Does not own: which card was opened, where the text came from, whether there is a network, or the site itself.
//       It renders the value it is given and reports the one request a reader can make from it: open the site.
//
// Architect's approved design (2026-10-11): source, headline, date and the stored text, with the origin of that
// text stated ("Resumo fornecido pela fonte" for a summary), partial content never presented as the article, and
// "Abrir no site" in the header *and* at the end. It honours Dynamic Type (the module's tokens are Dynamic Type
// styles, never fixed point sizes) and allows text selection; it reads nothing and fetches nothing.
//
// The note about completeness (review, 2026-10-17) states only what the app knows — the source supplied this text,
// and its completeness was not confirmed — and names the site only when the card carries an address the surface can
// offer. It never asserts a truncated text or an article available on the site: neither is established here.
import SwiftUI

/// What one scroll pass says about the sheet's gesture: how far the page is pulled down from its top edge, and
/// whether it is still there. Both are derived by `ReaderSheetPullDown`, so the surface owns no threshold.
private struct ReaderScrollObservation: Equatable {
    let pull: CGFloat
    let atTop: Bool
}

public struct FeedReadingSurface: View {
    public let content: FeedReadingContent
    public let appearance: ReaderAppearance
    /// The site, offered as an explicit request. Absent when the card carries no address: the surface then shows
    /// no way out rather than a control that cannot work.
    public let onOpenSite: (() -> Void)?
    public let onClose: () -> Void
    /// Whether the page is at its top edge, reported to the sheet that presents it. The sheet consults this when
    /// the platform asks whether its own drag may dismiss: a reader scrolled down through the text is not asking
    /// to leave it, while a reader at the top is.
    public let onTopChange: ((Bool) -> Void)?

    /// The sheet's pull-down rule, observed here and decided by `ReaderSheetPullDown`. The latch is taken when
    /// the reader's finger starts moving, not when the pull is already deep, so dragging back up through a page
    /// that was scrolled down cannot dismiss it. `isTrackingScroll` is SwiftUI's own phase, so a rubber-band
    /// settle, a programmatic scroll and a layout bounce are not gestures.
    @State private var isTrackingScroll = false
    @State private var gestureStartedAtTop = false
    @State private var isAtTop = true
    /// The request is made once. The dismissal is idempotent above this view too (button, native sheet drag and
    /// overscroll all end at the same finish), but a pull that keeps emitting offsets must not ask twice.
    @State private var dismissalRequested = false

    public init(content: FeedReadingContent, appearance: ReaderAppearance,
        onOpenSite: (() -> Void)? = nil, onClose: @escaping () -> Void,
        onTopChange: ((Bool) -> Void)? = nil) {
        self.content = content
        self.appearance = appearance
        self.onOpenSite = onOpenSite
        self.onClose = onClose
        self.onTopChange = onTopChange
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(appearance.separatorOpacity)
            ScrollView {
                VStack(alignment: .leading, spacing: FeedDesignTokens.Spacing.section) {
                    Text(verbatim: content.headline)
                        .font(FeedDesignTokens.Typography.cardTitle)
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("reading.headline")
                    metadata
                    origin
                    Text(verbatim: content.text)
                        .font(FeedDesignTokens.Typography.body)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("reading.body")
                }
                .frame(maxWidth: FeedDesignTokens.Measurement.readableContentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, FeedDesignTokens.Spacing.page)
                .padding(.vertical, FeedDesignTokens.Spacing.section)
            }
            // The sheet's explicit dismissal gesture, on the page that holds text. The system sheet already
            // dismisses on its own pull at the top; this is the same rule stated where the scroll view can see
            // it, so a page that consumes the overscroll still honours the gesture — and a page scrolled down
            // does not: the latch is taken when the drag starts, never re-read at depth.
            .readerSheetPullDown(isTrackingScroll: $isTrackingScroll,
                gestureStartedAtTop: $gestureStartedAtTop, isAtTop: $isAtTop,
                dismissalRequested: $dismissalRequested, onTopChange: onTopChange, onClose: onClose)
            footer
        }
        .background(appearance.pageBackground)
        // The visible control stays the primary path; this is the same dismissal reachable as an accessibility
        // action on the page itself, for a reader who cannot reach the header's button.
        .accessibilityAction(named: Text("Fechar")) { onClose() }
    }

    /// The source, and the one exit the reader can take from here.
    private var header: some View {
        HStack(spacing: FeedDesignTokens.Spacing.normal) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("reading.close")
            .accessibilityLabel(String(localized: "Fechar"))
            // A hardware keyboard's Escape is the same dismissal, for a reader who never touches the grabber.
            .keyboardShortcut(.cancelAction)

            Text(verbatim: content.sourceName)
                .font(FeedDesignTokens.Typography.label)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityIdentifier("reading.source")

            Spacer(minLength: 0)

            if let onOpenSite {
                // At the accessibility sizes a one-line text truncated to "Abrir…". The header now shows a short
                // visual label beside an *external-opening* glyph — never the share icon: this action opens the
                // publication, it does not share it. The accessibility label stays the full sentence.
                Button(action: onOpenSite) {
                    Label("Site", systemImage: "arrow.up.forward.app")
                        .font(FeedDesignTokens.Typography.label)
                        .lineLimit(1)
                        .fixedSize()
                }
                .accessibilityIdentifier("reading.open-site")
                .accessibilityLabel("Abrir no site")
            }
        }
        .tint(appearance.accent)
        .padding(.horizontal, FeedDesignTokens.Spacing.compact)
        .padding(.vertical, FeedDesignTokens.Spacing.tight)
    }

    private var metadata: some View {
        HStack(spacing: FeedDesignTokens.Spacing.compact) {
            if let publishedAt = content.publishedAt {
                Text(publishedAt, format: .dateTime.day().month().year())
                    .font(FeedDesignTokens.Typography.metadata)
                    .foregroundStyle(FeedDesignTokens.Palette.secondaryText)
                    .accessibilityIdentifier("reading.date")
            }
        }
    }

    /// What this text is, and what the app can say about it. A summary is a summary; a feed's body is what the
    /// source chose to publish. Neither can be certified as the article, so the note states only that the source
    /// supplied the text and that completeness was not confirmed — and names the site only when the card carries
    /// an address the surface can actually offer. It never promises the article, extraction, or that the site is
    /// reachable: none of those are established here.
    private var origin: some View {
        VStack(alignment: .leading, spacing: FeedDesignTokens.Spacing.tight) {
            Text(verbatim: content.origin.label)
                .font(FeedDesignTokens.Typography.badge)
                .foregroundStyle(appearance.accent)
                .accessibilityIdentifier("reading.origin")
            if content.isPartial {
                Text(verbatim: FeedReadingWording.note(offersSite: content.siteURL != nil))
                    .font(FeedDesignTokens.Typography.metadata)
                    .foregroundStyle(FeedDesignTokens.Palette.statusCaution)
                    .accessibilityIdentifier("reading.partial")
            }
        }
    }

    private var footer: some View {
        Group {
            if let onOpenSite {
                VStack(spacing: 0) {
                    Divider().opacity(appearance.separatorOpacity)
                    Button(action: onOpenSite) {
                        Text("Abrir no site")
                            .font(FeedDesignTokens.Typography.body.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, FeedDesignTokens.Spacing.normal)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("reading.open-site-footer")
                }
            }
        }
    }
}

/// The observer half of the pull-down rule, kept apart from the view so the availability of SwiftUI's scroll
/// observers is stated once. The rule itself (`ReaderSheetPullDown`) is platform-free; the package still builds
/// for macOS 14, where these two modifiers do not exist, and there the system sheet's own gesture remains.
@available(iOS 18, macOS 15, *)
private struct ReaderSheetPullDownObserver: ViewModifier {
    @Binding var isTrackingScroll: Bool
    @Binding var gestureStartedAtTop: Bool
    @Binding var isAtTop: Bool
    @Binding var dismissalRequested: Bool
    let onTopChange: ((Bool) -> Void)?
    let onClose: () -> Void

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { _, phase, _ in
                switch phase {
                case .tracking, .interacting:
                    if !isTrackingScroll {
                        isTrackingScroll = true
                        gestureStartedAtTop = isAtTop
                    }
                default:
                    isTrackingScroll = false
                    gestureStartedAtTop = false
                }
            }
            .onScrollGeometryChange(for: ReaderScrollObservation.self, of: { geometry in
                ReaderScrollObservation(
                    pull: ReaderSheetPullDown.pull(contentOffsetY: geometry.contentOffset.y,
                        topInset: geometry.contentInsets.top),
                    atTop: ReaderSheetPullDown.isAtTop(contentOffsetY: geometry.contentOffset.y,
                        topInset: geometry.contentInsets.top))
            }) { _, observation in
                if observation.atTop != isAtTop {
                    isAtTop = observation.atTop
                    onTopChange?(observation.atTop)
                }
                guard isTrackingScroll, gestureStartedAtTop, !dismissalRequested,
                    ReaderSheetPullDown.dismisses(startedAtTop: true, isTracking: true,
                        verticalPull: observation.pull) else { return }
                dismissalRequested = true
                // This action runs inside the scroll view's own pass; the app's surface stack is not mutated
                // while a view is being laid out.
                Task { @MainActor in onClose() }
            }
    }
}

private extension View {
    /// Applies the pull-down observers where the platform has them; elsewhere the sheet's own gesture stands.
    @ViewBuilder
    func readerSheetPullDown(isTrackingScroll: Binding<Bool>, gestureStartedAtTop: Binding<Bool>,
        isAtTop: Binding<Bool>, dismissalRequested: Binding<Bool>,
        onTopChange: ((Bool) -> Void)?, onClose: @escaping () -> Void) -> some View {
        if #available(iOS 18, macOS 15, *) {
            modifier(ReaderSheetPullDownObserver(isTrackingScroll: isTrackingScroll,
                gestureStartedAtTop: gestureStartedAtTop, isAtTop: isAtTop,
                dismissalRequested: dismissalRequested, onTopChange: onTopChange, onClose: onClose))
        } else {
            self
        }
    }
}
