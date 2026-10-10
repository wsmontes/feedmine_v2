// Owns: one semantic source choice for a surface to draw; no storage or HTTP.
import FeedMineDomain

public struct FeedSourceOption: Identifiable, Hashable, Sendable {
    public let id: SourceID
    public let name: String
    public let selected: Bool
    public init(id: SourceID, name: String, selected: Bool) {
        self.id = id; self.name = name; self.selected = selected
    }
}
