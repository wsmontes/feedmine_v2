import SwiftUI
#if DEBUG
import OSLog
#endif
import FeedMineDomain
import FeedMineRuntime


// Small derived geometry only: no published window, presentation or durable identity owner.
struct FeedVisualGeometry: Equatable {
    let offset: CGFloat
    /// The scroll view's own top content inset. `offset` is `contentOffset + topInset`; the card proofs and the
    /// B05 driver read the viewport at `contentOffset`, i.e. `offset - topInset`. The inset is live: it changed by
    /// ~1.6 pt between two rests of the same Release run, so a captured constant bias drifts.
    let topInset: CGFloat
    let extent: CGFloat
    let height: CGFloat
    let width: CGFloat

    init(offset: CGFloat, extent: CGFloat, height: CGFloat, width: CGFloat = 0, topInset: CGFloat = 0) {
        self.offset = offset
        self.topInset = topInset
        self.extent = extent
        self.height = height
        self.width = width
    }

    /// The line the card proofs and the acceptance driver read: the scroll view's content origin.
    var line: CGFloat { offset - topInset }
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
    /// Onde a linha superior do viewport cai **dentro** da carta escolhida, com a altura medida dela. É o dado que
    /// a borda do card sozinha não carrega: sem ele uma restauração prende a borda ao topo e move o texto.
    var presentedTopOffset: CardTopOffset?
    /// A borda superior de cada carta **no conteúdo** (`frame.minY + offset`), a altura medida e o offset da medida.
    /// É a base da escolha acima; podada ao redor do viewport, porque uma carta a mais de uma tela de distância
    /// nunca é o topo e volta a reportar quando se aproxima.
    ///
    /// O **offset em que ela foi medida** anda junto porque os dois números juntos distinguem o que moveu a carta:
    /// numa rolagem só o offset anda; num inserto/retirada de conteúdo **acima** dela os dois andam o mesmo tanto —
    /// e é esse segundo caso que envelhece as entradas das cartas que não voltaram a reportar.
    var cardContentTops: [PublicationCardID: (top: CGFloat, height: CGFloat, offset: CGFloat)] = [:]
    /// Uma animação programática (não um gesto do leitor) está em curso: nada do que o desenho mostrar enquanto ela
    /// durar é uma posição em repouso.
    var animating = false
    /// A última posição publicada ao host, e a última que o host reconheceu **em repouso**. As duas juntas evitam
    /// duas coisas: submeter uma posição por quadro (um passo de rolagem que não cruza a fronteira de um card não é
    /// uma posição nova) e perder a posição em que o leitor parou (a mesma posição muda de valor quando o desenho
    /// passa ao repouso).
    var publishedPresentedTop: PublicationCardID?
    var publishedPresentedOffset: CardTopOffset?
    var acknowledgedPresentedTop: PublicationCardID?
    var acknowledgedPresentedOffset: CardTopOffset?
    // Diagnóstico apenas: um vetor não verificado nunca é autoridade de direção nem veto global.
    var velocityUnverified = false
    /// The last **fresh** anchor proof (content top and measured height) of the armed restore. Content top is
    /// invariant to scrolling, so this value stays valid across geometry passes and lets the next geometry
    /// observation re-check the point even when the card does not report again. Only fresh proofs update it: a
    /// stale proof carries a content top from a layout that has already moved (measured 2026-10-22: thousands of
    /// points away), and following it oscillates.
    var anchorRestoreContent: (top: CGFloat, height: CGFloat)?
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
    /// R04: a destination (programmatic jump or accessibility move) whose pixels are not ready yet. The surface
    /// keeps drawing the current reading and applies this position only when the prepared value carries the pixels.
    /// It is UI state, not a second admission: no window, published card or durable value lives here.
    var pendingJump: PublicationCardID?
    /// The one-shot token that started `pendingJump`. A preparation requested by the binding's echo (`false`) may
    /// apply its prepared value locally, but only the caller that meant a jump may establish the position.
    var pendingJumpExplicit = false
    /// The relative point a restore must reproduce after `scrollPosition(id:)` aligns the anchor card. Armed only
    /// from a presentation that carried `restoredPosition`; cancelled by a real reader gesture and never re-armed
    /// by a later projection of the same restore.
    var restoration: FeedRestoration?
    /// The projection whose restore point this capture already adopted. A restore target is adopted **once per
    /// projection identity**, synchronously on the first geometry/proof that can report a position — not later from
    /// an `onChange`, which fires after the first card proof has already published a transient position. The same
    /// projection re-delivered (a remount, an unchanged snapshot) never re-arms a target a gesture cancelled.
    private var restorationSequence: UUID?

    struct FeedRestoration: Equatable, Sendable {
        let cardID: PublicationCardID
        let offset: CardTopOffset
    }
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
        motion.presentedTop.map {
            PresentationAnchor(cardID: $0, placement: .top, progress: motion.presentedTopOffset)
        }
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
        // A restauração ainda não convergiu: o que o desenho mostra é a posição de passagem, não uma
        // posição que o leitor segura. Nada dela pode virar durável.
        guard restoration == nil, let anchor = presentedAnchor else { return }
        let atRest = isRenderingAtRest
        let point = anchor.progress
        if motion.publishedPresentedTop == anchor.cardID {
            // Movement inside the same card is not a new position to the host: the latest point is remembered for
            // the rest, and only a rest that has not been acknowledged yet submits. No per-frame actor hop.
            let restPending = atRest && (motion.acknowledgedPresentedTop != anchor.cardID
                || !Self.samePoint(motion.acknowledgedPresentedOffset, point))
            if !restPending {
                motion.publishedPresentedOffset = point
                return
            }
        }
        motion.publishedPresentedTop = anchor.cardID
        motion.publishedPresentedOffset = point
        if atRest {
            motion.acknowledgedPresentedTop = anchor.cardID
            motion.acknowledgedPresentedOffset = point
        }
        host(anchor, atRest)
    }

    private static func samePoint(_ lhs: CardTopOffset?, _ rhs: CardTopOffset?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (lhs?, rhs?):
            return abs(lhs.topDelta - rhs.topDelta) <= CardTopOffset.measurementTolerance
                && abs(lhs.height - rhs.height) <= CardTopOffset.measurementTolerance
        default: return false
        }
    }

    /// Adopts the restore point a presentation carries, before anything this pass can publish. A presentation
    /// without a restore point claims nothing: the restore projections that carry one are the only ones this
    /// capture ever arms from, and the same projection never re-arms a point a gesture cancelled.
    mutating func adoptRestoration(_ position: PresentationAnchor?, sequenceID: UUID?) {
        guard let position, position.progress != nil, let sequenceID,
            restorationSequence != sequenceID else { return }
        restorationSequence = sequenceID
        armRestoration(position)
    }

    /// Arms the one-shot correction only for the relative point the presentation actually carries. A projection
    /// without it never moves the native offset on its own.
    mutating func armRestoration(_ anchor: PresentationAnchor?) {
        guard let anchor, let progress = anchor.progress else { return }
        restoration = FeedRestoration(cardID: anchor.cardID, offset: progress)
        motion.anchorRestoreContent = nil
    }

    /// A real reader intention cancels the restore instead of postponing it until the gesture ends — pushing the
    /// reader back after they moved would be a second, hidden navigation.
    mutating func cancelRestoration() {
        restoration = nil
        motion.anchorRestoreContent = nil
    }

    #if canImport(UIKit)
    /// Keeps the recorded relative point under the viewport after a launch. The current position is derived from
    /// the anchor's invariant content top (`frame.minY + offset`) and the **live** native content origin, never
    /// from the proof's own viewport line: a card proof and the scroll geometry are delivered in different passes,
    /// and a proof can describe a scroll the view has already left (measured 2026-10-22: the proof said the anchor
    /// was at the top while the live offset was 296 pt behind it, so the +22 pt restore landed 274 pt off).
    ///
    /// Freshness and on-screen are the two bounds that matter: an off-screen correction re-bases the lazy layout
    /// and asks for the opposite one (measured ±1.400 to ±6.800 pt alternations), and a stale proof carries a
    /// content top from a layout that has already moved. Layout-quiet is deliberately not a third gate: a card
    /// above can re-base the anchor once, with no further geometry callback to lift the gate, leaving the reader
    /// 435 pt off (measured, deterministic on the 508 pt card 2026-10-22).
    ///
    /// The restore stays armed until the reader takes control — a gesture cancels it outright — because the launch
    /// layout itself adjusts the content offset after the first correction (measured +82.5 pt on 2026-10-22, with
    /// the screen ending 82 pt off). Each anchor proof is one observation of that layout; there is no timer and no
    /// queued delta.
    /// Returns true when a native write happened; the callback carrying this proof is then stale by construction.
    @discardableResult
    mutating func applyRestorationIfNeeded(_ proof: FeedVisualCardGeometry) -> Bool {
        guard let target = restoration, target.cardID == proof.cardID else { return false }
        guard let nativeOffset = nativeScrollOffset.contentOffsetY, !nativeScrollOffset.isAnimatingScroll else {
            return false
        }
        let liveLine = nativeOffset + (motion.geometry?.topInset ?? 0)
        // The proof is usable only when it describes the current scroll state; the content top it carries is
        // meaningless otherwise (measured 2026-10-22: stale proofs carried tops thousands of points away).
        guard abs(proof.offset - liveLine) <= CardTopOffset.measurementTolerance else { return false }
        // And only while the anchor is actually on screen. Correcting an off-screen card changes which lazy cells
        // are realized, which re-bases the anchor's content top, which asks for the opposite correction (measured
        // 2026-10-22: alternating writes of ±1.400 to ±6.800 pt before the reader touched anything).
        guard proof.frame.maxY > 0, proof.frame.minY < proof.height else { return false }
        let contentTop = proof.frame.minY + proof.offset
        // The content top is scroll-invariant; keeping it lets the geometry-only pass re-check the point when the
        // card does not report again.
        motion.anchorRestoreContent = (contentTop, proof.frame.height)
        let minY = contentTop - liveLine
        let (expected, _) = target.offset.restoredTopDelta(forMeasuredHeight: proof.frame.height)
        let delta = minY - expected
        guard abs(delta) > CardTopOffset.measurementTolerance else { return false }
        return nativeScrollOffset.applyRestoration(delta)
    }

    /// Re-checks the armed restore from the last fresh anchor proof when only the scroll geometry moves: the
    /// launch layout adjusts the content offset after the first correction, and the card does not always report
    /// again before the screen comes to rest (measured 2026-10-22: an 80 pt shift after a correct write, with the
    /// test reading the shifted line). The stored content top is scroll-invariant, so pairing it with the live
    /// origin is exact; the write still requires a quiet layout and an on-screen anchor.
    @discardableResult
    mutating func enforceRestoration() -> Bool {
        guard let target = restoration, let stored = motion.anchorRestoreContent else { return false }
        guard let nativeOffset = nativeScrollOffset.contentOffsetY,
            !nativeScrollOffset.isAnimatingScroll else { return false }
        let liveLine = nativeOffset + (motion.geometry?.topInset ?? 0)
        let minY = stored.top - liveLine
        guard minY < stored.height, minY + stored.height > 0 else { return false }
        let (expected, _) = target.offset.restoredTopDelta(forMeasuredHeight: Double(stored.height))
        let delta = minY - expected
        guard abs(delta) > CardTopOffset.measurementTolerance else { return false }
        return nativeScrollOffset.applyRestoration(delta)
    }
    #endif

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
        guard let previous else {
            refreshPresentedTop(offset: next.line, reach: next.height)
            return nil
        }
        guard previous.extent == next.extent, previous.height == next.height, previous.width == next.width else {
            invalidateLayout()
            motion.geometry = next
            // A base da posição **sobrevive** a esta mudança: a extensão muda também quando a janela ganha cartas,
            // e nesse caso as coordenadas de conteúdo das cartas que já estavam medidas estão intactas. Uma carta
            // que o layout desloque corrige a sua própria entrada quando reporta de novo, então a base se
            // auto-corrige; esvaziá-la aqui fazia a escolha do topo recomeçar carta a carta e publicar posições
            // transitórias — medido em B05 (2026-10-14): o cursor durável **regrediu** para um card de cima e o
            // cold start desenhou outra tela.
            refreshPresentedTop(offset: next.line, reach: next.height)
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
        refreshPresentedTop(offset: next.line, reach: next.height)
        return reconsider()
    }

    /// O card em que o **viewport começa** e a linha superior do viewport **dentro dele**, decididos juntos em
    /// coordenadas de conteúdo.
    ///
    /// A escolha é a carta que **contém** a linha do topo (a de maior borda superior entre as que contêm, então a
    /// fronteira `top == offset` vence); quando a linha cai no espaçamento entre cartas, é a primeira carta abaixo
    /// dela. É a identidade que uma restauração consegue honrar junto com o delta — a regra anterior ("primeira
    /// carta a começar dentro do viewport") nomeava a carta **seguinte** sempre que o leitor parava dentro de uma,
    /// e prendê-la ao topo movia o texto em até uma altura de carta. A escolha depende só do conteúdo acumulado e
    /// do offset atual, então repetir o mesmo estado devolve o mesmo par — é isso que impede um repouso de publicar
    /// seis posições diferentes.
    private func refreshPresentedTop(offset: CGFloat, reach: CGFloat) {
        if motion.cardContentTops.count > 64 {
            // Uma carta a mais de um viewport acima do leitor nunca é o topo, e volta a reportar ao se aproximar.
            motion.cardContentTops = motion.cardContentTops.filter { $0.value.top + $0.value.height >= offset - reach }
        }
        let tolerance = CardTopOffset.tolerance
        let chosen: (key: PublicationCardID, entry: (top: CGFloat, height: CGFloat, offset: CGFloat))?
        if let boundary = motion.cardContentTops
            .filter({ $0.value.top <= offset + tolerance
                && $0.value.top + $0.value.height >= offset - tolerance })
            .max(by: { $0.value.top < $1.value.top }) {
            chosen = (boundary.key, boundary.value)
        } else {
            chosen = motion.cardContentTops
                .filter { $0.value.top >= offset - tolerance }
                .min { $0.value.top < $1.value.top }
                .map { ($0.key, $0.value) }
        }
        motion.presentedTop = chosen?.key
        motion.presentedTopOffset = chosen.flatMap { choice in
            CardTopOffset(topDelta: Double(choice.entry.top - offset), height: Double(choice.entry.height))
        }
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
        // **Um inserto (ou uma retirada) de conteúdo acima da leitora move todas as coordenadas abaixo dele — e as
        // cartas que não voltam a reportar ficam com a coordenada velha.** O sinal é a carta que reporta: numa
        // rolagem só o offset anda (a coordenada de conteúdo é imune a ela); num inserto os **dois** andam o mesmo
        // tanto. Aplicar esse mesmo deslocamento ao mapa inteiro realinha as entradas que não foram remedidas, e sem
        // isso a carta verdadeira do topo é descartada pelo filtro (`top >= offset - 1` — a entrada velha herda uma
        // posição acima do viewport), a escolha cai numa carta mais funda e a posição publicada nomeia o que a tela
        // **não** mostra. Medido, e reproduzido no teste determinístico desta rodada: 8 onde a tela mostra 6.
        let previous = motion.cardContentTops[proof.cardID]
        if let previous {
            let shift = proof.offset - previous.offset
            let moved = contentTop - previous.top
            if abs(shift) > 0.5, abs(moved - shift) <= 0.5 {
                motion.cardContentTops = motion.cardContentTops.mapValues {
                    (top: $0.top + shift, height: $0.height, offset: $0.offset + shift)
                }
                refreshPresentedTop(offset: proof.offset, reach: motion.geometry?.height ?? proof.height)
            }
        }
        motion.cardContentTops[proof.cardID] = (top: contentTop, height: proof.frame.height, offset: proof.offset)
        // The line is the scroll view's content origin (the card proof's own line, and the line the B05 driver
        // reads), never `contentOffset + contentInsets.top`: the inset changed by ~1.6 pt between two rests of the
        // same Release run, so a captured constant bias drifted and the durable point stayed ~1.6 pt above the
        // displayed line.
        let line = motion.geometry?.line ?? proof.offset
        let reach = motion.geometry?.height ?? proof.height
        // A carta que **é** a escolha pode ter sido remedida (altura) sem mudar a identidade: o delta relativo
        // acompanha a medição nova mesmo quando nenhuma outra carta entra acima da escolhida.
        if motion.presentedTop == proof.cardID {
            motion.presentedTopOffset = CardTopOffset(topDelta: Double(contentTop - line),
                height: Double(proof.frame.height))
        }
        let choiceTop = motion.presentedTop.flatMap { motion.cardContentTops[$0]?.top }
        // A card enters above the choice (the old rule) **or** it contains the line and starts below the current
        // choice, in which case the containing-card rule makes it the boundary winner.
        let entersAbove = choiceTop.map { contentTop < $0 } ?? true
        let containsLine = contentTop <= line + CardTopOffset.tolerance
            && contentTop + proof.frame.height >= line - CardTopOffset.tolerance
        if containsLine || (contentTop >= line - 1 && entersAbove) {
            refreshPresentedTop(offset: line, reach: reach)
        } else if motion.presentedTop == proof.cardID, !containsLine {
            // The chosen card itself no longer reaches the line (a height change): the choice must be re-derived,
            // never kept on a stale measurement.
            refreshPresentedTop(offset: line, reach: reach)
        }
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
