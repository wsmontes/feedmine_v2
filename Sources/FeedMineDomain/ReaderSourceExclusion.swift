import Foundation

/// An explicit durable source rule. The label remains readable if the catalogue removes the source;
/// only the existing source identity participates in matching.
public struct ReaderSourceExclusion: Hashable, Codable, Sendable {
    public let sourceID: SourceID
    public let displayName: String

    public init(sourceID: SourceID, displayName: String) {
        self.sourceID = sourceID
        self.displayName = displayName
    }

    /// The last supplied label wins for one identity. Equal labels never merge different sources.
    static func normalize(_ rules: [ReaderSourceExclusion]) -> [ReaderSourceExclusion] {
        var byID: [SourceID: ReaderSourceExclusion] = [:]
        for rule in rules { byID[rule.sourceID] = rule }
        return byID.values.sorted { $0.sourceID.rawValue.uuidString < $1.sourceID.rawValue.uuidString }
    }
}

/// The effective policy a publication opportunity observes, independent of display labels and of
/// rules the master switch currently masks. Alias expansion belongs to Composition.
public struct ReaderSourceExclusionSnapshot: Hashable, Sendable {
    public let sourceIDs: Set<SourceID>

    public init(settings: ReaderSettings) {
        sourceIDs = settings.contentFiltersEnabled
            ? Set(settings.contentSourceExclusions.map(\.sourceID)) : []
    }

    public static let unrestricted = ReaderSourceExclusionSnapshot(settings: .standard)
}
