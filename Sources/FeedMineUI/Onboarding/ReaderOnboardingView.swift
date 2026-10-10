//
// File: ReaderOnboardingView.swift
// Module: FeedMineUI
//
// Responsibility:
// V1's onboarding, which is **two stages**: Welcome, then the Composer. Layout, copy, controls and the
// transition are V1's (`Views/CuratedOnboardingView.swift`, `Onboarding/WelcomeScene.swift`,
// `Onboarding/FeedComposerScene.swift`); the recipe and the save belong to the host.
//
// Two deliberate differences, recorded in docs/v1-study/PORT_LOG.md:
// - V1's duel scenes (`StoryDuelScene`, `OnboardingSession`, `OnboardingSeed`) are dead code there — no
//   production caller — so they are **not** ported. The live flow is Welcome → Composer.
// - The Composer's preview shows the reader's **own** published cards ranked by the recipe the host resolves
//   (`previewCards`), so no headline and no image is invented while the reader shapes the feed.
import SwiftUI
import FeedMineDomain
import FeedMineRuntime

public struct ReaderOnboardingView: View {
    public enum Stage: Hashable, Sendable { case welcome, composer }

    @State private var stage: Stage
    @State private var recipe: FeedRecipeDefinition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// V1's deep navy. The scene is the one surface the app paints itself, so the palette is stated here.
    public static let welcomeBackground = Color(red: 5 / 255, green: 10 / 255, blue: 24 / 255)

    private let previewCards: [PresentationCard]
    private let topics: [OnboardingTopic]
    private let languages: [OnboardingLanguage]
    private let isSaving: Bool
    private let deviceLanguage: String
    private let onSave: (FeedRecipeDefinition, String, Bool) -> Void
    private let onClose: () -> Void

    /// `isFirstRun` starts at the welcome stage, as V1's gate did; a re-entry from the settings goes straight to
    /// the Composer, which is the stage that has something to change.
    public init(recipe: FeedRecipeDefinition = .neutral(), isFirstRun: Bool = true,
        previewCards: [PresentationCard] = [], topics: [OnboardingTopic] = [],
        languages: [OnboardingLanguage] = [], isSaving: Bool = false, deviceLanguage: String = "en",
        onSave: @escaping (FeedRecipeDefinition, String, Bool) -> Void, onClose: @escaping () -> Void) {
        _stage = State(initialValue: isFirstRun ? .welcome : .composer)
        _recipe = State(initialValue: recipe)
        self.previewCards = previewCards
        self.topics = topics
        self.languages = languages
        self.isSaving = isSaving
        self.deviceLanguage = deviceLanguage
        self.onSave = onSave
        self.onClose = onClose
    }

    public var body: some View {
        ZStack {
            (stage == .welcome ? Self.welcomeBackground : Color.clear).ignoresSafeArea()
            switch stage {
            case .welcome: welcome
            case .composer: composer
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.7), value: stage)
        // The gate's own identifier stays on the gate: a plain identifier on the container would override
        // every identifier inside it (the same rule the reader's search bar documents), which left the
        // Welcome and Composer controls unreachable. `.contain` keeps them elements of their own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding")
    }

    // MARK: - Stage 1: Welcome (V1's WelcomeScene)

    private var welcome: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                closeButton
            }
            .padding(.horizontal, FeedDesignTokens.Spacing.page)
            .padding(.top, FeedDesignTokens.Spacing.page)

            cardCascade
                .frame(maxHeight: 260)
                .clipped()
                .opacity(0.55)

            VStack(spacing: FeedDesignTokens.Spacing.deck) {
                headline
                Text(verbatim: String(localized: "O Feedmine reúne publicações independentes, podcasts, canais de vídeo e fontes públicas. Monte a mistura você mesmo — ou comece amplo e explore."))
                    .font(FeedDesignTokens.Typography.body)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, FeedDesignTokens.Spacing.deck)
                    .accessibilityIdentifier("welcome-body")
                trustBadges
                actions
            }
            .padding(.top, FeedDesignTokens.Spacing.deck)
            Spacer(minLength: FeedDesignTokens.Spacing.page)
        }
    }

    /// V1's cascade: the reader's own cards when there are any, and abstract panels when there are not — never a
    /// fabricated headline.
    private var cardCascade: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * 0.62
            ZStack {
                if previewCards.isEmpty {
                    ForEach(0..<6, id: \.self) { index in
                        RoundedRectangle(cornerRadius: FeedDesignTokens.Radius.card, style: .continuous)
                            .fill(.white.opacity(0.06))
                            .frame(width: width, height: 76)
                            .offset(x: CGFloat(index % 2 == 0 ? -18 : 18), y: CGFloat(index) * 34 - 90)
                    }
                } else {
                    ForEach(Array(previewCards.prefix(6).enumerated()), id: \.offset) { index, card in
                        FeedItemView(card: card, appearance: .standard, isBookmarked: false,
                            availableActions: [], onAction: { _ in })
                            .frame(width: width)
                            .offset(x: CGFloat(index % 2 == 0 ? -18 : 18), y: CGFloat(index) * 34 - 90)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var headline: some View {
        Text(verbatim: "")
            .font(FeedDesignTokens.Typography.pageTitle)
            .accessibilityIdentifier("welcome-headline")
            .accessibilityLabel(Text(verbatim: Self.welcomeHeadline))
            .overlay {
                // V1 tints the last word with the accent colour; the words themselves are its own.
                (Text("The open web,\narranged by ") + Text("you").foregroundColor(.accentColor) + Text("."))
                    .font(FeedDesignTokens.Typography.pageTitle)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
    }

    static let welcomeHeadline = "The open web, arranged by you."

    private var trustBadges: some View {
        HStack(spacing: FeedDesignTokens.Spacing.deck) {
            ForEach([String(localized: "No aparelho"), String(localized: "Sem conta"),
                String(localized: "Editável")], id: \.self) { badge in
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.shield.fill").font(.caption2)
                    Text(verbatim: badge).font(.caption2)
                }
                .foregroundStyle(.white.opacity(0.7))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("welcome-trust")
    }

    private var actions: some View {
        VStack(spacing: FeedDesignTokens.Spacing.tight) {
            Button {
                stage = .composer
            } label: {
                Text(verbatim: String(localized: "Montar meu feed"))
                    .font(.body.weight(.medium))
                    .frame(maxWidth: 260)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("welcome-shape")
            Button {
                onSave(.neutral(languages: [deviceLanguage]), autoName(for: .neutral(languages: [deviceLanguage])),
                    true)
            } label: {
                Text(verbatim: String(localized: "Começar amplo")).font(.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.8))
            .disabled(isSaving)
            .accessibilityIdentifier("welcome-broad")
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.body.weight(.light))
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding-close")
        .accessibilityLabel(Text(verbatim: String(localized: "Fechar")))
    }

    // MARK: - Stage 2: the Composer (V1's FeedComposerScene)

    private var composer: some View {
        // V1 pinned the footer as a *sibling* of the sheet's scroll view (`FeedComposerScene.editorialSheet`),
        // which is what keeps the last rows reachable. An inset drawn over the same scroll view left the media
        // toggles under the footer's own buttons (measured: a tap on the podcast switch hit "Abrir meu feed").
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: FeedDesignTokens.Spacing.deck) {
                    HStack {
                        Spacer()
                        closeButton
                    }
                    previewZone
                    Text(verbatim: String(localized: "Monte seu primeiro feed"))
                        .font(FeedDesignTokens.Typography.pageTitle)
                    Text(verbatim: String(localized: "Opcional. Mude tudo depois."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("composer-subtitle")
                    languageControl
                    discoveryControl
                    balanceControl
                    topicControl
                    mediaControl
                }
                .padding(FeedDesignTokens.Spacing.page)
            }
            .background(Color.clear)
            composerFooter
        }
    }

    @ViewBuilder private var previewZone: some View {
        VStack(alignment: .leading, spacing: FeedDesignTokens.Spacing.tight) {
            if previewCards.isEmpty {
                HStack(spacing: FeedDesignTokens.Spacing.tight) {
                    ForEach(0..<2, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: FeedDesignTokens.Radius.card, style: .continuous)
                            .fill(.quaternary)
                            .frame(height: 120)
                    }
                }
                .accessibilityIdentifier("composer-preview-skeleton")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: FeedDesignTokens.Spacing.tight) {
                        ForEach(Array(previewCards.prefix(3).enumerated()), id: \.offset) { _, card in
                            FeedItemView(card: card, appearance: .standard, isBookmarked: false,
                                availableActions: [], onAction: { _ in })
                                .frame(width: 260)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .accessibilityIdentifier("composer-preview")
            }
        }
    }

    private var languageControl: some View {
        OnboardingSection(title: String(localized: "Idiomas")) {
            let available = languages.isEmpty
                ? recipe.languages.map { OnboardingLanguage(code: $0, name: $0) }
                : languages
            FlowRow(items: available) { language in
                let isOn = recipe.languages.contains(language.code)
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
                .accessibilityIdentifier("composer-language-\(language.code)")
            }
        }
    }

    private var discoveryControl: some View {
        OnboardingSection(title: String(localized: "Descoberta")) {
            VStack(alignment: .leading, spacing: 4) {
                Slider(value: Binding(get: { recipe.discoveryLevel },
                    set: { value in var next = recipe; next.discoveryLevel = value; recipe = next }), in: 0...1)
                    .accessibilityIdentifier("composer-discovery")
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
            .accessibilityIdentifier("composer-balance-\(key)")
        }
        .padding(.vertical, 6)
    }

    private var topicControl: some View {
        OnboardingSection(title: String(localized: "Tópicos")) {
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
                        .accessibilityIdentifier("composer-topic-\(topic.key)")
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
                    .accessibilityIdentifier("composer-media-\(kind.rawValue)")
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var composerFooter: some View {
        HStack(spacing: FeedDesignTokens.Spacing.tight) {
            Button(String(localized: "Reiniciar")) { recipe = .neutral(languages: [deviceLanguage]) }
                .accessibilityIdentifier("composer-reset")
            Spacer()
            Button(String(localized: "Começar amplo")) {
                let broad = FeedRecipeDefinition.neutral(languages: [deviceLanguage])
                onSave(broad, autoName(for: broad), true)
            }
            .accessibilityIdentifier("composer-start-broad")
            Spacer()
            Button {
                onSave(recipe, autoName(for: recipe), false)
            } label: {
                Text(verbatim: String(localized: "Abrir meu feed")).font(.body.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving || recipe.mediaTypes.isEmpty)
            .accessibilityIdentifier("composer-open-feed")
        }
        .padding(FeedDesignTokens.Spacing.page)
        .background(.ultraThinMaterial)
    }

    // MARK: - Pieces

    private func chip(_ title: String, isOn: Bool) -> some View {
        Text(verbatim: title)
            .font(.caption)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(isOn ? Color.accentColor.opacity(0.18) : Color.clear, in: Capsule())
            .overlay(Capsule().stroke(isOn ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 1))
            .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
    }

    private func chipBackground(_ level: ReaderPreferenceLevel) -> Color {
        switch level {
        case .more: return .accentColor
        case .neutral: return .clear
        case .less: return .clear
        }
    }

    /// V1's `autoName()`: the feed is named by what the reader asked for more of.
    func autoName(for recipe: FeedRecipeDefinition) -> String {
        let names = Dictionary(uniqueKeysWithValues: topics.map { ($0.key, $0.name) })
        return FeedRecipeNaming.suggestedName(for: recipe, names: names)
    }
}

/// One titled block of the Composer's sheet.
struct OnboardingSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: FeedDesignTokens.Spacing.tight) {
            Text(verbatim: title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
    }
}

/// A wrapping row of chips, so a language list never overflows sideways.
struct FlowRow<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading,
            spacing: 8) {
            ForEach(items) { item in content(item) }
        }
    }
}

/// A language the Composer can offer, as a value the host supplies from the catalogue.
public struct OnboardingLanguage: Hashable, Sendable, Identifiable {
    public let code: String
    public let name: String
    public init(code: String, name: String) { self.code = code; self.name = name }
    public var id: String { code }
}

/// A topic the Composer can offer, keyed by the catalogue's own node key.
public struct OnboardingTopic: Hashable, Sendable, Identifiable {
    public let key: String
    public let name: String
    public init(key: String, name: String) { self.key = key; self.name = name }
    public var id: String { key }
}
