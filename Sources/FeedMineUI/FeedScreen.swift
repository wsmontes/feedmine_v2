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
    /// The name of the source whose surface this is, when the reader is on one (F12/S1). Nil on `.main`; the
    /// absence surface uses it to state the limit of what a source surface can ever show.
    private let sourceContextName: String?
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
        sourceContextName: String? = nil,
        onChooseSources: @escaping @MainActor () -> Void = {},
        onTryAgain: @escaping @MainActor () -> Void = {},
        onAdjustInterests: @escaping @MainActor () -> Void = {},
        editorial: (@MainActor (PresentationCard, Int, PresentationCard?) -> AnyView?)? = nil) {
        self.store = store
        self.appearance = appearance
        self.customStatusChip = statusChip
        self.lens = lens
        self.hasSources = hasSources
        self.sourceContextName = sourceContextName
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
        // A search context is a surface of its own: the feed window is intentionally empty while the reader is
        // searching, but the shell — and its results page — must still be mounted. Without this the app kept the
        // loading surface over a search that had already completed.
        } else if store.isSearching || !store.renderedItems.isEmpty {
            ReaderShell(store: store, appearance: appearance, status: { statusChip },
                lens: { if let lens { lens } }) {
                // The cover and its accessibility hiding are scoped to the **feed content**, never to the shell:
                // the reader's own header (context chip, sources, saved, filters, menu) stays usable while the
                // preparation cover is up, which is the surface's stated intent and the only way out of a context
                // that is still preparing.
                feedBody
                    // While the cover is up, the laid-out cards are not on screen: they are measured, not shown,
                    // and the accessibility tree must say the same thing the pixels do.
                    .accessibilityHidden(drawsPreparationCover)
                    // D4: the transition from preparation to reading is held by the **measured layout**, not by
                    // the arrival of a first card. The cards are laid out here (that is what measurement needs)
                    // and the preparation surface stays over them until they reach the viewport bottom. The judge
                    // is `FeedFirstScreenGate`; nothing about publication, admission or the cards changes.
                    .overlay {
                        if drawsPreparationCover {
                            preparationSurface
                                .transition(.opacity)
                        }
                    }
            }
        } else {
            // A source context that has no published item yet is a **reading surface**, not a dead end: without
            // the shell it drew a full-screen "Finding stories for you…" with no header, no context control and
            // no way back to Main or to the sources (measured 2026-10-23: more than seven minutes, no control).
            // The same chrome is mounted over the loading content; the content stays the work surface it was.
            ReaderShell(store: store, appearance: appearance, status: { statusChip },
                lens: { if let lens { lens } }) {
                FeedLoadingView(work: store.work, onTryAgain: { onTryAgain() },
                    onAdjustInterests: { onAdjustInterests() }, onChooseSources: { onChooseSources() },
                    sourceContextName: sourceContextName)
            }
        }
    }

    /// Whether the preparation surface is covering the laid-out cards this pass.
    ///
    /// Both facts are read together on purpose: `firstScreenReading` is the observable that changes when a
    /// **measurement** — not a new card — settles the transition, so the cover leaves on the same pass the decision
    /// changes, and `firstScreenSurface` is the decision itself (the screen and the host's launch record read this
    /// one value, never two opinions). The lifecycle that states those facts (the host's timeout and the appearance
    /// of a window) belongs to the host: this view renders, it executes nothing.
    private var drawsPreparationCover: Bool {
        !store.firstScreenReading && store.firstScreenSurface == .preparation
    }

    /// The preparation surface as a cover: the same honest surface the launch already draws (its copy is the
    /// work state's own), filled and opaque so the reader never sees a half-composed screen beneath it.
    private var preparationSurface: some View {
        FeedLoadingView(work: store.work, onTryAgain: { onTryAgain() },
            onAdjustInterests: { onAdjustInterests() }, onChooseSources: { onChooseSources() },
            sourceContextName: sourceContextName)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
    }

    /// The chip states the reader's situation. The host can replace it (T5 hook) because the host owns
    /// the counters; this default states only what the presentation value knows.
    @ViewBuilder private var statusChip: some View {
        if let customStatusChip { customStatusChip } else { FeedWorkBadge(work: store.work) }
    }

    /// The floating capsule is the only statement of work when there is nothing to read. Once cards are on
    /// screen the header chip states the same fact, so a second capsule only covers what the reader is reading —
    /// measured on the simulator: "Looking for news" sat on top of the fourth card while the feed was filling.
    @ViewBuilder private var workFeedback: some View {
        if store.renderedItems.isEmpty { FeedWorkFeedback(work: store.work) }
    }

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
                                    // D4: the layout is the evidence. Each laid-out card's own bottom (in the
                                    // scroll view's coordinates, so the list's spacing and the card's slot are
                                    // already inside it) and the viewport height the scroll view measured are what
                                    // `FeedFirstScreenGate` judges. Recorded in every build: it is the decision.
                                    store.noteFirstScreenLayout(cardID: card.id,
                                        contentBottom: proof.frame.maxY, viewportHeight: proof.height)
                                    #if canImport(UIKit)
                                    // The restore point must be adopted before this proof can become a position:
                                    // the first proof of a launch arrives before the viewport's `onChange` runs,
                                    // and publishing it would make a transient layout durable.
                                    capture.adoptRestoration(store.state.presentation?.restoredPosition,
                                        sequenceID: store.state.presentation?.provenance.sequenceID)
                                    // The relative point of a restore is applied to the frame proof the capture
                                    // would otherwise treat as movement; the callback carrying the pre-correction
                                    // geometry is stale by construction.
                                    if capture.applyRestorationIfNeeded(proof) {
                                        return
                                    }
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
                    // instead of stretching editorial text across the window. The cap is the **last** frame:
                    // expanding first and capping second keeps the drawn content inside the column (the reverse
                    // order re-expanded it to the scroll content width: 730.25 pt against 700 on iPad landscape).
                    .frame(maxWidth: .infinity)
                    .frame(maxWidth: FeedDesignTokens.Measurement.readableContentWidth)
                }
                .modifier(NativeFeedViewport(capture: $capture, store: store))
                #if DEBUG && canImport(UIKit)
                .modifier(FeedNativeWindowProof(ids: items.map(\.id), access: capture.nativeScrollOffset, deferredWindows: capture.interaction.deferredWindows))
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
                    .frame(maxWidth: .infinity)
                    .frame(maxWidth: FeedDesignTokens.Measurement.readableContentWidth)
                }
                // T3: work feedback is an overlay of constant height that never takes touches, so the
                // scroll viewport keeps exactly the geometry the reader was admitted into.
                .overlay(alignment: .bottom) { workFeedback }
            }
        } else {
            FeedLoadingView(work: store.work, onTryAgain: { onTryAgain() },
                onAdjustInterests: { onAdjustInterests() }, onChooseSources: { onChooseSources() },
                sourceContextName: sourceContextName)
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
                onReturnToStart: {
                    // P03/A3: this is a position intention like any other. Assigning `capture.positionID` here
                    // bypassed the binding's setter and exposed a released head without preparing its pixels.
                    guard let first = items.first?.id,
                        let presented = capture.interaction.presentation(for: store) else { return }
                    FeedPositionRequest.apply(first, presented: presented, capture: &capture, store: store,
                        explicit: true)
                })
        }
    }
}
