// Owns: editorial candidate identity, narrow content, explicit timestamp meaning and temporal evidence.
// Does not own: Persistence rows, PublishedCard snapshots, selection or ranking.

import Foundation
import FeedMineDomain

/// Where a candidate's timestamp came from. This is provenance, not reliability: an `authored` value is
/// the origin's own declared publication instant as canonical supply accepted it, and an `observed`
/// value is FeedMine's own observation, which is never a publication date and never substitutes for one.
public enum CandidateTimestampKind: Hashable, Sendable {
    case authored
    case observed
}

public struct CandidateTimestamp: Hashable, Sendable {
    public let value: Date
    public let kind: CandidateTimestampKind

    public init(value: Date, kind: CandidateTimestampKind) {
        self.value = value
        self.kind = kind
    }
}

/// The publication date a story may be treated as having. Absence is a stated fact, not a gap to fill:
/// an undated story has no publication date at all, and the observation instant never stands in for one.
public enum PublicationDateEvidence: Hashable, Sendable {
    /// The origin declared this instant and canonical supply accepted it. Declared is not verified:
    /// a publisher-declared date is the publisher's own statement, not an independently confirmed fact.
    case declared(Date)
    /// No publication date is known. This is absence of evidence, never a claim of recency.
    case absent
}

/// An inconsistency the temporal facts state about each other, exactly as they were recorded. It is a
/// computed relation between two accepted values — never a score, and never inferred from age, subject,
/// source name or words in the title.
public enum TemporalInconsistency: Hashable, Sendable {
    /// The accepted change instant precedes the accepted publication instant.
    case modificationBeforePublication(publication: Date, modification: Date)
}

/// The temporal evidence behind one candidate: the three facts that already exist, kept distinct and
/// never interchanged, plus the inconsistencies those facts themselves state.
///
/// There is deliberately no confidence score here, and no inferred category: every value is a recorded
/// fact. The story's contextual nature is a *different* dimension from date reliability and stays
/// `unknown` (see `StoryTemporalNature`) until real evidence and an approved interpretation rule exist.
///
/// Named limit of what canonical supply can reconstruct: the accepted value is the origin's declared
/// instant, or the observation instant when the claim lies ahead of it (the acceptance rule is
/// `OriginDeclaredInstant.accepted(observingAt:)`, applied when the item was translated). A clamped
/// claim is therefore stored as the observation instant and cannot be told apart here from a claim that
/// genuinely equalled it. Re-exposing that difference needs the claim persisted with the revision; it is
/// proposed separately and is not simulated with a heuristic.
public struct CandidateTemporalEvidence: Hashable, Sendable {
    /// The instant FeedMine observed the revision this candidate came from. FeedMine-controlled.
    public let observedAt: Date
    /// The accepted publication instant, when the origin declared one; nil is absence of evidence.
    public let acceptedAuthoredAt: Date?
    /// The accepted change instant, when the origin declared one; nil is absence of evidence.
    public let acceptedModifiedAt: Date?

    public init(observedAt: Date, acceptedAuthoredAt: Date? = nil, acceptedModifiedAt: Date? = nil) {
        self.observedAt = observedAt
        self.acceptedAuthoredAt = acceptedAuthoredAt
        self.acceptedModifiedAt = acceptedModifiedAt
    }

    /// The publication date this story may be treated as having. A missing declaration stays missing:
    /// the observation instant is never promoted into a publication date by default.
    public var publicationDate: PublicationDateEvidence {
        acceptedAuthoredAt.map(PublicationDateEvidence.declared) ?? .absent
    }

    /// The inconsistencies the recorded facts state about each other, in stable order.
    public var inconsistencies: [TemporalInconsistency] {
        guard let acceptedAuthoredAt, let acceptedModifiedAt, acceptedModifiedAt < acceptedAuthoredAt else {
            return []
        }
        return [.modificationBeforePublication(publication: acceptedAuthoredAt, modification: acceptedModifiedAt)]
    }

    /// Contextual temporal nature of this story. UNKNOWN because no approved interpretation rule and no
    /// real evidence for one exist in this build; age, subject, source and title are not evidence.
    public var nature: StoryTemporalNature { .unknown }
}

public struct Candidate: Hashable, Sendable {
    public let originRecordID: OriginRecordID
    public let originRevisionID: OriginRevisionID
    public let headline: String?
    public let summary: String?
    public let timestamp: CandidateTimestamp
    /// The temporal evidence behind `timestamp`. Additive: ordering keeps reading `timestamp`, and no
    /// policy consumes this value in this build, so a published Edition is unaffected by it.
    public let temporal: CandidateTemporalEvidence
    public let language: String?
    public let providerID: ProviderID?
    /// Sources this origin belongs to. Empty means unknown; it never constrains adjacency (PD-4).
    public let sourceIDs: Set<SourceID>
    /// Ordinal-0 canonical media locator; part of PD-1 material identity.
    public let primaryMediaLocator: String?
    /// Canonical body text or a generation-1 enrichment baseline for material recurrence.
    public let declaredBody: String?
    /// Generation 2 observed body presence/absence, or generation 1 has a baseline.
    /// False means legacy body state genuinely unknown (not the same as observed absent).
    public let bodyObserved: Bool
    /// Article URL the card opens (review F10).
    public let primaryLink: URL?

    public init(originRecordID: OriginRecordID, originRevisionID: OriginRevisionID,
        headline: String?, summary: String?, timestamp: CandidateTimestamp,
        temporal: CandidateTemporalEvidence? = nil,
        language: String?, providerID: ProviderID?, sourceIDs: Set<SourceID> = [], primaryMediaLocator: String? = nil,
        primaryLink: URL? = nil, declaredBody: String? = nil, bodyObserved: Bool = false) {
        self.originRecordID = originRecordID
        self.originRevisionID = originRevisionID
        self.headline = headline
        self.summary = summary
        self.timestamp = timestamp
        // A caller that states a timestamp and no evidence is stating the narrowest fact it has: the one
        // instant it gave, read exactly as `timestamp.kind` says — an authored value is that declared
        // publication instant, and an observed value is an observation with no declared publication date.
        // Producers that know the real facts state them; `CandidateProvider` always does.
        self.temporal = temporal ?? CandidateTemporalEvidence(observedAt: timestamp.value,
            acceptedAuthoredAt: timestamp.kind == .authored ? timestamp.value : nil)
        self.language = language
        self.providerID = providerID
        self.sourceIDs = sourceIDs
        self.primaryMediaLocator = primaryMediaLocator
        self.primaryLink = primaryLink
        self.declaredBody = declaredBody
        self.bodyObserved = bodyObserved || declaredBody != nil
    }
}
