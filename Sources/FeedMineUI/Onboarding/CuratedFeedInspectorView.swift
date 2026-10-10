//
// File: CuratedFeedInspectorView.swift
// Module: FeedMineUI
//
// Responsibility:
// V1's "open hood" (`Views/CuratedFeedInspectorView.swift`): the feed's name, what it asked for, the choices
// behind it, and the promise about what is never inferred. It edits nothing itself — the host owns the recipe
// and the save — and it states only what the summary carries.
//
// Deliberate difference, recorded in docs/v1-study/PORT_LOG.md: V1 drew sliders for the *learned* weights and a
// confidence label per key ("learning"/"medium"/"strong"), because it merged evidence with the recipe. V2 has no
// evidence yet, so the inspector lists the reader's own answers instead of inventing a confidence.
import SwiftUI
import FeedMineDomain

public struct CuratedFeedInspectorView: View {
    private let summary: CuratedFeedSummary
    private let discoveryPeriod: String?
    private let isSaving: Bool
    private let onSave: (String) -> Void
    private let onEdit: () -> Void
    private let onDelete: () -> Void
    private let onClose: () -> Void

    @State private var name: String

    public init(summary: CuratedFeedSummary, discoveryPeriod: String? = nil, isSaving: Bool = false,
        onSave: @escaping (String) -> Void, onEdit: @escaping () -> Void, onDelete: @escaping () -> Void,
        onClose: @escaping () -> Void) {
        self.summary = summary
        self.discoveryPeriod = discoveryPeriod
        self.isSaving = isSaving
        self.onSave = onSave
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onClose = onClose
        _name = State(initialValue: summary.name)
    }

    public var body: some View {
        List {
            identityCard
            answersCard
            languagesCard
            discoveryCard
            privacyNote
            Section {
                Button(String(localized: "Editar controles"), action: onEdit)
                    .accessibilityIdentifier("hood-edit")
                Button(String(localized: "Excluir feed curado"), role: .destructive, action: onDelete)
                    .accessibilityIdentifier("hood-delete")
            }
        }
        .listStyle(Self.listStyle)
        .navigationTitle(Text(verbatim: String(localized: "Feed curado")))
        .toolbar {
            ToolbarItem(placement: ReaderToolbarPlacement.trailing) {
                Button(String(localized: "Salvar")) { onSave(name) }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("hood-save")
            }
            ToolbarItem(placement: ReaderToolbarPlacement.trailing) {
                Button(String(localized: "Fechar"), action: onClose)
                    .accessibilityIdentifier("hood-close")
            }
        }
    }

    /// V1's identity card: the badge, the promise, the name and the three counts.
    private var identityCard: some View {
        Section {
            VStack(alignment: .leading, spacing: FeedDesignTokens.Spacing.tight) {
                Text(verbatim: String(localized: "CAPÔ ABERTO")).font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("hood-badge")
                Text(verbatim: String(localized: "Nada escondido aqui.")).font(.headline)
                Text(verbatim: String(localized: "Edite o que o Feedmine aprendeu, ou desligue o aprendizado."))
                    .font(.caption).foregroundStyle(.secondary)
                TextField(String(localized: "Nome do feed"), text: $name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("hood-name")
                HStack(spacing: FeedDesignTokens.Spacing.deck) {
                    metric("\(summary.answers.count)", String(localized: "escolhas"), id: "hood-choices")
                    metric("\(summary.answers.filter { $0.level != .neutral }.count)",
                        String(localized: "sinais"), id: "hood-signals")
                    metric("\(Int((summary.discoveryLevel * 100).rounded()))%",
                        String(localized: "descoberta"), id: "hood-discovery")
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func metric(_ value: String, _ label: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: value).font(.headline)
            Text(verbatim: label).font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityIdentifier(id)
    }

    /// The reader's own answers, strongest first — V1's "Interest mix" as a list rather than sliders it would
    /// have to invent a weight for.
    @ViewBuilder private var answersCard: some View {
        Section {
            if summary.answers.isEmpty {
                Text(verbatim: String(localized: "Este feed começou equilibrado. Ajuste os controles acima quando quiser."))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("hood-no-answers")
            }
            ForEach(summary.answers, id: \.key) { answer in
                HStack {
                    Text(verbatim: Self.displayName(answer.key)).font(.subheadline)
                    Spacer()
                    Text(verbatim: answer.isTopic ? answer.level.topicLabel : answer.level.balanceLabel)
                        .font(.caption)
                        .foregroundStyle(answer.level == .neutral ? .secondary : .primary)
                }
                .accessibilityIdentifier("hood-answer")
            }
        } header: {
            Text(verbatim: String(localized: "Interesses"))
        } footer: {
            Text(verbatim: String(localized: "Só escolhas explícitas — nunca uma rolagem de passagem."))
                .font(.caption)
                .accessibilityIdentifier("hood-answers-footer")
        }
    }

    private var languagesCard: some View {
        Section {
            if summary.languages.isEmpty {
                Text(verbatim: String(localized: "Todos os idiomas")).foregroundStyle(.secondary)
            } else {
                Text(verbatim: summary.languages.joined(separator: " · "))
                    .accessibilityIdentifier("hood-languages")
            }
            Text(verbatim: summary.mediaTypes.map(\.displayName).joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("hood-media")
        } header: {
            Text(verbatim: String(localized: "Idiomas e tipos"))
        }
    }

    private var discoveryCard: some View {
        Section {
            HStack {
                Text(verbatim: String(localized: "Descoberta"))
                Spacer()
                Text(verbatim: "\(Int((summary.discoveryLevel * 100).rounded()))%")
                    .foregroundStyle(.secondary)
                if let discoveryPeriod {
                    Text(verbatim: discoveryPeriod).font(.caption).foregroundStyle(.tertiary)
                }
            }
            HStack {
                Text(verbatim: String(localized: "Continuar aprendendo"))
                Spacer()
                Text(verbatim: summary.adjustFromOpens ? String(localized: "ligado") : String(localized: "desligado"))
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("hood-learning")
        } header: {
            Text(verbatim: String(localized: "Descoberta e aprendizado"))
        }
    }

    /// V1's own promise, kept word for word in the reader's language.
    private var privacyNote: some View {
        Section {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "hand.raised.fill").foregroundStyle(.secondary)
                Text(verbatim: String(localized: "Nenhuma personalidade, religião, etnia, gênero, localização ou rótulo demográfico é inferido ou guardado."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("hood-privacy")
        }
    }

    /// A key as the reader reads it: the catalogue's own node path, without the recipe's namespace.
    static func displayName(_ key: String) -> String {
        for prefix in ["topic:", "region:", "editorial:", "nature:", "media:", "scope:"] where key.hasPrefix(prefix) {
            return String(key.dropFirst(prefix.count))
        }
        return key
    }

    #if os(iOS)
    private static let listStyle = InsetGroupedListStyle()
    #else
    private static let listStyle = InsetListStyle()
    #endif
}
