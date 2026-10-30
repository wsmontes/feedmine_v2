// Real visual inputs terminate at the store callback; executable composition is external.
import SwiftUI
#if DEBUG
import OSLog
#endif
import FeedMineDomain
import FeedMineRuntime

@MainActor
public struct FeedScreen: View {
    private let store: FeedScreenStore
    /// The frozen visual system for this session. It is an immutable host input, never internal
    /// observable state: an appearance change is an explicit decision, not an effect of this view.
    private let appearance: ReaderAppearance
    /// The host's own status chip (V1's `CompactFeedStatus` equivalent). Nil renders the delivery's
    /// default, which states only what the presentation value knows.
    private let customStatusChip: AnyView?
    /// The host's filter lens (V1's chip bar). Nil draws nothing above the feed.
    private let lens: AnyView?
    /// Whether the reader's accepted selection has any sources at all, and what to do about it. It is the
    /// host's fact: this view owns no selection. An empty selection is not a preparation and not a failure —
    /// it is V1's own empty surface, so it takes precedence over both.
    private let hasSources: Bool
    private let onChooseSources: @MainActor () -> Void
    /// R3: the host's recovery actions for the absence surface. "Tentar novamente" runs a real
    /// attempt and "Ajustar interesses" opens the flow that owns the reader's interests; this view
    /// executes neither.
    private let onTryAgain: @MainActor () -> Void
    private let onAdjustInterests: @MainActor () -> Void
    /// The host's editorial row: offered between cards, and only where the host says there is something truthful
    /// to ask. Nil — or a nil answer for a card — draws nothing, so the feed surface never invents an offer.
    private let editorial: (@MainActor (PresentationCard, Int, PresentationCard?) -> AnyView?)?
    @State private var capture = FeedVisualCapture()

    public init(store: FeedScreenStore, appearance: ReaderAppearance = .standard,
        statusChip: AnyView? = nil, lens: AnyView? = nil, hasSources: Bool = true,
        onChooseSources: @escaping @MainActor () -> Void = {},
        onTryAgain: @escaping @MainActor () -> Void = {},
        onAdjustInterests: @escaping @MainActor () -> Void = {},
        editorial: (@MainActor (PresentationCard, Int, PresentationCard?) -> AnyView?)? = nil) {
        self.store = store
        self.appearance = appearance
        self.customStatusChip = statusChip
        self.lens = lens
        self.hasSources = hasSources
        self.onChooseSources = onChooseSources
        self.onTryAgain = onTryAgain
        self.onAdjustInterests = onAdjustInterests
        self.editorial = editorial
    }

    public var body: some View {
        // The reader's chrome belongs to the feed surface: before the first presentation there is no
        // feed to read, so the preparation state keeps its own full-screen surface (V1 too drew its
        // header for the session, and T11 owns the preparation experience).
        if !hasSources {
            // V1 drew this surface instead of the feed, with the reader's chrome: nothing is being prepared,
            // so there is no progress to state.
            ReaderShell(store: store, appearance: appearance, status: { statusChip },
                lens: { if let lens { lens } }) {
                FeedSourcesEmptyStateView(appearance: appearance, onChooseSources: onChooseSources)
            }
        } else if !store.renderedItems.isEmpty {
            ReaderShell(store: store, appearance: appearance, status: { statusChip },
                lens: { if let lens { lens } }) {
                feedBody
            }
        } else {
            FeedLoadingView(work: store.work, onTryAgain: { onTryAgain() },
                onAdjustInterests: { onAdjustInterests() }, onChooseSources: { onChooseSources() })
        }
    }

    /// The chip states the reader's situation. The host can replace it (T5 hook) because the host owns
    /// the counters; this default states only what the presentation value knows.
    @ViewBuilder private var statusChip: some View {
        if let customStatusChip { customStatusChip } else { FeedWorkBadge(work: store.work) }
    }

    private var workFeedback: some View { FeedWorkFeedback(work: store.work) }

    @ViewBuilder private var feedBody: some View {
        // A lista desenha **conteúdo**: os itens que a loja publica (mudam quando a janela muda) e, durante um
        // gesto, a janela segurada. A posição do leitor **não** é lida aqui — era ela que fazia a lista inteira ser
        // reavaliada a cada avanço (medido no aparelho, 2026-10-14: 12–14 instalações por segundo numa rajada).
        // Princípio do dono: a UI é imediata; o backend corre atrás e se antecipa.
        let items = capture.interaction.heldItems(matching: store) ?? store.renderedItems
        if !items.isEmpty {
            if #available(iOS 18, macOS 15, *) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: FeedDesignTokens.Spacing.section) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, card in
                          // One stable lazy cell per publication ID. Measure the card itself;
                          // the optional invitation keeps the same spacing inside this cell.
                            VStack(alignment: .leading, spacing: FeedDesignTokens.Spacing.section) {
                              FeedItemView(card: card, appearance: appearance,
                                isBookmarked: store.bookmarkedIDs.contains(card.id),
                                availableActions: store.availableActions,
                                onAction: { store.perform($0, rendered: store.state.presentation) })
                                .onGeometryChange(for: FeedVisualCardGeometry?.self, of: { proxy in
                                    guard let bounds = proxy.bounds(of: .scrollView(axis: .vertical)) else { return nil }
                                    let frame = proxy.frame(in: .scrollView(axis: .vertical))
                                    let local = proxy.frame(in: .named("feed-visual-content"))
                                    return .init(cardID: card.id, frame: frame,
                                        offset: local.minY - frame.minY, height: bounds.height)
                                }) { proof in
                                    #if DEBUG
                                    FeedVisualCapture.probeEntries += 1
                                    #endif
                                    // A prova vale para uma carta que a lista desenha e para a apresentação que a loja
                                    // tem agora — comparada pela **identidade publicada**, nunca pela posição do
                                    // leitor (era essa leitura, dentro do corpo, que re-renderizava a lista a cada
                                    // avanço).
                                    guard store.renderedItems.contains(where: { $0.id == card.id }),
                                        let current = store.state.presentation,
                                        store.renderedEditionID == current.editionID,
                                        store.renderedContextKey == current.contextKey,
                                        let proof else { return }
                                    #if DEBUG
                                    FeedVisualCapture.probeGuards += 1
                                    #endif
                                    #if canImport(UIKit)
                                    if capture.nativeScrollOffset.observe(proof) {
                                        return
                                    }
                                    #endif
                                    if let event = capture.observeCard(proof,
                                        isLast: store.state.presentation?.window.items.last?.id == proof.cardID) {
                                        #if DEBUG
                                        FeedVisualCapture.submissions += 1
                                        #endif
                                        store.submitViewport(event.observation, activity: event.activity, rendered: store.state.presentation)
                                    }
                                    if let event = capture.settle() {
                                        store.submitViewport(event.observation, activity: event.activity, rendered: store.state.presentation)
                                    }
                                    // Onde o viewport **começa** vai para o host: é a posição que a durabilidade
                                    // grava, porque é a única que uma restauração reproduz exatamente. O store a
                                    // repassa — quem a lembra é a sessão — e a captura só fala quando a posição
                                    // muda ou chega ao repouso.
                                    capture.reportPresentedPosition { anchor, atRest in
                                        store.publishPresentedPosition(anchor, atRest: atRest)
                                    }
                                }
                            EditorialSlot { editorial?(card, index, index > 0 ? items[index - 1] : nil) }
                          }
                        }
                        endOfContentBlock(items: items)
                    }
                    #if canImport(UIKit)
                    .background(FeedNativeScrollProbe(access: capture.nativeScrollOffset, ids: items.map(\.id)))
                    #endif
                    .modifier(NativeFeedTargets())
                    // U1-F: one FeedScreen for every device; wide displays keep a readable column
                    // instead of stretching editorial text across the window.
                    .frame(maxWidth: FeedDesignTokens.Measurement.readableContentWidth)
                    .frame(maxWidth: .infinity)
                }
                .modifier(NativeFeedViewport(capture: $capture, store: store))
                #if DEBUG && canImport(UIKit)
                .modifier(FeedNativeWindowProof(ids: items.map(\.id), access: capture.nativeScrollOffset,
                    deferredWindows: capture.interaction.deferredWindows, store: store, capture: $capture))
                #endif
                // T3: work feedback is an overlay of constant height that never takes touches, so the
                // scroll viewport keeps exactly the geometry the reader was admitted into.
                .overlay(alignment: .bottom) { workFeedback }
            } else {
                // macOS 14 renders local cards without automatic viewport capture.
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: FeedDesignTokens.Spacing.section) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, card in
                            Group {
                                FeedItemView(card: card, appearance: appearance,
                                    isBookmarked: store.bookmarkedIDs.contains(card.id),
                                    availableActions: store.availableActions,
                                    onAction: { store.perform($0, rendered: store.state.presentation) })
                                EditorialSlot { editorial?(card, index, index > 0 ? items[index - 1] : nil) }
                            }
                        }
                        endOfContentBlock(items: items)
                    }
                    .padding(FeedDesignTokens.Spacing.page)
                    .frame(maxWidth: FeedDesignTokens.Measurement.readableContentWidth)
                    .frame(maxWidth: .infinity)
                }
                // T3: work feedback is an overlay of constant height that never takes touches, so the
                // scroll viewport keeps exactly the geometry the reader was admitted into.
                .overlay(alignment: .bottom) { workFeedback }
            }
        } else {
            FeedLoadingView(work: store.work, onTryAgain: { onTryAgain() },
                onAdjustInterests: { onAdjustInterests() }, onChooseSources: { onChooseSources() })
        }
    }

    /// PO 2026-10-14: the end the composition asserted is **one more child of the list**, after the last
    /// card — it never replaces the screen and is never inserted above a card. The three actions reuse what
    /// this surface already owns: the host's interests and sources hooks, and, for "Voltar ao início", the
    /// reading position itself (the first drawn card), so no session is rebuilt and the order never changes.
    @ViewBuilder private func endOfContentBlock(items: [PresentationCard]) -> some View {
        if store.work == .endOfContent {
            FeedEndOfContentView(appearance: appearance,
                onExploreSubjects: { onAdjustInterests() },
                onWidenSources: { onChooseSources() },
                onReturnToStart: { capture.positionID = items.first?.id })
        }
    }
}
