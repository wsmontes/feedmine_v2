// File: FeedItemRowView.swift
// Module: FeedMineUI
// Owns: the compact row layout, copied from V1 `Views/FeedItemRowView.swift`.
// Does not own: gestures, menus, downloads or decoding. `FeedItemView` owns the row's interactions.

import SwiftUI
import FeedMineRuntime

public struct FeedItemRowView: View, Equatable {
    public let card: PresentationCard
    public let appearance: ReaderAppearance
    public let isRead: Bool

    public init(card: PresentationCard, appearance: ReaderAppearance, isRead: Bool = false) {
        self.card = card
        self.appearance = appearance
        self.isRead = isRead
    }

    private var isAudio: Bool { card.primaryActionKind == .mediaPlayback }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if card.isImageBearing {
                Group {
                    if isAudio, card.image == nil {
                        audioPlaceholder
                    } else {
                        Image("Placeholder-Article").resizable().aspectRatio(contentMode: .fill)
                    }
                }
                .frame(width: appearance.compactThumbnailSide, height: appearance.compactThumbnailSide)
                .clipped()
                .overlay { decodedImage }
                .clipShape(RoundedRectangle(cornerRadius: appearance.landscapeThumbnailRadius))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: card.title ?? "")
                    .font(appearance.font(.cardTitle))
                    .fontWeight(appearance.titleWeight)
                    .lineLimit(2)
                    .foregroundStyle(isRead ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))

                if let summary = card.primaryText, !summary.isEmpty {
                    Text(verbatim: summary)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 4) {
                    Text(verbatim: card.sourceDisplayName ?? "")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(verbatim: "·").font(.caption2).foregroundStyle(.tertiary)
                    Text(verbatim: FeedItemCardView.formatted(card.timestamp?.value))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, appearance.contentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appearance.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: appearance.landscapeCardRadius))
        .overlay(RoundedRectangle(cornerRadius: appearance.landscapeCardRadius)
            .stroke(appearance.cardBorder, lineWidth: appearance.borderWidth))
        .overlay(alignment: .leading) { accentBar }
        .opacity(isRead ? appearance.readOpacity : 1)
    }

    @ViewBuilder private var decodedImage: some View {
        if let cgImage = card.image?.cgImage {
            Image(decorative: cgImage, scale: 1, orientation: .up).resizable().scaledToFill()
        }
    }

    private var audioPlaceholder: some View {
        ZStack {
            LinearGradient(colors: [Color.purple.opacity(0.25), Color.indigo.opacity(0.10)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "waveform")
                .font(.system(size: 28, weight: .ultraLight))
                .foregroundStyle(Color.purple.opacity(0.5))
        }
    }

    private var accentBar: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(appearance.accent.opacity(isRead ? 0.25 : 0.8))
            .frame(width: appearance.accentBarWidth)
            .padding(.vertical, 8)
            .padding(.leading, appearance.accentBarInset)
    }
}
