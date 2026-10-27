import FeedMineDomain
import FeedMinePersistence
import FeedMineRuntime

/// Resolves durable source rules through the existing verified identity index. Missing catalogue
/// rows never erase the identity the reader excluded, and names/URLs never infer a new relation.
public enum ReaderSourceExclusionPolicy {
    public static func capture(in database: RuntimeDatabase) throws -> ProductionSourceExclusions {
        let snapshot = try ReaderPreferencesStore(database: database).sourceExclusionSnapshot()
        guard !snapshot.sourceIDs.isEmpty else {
            return ProductionSourceExclusions(snapshot: snapshot, resolvedSourceIDs: [])
        }
        let links = try ReaderLibraryStore(database: database).sourceLinks()
        return ProductionSourceExclusions(snapshot: snapshot,
            resolvedSourceIDs: sourceIDs(snapshot: snapshot, links: links))
    }

    public static func sourceIDs(snapshot: ReaderSourceExclusionSnapshot,
        links: [String: ReaderLibraryStore.SourceLink]) -> Set<SourceID> {
        var result = snapshot.sourceIDs
        for sourceID in snapshot.sourceIDs {
            result.formUnion(SourceIdentityIndex.sourceIDs(in: links, for: sourceID))
        }
        return result
    }
}
