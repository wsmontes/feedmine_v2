// File: FeedItemCardView.swift
// Module: FeedMineUI
// Owns: the visual composition of one reader card, copied from V1 `Views/FeedItemCardView.swift`.
// Does not own: downloads, decoding, URL resolution, players, pasteboards or share sheets. Every
// interaction leaves as one `ReaderCardActionEvent`.
//
// Differences from V1, all recorded in `docs/v1-study/PORT_LOG.md`:
// - The card band decides from `PresentationCard` (layout + frozen aspect ratio + action kind) rather
//   than from a legacy `FeedItem`/`CardMediaSlot`/`CardPresentation.Affordances` triple.
// - The left accent bar uses the reader's palette accent. V1 tinted it per *category*, and the catalog
//   category is not part of the V2 card yet (T7 supplies the taxonomy).
// - The hero placeholder uses the asset names that exist in the bundle (`Placeholder-Article`); V1
//   looked up a palette-suffixed name that no asset catalog in the checkout defines, which is why its
//   hero slots rendered blank.

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import FeedMineDomain
import FeedMineRuntime

public struct FeedItemCardView: View, Equatable {
    /// Identity is content and chrome, never the action closures (not Equatable).
    nonisolated public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.card == rhs.card && lhs.appearance == rhs.appearance
            && lhs.isRead == rhs.isRead && lhs.isBookmarked == rhs.isBookmarked
            && lhs.isInBookmarkBox == rhs.isInBookmarkBox
            && lhs.availableActions == rhs.availableActions
    }

    public let card: PresentationCard
    public let appearance: ReaderAppearance
    public let isRead: Bool
    public let isBookmarked: Bool
    /// True while the card is shown from a bookmark box: the control moves or removes instead of toggling.
    public let isInBookmarkBox: Bool
    /// Controls the host can actually execute; a card never renders a dead control.
    public let availableActions: Set<ReaderCardAction>
    public let onAction: (ReaderCardActionEvent) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public init(card: PresentationCard, appearance: ReaderAppearance, isRead: Bool = false,
        isBookmarked: Bool = false, isInBookmarkBox: Bool = false,
        availableActions: Set<ReaderCardAction> = Set(ReaderCardAction.allCases),
        onAction: @escaping (ReaderCardActionEvent) -> Void) {
        self.card = card
        self.appearance = appearance
        self.isRead = isRead
        self.isBookmarked = isBookmarked
        self.isInBookmarkBox = isInBookmarkBox
        self.availableActions = availableActions
        self.onAction = onAction
    }

    private var isLandscape: Bool { horizontalSizeClass == .regular }
    private var isAudio: Bool { card.primaryActionKind == .mediaPlayback }

    public var body: some View {
        Group {
            if isLandscape { landscapeCard } else { portraitCard }
        }
        .opacity(isRead ? appearance.readOpacity : 1)
    }

    // MARK: - Portrait

    private var portraitCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if card.isImageBearing {
                heroSlot
                sourceRow
                    .padding(.horizontal, appearance.contentPadding)
                    .padding(.top, appearance.contentPadding)
            } else {
                sourceRow
                    .padding(.horizontal, appearance.contentPadding)
                    .padding(.top, 14)
            }

            contentSurface
        }
        .frame(maxWidth: .infinity)
        .background(appearance.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: appearance.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: appearance.cardRadius)
            .stroke(appearance.cardBorder, lineWidth: appearance.borderWidth))
        .overlay(alignment: .leading) { accentBar(verticalInset: 12) }
        .contextMenu { contextMenu }
    }

    /// Wraps exactly the surface that opens the article, and nothing else. The reader's tap is answered by **this**
    /// view and by no ancestor — the wrapper above stops taking touches — so a control placed as a *sibling* of this
    /// surface keeps its own touch instead of competing for it. `buttonStyle(.plain)` because the label already
    /// draws everything: the button adds a hit area, not chrome.
    ///
    /// `mediaAction` is the hero's own tap for a playable card. `heroSlot` answers it with a gesture, and a gesture
    /// is not in the accessibility tree: measured on the device (`docs/reviews/2026-10-11-article-reading-diagnosis.md`
    /// §3), the card's tree carried the bookmark control and the opening label, and the play tap had no element at
    /// all. A playable card therefore states the same action here, where VoiceOver reaches it.
    @ViewBuilder private func openingSurface<Content: View>(mediaAction: Bool = false,
        @ViewBuilder content: () -> Content) -> some View {
        let surface = Button { emit(.open) } label: { content().contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityIdentifier("card.open")
        if mediaAction {
            surface.accessibilityAction(named: Text(String(localized: "Tocar"))) { emit(.openMedia) }
        } else {
            surface
        }
    }

    /// The surface that opens the article in the portrait card. Title, summary and date are a single target; the
    /// source row — which carries the inline bookmark — sits **above** it as a sibling, so the bookmark keeps its
    /// own touch. Measured before the separation: a 44×44 bookmark target reported *not hittable*, because the
    /// wrapper's gesture sat above it, and the same layer swallowed the long press meant for the card's menu.
    private var contentSurface: some View {
        // The hero above answers a playable card's tap with `openMedia`; the card states that action here too, so
        // playing an episode never depends on a gesture only a touch screen can make. Nothing is added for a card
        // the host cannot play (`availableActions`), which is the same rule every other control follows.
        openingSurface(mediaAction: isAudio && availableActions.contains(.openMedia)) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: card.title ?? "")
                    .font(appearance.font(.cardTitle))
                    .fontWeight(appearance.titleWeight)
                    .lineLimit(2)
                    .foregroundStyle(isRead ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .accessibilityIdentifier("card.title")
                    .padding(.horizontal, appearance.contentPadding)
                    // Keyed on the reserved slot, never on whether bytes arrived: a late image must not move
                    // this line or anything below it.
                    .padding(.top, card.isImageBearing ? 10 : 6)

                if let summary = card.primaryText, !summary.isEmpty {
                    Text(verbatim: summary)
                        .font(appearance.font(.cardSummary))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .padding(.horizontal, appearance.contentPadding)
                        .padding(.top, 6)
                }

                HStack {
                    Text(verbatim: Self.formatted(card.timestamp?.value))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, appearance.contentPadding)
                .padding(.top, 8)
                .padding(.bottom, appearance.cardPadding)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Landscape (V1 "band")

    private var landscapeCard: some View {
        HStack(spacing: 12) {
            if card.isImageBearing {
                Group {
                    if isAudio, card.image == nil {
                        audioPlaceholder
                    } else {
                        placeholderView
                    }
                }
                .frame(width: appearance.landscapeThumbnailSide, height: appearance.landscapeThumbnailSide)
                .clipped()
                .overlay { decodedImage }
                .clipShape(RoundedRectangle(cornerRadius: appearance.landscapeThumbnailRadius))
            }

            openingSurface { landscapeContent }
        }
        .padding(appearance.contentPadding)
        .frame(maxWidth: .infinity)
        .background(appearance.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: appearance.landscapeCardRadius))
        .overlay(RoundedRectangle(cornerRadius: appearance.landscapeCardRadius)
            .stroke(appearance.cardBorder, lineWidth: appearance.borderWidth))
        .overlay(alignment: .leading) { accentBar(verticalInset: 10) }
        .contextMenu { contextMenu }
    }

    /// The band's texts, wrapped by `openingSurface` so the reader's tap opens the article. This presentation carries
    /// no inline bookmark of its own — the compact row owns that — and its other controls are the hero's media
    /// gesture and the card's menu, both of which keep their own touches because this surface is their sibling.
    private var landscapeContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: card.sourceDisplayName ?? "")
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)

            Text(verbatim: card.title ?? "")
                .font(appearance.font(.cardTitle))
                .fontWeight(appearance.titleWeight)
                .lineLimit(2)
                .foregroundStyle(isRead ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .accessibilityIdentifier("card.title")
                .padding(.top, 4)

            if let summary = card.primaryText, !summary.isEmpty {
                Text(verbatim: summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 3)
            }

            HStack {
                Text(verbatim: Self.formatted(card.timestamp?.value))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Slots

    /// The frozen aspect ratio *is* the slot: its height never depends on what it holds, so a card
    /// that has no bytes yet renders a placeholder of the same size and nothing below it moves.
    private var heroSlot: some View {
        Rectangle()
            .fill(appearance.mediaPlaceholder)
            .aspectRatio(card.mediaAspectRatio ?? appearance.heroAspectRatio, contentMode: .fit)
            .overlay {
                if isAudio, card.image == nil { audioPlaceholder } else { placeholderView }
            }
            .overlay { decodedImage }
            .clipShape(RoundedRectangle(cornerRadius: appearance.mediaRadius))
            .contentShape(Rectangle())
            // The hero answers its own tap: media plays for an audio card, and the article opens for the rest. With
            // the wrapper no longer taking touches, an image that had no gesture here would open nothing at all.
            .highPriorityGesture(isAudio
                ? TapGesture().onEnded { emit(.openMedia) }
                : TapGesture().onEnded { emit(.open) })
            .overlay { mediaOverlay }
            .overlay(alignment: .topTrailing) { bookmarkOverlay }
            // The slot states which of its two states it is in: a decoded bitmap fills it, or the frozen
            // placeholder does. The container form (never a plain identifier) keeps the bookmark control
            // inside it queryable and leaves VoiceOver focusing the control, not the drawing.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(card.image?.cgImage != nil
                ? "\(card.id.rawValue.uuidString)-media-image"
                : "\(card.id.rawValue.uuidString)-media-slot")
    }

    @ViewBuilder private var decodedImage: some View {
        if let cgImage = card.image?.cgImage {
            Image(decorative: cgImage, scale: 1, orientation: .up)
                .resizable()
                .scaledToFill()
                .overlay(isRead ? Color.black.opacity(0.15) : nil)
        }
    }

    @ViewBuilder private var placeholderView: some View {
        Image("Placeholder-Article")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .opacity(0.5)
            // The slot is a drawing: it says nothing a reader needs, and an unlabelled image in the tree is one
            // more stop before the card's own texts (which are the card's content).
            .accessibilityHidden(true)
    }

    /// V1's code-drawn audio placeholder (no asset involved). A drawing, never the control: the play glyph reads
    /// as a button to a reader who cannot see it, and the card's own element states the play action
    /// (`openingSurface(mediaAction:)`).
    private var audioPlaceholder: some View {
        ZStack {
            LinearGradient(colors: [Color.purple.opacity(0.25), Color.indigo.opacity(0.10)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .strokeBorder(Color.purple.opacity(0.12), lineWidth: 1)
                    .scaleEffect(0.4 + CGFloat(index) * 0.2)
            }
            Circle()
                .fill(Color.purple.opacity(0.18))
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color.purple.opacity(0.6))
                        .offset(x: 1)
                }
            VStack {
                Spacer(minLength: 0)
                Image(systemName: "waveform")
                    .font(.system(size: 56, weight: .ultraLight))
                    .foregroundStyle(Color.purple.opacity(0.20))
                    .offset(y: 12)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private var mediaOverlay: some View {
        if isAudio {
            Image(systemName: "headphones")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.35), in: Circle())
                // The kind is already stated in words by the source row's own badge; the glyph only repeats it.
                .accessibilityHidden(true)
        }
    }

    // MARK: - Source row and controls

    private var sourceRow: some View {
        HStack(spacing: 4) {
            Text(verbatim: card.sourceDisplayName ?? "")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(1)

            if isAudio { mediaBadge(String(localized: "Podcast"), color: .purple) }

            Spacer(minLength: 0)

            if !card.isImageBearing { inlineBookmarkControl }
        }
    }

    /// The inline control's glyph. The icon is caption-sized **on purpose** — the fix for an unreachable target is
    /// not a bigger picture. What grows is the *area*: 44 pt on each side, the minimum Apple's guidelines ask of a
    /// control a reader has to hit, and `contentShape` makes that whole area hit-testable rather than only the
    /// drawn glyph. Measured before the fix: `{{401.7, 189.0}, {8.0, 12.7}}` — eight by thirteen points, which no
    /// finger hits reliably and no assistive technology can address at all.
    private func inlineBookmarkGlyph(_ filled: Bool, tint: AnyShapeStyle) -> some View {
        Image(systemName: filled ? "bookmark.fill" : "bookmark")
            .font(.caption)
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    @ViewBuilder private var inlineBookmarkControl: some View {
        if !availableActions.contains(.save) {
            EmptyView()
        } else if isInBookmarkBox {
            Button { emit(.save) } label: { inlineBookmarkGlyph(true, tint: AnyShapeStyle(.yellow)) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("card.bookmarkBox")
        } else {
            Button { emit(.save) } label: {
                inlineBookmarkGlyph(isBookmarked,
                    tint: isBookmarked ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("card.bookmark")
            // The glyph states nothing to a reader who cannot see it: without these words the control is
            // announced by the symbol's own name (`bookmark`), which names neither the article nor the act. The
            // two phrases are the card menu's own (`contextMenu`), so the button and the menu say the same thing.
            .accessibilityLabel(Text(verbatim: bookmarkActionLabel))
            .accessibilityValue(isBookmarked ? "bookmarked" : "not bookmarked")
        }
    }

    /// What activating the card's own save control does, in the interface's own words. The box variant is left as
    /// it is: there the glyph always reads as saved, and whether the host removes or moves the card is the host's
    /// rule (`isInBookmarkBox`), which this card does not know.
    private var bookmarkActionLabel: String {
        isBookmarked ? Self.removeFromSavedLabel : Self.saveArticleLabel
    }

    static let saveArticleLabel = String(localized: "Salvar artigo")
    static let removeFromSavedLabel = String(localized: "Remover dos salvos")

    @ViewBuilder private var bookmarkOverlay: some View {
        if !availableActions.contains(.save) {
            EmptyView()
        } else if isInBookmarkBox {
            Button { emit(.save) } label: { bookmarkOverlayLabel(filled: true) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("card.bookmarkBox")
        } else {
            Button { emit(.save) } label: { bookmarkOverlayLabel(filled: isBookmarked) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("card.bookmark")
                .accessibilityLabel(Text(verbatim: bookmarkActionLabel))
                .accessibilityValue(isBookmarked ? "bookmarked" : "not bookmarked")
        }
    }

    private func bookmarkOverlayLabel(filled: Bool) -> some View {
        Image(systemName: filled ? "bookmark.fill" : "bookmark")
            .font(.title3)
            .foregroundStyle(filled ? AnyShapeStyle(.yellow) : AnyShapeStyle(.white))
            .frame(width: overlayBadgeSide, height: overlayBadgeSide)
            .background(.ultraThinMaterial, in: Circle())
            .shadow(color: .black.opacity(0.15), radius: 4)
            .padding(appearance.overlayBadgePadding)
    }

    /// The badge's own side, after Dynamic Type: the glyph inside it is a text style (`.title3`), so the circle
    /// must follow the reader's text size instead of holding 36 pt while the glyph grows past it. It stays
    /// relative to the appearance's own value (`overlayBadgeSize`) rather than replacing it: a side the reader's
    /// preferences state, scaled by how much larger than the default they need their text, is the product.
    private var overlayBadgeSide: CGFloat {
        appearance.overlayBadgeSize * (overlayBadgeReference / ReaderAppearance.standard.overlayBadgeSize)
    }

    @ScaledMetric(relativeTo: .title3)
    private var overlayBadgeReference: CGFloat = ReaderAppearance.standard.overlayBadgeSize

    private func accentBar(verticalInset: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(appearance.accent.opacity(isRead ? 0.25 : 0.8))
            .frame(width: appearance.accentBarWidth)
            .padding(.vertical, verticalInset)
            .padding(.leading, appearance.accentBarInset)
    }

    private func mediaBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.heavy)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }

    /// The same menu V1 offered, minus the two controls that need a resolved URL or a rendered image:
    /// V2 resolves the target outside UI (`ReaderCardAction`) and keeps the reader in the app.
    @ViewBuilder private var contextMenu: some View {
        if availableActions.contains(.save) {
            Button { emit(.save) } label: {
                Label(isBookmarked ? String(localized: "Remover dos salvos") : String(localized: "Salvar artigo"),
                    systemImage: isBookmarked ? "bookmark.slash" : "bookmark")
            }
        }
        if availableActions.contains(.viewSource) {
            Button { emit(.viewSource) } label: {
                Label(String(localized: "Ver a fonte"), systemImage: "rectangle.stack")
            }
        }
        if availableActions.contains(.addSourceToCollection) {
            Button { emit(.addSourceToCollection) } label: {
                Label(String(localized: "Adicionar fonte a uma coleção"),
                    systemImage: "rectangle.stack.badge.plus")
            }
        }
        if availableActions.contains(.copyLink) {
            Button { emit(.copyLink) } label: {
                Label(String(localized: "Copiar link"), systemImage: "doc.on.doc")
            }
        }
        if availableActions.contains(.share), card.primaryActionKind == .externalURL {
            Button { emit(.share) } label: {
                Label(String(localized: "Compartilhar"), systemImage: "square.and.arrow.up")
            }
        }
    }

    private func emit(_ action: ReaderCardAction) {
        onAction(ReaderCardActionEvent(action: action, cardID: card.id))
    }

    // MARK: - Dates (V1 formatting)

    // Both formatters state the interface language instead of taking the process default: a date is part of the
    // interface, and it must not disagree with the copy around it.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = CatalogLanguageNaming.interfaceLocale
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        formatter.locale = CatalogLanguageNaming.interfaceLocale
        return formatter
    }()

    /// V1's rule: relative while it is recent, the locale's short date afterwards.
    public static func formatted(_ date: Date?) -> String {
        guard let date else { return "" }
        if Date().timeIntervalSince(date) < 7 * 24 * 3600 {
            return relativeFormatter.localizedString(for: date, relativeTo: Date())
        }
        return shortDateFormatter.string(from: date)
    }
}
