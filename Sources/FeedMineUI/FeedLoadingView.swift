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
    /// F12/S1: the source whose surface this is, when the reader is on one. The absence surface states what such a
    /// surface can ever show — the items the source publishes in its own feed, never the site's whole archive.
    private let sourceContextName: String?
    @Environment(\.colorScheme) private var colorScheme

    public init(work: FeedPresentationState.Work, onTryAgain: (() -> Void)? = nil,
        onAdjustInterests: (() -> Void)? = nil, onChooseSources: (() -> Void)? = nil,
        sourceContextName: String? = nil) {
        self.work = work
        self.onTryAgain = onTryAgain
        self.onAdjustInterests = onAdjustInterests
        self.onChooseSources = onChooseSources
        self.sourceContextName = sourceContextName
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
                    // NF-04: `deferred` is the outcome of an opportunity the engine did **not** run — the
                    // coordinator denied the attempt's resources, or a newer attempt superseded it. Saying
                    // "looking for more news" claimed a search in flight and promised a next attempt "in a
                    // moment" that nothing committed to: the invented work the PO forbade. The surface states
                    // the situation and leaves the next attempt to the host.
                    VStack(spacing: FeedDesignTokens.Spacing.tight) {
                        Text("Aguardando nova oportunidade")
                        Text("Nada está sendo buscado agora.")
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
            sourceScopeNote
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

    /// F12/S1: the one sentence that states a source surface's limit — the items the source publishes in its own
    /// feed, never the site's whole archive. Kept as a value so the criterion can be stated without rendering.
    public static func sourceScopeNote(sourceContextName: String) -> String {
        String(localized: "Você está vendo os itens que \(sourceContextName) publica no feed. O arquivo completo do site não faz parte dele.")
    }

    /// Where the note belongs: an absence **of a source** — not the main feed (no name) and not a surface that is
    /// still preparing (no bounded set is being shown yet).
    public static func showsSourceScopeNote(work: FeedPresentationState.Work,
        sourceContextName: String?) -> Bool {
        guard sourceContextName != nil else { return false }
        switch work {
        case .unavailable, .unreachable, .deferred, .failed, .endOfContent: return true
        case .idle, .pending, .preparing: return false
        }
    }

    /// F12/S1: what a source surface can and cannot show, stated where the absence is. Only an absence state draws
    /// it — while preparing, the reader is not yet looking at a bounded set. Nil name (the main feed) draws nothing.
    @ViewBuilder private var sourceScopeNote: some View {
        if let sourceContextName, Self.showsSourceScopeNote(work: work, sourceContextName: sourceContextName) {
            Text(Self.sourceScopeNote(sourceContextName: sourceContextName))
                .font(FeedDesignTokens.Typography.label)
                .foregroundStyle(FeedDesignTokens.Palette.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, FeedDesignTokens.Spacing.page)
                .accessibilityIdentifier("feed-source-scope-note")
        }
    }

    /// The actions the PO approved, and only where they are the honest next step: a walk that ended
    /// without eligible stories offers both; a proven connection failure and a deferred attempt offer trying
    /// again alone. The host's action runs a real attempt (`refreshFromTheReader` → `foreground`), which is why
    /// a state that is only waiting — not searching — may offer it.
    @ViewBuilder private var recoveryActions: some View {
        switch work {
        case .unavailable:
            actions(tryAgain: true, adjust: true)
        case .unreachable, .deferred:
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
