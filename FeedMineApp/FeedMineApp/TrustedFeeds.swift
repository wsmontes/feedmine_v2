import Foundation
import FeedMineDomain
import FeedMinePersistence
import FeedMineComposition

struct TrustedFeed: Sendable {
    let targetID: AcquisitionTargetID
    let sourceID: SourceID
    let bindingID: SourceBindingID
    let principal: String
    let endpoint: URL
    /// Frozen attribution shown on published cards.
    let displayName: String

    static let development: [TrustedFeed] = [
        .init(targetID: .init(rawValue: UUID(uuidString: "40000000-0000-4000-8000-000000000001")!),
            sourceID: .init(rawValue: UUID(uuidString: "50000000-0000-4000-8000-000000000001")!),
            bindingID: .init(rawValue: UUID(uuidString: "60000000-0000-4000-8000-000000000001")!),
            principal: "bbc-world", endpoint: URL(string: "https://feeds.bbci.co.uk/news/world/rss.xml")!, displayName: "BBC World"),
        .init(targetID: .init(rawValue: UUID(uuidString: "40000000-0000-4000-8000-000000000002")!),
            sourceID: .init(rawValue: UUID(uuidString: "50000000-0000-4000-8000-000000000002")!),
            bindingID: .init(rawValue: UUID(uuidString: "60000000-0000-4000-8000-000000000002")!),
            principal: "bbc-science", endpoint: URL(string: "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml")!, displayName: "BBC Science")
    ]
}

enum TrustedCatalogError: Error { case missingResource, invalidLimit, missingDefaultSource(String) }

extension TrustedFeed {
    /// A small, explicit news/science starter set from the actual catalog. The complete catalog
    /// remains available to source selection; startup never registers every default-enabled row.
    static func catalog(limit: Int, resourceURL: URL?) throws -> [TrustedFeed] {
        guard limit > 0 else { throw TrustedCatalogError.invalidLimit }
        guard let resourceURL else { throw TrustedCatalogError.missingResource }
        let reader = try LegacyCatalogReader(catalogURL: resourceURL)
        let keys = ["https://feeds.bbci.co.uk/news/rss.xml", "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml",
            "https://feeds.npr.org/1001/rss.xml", "https://theguardian.com/world/rss"]
        return try keys.prefix(limit).map { key in
            guard let record = try reader.source(key: key), let entry = LegacyCatalogImport.entry(record) else {
                throw TrustedCatalogError.missingDefaultSource(key)
            }
            return TrustedFeed(targetID: entry.targetID, sourceID: entry.source.id, bindingID: entry.bindingID,
                principal: entry.principal, endpoint: entry.endpoint, displayName: entry.source.displayName)
        }
    }

    static func resolve(keys: [String], fallback: [TrustedFeed]) throws -> [TrustedFeed] {
        var reader: LegacyCatalogReader?
        return try keys.map { key in
            if let supplied = fallback.first(where: { $0.principal == key }) { return supplied }
            if reader == nil {
                guard let url = Bundle.main.url(forResource: "catalog", withExtension: "sqlite") else { throw TrustedCatalogError.missingResource }
                reader = try LegacyCatalogReader(catalogURL: url)
            }
            guard let record = try reader?.source(key: key), let entry = LegacyCatalogImport.entry(record) else {
                throw TrustedCatalogError.missingDefaultSource(key)
            }
            return TrustedFeed(targetID: entry.targetID, sourceID: entry.source.id, bindingID: entry.bindingID,
                principal: entry.principal, endpoint: entry.endpoint, displayName: entry.source.displayName)
        }
    }

    static func catalogOrDevelopment(limit: Int) -> [TrustedFeed] {
        #if DEBUG
        if ProcessInfo.processInfo.environment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] == "1" { return development }
        #endif
        do { return try catalog(limit: limit, resourceURL: Bundle.main.url(forResource: "catalog", withExtension: "sqlite")) }
        catch {
            #if DEBUG
            return development
            #else
            // AppComposition presents an explicit startup failure for an absent/invalid release catalog.
            return []
            #endif
        }
    }
}

#if DEBUG
// A real closed proxy used only for the development network-blocked relaunch proof.
enum DevelopmentNetworkBlock {
    static func apply(to configuration: URLSessionConfiguration) {
        configuration.connectionProxyDictionary = ["HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": 9,
            "HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": 9]
    }
}
#endif
