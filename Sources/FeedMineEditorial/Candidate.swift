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

/// What canonical supply can state about one instant a revision carries, whichever temporal fact it
/// belongs to (`publicationDate`, `modificationDate`). The cases are statements of evidence, never a
/// score: an instant is only called `declared` when canonical supply can actually tell it apart from
/// FeedMine's own observation.
public enum PublicationDateEvidence: Hashable, Sendable {
    /// The origin declared this instant and canonical supply holds it apart from the observation.
    /// Declared is not verified: a publisher-declared date is the publisher's own statement, not an
    /// independently confirmed fact.
    case declared(Date)
    /// The accepted instant is exactly the observation instant, and the origin's original declaration is
    /// not available to tell a genuine coincidence apart from a declaration the observation had to accept
    /// as itself. Canonical supply states the ambiguity and claims nothing: this is never read as a
    /// publication date proven to be current.
    case ambiguousAtObservation(Date)
    /// No such instant is known. This is absence of evidence, never a claim of recency.
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
/// fact, and every uncertainty is stated instead of resolved.
///
/// The origin's original declaration is TRANSIENT. It exists only in the acquisition/admission exchange
/// (`AcquisitionObservation.declaredAuthoredAt` / `.declaredModifiedAt`, checked by
/// `AcquisitionAdmissionStore.validate`) and does NOT survive current persistence: canonical supply keeps
/// the accepted value only, so nothing here may claim the declaration was canonically preserved. That is
/// why an accepted instant equal to the observation instant is reported as `ambiguousAtObservation` —
/// a clamped future declaration and a genuine coincidence are the same bytes, and the contract refuses to
/// promote either of them into a provably current publication date.
///
/// The conservative reading never removes a story from the offer: it changes how a date is described, and
/// no policy in this build consumes it (`SelectionEngine` still orders by `timestamp`).
public struct CandidateTemporalEvidence: Hashable, Sendable {
    /// The instant FeedMine observed the revision this candidate came from. FeedMine-controlled.
    public let observedAt: Date
    /// The publication instant canonical supply accepted: the origin's own claim, or the observation
    /// instant when the claim lay ahead of it. nil is absence of a declaration. This raw value cannot tell
    /// a declaration from an acceptance on its own — read `publicationDate` for the evidence.
    public let acceptedAuthoredAt: Date?
    /// The change instant canonical supply accepted, on the same terms as `acceptedAuthoredAt`. Read
    /// `modificationDate` for the evidence.
    public let acceptedModifiedAt: Date?

    public init(observedAt: Date, acceptedAuthoredAt: Date? = nil, acceptedModifiedAt: Date? = nil) {
        self.observedAt = observedAt
        self.acceptedAuthoredAt = acceptedAuthoredAt
        self.acceptedModifiedAt = acceptedModifiedAt
    }

    /// The publication date this story may be treated as having, stated with the uncertainty canonical
    /// supply actually holds. A missing declaration stays missing, and an accepted instant that is exactly
    /// the observation instant stays ambiguous rather than becoming a date of today.
    public var publicationDate: PublicationDateEvidence {
        guard let acceptedAuthoredAt else { return .absent }
        return acceptedAuthoredAt == observedAt ? .ambiguousAtObservation(acceptedAuthoredAt)
            : .declared(acceptedAuthoredAt)
    }

    /// The change-date evidence of this revision, read with the same vocabulary and the same conservative
    /// rule: an accepted change instant equal to the observation instant is ambiguous, so nothing about a
    /// material change is fabricated from it.
    public var modificationDate: PublicationDateEvidence {
        guard let acceptedModifiedAt else { return .absent }
        return acceptedModifiedAt == observedAt ? .ambiguousAtObservation(acceptedModifiedAt)
            : .declared(acceptedModifiedAt)
    }

    /// The inconsistencies the recorded facts state about each other, in stable order. Only two
    /// unambiguous declarations can state one: an accepted instant the observation may have produced
    /// itself is never used to accuse a publisher of an impossible date order.
    public var inconsistencies: [TemporalInconsistency] {
        guard case .declared(let publication) = publicationDate,
            case .declared(let modification) = modificationDate, modification < publication else {
            return []
        }
        return [.modificationBeforePublication(publication: publication, modification: modification)]
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
        // instant it gave, read exactly as `timestamp.kind` says — an observed value is an observation with
        // no declared publication date, and an authored value is an accepted publication instant with no
        // separate observation instant to compare it against. That authored reading lands on
        // `ambiguousAtObservation`: with only one instant available, a declared date equal to it cannot be
        // told apart from a declaration the observation had to accept as itself, and the contract never
        // turns that into a declared publication date by assumption. Producers that know the real facts
        // state them; `CandidateProvider` always does.
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
