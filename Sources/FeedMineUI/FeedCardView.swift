// Pure rendering of the supplied local occurrence; no asset or action target is exposed here.
import SwiftUI
import FeedMineRuntime

@MainActor
public struct FeedCardView: View {
    private let card: PresentationCard

    public init(card: PresentationCard) {
        self.card = card
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = card.title {
                Text(verbatim: title)
                    .font(card.layout == .hero ? .title2 : .headline)
            }
            if let text = card.primaryText {
                Text(verbatim: text)
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
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(card.id.rawValue.uuidString)
    }
}
