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

            Text(verbatim: card.title ?? "")
                .font(appearance.font(.cardTitle))
                .fontWeight(appearance.titleWeight)
                .lineLimit(2)
                .foregroundStyle(isRead ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
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
        .frame(maxWidth: .infinity)
        .background(appearance.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: appearance.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: appearance.cardRadius)
            .stroke(appearance.cardBorder, lineWidth: appearance.borderWidth))
        .overlay(alignment: .leading) { accentBar(verticalInset: 12) }
        .contextMenu { contextMenu }
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
        .padding(appearance.contentPadding)
        .frame(maxWidth: .infinity)
        .background(appearance.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: appearance.landscapeCardRadius))
        .overlay(RoundedRectangle(cornerRadius: appearance.landscapeCardRadius)
            .stroke(appearance.cardBorder, lineWidth: appearance.borderWidth))
        .overlay(alignment: .leading) { accentBar(verticalInset: 10) }
        .contextMenu { contextMenu }
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
            .highPriorityGesture(isAudio ? TapGesture().onEnded { emit(.openMedia) } : nil)
            .overlay { mediaOverlay }
            .overlay(alignment: .topTrailing) { bookmarkOverlay }
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
    }

    /// V1's code-drawn audio placeholder (no asset involved).
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
    }

    @ViewBuilder private var mediaOverlay: some View {
        if isAudio {
            Image(systemName: "headphones")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.35), in: Circle())
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

    @ViewBuilder private var inlineBookmarkControl: some View {
        if !availableActions.contains(.save) {
            EmptyView()
        } else if isInBookmarkBox {
            Button { emit(.save) } label: {
                Image(systemName: "bookmark.fill").font(.caption).foregroundStyle(.yellow)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("card.bookmarkBox")
        } else {
            Button { emit(.save) } label: {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .font(.caption)
                    .foregroundStyle(isBookmarked ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("card.bookmark")
            .accessibilityValue(isBookmarked ? "bookmarked" : "not bookmarked")
        }
    }

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
                .accessibilityValue(isBookmarked ? "bookmarked" : "not bookmarked")
        }
    }

    private func bookmarkOverlayLabel(filled: Bool) -> some View {
        Image(systemName: filled ? "bookmark.fill" : "bookmark")
            .font(.title3)
            .foregroundStyle(filled ? AnyShapeStyle(.yellow) : AnyShapeStyle(.white))
            .frame(width: appearance.overlayBadgeSize, height: appearance.overlayBadgeSize)
            .background(.ultraThinMaterial, in: Circle())
            .shadow(color: .black.opacity(0.15), radius: 4)
            .padding(appearance.overlayBadgePadding)
    }

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

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
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
