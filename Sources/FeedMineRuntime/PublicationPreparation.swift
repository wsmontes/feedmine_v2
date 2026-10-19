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
    case invalidImageLayout(index: Int)
    case invalidDraft(index: Int)
}

/// One publication opportunity after the presentation gate: only candidates whose declared presentation is
/// actually prepared. `selection` and `cardIDs` are reduced with `drafts`, so the coordinator's one-to-one
/// identity stays exact.
public struct PublicationPlan: Hashable, Sendable {
    public let selection: SelectionResult
    public let drafts: [PublicationCardDraft]
    public let cardIDs: [PublicationCardID]
}

public enum PublicationPreparation {
    /// One candidate's draft, or nil when its declared presentation has no prepared media. An image the card
    /// declared but that never became usable does not produce a text card: the candidate leaves the current
    /// publication opportunity (INV-17) and never receives an occurrence in its place.
    private static func draft(selection: SelectionResult, inputs: [PublicationPreparationInput],
        index: Int) throws -> PublicationCardDraft? {
        let candidate = selection.orderedCandidates[index], input = inputs[index]
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
            guard case .usable(let asset) = result.state else { return nil }
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
            media: media, renderContract: contract, primaryAction: input.primaryAction,
            // P10: frozen at publication from the candidate's own facts — never from the latest canonical revision.
            diversity: EditorialDiversityFact(sourceIDs: Array(candidate.sourceIDs), providerID: candidate.providerID,
                subjects: candidate.topics.identities.map(\.key))) else {
            throw PublicationPreparationError.invalidDraft(index: index)
        }
        return draft
    }

    /// Drafts for the presentable candidates; a prepared input whose image is not usable is skipped.
    public static func drafts(selection: SelectionResult,
        inputs: [PublicationPreparationInput]) throws -> [PublicationCardDraft] {
        guard selection.orderedCandidates.count == inputs.count else {
            throw PublicationPreparationError.inputCountMismatch
        }
        return try selection.orderedCandidates.indices.compactMap {
            try draft(selection: selection, inputs: inputs, index: $0)
        }
    }

    /// The whole publication opportunity with excluded candidates removed from the selection it will publish.
    public static func plan(selection: SelectionResult,
        publication: LocalPreparedPublication) throws -> PublicationPlan {
        guard selection.orderedCandidates.count == publication.inputs.count,
            publication.cardIDs.count == publication.inputs.count else {
            throw PublicationPreparationError.inputCountMismatch
        }
        var candidates: [Candidate] = []
        var drafts: [PublicationCardDraft] = []
        var cardIDs: [PublicationCardID] = []
        candidates.reserveCapacity(selection.orderedCandidates.count)
        drafts.reserveCapacity(selection.orderedCandidates.count)
        cardIDs.reserveCapacity(selection.orderedCandidates.count)
        for index in selection.orderedCandidates.indices {
            guard let draft = try draft(selection: selection, inputs: publication.inputs, index: index) else {
                continue
            }
            candidates.append(selection.orderedCandidates[index])
            drafts.append(draft)
            cardIDs.append(publication.cardIDs[index])
        }
        return PublicationPlan(
            selection: SelectionResult(editorialRevision: selection.editorialRevision,
                orderedCandidates: candidates, supplyReport: selection.supplyReport),
            drafts: drafts, cardIDs: cardIDs)
    }
}
