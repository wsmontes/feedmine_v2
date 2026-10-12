// File: ReaderLanguageCode.swift
// Module: FeedMineDomain
//
// Responsibility:
//   The one vocabulary of language choices: the catalogue declares codes like `en`, `en-US`, `pt-BR`, a reader
//   chooses a *language*, and everything that stores, shows or matches a language speaks the primary subtag.
//
// Does not own:
//   Naming a language for a reader (presentation) or reading the catalogue (Persistence).
//
// Why this exists:
//   `pt-BR` and `pt` are the same language to a reader and to the engine, but they were two identities in three
//   places at once: the filter stored the raw catalogue code, the onboarding chip appended the raw code without
//   normalization, and the discovery profile required exact membership of a set documented as primary subtags.
//   A regional selection therefore admitted only its own regional sources in one path and nothing at all in the
//   other. One rule, applied at every entrance: the choice is the primary subtag, lowercased.

import Foundation

public enum ReaderLanguageCode {
    /// `pt-BR` → `pt`, `en_us` → `en`, `PT` → `pt`. An empty code stays empty: the catalogue's undeclared bucket.
    public static func choice(_ code: String) -> String {
        String(code.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(while: { $0 != "-" && $0 != "_" })).lowercased()
    }

    /// A code that names no language a reader could have chosen (`und`, or nothing).
    public static func isUndeclared(_ code: String) -> Bool {
        let choice = choice(code)
        return choice.isEmpty || choice == "und"
    }

    /// A set of choices: normalized, duplicates collapsed, empty values dropped. A selection holding both `pt`
    /// and `pt-BR` is one choice, not two.
    public static func choices<S: Sequence>(_ codes: S) -> Set<String> where S.Element == String {
        Set(codes.map(choice).filter { !$0.isEmpty })
    }

    /// Whether a value a source or a catalogue row declares answers one of the reader's own choices.
    public static func answered(_ declared: String, by choices: Set<String>) -> Bool {
        choices.contains(choice(declared))
    }
}
