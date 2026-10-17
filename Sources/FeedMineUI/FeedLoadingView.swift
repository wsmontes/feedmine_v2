// Factual absence/work presentation; execution remains external.
// R3: the copy is the PO's approved text. Every state names a fact the engine produced — no invented
// progress, no engine vocabulary ("apresentação local"), and a connection failure only when the
// transport proved one. Recovery actions are host callbacks: this view executes nothing.
import SwiftUI

/// One way out the absence surface can offer. The host owns the attempt or the destination behind it; this
/// value only names it, so the surface's decision is stated without rendering.
public enum FeedRecoveryRoute: String, CaseIterable, Hashable, Sendable {
    case tryAgain
    case adjustInterests
    case sources
    case settings
}

public extension FeedPresentationState.Work {
    /// R3/F-UX-2: the routes that are the honest next step for each work fact, in drawing order. A walk that
    /// ended without eligible stories offers another attempt and the interests it was walked for; a proven
    /// connection failure offers the attempt alone. A generic failure is the one state drawn without the
    /// reader's chrome — the shell is not drawn without a feed — so it must also offer the reader's own way
    /// out: the sources the session reads and the settings surface. Those are the destinations the shell's
    /// menu already presents; this adds no navigation, it keeps the routes the reader lost with the shell.
    var recoveryRoutes: [FeedRecoveryRoute] {
        switch self {
        case .unavailable: return [.tryAgain, .adjustInterests]
        case .unreachable: return [.tryAgain]
        case .failed: return [.tryAgain, .sources, .settings]
        default: return []
        }
    }
}

@MainActor
public struct FeedLoadingView: View {
    private let work: FeedPresentationState.Work
    private let onTryAgain: (() -> Void)?
    private let onAdjustInterests: (() -> Void)?
    private let onChooseSources: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    public init(work: FeedPresentationState.Work, onTryAgain: (() -> Void)? = nil,
        onAdjustInterests: (() -> Void)? = nil, onChooseSources: (() -> Void)? = nil) {
        self.work = work
        self.onTryAgain = onTryAgain
        self.onAdjustInterests = onAdjustInterests
        self.onChooseSources = onChooseSources
    }

    /// The host's closure as an action the end block may take on the main actor.
    private func mainActorAction(_ action: (() -> Void)?) -> (@MainActor () -> Void)? {
        guard let action else { return nil }
        return { @MainActor in action() }
    }

    public var body: some View {
        VStack(spacing: FeedDesignTokens.Spacing.page) {
            // U1-B: restrained branding on the absence surface. The factual work text below stays
            // the source of truth; the wordmark never replaces pipeline evidence.
            Image(FeedDesignTokens.AssetName.wordmark(for: colorScheme))
                .resizable()
                .scaledToFit()
                .frame(maxWidth: FeedDesignTokens.Measurement.wordmarkWidth)
                .accessibilityHidden(true)
            Group {
                switch work {
                case .idle, .pending:
                    Text("Descobrindo histórias para você…")
                case .unavailable:
                    Text("Ainda não encontramos histórias para você.")
                case .deferred:
                    VStack(spacing: FeedDesignTokens.Spacing.tight) {
                        Text("Procurando mais novidades…")
                        Text("Ainda não encontramos conteúdo suficiente. Vamos tentar novamente em instantes.")
                            .font(FeedDesignTokens.Typography.label)
                            .foregroundStyle(FeedDesignTokens.Palette.secondaryText)
                    }
                case .unreachable:
                    VStack(spacing: FeedDesignTokens.Spacing.tight) {
                        Text("Não foi possível conectar.")
                        Text("Não conseguimos buscar novas histórias agora.")
                            .font(FeedDesignTokens.Typography.label)
                            .foregroundStyle(FeedDesignTokens.Palette.secondaryText)
                    }
                case .failed(let message):
                    Text(verbatim: message)
                case .endOfContent:
                    // Nothing is drawn above the end: the reader has no cards at all. The state is still stated
                    // with the ratified view and copy, offering only the routes that can act here — never one that
                    // promises a position there is nothing to return to (review, 2026-10-14). The sentence lives
                    // in exactly one place, so the two surfaces cannot drift.
                    FeedEndOfContentView(onExploreSubjects: mainActorAction(onAdjustInterests),
                        onWidenSources: mainActorAction(onChooseSources))
                case .preparing(let progress):
                    FeedPreparationView(progress: progress)
                }
            }
            .font(FeedDesignTokens.Typography.body)
            .multilineTextAlignment(.center)
            recoveryActions
        }
        .padding(FeedDesignTokens.Spacing.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The surface is nameable, so a journey can assert its **absence** — the half of the PO's headline criterion
        // ("close and reopen the app … with no loading screen in between") that no test ever asserted. The container
        // keeps its children (V1 named its own loading surface the same way, `initial-feed-loading`).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feed-loading-surface")
    }

    /// The actions the PO approved, drawn from the plan the work fact states. A route the host did not
    /// supply draws nothing, so the surface never invents a destination or an attempt.
    @ViewBuilder private var recoveryActions: some View {
        let routes = work.recoveryRoutes
        if !routes.isEmpty {
            HStack(spacing: FeedDesignTokens.Spacing.deck) {
                ForEach(routes, id: \.self) { route in
                    action(for: route)
                }
            }
            .accessibilityIdentifier("feed-recovery-actions")
        }
    }

    @ViewBuilder private func action(for route: FeedRecoveryRoute) -> some View {
        switch route {
        case .tryAgain:
            if let onTryAgain {
                Button("Tentar novamente", action: onTryAgain)
                    .buttonStyle(.borderedProminent)
            }
        case .adjustInterests:
            if let onAdjustInterests {
                Button("Ajustar interesses", action: onAdjustInterests)
                    .buttonStyle(.bordered)
            }
        case .sources:
            if let onChooseSources {
                Button(String(localized: "Fontes"), action: onChooseSources)
                    .buttonStyle(.bordered)
            }
        case .settings:
            // The same settings surface the interests route opens in this build; the label is the
            // destination's own title, as the shell's menu states it.
            if let onAdjustInterests {
                Button(String(localized: "Ajustes"), action: onAdjustInterests)
                    .buttonStyle(.bordered)
            }
        }
    }
}
