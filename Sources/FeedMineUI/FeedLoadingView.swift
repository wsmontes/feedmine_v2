// Factual absence/work presentation; execution remains external.
// R3: the copy is the PO's approved text. Every state names a fact the engine produced — no invented
// progress, no engine vocabulary ("apresentação local"), and a connection failure only when the
// transport proved one. Recovery actions are host callbacks: this view executes nothing.
import SwiftUI

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
    }

    /// The actions the PO approved, and only where they are the honest next step: a walk that ended
    /// without eligible stories offers both; a proven connection failure offers trying again alone.
    @ViewBuilder private var recoveryActions: some View {
        switch work {
        case .unavailable:
            actions(tryAgain: true, adjust: true)
        case .unreachable:
            actions(tryAgain: true, adjust: false)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private func actions(tryAgain: Bool, adjust: Bool) -> some View {
        if (tryAgain && onTryAgain != nil) || (adjust && onAdjustInterests != nil) {
            HStack(spacing: FeedDesignTokens.Spacing.deck) {
                if tryAgain, let onTryAgain {
                    Button("Tentar novamente", action: onTryAgain)
                        .buttonStyle(.borderedProminent)
                }
                if adjust, let onAdjustInterests {
                    Button("Ajustar interesses", action: onAdjustInterests)
                        .buttonStyle(.bordered)
                }
            }
            .accessibilityIdentifier("feed-recovery-actions")
        }
    }
}
