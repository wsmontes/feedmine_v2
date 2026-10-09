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
                HStack {
                    Text(source.name)
                    Spacer()
                    if source.selected { Image(systemName: "checkmark") }
                }
            }.accessibilityIdentifier("source-choice-" + source.id.rawValue.uuidString)
        }
        .searchable(text: $query, prompt: "Buscar fontes no catálogo")
        .onChange(of: query) { _, value in onSearch(value) }
        .navigationTitle("Fontes")
    }
}
