import XCTest
import SwiftUI
import FeedMineDomain
@testable import FeedMineRuntime
@testable import FeedMinePublication
import FeedMinePersistence
#if os(macOS)
import AppKit
#endif
@testable import FeedMineUI

@MainActor
final class FeedViewportCaptureTests: XCTestCase {
    func testBorrowedRenderWaitsForActualReaderAndRejectsAnotherOwner() throws {
        let ids = (0..<9).map { _ in PublicationCardID() }
        let cards = try ids.map { id in
            PresentationCard(publishedCard: try XCTUnwrap(PublishedCard(id: id,
                origin: .init(originRecordID: OriginRecordID(), originRevisionID: OriginRevisionID(),
                    sourceID: nil, providerID: nil, sourceDisplayName: nil, providerDisplayName: nil),
                contentEntityID: nil, contentClusterID: nil, text: .init(title: "Local", primaryText: "Text"),
                timestamp: nil, media: .none, renderContract: XCTUnwrap(RenderContract(layout: .textOnly,
                    mediaAspectRatio: nil)), primaryAction: nil)))
        }
        let edition = FeedEditionID(), sequence = UUID()
        func snapshot(_ range: Range<Int>, position: UInt64) throws -> FeedPresentationSnapshot {
            .init(contextKey: FeedContext(request: .main).key, editionID: edition,
                window: try XCTUnwrap(FeedWindowSnapshot(items: Array(cards[range]),
                    anchor: .init(cardID: ids[range.lowerBound], placement: .center))),
                provenance: .init(sequenceID: sequence, position: position))
        }
        let first = try snapshot(0..<5, position: 1), moved = try snapshot(2..<9, position: 2)
        let store = FeedScreenStore { _, _ in }
        try store.install(.init(presentation: first))
        var render = FeedInteractionPresentation()
        render.begin(first, owner: ObjectIdentifier(store))
        store.setReadingInteractionActive(true)
        try store.install(.init(presentation: moved))
        render.noteIncoming(store)
        XCTAssertEqual(render.presentation(for: store), first)
        XCTAssertEqual(render.deferredWindows, 1)
        render.end(afterReading: ids[0], store: store)
        XCTAssertTrue(render.isHolding, "Do not drop the real rendered reader before Runtime acknowledgement")
        let acknowledged = try snapshot(0..<7, position: 3)
        try store.install(.init(presentation: acknowledged))
        render.noteIncoming(store)
        XCTAssertFalse(render.isHolding)
        XCTAssertFalse(store.isReadingInteractionActive)
        XCTAssertEqual(render.presentation(for: store), acknowledged)
        render.begin(acknowledged, owner: ObjectIdentifier(store))
        let other = FeedScreenStore { _, _ in }
        try other.install(.init(presentation: moved))
        XCTAssertEqual(render.presentation(for: other), moved)
        render.noteIncoming(other)
        XCTAssertFalse(render.isHolding)
    }

    func testNativeWindowWitnessIsBoundedAndCapturedBeforeTheNewLayout() {
        var correction = FeedWindowOffsetCorrection()
        let ids = (0..<30).map { _ in PublicationCardID() }
        correction.updateWindow(Array(ids[0..<3]))
        _ = correction.observe(.init(cardID: ids[1],
            frame: CGRect(x: 0, y: 200, width: 300, height: 400), offset: 100, height: 800))
        correction.updateWindow(Array(ids[1..<4]))
        let delta = correction.observe(.init(cardID: ids[1],
            frame: CGRect(x: 0, y: -10, width: 300, height: 400), offset: 150, height: 800))
        XCTAssertEqual(delta, -160)
        for start in 2..<27 {
            correction.updateWindow(Array(ids[start..<(start + 3)]))
            for id in ids[start..<(start + 3)] {
                _ = correction.observe(.init(cardID: id,
                    frame: CGRect(x: 0, y: 200, width: 300, height: 400), offset: 100, height: 800))
            }
            XCTAssertLessThanOrEqual(correction.retainedCount, 3)
        }
    }
    func testReprojectionAndNewGestureDiscardStaleCorrection() {
        var correction = FeedWindowOffsetCorrection()
        let a = PublicationCardID(), b = PublicationCardID()
        correction.updateWindow([a])
        let before = FeedVisualCardGeometry(cardID: a,
            frame: CGRect(x: 0, y: 200, width: 300, height: 400), offset: 100, height: 800)
        _ = correction.observe(before)
        correction.updateWindow([a])
        XCTAssertNil(correction.observe(before))
        correction.updateWindow([a, b])
        correction.cancel()
        XCTAssertNil(correction.observe(.init(cardID: a,
            frame: CGRect(x: 0, y: 40, width: 300, height: 400), offset: 100, height: 800)))
    }

    func testWindowCorrectionIgnoresPureScrollingAndChangedViewport() {
        var correction = FeedWindowOffsetCorrection()
        let a = PublicationCardID(), b = PublicationCardID(), c = PublicationCardID()
        correction.updateWindow([a])
        _ = correction.observe(.init(cardID: a,
            frame: CGRect(x: 0, y: 200, width: 300, height: 400), offset: 100, height: 800))
        correction.updateWindow([a, b])
        XCTAssertNil(correction.observe(.init(cardID: a,
            frame: CGRect(x: 0, y: 150, width: 300, height: 400), offset: 150, height: 800)))
        correction.updateWindow([a, b, c])
        XCTAssertNil(correction.observe(.init(cardID: a,
            frame: CGRect(x: 0, y: 100, width: 600, height: 400), offset: 150, height: 400)))
    }

    /// PO 2026-10-14: a captura relata **onde o viewport começa** — o primeiro card cuja borda superior está dentro
    /// do viewport —, e não (só) o card em que o leitor está: é esse card do topo que a durabilidade grava, porque é
    /// ele que uma restauração reproduz exatamente. A escolha é feita em **coordenadas de conteúdo**, invariantes à
    /// rolagem: comparar bordas medidas no viewport, em passadas diferentes do layout, foi o defeito medido em B05
    /// (2026-10-14) — seis posições distintas num único repouso, e o cursor terminando num card que não era o topo.
    func testPresentedTopIsTheFirstCardStartingInsideTheViewport() {
        var capture = FeedVisualCapture()
        let above = PublicationCardID(), top = PublicationCardID(), below = PublicationCardID()
        // Conteúdo: cada carta ocupa 400 de altura, e o viewport começa no conteúdo 120.
        _ = capture.observe(.init(offset: 120, extent: 2_000, height: 800))
        capture.observeCard(.init(cardID: above,
            frame: .init(x: 0, y: -120, width: 400, height: 200), offset: 120, height: 800))
        XCTAssertNil(capture.presentedAnchor, "uma carta que começa acima da borda não é o card do topo")
        capture.observeCard(.init(cardID: top,
            frame: .init(x: 0, y: 280, width: 400, height: 200), offset: 120, height: 800))
        XCTAssertEqual(capture.presentedAnchor, PresentationAnchor(cardID: top, placement: .top))
        capture.observeCard(.init(cardID: below,
            frame: .init(x: 0, y: 680, width: 400, height: 200), offset: 120, height: 800))
        XCTAssertEqual(capture.presentedAnchor?.cardID, top, "cartas abaixo nunca substituem o topo")
        // Rolar não move o conteúdo: a escolha passa a ser a próxima carta que começa dentro do viewport.
        _ = capture.observe(.init(offset: 600, extent: 2_000, height: 800))
        XCTAssertEqual(capture.presentedAnchor, PresentationAnchor(cardID: below, placement: .top))
        // Uma mudança de geometria — a janela ganha cartas, ou o layout muda — **não** esvazia a base: as
        // coordenadas de conteúdo das cartas já medidas continuam válidas, e cada carta corrige a sua própria
        // entrada quando o layout a desloca.
        _ = capture.observe(.init(offset: 600, extent: 2_100, height: 800))
        XCTAssertEqual(capture.presentedAnchor, PresentationAnchor(cardID: below, placement: .top))
        // E uma carta que o layout subiu para dentro do viewport passa a ser a escolha: a sua própria entrada
        // corrigida é o que a base usa, sem ninguém precisar esvaziá-la.
        capture.observeCard(.init(cardID: top,
            frame: .init(x: 0, y: 10, width: 400, height: 200), offset: 600, height: 800))
        XCTAssertEqual(capture.presentedAnchor, PresentationAnchor(cardID: top, placement: .top))
    }


    /// **Teste decisivo da sonda de 2026-10-14** (lead): uma janela cuja **cabeça cresce acima da escolha**, com a
    /// carta acima que **não** volta a reportar — e o `gap` que isso produz.
    ///
    /// A forma é a medida no B05: a carta do topo (posição 6) e a de baixo dela não voltam a ser medidas, a carta
    /// mais funda (posição 8) sim, e a geometria muda de forma (a extensão cresceu com o inserto). O filtro do
    /// topo (`top >= offset - 1`) descarta a entrada **velha** da verdadeira carta do topo — ela parece acima do
    /// viewport —, e a escolha cai na carta mais funda: 8 onde a tela mostra 6, duas cartas fora.
    func testWindowHeadThatGrowsAboveTheChoiceMustNotMoveThePresentedTop() {
        var capture = FeedVisualCapture()
        // Layout 1: a leitora no topo da carta A (posição 6), com B e C abaixo. Cada linha ocupa 190 pt.
        _ = capture.observe(.init(offset: 0, extent: 1_000, height: 800))
        let above = PublicationCardID(), a = PublicationCardID(), b = PublicationCardID(), c = PublicationCardID()
        capture.observeCard(.init(cardID: above, frame: .init(x: 0, y: -190, width: 400, height: 190), offset: 0, height: 800))
        capture.observeCard(.init(cardID: a, frame: .init(x: 0, y: 0, width: 400, height: 190), offset: 0, height: 800))
        capture.observeCard(.init(cardID: b, frame: .init(x: 0, y: 190, width: 400, height: 190), offset: 0, height: 800))
        capture.observeCard(.init(cardID: c, frame: .init(x: 0, y: 380, width: 400, height: 190), offset: 0, height: 800))
        XCTAssertEqual(capture.presentedAnchor, PresentationAnchor(cardID: a, placement: .top),
            "a verdade: o viewport começa na carta A")
        // Layout 2: a cabeça cresce 380 pt (duas linhas acima de A). O desenho mantém a leitora no lugar, então o
        // offset do conteúdo vai a 380 e as coordenadas de **todas** as cartas abaixo do inserto andam 380.
        // `above` e `a` **não** voltam a reportar; `c` reporta (a coordenada dela e o offset andaram juntos).
        _ = capture.observe(.init(offset: 380, extent: 1_380, height: 800))
        capture.observeCard(.init(cardID: c, frame: .init(x: 0, y: 380, width: 400, height: 190), offset: 380, height: 800))
        XCTAssertEqual(capture.presentedAnchor, PresentationAnchor(cardID: a, placement: .top),
            "a carta do topo continua sendo A: uma carta que não voltou a ser medida não pode virar a escolha só porque o inserto acima dela envelheceu a coordenada guardada")
    }

    /// O repouso semântico do desenho: nenhum gesto, nenhum hold emprestado, nenhuma animação programática. É ele
    /// que deixa uma posição **distinta** do viewport virar durável na hora — e uma animação do sistema não é
    /// repouso, por mais que o leitor não esteja tocando a tela.
    func testInterruptedNativeMotionDropsStaleSignalsWithoutLosingPosition() {
        let id = PublicationCardID()
        for wasAnimating in [false, true] {
            var capture = FeedVisualCapture()
            capture.positionID = id
            capture.motion.readerCardID = id
            capture.motion.presentedTop = id
            capture.motion.publishedPresentedTop = id
            capture.motion.acknowledgedPresentedTop = id
            capture.reading = !wasAnimating
            capture.motion.animating = wasAnimating
            capture.motion.direction = .forward
            capture.motion.lastEmission = FeedVisualEvent(
                observation: .init(anchor: .init(cardID: id, placement: .center)), activity: .forward)
            capture.motion.geometry = .init(offset: 120, extent: 2_000, height: 800)
            capture.motion.visibleProof = .init(cardID: id,
                frame: .init(x: 0, y: 0, width: 400, height: 200), offset: 120, height: 800)
            capture.motion.velocityUnverified = true

            capture.interruptTransientMotion()

            XCTAssertFalse(capture.reading)
            XCTAssertFalse(capture.motion.animating)
            XCTAssertNil(capture.motion.direction, "a future gesture must prove its own direction")
            XCTAssertNil(capture.motion.lastEmission, "a future gesture must not reuse a pre-dismissal event")
            XCTAssertNil(capture.motion.geometry, "the returning screen must provide fresh geometry")
            XCTAssertNil(capture.motion.visibleProof, "a stale card sample is not evidence after return")
            XCTAssertFalse(capture.motion.velocityUnverified)
            XCTAssertEqual(capture.positionID, id, "a modal must not reset the visible scroll target")
            XCTAssertEqual(capture.motion.readerCardID, id)
            XCTAssertEqual(capture.presentedAnchor, PresentationAnchor(cardID: id, placement: .top))
            var repeated: [(PresentationAnchor, Bool)] = []
            capture.reportPresentedPosition { repeated.append(($0, $1)) }
            XCTAssertTrue(repeated.isEmpty, "an already acknowledged position is not checkpointed again")
        }
    }

    func testTheRenderingIsAtRestOnlyWithoutAGestureOrAProgrammaticAnimation() {
        var capture = FeedVisualCapture()
        XCTAssertTrue(capture.isRenderingAtRest)
        capture.reading = true
        XCTAssertFalse(capture.isRenderingAtRest, "um gesto em curso não é repouso")
        capture.reading = false
        capture.motion.animating = true
        XCTAssertFalse(capture.isRenderingAtRest, "uma animação programática não é repouso")
        capture.motion.animating = false
        XCTAssertTrue(capture.isRenderingAtRest)
    }

    /// A posição é dita **quando muda** e **uma vez por repouso**: um passo de rolagem que não cruza a fronteira de
    /// um card não é uma posição nova, e a posição em que o leitor parou ainda precisa ser dita em repouso — é ela
    /// que vira escrita, e uma posição dita só em movimento não é gravada.
    func testPresentedPositionIsReportedOnChangeAndOncePerRest() {
        var capture = FeedVisualCapture()
        var events: [(PresentationAnchor, Bool)] = []
        let first = PublicationCardID(), second = PublicationCardID()
        capture.motion.presentedTop = first
        capture.reportPresentedPosition { events.append(($0, $1)) }
        XCTAssertEqual(events.map(\.1), [true], "em repouso, uma posição nova é dita na hora")
        capture.reportPresentedPosition { events.append(($0, $1)) }
        XCTAssertEqual(events.count, 1, "a mesma posição em repouso não é dita duas vezes")
        // Um gesto em curso: a posição nova é dita como um fato que ainda **não** está em repouso.
        capture.reading = true
        capture.motion.presentedTop = second
        capture.reportPresentedPosition { events.append(($0, $1)) }
        XCTAssertEqual(events.map(\.1), [true, false], "em movimento a posição não é um repouso")
        // E o repouso na mesma posição ainda é dito: é ele que faz a escrita.
        capture.reading = false
        capture.reportPresentedPosition { events.append(($0, $1)) }
        XCTAssertEqual(events.map(\.1), [true, false, true])
        XCTAssertEqual(events.map(\.0), [PresentationAnchor(cardID: first, placement: .top),
            PresentationAnchor(cardID: second, placement: .top),
            PresentationAnchor(cardID: second, placement: .top)])
        capture.reportPresentedPosition { events.append(($0, $1)) }
        XCTAssertEqual(events.count, 3, "o repouso não repete a mesma posição")
    }

    func testN3OffscreenReferenceNeverBecomesVisibleAnchor() {
        var capture = FeedVisualCapture()
        let id = PublicationCardID()
        capture.phase(active: true, velocity: nil)
        _ = capture.observe(.init(offset: 0, extent: 1000, height: 200))
        _ = capture.observeCard(.init(cardID: id, frame: .init(x: 0, y: 0, width: 300, height: 200), offset: 0, height: 200))
        XCTAssertNil(capture.observe(.init(offset: 400, extent: 1000, height: 200)))
        XCTAssertNil(capture.observeCard(.init(cardID: id, frame: .init(x: 0, y: -400, width: 300, height: 200), offset: 400, height: 200)))
        XCTAssertNil(capture.motion.lastEmission)
    }

    // N3–N6: independent streams have different endpoints and sampling intervals.
    func testN3IndependentIntervalsInBothDeliveryOrders() {
        for cardFirst in [false, true] {
            var capture = FeedVisualCapture()
            let id = PublicationCardID()
            capture.phase(active: true, velocity: nil)
            _ = capture.observe(.init(offset: 0, extent: 1000, height: 200))
            _ = capture.observeCard(.init(cardID: id, frame: .init(x: 0, y: 100, width: 300, height: 200), offset: 0, height: 200))
            let proof = FeedVisualCardGeometry(cardID: id, frame: .init(x: 0, y: 75, width: 300, height: 200), offset: 25, height: 200)
            let event: FeedVisualEvent?
            if cardFirst {
                XCTAssertNil(capture.observeCard(proof))
                event = capture.observe(.init(offset: 40, extent: 1000, height: 200))
            } else {
                XCTAssertNil(capture.observe(.init(offset: 40, extent: 1000, height: 200)))
                event = capture.observeCard(proof)
            }
            XCTAssertEqual(event?.activity, .forward)
            XCTAssertEqual(event?.observation.anchor.cardID, id)
            XCTAssertNil(capture.reconsider(), "Equivalent evidence is deduplicated")
        }
    }

    func testRealMovementAndInertiaRetainLatestAnchorWithoutDuplicates() {
        let a = PublicationCardID(), b = PublicationCardID(), c = PublicationCardID()
        var capture = FeedVisualCapture()
        capture.positionID = a
        XCTAssertNil(capture.observe(.init(offset: 0, extent: 1000, height: 200)))
        capture.reading = true
        XCTAssertEqual(Self.move(&capture, id: a, offset: 20)?.activity, .forward)
        capture.positionID = b
        XCTAssertEqual(Self.move(&capture, id: b, offset: 40)?.observation.anchor.cardID, b)
        capture.positionID = c
        XCTAssertEqual(Self.move(&capture, id: c, offset: 60)?.observation.anchor.cardID, c)
        XCTAssertNil(capture.observe(.init(offset: 60, extent: 1000, height: 200)))
        capture.positionID = b
        XCTAssertEqual(Self.move(&capture, id: b, offset: 40)?.activity, .backward)
    }

    func testInstallLayoutAndStationaryDoNotInventReading() {
        var capture = FeedVisualCapture()
        capture.positionID = PublicationCardID()
        XCTAssertNil(capture.observe(.init(offset: 0, extent: 1000, height: 200)))
        XCTAssertNil(capture.observe(.init(offset: 20, extent: 1000, height: 200)))
        capture.reading = true
        XCTAssertNil(capture.observe(.init(offset: 20, extent: 1200, height: 200)))
        XCTAssertNil(capture.observe(.init(offset: 20, extent: 1200, height: 300)))
        capture.invalidateLayout()
        XCTAssertNil(capture.observe(.init(offset: 100, extent: 1200, height: 300)))
    }

    func testTailIsGeometryAndSmallWindowIsNotExhaustion() {
        var capture = FeedVisualCapture()
        capture.positionID = PublicationCardID()
        _ = capture.observe(.init(offset: 0, extent: 300, height: 200))
        capture.reading = true
        XCTAssertEqual(Self.move(&capture, id: capture.positionID!, offset: 100, extent: 300)?.activity, .explicitTailApproach)
        XCTAssertNil(capture.observe(.init(offset: 100, extent: 300, height: 200)))
        XCTAssertEqual(Self.move(&capture, id: capture.positionID!, offset: 90, extent: 300)?.activity, .backward)
    }

    func testLayoutChangeCannotReusePriorDirectionForPositionOrTail() {
        var capture = FeedVisualCapture()
        capture.positionID = PublicationCardID()
        _ = capture.observe(.init(offset: 0, extent: 1000, height: 200))
        capture.reading = true
        _ = capture.observe(.init(offset: 20, extent: 1000, height: 200))
        XCTAssertNil(capture.observe(.init(offset: 20, extent: 1200, height: 200)))
        capture.positionID = PublicationCardID()
        _ = capture.observeCard(.init(cardID: capture.positionID!, frame: .init(x: 0, y: 180, width: 300, height: 500), offset: 20, height: 200), isLast: true)
        XCTAssertNil(capture.reconsider())
    }

    func testNativePositionAloneDoesNotProveCurrentViewport() {
        var capture = FeedVisualCapture()
        capture.positionID = PublicationCardID()
        _ = capture.observe(.init(offset: 0, extent: 1000, height: 200))
        capture.reading = true
        XCTAssertNil(capture.observe(.init(offset: 200, extent: 1000, height: 200)))
    }


    func testLastRealMovementAfterRecenterIsNotLostInEitherOrder() {
        for cardFirst in [false, true] {
            var capture = FeedVisualCapture()
            let id = PublicationCardID()
            _ = capture.observe(.init(offset: 0, extent: 1000, height: 200))
            capture.reading = true
            XCTAssertNotNil(Self.move(&capture, id: id, offset: 20))
            capture.invalidateLayout()
            let proof = FeedVisualCardGeometry(cardID: id, frame: .init(x: 0, y: -20, width: 300, height: 200), offset: 200, height: 200)
            let event: FeedVisualEvent?
            if cardFirst {
                XCTAssertNil(capture.observeCard(proof))
                event = capture.observe(.init(offset: 200, extent: 800, height: 200))
            } else {
                XCTAssertNil(capture.observe(.init(offset: 200, extent: 800, height: 200)))
                event = capture.observeCard(proof)
            }
            // Same semantic anchor and direction are already delivered; no duplicate is required.
            XCTAssertNil(event)
            XCTAssertEqual(capture.motion.direction, .forward)
        }
    }

    func testPendingLastVisibleProofCanSettleAfterInertiaEnds() {
        var capture = FeedVisualCapture()
        let id = PublicationCardID()
        _ = capture.observe(.init(offset: 0, extent: 1000, height: 200))
        capture.reading = true
        _ = capture.observeCard(.init(cardID: id, frame: .init(x: 0, y: 50, width: 300, height: 200), offset: 0, height: 200))
        XCTAssertNil(capture.observe(.init(offset: 50, extent: 1000, height: 200)))
        capture.reading = false
        XCTAssertEqual(capture.observeCard(.init(cardID: id, frame: .init(x: 0, y: 0, width: 300, height: 200), offset: 50, height: 200))?.observation.anchor.cardID, id)
        XCTAssertNil(capture.reconsider())
    }


    func testLatestDifferentVisibleAnchorAfterLayoutAndStationarySettlement() {
        var capture = FeedVisualCapture()
        let a = PublicationCardID(), b = PublicationCardID()
        _ = capture.observe(.init(offset: 0, extent: 1000, height: 200))
        capture.reading = true
        XCTAssertNotNil(Self.move(&capture, id: a, offset: 20))
        capture.invalidateLayout()
        XCTAssertNil(capture.observe(.init(offset: 200, extent: 800, height: 200)))
        XCTAssertNil(capture.observeCard(.init(cardID: a, frame: .init(x: 0, y: -200, width: 300, height: 200), offset: 200, height: 200)))
        // New legitimate displacement after the recenter fence, not the recenter itself.
        capture.invalidateLayout()
        _ = capture.observe(.init(offset: 180, extent: 800, height: 200))
        _ = capture.observeCard(.init(cardID: b, frame: .init(x: 0, y: 36, width: 300, height: 200), offset: 180, height: 200))
        XCTAssertNil(capture.observe(.init(offset: 200, extent: 800, height: 200)))
        let event = capture.observeCard(.init(cardID: b, frame: .init(x: 0, y: 16, width: 300, height: 200), offset: 200, height: 200))
        XCTAssertEqual(event?.observation.anchor.cardID, b)
        XCTAssertEqual(event?.activity, .forward)
        capture.reading = false
        XCTAssertEqual(capture.settle()?.activity, .stationary)
        XCTAssertNil(capture.settle())
        capture = FeedVisualCapture()
        XCTAssertNil(capture.settle())
        XCTAssertNil(capture.reconsider())
    }

    func testPartialTailVisibilityAndRepeatedGeometryDoNotDuplicateDemand() {
        var capture = FeedVisualCapture()
        let a = PublicationCardID(), last = PublicationCardID()
        _ = capture.observe(.init(offset: 0, extent: 1000, height: 200))
        capture.reading = true
        XCTAssertNil(capture.observeCard(.init(cardID: last, frame: .init(x: 0, y: 180, width: 300, height: 500), offset: 50, height: 200), isLast: true))
        XCTAssertEqual(Self.move(&capture, id: a, offset: 50)?.activity, .explicitTailApproach)
        XCTAssertNil(Self.move(&capture, id: a, offset: 50))
        XCTAssertNil(capture.reconsider())
    }


    func testLayoutDisplacementDuringActiveReadingIsNotUserMovement() {
        for cardFirst in [false, true] {
            var capture = FeedVisualCapture()
            let id = PublicationCardID()
            _ = capture.observe(.init(offset: 0, extent: 1000, height: 200))
            capture.reading = true
            XCTAssertNotNil(Self.move(&capture, id: id, offset: 20))
            capture.invalidateLayout()
            // Prefix layout moves the unchanged card; there is no new user input.
            let proof = FeedVisualCardGeometry(cardID: id,
                frame: .init(x: 0, y: 20, width: 300, height: 200), offset: 200, height: 200)
            if cardFirst {
                XCTAssertNil(capture.observeCard(proof))
                XCTAssertNil(capture.observe(.init(offset: 200, extent: 1400, height: 200)))
            } else {
                XCTAssertNil(capture.observe(.init(offset: 200, extent: 1400, height: 200)))
                XCTAssertNil(capture.observeCard(proof))
            }
        }
    }

    func testLatePartialTailProofMustPreserveFinalTailDemand() {
        var capture = FeedVisualCapture()
        let a = PublicationCardID(), last = PublicationCardID()
        _ = capture.observe(.init(offset: 0, extent: 1000, height: 200))
        capture.reading = true
        XCTAssertEqual(Self.move(&capture, id: a, offset: 50)?.activity, .forward)
        let tail = capture.observeCard(.init(cardID: last,
            frame: .init(x: 0, y: 180, width: 300, height: 500), offset: 50, height: 200), isLast: true)
        XCTAssertEqual(tail?.activity, .explicitTailApproach)
        XCTAssertEqual(tail?.observation.anchor.cardID, a)
    }

    static func assertVisualBoundary(file: StaticString = #filePath, line: UInt = #line) {
        let store = FeedScreenStore { _, _ in XCTFail("No hidden emission", file: file, line: line) }
        let fields = Array(Mirror(reflecting: FeedScreen(store: store)).children)
        XCTAssertEqual(fields.filter { String(describing: type(of: $0.value)).hasPrefix("State<") }.count, 1, file: file, line: line)
        let visual = FeedVisualCapture()
        for field in Mirror(reflecting: visual).children {
            let name = String(describing: type(of: field.value))
            for forbidden in ["FeedPresentation", "FeedWindow", "PresentationCard", "FeedEditionID", "ContextKey", "Array<"] {
                XCTAssertFalse(name.contains(forbidden), name, file: file, line: line)
            }
        }
        var capture = visual
        capture.positionID = PublicationCardID()
        XCTAssertNil(capture.observe(.init(offset: 0, extent: 1000, height: 200)), file: file, line: line)
        capture.reading = true
        XCTAssertNotNil(move(&capture, id: capture.positionID!, offset: 10), file: file, line: line)
        XCTAssertNil(capture.observe(.init(offset: 10, extent: 1000, height: 200)), file: file, line: line)
        capture.invalidateLayout()
        XCTAssertNil(capture.observe(.init(offset: 300, extent: 1000, height: 200)), file: file, line: line)
    }

    private static func move(_ capture: inout FeedVisualCapture, id: PublicationCardID,
        offset: CGFloat, extent: CGFloat = 1000, height: CGFloat = 200) -> FeedVisualEvent? {
        let oldProof = capture.motion.priorProof
        if oldProof == nil, let old = capture.motion.geometry, old.offset != offset {
            // Explicit stable-content fixture, sampled before the displacement.
            _ = capture.observeCard(.init(cardID: id,
                frame: .init(x: 0, y: offset - old.offset, width: 300, height: height),
                offset: old.offset, height: height))
        }
        let fromGeometry = capture.observe(.init(offset: offset, extent: extent, height: height))
        var fromReference: FeedVisualEvent?
        if let oldProof, oldProof.offset != offset {
            fromReference = capture.observeCard(.init(cardID: oldProof.cardID,
                frame: oldProof.frame.offsetBy(dx: 0, dy: oldProof.offset - offset), offset: offset, height: height))
        }
        let frame = oldProof?.cardID == id
            ? oldProof!.frame.offsetBy(dx: 0, dy: oldProof!.offset - offset)
            : CGRect(x: 0, y: 0, width: 300, height: height)
        let fromCard = capture.observeCard(.init(cardID: id, frame: frame, offset: offset, height: height))
        return fromCard ?? fromReference ?? fromGeometry
    }

    func testReversalInBothCallbackOrdersUsesMatchedVisibleGeometry() {
        for cardFirst in [false, true] {
            var capture = FeedVisualCapture()
            let a = PublicationCardID(), b = PublicationCardID()
            _ = capture.observe(.init(offset: 0, extent: 1000, height: 200))
            capture.reading = true
            XCTAssertEqual(Self.move(&capture, id: a, offset: 100)?.activity, .forward)
            _ = capture.observeCard(.init(cardID: b, frame: .init(x: 0, y: -50, width: 300, height: 200), offset: 100, height: 200))
            let proof = FeedVisualCardGeometry(cardID: b, frame: .init(x: 0, y: 0, width: 300, height: 200), offset: 50, height: 200)
            if cardFirst {
                XCTAssertNil(capture.observeCard(proof))
                let event = capture.observe(.init(offset: 50, extent: 1000, height: 200))
                XCTAssertEqual(event?.activity, .backward)
                XCTAssertEqual(event?.observation.anchor.cardID, b)
            } else {
                XCTAssertNil(capture.observe(.init(offset: 50, extent: 1000, height: 200)))
                let event = capture.observeCard(proof)
                XCTAssertEqual(event?.activity, .backward)
                XCTAssertEqual(event?.observation.anchor.cardID, b)
            }
        }
    }

    func testOffscreenCardsAndUnequalHeightsRequireActualVisibleProof() {
        var capture = FeedVisualCapture()
        let a = PublicationCardID()
        _ = capture.observe(.init(offset: 0, extent: 2000, height: 200))
        capture.reading = true
        _ = capture.observeCard(.init(cardID: a, frame: .init(x: 0, y: -850, width: 300, height: 1200), offset: 0, height: 200))
        _ = capture.observe(.init(offset: 50, extent: 2000, height: 200))
        XCTAssertNil(capture.observeCard(.init(cardID: PublicationCardID(), frame: .init(x: 0, y: 250, width: 300, height: 400), offset: 50, height: 200)))
        XCTAssertNil(capture.observeCard(.init(cardID: PublicationCardID(), frame: .init(x: 0, y: 30, width: 300, height: 30), offset: 50, height: 200)))
        XCTAssertEqual(capture.observeCard(.init(cardID: a, frame: .init(x: 0, y: -900, width: 300, height: 1200), offset: 50, height: 200))?.observation.anchor.cardID, a)
    }

    // D1-C1/C3, D1-D1/D2 and D1-E: optional velocity is not a scroll veto.
    func testD1OptionalVelocityAndDecelerationUseConsistentDisplacement() {
        for velocity: CGVector? in [nil, .zero] {
            var capture = FeedVisualCapture()
            let id = PublicationCardID()
            _ = capture.observe(.init(offset: 0, extent: 1000, height: 200))
            capture.phase(active: true, velocity: velocity)
            XCTAssertEqual(Self.move(&capture, id: id, offset: 30)?.activity, .forward)
            capture.phase(active: true, velocity: velocity) // continued deceleration context
            XCTAssertEqual(Self.move(&capture, id: id, offset: 10)?.activity, .backward)
            XCTAssertEqual(capture.motion.direction, .backward)
            capture.phase(active: true, velocity: nil)
            XCTAssertEqual(capture.motion.direction, .backward, "Missing velocity does not erase known direction")
        }
        var insufficient = FeedVisualCapture()
        insufficient.phase(active: true, velocity: nil)
        _ = insufficient.observe(.init(offset: 0, extent: 1000, height: 200))
        XCTAssertNil(insufficient.observe(.init(offset: 50, extent: 1000, height: 200)))
        XCTAssertNil(insufficient.motion.direction)
    }

    // D1-D4 tests a synthetic ambiguous vector, not its physical SDK orientation.
    func testD1UnverifiedNonzeroVelocityCannotChooseAnArbitraryDirection() {
        for dy: CGFloat in [-20, 20] {
            var capture = FeedVisualCapture()
            let id = PublicationCardID()
            _ = capture.observe(.init(offset: 0, extent: 1000, height: 200))
            capture.phase(active: true, velocity: .init(dx: 0, dy: dy))
            XCTAssertEqual(Self.move(&capture, id: id, offset: 30)?.activity, .forward,
                "N9 direction comes from stable visual displacement, never the unverified vector")
            XCTAssertTrue(capture.motion.velocityUnverified)
            XCTAssertEqual(Self.move(&capture, id: id, offset: 10)?.activity, .backward)
            capture.invalidateLayout()
            _ = capture.observe(.init(offset: 10, extent: 1000, height: 200))
            XCTAssertNil(capture.observe(.init(offset: 60, extent: 1000, height: 200)),
                "The vector alone does not authorize direction")
        }
    }

    // V6-L additionally rejects local card layout changes with unchanged document extent.
    func testD1ActiveLayoutCannotMasqueradeAsStableCardDisplacement() {
        for cardFirst in [false, true] {
            for changesHeight in [false, true] {
                var capture = FeedVisualCapture()
                let id = PublicationCardID()
                capture.phase(active: true, velocity: .zero)
                _ = capture.observe(.init(offset: 0, extent: 1000, height: 200))
                _ = capture.observeCard(.init(cardID: id, frame: .init(x: 0, y: 0, width: 300, height: 200), offset: 0, height: 200))
                let next = FeedVisualCardGeometry(cardID: id,
                    frame: .init(x: 0, y: changesHeight ? -40 : 20, width: 300, height: changesHeight ? 250 : 200), offset: 40, height: 200)
                if cardFirst {
                    XCTAssertNil(capture.observeCard(next))
                    XCTAssertNil(capture.observe(.init(offset: 40, extent: 1000, height: 200)))
                } else {
                    XCTAssertNil(capture.observe(.init(offset: 40, extent: 1000, height: 200)))
                    XCTAssertNil(capture.observeCard(next))
                }
                XCTAssertNil(capture.motion.lastEmission)
            }
        }
    }

    func testD2LateTailDedupAndNewAnchorDoNotRegressToOldAnchor() {
        var capture = FeedVisualCapture()
        let b = PublicationCardID(), c = PublicationCardID(), last = PublicationCardID()
        _ = capture.observe(.init(offset: 0, extent: 1000, height: 200))
        capture.phase(active: true, velocity: nil)
        XCTAssertEqual(Self.move(&capture, id: b, offset: 50)?.activity, .forward)
        let tail = FeedVisualCardGeometry(cardID: last, frame: .init(x: 0, y: 180, width: 300, height: 500), offset: 50, height: 200)
        let upgraded = capture.observeCard(tail, isLast: true)
        XCTAssertEqual(upgraded?.observation.anchor.cardID, b)
        XCTAssertEqual(upgraded?.activity, .explicitTailApproach)
        XCTAssertNil(capture.observeCard(tail, isLast: true))
        XCTAssertEqual(Self.move(&capture, id: c, offset: 70)?.observation.anchor.cardID, c)
        XCTAssertNil(capture.observeCard(tail, isLast: true), "An old tail sample cannot regress C to B")
        capture = FeedVisualCapture() // the Edition/context fence resets the sole visual record
        XCTAssertNil(capture.observeCard(tail, isLast: true))
        XCTAssertNil(capture.motion.lastEmission)
    }

    func testNoDirectionAfterStationaryOrBeforeActiveContext() {
        var capture = FeedVisualCapture()
        let id = PublicationCardID()
        _ = capture.observe(.init(offset: 0, extent: 1000, height: 200))
        XCTAssertNil(Self.move(&capture, id: id, offset: 20))
        capture.phase(active: true, velocity: nil)
        XCTAssertEqual(Self.move(&capture, id: id, offset: 40)?.activity, .forward)
        capture.reading = false
        XCTAssertEqual(capture.settle()?.activity, .stationary)
        XCTAssertNil(Self.move(&capture, id: id, offset: 60))
        XCTAssertEqual(capture.motion.lastEmission?.activity, .stationary)
    }

    func testLatestSampleSurvivesCoalescedCallbackStreams() {
        for cardsFirst in [false, true] {
            var capture = FeedVisualCapture()
            let id = PublicationCardID()
            _ = capture.observe(.init(offset: 0, extent: 1000, height: 200))
            _ = capture.observeCard(.init(cardID: id, frame: .init(x: 0, y: 40, width: 300, height: 200), offset: 0, height: 200))
            capture.phase(active: true, velocity: nil)
            let middle = FeedVisualCardGeometry(cardID: id, frame: .init(x: 0, y: 20, width: 300, height: 200), offset: 20, height: 200)
            let latest = FeedVisualCardGeometry(cardID: id, frame: .init(x: 0, y: 0, width: 300, height: 200), offset: 40, height: 200)
            let event: FeedVisualEvent?
            if cardsFirst {
                XCTAssertNil(capture.observeCard(middle))
                XCTAssertNil(capture.observeCard(latest))
                event = capture.observe(.init(offset: 40, extent: 1000, height: 200))
            } else {
                XCTAssertNil(capture.observe(.init(offset: 20, extent: 1000, height: 200)))
                XCTAssertNil(capture.observe(.init(offset: 40, extent: 1000, height: 200)))
                event = capture.observeCard(latest)
            }
            XCTAssertEqual(event?.activity, .forward)
            XCTAssertEqual(event?.observation.anchor.cardID, id)
        }
    }

    func testCoalescedReturnToBaselineKeepsProvenLatestBackwardMovement() {
        var capture = FeedVisualCapture()
        let id = PublicationCardID()
        _ = capture.observe(.init(offset: 0, extent: 1000, height: 200))
        _ = capture.observeCard(.init(cardID: id, frame: .init(x: 0, y: 0, width: 300, height: 200), offset: 0, height: 200))
        capture.phase(active: true, velocity: nil)
        XCTAssertNil(capture.observe(.init(offset: 20, extent: 1000, height: 200)))
        XCTAssertNil(capture.observe(.init(offset: 0, extent: 1000, height: 200)))
        XCTAssertNil(capture.observeCard(.init(cardID: id, frame: .init(x: 0, y: -20, width: 300, height: 200), offset: 20, height: 200)))
        let event = capture.observeCard(.init(cardID: id, frame: .init(x: 0, y: 0, width: 300, height: 200), offset: 0, height: 200))
        XCTAssertEqual(event?.activity, .backward, "Both streams prove the latest return, despite zero net displacement")
        XCTAssertEqual(event?.observation.anchor.cardID, id)
    }

    func testLateTailAfterIdleRetainsFinalMovementEvidence() {
        var capture = FeedVisualCapture()
        let id = PublicationCardID(), last = PublicationCardID()
        _ = capture.observe(.init(offset: 0, extent: 1000, height: 200))
        capture.phase(active: true, velocity: .zero)
        XCTAssertEqual(Self.move(&capture, id: id, offset: 50)?.activity, .forward)
        capture.reading = false
        XCTAssertEqual(capture.settle()?.activity, .stationary)
        let tail = FeedVisualCardGeometry(cardID: last, frame: .init(x: 0, y: 180, width: 300, height: 500), offset: 50, height: 200)
        let event = capture.observeCard(tail, isLast: true)
        XCTAssertEqual(event?.activity, .explicitTailApproach)
        XCTAssertEqual(event?.observation.anchor.cardID, id)
        XCTAssertNil(capture.observeCard(tail, isLast: true))
        XCTAssertNil(capture.settle(), "Late tail must not reopen a stationary/tail cycle")
    }

    func testCoalescedReversalIsNotMisclassifiedByNetDisplacement() {
        for sign: CGFloat in [-1, 1] {
            for cardsFirst in [false, true] {
                var capture = FeedVisualCapture()
                let id = PublicationCardID()
                _ = capture.observe(.init(offset: 100, extent: 1000, height: 200))
                _ = capture.observeCard(.init(cardID: id, frame: .init(x: 0, y: 0, width: 300, height: 200), offset: 100, height: 200))
                capture.phase(active: true, velocity: nil)
                let far = FeedVisualCardGeometry(cardID: id, frame: .init(x: 0, y: -40 * sign, width: 300, height: 200), offset: 100 + 40 * sign, height: 200)
                let latest = FeedVisualCardGeometry(cardID: id, frame: .init(x: 0, y: -20 * sign, width: 300, height: 200), offset: 100 + 20 * sign, height: 200)
                if cardsFirst {
                    XCTAssertNil(capture.observeCard(far))
                    XCTAssertNil(capture.observeCard(latest))
                    XCTAssertNil(capture.observe(.init(offset: latest.offset, extent: 1000, height: 200)))
                } else {
                    XCTAssertNil(capture.observe(.init(offset: far.offset, extent: 1000, height: 200)))
                    XCTAssertNil(capture.observe(.init(offset: latest.offset, extent: 1000, height: 200)))
                    XCTAssertNil(capture.observeCard(latest))
                }
                XCTAssertNil(capture.motion.lastEmission, "Unsynchronized reversal is ambiguous, not net-direction evidence")
            }
        }
    }

    func testRepeatedTailAcrossIdleDoesNotRepeatKnownEvidence() {
        var capture = FeedVisualCapture()
        let id = PublicationCardID(), last = PublicationCardID()
        _ = capture.observe(.init(offset: 0, extent: 1000, height: 200))
        capture.phase(active: true, velocity: nil)
        XCTAssertEqual(Self.move(&capture, id: id, offset: 50)?.activity, .forward)
        let tail = FeedVisualCardGeometry(cardID: last, frame: .init(x: 0, y: 180, width: 300, height: 500), offset: 50, height: 200)
        XCTAssertEqual(capture.observeCard(tail, isLast: true)?.activity, .explicitTailApproach)
        capture.reading = false
        XCTAssertEqual(capture.settle()?.activity, .stationary)
        XCTAssertNil(capture.observeCard(tail, isLast: true))
        XCTAssertNil(capture.settle())
    }

#if os(macOS)
    /// T3: the transient visual position describes the reference card (and how much of it is above the
    /// viewport) without deciding anything about admission.
    func testTS3VisualPositionDescribesTheReferenceCardOnly() throws {
        var capture = FeedVisualCapture()
        XCTAssertNil(capture.position, "No proof, no position")
        let id = PublicationCardID()
        _ = capture.observe(FeedVisualGeometry(offset: 300, extent: 4_000, height: 800))
        _ = capture.observe(FeedVisualGeometry(offset: 320, extent: 4_000, height: 800))
        // The card straddles the reference line (half the viewport) while its top edge is above it.
        capture.observeCard(FeedVisualCardGeometry(cardID: id,
            frame: CGRect(x: 0, y: -120, width: 400, height: 600), offset: 420, height: 800), isLast: false)
        let position = try XCTUnwrap(capture.position)
        XCTAssertEqual(position.cardID, id)
        XCTAssertEqual(position.offsetWithinCard, 120, "How much of the card is above the viewport")
        XCTAssertEqual(position.placement, .center)
        XCTAssertEqual(position.anchor, PresentationAnchor(cardID: id, placement: .center))
        capture.invalidateLayout()
        XCTAssertNil(capture.position, "A layout change clears the transient position")
    }

    /// T3: the position value clamps inside its own card and refuses non-finite input, so a partly
    /// visible card can never describe an offset outside itself.
    func testTS3ScrollPositionClampsAndRejectsNonFiniteInput() throws {
        let id = PublicationCardID()
        XCTAssertEqual(try XCTUnwrap(FeedScrollPosition(cardID: id, viewportTop: 0, cardTop: -900,
            cardHeight: 400)).offsetWithinCard, 400)
        XCTAssertEqual(try XCTUnwrap(FeedScrollPosition(cardID: id, viewportTop: 0, cardTop: 30,
            cardHeight: 400)).offsetWithinCard, 0)
        XCTAssertNil(FeedScrollPosition(cardID: id, viewportTop: 0, cardTop: 0, cardHeight: 0))
        XCTAssertNil(FeedScrollPosition(cardID: id, offsetWithinCard: .infinity))
    }

    func testNativeHostedLayoutPreservesPositionWithoutInventingReading() async throws {
        guard #available(macOS 15, *) else { return }
        _ = NSApplication.shared
        let ids = (0..<12).map { _ in PublicationCardID() }
        let edition = FeedEditionID()
        let cards = try ids.enumerated().map { index, id in
            try XCTUnwrap(PublishedCard(id: id,
                origin: .init(originRecordID: OriginRecordID(), originRevisionID: OriginRevisionID(), sourceID: nil, providerID: nil, sourceDisplayName: nil, providerDisplayName: nil),
                contentEntityID: nil, contentClusterID: nil,
                text: .init(title: "Native card \(index)", primaryText: String(repeating: "Locally published text. ", count: 20)),
                timestamp: nil, media: .none,
                renderContract: XCTUnwrap(RenderContract(layout: .textOnly, mediaAspectRatio: nil)), primaryAction: nil))
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let history = PublicationHistory(database: database)
        let session = FeedSession(publicationHistory: history)
        func persist(_ editionID: FeedEditionID, _ published: [PublishedCard]) throws {
            let context = FeedContext(request: .main)
            let v = PolicyVersion(rawValue: 1)
            let revision = EditorialRevision(id: EditorialRevisionID(), contextKey: context.key,
                catalogGeneration: .init(rawValue: 1), userSelectionVersion: v, eligibilityPolicyVersion: v,
                scoringPolicyVersion: v, sequencingPolicyVersion: v, exposurePolicyVersion: v,
                selectionSchemaVersion: .init(rawValue: 1))
            let value = FeedEdition(id: editionID, editorialRevision: revision,
                publicationSchemaVersion: .init(rawValue: 1), selectionSeed: 1, createdAt: Date())
            let segment = try XCTUnwrap(FeedSegment(id: FeedSegmentID(), editionID: editionID, ordinal: 0,
                segmentSeed: 1, publicationSchemaVersion: value.publicationSchemaVersion,
                createdAt: Date(), cardIDs: published.map(\.id)))
            let records = try PublicationPersistenceMapping.records(segment: segment, cards: published)
            try PublicationStore(database: database).createEdition(PublicationPersistenceMapping.record(value),
                firstSegment: records.0, cards: records.1)
            try history.saveCursor(.init(editionID: editionID, anchor: .init(cardID: published[4].id, placement: .top)), updatedAt: Date())
        }
        try persist(edition, cards)
        let restored = try await session.admitPresentation(.restore(.init(backwardCapacity: 4, forwardCapacity: 5)))
        let snapshot = try XCTUnwrap(restored)
        var events: [(ViewportObservation, RunwayActivity)] = []
        let store = FeedScreenStore { events.append(($0, $1)) }
        try store.install(.init(presentation: snapshot))
        let hosting = NSHostingView(rootView: FeedScreen(store: store).frame(width: 400, height: 300))
        hosting.frame = .init(x: 0, y: 0, width: 400, height: 300)
        let nativeWindow = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        nativeWindow.contentView = hosting
        func scrollView(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { scrollView($0) }.first
        }
        for _ in 0..<20 { hosting.layoutSubtreeIfNeeded(); await Task.yield() }
        XCTAssertTrue(events.isEmpty)
        let scroll = try XCTUnwrap(scrollView(hosting))
        let before = scroll.contentView.bounds.origin.y
        let extended = try await session.admitPresentation(.restore(.init(backwardCapacity: 4, forwardCapacity: 7)))
        try store.install(.init(presentation: try XCTUnwrap(extended)))
        for _ in 0..<40 { hosting.layoutSubtreeIfNeeded(); await Task.yield() }
        XCTAssertEqual(scroll.contentView.bounds.origin.y, before, accuracy: 1, "Tail extension must preserve position")
        let oldHeight = try XCTUnwrap(scroll.documentView).frame.height
        XCTAssertGreaterThan(before, 0, "Restore the provided interior publication anchor")
        XCTAssertTrue(events.isEmpty, "Programmatic layout is not user input")
        _ = try await session.admitPresentation(.restore(.init(backwardCapacity: 2, forwardCapacity: 7)))
        let recentered = try await session.submitViewport(.init(anchor: .init(cardID: ids[4], placement: .center)))
        try store.install(.init(presentation: try XCTUnwrap(recentered)))
        for _ in 0..<40 { hosting.layoutSubtreeIfNeeded(); await Task.yield() }
        let newHeight = try XCTUnwrap(scroll.documentView).frame.height
        XCTAssertEqual(scroll.contentView.bounds.origin.y, before - (oldHeight - newHeight), accuracy: 1,
            "Removing preceding cards must preserve the visible published position")
        XCTAssertTrue(events.isEmpty, "Recenter must not fabricate user input")
        let newEdition = FeedEditionID()
        let replacement = try cards.map { card in
            try XCTUnwrap(PublishedCard(id: PublicationCardID(), origin: card.origin,
                contentEntityID: card.contentEntityID, contentClusterID: card.contentClusterID,
                text: card.text, timestamp: card.timestamp, media: card.media,
                renderContract: card.renderContract, primaryAction: card.primaryAction))
        }
        try persist(newEdition, replacement)
        let nextSession = FeedSession(publicationHistory: history)
        let nextSnapshot = try await nextSession.admitPresentation(.restore(.init(backwardCapacity: 4, forwardCapacity: 7)))
        var replacementCalls = 0
        let nextStore = FeedScreenStore { _, _ in replacementCalls += 1 }
        try nextStore.install(.init(presentation: try XCTUnwrap(nextSnapshot)))
        hosting.rootView = FeedScreen(store: nextStore).frame(width: 400, height: 300)
        for _ in 0..<40 { hosting.layoutSubtreeIfNeeded(); await Task.yield() }
        XCTAssertEqual(replacementCalls, 0)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(nextStore.state.presentation?.editionID, newEdition)
        withExtendedLifetime(nativeWindow) {}
    }
#endif

}
