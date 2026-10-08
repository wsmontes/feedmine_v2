// Owns: immutable prepared semantic payload awaiting occurrence identity.
// Does not own: preparation, storage or editorial selection.

import FeedMineDomain
import FeedMineMedia

public struct PublicationCardDraft: Hashable, Sendable {
    public let origin: PublishedOrigin
    public let contentEntityID: ContentEntityID?
    public let contentClusterID: ContentClusterID?
    public let text: PublishedText
    public let timestamp: PublishedTimestamp?
    public let media: PublishedMediaSet
    public let renderContract: RenderContract
    public let primaryAction: PublishedPrimaryAction?

    public init?(origin: PublishedOrigin, contentEntityID: ContentEntityID?, contentClusterID: ContentClusterID?,
        text: PublishedText, timestamp: PublishedTimestamp?, media: PublishedMediaSet,
        renderContract: RenderContract, primaryAction: PublishedPrimaryAction?) {
        guard renderContract.layout != .textOnly || media.primary == nil else { return nil }
        self.origin = origin
        self.contentEntityID = contentEntityID
        self.contentClusterID = contentClusterID
        self.text = text
        self.timestamp = timestamp
        self.media = media
        self.renderContract = renderContract
        self.primaryAction = primaryAction
    }
}
