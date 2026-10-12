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
    private let bundle: Bundle

    public init(database: RuntimeDatabase, templates: [ReaderContentFilterTemplate]? = nil,
        bundle: Bundle = .main) {
        self.database = database
        self.templates = templates ?? ReaderContentFilterCatalog.bundled(bundle)
        self.bundle = bundle
    }

    public func state() async throws -> ReaderContentFilterState {
        let settings = try settings()
        return ReaderContentFilterState(isEnabled: settings.contentFiltersEnabled,
            rules: settings.contentFilterRules,
            enabledTemplates: settings.contentFilterTemplates,
            templates: templates.map { template in
                ReaderContentFilterTemplateRow(id: template.key, name: template.name(),
                    ruleCount: template.rules().count)
            })
    }

    public func setEnabled(_ enabled: Bool) async throws {
        try update { $0.contentFiltersEnabled = enabled }
    }

    public func setRules(_ words: [String]) async throws {
        try update { $0.contentFilterRules = words }
    }

    public func setTemplates(_ keys: [String]) async throws {
        try update { $0.contentFilterTemplates = keys }
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
