import Foundation
import FeedMineDomain

struct TrustedFeed: Sendable {
    let targetID: AcquisitionTargetID
    let sourceID: SourceID
    let bindingID: SourceBindingID
    let principal: String
    let endpoint: URL

    static let development: [TrustedFeed] = [
        .init(targetID: .init(rawValue: UUID(uuidString: "40000000-0000-4000-8000-000000000001")!),
            sourceID: .init(rawValue: UUID(uuidString: "50000000-0000-4000-8000-000000000001")!),
            bindingID: .init(rawValue: UUID(uuidString: "60000000-0000-4000-8000-000000000001")!),
            principal: "bbc-world", endpoint: URL(string: "https://feeds.bbci.co.uk/news/world/rss.xml")!),
        .init(targetID: .init(rawValue: UUID(uuidString: "40000000-0000-4000-8000-000000000002")!),
            sourceID: .init(rawValue: UUID(uuidString: "50000000-0000-4000-8000-000000000002")!),
            bindingID: .init(rawValue: UUID(uuidString: "60000000-0000-4000-8000-000000000002")!),
            principal: "bbc-science", endpoint: URL(string: "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml")!)
    ]
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
