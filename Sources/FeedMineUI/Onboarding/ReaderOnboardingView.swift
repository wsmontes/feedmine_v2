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
    /// The recipe the host handed in — the reader's own answers from a previous pass, or the first run's
    /// suggested languages. "Reiniciar" and the broad entry go back to it; resetting to an empty recipe instead
    /// would throw away the suggestion and leave discovery with no profile at all.
    private let initialRecipe: FeedRecipeDefinition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// V1's deep navy. The scene is the one surface the app paints itself, so the palette is stated here.
    public static let welcomeBackground = Color(red: 5 / 255, green: 10 / 255, blue: 24 / 255)

    private let previewCards: [PresentationCard]
    private let topics: [OnboardingTopic]
    /// The regions the reader can name: discovery's own promise is that the open internet is chosen by interest,
    /// and a region is one of those interests (B01 of the acceptance benchmark asks for exactly this choice).
    private let regions: [OnboardingRegion]
    private let languages: [OnboardingLanguage]
    private let isSaving: Bool
    /// The reader's own file, imported at first contact. The file picker belongs to the host (`SourceManagementView`
    /// reports the same intent the same way: a `Button` that calls a closure), and so does the preview and the
    /// commit — this scene never reads a file and never writes one.
    private let onImport: () -> Void
    private let onSave: (FeedRecipeDefinition) -> Void
    private let onClose: () -> Void
    /// The prominent footer action's label. The first run opens the feed ("Abrir meu feed"); the curated
    /// composer saves a preset without moving the reading, so its host names the action for what it does.
    private let primaryTitle: String

    /// `isFirstRun` starts at the welcome stage, as V1's gate did; a re-entry from the settings goes straight to
    /// the Composer, which is the stage that has something to change.
    public init(recipe: FeedRecipeDefinition = .neutral(), isFirstRun: Bool = true,
        previewCards: [PresentationCard] = [], topics: [OnboardingTopic] = [], regions: [OnboardingRegion] = [],
        languages: [OnboardingLanguage] = [], isSaving: Bool = false,
        primaryTitle: String? = nil,
        onImport: @escaping () -> Void = {}, onSave: @escaping (FeedRecipeDefinition) -> Void,
        onClose: @escaping () -> Void) {
        _stage = State(initialValue: isFirstRun ? .welcome : .composer)
        _recipe = State(initialValue: recipe)
        self.initialRecipe = recipe
        self.previewCards = previewCards
        self.topics = topics
        self.regions = regions
        self.languages = languages
        self.isSaving = isSaving
        self.primaryTitle = primaryTitle ?? String(localized: "Abrir meu feed")
        self.onImport = onImport
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

    /// V1 tints the last word with the accent colour; the words themselves are its own.
    ///
    /// The sentence **is** the element, drawn where the reader reads it. It used to be an `.overlay` of an empty
    /// `Text(verbatim: "")`: measured (`docs/reviews/2026-10-11-round9-language-choice-and-localization.md` §8,
    /// PO-classified P1), that placeholder has no size of its own, so the app's own headline painted nothing — the
    /// element VoiceOver could reach (`welcome-headline`) carried words no reader could see, in a box with no area.
    private var headline: some View {
        (Text(String(localized: "The open web,\narranged by "))
            + Text(String(localized: "you")).foregroundColor(.accentColor)
            + Text(verbatim: "."))
            .font(FeedDesignTokens.Typography.pageTitle)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .accessibilityIdentifier("welcome-headline")
            .accessibilityLabel(Text(verbatim: Self.welcomeHeadline))
    }

    static let welcomeHeadline = String(localized: "The open web, arranged by you.")

    private var trustBadges: some View {
        HStack(spacing: FeedDesignTokens.Spacing.deck) {
            ForEach([String(localized: "No aparelho"), String(localized: "Sem conta"),
                String(localized: "Editável")], id: \.self) { badge in
                HStack(spacing: 4) {
                    // Decoration: the badge is its own words.
                    Image(systemName: "checkmark.shield.fill").font(.caption2)
                        .accessibilityHidden(true)
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
                // Entering wide open **is** the skip: the language answer stays the one the host suggested
                // (F02 §2.1), never an empty set — an empty profile is what discovery reads as "nothing to look
                // for", and the feed would open on the selection surface. Places stay unnamed, which acquisition
                // already reads as every place.
                onSave(initialRecipe)
            } label: {
                Text(verbatim: String(localized: "Começar amplo")).font(.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.8))
            .disabled(isSaving)
            .accessibilityIdentifier("welcome-broad")
            // F18 R1: the reader who already has a file of sources can bring it now, and the gate keeps its own
            // two ways forward — importing is neither a step of the first run nor a condition for leaving it.
            // R7's naming: what this file carries is the reader's own sources, never a backup of the app's data.
            Button(action: onImport) {
                Text(verbatim: String(localized: "Importar OPML")).font(.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.8))
            .disabled(isSaving)
            .accessibilityIdentifier("welcome-import")
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
                    Text(verbatim: String(localized: "Escolha idiomas e lugares"))
                        .font(FeedDesignTokens.Typography.pageTitle)
                    Text(verbatim: String(localized: "Você entra no feed agora. Os assuntos, você responde dentro dele."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("composer-subtitle")
                    // The same control set the settings page shows, over the same recipe value — scoped here to
                    // the two answers the first run collects: the reader must not fill a form before discovering.
                    ReaderDiscoveryControls(recipe: $recipe, languages: languages, topics: topics,
                        places: regions, scope: .firstRun)
                }
                .padding(FeedDesignTokens.Spacing.page)
            }
            .background(Color.clear)
            composerFooter
        }
    }

    @ViewBuilder private var previewZone: some View {
        // Nothing is drawn before there is something real to show. The first run used to draw two grey blocks here
        // (the "retângulos cinza" the owner reported on 2026-10-11 and again on 2026-10-24): they held no content,
        // said nothing, and read as media that had failed. A preview either shows the reader's own published cards
        // or it does not exist.
        VStack(alignment: .leading, spacing: FeedDesignTokens.Spacing.tight) {
            if !previewCards.isEmpty {
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

    private var composerFooter: some View {
        HStack(spacing: FeedDesignTokens.Spacing.tight) {
            Button(String(localized: "Reiniciar")) { recipe = initialRecipe }
                .accessibilityIdentifier("composer-reset")
            Spacer()
            // Broad from the Composer: the language answers the reader sees stay (the suggestion, unless they
            // changed it), and the narrowing places are dropped — "Mundo todo" for places, as F02 §2.1 states.
            // Saving `.neutral()` here would discard the language suggestion and take discovery back to nothing.
            Button(String(localized: "Começar amplo")) {
                onSave(.neutral(languages: recipe.languages, hasLanguageAnswer: recipe.hasLanguageAnswer))
            }
            .accessibilityIdentifier("composer-start-broad")
            Spacer()
            Button {
                onSave(recipe)
            } label: {
                Text(verbatim: primaryTitle).font(.body.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving || recipe.mediaTypes.isEmpty)
            .accessibilityIdentifier("composer-open-feed")
        }
        .padding(FeedDesignTokens.Spacing.page)
        .background(.ultraThinMaterial)
    }

    // MARK: - Pieces

}

/// One titled block of the Composer's sheet.
struct OnboardingSection<Content: View>: View {
    let title: String
    /// A surface whose heading **is** the question names it, so a test reaches the question instead of the copy in
    /// whichever language the device is set to. Sections without one keep no identifier (unchanged tree).
    var identifier: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: FeedDesignTokens.Spacing.tight) {
            if let identifier {
                Text(verbatim: title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(identifier)
            } else {
                Text(verbatim: title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
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

/// A language the Composer can offer, as a value the host supplies from the catalogue. The catalogue declares
/// 257 codes and the reader chooses a language: the code here is the primary subtag, and the variants are what
/// the catalogue holds under it — information, never a second way to choose the same language.
public struct OnboardingLanguage: Hashable, Sendable, Identifiable {
    public let code: String
    /// The language's name in the interface language — never a code.
    public let name: String
    /// Every source the catalogue holds for this language: what "fontes disponíveis" counts.
    public let availableSources: Int
    /// The catalogue's own codes under this language, biggest first.
    public let variants: [OnboardingLanguageVariant]

    public init(code: String, name: String, availableSources: Int = 0,
        variants: [OnboardingLanguageVariant] = []) {
        self.code = code; self.name = name
        self.availableSources = availableSources; self.variants = variants
    }

    public var id: String { code }
    /// Whether naming the region adds something: a language declared once has nothing to expand.
    public var hasRegionVariants: Bool { variants.contains { $0.hasRegion } }

    /// The catalogue's own row for a code the catalogue named only once (a recipe's own answer).
    public init(recipeCode: String) {
        self.init(code: CatalogLanguageNaming.choiceCode(recipeCode),
            name: CatalogLanguageNaming.displayName(forLanguageCode: recipeCode))
    }
}

/// One regional variant of a language, as the expansion shows it. Informative: there is no control here.
public struct OnboardingLanguageVariant: Hashable, Sendable, Identifiable {
    public let code: String
    /// The language and its region, in the interface language.
    public let label: String
    public let availableSources: Int
    /// Whether this code names a region on top of the language.
    public let hasRegion: Bool

    public init(code: String, label: String, availableSources: Int, hasRegion: Bool) {
        self.code = code; self.label = label
        self.availableSources = availableSources; self.hasRegion = hasRegion
    }

    public var id: String { code }
}

/// A topic the Composer can offer, keyed by the catalogue's own node key.
/// One region the Composer can name, by the catalogue's own country node key.
public struct OnboardingRegion: Hashable, Sendable, Identifiable {
    public let key: String
    public let name: String

    public init(key: String, name: String) { self.key = key; self.name = name }

    public var id: String { key }
    /// The recipe's own vocabulary: a region is a topic preference on the country's placement.
    public var preferenceKey: String { "topic:\(key)" }
}

public struct OnboardingTopic: Hashable, Sendable, Identifiable {
    public let key: String
    public let name: String
    public init(key: String, name: String) { self.key = key; self.name = name }
    public var id: String { key }
}
