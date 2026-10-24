import SwiftUI
#if DEBUG
import OSLog
#endif
import FeedMineDomain
import FeedMineRuntime

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
    ///
    /// O **offset em que ela foi medida** anda junto porque os dois números juntos distinguem o que moveu a carta:
    /// numa rolagem só o offset anda; num inserto/retirada de conteúdo **acima** dela os dois andam o mesmo tanto —
    /// e é esse segundo caso que envelhece as entradas das cartas que não voltaram a reportar.
    var cardContentTops: [PublicationCardID: (top: CGFloat, offset: CGFloat)] = [:]
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
    /// R04: a destination (programmatic jump or accessibility move) whose pixels are not ready yet. The surface
    /// keeps drawing the current reading and applies this position only when the prepared value carries the pixels.
    /// It is UI state, not a second admission: no window, published card or durable value lives here.
    var pendingJump: PublicationCardID?
    /// The one-shot token that started `pendingJump`. A preparation requested by the binding's echo (`false`) may
    /// apply its prepared value locally, but only the caller that meant a jump may establish the position.
    var pendingJumpExplicit = false
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
            motion.cardContentTops = motion.cardContentTops.filter { $0.value.top >= offset - reach }
        }
        motion.presentedTop = motion.cardContentTops
            .filter { $0.value.top >= offset - 1 }
            .min { $0.value.top < $1.value.top }?.key
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
        if let previous = motion.cardContentTops[proof.cardID] {
            let shift = proof.offset - previous.offset
            let moved = contentTop - previous.top
            if abs(shift) > 0.5, abs(moved - shift) <= 0.5 {
                motion.cardContentTops = motion.cardContentTops.mapValues {
                    (top: $0.top + shift, offset: $0.offset + shift)
                }
                refreshPresentedTop(offset: proof.offset, reach: motion.geometry?.height ?? proof.height)
            }
        }
        motion.cardContentTops[proof.cardID] = (top: contentTop, offset: proof.offset)
        let offset = motion.geometry?.offset ?? proof.offset
        let reach = motion.geometry?.height ?? proof.height
        let aboveTheChoice = motion.presentedTop.flatMap { motion.cardContentTops[$0] }.map { contentTop < $0.top } ?? true
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
