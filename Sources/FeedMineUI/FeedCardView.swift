// Pure rendering of the supplied local occurrence; no asset loading or action target here.
// Images arrive already decoded at slot size inside PresentationCard (Runtime owns decoding).
// The visual slot is sized by the frozen aspect ratio, so a missing image renders a placeholder
// of the same size and the card never changes height (v1 lesson MD-2 / PD-5).
import SwiftUI
import FeedMineRuntime

@MainActor
public struct FeedCardView: View {
    private let card: PresentationCard
    private let onOpen: (@MainActor () -> Void)?
    /// U1-D: at accessibility text sizes the compact row becomes a vertical arrangement instead
    /// of clipping text into a fixed-width thumbnail column.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The row thumbnail follows the reader's text size; the Runtime decode slot stays at the
    /// reference size (reported as a limitation rather than changing media policy in this gate).
    @ScaledMetric(relativeTo: .body) private var thumbnailSide = FeedDesignTokens.Measurement.compactThumbnailBase

    public init(card: PresentationCard, onOpen: (@MainActor () -> Void)? = nil) {
        self.card = card
        self.onOpen = onOpen
    }

    public var body: some View {
        if let onOpen, card.primaryActionKind != nil {
            Button(action: onOpen) { content }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isLink)
                .accessibilityHint(Text("Abre o artigo"))
        } else {
            content
        }
    }

    @ViewBuilder private var content: some View {
        switch card.layout {
        case .hero:
            VStack(alignment: .leading, spacing: FeedDesignTokens.Spacing.compact) {
                visual(aspectRatio: card.mediaAspectRatio ?? 16.0 / 9.0)
                    .frame(maxWidth: .infinity)
                text
            }
            .modifier(CardChrome(id: card.id.rawValue.uuidString))
        case .thumbnail:
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: FeedDesignTokens.Spacing.normal) {
                    text
                    visual(aspectRatio: 1)
                        .frame(width: thumbnailSide, height: thumbnailSide, alignment: .leading)
                }
                .modifier(CardChrome(id: card.id.rawValue.uuidString))
            } else {
                HStack(alignment: .top, spacing: FeedDesignTokens.Spacing.normal) {
                    text
                    Spacer(minLength: 0)
                    visual(aspectRatio: 1)
                        .frame(width: thumbnailSide, height: thumbnailSide)
                }
                .modifier(CardChrome(id: card.id.rawValue.uuidString))
            }
        case .textOnly:
            text.modifier(CardChrome(id: card.id.rawValue.uuidString))
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: FeedDesignTokens.Spacing.compact) {
            if let title = card.title {
                Text(verbatim: title)
                    .font(card.layout == .hero ? FeedDesignTokens.Typography.cardTitleFeatured : FeedDesignTokens.Typography.cardTitle)
            }
            if let text = card.primaryText {
                Text(verbatim: text)
                    .font(FeedDesignTokens.Typography.body)
                    .lineLimit(card.layout == .textOnly ? 8 : 4)
            }
            if let source = card.sourceDisplayName {
                Text(verbatim: source)
                    .font(FeedDesignTokens.Typography.metadata)
                    .foregroundStyle(FeedDesignTokens.Palette.secondaryText)
            }
            if let provider = card.providerDisplayName {
                Text(verbatim: provider)
                    .font(FeedDesignTokens.Typography.metadata)
                    .foregroundStyle(FeedDesignTokens.Palette.secondaryText)
            }
            if let timestamp = card.timestamp {
                HStack {
                    switch timestamp.kind {
                    case .authored: Text("Autoria")
                    case .modified: Text("Modificado")
                    case .observed: Text("Observado")
                    }
                    Text(timestamp.value, format: .dateTime.day().month().year().hour().minute())
                }
                .font(FeedDesignTokens.Typography.metadata)
                .foregroundStyle(FeedDesignTokens.Palette.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func visual(aspectRatio: Double) -> some View {
        Rectangle()
            .fill(FeedDesignTokens.Palette.mediaPlaceholder)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                if let image = card.image {
                    Image(decorative: image.cgImage, scale: 1)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: FeedDesignTokens.Radius.media))
            .accessibilityHidden(true)
    }
}

private struct CardChrome: ViewModifier {
    let id: String
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(FeedDesignTokens.Spacing.card)
            .background(FeedDesignTokens.Palette.cardSurface, in: RoundedRectangle(cornerRadius: FeedDesignTokens.Radius.card))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(id)
    }
}
