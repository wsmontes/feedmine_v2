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

/// Contadores de fluxo que o **host** também precisa ler (a instalação é decidida lá). Públicos de propósito,
/// só de diagnóstico: uma janela que não cresce é uma instalação rejeitada a mais.
public enum FeedFlowCounters {
    public nonisolated(unsafe) static var installAttempts = 0
    public nonisolated(unsafe) static var installAccepts = 0
    public nonisolated(unsafe) static var installRejects = 0
}

/// A linha editorial desenhada no **próprio corpo**: o que ela lê (posição do leitor, orçamento de ofertas,
/// preferências) invalida só ela, nunca a lista. A V1 tinha a mesma forma — a linha era uma view dentro da
/// `LazyVStack`. Sem isso, a leitura de posição feita aqui dentro voltava a re-renderizar o feed a cada avanço.
@MainActor
struct EditorialSlot: View {
    private let content: @MainActor () -> AnyView?

    init(content: @escaping @MainActor () -> AnyView?) { self.content = content }

    var body: some View {
        if let content = content() { content }
    }
}

/// Reserved, non-interactive work feedback (T3): constant height, no hit testing, so reporting work can
/// never change the scroll geometry the reader was admitted into.
@MainActor
struct FeedWorkFeedback: View {
    let work: FeedPresentationState.Work
    var body: some View {
        FeedWorkBadge(work: work)
            .frame(height: FeedDesignTokens.Measurement.workFeedbackHeight, alignment: .bottom)
            .allowsHitTesting(false)
    }
}

/// Review M17: work that continues after cards are visible is shown without touching the cards.
struct FeedWorkBadge: View {
    let work: FeedPresentationState.Work
    var body: some View {
        switch work {
        case .pending, .preparing:
            Label("Buscando novidades", systemImage: "arrow.triangle.2.circlepath")
                .modifier(BadgeStyle())
        case .failed(let message):
            Label { Text(verbatim: message) } icon: { Image(systemName: "exclamationmark.triangle") }
                .modifier(BadgeStyle())
        case .idle, .unavailable, .deferred, .unreachable, .endOfContent:
            EmptyView()
        }
    }
}

private struct BadgeStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.font(FeedDesignTokens.Typography.badge)
            .padding(.horizontal, FeedDesignTokens.Spacing.normal)
            .padding(.vertical, FeedDesignTokens.Spacing.compact)
            .background(.thinMaterial, in: Capsule())
            .padding(.bottom, FeedDesignTokens.Spacing.compact)
    }
}

// Small derived geometry only: no published window, presentation or durable identity owner.
struct FeedVisualGeometry: Equatable {
    let offset: CGFloat
    let extent: CGFloat
    let height: CGFloat
    let width: CGFloat

    init(offset: CGFloat, extent: CGFloat, height: CGFloat, width: CGFloat = 0) {
        self.offset = offset
        self.extent = extent
        self.height = height
        self.width = width
    }
}

struct FeedVisualEvent: Equatable {
    let observation: ViewportObservation
    let activity: RunwayActivity
}

// One current visual proof and one borrowed render window for an active interaction.
// The store remains the sole canonical presentation; this never admits or retains history.
struct FeedVisualCardGeometry: Equatable, Sendable {
    let cardID: PublicationCardID
    let frame: CGRect
    let offset: CGFloat
    let height: CGFloat
}

// Internal for behavioral architecture tests; no public navigation contract.
/// O movimento do leitor **por frame**: geometria, provas de carta, direção, offsets confirmados. Uma caixa de
/// referência simples e deliberadamente **não observável**.
///
/// Cada callback de geometria escreve aqui. Enquanto isso vivia no estado observável da view, todo frame sujava o
/// `FeedScreen` e reavaliava a superfície inteira do feed — o "engasgo leve e constante" relatado no aparelho
/// (2026-10-14). É a mesma separação que a V1 fazia: o tick de rolagem dela escrevia em side-state que o corpo da
/// view não lê.
@MainActor
final class FeedVisualMotion {
    var geometry: FeedVisualGeometry?
    var visibleProof: FeedVisualCardGeometry?
    var priorProof: FeedVisualCardGeometry?
    var direction: RunwayActivity?
    var lastEmission: FeedVisualEvent?
    // Cada fluxo contribui com a sua própria direção; os extremos não são sincronizados.
    var geometryMotion: RunwayActivity?
    var cardMotion: RunwayActivity?
    var confirmedOffset: CGFloat?
    var tailOffset: CGFloat?
    var settled = false
    var tailReported = false
    var readerCardID: PublicationCardID?
    /// Onde o **viewport começa**: o card do topo. Ele é escolhido em **coordenadas de conteúdo**, invariantes à
    /// rolagem — duas cartas medidas em passadas diferentes do layout não são comparáveis em coordenadas do
    /// viewport, e foi isso que fez a primeira versão publicar seis posições distintas num único repouso (medido em
    /// B05, 2026-10-14: o cursor terminou num card que não era o do topo da tela).
    var presentedTop: PublicationCardID?
    /// A borda superior de cada carta **no conteúdo** (`frame.minY + offset`), que não se move quando o leitor rola.
    /// É a base da escolha acima; podada ao redor do viewport, porque uma carta a mais de uma tela de distância
    /// nunca é o topo e volta a reportar quando se aproxima.
    var cardContentTops: [PublicationCardID: CGFloat] = [:]
    /// Uma animação programática (não um gesto do leitor) está em curso: nada do que o desenho mostrar enquanto ela
    /// durar é uma posição em repouso.
    var animating = false
    /// A última posição publicada ao host, e a última que o host reconheceu **em repouso**. As duas juntas evitam
    /// duas coisas: submeter uma posição por quadro (um passo de rolagem que não cruza a fronteira de um card não é
    /// uma posição nova) e perder a posição em que o leitor parou (a mesma posição muda de valor quando o desenho
    /// passa ao repouso).
    var publishedPresentedTop: PublicationCardID?
    var acknowledgedPresentedTop: PublicationCardID?
    // Diagnóstico apenas: um vetor não verificado nunca é autoridade de direção nem veto global.
    var velocityUnverified = false
    #if DEBUG
    var geometryLogged = false
    #endif
}

@MainActor
struct FeedVisualCapture {
    #if canImport(UIKit)
    let nativeScrollOffset = FeedNativeScrollOffset()
    #endif
    /// O movimento por frame vive na caixa acima: mutações dela **não** invalidam a view.
    let motion = FeedVisualMotion()
    var interaction = FeedInteractionPresentation()
    var renderOwner: ObjectIdentifier?
    var reading = false
    var positionID: PublicationCardID?
    #if DEBUG
    /// Traço de diagnóstico do capture, **desligado por padrão** (ordem do arquiteto): liga com
    /// `FEEDMINE_TRACE_CAPTURE=1`. A medição de posição precisa dele; a operação normal não paga o custo — uma
    /// corrida de UI com o traço ligado passa de 1,4 milhão de linhas de log.
    static let tracesCapture = ProcessInfo.processInfo.environment["FEEDMINE_TRACE_CAPTURE"] == "1"
    /// Contadores de fluxo: onde a cadeia para quando o leitor rola. Cada um é um portão da emissão de posição.
    nonisolated(unsafe) static var geometryObservations = 0
    nonisolated(unsafe) static var probeEntries = 0
    nonisolated(unsafe) static var probeGuards = 0
    nonisolated(unsafe) static var cardObservations = 0
    nonisolated(unsafe) static var emissions = 0
    nonisolated(unsafe) static var submissions = 0
    nonisolated(unsafe) static var scrollGeometryEvents = 0
    nonisolated(unsafe) static var scrollPhaseEvents = 0
    nonisolated(unsafe) static var scopeRejections = 0

    #endif

    mutating func phase(active: Bool, velocity: CGVector?) {
        if active && !reading {
            motion.geometryMotion = nil
            motion.cardMotion = nil
        }
        reading = active
        motion.velocityUnverified = velocity.map { $0.dx != 0 || $0.dy != 0 } ?? false
        #if DEBUG
        Self.trace("native phase active=\(active) velocityUnverified=\(motion.velocityUnverified) vector=\(String(describing: velocity))")
        #endif
    }

    /// Transient visual position of the reader: one card and how much of it is above the viewport.
    /// UI state only — it never decides admission (the session does) and is never persisted.
    var position: FeedScrollPosition? {
        guard let proof = motion.visibleProof else { return nil }
        return FeedScrollPosition(cardID: proof.cardID, viewportTop: 0, cardTop: proof.frame.minY,
            cardHeight: proof.height)
    }

    /// Onde o **viewport desenhado começa**, na forma que uma restauração honra exatamente: o primeiro card cuja
    /// borda superior está dentro do viewport, preso à borda de cima. É a posição que o host publica e grava — nunca
    /// pixels, e nunca o card em que o leitor *está* (esse não determina o viewport).
    var presentedAnchor: PresentationAnchor? {
        motion.presentedTop.map { PresentationAnchor(cardID: $0, placement: .top) }
    }

    /// O repouso semântico do próprio desenho: nenhum gesto em curso, nenhum hold emprestado, nenhuma animação
    /// programática e nenhuma correção de offset em curso. É o fato que deixa uma posição distinta virar durável.
    var isRenderingAtRest: Bool {
        guard !reading, !interaction.isHolding, !motion.animating else { return false }
        #if canImport(UIKit)
        return !nativeScrollOffset.isCorrecting && !nativeScrollOffset.isAnimatingScroll
        #else
        return true
        #endif
    }

    /// Diz ao host onde o viewport começa — quando a posição **muda**, e quando ela é a mesma mas chegou ao
    /// **repouso**. Fora desses dois casos não há submissão: um passo de rolagem que não cruza a fronteira de um card
    /// não é uma posição nova, e uma submissão por quadro custaria um salto de ator por quadro no caminho de
    /// renderização (o mesmo custo que a lista deixou de pagar por avanço, 2026-10-14).
    func reportPresentedPosition(to host: @MainActor (PresentationAnchor, Bool) -> Void) {
        guard let anchor = presentedAnchor else { return }
        let atRest = isRenderingAtRest
        if motion.publishedPresentedTop == anchor.cardID,
            !atRest || motion.acknowledgedPresentedTop == anchor.cardID { return }
        motion.publishedPresentedTop = anchor.cardID
        if atRest { motion.acknowledgedPresentedTop = anchor.cardID }
        host(anchor, atRest)
    }

    func invalidateLayout() {
        motion.geometry = nil
        motion.visibleProof = nil
        motion.priorProof = nil
        motion.geometryMotion = nil
        motion.cardMotion = nil
        motion.confirmedOffset = nil
        motion.tailOffset = nil
        motion.settled = false
        motion.tailReported = false
        // A base da posição do viewport **não** é descartada aqui: `invalidateLayout` também é chamado quando uma
        // janela muda ou um gesto começa, e em nenhum desses casos as coordenadas de conteúdo das cartas deixaram de
        // valer. Quem a descarta é a única coisa que as invalida: uma mudança real de layout (ver `observe`).
        #if DEBUG
        motion.geometryLogged = false
        #endif
    }

    func observe(_ next: FeedVisualGeometry) -> FeedVisualEvent? {
        #if DEBUG
        Self.geometryObservations += 1
        if !motion.geometryLogged {
            Self.trace("native geometry offset=\(next.offset) extent=\(next.extent) height=\(next.height)")
            motion.geometryLogged = true
        }
        #endif
        let previous = motion.geometry
        motion.geometry = next
        guard let previous else { refreshPresentedTop(offset: next.offset, reach: next.height); return nil }
        guard previous.extent == next.extent, previous.height == next.height, previous.width == next.width else {
            invalidateLayout()
            motion.geometry = next
            // A base da posição **sobrevive** a esta mudança: a extensão muda também quando a janela ganha cartas,
            // e nesse caso as coordenadas de conteúdo das cartas que já estavam medidas estão intactas. Uma carta
            // que o layout desloque corrige a sua própria entrada quando reporta de novo, então a base se
            // auto-corrige; esvaziá-la aqui fazia a escolha do topo recomeçar carta a carta e publicar posições
            // transitórias — medido em B05 (2026-10-14): o cursor durável **regrediu** para um card de cima e o
            // cold start desenhou outra tela.
            refreshPresentedTop(offset: next.offset, reach: next.height)
            return nil
        }
        if next.offset != previous.offset {
            motion.confirmedOffset = nil
            if reading {
                motion.geometryMotion = next.offset > previous.offset ? .forward : .backward
            } else {
                motion.geometryMotion = nil
                motion.cardMotion = nil
            }
        }
        refreshPresentedTop(offset: next.offset, reach: next.height)
        return reconsider()
    }

    /// O card em que o **viewport começa**, decidido em coordenadas de conteúdo: o de menor borda superior entre os
    /// que começam dentro do viewport (a mesma regra da aceitação, com a mesma tolerância de um ponto). A escolha
    /// depende só do conteúdo acumulado e do offset atual, então repetir o mesmo estado devolve o mesmo card — é
    /// isso que impede um repouso de publicar seis posições diferentes.
    private func refreshPresentedTop(offset: CGFloat, reach: CGFloat) {
        if motion.cardContentTops.count > 64 {
            // Uma carta a mais de um viewport acima do leitor nunca é o topo, e volta a reportar ao se aproximar.
            motion.cardContentTops = motion.cardContentTops.filter { $0.value >= offset - reach }
        }
        motion.presentedTop = motion.cardContentTops
            .filter { $0.value >= offset - 1 }
            .min { $0.value < $1.value }?.key
    }

    func observeCard(_ proof: FeedVisualCardGeometry, isLast: Bool = false) -> FeedVisualEvent? {
        #if DEBUG
        Self.cardObservations += 1
        // Traço por carta e por leitura, com o id, **só com a flag de diagnóstico ligada**: a coordenada de conteúdo
        // (`frameY + offset`) é imune ao gesto, então uma descontinuidade nela é o deslocamento causado pela
        // ATUALIZAÇÃO da janela — a referência que o arquiteto definiu, medida sem estimar alturas.
        if Self.tracesCapture {
            Self.trace("native card observed id=\(proof.cardID.rawValue.uuidString) frameY=\(proof.frame.minY) "
                + "offset=\(proof.offset) height=\(proof.height)")
        }
        #endif
        let intersects = proof.frame.height > 0 && proof.frame.maxY > 0 && proof.frame.minY < proof.height
        if isLast { motion.tailOffset = intersects ? proof.offset : nil }
        // **Onde o viewport começa.** A carta entra na base com a sua borda superior **no conteúdo**
        // (`frame.minY + offset`), que a rolagem não move: é o que torna as cartas comparáveis entre passadas
        // diferentes do layout. A escolha em si só pode mudar quando a carta medida entra acima da escolhida, e as
        // duas decisões são O(1) — a lista de topo é lida uma vez por mudança de geometria do scroll, não por carta.
        let contentTop = proof.frame.minY + proof.offset
        motion.cardContentTops[proof.cardID] = contentTop
        let offset = motion.geometry?.offset ?? proof.offset
        let reach = motion.geometry?.height ?? proof.height
        let aboveTheChoice = motion.presentedTop.flatMap { motion.cardContentTops[$0] }.map { contentTop < $0 } ?? true
        if contentTop >= offset - 1, aboveTheChoice { refreshPresentedTop(offset: offset, reach: reach) }
        if let old = motion.priorProof, old.cardID == proof.cardID {
            let stable = old.frame.size == proof.frame.size && old.height == proof.height &&
                abs((old.frame.minY + old.offset) - (proof.frame.minY + proof.offset)) <= 0.5
            if !stable {
                motion.confirmedOffset = nil
                motion.geometryMotion = nil
                motion.cardMotion = nil
            } else if old.frame.minY != proof.frame.minY, reading || motion.geometryMotion != nil {
                motion.cardMotion = proof.frame.minY < old.frame.minY ? .forward : .backward
            }
        }
        // Only one actual reference card; its invariant content coordinate distinguishes layout.
        let reference = min(proof.height / 2, max(0, (motion.geometry?.extent ?? proof.height) - proof.offset - 16.5))
        if intersects, proof.frame.minY - 8 <= reference, proof.frame.maxY + 8 > reference {
            motion.priorProof = proof
            motion.visibleProof = proof
        } else if motion.visibleProof?.cardID == proof.cardID {
            motion.visibleProof = nil
        }
        return reconsider()
    }

    func settle() -> FeedVisualEvent? {
        guard !reading, !motion.settled, let old = motion.lastEmission, old.activity != .stationary,
            let geometry = motion.geometry, motion.confirmedOffset == geometry.offset,
            let proof = motion.visibleProof, proof.cardID == old.observation.anchor.cardID,
            proof.height == geometry.height else { return nil }
        let event = FeedVisualEvent(observation: old.observation, activity: .stationary)
        motion.lastEmission = event
        motion.readerCardID = event.observation.anchor.cardID
        motion.settled = true
        #if DEBUG
        Self.trace("semantic viewport emitted activity=stationary anchor=\(proof.cardID)")
        #endif
        return event
    }

    func reconsider() -> FeedVisualEvent? {
        guard let geometry = motion.geometry else { return nil }
        if let global = motion.geometryMotion, let visual = motion.cardMotion, global == visual {
            motion.direction = global
            motion.confirmedOffset = geometry.offset
            motion.settled = false
            motion.tailReported = false
            motion.geometryMotion = nil
            motion.cardMotion = nil
        }
        guard let direction = motion.direction, motion.confirmedOffset == geometry.offset,
            let proof = motion.visibleProof, proof.height == geometry.height else { return nil }
        // A late tail may upgrade the same anchor. An older tail cannot upgrade a newer anchor.
        let tailVisible = motion.tailOffset.map { $0 >= proof.offset } ?? false
        let activity: RunwayActivity = direction == .forward &&
            (tailVisible || geometry.offset + geometry.height >= geometry.extent)
            ? .explicitTailApproach : direction
        if motion.settled {
            guard activity == .explicitTailApproach, !motion.tailReported,
                proof.cardID == motion.lastEmission?.observation.anchor.cardID else { return nil }
        }
        if activity == .explicitTailApproach { motion.tailReported = true }
        let event = FeedVisualEvent(observation: .init(anchor: .init(cardID: proof.cardID, placement: .center)), activity: activity)
        guard event != motion.lastEmission else { return nil }
        #if DEBUG
        Self.emissions += 1
        #endif
        motion.lastEmission = event
        motion.readerCardID = event.observation.anchor.cardID
        #if DEBUG
        Self.trace("semantic viewport emitted activity=\(activity) anchor=\(proof.cardID)")
        #endif
        return event
    }

    #if DEBUG
    private static func trace(_ value: String) {
        Logger(subsystem: "com.feedmine.development", category: "native-capture").info("\(value, privacy: .public)")
    }
    #endif

}

@available(iOS 18, macOS 15, *)
private struct NativeFeedViewport: ViewModifier {
    @Binding var capture: FeedVisualCapture
    let store: FeedScreenStore

    /// A apresentação que a posição **segue**: a janela segurada enquanto um gesto está em curso, e a publicada
    /// fora dele — a mesma leitura que a lista fazia antes do desacoplamento, agora lida **dentro** do modificador
    /// (assim um avanço reavalia este modificador, barato, e não o corpo da lista, que é o desenho dos itens).
    ///
    /// Não trocar por `store.state.presentation`. Com o valor publicado aqui, o teste de escopo
    /// (`presentation(for:)?.window == presented.window`) passa a comparar a janela **segurada** com a **publicada**:
    /// a primeira atualização de janela que chega durante o gesto torna o escopo falso para sempre, e a saída do
    /// hold (ramo `phase == .idle`) mora atrás desse mesmo guard — medido no simulador em 2026-10-14: 8 flings
    /// rápidos produziram 1 avanço e nenhuma mudança da lista desenhada.
    private var presented: FeedPresentationSnapshot? { capture.interaction.presentation(for: store) }

    private var matchesScope: Bool {
        guard let current = store.state.presentation, let presented else { return false }
        return capture.renderOwner == ObjectIdentifier(store) &&
            capture.interaction.presentation(for: store)?.window == presented.window &&
            current.contextKey == presented.contextKey && current.editionID == presented.editionID &&
            current.provenance.sequenceID == presented.provenance.sequenceID
    }

    // Card bounds use the container viewport; visibleRect may also include safe-area insets.
    private func visualGeometry(_ geometry: ScrollGeometry) -> FeedVisualGeometry {
        .init(offset: geometry.contentOffset.y + geometry.contentInsets.top,
            extent: geometry.contentSize.height,
            height: geometry.containerSize.height,
            width: geometry.containerSize.width)
    }

    func body(content: Content) -> some View {
        return content
            .id(store.state.presentation?.editionID)
            .id(store.state.presentation?.contextKey)
            // A restauração honra a colocação que o registro carrega: o `scrollPosition` sem âncora alinha o card
            // identificado à borda de **cima** do viewport (medido duas vezes em 2026-10-14: o card da âncora
            // pousou com a borda superior exatamente na borda do viewport), que é o que a colocação `.top` — a
            // única que o registro durável agora escreve — significa. Uma linha antiga (`.center`, o card do leitor)
            // continua pousando presa no topo, exatamente como o build anterior fazia, e o próximo repouso a
            // reescreve como `.top`. Não passar uma âncora explícita é deliberado: com `anchor: .top` o SwiftUI
            // re-alinha o card identificado a cada mutação de janela, e a posição visível do leitor anda — medido em
            // `Tests/ArchitectureSmokeTests/FeedViewportCaptureTests.testNativeHostedLayoutPreservesPositionWithoutInventingReading`
            // (440 -> 369) quando a âncora explícita foi tentada.
            .scrollPosition(id: Binding(get: {
                capture.positionID ?? presented?.window.anchor.cardID
            }, set: { id in
                guard matchesScope, let id, presented?.window.items.contains(where: { $0.id == id }) == true else { return }
                capture.positionID = id
                capture.motion.readerCardID = id
            }))
            .onScrollPhaseChange { oldPhase, phase, context in
                #if DEBUG
                FeedVisualCapture.scrollPhaseEvents += 1
                #endif
                // Uma animação programática não é um gesto do leitor: enquanto ela corre, o desenho não está em
                // repouso e nada do que ele mostrar no meio vira posição durável.
                capture.motion.animating = phase == .animating
                guard matchesScope else { return }
                #if DEBUG
                if FeedVisualCapture.tracesCapture {
                    Logger(subsystem: "com.feedmine.development", category: "native-capture").info("native SwiftUI phase=\(String(describing: oldPhase), privacy: .public)->\(String(describing: phase), privacy: .public)")
                }
                #endif
                if phase != .idle {
                    capture.interaction.begin(presented, owner: ObjectIdentifier(store))
                } else {
                    let reader = capture.position?.cardID ?? capture.motion.readerCardID
                    if capture.interaction.isHolding, let reader, let presented, let current = store.state.presentation,
                        !current.window.items.contains(where: { $0.id == reader }) {
                        store.submitViewport(.init(anchor: .init(cardID: reader, placement: .top)),
                            activity: .stationary, rendered: presented, reconciliation: true)
                    }
                    capture.interaction.end(afterReading: reader, store: store)
                }
                store.setReadingInteractionActive(phase != .idle || capture.interaction.isHolding)
                #if canImport(UIKit)
                capture.nativeScrollOffset.setInteractionActive(phase != .idle)
                #endif
                let wasReading = oldPhase == .interacting || oldPhase == .decelerating
                let isReading = phase == .interacting || phase == .decelerating
                #if canImport(UIKit)
                if phase == .tracking { capture.nativeScrollOffset.cancel(discardingSamples: false) }
                else if capture.nativeScrollOffset.isCorrecting {
                    capture.reading = isReading
                    capture.invalidateLayout()
                    _ = capture.observe(visualGeometry(context.geometry))
                    return
                }
                #endif
                if (!wasReading && isReading) || phase == .animating || phase == .tracking {
                    capture.invalidateLayout()
                }
                capture.phase(active: (wasReading || isReading) && phase != .animating && phase != .tracking, velocity: context.velocity)
                let geometry = context.geometry
                if let event = capture.observe(visualGeometry(geometry)) {
                    store.submitViewport(event.observation, activity: event.activity, rendered: presented)
                }
                capture.reading = isReading
                if phase == .animating || phase == .tracking { capture.invalidateLayout() }
                if phase == .idle, let event = capture.settle() {
                    store.submitViewport(event.observation, activity: event.activity, rendered: presented)
                }
                if phase == .idle {
                    // A chegada ao repouso é o momento em que a posição do viewport passa a ser uma posição que o
                    // leitor realmente segura — **inclusive** quando a tela se moveu sem gesto nenhum (uma rolagem
                    // de acessibilidade, uma animação do sistema): o host a grava pelo mesmo dono do cursor.
                    capture.reportPresentedPosition { anchor, atRest in
                        store.publishPresentedPosition(anchor, atRest: atRest)
                    }
                }
            }
            .onScrollGeometryChange(for: FeedVisualGeometry.self, of: { geometry in
                visualGeometry(geometry)
            }) { _, geometry in
                #if DEBUG
                FeedVisualCapture.scrollGeometryEvents += 1
                #endif
                guard matchesScope else {
                    #if DEBUG
                    FeedVisualCapture.scopeRejections += 1
                    #endif
                    return
                }
                #if canImport(UIKit)
                if capture.nativeScrollOffset.isCorrecting {
                    capture.invalidateLayout()
                    _ = capture.observe(geometry)
                    return
                }
                #endif
                if let event = capture.observe(geometry) {
                    store.submitViewport(event.observation, activity: event.activity, rendered: presented)
                }
                // Toda mudança da geometria do scroll é um movimento do viewport — inclusive os que **nenhum gesto**
                // produziu (uma rolagem de acessibilidade, uma re-layout do sistema, uma animação programática). A
                // posição onde o viewport começa é publicada aqui: em movimento o dono do cursor só a lembra, e no
                // repouso ela vira escrita. Sem isto, o leitor que morre depois de uma dessas volta a uma posição
                // que já tinha deixado (medido em B05, 2026-10-14: oito cards atrás da tela que o driver mediu).
                capture.reportPresentedPosition { anchor, atRest in
                    store.publishPresentedPosition(anchor, atRest: atRest)
                }
            }
            .onChange(of: presented?.window) { old, new in
                // A new layout must establish a fresh viewport proof. Native offset correction
                // is handled independently, before card geometry becomes a reader event.
                capture.invalidateLayout()
            }
            .onChange(of: store.state.presentation?.window) { _, _ in
                capture.interaction.noteIncoming(store)
            }
            .onChange(of: ObjectIdentifier(store), initial: true) { _, _ in
                capture.renderOwner = ObjectIdentifier(store)
            }
            .onDisappear {
                guard matchesScope else { return }
                capture.interaction.end()
                store.setReadingInteractionActive(false)
                #if canImport(UIKit)
                capture.nativeScrollOffset.setInteractionActive(false)
                capture.nativeScrollOffset.cancel()
                #endif
            }
            .onChange(of: ObjectIdentifier(store)) { _, _ in
                capture = FeedVisualCapture()
                capture.renderOwner = ObjectIdentifier(store)
                store.setReadingInteractionActive(false)
            }
            .onChange(of: store.state.presentation?.editionID) { _, _ in
                capture = FeedVisualCapture()
                capture.renderOwner = ObjectIdentifier(store)
                store.setReadingInteractionActive(false)
            }
            .onChange(of: store.state.presentation?.contextKey) { _, _ in
                capture = FeedVisualCapture()
                capture.renderOwner = ObjectIdentifier(store)
                store.setReadingInteractionActive(false)
            }
    }
}

@available(iOS 18, macOS 15, *)
private struct NativeFeedTargets: ViewModifier {
    func body(content: Content) -> some View {
        content.scrollTargetLayout().padding().coordinateSpace(name: "feed-visual-content")
    }
}
