import XCTest

/// Jornada de rolagem com evidência bruta, sem transformar a lentidão desta máquina em critério de qualidade.
/// O número de gestos define a carga exercitada; não é um limiar de aprovação de fluidez.
@MainActor
final class FluidityJourneyUITests: XCTestCase {
    func testScrollingAdvancesTheReadingPointAndRecordsTheFrameSeries() throws {
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
        let proof = app.staticTexts["feed-frame-proof"]
        let started = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", ";seconds="), object: proof)
        XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 15), .completed,
            "o medidor deve publicar sua série")
        let before = proof.label

        // Não consultar a árvore durante os gestos: a própria consulta interfere na carga medida.
        for _ in 0..<6 { scroll.swipeUp(velocity: .fast) }

        XCTAssertEqual(app.state, .runningForeground)
        let finalCard = try XCTUnwrap(visibleCardIdentifier(), "a rolagem deve deixar conteúdo visível")
        XCTAssertNotEqual(finalCard, initialCard,
            "gestos para frente devem levar a outro ponto de leitura")
        let after = app.staticTexts["feed-frame-proof"].label
        XCTAssertNotEqual(after, before, "a série deve continuar sendo registrada durante a jornada")

        let evidence = XCTAttachment(string: """
            initial_card=\(initialCard)
            final_card=\(finalCard)
            before=\(before)
            after=\(after)
            Fluidez: série observada, sem limiar de aprovação. Não substitui medição no aparelho nem B06.
            """)
        evidence.name = "scroll-journey-frame-series"
        evidence.lifetime = .keepAlways
        add(evidence)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "scroll-journey-final-surface"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
