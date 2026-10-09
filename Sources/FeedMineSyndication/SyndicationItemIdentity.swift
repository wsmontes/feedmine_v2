// Protocol adapter for link-derived item identity. Opaque guid/id values remain unchanged.
import FeedMineDomain

enum SyndicationItemIdentity {
    static func linkIdentity(_ raw: String) -> String { ContentLocatorIdentity.normalizedLink(raw) }
}
