// File: PresentationCard.swift
// Module: FeedMineRuntime
// Owns: disposable immutable UI-facing projection of published card values.
// Does not own: publication authority, storage, provenance, media or action execution.

import Foundation
import FeedMineDomain
import FeedMinePublication
import FeedMineMedia

public enum PresentationCardLayout: String, Hashable, Sendable {
    case hero
    case thumbnail
    case textOnly
}

public enum PresentationTimestampKind: String, Hashable, Sendable {
    case authored
    case modified
    case observed
}

public struct PresentationTimestamp: Hashable, Sendable {
    public let value: Date
    public let kind: PresentationTimestampKind
}

public enum PresentationPrimaryActionKind: String, Hashable, Sendable {
    case externalURL
    case mediaPlayback
    case localContentDetail
}

/// Presentation is reconstructible; frozen publication remains the authority.
/// Action targets and backend provenance deliberately do not cross this surface.
public struct PresentationCard: Identifiable, Hashable, Sendable {
    public let id: PublicationCardID
    public let title: String?
    public let primaryText: String?
    public let timestamp: PresentationTimestamp?
    /// Which source this card came from: the frozen publication's own identity. A surface that wants to say
    /// something about the source the reader is reading (F02's invitation) needs to know which one it is, and
    /// asking the database per card during a render was both a cost and a race.
    public let sourceID: SourceID?
    public let sourceDisplayName: String?
    public let providerDisplayName: String?
    public let layout: PresentationCardLayout
    public let mediaAspectRatio: Double?
    public let primaryActionKind: PresentationPrimaryActionKind?
    /// Slot-sized local image ready to draw. An admitted image card always carries it; nil means either a declared
    /// `.textOnly` card or a bitmap released outside the pixel band, which is reconstructed before it is drawn.
    public let image: PresentationImage?

    /// Residency-only reconstruction: identical frozen values with different decoded pixels.
    /// Internal on purpose — no external snapshot factory crosses the Runtime boundary.
    init(id: PublicationCardID, title: String?, primaryText: String?, timestamp: PresentationTimestamp?,
        sourceID: SourceID?, sourceDisplayName: String?, providerDisplayName: String?,
        layout: PresentationCardLayout,
        mediaAspectRatio: Double?, primaryActionKind: PresentationPrimaryActionKind?, image: PresentationImage?) {
        self.id = id
        self.title = title
        self.primaryText = primaryText
        self.timestamp = timestamp
        self.sourceID = sourceID
        self.sourceDisplayName = sourceDisplayName
        self.providerDisplayName = providerDisplayName
        self.layout = layout
        self.mediaAspectRatio = mediaAspectRatio
        self.primaryActionKind = primaryActionKind
        self.image = image
    }

    /// The same frozen card with different decoded pixels. Identity, layout, aspect ratio, text and the
    /// action are untouched: decoded pixels are residency, never identity.
    func withDecodedImage(_ image: PresentationImage?) -> PresentationCard {
        PresentationCard(id: id, title: title, primaryText: primaryText, timestamp: timestamp, sourceID: sourceID,
            sourceDisplayName: sourceDisplayName, providerDisplayName: providerDisplayName, layout: layout,
            mediaAspectRatio: mediaAspectRatio, primaryActionKind: primaryActionKind, image: image)
    }

    /// Releases only the bitmap. The slot keeps its frozen geometry, so nothing moves and the card is
    /// never "upgraded": the layout decided at publication is what it renders.
    func releasingDecodedImage() -> PresentationCard { withDecodedImage(nil) }

    /// A layout that was published with an image slot, whatever its residency state is right now.
    public var isImageBearing: Bool { layout != .textOnly }

    /// Admission projection: the value that may cross the feed's presentation boundary.
    ///
    /// An image card is admitted only with its slot-sized pixels decoded. When the media cannot be decoded — the
    /// bytes are absent or corrupt, or this composition has no decoder — the occurrence is **not** admitted as an
    /// image slot waiting for pixels: it keeps its frozen identity and text as a **declared** `.textOnly` card, the
    /// legitimate final presentation the owner's rule allows a text card to be. The `init(publishedCard:decoder:)`
    /// below stays the residency projection: cards outside the pixel band keep their frozen layout with the bitmap
    /// released, and they are reconstructed through this initializer before they are drawn again.
    init(admitting publishedCard: PublishedCard, decoder: PresentationImageDecoder?) {
        self.init(publishedCard: publishedCard, decoder: decoder)
        guard layout != .textOnly, image == nil else { return }
        self = PresentationCard(id: id, title: title, primaryText: primaryText, timestamp: timestamp,
            sourceID: sourceID, sourceDisplayName: sourceDisplayName, providerDisplayName: providerDisplayName,
            layout: .textOnly, mediaAspectRatio: nil, primaryActionKind: primaryActionKind, image: nil)
    }

    /// Residency projection (never admission): frozen values, pixels only when a decoder supplies them.
    init(publishedCard: PublishedCard, decoder: PresentationImageDecoder? = nil) {
        id = publishedCard.id
        title = publishedCard.text.title
        primaryText = publishedCard.text.primaryText
        sourceID = publishedCard.origin.sourceID
        sourceDisplayName = publishedCard.origin.sourceDisplayName
        providerDisplayName = publishedCard.origin.providerDisplayName
        timestamp = publishedCard.timestamp.map { timestamp in
            let kind: PresentationTimestampKind
            switch timestamp.kind {
            case .authored: kind = .authored
            case .modified: kind = .modified
            case .observed: kind = .observed
            }
            return PresentationTimestamp(value: timestamp.value, kind: kind)
        }
        switch publishedCard.renderContract.layout {
        case .hero: layout = .hero
        case .thumbnail: layout = .thumbnail
        case .textOnly: layout = .textOnly
        }
        mediaAspectRatio = publishedCard.renderContract.mediaAspectRatio
        switch publishedCard.primaryAction {
        case nil: primaryActionKind = nil
        case .externalURL: primaryActionKind = .externalURL
        case .mediaPlayback: primaryActionKind = .mediaPlayback
        case .localContentDetail: primaryActionKind = .localContentDetail
        }
        let projectedLayout = layout
        image = publishedCard.media.primary.flatMap { decoder?.image(key: $0.key, layout: projectedLayout) }
    }
}
