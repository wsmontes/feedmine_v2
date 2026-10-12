//
// File: ReaderDiscoveryPreferencesView.swift
// Module: FeedMineUI
//
// Responsibility:
// The reader's discovery answers in one place: the languages and places discovery starts from, how far it may
// explore, the editorial balance, the subjects, the content kinds — and the interests the reader declared by
// answering invitations inside the feed. Every control writes the same stored profile the feed reads, so an
// answer given here and an answer given in the feed are the same answer.
//
// Does not own: the discovery query (Composition), persistence (the settings backend) or the feed itself.
import FeedMineDomain
import SwiftUI

public struct ReaderDiscoveryPreferencesView: View {
    private let store: ReaderSettingsStore
    private let languages: [OnboardingLanguage]
    private let topics: [OnboardingTopic]
    private let places: [OnboardingRegion]
    /// Saving "a feed with these preferences" and opening it. The page never activates a feed by itself: creating
    /// one must not move the reading, so opening it is the reader's own next step (offered, never taken).
    private let onCreateFeed: (FeedRecipeDefinition, String) async -> ContextKey?
    private let onOpenFeed: (ContextKey) async -> Void

    @State private var feedName = ""
    @State private var createdKey: ContextKey?
    @State private var isCreating = false

    public init(store: ReaderSettingsStore, languages: [OnboardingLanguage] = [],
        topics: [OnboardingTopic] = [], places: [OnboardingRegion] = [],
        onCreateFeed: @escaping (FeedRecipeDefinition, String) async -> ContextKey? = { _, _ in nil },
        onOpenFeed: @escaping (ContextKey) async -> Void = { _ in }) {
        self.store = store
        self.languages = languages
        self.topics = topics
        self.places = places
        self.onCreateFeed = onCreateFeed
        self.onOpenFeed = onOpenFeed
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FeedDesignTokens.Spacing.deck) {
                Text(verbatim: String(localized: """
                    Descoberta é o que o FeedMine procura por você fora do seu feed: as respostas abaixo dizem \
                    onde olhar. Mudar uma resposta não mexe no que já está na sua tela.
                    """))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("discovery-preferences-summary")
                ReaderDiscoveryControls(recipe: profile, languages: languages, topics: topics, places: places,
                    identifierPrefix: "discovery")
                editorialTipsSection
                declaredInterests
                createFeedSection
            }
            .padding(FeedDesignTokens.Spacing.page)
        }
        .navigationTitle(String(localized: "Preferências de descoberta"))
        .accessibilityIdentifier("discovery-preferences")
    }

    /// A feed of the reader's own, built from these answers. F02 took the questionnaire out of the first run, not
    /// the reader's ability to state rules once and keep them: the rules are right here to review, the feed gets a
    /// name, and it stays where the library can find it.
    @ViewBuilder private var createFeedSection: some View {
        OnboardingSection(title: String(localized: "Criar um feed com estas preferências")) {
            VStack(alignment: .leading, spacing: FeedDesignTokens.Spacing.tight) {
                TextField(String(localized: "Nome do feed"), text: $feedName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("discovery-feed-name")
                HStack(spacing: FeedDesignTokens.Spacing.tight) {
                    Button {
                        isCreating = true
                        let recipe = store.settings.discoveryProfile
                        let name = feedName
                        Task {
                            createdKey = await onCreateFeed(recipe, name)
                            isCreating = false
                        }
                    } label: {
                        Text(verbatim: String(localized: "Criar feed com estas preferências"))
                    }
                    .buttonStyle(.bordered)
                    .disabled(isCreating || feedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("discovery-create-feed")
                    if let createdKey {
                        Button {
                            let key = createdKey
                            Task { await onOpenFeed(key) }
                        } label: {
                            Text(verbatim: String(localized: "Abrir feed"))
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("discovery-open-created-feed")
                    }
                }
                Text(verbatim: String(localized: "Criar não abre nada nem muda o que você está lendo."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("discovery-create-note")
            }
        }
    }

    /// Round 10's way back (the PO's P1): hiding the invitations is a preference, and this — the page that reads
    /// the interests they taught the engine — is where they come back. Turning them on again is the reader's own
    /// explicit act; nothing else in the app turns the offers back on.
    @ViewBuilder private var editorialTipsSection: some View {
        OnboardingSection(title: String(localized: "Sugestões no feed")) {
            VStack(alignment: .leading, spacing: FeedDesignTokens.Spacing.tight) {
                Toggle(isOn: Binding(
                    get: { !store.settings.editorialTipsHidden },
                    set: { value in
                        Task { await store.update { $0.editorialTipsHidden = !value } }
                    })) {
                    Text(verbatim: String(localized: "Mostrar sugestões do FeedMine"))
                }
                .accessibilityIdentifier("discovery-editorial-tips")
                Text(verbatim: String(localized: "As sugestões aparecem de quando em quando, depois de um artigo. Esconder não apaga as respostas que você já deu nem muda o seu feed."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The interests the reader declared — in the feed or here — with the way back. A vote is not final: the PRD
    /// is explicit that a person changes their mind without punishment, so every declared interest can be dropped.
    @ViewBuilder private var declaredInterests: some View {
        let declared = store.settings.discoveryProfile.topicPreferences
            .filter { $0.value == .more && !isPlace($0.key) }
            .keys.sorted()
        if !declared.isEmpty {
            OnboardingSection(title: String(localized: "Assuntos que você pediu")) {
                VStack(spacing: 0) {
                    ForEach(declared, id: \.self) { key in
                        HStack {
                            Text(verbatim: name(for: key)).font(.subheadline)
                            Spacer()
                            Button {
                                Task { await store.update { $0.discoveryProfile.topicPreferences[key] = nil } }
                            } label: {
                                Text(verbatim: String(localized: "Remover")).font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("discovery-declared-\(key)")
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    /// The profile as the settings store holds it: a control change is one stored update, and the store's own
    /// read-back is what the controls then show.
    private var profile: Binding<FeedRecipeDefinition> {
        Binding(
            get: { store.settings.discoveryProfile },
            set: { value in Task { await store.update { $0.discoveryProfile = value } } })
    }

    private func isPlace(_ key: String) -> Bool {
        places.contains { $0.preferenceKey == key }
    }

    private func name(for key: String) -> String {
        let node = key.hasPrefix("topic:") ? String(key.dropFirst("topic:".count)) : key
        if let topic = topics.first(where: { $0.key == key || $0.key == node }) { return topic.name }
        if let place = places.first(where: { $0.preferenceKey == key }) { return place.name }
        return node.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? node
    }
}
