// File: SearchExpression.swift
// Module: FeedMineDomain
//
// Responsibility:
// R14: the one interpretation of a search query. The domain owns the grammar; the provider and the UI consume the
// same expression, so a stored query cannot be read by two different parsers.
//
// Grammar (deliberately the approved contract, nothing more):
//   - whitespace separates terms;
//   - a leading `-` marks an excluded term (`astronomia -astrologia`);
//   - a hyphen inside a term is part of it (`teoria-de-cordas`);
//   - a bare `-` is not a term;
//   - case and diacritics never distinguish (`Astronomia` == `astronomia`);
//   - a positive term matches any of the supplied fields; every excluded term must match none;
//   - only negatives (or nothing) cannot start a search.
// No quotes, OR, weights or extra operators are invented.
//
// Does not own: supply, ordering, acquisition, publication or UI.
import Foundation

public struct SearchExpression: Hashable, Sendable {
    /// The reader's original text; never rewritten.
    public let query: String
    /// Positive terms, already normalized for matching, in the order typed.
    public let terms: [String]
    /// Terms that must not appear in any field, normalized.
    public let excludedTerms: [String]

    public init?(query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var terms: [String] = [], excluded: [String] = []
        for raw in query.split(whereSeparator: { $0.isWhitespace }) {
            let token = String(raw)
            guard token != "-" else { continue }
            if token.hasPrefix("-") {
                let body = String(token.dropFirst())
                guard !body.isEmpty, body != "-" else { continue }
                excluded.append(Self.normalize(body))
            } else {
                terms.append(Self.normalize(token))
            }
        }
        self.query = query
        self.terms = terms
        self.excludedTerms = excluded
    }

    /// A query with at least one positive term may search; only negatives cannot.
    public var canSearch: Bool { !terms.isEmpty }

    /// Whether the supplied fields satisfy the expression. Missing fields are absence, never a match.
    public func matches(fields: [String]) -> Bool {
        guard canSearch else { return false }
        let normalized = fields.map(Self.normalize)
        for term in terms where !normalized.contains(where: { $0.contains(term) }) { return false }
        for excluded in excludedTerms where normalized.contains(where: { $0.contains(excluded) }) { return false }
        return true
    }

    /// Case- and diacritic-insensitive matching key; locale-independent (POSIX). Persistence and the host use
    /// this same fold, so a query is interpreted once by the domain and never by a second, divergent parser.
    public static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The semantics a persisted query was written under. A stored query without the marker was written before the
/// expression grammar existed and keeps its literal meaning; new searches state `termsV1` explicitly.
public enum SearchSemantics: String, Codable, Hashable, Sendable {
    case legacyLiteral
    case termsV1
}
