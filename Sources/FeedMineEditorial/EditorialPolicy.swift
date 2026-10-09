// Owns: nominal executable-policy identity and explicit pure baseline behaviors.
// Does not own: policy resolution, storage or publication.

import FeedMineDomain

public struct ResolvedSelectionPolicy: Hashable, Sendable {
    public enum EligibilityBehavior: Hashable, Sendable { case structuralOnly; case selectedSources(Set<SourceID>) }
    public enum ScoringBehavior: Hashable, Sendable { case equal }
    public enum SequencingBehavior: Hashable, Sendable {
        case recencyDescending
        /// Recency order with PD-4 source alternation: never two adjacent cards sharing a source.
        case recencyAlternatingSources
    }
    public enum ExposureBehavior: Hashable, Sendable {
        case none
        /// Phase 3R5: an origin published in the Edition never occurs again.
        case excludePublishedRevisions
        /// PD-1: an origin occurs again when its title or text changed materially (edited article).
        case excludePublishedMaterial
    }

    public let contextKey: ContextKey
    public let userSelectionVersion: PolicyVersion
    public let eligibilityPolicyVersion: PolicyVersion
    public let scoringPolicyVersion: PolicyVersion
    public let sequencingPolicyVersion: PolicyVersion
    public let exposurePolicyVersion: PolicyVersion
    public let selectionSchemaVersion: SelectionSchemaVersion
    public let eligibility: EligibilityBehavior
    public let scoring: ScoringBehavior
    public let sequencing: SequencingBehavior
    public let exposure: ExposureBehavior

    public init(contextKey: ContextKey, userSelectionVersion: PolicyVersion,
        eligibilityPolicyVersion: PolicyVersion, scoringPolicyVersion: PolicyVersion,
        sequencingPolicyVersion: PolicyVersion, exposurePolicyVersion: PolicyVersion,
        selectionSchemaVersion: SelectionSchemaVersion, eligibility: EligibilityBehavior,
        scoring: ScoringBehavior, sequencing: SequencingBehavior, exposure: ExposureBehavior) {
        self.contextKey = contextKey
        self.userSelectionVersion = userSelectionVersion
        self.eligibilityPolicyVersion = eligibilityPolicyVersion
        self.scoringPolicyVersion = scoringPolicyVersion
        self.sequencingPolicyVersion = sequencingPolicyVersion
        self.exposurePolicyVersion = exposurePolicyVersion
        self.selectionSchemaVersion = selectionSchemaVersion
        self.eligibility = eligibility
        self.scoring = scoring
        self.sequencing = sequencing
        self.exposure = exposure
    }

    func matches(_ revision: EditorialRevision) -> Bool {
        contextKey == revision.contextKey
            && userSelectionVersion == revision.userSelectionVersion
            && eligibilityPolicyVersion == revision.eligibilityPolicyVersion
            && scoringPolicyVersion == revision.scoringPolicyVersion
            && sequencingPolicyVersion == revision.sequencingPolicyVersion
            && exposurePolicyVersion == revision.exposurePolicyVersion
            && selectionSchemaVersion == revision.selectionSchemaVersion
    }
}
