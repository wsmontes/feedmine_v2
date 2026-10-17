//
// File: ReaderContentFilterAdapter.swift
// Module: FeedMineComposition
//
// Responsibility:
// The content-filter surface's backend: the reader's gate, their own words and their templates, over the settings
// value the app already stores, with V1's own template catalogue resolved for the reader's language.
//
// Adding or removing a rule never touches the templates' keywords, and turning a template off never touches the
// words the reader typed — the two are stored apart precisely so one cannot erase the other (V1's
// `ContentFilterStore` kept the same distinction).
//
// Does not own: the surface (UI), where preferences live (Persistence) or which candidates a rule hides
// (Editorial, over the exclusions `ReaderContentFilterPolicy` produces).
import Foundation
import FeedMineDomain
import FeedMinePersistence
import FeedMineUI

public struct ReaderContentFilterAdapter: ReaderContentFilterBackend {
    private let database: RuntimeDatabase
    private let templates: [ReaderContentFilterTemplate]
    /// The reader's language and its base language, in the same order and with the same default the policy uses:
    /// a template's words are resolved for the reader, and stating the language is what lets a test pin the count
    /// instead of borrowing the host's.
    private let languages: [String]
    private let bundle: Bundle
    private let onSourceExclusionsChanged: @Sendable () async -> Void

    public init(database: RuntimeDatabase, templates: [ReaderContentFilterTemplate]? = nil,
        languages: [String] = ReaderContentFilterTemplate.preferredLanguages, bundle: Bundle = .main,
        onSourceExclusionsChanged: @escaping @Sendable () async -> Void = {}) {
        self.database = database
        self.templates = templates ?? ReaderContentFilterCatalog.bundled(bundle)
        self.languages = languages
        self.bundle = bundle
        self.onSourceExclusionsChanged = onSourceExclusionsChanged
    }

    public func state() async throws -> ReaderContentFilterState {
        let settings = try settings()
        return ReaderContentFilterState(isEnabled: settings.contentFiltersEnabled,
            rules: settings.contentFilterRules,
            enabledTemplates: settings.contentFilterTemplates,
            templates: templates.map { template in
                ReaderContentFilterTemplateRow(id: template.key, name: template.name(languages: languages),
                    ruleCount: template.rules(languages: languages).count)
            }, sourceExclusions: settings.contentSourceExclusions)
    }

    public func setEnabled(_ enabled: Bool) async throws {
        let before = ReaderSourceExclusionSnapshot(settings: try settings())
        try update { $0.contentFiltersEnabled = enabled }
        if ReaderSourceExclusionSnapshot(settings: try settings()) != before {
            await onSourceExclusionsChanged()
        }
    }

    public func setRules(_ words: [String]) async throws {
        try update { $0.contentFilterRules = words }
    }

    public func setTemplates(_ keys: [String]) async throws {
        try update { $0.contentFilterTemplates = keys }
    }

    public func setSourceExclusions(_ rules: [ReaderSourceExclusion]) async throws {
        let before = ReaderSourceExclusionSnapshot(settings: try settings())
        try update { $0.contentSourceExclusions = rules }
        if ReaderSourceExclusionSnapshot(settings: try settings()) != before {
            await onSourceExclusionsChanged()
        }
    }

    private func settings() throws -> ReaderSettings {
        try ReaderSettingsCoordinator(database: database).settings()
    }

    private func update(_ change: (inout ReaderSettings) -> Void) throws {
        var settings = try settings()
        let before = settings
        change(&settings)
        guard settings != before else { return }
        try ReaderSettingsCoordinator(database: database).update(settings)
    }
}
