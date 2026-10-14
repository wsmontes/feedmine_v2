import Foundation
import XCTest
import FeedMineDomain
@testable import FeedMinePersistence
@testable import FeedMinePublication
@testable import FeedMineRuntime

final class FeedSessionCheckpointTests: XCTestCase {
    private let initialTime = Date(timeIntervalSince1970: 300.75)
    private let milestoneTime = Date(timeIntervalSince1970: 400.5)

    private func withLocation(_ body: (RuntimeDatabaseLocation) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(RuntimeDatabaseLocation(directory: directory))
    }

    private func persist(location: RuntimeDatabaseLocation) throws -> (FeedEdition, [PublishedCard]) {
        let edition = WarmPresentationFixture.edition()
        let cards = try (0..<10).map {
            try WarmPresentationFixture.card(layout: .textOnly, action: nil, title: "P\($0)")
        }
        let database = try RuntimeDatabase(location: location)
        let store = PublicationStore(database: database)
        for ordinal in 0..<2 {
            let segmentCards = Array(cards[(ordinal * 5)..<(ordinal * 5 + 5)])
            let segment = try XCTUnwrap(FeedSegment(id: FeedSegmentID(), editionID: edition.id,
                ordinal: UInt64(ordinal), segmentSeed: UInt64(ordinal),
                publicationSchemaVersion: edition.publicationSchemaVersion,
                createdAt: edition.createdAt, cardIDs: segmentCards.map(\.id)))
            let records = try PublicationPersistenceMapping.records(segment: segment, cards: segmentCards)
            if ordinal == 0 {
                try store.createEdition(PublicationPersistenceMapping.record(edition), firstSegment: records.0, cards: records.1)
            } else {
                try store.appendSegment(records.0, cards: records.1)
            }
        }
        let cursor = SessionCursor(editionID: edition.id,
            anchor: FeedWindowAnchor(cardID: cards[4].id, placement: .center))
        try SessionStore(database: database).saveCheckpoint(
            PublicationPersistenceMapping.checkpoint(cursor, updatedAt: initialTime))
        return (edition, cards)
    }

    func testNoStateReturnsFalseWithoutCreatingCheckpoint() async throws {
        try await withLocation { location in
            let database = try RuntimeDatabase(location: location)
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            let saved = try await session.checkpointCurrentPosition(at: milestoneTime)
            XCTAssertFalse(saved)
            XCTAssertNil(try SessionStore(database: database).checkpoint())
            let current = await session.currentPresentation()
            XCTAssertNil(current)
        }
    }

    func testRestoreThenMilestonePersistsSamePositionWithSuppliedTime() async throws {
        try await withLocation { location in
            let (edition, cards) = try persist(location: location)
            let database = try RuntimeDatabase(location: location)
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            let restored = try await session.admitPresentation(.restore(.init(backwardCapacity: 2, forwardCapacity: 2)))
            let saved = try await session.checkpointCurrentPosition(at: milestoneTime)
            XCTAssertTrue(saved)
            let checkpoint = try XCTUnwrap(SessionStore(database: database).checkpoint())
            XCTAssertEqual(checkpoint.editionID, edition.id)
            XCTAssertEqual(checkpoint.cardID, cards[4].id)
            XCTAssertEqual(checkpoint.anchorPlacement, "center")
            XCTAssertEqual(checkpoint.updatedAt, milestoneTime)
            let current = await session.currentPresentation()
            XCTAssertEqual(current, restored)
        }
    }

    // Session, history and database references all leave scope before the caller reopens.
    private func shiftCheckpointAndClose(location: RuntimeDatabaseLocation, edition: FeedEdition,
        cards: [PublishedCard], index: Int, placement: PresentationAnchorPlacement) async throws {
        let database = try RuntimeDatabase(location: location)
        let history = PublicationHistory(database: database)
        let session = FeedSession(publicationHistory: history)
        let restored = try await session.admitPresentation(.restore(.init(backwardCapacity: 2, forwardCapacity: 2)))
        XCTAssertEqual(restored?.window.items.map(\.id), Array(cards[2...6]).map(\.id))
        let before = try XCTUnwrap(SessionStore(database: database).checkpoint())
        let shifted = try await session.submitViewport(ViewportObservation(
            anchor: PresentationAnchor(cardID: cards[index].id, placement: placement)))
        XCTAssertEqual(shifted?.window.anchor, PresentationAnchor(cardID: cards[index].id, placement: placement))
        XCTAssertEqual(try SessionStore(database: database).checkpoint(), before)
        XCTAssertEqual(before.cardID, cards[4].id)
        XCTAssertEqual(before.anchorPlacement, "center")
        let saved = try await session.checkpointCurrentPosition(at: milestoneTime)
        XCTAssertTrue(saved)
        let checkpoint = try XCTUnwrap(SessionStore(database: database).checkpoint())
        XCTAssertEqual(checkpoint.editionID, edition.id)
        XCTAssertEqual(checkpoint.cardID, cards[index].id)
        XCTAssertEqual(checkpoint.anchorPlacement, placement.rawValue)
        XCTAssertEqual(checkpoint.updatedAt, milestoneTime)
        let current = await session.currentPresentation()
        XCTAssertEqual(current, shifted)
    }

    func testShiftToP6ThenMilestoneSurvivesCloseAndReopen() async throws {
        try await withLocation { location in
            let (edition, cards) = try persist(location: location)
            try await shiftCheckpointAndClose(location: location, edition: edition, cards: cards, index: 6, placement: .center)
            let database = try RuntimeDatabase(location: location)
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            let restored = try await session.admitPresentation(.restore(.init(backwardCapacity: 2, forwardCapacity: 2)))
            XCTAssertEqual(restored?.window.anchor, PresentationAnchor(cardID: cards[6].id, placement: .center))
            XCTAssertEqual(restored?.window.items.map(\.id), Array(cards[4...8]).map(\.id))
            XCTAssertEqual(restored?.contextKey, edition.contextKey)
            XCTAssertEqual(restored?.editionID, edition.id)
        }
    }

    func testP5TopMilestoneSurvivesCloseAndReopen() async throws {
        try await withLocation { location in
            let (edition, cards) = try persist(location: location)
            try await shiftCheckpointAndClose(location: location, edition: edition, cards: cards, index: 5, placement: .top)
            let database = try RuntimeDatabase(location: location)
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            let restored = try await session.admitPresentation(.restore(.init(backwardCapacity: 2, forwardCapacity: 2)))
            XCTAssertEqual(restored?.window.anchor, PresentationAnchor(cardID: cards[5].id, placement: .top))
        }
    }

    func testStorageFailurePreservesMemoryP6AndDurableP4() async throws {
        try await withLocation { location in
            let (_, cards) = try persist(location: location)
            let database = try RuntimeDatabase(location: location)
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            _ = try await session.admitPresentation(.restore(.init(backwardCapacity: 2, forwardCapacity: 2)))
            let shifted = try await session.submitViewport(ViewportObservation(
                anchor: PresentationAnchor(cardID: cards[6].id, placement: .center)))
            let before = try XCTUnwrap(SessionStore(database: database).checkpoint())
            try database.write { db in
                try db.execute(sql: """
                    CREATE TRIGGER reject_checkpoint BEFORE UPDATE ON session_checkpoint
                    BEGIN SELECT RAISE(ABORT, 'test checkpoint failure'); END
                    """)
            }
            do {
                _ = try await session.checkpointCurrentPosition(at: milestoneTime)
                XCTFail("Expected checkpoint failure")
            } catch {
                XCTAssertTrue(String(describing: error).contains("test checkpoint failure"))
            }
            let current = await session.currentPresentation()
            XCTAssertEqual(current, shifted)
            XCTAssertEqual(current?.window.anchor.cardID, cards[6].id)
            XCTAssertEqual(try SessionStore(database: database).checkpoint(), before)
            XCTAssertEqual(before.cardID, cards[4].id)
            try database.write { db in
                try db.execute(sql: "DROP TRIGGER reject_checkpoint")
            }
        }
    }

    func testInvalidDatePropagatesPersistenceErrorWithoutChangingStateOrCursor() async throws {
        try await withLocation { location in
            let (_, cards) = try persist(location: location)
            let database = try RuntimeDatabase(location: location)
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            _ = try await session.admitPresentation(.restore(.init(backwardCapacity: 2, forwardCapacity: 2)))
            let shifted = try await session.submitViewport(ViewportObservation(
                anchor: PresentationAnchor(cardID: cards[6].id, placement: .center)))
            let before = try SessionStore(database: database).checkpoint()
            do {
                _ = try await session.checkpointCurrentPosition(at: Date(timeIntervalSince1970: .infinity))
                XCTFail("Expected invalid date")
            } catch {
                XCTAssertEqual(error as? SessionStoreError, .invalidRepresentation("updated_at"))
            }
            let current = await session.currentPresentation()
            XCTAssertEqual(current, shifted)
            XCTAssertEqual(try SessionStore(database: database).checkpoint(), before)
        }
    }

    // MARK: - PO 2026-10-14: a posição durável sobre o último card admitido e estabelecido

    /// O defeito medido no B05: sem passar por nenhum milestone (troca de contexto, substituição de sessão,
    /// background, criação da edição), o cursor durável continuava no primeiro card da edição e um fechamento à
    /// força voltava para lá. A observação estabelecida do leitor passa a ser durável — com **identidade e
    /// contexto** (o registro do contexto é o próprio registro), e sem nenhum milestone.
    func testASettledObservationBecomesDurableWithoutAnyMilestone() async throws {
        try await withLocation { location in
            let (edition, cards) = try persist(location: location)
            let settledTime = Date(timeIntervalSince1970: 500)
            let session = FeedSession(publicationHistory: PublicationHistory(database: try RuntimeDatabase(location: location)))
            _ = try await session.admitPresentation(.restore(.init(backwardCapacity: 2, forwardCapacity: 2)))
            _ = try await session.submitViewport(ViewportObservation(
                anchor: PresentationAnchor(cardID: cards[6].id, placement: .center)))
            let recording = try await session.recordSettledPosition(at: settledTime)
            XCTAssertEqual(recording, .written(cardID: cards[6].id, placement: .center))
            let store = try SessionStore(database: try RuntimeDatabase(location: location))
            let active = try XCTUnwrap(store.checkpoint())
            XCTAssertEqual(active.editionID, edition.id)
            XCTAssertEqual(active.cardID, cards[6].id)
            XCTAssertEqual(active.anchorPlacement, "center")
            XCTAssertEqual(active.updatedAt, settledTime)
            XCTAssertEqual(try store.checkpoint(for: edition.contextKey)?.cardID, cards[6].id,
                "the durable position carries the context's own identity, not a global one")
        }
    }

    /// O fechamento à força: a sessão morre, uma nova abre o mesmo banco e volta para o card em que o leitor
    /// estava — o último admitido e estabelecido, não o primeiro da edição.
    func testAForcedCloseReopensOnTheSettledCard() async throws {
        try await withLocation { location in
            let (edition, cards) = try persist(location: location)
            do {
                let session = FeedSession(publicationHistory: PublicationHistory(
                    database: try RuntimeDatabase(location: location)))
                _ = try await session.admitPresentation(.restore(.init(backwardCapacity: 2, forwardCapacity: 2)))
                _ = try await session.submitViewport(ViewportObservation(
                    anchor: PresentationAnchor(cardID: cards[6].id, placement: .top)))
                _ = try await session.recordSettledPosition(at: Date(timeIntervalSince1970: 600))
            }
            let reopened = FeedSession(publicationHistory: PublicationHistory(
                database: try RuntimeDatabase(location: location)))
            let restored = try await reopened.admitPresentation(.restore(.init(backwardCapacity: 2, forwardCapacity: 2)))
            XCTAssertEqual(restored?.window.anchor, PresentationAnchor(cardID: cards[6].id, placement: .top))
            XCTAssertEqual(restored?.editionID, edition.id)
            XCTAssertEqual(restored?.window.items.map(\.id), Array(cards[4...8]).map(\.id),
                "a janela volta materializada em torno do card estabelecido")
        }
    }

    /// A janela declarada, exercitada nas duas bordas: dentro dela nada é gravado (e o desfecho diz quanto
    /// falta), na borda ela libera a escrita do card novo.
    func testTheDeclaredWindowIsTheMaximumLossAndItIsWhatGatesTheWrite() async throws {
        try await withLocation { location in
            let (_, cards) = try persist(location: location)
            let window = FeedSession.settledPositionDebounceWindow
            XCTAssertEqual(window, 20, "a janela máxima de perda declarada é 20 s (3 escritas por minuto)")
            let first = Date(timeIntervalSince1970: 1_000)
            let database = try RuntimeDatabase(location: location)
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            _ = try await session.admitPresentation(.restore(.init(backwardCapacity: 2, forwardCapacity: 2)))
            _ = try await session.submitViewport(ViewportObservation(
                anchor: PresentationAnchor(cardID: cards[6].id, placement: .center)))
            let firstWrite = try await session.recordSettledPosition(at: first)
            XCTAssertEqual(firstWrite, .written(cardID: cards[6].id, placement: .center))
            let written = try XCTUnwrap(SessionStore(database: database).checkpoint())

            // O leitor anda de novo, um segundo antes de a janela fechar: nada é gravado, e o desfecho diz a
            // distância até a próxima escrita possível.
            _ = try await session.submitViewport(ViewportObservation(
                anchor: PresentationAnchor(cardID: cards[5].id, placement: .center)))
            let insideTheWindow = try await session.recordSettledPosition(at: first.addingTimeInterval(window - 1))
            XCTAssertEqual(insideTheWindow, .withinWindow(remaining: 1))
            XCTAssertEqual(try SessionStore(database: database).checkpoint(), written,
                "dentro da janela o cursor durável fica onde estava — é esta a perda máxima declarada")

            // Na borda da janela, a escrita acontece — e é o card novo que passa a ser durável.
            let atTheEdge = try await session.recordSettledPosition(at: first.addingTimeInterval(window))
            XCTAssertEqual(atTheEdge, .written(cardID: cards[5].id, placement: .center))
            XCTAssertEqual(try SessionStore(database: database).checkpoint()?.cardID, cards[5].id)
        }
    }

    /// O custo declarado tem de ser verdade para um leitor parado: a posição que já está durável nunca é
    /// reescrita, nem muito depois da janela — descansar não produz escrita nenhuma.
    func testAPositionAlreadyDurableIsNeverRewritten() async throws {
        try await withLocation { location in
            let (_, cards) = try persist(location: location)
            let first = Date(timeIntervalSince1970: 2_000)
            let database = try RuntimeDatabase(location: location)
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            _ = try await session.admitPresentation(.restore(.init(backwardCapacity: 2, forwardCapacity: 2)))
            _ = try await session.submitViewport(ViewportObservation(
                anchor: PresentationAnchor(cardID: cards[6].id, placement: .center)))
            _ = try await session.recordSettledPosition(at: first)
            let written = try XCTUnwrap(SessionStore(database: database).checkpoint())
            let later = first.addingTimeInterval(10 * FeedSession.settledPositionDebounceWindow)
            let resting = try await session.recordSettledPosition(at: later)
            XCTAssertEqual(resting, .alreadyDurable)
            XCTAssertEqual(try SessionStore(database: database).checkpoint(), written,
                "the same position is never rewritten, whatever the clock says")
        }
    }

    /// A gravação de milestone continua sendo um milestone: a janela nunca a suprime, e ela também move o
    /// relógio do debounce (a janela seguinte mede a partir do que o leitor realmente tornou durável).
    func testAMilestoneIsNeverSuppressedByTheWindow() async throws {
        try await withLocation { location in
            let (_, cards) = try persist(location: location)
            let first = Date(timeIntervalSince1970: 3_000)
            let database = try RuntimeDatabase(location: location)
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            _ = try await session.admitPresentation(.restore(.init(backwardCapacity: 2, forwardCapacity: 2)))
            _ = try await session.submitViewport(ViewportObservation(
                anchor: PresentationAnchor(cardID: cards[6].id, placement: .center)))
            _ = try await session.recordSettledPosition(at: first)
            _ = try await session.submitViewport(ViewportObservation(
                anchor: PresentationAnchor(cardID: cards[5].id, placement: .top)))
            let milestone = first.addingTimeInterval(1)
            let milestoneSaved = try await session.checkpointCurrentPosition(at: milestone)
            XCTAssertTrue(milestoneSaved)
            let store = try SessionStore(database: database)
            XCTAssertEqual(try store.checkpoint()?.cardID, cards[5].id)
            XCTAssertEqual(try store.checkpoint()?.updatedAt, milestone)
            // A posição gravada pelo milestone é a que a janela seguinte mede: uma observação nova logo depois
            // volta a ser admitida como dentro da janela, não como uma primeira escrita.
            _ = try await session.submitViewport(ViewportObservation(
                anchor: PresentationAnchor(cardID: cards[6].id, placement: .center)))
            guard case .withinWindow(let remaining) = try await session.recordSettledPosition(at: milestone.addingTimeInterval(1))
            else { return XCTFail("a milestone must move the debounce's own clock") }
            XCTAssertEqual(remaining, FeedSession.settledPositionDebounceWindow - 1, accuracy: 0.0001)
        }
    }

    /// Sem apresentação admitida não há posição: o desfecho diz isso e nenhum registro é criado.
    func testNoPresentationRecordsNothing() async throws {
        try await withLocation { location in
            let database = try RuntimeDatabase(location: location)
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            let recording = try await session.recordSettledPosition(at: Date(timeIntervalSince1970: 10))
            XCTAssertEqual(recording, .nothingToRecord)
            XCTAssertNil(try SessionStore(database: database).checkpoint())
        }
    }

    /// O contraste que a janela existe para declarar: **em movimento**, uma observação dentro da janela espera;
    /// **no repouso**, a mesma observação é gravada na hora. É isso que faz a perda máxima declarada valer só para
    /// a morte súbita durante a rolagem: quem chega ao repouso não perde nada.
    func testARestIsRecordedImmediatelyWhileMovementWaitsForTheWindow() async throws {
        try await withLocation { location in
            let (_, cards) = try persist(location: location)
            let first = Date(timeIntervalSince1970: 5_000)
            let database = try RuntimeDatabase(location: location)
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            _ = try await session.admitPresentation(.restore(.init(backwardCapacity: 2, forwardCapacity: 2)))
            _ = try await session.submitViewport(ViewportObservation(
                anchor: PresentationAnchor(cardID: cards[6].id, placement: .center)))
            _ = try await session.recordSettledPosition(at: first, settled: true)
            let written = try XCTUnwrap(SessionStore(database: database).checkpoint())

            // Ainda se movendo, dentro da janela: espera.
            _ = try await session.submitViewport(ViewportObservation(
                anchor: PresentationAnchor(cardID: cards[5].id, placement: .center)))
            let moving = try await session.recordSettledPosition(at: first.addingTimeInterval(1))
            guard case .withinWindow = moving else {
                return XCTFail("a moving observation inside the window must wait; observed \(moving)")
            }
            XCTAssertEqual(try SessionStore(database: database).checkpoint(), written)

            // E o mesmo movimento, agora como repouso: grava na hora, sem esperar a janela.
            let rest = try await session.recordSettledPosition(at: first.addingTimeInterval(2), settled: true)
            XCTAssertEqual(rest, .written(cardID: cards[5].id, placement: .center))
            XCTAssertEqual(try SessionStore(database: database).checkpoint()?.cardID, cards[5].id)
            XCTAssertEqual(try SessionStore(database: database).checkpoint()?.updatedAt,
                first.addingTimeInterval(2))
        }
    }

    /// O custo medido, ao lado do orçamento: uma escrita é um upsert de uma linha, e o custo declarado é no
    /// máximo `60 / janela` = 3 escritas por minuto de leitura. O número abaixo é medido nesta máquina, não
    /// estimado — o teto da asserção é folgado de propósito (três quadros a 60 Hz), porque o que se afirma aqui
    /// é a ordem de grandeza, não um microbenchmark.
    func testTheDurabilityWriteCostsFarLessThanOneFramePerWindow() async throws {
        try await withLocation { location in
            let (_, cards) = try persist(location: location)
            let database = try RuntimeDatabase(location: location)
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            _ = try await session.admitPresentation(.restore(.init(backwardCapacity: 2, forwardCapacity: 2)))
            let window = FeedSession.settledPositionDebounceWindow
            let base = Date(timeIntervalSince1970: 4_000)
            var writes = 0
            let started = ProcessInfo.processInfo.systemUptime
            for step in 0..<200 {
                let card = cards[3 + (step % 4)]
                _ = try await session.submitViewport(ViewportObservation(
                    anchor: PresentationAnchor(cardID: card.id, placement: .center)))
                // Cada passo passa a janela declarada e muda de card, então cada passo é uma escrita — o pior caso
                // que a regra permite (o leitor avançando sem parar, com o relógio sempre passando da janela).
                guard case .written = try await session.recordSettledPosition(
                    at: base.addingTimeInterval(window * Double(step))) else {
                    return XCTFail("step \(step) must be a real write")
                }
                writes += 1
            }
            let average = (ProcessInfo.processInfo.systemUptime - started) / Double(max(writes, 1))
            print("DURABILITY_COST writes=\(writes) average_write_ms=\(String(format: "%.3f", average * 1000))"
                + " declared_writes_per_minute=\(Int(60 / window)) frame_budget_ms=16.67")
            XCTAssertGreaterThan(writes, 100, "the measurement is about real writes")
            XCTAssertLessThan(average, 0.05, "one write is far below a frame (16,67 ms)")
        }
    }

    /// PO 2026-10-14: o registro durável nomeia **o card em que o viewport do leitor começa** — o do topo —, preso
    /// à borda de cima, e não o card em que ele está. Só a primeira forma é *completa*: o card em que o leitor está
    /// é o que a captura escolhe pela linha de referência, e a distância dessa linha até a borda do card não faz
    /// parte de um registro que nunca carrega pixels (medido em B05, 2026-10-14: o registro nomeava o card do leitor
    /// e o cold start desenhava o viewport quatro cards adiante). Em movimento o fato é apenas lembrado.
    func testThePresentedTopCardBecomesTheDurablePositionPinnedToTheTopEdge() async throws {
        try await withLocation { location in
            let (_, cards) = try persist(location: location)
            let database = try RuntimeDatabase(location: location)
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            _ = try await session.admitPresentation(.restore(.init(backwardCapacity: 2, forwardCapacity: 2)))
            let moving = try await session.notePresentedPosition(
                PresentationAnchor(cardID: cards[3].id, placement: .top), atRest: false)
            XCTAssertNil(moving, "em movimento o fato é lembrado, não gravado")
            XCTAssertEqual(try SessionStore(database: database).checkpoint()?.cardID, cards[4].id)
            let written = try await session.notePresentedPosition(
                PresentationAnchor(cardID: cards[3].id, placement: .top), atRest: true)
            XCTAssertEqual(written, .written(cardID: cards[3].id, placement: .top))
            let checkpoint = try XCTUnwrap(SessionStore(database: database).checkpoint())
            XCTAssertEqual(checkpoint.cardID, cards[3].id)
            XCTAssertEqual(checkpoint.anchorPlacement, "top", "o topo é gravado como topo")
        }
    }

    /// Um registro nunca nomeia um card que a janela admitida não carrega: um fato de desenho velho (outro
    /// contexto, outra edição, um card que a janela cortou) volta à âncora da própria janela em vez de gravar uma
    /// posição que ninguém consegue restaurar — e repetir o mesmo fato não reescreve nada.
    func testAStaleOrForeignPresentedCardFallsBackToTheWindowAnchor() async throws {
        try await withLocation { location in
            let (_, cards) = try persist(location: location)
            let database = try RuntimeDatabase(location: location)
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            _ = try await session.admitPresentation(.restore(.init(backwardCapacity: 2, forwardCapacity: 2)))
            // A janela restaurada é cards[2...6]: cards[9] e cards[0] estão fora dela.
            let outsideTheTail = try await session.notePresentedPosition(
                PresentationAnchor(cardID: cards[9].id, placement: .top), atRest: true)
            XCTAssertEqual(outsideTheTail, .written(cardID: cards[4].id, placement: .center))
            let again = try await session.notePresentedPosition(
                PresentationAnchor(cardID: cards[9].id, placement: .top), atRest: true)
            XCTAssertEqual(again, .alreadyDurable, "a mesma posição relatada de novo não reescreve o cursor")
            XCTAssertEqual(try SessionStore(database: database).checkpoint()?.cardID, cards[4].id)
            XCTAssertEqual(try SessionStore(database: database).checkpoint()?.anchorPlacement, "center")
        }
    }

    /// E o fato que a restauração mede: o card do topo volta preso à borda de cima — a mesma identidade no topo da
    /// tela —, com a janela materializada em volta dele.
    func testThePresentedTopCardSurvivesACloseAndReopen() async throws {
        try await withLocation { location in
            let (edition, cards) = try persist(location: location)
            do {
                let database = try RuntimeDatabase(location: location)
                let session = FeedSession(publicationHistory: PublicationHistory(database: database))
                _ = try await session.admitPresentation(.restore(.init(backwardCapacity: 2, forwardCapacity: 2)))
                _ = try await session.notePresentedPosition(
                    PresentationAnchor(cardID: cards[3].id, placement: .top), atRest: true)
            }
            let database = try RuntimeDatabase(location: location)
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            let restored = try await session.admitPresentation(.restore(.init(backwardCapacity: 2, forwardCapacity: 2)))
            XCTAssertEqual(restored?.window.anchor, PresentationAnchor(cardID: cards[3].id, placement: .top))
            XCTAssertEqual(restored?.window.items.map(\.id), Array(cards[1...5]).map(\.id))
            XCTAssertEqual(restored?.editionID, edition.id)
        }
    }

    /// O milestone grava a mesma posição que o repouso, pelo mesmo mapeamento: com o card do topo relatado, o
    /// registro nomeia o topo; sem ele, a âncora da janela (o comportamento de antes).
    func testAMilestoneStatesThePresentedTopWhenTheAppHasOne() async throws {
        try await withLocation { location in
            let (_, cards) = try persist(location: location)
            let database = try RuntimeDatabase(location: location)
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            _ = try await session.admitPresentation(.restore(.init(backwardCapacity: 2, forwardCapacity: 2)))
            _ = try await session.notePresentedPosition(
                PresentationAnchor(cardID: cards[6].id, placement: .top), atRest: false)
            let saved = try await session.checkpointCurrentPosition(at: milestoneTime)
            XCTAssertTrue(saved)
            XCTAssertEqual(try SessionStore(database: database).checkpoint()?.cardID, cards[6].id)
            XCTAssertEqual(try SessionStore(database: database).checkpoint()?.anchorPlacement, "top")
        }
    }
}
