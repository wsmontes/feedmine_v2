//
// File: FeedEndOfContentView.swift
// Module: FeedMineUI
//
// Responsibility:
//   The ratified end-of-eligible-content block. It is drawn as the **last child of the feed list** —
//   after the last published card — so nothing above it moves, the screen is never replaced and the
//   block is never inserted in the middle. It states the end the composition asserted and offers the
//   three actions the PO ratified; it executes none of them, because each is a host callback.
//
// Deliberate difference from FeedLoadingView: that surface states the provisional "nothing yet" and
// keeps its own copy and actions. The two states share visual structure but are distinguishable by the
// reader — this one says the offer ended and offers how to widen it.
//
// Does not own: production, admission, ordering or the end decision itself (that is composition's).
import SwiftUI
import FeedMineDomain

@MainActor
public struct FeedEndOfContentView: View {
    private let appearance: ReaderAppearance
    /// "Explore outros assuntos" — the host's interests surface.
    private let onExploreSubjects: (@MainActor () -> Void)?
    /// "Ampliar fontes" — the host's sources screen.
    private let onWidenSources: (@MainActor () -> Void)?
    /// "Voltar ao início" — the host's existing reading position, never a rebuilt session. `nil` where there is
    /// no position to go back to (the reader has nothing drawn); F02's rule is that no control may promise what
    /// the app cannot fulfil, so a route without a host action is not offered (review, 2026-10-14).
    private let onReturnToStart: (@MainActor () -> Void)?

    public init(appearance: ReaderAppearance = .standard,
        onExploreSubjects: (@MainActor () -> Void)? = nil,
        onWidenSources: (@MainActor () -> Void)? = nil,
        onReturnToStart: (@MainActor () -> Void)? = nil) {
        self.appearance = appearance
        self.onExploreSubjects = onExploreSubjects
        self.onWidenSources = onWidenSources
        self.onReturnToStart = onReturnToStart
    }

    /// The PO's ratified copy and action titles, as values so a test can state them without rendering.
    public static let message = String(localized: "Você chegou ao fim das histórias disponíveis para sua seleção.")
    public static let exploreSubjectsTitle = String(localized: "Explore outros assuntos")
    public static let widenSourcesTitle = String(localized: "Ampliar fontes")
    public static let returnToStartTitle = String(localized: "Voltar ao início")

    public var body: some View {
        VStack(alignment: .leading, spacing: FeedDesignTokens.Spacing.normal) {
            Text(Self.message)
                .font(FeedDesignTokens.Typography.label)
                .foregroundStyle(FeedDesignTokens.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("feed-end-message")
            VStack(alignment: .leading, spacing: FeedDesignTokens.Spacing.compact) {
                if let onExploreSubjects {
                    Button { onExploreSubjects() } label: {
                        Label(Self.exploreSubjectsTitle, systemImage: "sparkles")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(appearance.accent)
                    .accessibilityIdentifier("feed-end-explore-subjects")
                }
                if let onWidenSources {
                    Button { onWidenSources() } label: {
                        Label(Self.widenSourcesTitle, systemImage: "plus.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("feed-end-widen-sources")
                }
                if let onReturnToStart {
                    Button { onReturnToStart() } label: {
                        Label(Self.returnToStartTitle, systemImage: "arrow.up.to.line")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("feed-end-return-to-start")
                }
            }
        }
        .padding(FeedDesignTokens.Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FeedDesignTokens.Palette.cardSurface,
            in: RoundedRectangle(cornerRadius: FeedDesignTokens.Radius.overlay))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feed-end-of-content")
    }
}
