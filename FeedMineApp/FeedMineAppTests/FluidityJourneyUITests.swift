import XCTest

/// Jornada de rolagem com evidência bruta, sem transformar a lentidão desta máquina em critério de qualidade.
/// O número de gestos define a carga exercitada; não é um limiar de aprovação de fluidez.
@MainActor
final class FluidityJourneyUITests: XCTestCase {
    /// A carga da jornada curta: seis gestos, como antes.
    private static let shortGestures = 6

    /// A carga da jornada longa: os mesmos gestos, repetidos até a rolagem durar segundos de sobra para julgar a
    /// proporção de quadros perdidos. Continua sendo **carga**, não limiar: o teste afirma as mesmas três coisas da
    /// jornada curta, e a série é o que se mede.
    ///
    /// O gesto é uma arrastada com pausa (`press(thenDragTo:thenHoldForDuration:)`), e não uma sequência de
    /// `swipeUp`: entre dois eventos o XCTest espera o app ficar ocioso, e essa espera entra na série como segundos
    /// de tela parada. A arrastada mantém o dedo na tela e o conteúdo em movimento, que é o que a medida quer.
    private static let longDrags = 14
    private static let dragPressSeconds: TimeInterval = 0.1
    private static let dragHoldSeconds: TimeInterval = 0.8

    func testScrollingAdvancesTheReadingPointAndRecordsTheFrameSeries() throws {
        try scrollJourney(gestures: .swipes(Self.shortGestures),
            evidenceName: "scroll-journey-frame-series")
    }

    /// A mesma jornada com carga longa. Ela lê a série **antes** e **depois** da rolagem: o que ficou entre as duas
    /// leituras é o que a rolagem produziu — os segundos de lançamento e de espera ficam de fora da janela, e não
    /// diluem a proporção.
    func testLongScrollKeepsTheFrameSeriesRecording() throws {
        try scrollJourney(gestures: .drags(Self.longDrags, press: Self.dragPressSeconds,
            hold: Self.dragHoldSeconds), evidenceName: "scroll-journey-long-frame-series")
    }

    /// Como a rolagem é exercitada: os gestos são carga, e a forma do gesto muda o que a série mede.
    private enum Load {
        case swipes(Int)
        case drags(Int, press: TimeInterval, hold: TimeInterval)
    }

    /// Whether this configuration publishes the series in the accessibility tree.
    ///
    /// `FeedFrameMeter`'s ring buffer and its `feed-frame-proof` surface are `#if DEBUG` by construction, so a
    /// Release journey has no such element and an assertion on it would fail for the configuration rather than for
    /// the product. The launch environment and the gestures are identical in both configurations, but the fixture
    /// flags are inert in Release for the same reason (`TrustedFeed.developmentSelection`,
    /// `DevelopmentLocalFeeds` and `FEEDMINE_RUNTIME_NAMESPACE` are DEBUG-only): a Release reader scrolls whatever
    /// sources its own container already persisted. What changes in the test is only where the series is read. The
    /// app writes the same one-second windows (`frames/late/bad/severe/worst_ms`) to its own `trace.jsonl` through
    /// `RunwayTrace`, which is **not** conditional — that file is the channel both configurations share, and
    /// `FRAME-WINDOW` below states the seconds the gestures occupied so the proportion is recomputed from the
    /// app's own record instead of from a summary the test produced.
    private var publishesSeries: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    private func scrollJourney(gestures load: Load, evidenceName: String) throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["FEEDMINE_FIXTURE_ITEMS"] = "95"
        app.launchEnvironment["FEEDMINE_TRACE_CAPTURE"] = "1"
        app.launch()

        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 45), "o leitor deve chegar ao feed")
        let cards = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier MATCHES %@",
            "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 30), "a rolagem exige conteúdo publicado")
        func visibleCardIdentifier() -> String? {
            let viewport = scroll.frame
            return cards.allElementsBoundByIndex
                .filter { $0.isHittable && $0.frame.intersects(viewport) }
                .min { $0.frame.minY < $1.frame.minY }?.identifier
        }
        let initialCard = try XCTUnwrap(visibleCardIdentifier(), "uma carta deve estar visível")
        var before = ""
        if publishesSeries {
            let proof = app.staticTexts["feed-frame-proof"]
            let started = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label CONTAINS %@", ";seconds="), object: proof)
            XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 15), .completed,
                "o medidor deve publicar sua série")
            before = proof.label
        }

        // A carga medida é esta janela, e ela se declara em segundos de relógio: a série é recomputada do traço do
        // app, que é o canal comum a Debug e Release, e não de um resumo que o teste já tenha feito.
        let windowStart = Date()
        // Não consultar a árvore durante os gestos: a própria consulta interfere na carga medida.
        switch load {
        case let .swipes(count):
            for _ in 0..<count { scroll.swipeUp(velocity: .fast) }
        case let .drags(count, press, hold):
            let from = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82))
            let to = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18))
            for _ in 0..<count {
                from.press(forDuration: press, thenDragTo: to, withVelocity: .fast,
                    thenHoldForDuration: hold)
            }
        }

        let windowEnd = Date()
        print("FRAME-WINDOW start=\(windowStart.timeIntervalSince1970) end=\(windowEnd.timeIntervalSince1970) "
            + "seconds=\(windowEnd.timeIntervalSince(windowStart))")

        XCTAssertEqual(app.state, .runningForeground)
        let finalCard = try XCTUnwrap(visibleCardIdentifier(), "a rolagem deve deixar conteúdo visível")
        XCTAssertNotEqual(finalCard, initialCard,
            "gestos para frente devem levar a outro ponto de leitura")
        var after = ""
        if publishesSeries {
            after = app.staticTexts["feed-frame-proof"].label
            XCTAssertNotEqual(after, before, "a série deve continuar sendo registrada durante a jornada")
        }

        // A série bruta sai no log da corrida além do anexo: medir exige poder recomputar a partir do que o app
        // publicou, e não de um número que o teste já tenha resumido.
        print("FRAME-JOURNEY initial_card=\(initialCard)")
        print("FRAME-JOURNEY final_card=\(finalCard)")
        if publishesSeries {
            print("FRAME-JOURNEY before=\(before)")
            print("FRAME-JOURNEY after=\(after)")
        }

        let evidence = XCTAttachment(string: """
            initial_card=\(initialCard)
            final_card=\(finalCard)
            series_read=\(publishesSeries ? "accessibility" : "trace.jsonl")
            before=\(before)
            after=\(after)
            Fluidez: série observada, sem limiar de aprovação. Não substitui medição no aparelho nem B06.
            """)
        evidence.name = evidenceName
        evidence.lifetime = .keepAlways
        add(evidence)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "\(evidenceName)-final-surface"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
