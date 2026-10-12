import FeedMineDomain
import FeedMineRuntime
import SwiftUI

/// The reader's discovery answers as a control set, written **once**: the first run, the settings page
/// ("Preferências de descoberta") and anything else that edits the same value render the same controls over the
/// same `FeedRecipeDefinition`, so two surfaces can never disagree about what the reader asked for.
///
/// The identifiers carry a prefix because the surfaces are told apart by a test that has to reach the control it
/// means: the Composer keeps `composer-*` (its own tests and the acceptance driver name those), the settings page
/// uses `discovery-*`.
public struct ReaderDiscoveryControls: View {
    /// How much of the answer set a surface shows. The **first run** collects only languages and places — the
    /// reader enters the feed and answers about subjects *inside it* (F02); everything else belongs to the
    /// discovery preferences page, where a reader who wants to tune the machinery goes on purpose.
    public enum Scope: Sendable {
        case firstRun
        case full
    }

    @Binding private var recipe: FeedRecipeDefinition
    /// Which language's regions are open. One at a time: the expansion is about the language being looked at.
    @State private var expandedLanguage: String?
    private let languages: [OnboardingLanguage]
    private let topics: [OnboardingTopic]
    private let places: [OnboardingRegion]
    private let showsTopics: Bool
    private let scope: Scope
    private let identifierPrefix: String

    public init(recipe: Binding<FeedRecipeDefinition>, languages: [OnboardingLanguage] = [],
        topics: [OnboardingTopic] = [], places: [OnboardingRegion] = [], showsTopics: Bool = true,
        scope: Scope = .full, identifierPrefix: String = "composer") {
        _recipe = recipe
        self.languages = languages
        self.topics = topics
        self.places = places
        self.showsTopics = showsTopics
        self.scope = scope
        self.identifierPrefix = identifierPrefix
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: FeedDesignTokens.Spacing.deck) {
            languageControl
            if !places.isEmpty { placeControl }
            if scope == .full {
                discoveryControl
                balanceControl
                if showsTopics, !topics.isEmpty { topicControl }
                mediaControl
            }
        }
    }

    private var languageControl: some View {
        OnboardingSection(title: String(localized: "Idiomas")) {
            let available = languages.isEmpty
                ? recipe.languages.map { OnboardingLanguage(recipeCode: $0) }
                : languages
            VStack(alignment: .leading, spacing: 8) {
                FlowRow(items: available) { language in
                    let isOn = recipe.languages.contains(language.code)
                    HStack(spacing: 4) {
                        Button {
                            var next = recipe
                            if isOn {
                                // V1 kept at least one language: removing the last one is not a state it allowed.
                                guard next.languages.count > 1 else { return }
                                next.languages.removeAll { $0 == language.code }
                            } else {
                                next.languages = next.languages + [language.code]
                            }
                            recipe = next
                        } label: {
                            chip(language.name, isOn: isOn)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("\(identifierPrefix)-language-\(language.code)")
                        if language.hasRegionVariants {
                            Button {
                                expandedLanguage = expandedLanguage == language.code ? nil : language.code
                            } label: {
                                Image(systemName: expandedLanguage == language.code
                                    ? "chevron.down" : "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("\(identifierPrefix)-language-regions-\(language.code)")
                            .accessibilityLabel(Text(verbatim: String(localized: "Regiões de \(language.name)")))
                        }
                    }
                }
                if let expanded = expandedLanguage,
                    let language = available.first(where: { $0.code == expanded }) {
                    languageVariants(language)
                }
            }
        }
    }

    /// What the catalogue holds under the chosen language: the total, then the regions it comes from. A variant
    /// is information — it is named and counted, and there is nothing here to select, because choosing a region
    /// is a different feature from choosing a language.
    private func languageVariants(_ language: OnboardingLanguage) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(language.name) · " + CatalogLanguageNaming.availableSourcesLabel(language.availableSources))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(language.variants) { variant in
                HStack(spacing: 8) {
                    Text(verbatim: variant.hasRegion
                        ? variant.label : String(localized: "Região não especificada"))
                        .font(.caption2).foregroundStyle(.secondary)
                        .accessibilityIdentifier("\(identifierPrefix)-language-variant-\(variant.code)")
                    Spacer(minLength: 0)
                    Text(verbatim: CatalogLanguageNaming.numberLabel(variant.availableSources))
                        .font(.caption2).foregroundStyle(.tertiary)
                        .accessibilityIdentifier("\(identifierPrefix)-language-variant-count-\(variant.code)")
                }
            }
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Where the reader is curious about. More than one place is allowed — "idiomas e lugares" is the answer the
    /// first run collects — and each answer is stored in the recipe's own vocabulary (`topic:90_countries/<place>`)
    /// so the discovery pool reads it like any other interest. Tapping a chosen place takes the answer back.
    private var placeControl: some View {
        OnboardingSection(title: String(localized: "Lugares")) {
            FlowRow(items: places) { place in
                let isOn = recipe.topicPreferences[place.preferenceKey] == .more
                Button {
                    var next = recipe
                    if isOn {
                        next.topicPreferences[place.preferenceKey] = nil
                    } else {
                        next.topicPreferences[place.preferenceKey] = .more
                    }
                    recipe = next
                } label: {
                    chip(place.name, isOn: isOn)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(identifierPrefix)-region-\(place.key)")
            }
        }
    }

    private var discoveryControl: some View {
        OnboardingSection(title: String(localized: "Descoberta")) {
            VStack(alignment: .leading, spacing: 4) {
                Slider(value: Binding(get: { recipe.discoveryLevel },
                    set: { value in var next = recipe; next.discoveryLevel = value; recipe = next }), in: 0...1)
                    .accessibilityIdentifier("\(identifierPrefix)-discovery")
                HStack {
                    Text(verbatim: String(localized: "Focado")).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text(verbatim: String(localized: "Exploratório")).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// V1's "Source balance": three rows, each a Less/Balanced/More cycle on its own editorial key.
    private var balanceControl: some View {
        OnboardingSection(title: String(localized: "Equilíbrio de fontes")) {
            VStack(spacing: 0) {
                balanceRow(String(localized: "Referências estabelecidas"), key: "editorial:reference")
                balanceRow(String(localized: "Fontes especializadas"), key: "editorial:specialist")
                balanceRow(String(localized: "Vozes independentes"), key: "editorial:distinctive")
            }
        }
    }

    private func balanceRow(_ title: String, key: String) -> some View {
        let level = recipe.editorialPreferences[key] ?? .neutral
        return HStack {
            Text(verbatim: title).font(.subheadline)
            Spacer()
            Button {
                var next = recipe
                next.editorialPreferences[key] = level.next()
                recipe = next
            } label: {
                HStack(spacing: 6) {
                    Text(verbatim: level.balanceLabel).font(.caption)
                    Image(systemName: "chevron.right").font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(identifierPrefix)-balance-\(key)")
        }
        .padding(.vertical, 6)
    }

    private var topicControl: some View {
        OnboardingSection(title: String(localized: "Assuntos")) {
            VStack(spacing: 0) {
                ForEach(topics) { topic in
                    let level = recipe.topicPreferences[topic.key] ?? .neutral
                    HStack {
                        Text(verbatim: topic.name).font(.subheadline)
                        Spacer()
                        Button {
                            var next = recipe
                            next.topicPreferences[topic.key] = level.next()
                            recipe = next
                        } label: {
                            Text(verbatim: level.topicLabel)
                                .font(.caption)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(chipBackground(level), in: Capsule())
                                .foregroundStyle(level == .more ? Color.white : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("\(identifierPrefix)-topic-\(Self.nodeKey(topic.key))")
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var mediaControl: some View {
        OnboardingSection(title: String(localized: "Tipos de conteúdo")) {
            VStack(spacing: 0) {
                ForEach(ReaderRecipeMediaType.allCases, id: \.rawValue) { kind in
                    Toggle(isOn: Binding(get: { recipe.mediaTypes.contains(kind) }, set: { value in
                        var next = recipe
                        if value { next.mediaTypes.insert(kind) } else { next.mediaTypes.remove(kind) }
                        // V1 never let a recipe ask for nothing; the last kind cannot be switched off.
                        guard !next.mediaTypes.isEmpty else { return }
                        recipe = next
                    })) {
                        Text(verbatim: kind.displayName).font(.subheadline)
                    }
                    .tint(.green)
                    .accessibilityIdentifier("\(identifierPrefix)-media-\(kind.rawValue)")
                    .padding(.vertical, 2)
                }
            }
        }
    }

    /// A chosen answer is stated to assistive technology too, not only by colour: a reader using VoiceOver has to
    /// hear which language, place or balance they picked, and a surface that only paints its state hides it.
    private func chip(_ title: String, isOn: Bool) -> some View {
        Text(verbatim: title)
            .font(.caption)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(isOn ? Color.accentColor.opacity(0.18) : Color.clear, in: Capsule())
            .overlay(Capsule().stroke(isOn ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 1))
            .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private func chipBackground(_ level: ReaderPreferenceLevel) -> Color {
        switch level {
        case .more: return .accentColor
        case .neutral: return .clear
        case .less: return .clear
        }
    }

    /// The identifier carries the catalogue's own node key, without the `topic:` the recipe stores it under: the
    /// benchmark names interests that way (`04-technology-science`), and a surface a test has to reach should be
    /// named in the vocabulary the rest of the product speaks.
    static func nodeKey(_ key: String) -> String {
        key.hasPrefix("topic:") ? String(key.dropFirst("topic:".count)) : key
    }
}
