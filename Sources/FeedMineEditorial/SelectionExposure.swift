// Owns: explicitly supplied pure exposure facts, independent of publication storage.
import FeedMineDomain

public struct SelectionExposureSnapshot: Hashable, Sendable {
    public let requestedOriginIDs: [OriginRecordID]
    public let publishedOriginIDs: Set<OriginRecordID>
    /// Material keys already published for each origin (PD-1). Absent for an origin means its
    /// published text is unknown, which excludes it like Phase 3R5.
    public let publishedMaterialKeys: [OriginRecordID: Set<String>]

    public init?(requestedOriginIDs: [OriginRecordID], publishedOriginIDs: Set<OriginRecordID>,
        publishedMaterialKeys: [OriginRecordID: Set<String>] = [:]) {
        let requested = Set(requestedOriginIDs)
        guard requested.count == requestedOriginIDs.count,
            publishedOriginIDs.isSubset(of: requested),
            Set(publishedMaterialKeys.keys).isSubset(of: publishedOriginIDs) else { return nil }
        self.requestedOriginIDs = requestedOriginIDs
        self.publishedOriginIDs = publishedOriginIDs
        self.publishedMaterialKeys = publishedMaterialKeys
    }

    /// Whitespace-collapsed headline and summary. Must equal `PublicationStore.materialKey` over the
    /// published title/primary text, which Runtime copies verbatim from the candidate.
    public static func materialKey(headline: String?, summary: String?) -> String {
        func collapse(_ text: String?) -> String { (text ?? "").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
        return collapse(headline) + "\u{1F}" + collapse(summary)
    }

    /// PD-1: an already-published origin is eligible again only with materially new text.
    func alreadyPublished(_ candidate: Candidate) -> Bool {
        guard publishedOriginIDs.contains(candidate.originRecordID) else { return false }
        guard let keys = publishedMaterialKeys[candidate.originRecordID] else { return true }
        return keys.contains(Self.materialKey(headline: candidate.headline, summary: candidate.summary))
    }
}
