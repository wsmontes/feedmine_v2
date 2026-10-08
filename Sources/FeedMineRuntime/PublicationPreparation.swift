// Owns: pure positional assembly of prepared publication draft values.
// The caller chooses presentation; this boundary never executes history or retrieves facts.

import FeedMineDomain
import FeedMineEditorial
import FeedMineMedia
import FeedMinePublication

public enum PublicationPresentation: Hashable, Sendable {
    case textOnly
    case image(MediaPreparationResult, layout: PublishedCardLayout)
}

public struct PublicationPreparationInput: Hashable, Sendable {
    public let origin: PublishedOrigin
    public let contentEntityID: ContentEntityID?
    public let contentClusterID: ContentClusterID?
    public let primaryAction: PublishedPrimaryAction?
    public let presentation: PublicationPresentation

    public init(origin: PublishedOrigin, contentEntityID: ContentEntityID?, contentClusterID: ContentClusterID?,
        primaryAction: PublishedPrimaryAction?, presentation: PublicationPresentation) {
        self.origin = origin
        self.contentEntityID = contentEntityID
        self.contentClusterID = contentClusterID
        self.primaryAction = primaryAction
        self.presentation = presentation
    }
}

public enum PublicationPreparationError: Error, Equatable, Sendable {
    case inputCountMismatch
    case originMismatch(index: Int)
    case mediaRevisionMismatch(index: Int)
    case mediaNotUsable(index: Int)
    case invalidImageLayout(index: Int)
    case invalidDraft(index: Int)
}

public enum PublicationPreparation {
    public static func drafts(selection: SelectionResult,
        inputs: [PublicationPreparationInput]) throws -> [PublicationCardDraft] {
        guard selection.orderedCandidates.count == inputs.count else {
            throw PublicationPreparationError.inputCountMismatch
        }
        return try selection.orderedCandidates.enumerated().map { index, candidate in
            let input = inputs[index]
            guard input.origin.originRecordID == candidate.originRecordID,
                input.origin.originRevisionID == candidate.originRevisionID,
                input.origin.providerID == candidate.providerID else {
                throw PublicationPreparationError.originMismatch(index: index)
            }
            let media: PublishedMediaSet
            let contract: RenderContract
            switch input.presentation {
            case .textOnly:
                media = .none
                guard let textContract = RenderContract(layout: .textOnly, mediaAspectRatio: nil) else {
                    throw PublicationPreparationError.invalidDraft(index: index)
                }
                contract = textContract
            case .image(let result, let layout):
                guard layout == .hero || layout == .thumbnail else {
                    throw PublicationPreparationError.invalidImageLayout(index: index)
                }
                guard result.originRevisionID == candidate.originRevisionID else {
                    throw PublicationPreparationError.mediaRevisionMismatch(index: index)
                }
                guard case .usable(let asset) = result.state else {
                    throw PublicationPreparationError.mediaNotUsable(index: index)
                }
                guard let reference = PublishedMediaRef(key: asset.key, pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight, mimeType: asset.mimeType),
                    let imageContract = RenderContract(layout: layout,
                        mediaAspectRatio: Double(asset.pixelWidth) / Double(asset.pixelHeight)) else {
                    throw PublicationPreparationError.invalidDraft(index: index)
                }
                media = PublishedMediaSet(primary: reference)
                contract = imageContract
            }
            let timestampKind: PublishedTimestampKind
            switch candidate.timestamp.kind {
            case .authored: timestampKind = .authored
            case .observed: timestampKind = .observed
            }
            guard let draft = PublicationCardDraft(origin: input.origin, contentEntityID: input.contentEntityID,
                contentClusterID: input.contentClusterID,
                text: PublishedText(title: candidate.headline, primaryText: candidate.summary),
                timestamp: PublishedTimestamp(value: candidate.timestamp.value, kind: timestampKind),
                media: media, renderContract: contract, primaryAction: input.primaryAction) else {
                throw PublicationPreparationError.invalidDraft(index: index)
            }
            return draft
        }
    }
}
