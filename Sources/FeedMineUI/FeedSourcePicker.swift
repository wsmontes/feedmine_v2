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

    /// U2: selected sources first, then by name; ordering is presentation only and never changes
    /// what the composition stores.
    private var ordered: [FeedSourceOption] {
        options.sorted { left, right in
            if left.selected != right.selected { return left.selected }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    private var selectedCount: Int { options.lazy.filter(\.selected).count }

    public var body: some View {
        Group {
            if ordered.isEmpty {
                ContentUnavailableView {
                    Label("Nenhuma fonte", systemImage: "square.grid.2x2")
                } description: {
                    Text("Digite para buscar no catálogo de fontes.")
                }
            } else {
                List {
                    Section {
                        ForEach(ordered) { source in
                            Button { onToggle(source.id) } label: {
                                HStack {
                                    Text(source.name)
                                    Spacer()
                                    if source.selected { Image(systemName: "checkmark") }
                                }
                            }
                            .accessibilityIdentifier("source-choice-" + source.id.rawValue.uuidString)
                            .accessibilityAddTraits(source.selected ? [.isSelected] : [])
                        }
                    } header: {
                        Text("\(selectedCount) de \(options.count) selecionadas")
                            .accessibilityIdentifier("source-selection-count")
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Buscar fontes no catálogo")
        .onChange(of: query) { _, value in onSearch(value) }
        .navigationTitle("Fontes")
    }
}
