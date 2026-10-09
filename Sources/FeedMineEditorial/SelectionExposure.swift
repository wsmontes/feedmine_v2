// Owns: explicitly supplied pure exposure facts, independent of publication storage.
import FeedMineDomain

public struct SelectionExposureSnapshot: Hashable, Sendable {
    public let requestedOriginIDs: [OriginRecordID]
    public let publishedOriginIDs: Set<OriginRecordID>
    /// Material keys already published for each origin (PD-1). Absent for an origin means its
    /// published text is unknown, which excludes it like Phase 3R5.
    public let publishedMaterialKeys: [OriginRecordID: Set<String>]
    /// Origins that already have an occurrence ahead of the reader (PD-1 rule 2): never another.
    public let unseenOriginIDs: Set<OriginRecordID>

    public init?(requestedOriginIDs: [OriginRecordID], publishedOriginIDs: Set<OriginRecordID>,
        publishedMaterialKeys: [OriginRecordID: Set<String>] = [:], unseenOriginIDs: Set<OriginRecordID> = []) {
        let requested = Set(requestedOriginIDs)
        guard requested.count == requestedOriginIDs.count,
            publishedOriginIDs.isSubset(of: requested),
            Set(publishedMaterialKeys.keys).isSubset(of: publishedOriginIDs),
            unseenOriginIDs.isSubset(of: publishedOriginIDs) else { return nil }
        self.requestedOriginIDs = requestedOriginIDs
        self.publishedOriginIDs = publishedOriginIDs
        self.publishedMaterialKeys = publishedMaterialKeys
        self.unseenOriginIDs = unseenOriginIDs
    }

    /// Whitespace-collapsed headline and summary plus the primary media locator. Must equal
    /// `PublicationStore.materialKey` over the published title/primary text (copied verbatim from
    /// the candidate) and the revision's ordinal-0 media locator.
    public static func materialKey(headline: String?, summary: String?, primaryMedia: String? = nil) -> String {
        MaterialContentIdentity.key(title: headline, text: summary, primaryMedia: primaryMedia)
    }

    /// PD-1: an already-published origin is eligible again only with materially new content, and
    /// only when no earlier occurrence of it is still waiting ahead of the reader.
    func alreadyPublished(_ candidate: Candidate) -> Bool {
        guard publishedOriginIDs.contains(candidate.originRecordID) else { return false }
        if unseenOriginIDs.contains(candidate.originRecordID) { return true }
        guard let keys = publishedMaterialKeys[candidate.originRecordID] else { return true }
        return keys.contains(Self.materialKey(headline: candidate.headline, summary: candidate.summary,
            primaryMedia: candidate.primaryMediaLocator))
    }
}
