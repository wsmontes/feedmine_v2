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
        if !admitsDeclaredScript(candidate) { return false }
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

    /// A story whose own readable text is written in a script its document cannot be speaking is not admitted, for
    /// any reader. This is an integrity rule, not a preference: the measured defect was a channel that declared `en`
    /// and published a Russian advertisement, and the reader who had selected only English received it. Absence of a
    /// declaration, an unknown language or mixed text is no evidence, and no evidence admits.
    private func admitsDeclaredScript(_ candidate: Candidate) -> Bool {
        let text = readableText(of: candidate)
        guard !text.isEmpty else { return true }
        return ReaderLanguageScript.admits(text, declaredLanguage: candidate.language)
    }

    /// What a candidate actually shows: its headline and summary. The body is not read — a story may quote another
    /// language inside its text, and that is not a fact about the card the reader sees first.
    private func readableText(of candidate: Candidate) -> String {
        [candidate.headline, candidate.summary].compactMap { $0 }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func admitsLanguage(_ candidate: Candidate) -> Bool {
        let languages = ReaderLanguageCode.choices(filter.languages)
        guard enforced.contains(.languages), !languages.isEmpty else { return true }
        // The reader's choice is enforced on the text as well as on the declaration: a document that declares a
        // language the reader did not choose has already failed, and one that declares a chosen language but shows
        // an incompatible script is the same defect from the other side.
        guard ReaderLanguageScript.admits(readableText(of: candidate), languages: languages) else { return false }
        guard let language = candidate.language?.trimmingCharacters(in: .whitespacesAndNewlines),
            !language.isEmpty else { return false }
        // The choice is the language, not the code: a filter that named `pt` admits `pt-BR` and `pt-PT`, exactly
        // as the discovery pool does.
        return ReaderLanguageCode.answered(language, by: languages)
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
