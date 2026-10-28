/// One template's words already resolved for the opportunity's language. Labels and catalogue IO
/// belong to Composition; this immutable descriptor can also be evaluated inside a writer transaction.
public struct ReaderWordTemplateRules: Hashable, Sendable {
    public let key: String
    public let rules: [String]

    public init(key: String, rules: [String]) {
        self.key = key
        self.rules = ReaderContentExclusions.normalize(rules)
    }
}

/// The effective word policy and the inputs needed to validate it against current durable settings.
/// Global settings never alter the contextual key or previously published history.
public struct ReaderWordExclusionSnapshot: Hashable, Sendable {
    public enum ResolutionError: Error, Equatable {
        case duplicateTemplate(String)
        case missingTemplates([String])
    }

    public let templates: [ReaderWordTemplateRules]
    public let context: ReaderContentExclusions
    public let exclusions: ReaderContentExclusions

    public init(settings: ReaderSettings, templates: [ReaderWordTemplateRules],
        context: ReaderContentExclusions = .disabled) throws {
        self.templates = templates
        self.context = context
        exclusions = try Self.resolve(settings: settings, templates: templates, context: context)
    }

    /// Compare meaning, not the master bit or selected template IDs: overlapping context words and
    /// equivalent templates can make a settings change semantically identical for this opportunity.
    public func matches(settings: ReaderSettings) throws -> Bool {
        try Self.resolve(settings: settings, templates: templates, context: context) == exclusions
    }

    private static func resolve(settings: ReaderSettings, templates: [ReaderWordTemplateRules],
        context: ReaderContentExclusions) throws -> ReaderContentExclusions {
        var words = context.isEnabled ? context.rules : []
        if settings.contentFiltersEnabled {
            words.append(contentsOf: settings.contentFilterRules)
            if !settings.contentFilterTemplates.isEmpty {
                var byKey: [String: ReaderWordTemplateRules] = [:]
                for template in templates.sorted(by: { $0.key < $1.key }) {
                    guard byKey.updateValue(template, forKey: template.key) == nil else {
                        throw ResolutionError.duplicateTemplate(template.key)
                    }
                }
                let missing = Set(settings.contentFilterTemplates).filter { byKey[$0] == nil }.sorted()
                guard missing.isEmpty else { throw ResolutionError.missingTemplates(missing) }
                for key in settings.contentFilterTemplates {
                    // All selected keys were checked above; never silently drop an unresolved rule.
                    guard let template = byKey[key] else { throw ResolutionError.missingTemplates([key]) }
                    words.append(contentsOf: template.rules)
                }
            }
        }
        let normalized = ReaderContentExclusions.normalize(words)
        return normalized.isEmpty ? .disabled : ReaderContentExclusions(isEnabled: true, rules: normalized)
    }
}
