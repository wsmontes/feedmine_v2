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

extension TrustedFeed {
    /// PD-2: when the v1 catalog is bundled (`catalog.sqlite`), the app follows its curated default
    /// sources instead of the two development feeds. Registration is bounded by `limit`; choosing
    /// which sources a reader follows belongs to a later onboarding gate.
    static func catalogOrDevelopment(limit: Int) -> [TrustedFeed] {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "sqlite"),
            let reader = try? LegacyCatalogReader(catalogURL: url),
            let entries = try? LegacyCatalogImport.entries(from: reader, limit: limit), !entries.isEmpty else {
            return development
        }
        return entries.map { entry in
            TrustedFeed(targetID: entry.targetID, sourceID: entry.source.id, bindingID: entry.bindingID,
                principal: entry.principal, endpoint: entry.endpoint, displayName: entry.source.displayName)
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
