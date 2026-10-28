//
// File: ReaderContentFilterPolicy.swift
// Module: FeedMineComposition
//
// Responsibility:
// The one rule that decides what the reader's content filters actually hide: the gate, the reader's own rules and
// the keywords of the templates they turned on, resolved for their language. Pure, so the same function answers
// the session's selection, the surface that edits the rules and the test that proves both agree.
//
// The gate and the rules are deliberately separate values: turning the filters **off** masks what they hide
// without erasing a single rule — V1 behaved the same way (`ContentFilterStore.isEnabled` gated `activeFilters`,
// and nothing was deleted), and a reader who turns them back on finds their words where they left them.
//
// Does not own: storing the choices (Persistence/Settings), the surface that edits them (UI) or applying them to
// candidates (Editorial reads the `ReaderContentExclusions` this produces).
import Foundation
import FeedMineDomain

public enum ReaderContentFilterPolicy {
    public typealias ResolutionError = ReaderWordExclusionSnapshot.ResolutionError

    /// Strict resolution for future publication; the writer uses the same domain resolver and descriptor.
    public static func resolvedExclusions(settings: ReaderSettings, templates: [ReaderContentFilterTemplate],
        context: ReaderContentExclusions = .disabled,
        languages: [String] = ReaderContentFilterTemplate.preferredLanguages) throws -> ReaderContentExclusions {
        try ReaderWordExclusionSnapshot(settings: settings,
            templates: templates.map { ReaderWordTemplateRules(key: $0.key, rules: $0.rules(languages: languages)) },
            context: context).exclusions
    }

    /// The keyword set the reader's own rules and their enabled templates add up to, whether or not the gate is
    /// on. This is what a surface states and what a rule is added to or removed from.
    public static func rules(settings: ReaderSettings, templates: [ReaderContentFilterTemplate],
        languages: [String] = ReaderContentFilterTemplate.preferredLanguages) -> [String] {
        let byKey = Dictionary(uniqueKeysWithValues: templates.map { ($0.key, $0) })
        let fromTemplates = settings.contentFilterTemplates.flatMap { byKey[$0]?.rules(languages: languages) ?? [] }
        return ReaderContentExclusions.normalize(settings.contentFilterRules + fromTemplates)
    }

    /// What a session applies. The gate is the only thing that can make this empty: with it off, the reader's
    /// rules are still stored, still stated, and hide nothing.
    public static func exclusions(settings: ReaderSettings, templates: [ReaderContentFilterTemplate],
        languages: [String] = ReaderContentFilterTemplate.preferredLanguages) -> ReaderContentExclusions {
        let rules = rules(settings: settings, templates: templates, languages: languages)
        guard settings.contentFiltersEnabled, !rules.isEmpty else { return .disabled }
        return ReaderContentExclusions(isEnabled: true, rules: rules)
    }

    /// The reader's filter, with the exclusions the session should apply. Everything else about the filter —
    /// the lens criteria — is untouched: the content filters are not a lens criterion and never expire.
    public static func applying(settings: ReaderSettings, templates: [ReaderContentFilterTemplate],
        to filter: ReaderFilter, languages: [String] = ReaderContentFilterTemplate.preferredLanguages) -> ReaderFilter {
        filter.replacing(exclusions: exclusions(settings: settings, templates: templates, languages: languages))
    }

    /// The two rule sets a session applies, added together: the ones a **context** carries (a smart bookmark's own
    /// words, which V1 kept per preset and `LegacyUserStateImport` preserves) and the reader's **global** filters.
    ///
    /// Neither replaces the other, and a disabled set contributes nothing — that is what makes the master switch
    /// mask the global rules only, and what keeps an imported bookmark from showing exactly the content it
    /// excluded.
    public static func combining(context: ReaderContentExclusions,
        global: ReaderContentExclusions) -> ReaderContentExclusions {
        let rules = ReaderContentExclusions.normalize((context.isEnabled ? context.rules : [])
            + (global.isEnabled ? global.rules : []))
        guard !rules.isEmpty else { return .disabled }
        return ReaderContentExclusions(isEnabled: true, rules: rules)
    }
}
