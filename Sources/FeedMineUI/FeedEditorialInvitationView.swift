//
// File: FeedEditorialInvitationView.swift
// Module: FeedMineUI
//
// Responsibility:
// F02's in-feed invitation: the feed presents what discovery found, and the reader says **in place** where to
// explore more or less of. It is one block of the feed, not a form, not a gate, and never more than the reader
// asked for: every action states its consequence, the answer can be taken back, and the invitations can be
// hidden for good.
//
// Does not own: the vote (the host writes the preference), discovery, or the feed's own cards.
import FeedMineDomain
import SwiftUI

public struct FeedEditorialInvitationView: View {
    private let subjectName: String
    private let nodeKey: String
    private let answered: ReaderPreferenceLevel?
    /// Round 10's budget, stated as a form: only the session's **first** offer asks the full question; the ones
    /// after it keep the same actions in less space. Both forms carry the same identifiers, because they are the
    /// same offer — the reader's actions do not change with the form.
    private let isCompact: Bool
    private let onVote: (ReaderPreferenceLevel) -> Void
    private let onUndo: () -> Void
    private let onHide: () -> Void

    public init(subjectName: String, nodeKey: String, answered: ReaderPreferenceLevel? = nil,
        isCompact: Bool = false,
        onVote: @escaping (ReaderPreferenceLevel) -> Void, onUndo: @escaping () -> Void = {},
        onHide: @escaping () -> Void = {}) {
        self.subjectName = subjectName
        self.nodeKey = nodeKey
        self.answered = answered
        self.isCompact = isCompact
        self.onVote = onVote
        self.onUndo = onUndo
        self.onHide = onHide
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: FeedDesignTokens.Spacing.tight) {
            Text(verbatim: String(localized: "FeedMine sugere"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            if let answered {
                // The answer is stated, and it is not final: the PRD is explicit that a person changes their mind
                // without punishment, so the way back is right here.
                Text(verbatim: answered == .more
                    ? String(localized: "Você pediu mais fontes em \(subjectName). Vamos procurar mais delas.")
                    : String(localized: "Você pediu menos fontes em \(subjectName). Vamos procurar menos delas."))
                    .font(.subheadline)
                    HStack(spacing: FeedDesignTokens.Spacing.tight) {
                        Button(String(localized: "Desfazer")) { onUndo() }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("feed-invitation-undo-\(nodeKey)")
                        Button(String(localized: "Esconder dicas")) { onHide() }
                            .buttonStyle(.plain)
                            .font(.caption)
                        .accessibilityIdentifier("feed-invitation-hide-\(nodeKey)")
                }
            } else if isCompact {
                // The session's later offers: the same title, the same two answers, the same way out, and no
                // paragraphs — the reader has met the question's shape already and is being asked about another
                // group, not taught the product again.
                Text(verbatim: String(localized: "FeedMine sugere"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    actions
            } else {
                // The review's wording, and the reason for it: the subject offered is how the **catalogue
                // files the source**, not what the article is about. The sentence attributes the classification
                // to FeedMine and says exactly what the answer changes.
                Text(verbatim: String(localized: "No nosso catálogo, esta fonte está em \(subjectName). Quer explorar mais fontes desse grupo?"))
                    .font(.subheadline)
                    actions
                // The consequence, in plain words: the reader should never have to guess what a tap does.
                Text(verbatim: String(localized: "Sua resposta orienta a busca por mais ou menos fontes desse grupo nas próximas descobertas. Você pode mudar de ideia."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("feed-invitation-consequence-\(nodeKey)")
                }
        }
        .padding(FeedDesignTokens.Spacing.tight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: FeedDesignTokens.Radius.card,
            style: .continuous))
        // Measured, twice: a container that declares itself an accessibility element **hides its own buttons** from
        // the tree — the app offered thousands of invitations that no query could find, which also means a reader
        // with VoiceOver could never answer one. The block therefore declares no element of its own: its actions
        // are the elements, each one stating what it does.
    }

    /// The two answers and the way out. One definition, so the full and the compact form can never drift apart in
    /// what they do — only in how much they explain.
    @ViewBuilder private var actions: some View {
        HStack(spacing: FeedDesignTokens.Spacing.tight) {
            Button(String(localized: "Mais de \(subjectName)")) { onVote(.more) }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("feed-invitation-more-\(nodeKey)")
            Button(String(localized: "Menos de \(subjectName)")) { onVote(.less) }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("feed-invitation-less-\(nodeKey)")
            Button(String(localized: "Esconder dicas")) { onHide() }
                .buttonStyle(.plain)
                .font(.caption)
                .accessibilityIdentifier("feed-invitation-hide-\(nodeKey)")
        }
    }

}
