// Owns: nominal executable-policy identity and explicit pure baseline behaviors.
// Does not own: policy resolution, storage or publication.

import FeedMineDomain

public struct ResolvedSelectionPolicy: Hashable, Sendable {
    public enum EligibilityBehavior: Hashable, Sendable { case structuralOnly; case selectedSources(Set<SourceID>) }
    public enum ScoringBehavior: Hashable, Sendable {
        case equal
        /// T11: a curated feed ranks its sources by the reader's own recipe. The weights are keyed by the
        /// session's own source identities, which is what the engine can see; resolving a recipe into them is
        /// `FeedRecipeResolution`'s business and never the engine's. A source with no weight weighs 1.
        case weighted([SourceID: Double])
    }
    public enum SequencingBehavior: Hashable, Sendable {
        case recencyDescending
        /// Sequencing v2: recency order with PD-4 source alternation — never two adjacent cards sharing a
        /// source, taking the earliest compatible candidate. An Edition published under v2 keeps this
        /// behavior when it is restored and read forward; changing it in place would re-run old Editions
        /// under a rule they were never published with.
        case recencyAlternatingSources
        /// Sequencing v3 (R2-D1): the same PD-4 alternation, but the next source is the one that has
        /// consumed the smallest share of what this window offers it (recency breaks the tie). PD-4 alone
        /// produced `A B A C A` on a real window holding twelve sources; measured, this rule meets every
        /// source in the window before repeating one, keeps a reserve of the scarce sources PD-4 needs to
        /// keep publishing, and places as many cards as the greedy rule did. This is the behavior for a
        /// policy that is not weighting anything (`.equal`).
        case recencyAlternatingSourcesBySupplyShare
        /// Sequencing v4 (R2 review): the same rule, with the reader's own weights shaping it — the
        /// prospective priority is `(served + 1) / offered / weight`, so a source the recipe favours is
        /// served sooner and a source it disfavours later, from the first choice on. Weights come from
        /// `FeedRecipeResolution` (clamped to 0.42…3.0), so this is a gradual preference, never an absolute
        /// precedence: PD-4 still binds every adjacent pair and no source is starved. Kept as its own
        /// version so the unweighted v3 keeps the meaning the Editions published under it were given.
        case recencyAlternatingSourcesByWeightedSupplyShare
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
