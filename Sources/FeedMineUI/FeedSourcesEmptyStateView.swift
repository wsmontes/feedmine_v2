//
// File: FeedEmptyStateView.swift
// Module: FeedMineUI
//
// Responsibility:
// V1's `FeedEmptyStateView` for the one mode this delivery owns: a reader whose selection has no
// sources. It copies the legacy layout — the accent circle, the globe, the title, the description and
// the one prominent action — and it is a value-driven view: the host states what the reader can do
// about it, the view states nothing it was not given.
//
// Deliberate difference from V1 (recorded in docs/v1-study/PORT_LOG.md): V1's copy sent the reader to
// *Filters* ("Enable some countries or topics in Filters…") because its filter sheet held the
// country/topic selection. In V2 the preference and the criterion are separate surfaces: the country
// and topic *selection* lives in source management, and a filter criterion cannot add content to an
// empty selection. The action therefore opens source management, and says so.
import SwiftUI
import FeedMineDomain

@MainActor
public struct FeedSourcesEmptyStateView: View {
    private let appearance: ReaderAppearance
    /// What the host does when the reader asks to fix the selection.
    private let onChooseSources: @MainActor () -> Void

    public init(appearance: ReaderAppearance = .standard,
        onChooseSources: @escaping @MainActor () -> Void) {
        self.appearance = appearance
        self.onChooseSources = onChooseSources
    }

    /// V1's copy for this mode, as a value so a test can state it without rendering.
    // The ported views state their copy in the app's own language (V1's `Todos os países` / `Concluir`
    // convention), not in V1's English literals.
    public static let title = String(localized: "Nenhuma fonte habilitada")
    public static let message = String(localized: "Ative países ou tópicos em Fontes para começar a ver conteúdo.")
    public static let actionTitle = String(localized: "Escolher fontes")
    public static let iconName = "globe.americas.fill"

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(appearance.accent.opacity(0.1))
                    .frame(width: 100, height: 100)
                Image(systemName: Self.iconName)
                    .font(.system(size: 40))
                    .foregroundStyle(appearance.accent)
            }
            Text(Self.title)
                .font(.title3)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: 360)
                .padding(.horizontal, 24)
                .accessibilityIdentifier("feed-empty-title")
            Text(Self.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.9)
                .padding(.horizontal, 32)
            Button {
                onChooseSources()
            } label: {
                HStack {
                    Image(systemName: "line.3.horizontal.decrease")
                    Text(Self.actionTitle)
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .tint(appearance.accent)
            .controlSize(.large)
            .accessibilityIdentifier("feed-empty-action")
            Spacer()
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity)
        // The surface's own identifier stays on the surface; the title and the action keep theirs inside it.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feed-empty-state")
    }
}
