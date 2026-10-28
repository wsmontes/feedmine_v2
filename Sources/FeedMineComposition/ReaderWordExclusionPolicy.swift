import FeedMineDomain
import FeedMinePersistence

/// The immutable language/catalogue inputs of this reader's publication opportunities. Current
/// preferences are always read strictly; this value is not a second settings or policy registry.
public struct ReaderWordExclusionPolicy: Sendable {
    private let database: RuntimeDatabase
    private let templates: [ReaderWordTemplateRules]
    private let context: ReaderContentExclusions

    public init(database: RuntimeDatabase, templates: [ReaderContentFilterTemplate],
        context: ReaderContentExclusions = .disabled,
        languages: [String] = ReaderContentFilterTemplate.preferredLanguages) {
        self.database = database
        self.context = context
        self.templates = templates.map { ReaderWordTemplateRules(key: $0.key, rules: $0.rules(languages: languages)) }
    }

    public func capture() throws -> ReaderWordExclusionSnapshot {
        try ReaderPreferencesStore(database: database).wordExclusionSnapshot(templates: templates, context: context)
    }
}
