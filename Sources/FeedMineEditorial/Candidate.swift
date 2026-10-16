// Owns: editorial candidate identity, narrow content, explicit timestamp meaning and topic evidence.
// Does not own: Persistence rows, PublishedCard snapshots, selection or ranking.

import Foundation
import FeedMineDomain

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

/// The topic evidence behind one candidate: the subjects the story's own document declared for it, as
/// canonical supply recorded them, plus the identity those declarations may carry.
///
/// Absence is a stated fact, not a gap to fill. A story whose document declared no subject has no topic
/// evidence at all, and nothing here may invent one from the Source, the catalogue, the headline, the
/// summary or a classifier. This is not the feed's taxonomy and not the Source's: a source's placement
/// is a different identity and never fills this one.
///
/// There is deliberately no FeedMine node and no confidence here: a declared subject is the publisher's
/// own text in the publisher's own vocabulary, and its identity compares *declarations*, never meanings
/// (see `DeclaredSubjectEquivalence`).
public struct CandidateTopicEvidence: Hashable, Sendable {
    /// The recorded declarations, deduplicated and in canonical order. Empty is absence of evidence.
    public let declaredSubjects: [DeclaredSubjectClaim]

    public init(_ subjects: StoryDeclaredSubjects? = nil) {
        self.declaredSubjects = subjects?.claims ?? []
    }

    /// The evidence of a story whose own document declared no subject.
    public static let absent = CandidateTopicEvidence()

    /// True when the story declared nothing: absence of evidence, never evidence of one subject.
    public var isAbsent: Bool { declaredSubjects.isEmpty }

    /// The identities those declarations carry, in the same canonical order — the topic identity a
    /// consumer compares, reconstructed from the canonical declaration alone.
    public var identities: [DeclaredSubjectIdentity] { declaredSubjects.map(\.identity) }

    /// How far those identities reach: `.declaredLabelOnly`, always. No mapping to a FeedMine taxonomic
    /// node exists in this build, so none is assigned to any declaration.
    public var equivalence: DeclaredSubjectEquivalence { .declaredLabelOnly }

    /// Whether two candidates declare at least one identical subject: true only when both documents used
    /// the same item-level surface, named the same taxonomy (or none on both sides) and wrote text that
    /// normalizes the same way. It compares recorded declarations; it is never a judgement that two
    /// stories are about the same thing, and nothing in this build consumes it to order anything.
    public func sharesDeclaredSubject(with other: CandidateTopicEvidence) -> Bool {
        !Set(identities).isDisjoint(with: Set(other.identities))
    }
}

public struct Candidate: Hashable, Sendable {
    public let originRecordID: OriginRecordID
    public let originRevisionID: OriginRevisionID
    public let headline: String?
    public let summary: String?
    public let timestamp: CandidateTimestamp
    /// The topic evidence behind this candidate: the subjects the story's own document declared, and
    /// nothing else. Additive: ordering, eligibility and publication keep reading what they already read,
    /// and no policy consumes this value in this build, so a published Edition is unaffected by it.
    public let topics: CandidateTopicEvidence
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
        topics: CandidateTopicEvidence = .absent,
        language: String?, providerID: ProviderID?, sourceIDs: Set<SourceID> = [], primaryMediaLocator: String? = nil,
        primaryLink: URL? = nil, declaredBody: String? = nil, bodyObserved: Bool = false) {
        self.originRecordID = originRecordID
        self.originRevisionID = originRevisionID
        self.headline = headline
        self.summary = summary
        self.timestamp = timestamp
        // A caller that states no topics is stating the narrowest fact it has, and the only honest one: a
        // story whose document declared no subject has no topic evidence, and one is never inferred from
        // its text, its Source or the catalogue. A producer that knows the real declarations states them;
        // `CandidateProvider` always does.
        self.topics = topics
        self.language = language
        self.providerID = providerID
        self.sourceIDs = sourceIDs
        self.primaryMediaLocator = primaryMediaLocator
        self.primaryLink = primaryLink
        self.declaredBody = declaredBody
        self.bodyObserved = bodyObserved || declaredBody != nil
    }
}
