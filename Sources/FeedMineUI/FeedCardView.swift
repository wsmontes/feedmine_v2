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
            VStack(alignment: .leading, spacing: 10) {
                visual(aspectRatio: card.mediaAspectRatio ?? 16.0 / 9.0)
                    .frame(maxWidth: .infinity)
                text
            }
            .modifier(CardChrome(id: card.id.rawValue.uuidString))
        case .thumbnail:
            HStack(alignment: .top, spacing: 12) {
                text
                Spacer(minLength: 0)
                visual(aspectRatio: 1)
                    .frame(width: 88, height: 88)
            }
            .modifier(CardChrome(id: card.id.rawValue.uuidString))
        case .textOnly:
            text.modifier(CardChrome(id: card.id.rawValue.uuidString))
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = card.title {
                Text(verbatim: title)
                    .font(card.layout == .hero ? .title2 : .headline)
            }
            if let text = card.primaryText {
                Text(verbatim: text)
                    .lineLimit(card.layout == .textOnly ? 8 : 4)
            }
            if let source = card.sourceDisplayName {
                Text(verbatim: source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let provider = card.providerDisplayName {
                Text(verbatim: provider)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func visual(aspectRatio: Double) -> some View {
        Rectangle()
            .fill(.quaternary)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                if let image = card.image {
                    Image(decorative: image.cgImage, scale: 1)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }
}

private struct CardChrome: ViewModifier {
    let id: String
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(id)
    }
}
