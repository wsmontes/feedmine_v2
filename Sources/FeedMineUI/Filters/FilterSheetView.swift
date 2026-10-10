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
    public let code: String
    public let name: String
    public let enabledSources: Int
    public let isSelected: Bool
    /// V1's `LanguageInfo` carried a flag emoji from its own table; the catalog has only codes, and a
    /// two-letter *language* code is not a country (EN is not a country), so the sheet shows no flag
    /// instead of a wrong one.
    public init(code: String, name: String, enabledSources: Int, isSelected: Bool) {
        self.code = code; self.name = name
        self.enabledSources = enabledSources; self.isSelected = isSelected
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
}

public struct FilterSheetView: View {
    @State private var store: ReaderFilterStore
    private let languages: [CatalogLanguageSummary]
    private let presets: [FilterPresetRow]
    private let appearance: ReaderAppearance
    private let onShowCountries: () -> Void
    private let onShowTopics: () -> Void
    private let onDone: () -> Void

    public init(store: ReaderFilterStore, languages: [CatalogLanguageSummary] = [],
        presets: [FilterPresetRow] = FilterSheetView.defaultPresets, appearance: ReaderAppearance = .standard,
        onShowCountries: @escaping () -> Void = {}, onShowTopics: @escaping () -> Void = {},
        onDone: @escaping () -> Void = {}) {
        _store = State(initialValue: store)
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
                            store.select(preset: row.preset)
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
                            Button {
                                store.toggleLanguage(row.code)
                            } label: {
                                HStack {
                                    Text(verbatim: row.name).foregroundStyle(.primary)
                                    Spacer(minLength: 0)
                                    if row.isSelected {
                                        Image(systemName: "checkmark").foregroundStyle(appearance.accent)
                                    }
                                    Text(verbatim: "\(row.enabledSources) on")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("language-\(row.code)")
                            .accessibilityValue(row.isSelected ? "selected" : "not selected")
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
                Button(String(localized: "Concluído"), action: onDone)
                    .accessibilityIdentifier("filter-done")
            }
        }
    }

    /// Languages as the sheet shows them: declared ones by size, the undeclared bucket last.
    public var languageRows: [FilterLanguageRow] {
        FilterSheetView.languageRows(languages, selected: Set(store.draft.languages))
    }

    public static func languageRows(_ languages: [CatalogLanguageSummary],
        selected: Set<String>) -> [FilterLanguageRow] {
        languages.map { language in
            FilterLanguageRow(code: language.code, name: language.displayName,
                enabledSources: language.enabledSources, isSelected: selected.contains(language.code))
        }
    }

    private func checkRow(_ title: String, icon: String, isSelected: Bool) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer(minLength: 0)
            if isSelected { Image(systemName: "checkmark").foregroundStyle(appearance.accent) }
        }
    }

}
