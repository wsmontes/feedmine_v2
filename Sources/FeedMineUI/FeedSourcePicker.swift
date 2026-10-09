// Owns: semantic source choices and user callbacks; no storage or HTTP.
import SwiftUI
import FeedMineDomain

public struct FeedSourceOption: Identifiable, Hashable, Sendable {
    public let id: SourceID
    public let name: String
    public let selected: Bool
    public init(id: SourceID, name: String, selected: Bool) {
        self.id = id; self.name = name; self.selected = selected
    }
}

@MainActor
public struct FeedSourcePicker: View {
    private let options: [FeedSourceOption]
    private let onSearch: (String) -> Void
    private let onToggle: (SourceID) -> Void
    @State private var query = ""
    public init(options: [FeedSourceOption], onSearch: @escaping (String) -> Void,
        onToggle: @escaping (SourceID) -> Void) {
        self.options = options; self.onSearch = onSearch; self.onToggle = onToggle
    }
    public var body: some View {
        List(options) { source in
            Button { onToggle(source.id) } label: {
                HStack(spacing: 12) {
                    // Same stable source color as the card accent bar, so choices read as the feed does.
                    Circle().fill(FeedDesign.sourceColor(source.name)).frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text(verbatim: source.name).foregroundStyle(.primary)
                    Spacer()
                    if source.selected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(FeedDesign.accent)
                            .accessibilityLabel(Text("Selecionada"))
                    }
                }
                .contentShape(Rectangle())
            }.accessibilityIdentifier("source-choice-" + source.id.rawValue.uuidString)
        }
        .searchable(text: $query, prompt: "Buscar fontes no catálogo")
        .onChange(of: query) { _, value in onSearch(value) }
        .navigationTitle("Fontes")
    }
}
