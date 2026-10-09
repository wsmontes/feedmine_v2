// Pure rendering of the supplied local occurrence; no asset loading or action target here.
// Images arrive already decoded at slot size inside PresentationCard (Runtime owns decoding).
// The visual slot is sized by the frozen aspect ratio, so a missing image renders a placeholder
// of the same size and the card never changes height (v1 lesson MD-2 / PD-5).
//
// Visual language ported from v1 (accent bar, warm surfaces, serif headlines, source kicker)
// with v1's scroll costs removed: no per-cell geometry readers, no shadows, no per-cell loading,
// a constant view structure per layout, and equality on the card value so unrelated store
// changes never re-evaluate visible cards.
import SwiftUI
import FeedMineRuntime

@MainActor
public struct FeedCardView: View, Equatable {
    private let card: PresentationCard
    private let bookmarked: Bool
    private let onOpen: (@MainActor () -> Void)?

    public init(card: PresentationCard, bookmarked: Bool = false, onOpen: (@MainActor () -> Void)? = nil) {
        self.card = card
        self.bookmarked = bookmarked
        self.onOpen = onOpen
    }

    /// The card value is the whole visual input; the callback only forwards identity.
    public nonisolated static func == (lhs: FeedCardView, rhs: FeedCardView) -> Bool {
        lhs.card == rhs.card && lhs.bookmarked == rhs.bookmarked
    }

    public var body: some View {
        if let onOpen, card.primaryActionKind != nil {
            Button(action: onOpen) { content }
                .buttonStyle(CardPressStyle())
                .accessibilityAddTraits(.isLink)
                .accessibilityHint(Text("Abre o artigo"))
        } else {
            content
        }
    }

    private var accent: Color { FeedDesign.sourceColor(card.sourceDisplayName) }

    @ViewBuilder private var content: some View {
        switch card.layout {
        case .hero:
            VStack(alignment: .leading, spacing: 0) {
                visual(aspectRatio: card.mediaAspectRatio ?? 16.0 / 9.0)
                    .frame(maxWidth: .infinity)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: FeedDesign.cardRadius,
                        topTrailingRadius: FeedDesign.cardRadius, style: .continuous))
                text(style: .hero, summaryLines: 3)
                    .padding(FeedDesign.cardPadding)
            }
            .modifier(CardChrome(id: card.id.rawValue.uuidString, accent: accent, tint: nil, bookmarked: bookmarked))
        case .thumbnail:
            HStack(alignment: .top, spacing: 12) {
                text(style: .thumbnail, summaryLines: 3)
                visual(aspectRatio: 1)
                    .frame(width: FeedDesign.thumbnailSide, height: FeedDesign.thumbnailSide)
                    .clipShape(RoundedRectangle(cornerRadius: FeedDesign.thumbnailRadius, style: .continuous))
            }
            .padding(FeedDesign.cardPadding)
            .modifier(CardChrome(id: card.id.rawValue.uuidString, accent: accent, tint: nil, bookmarked: bookmarked))
        case .textOnly:
            // PD-5: a designed text card, not a card with a missing picture.
            text(style: .textOnly, summaryLines: 6)
                .padding(.vertical, FeedDesign.cardPadding + 4)
                .padding(.horizontal, FeedDesign.cardPadding)
                .modifier(CardChrome(id: card.id.rawValue.uuidString, accent: accent, tint: accent, bookmarked: bookmarked))
        }
    }

    private func text(style: PresentationCardLayoutStyle, summaryLines: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let source = card.sourceDisplayName {
                Text(verbatim: source)
                    .font(FeedDesign.kicker)
                    .foregroundStyle(accent)
                    .lineLimit(1)
            }
            if let title = card.title {
                Text(verbatim: title)
                    .font(FeedDesign.title(style))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let text = card.primaryText {
                Text(verbatim: text)
                    .font(FeedDesign.summary)
                    .foregroundStyle(.secondary)
                    .lineLimit(summaryLines)
            }
            if card.providerDisplayName != nil || card.timestamp != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let provider = card.providerDisplayName {
                        Text(verbatim: provider)
                            .lineLimit(1)
                    }
                    if let timestamp = card.timestamp {
                        HStack(spacing: 4) {
                            switch timestamp.kind {
                            case .authored: Text("Autoria")
                            case .modified: Text("Modificado")
                            case .observed: Text("Observado")
                            }
                            Text(timestamp.value, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                        }
                        .lineLimit(1)
                    }
                }
                .font(FeedDesign.meta)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func visual(aspectRatio: Double) -> some View {
        Rectangle()
            .fill(FeedDesign.placeholder)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                if let image = card.image {
                    Image(decorative: image.cgImage, scale: 1)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

/// v1 card chrome: surface, hairline stroke and a left accent bar. No shadow (offscreen
/// rendering per cell during scroll); depth comes from the page/surface contrast instead.
private struct CardChrome: ViewModifier {
    let id: String
    let accent: Color
    let tint: Color?
    let bookmarked: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: FeedDesign.cardRadius, style: .continuous)
        return content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape.fill(FeedDesign.surface)
                    .overlay { if let tint { shape.fill(tint.opacity(0.06)) } }
            }
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(accent.opacity(0.85))
                    .frame(width: FeedDesign.accentBarWidth)
                    .padding(.vertical, FeedDesign.cardRadius)
                    .accessibilityHidden(true)
            }
            .overlay { shape.strokeBorder(FeedDesign.hairline, lineWidth: 0.5) }
            // Saved mark: a corner ribbon drawn over the card, never part of its layout.
            .overlay(alignment: .topTrailing) {
                if bookmarked {
                    Image(systemName: "bookmark.fill")
                        .font(.footnote)
                        .foregroundStyle(FeedDesign.accent)
                        .padding(10)
                        .accessibilityLabel(Text("Salvo"))
                }
            }
            .contentShape(shape)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(id)
    }
}

/// Immediate touch feedback without layout change: transform and opacity only.
private struct CardPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
