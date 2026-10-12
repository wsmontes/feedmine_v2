//
// File: ReaderContentFilterView.swift
// Module: FeedMineUI
//
// Responsibility:
// V1's content-filter surface (`Views/ContentFilterView.swift`): the master switch, the templates the reader
// turns on, the words they add themselves, and the words they remove. What a rule hides is stated in the
// footer, because a filter that hides nothing must not look like one that does.
//
// The surface edits the reader's **preferences** — the gate, the templates and the custom words — and never the
// lens: V1's content filters were global and never expired, and so are V2's. Turning the master switch off masks
// the rules instead of deleting them, and the footer says so.
//
// Does not own: storing anything (the backend does), the templates' words (the composition resolves V1's own
// catalogue), or applying a rule (Editorial).
import Foundation
import Observation
import SwiftUI
import FeedMineDomain

/// One template as the surface draws it.
public struct ReaderContentFilterTemplateRow: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// How many words turning it on adds.
    public let ruleCount: Int

    public init(id: String, name: String, ruleCount: Int) {
        self.id = id; self.name = name; self.ruleCount = ruleCount
    }
}

/// One rule the reader wrote themselves.
public struct ReaderContentFilterRuleRow: Hashable, Sendable, Identifiable {
    public let id: String
    public let words: [String]

    public init(id: String, words: [String]) { self.id = id; self.words = words }
}

/// The operations the surface needs. The composition implements it; the view never touches storage.
public protocol ReaderContentFilterBackend: Sendable {
    /// The master switch and the reader's own words, plus the templates this build carries.
    func state() async throws -> ReaderContentFilterState
    func setEnabled(_ enabled: Bool) async throws
    /// The reader's own words. Template keywords are not part of them: turning a template off takes exactly the
    /// words it added, and leaves what the reader typed where they left it.
    func setRules(_ words: [String]) async throws
    func setTemplates(_ keys: [String]) async throws
}

/// What the surface draws and edits, as one value.
public struct ReaderContentFilterState: Hashable, Sendable {
    public let isEnabled: Bool
    public let rules: [String]
    public let enabledTemplates: [String]
    public let templates: [ReaderContentFilterTemplateRow]

    public init(isEnabled: Bool, rules: [String], enabledTemplates: [String],
        templates: [ReaderContentFilterTemplateRow]) {
        self.isEnabled = isEnabled; self.rules = rules
        self.enabledTemplates = enabledTemplates; self.templates = templates
    }
}

@MainActor
@Observable
public final class ReaderContentFilterStore {
    public private(set) var isEnabled = false
    public private(set) var rules: [String] = []
    public private(set) var enabledTemplates: Set<String> = []
    public private(set) var templates: [ReaderContentFilterTemplateRow] = []
    public private(set) var errorMessage: String?

    @ObservationIgnored private let backend: any ReaderContentFilterBackend

    public init(backend: any ReaderContentFilterBackend) { self.backend = backend }

    /// How a rule reads: one line of words, as V1's row carried (`Name` — its keywords).
    public var ruleRows: [ReaderContentFilterRuleRow] {
        rules.map { ReaderContentFilterRuleRow(id: $0, words: $0.split(separator: " ").map(String.init)) }
    }

    public func load() async {
        do {
            let state = try await backend.state()
            isEnabled = state.isEnabled
            rules = state.rules
            enabledTemplates = Set(state.enabledTemplates)
            templates = state.templates
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Não foi possível ler os filtros de conteúdo.")
        }
    }

    public func setEnabled(_ enabled: Bool) async {
        isEnabled = enabled
        do { try await backend.setEnabled(enabled); errorMessage = nil }
        catch { await refresh(after: String(localized: "Não foi possível salvar o filtro de conteúdo.")) }
    }

    public func isTemplateEnabled(_ key: String) -> Bool { enabledTemplates.contains(key) }

    public func toggleTemplate(_ key: String) async {
        var next = enabledTemplates
        if next.contains(key) { next.remove(key) } else { next.insert(key) }
        enabledTemplates = next
        do { try await backend.setTemplates(next.sorted()); errorMessage = nil }
        catch { await refresh(after: String(localized: "Não foi possível salvar o filtro de conteúdo.")) }
    }

    /// Adds the words the reader typed. Commas and newlines separate them, as V1 split them; an empty entry or
    /// one that is already there changes nothing.
    @discardableResult
    public func addRules(_ text: String) async -> Bool {
        let words = ReaderContentExclusions.normalize(text.split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" })
            .map(String.init))
        guard !words.isEmpty else { return false }
        return await setRules(ReaderContentExclusions.normalize(rules + words))
    }

    @discardableResult
    public func removeRule(_ id: String) async -> Bool {
        await setRules(rules.filter { $0 != id })
    }

    private func setRules(_ words: [String]) async -> Bool {
        guard words != rules else { return false }
        let previous = rules
        rules = words
        do { try await backend.setRules(words); errorMessage = nil; return true }
        catch {
            rules = previous
            await refresh(after: String(localized: "Não foi possível salvar o filtro de conteúdo."))
            return false
        }
    }

    private func refresh(after message: String) async {
        let previous = errorMessage
        await load()
        errorMessage = message.isEmpty ? previous : message
    }
}

/// V1's surface: the master switch, the templates, the reader's own words, and how many rules are in force.
public struct ReaderContentFilterView: View {
    @State private var store: ReaderContentFilterStore
    private let appearance: ReaderAppearance

    @State private var showsNewRule = false
    @State private var newRuleWords = ""

    public init(store: ReaderContentFilterStore, appearance: ReaderAppearance = .standard) {
        _store = State(initialValue: store)
        self.appearance = appearance
    }

    public var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(get: { store.isEnabled },
                    set: { value in Task { await store.setEnabled(value) } })) {
                    Label(String(localized: "Filtrar conteúdo"), systemImage: "eye.slash")
                }
                .accessibilityIdentifier("content-filter-enabled")
            } footer: {
                Text(verbatim: store.isEnabled
                    ? String(localized: "As regras abaixo estão sendo aplicadas.")
                    : String(localized: "Desligado: as regras ficam guardadas e nada é escondido."))
                    .font(.caption)
                    .accessibilityIdentifier("content-filter-state")
            }

            Section {
                ForEach(store.templates) { template in
                    Toggle(isOn: Binding(get: { store.isTemplateEnabled(template.id) },
                        set: { _ in Task { await store.toggleTemplate(template.id) } })) {
                        HStack(spacing: 8) {
                            Image(systemName: Self.icon(template.id))
                                .frame(width: 22)
                                .foregroundStyle(appearance.accent)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: template.name)
                                Text(verbatim: String(localized: "\(template.ruleCount) palavras"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("content-filter-template-\(template.id)")
                }
            } header: {
                Text(verbatim: String(localized: "Modelos"))
            } footer: {
                Text(verbatim: String(localized: "Assuntos prontos para esconder. Um modelo traz as palavras do seu idioma e as em inglês."))
                    .font(.caption)
            }

            Section {
                if store.rules.isEmpty {
                    Text(verbatim: String(localized: "Nenhuma palavra sua ainda."))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("content-filter-rules-empty")
                }
                ForEach(store.ruleRows) { rule in
                    Text(verbatim: rule.id)
                        .accessibilityIdentifier("content-filter-rule")
                }
                .onDelete { offsets in
                    let ids = offsets.map { store.ruleRows[$0].id }
                    Task { for id in ids { _ = await store.removeRule(id) } }
                }
                Button {
                    newRuleWords = ""
                    showsNewRule = true
                } label: {
                    Label(String(localized: "Adicionar palavras…"), systemImage: "plus.circle")
                        .foregroundStyle(appearance.accent)
                }
                .accessibilityIdentifier("content-filter-add-rule")
            } header: {
                Text(verbatim: String(localized: "Palavras suas"))
            } footer: {
                Text(verbatim: String(localized: "Esconde artigos cujo título ou resumo contenha qualquer uma das palavras. Vale para títulos e resumos, em qualquer idioma."))
                    .font(.caption)
            }
        }
        .listStyle(Self.listStyle)
        .scrollContentBackground(.hidden)
        .background(appearance.pageBackground)
        .navigationTitle(Text(verbatim: String(localized: "Filtros de conteúdo")))
        .alert(String(localized: "Nova regra"), isPresented: $showsNewRule) {
            TextField(String(localized: "Palavras (separadas por vírgula)"), text: $newRuleWords)
            Button(String(localized: "Adicionar")) {
                let words = newRuleWords
                Task { _ = await store.addRules(words) }
            }
            Button(String(localized: "Cancelar"), role: .cancel) {}
        }
        .alert(String(localized: "Não foi possível salvar"), isPresented: Binding(
            get: { store.errorMessage != nil }, set: { _ in })) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(verbatim: store.errorMessage ?? "")
        }
        .task { await store.load() }
    }

    #if os(iOS)
    private static let listStyle = InsetGroupedListStyle()
    #else
    private static let listStyle = InsetListStyle()
    #endif

    /// V1's own pairings (`ContentFilterView.templateIcon`).
    static func icon(_ key: String) -> String {
        switch key {
        case "politics": return "building.columns.fill"
        case "violence": return "exclamationmark.shield.fill"
        case "crypto": return "bitcoinsign.circle.fill"
        case "sports": return "sportscourt.fill"
        case "celebrity": return "star.fill"
        case "ai_hype": return "cpu.fill"
        default: return "eye.slash"
        }
    }
}
