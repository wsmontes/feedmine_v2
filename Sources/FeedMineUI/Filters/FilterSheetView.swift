// File: FilterSheetView.swift
// Module: FeedMineUI
// Owns: V1's filter sheet — Clear All, the preset picker, content type, topics, language and mood — copied
//       from `Views/FilterSheetView.swift`.
// Does not own: applying (the sheet going away *is* the apply, V1's `onDisappear`), the catalog (values come
// in), or navigation to the country/topic screens (the host presents them).
//
// Honesty rule (T6): a section whose criterion this build cannot enforce is **not drawn**, instead of being
// offered and then ignored — `ReaderFilterDraft.availableCriteria` decides.

import SwiftUI
import FeedMineDomain
import FeedMineRuntime

/// One language row of the sheet.
public struct FilterLanguageRow: Hashable, Sendable, Identifiable {
    /// The primary subtag: the choice itself, and what the filter persists. The catalogue declares 257 codes and
    /// a reader chooses a language — the variants are what it holds under it.
    public let code: String
    public let name: String
    /// Every source the catalogue holds under this language: the one number a row shows.
    public let availableSources: Int
    public let isSelected: Bool
    /// The catalogue's own codes under this language, biggest first. Information, never a second choice.
    public let variants: [FilterLanguageVariant]
    /// V1's `LanguageInfo` carried a flag emoji from its own table; the catalog has only codes, and a
    /// two-letter *language* code is not a country (EN is not a country), so the sheet shows no flag
    /// instead of a wrong one.
    public init(code: String, name: String, availableSources: Int, isSelected: Bool,
        variants: [FilterLanguageVariant] = []) {
        self.code = code; self.name = name
        self.availableSources = availableSources; self.isSelected = isSelected
        self.variants = variants
    }

    public var id: String { code }
    /// Whether the expansion has something to say: a language the catalogue declares once has no regions.
    public var hasVariants: Bool { variants.contains { $0.hasRegion } }
    /// "26.012 fontes disponíveis" — the count every surface states the same way.
    public var totalLabel: String { CatalogLanguageNaming.availableSourcesLabel(availableSources) }
}

/// One regional variant of a language, as the expansion shows it.
public struct FilterLanguageVariant: Hashable, Sendable, Identifiable {
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

/// The preset the reader can choose, with the label the sheet shows. T8 supplies the named ones.
public struct FilterPresetRow: Hashable, Sendable, Identifiable {
    public let id: String
    public let preset: ReaderPresetID
    public let name: String
    public let systemImage: String
    public let isSelected: Bool
    /// T8: a *saved* preset carries the whole identity it activates (terms, filters, scope), because selecting
    /// it is not editing a criterion — it is moving to the context the reader stored. Nil for V1's two plain
    /// entries, which are the draft's own preset and are applied with Concluído like every other criterion.
    public let key: ContextKey?

    public init(id: String, preset: ReaderPresetID, name: String, systemImage: String, isSelected: Bool,
        key: ContextKey? = nil) {
        self.id = id; self.preset = preset; self.name = name; self.systemImage = systemImage
        self.isSelected = isSelected; self.key = key
    }
}

public struct FilterSheetView: View {
    @State private var store: ReaderFilterStore
    /// Which languages are showing their regional variants. One set, because the sheet is a list, not a menu.
    @State private var expandedLanguages: Set<String> = []
    /// What the last apply told the reader, when it failed. The two failures say opposite things, so the sheet
    /// shows the failure's own sentence instead of one generic "could not apply".
    @State private var applyFailure: String?
    private let languages: [CatalogLanguageGroup]
    private let presets: [FilterPresetRow]
    private let appearance: ReaderAppearance
    /// T8: a saved preset's selection is an activation, not a draft change.
    private let onActivate: @MainActor (ContextKey) async throws -> Void
    private let onShowCountries: () -> Void
    private let onShowTopics: () -> Void
    private let onDone: () -> Void

    /// Builds the draft store from values, so the host never mutates state while rendering to open the sheet.
    /// `onApply` is the host's persist-and-activate step; the sheet closes only after it returns.
    public init(applying filter: ReaderFilter, preset: ReaderPresetID,
        availableCriteria: Set<ReaderFilterCriterion>, languages: [CatalogLanguageGroup] = [],
        presets: [FilterPresetRow] = FilterSheetView.defaultPresets, appearance: ReaderAppearance = .standard,
        onApply: @escaping @MainActor (ReaderFilter, ReaderPresetID) async throws -> Void,
        onActivate: @escaping @MainActor (ContextKey) async throws -> Void = { _ in },
        onShowCountries: @escaping () -> Void = {}, onShowTopics: @escaping () -> Void = {},
        onDone: @escaping () -> Void = {}) {
        _store = State(initialValue: ReaderFilterStore(applying: filter, preset: preset,
            availableCriteria: availableCriteria, onApply: onApply))
        self.onActivate = onActivate
        self.languages = languages
        self.presets = presets
        self.appearance = appearance
        self.onShowCountries = onShowCountries
        self.onShowTopics = onShowTopics
        self.onDone = onDone
    }

    public init(store: ReaderFilterStore, languages: [CatalogLanguageGroup] = [],
        presets: [FilterPresetRow] = FilterSheetView.defaultPresets, appearance: ReaderAppearance = .standard,
        onActivate: @escaping @MainActor (ContextKey) async throws -> Void = { _ in },
        onShowCountries: @escaping () -> Void = {}, onShowTopics: @escaping () -> Void = {},
        onDone: @escaping () -> Void = {}) {
        _store = State(initialValue: store)
        self.onActivate = onActivate
        self.languages = languages
        self.presets = presets
        self.appearance = appearance
        self.onShowCountries = onShowCountries
        self.onShowTopics = onShowTopics
        self.onDone = onDone
    }

    /// V1's two always-available entries; named presets (collections, smart bookmarks, curated feeds) arrive
    /// with T8 and are offered by the host.
    public static let defaultPresets: [FilterPresetRow] = [
        .init(id: "everything", preset: .everything, name: String(localized: "Tudo"),
            systemImage: "circle.grid.3x3.fill", isSelected: true),
        .init(id: "lastClicked", preset: .lastClicked, name: String(localized: "Último aberto"),
            systemImage: "clock.arrow.circlepath", isSelected: false)
    ]

    public var body: some View {
        List {
            Section {
                Button(role: .destructive) {
                    store.clearAll()
                } label: {
                    Label(String(localized: "Limpar todos os filtros"), systemImage: "xmark.circle")
                }
                .accessibilityIdentifier("filter-clear-all")
                .disabled(!store.isDirty && store.draft.applied.isUnrestricted)
            }

            if store.draft.availableCriteria.contains(.preset), !presets.isEmpty {
                Section(String(localized: "Feeds")) {
                    ForEach(presets) { row in
                        Button {
                            // A saved preset carries its whole identity: choosing it moves the reader there.
                            if let key = row.key {
                                Task {
                                    do {
                                        try await onActivate(key)
                                        onDone()
                                    } catch let failure as ReaderFilterFailure {
                                        applyFailure = failure.readerMessage
                                    } catch {
                                        applyFailure = String(localized: "Não foi possível abrir este feed. Tente novamente.")
                                    }
                                }
                            } else {
                                store.select(preset: row.preset)
                            }
                        } label: {
                            HStack {
                                Label(row.name, systemImage: row.systemImage)
                                Spacer(minLength: 0)
                                if row.preset == store.draft.preset {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(appearance.accent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("preset-option-\(row.id)")
                        .accessibilityValue(row.preset == store.draft.preset ? "selected" : "not selected")
                    }
                    Button(action: onShowCountries) {
                        HStack {
                            Label(String(localized: "Países"), systemImage: "globe")
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        // The row's whole width is the control. Without this, only the label's glyphs are
                        // hit-testable and a tap at the row's centre lands in the Spacer and does nothing.
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("countries-link")
                }
            }

            if store.draft.availableCriteria.contains(.contentType) {
                Section(String(localized: "Tipo de conteúdo")) {
                    ForEach(ReaderContentType.allCases, id: \.rawValue) { type in
                        Button {
                            store.select(contentType: type)
                        } label: { checkRow(type.rawValue, icon: type.icon,
                            isSelected: store.draft.contentType == type) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("content-type-\(type.rawValue.lowercased())")
                            .accessibilityValue(store.draft.contentType == type ? "selected" : "not selected")
                    }
                }
            }

            if store.draft.availableCriteria.contains(.taxonomy) {
                Section(String(localized: "Tópicos")) {
                    Button(action: onShowTopics) {
                        HStack {
                            Label(String(localized: "Navegar por tópicos"), systemImage: "list.bullet.rectangle")
                            Spacer(minLength: 0)
                            if !store.draft.taxonomyNodeIDs.isEmpty {
                                Text(verbatim: "\(store.draft.taxonomyNodeIDs.count)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("browse-topics")
                    .accessibilityValue("\(store.draft.taxonomyNodeIDs.count)")
                }
            }

            if store.draft.availableCriteria.contains(.languages) {
                Section(String(localized: "Idioma")) {
                    if languageRows.isEmpty {
                        Text(String(localized: "Sem dados de idioma disponíveis"))
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        ForEach(languageRows) { row in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Button {
                                        store.toggleLanguage(row.code)
                                    } label: {
                                        HStack {
                                            Text(verbatim: row.name).foregroundStyle(.primary)
                                            Spacer(minLength: 0)
                                            if row.isSelected {
                                                Image(systemName: "checkmark").foregroundStyle(appearance.accent)
                                            }
                                            Text(verbatim: row.totalLabel)
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        // A plain button in a List only hits its label's drawn area; the row itself
                                        // must be the target, including the spacer.
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("language-\(row.code)")
                                    .accessibilityValue(row.isSelected ? "selected" : "not selected")
                                    if row.hasVariants {
                                        Button {
                                            if expandedLanguages.contains(row.code) {
                                                expandedLanguages.remove(row.code)
                                            } else {
                                                expandedLanguages.insert(row.code)
                                            }
                                        } label: {
                                            Image(systemName: expandedLanguages.contains(row.code)
                                                ? "chevron.down" : "chevron.right")
                                                .font(.caption2).foregroundStyle(.tertiary)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("language-regions-\(row.code)")
                                        .accessibilityLabel(Text(verbatim: String(localized: "Regiões de \(row.name)")))
                                    }
                                }
                                if expandedLanguages.contains(row.code) { variants(of: row) }
                            }
                        }
                    }
                }
            }

            if store.draft.availableCriteria.contains(.mood) {
                Section(String(localized: "Humor")) {
                    ForEach(ReaderMood.allCases, id: \.rawValue) { mood in
                        Button {
                            store.select(mood: mood)
                        } label: { checkRow(mood.rawValue, icon: mood.icon, isSelected: store.draft.mood == mood) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("mood-\(mood.rawValue.lowercased())")
                            .accessibilityValue(store.draft.mood == mood ? "selected" : "not selected")
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
        .background(appearance.pageBackground)
        .navigationTitle(String(localized: "Filtros"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: ReaderToolbarPlacement.trailing) {
                // V1: the sheet going away is the apply. The host's `onApply` persists the identity and
                // activates its context; the sheet closes only after that succeeded, and a failure keeps the
                // draft (and the sheet) so the reader can retry — with the failure's own sentence on screen.
                Button {
                    guard !store.isApplying else { return }
                    Task {
                        do {
                            let applied = try await store.apply()
                            // A duplicate tap that found the first apply in flight must not close the sheet.
                            if applied || !store.isDirty { onDone() }
                        } catch let failure as ReaderFilterFailure {
                            applyFailure = failure.readerMessage
                        } catch {
                            applyFailure = String(localized: "Não foi possível salvar o filtro. Tente novamente.")
                        }
                    }
                } label: {
                    if store.isApplying {
                        ProgressView()
                    } else {
                        Text(verbatim: String(localized: "Concluído"))
                    }
                }
                .disabled(store.isApplying)
                .accessibilityIdentifier("filter-done")
            }
        }
        .alert(String(localized: "Filtro"), isPresented: Binding(
            get: { applyFailure != nil }, set: { if !$0 { applyFailure = nil } })) {
            Button("OK") { applyFailure = nil }
        } message: {
            Text(applyFailure ?? "")
        }
    }

    /// Languages as the sheet shows them: one row per language, the catalogue's order kept, the undeclared
    /// bucket last.
    public var languageRows: [FilterLanguageRow] {
        FilterSheetView.languageRows(languages, selected: Set(store.draft.languages))
    }

    public static func languageRows(_ languages: [CatalogLanguageGroup],
        selected: Set<String>) -> [FilterLanguageRow] {
        // A filter stored before the choice became the language itself can hold a regional code (`pt-BR`). It is
        // the same language, and showing the row as unselected would say the filter is unset while it filters.
        func isSelected(_ language: CatalogLanguageGroup) -> Bool {
            selected.contains(language.languageCode)
                || selected.contains { CatalogLanguageNaming.choiceCode($0) == language.languageCode }
        }
        return languages.map { language in
            // A language the catalogue declares once has nothing to expand unless that one code names a region.
            let expands = language.variants.count > 1 || language.hasRegionVariants
            return FilterLanguageRow(code: language.languageCode, name: language.displayName,
                availableSources: language.availableSources, isSelected: isSelected(language),
                variants: expands ? language.variants.map {
                    FilterLanguageVariant(code: $0.code, label: $0.variantLabel,
                        availableSources: $0.totalSources, hasRegion: $0.hasRegion)
                } : [])
        }
    }

    /// What the catalogue holds under the language: the regions its sources are declared in, named and counted.
    /// There is no control here — choosing a region is a different feature from choosing a language.
    @ViewBuilder private func variants(of row: FilterLanguageRow) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(row.variants) { variant in
                HStack(spacing: 8) {
                    Text(verbatim: variant.hasRegion
                        ? variant.label : String(localized: "Região não especificada"))
                        .font(.caption2).foregroundStyle(.secondary)
                        .accessibilityIdentifier("language-variant-\(variant.code)")
                    Spacer(minLength: 0)
                    Text(verbatim: CatalogLanguageNaming.numberLabel(variant.availableSources))
                        .font(.caption2).foregroundStyle(.tertiary)
                        .accessibilityIdentifier("language-variant-count-\(variant.code)")
                }
            }
        }
        .padding(.leading, 4)
    }

    private func checkRow(_ title: String, icon: String, isSelected: Bool) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer(minLength: 0)
            if isSelected { Image(systemName: "checkmark").foregroundStyle(appearance.accent) }
        }
        .contentShape(Rectangle())
    }

}
