// File: ReaderFilterEligibility.swift
// Module: FeedMineEditorial
// Owns: whether one candidate satisfies the reader's filter — the enforceable half of T6.
// Does not own: acquiring supply, ordering, publication or the filter sheet.
//
// Honesty rule (T6, Codex review 2026-10-09): a criterion this build cannot answer is **not consulted**
// and the UI must not offer it; a criterion that is consulted is never satisfied by inventing metadata —
// a missing language fails a language criterion instead of passing it by default.

import Foundation
import FeedMineDomain

public struct ReaderFilterEligibility: Hashable, Sendable {
    public let filter: ReaderFilter
    /// Sources this context restricts to; nil means "whatever the context already selected". A candidate
    /// with unknown memberships is not excluded by this (the acquisition boundary scoped the query already).
    public let restrictedSourceIDs: Set<SourceID>?
    /// Criteria this build can actually answer. Anything outside it is ignored here.
    public let enforced: Set<ReaderFilterCriterion>

    public init(filter: ReaderFilter, restrictedSourceIDs: Set<SourceID>? = nil,
        enforced: Set<ReaderFilterCriterion> = ReaderFilterCriterion.enforceable) {
        self.filter = filter
        self.restrictedSourceIDs = restrictedSourceIDs
        self.enforced = enforced
    }

    /// The eligibility of a plain, unfiltered surface: everything is admitted.
    public static let unfiltered = ReaderFilterEligibility(filter: .unrestricted)

    public var isUnrestricted: Bool {
        filter.isUnrestricted && (restrictedSourceIDs?.isEmpty ?? true)
    }

    /// True when this candidate may enter selection.
    public func admits(_ candidate: Candidate) -> Bool {
        if !admitsSources(candidate) { return false }
        if !admitsLanguage(candidate) { return false }
        if !admitsMood(candidate) { return false }
        return !hides(candidate)
    }

    /// V1 filtered by source selection before anything else; a candidate whose origin belongs only to
    /// sources outside the restriction is not eligible.
    private func admitsSources(_ candidate: Candidate) -> Bool {
        guard let restrictedSourceIDs, !restrictedSourceIDs.isEmpty else { return true }
        guard !candidate.sourceIDs.isEmpty else { return true }
        return !candidate.sourceIDs.isDisjoint(with: restrictedSourceIDs)
    }

    private func admitsLanguage(_ candidate: Candidate) -> Bool {
        let languages = filter.languages
        guard enforced.contains(.languages), !languages.isEmpty else { return true }
        guard let language = candidate.language?.trimmingCharacters(in: .whitespacesAndNewlines),
            !language.isEmpty else { return false }
        // Compare on the primary subtag, as V1 did when it stored "pt" while a feed declared "pt-BR".
        let primary = String(language.prefix(while: { $0 != "-" && $0 != "_" })).lowercased()
        return languages.contains { $0.lowercased() == primary || $0.lowercased() == language.lowercased() }
    }

    private func admitsMood(_ candidate: Candidate) -> Bool {
        guard enforced.contains(.mood) else { return true }
        return filter.mood.matches(candidate.headline)
    }

    /// Keyword exclusions hide a card by its readable text; they never expire and are consulted whenever
    /// they carry rules.
    private func hides(_ candidate: Candidate) -> Bool {
        let exclusions = filter.exclusions
        guard exclusions.isEnabled, !exclusions.rules.isEmpty else { return false }
        return exclusions.excludes(candidate.headline) || exclusions.excludes(candidate.summary)
    }
}
