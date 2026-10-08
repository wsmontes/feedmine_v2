// Connector-specific configuration; transport and durable generation authority are not owned here.
import Foundation
import FeedMineDomain
import FeedMineAcquisition

public struct SyndicationTargetConfiguration: Hashable, Sendable {
    public let targetID: AcquisitionTargetID
    public let endpoint: URL
    public let memberships: [AcquisitionMembershipClaim]

    public init?(targetID: AcquisitionTargetID, endpoint: URL, memberships: [AcquisitionMembershipClaim]) {
        guard let scheme = endpoint.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = endpoint.host, !host.isEmpty, endpoint.user == nil, endpoint.password == nil,
            !memberships.isEmpty, Set(memberships.map(\.sourceID)).count == memberships.count else { return nil }
        self.targetID = targetID
        self.endpoint = endpoint
        self.memberships = memberships
    }
}
