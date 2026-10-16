import XCTest

/// F48-HITCH-X — o instrumento dos dois experimentos, com a **mesma** instrumentação nos dois lados.
///
/// Por que existe: a corrida F48-HITCH mediu que o engasgo acompanha o gesto (90 quadros severos em 26 s contra 6
/// em 89 s ociosos) e que o pico segue as instalações da janela admitida (54 dos 90 severos nos 6 segundos com 4–5
/// observações do gesto e 11–13 admissões). O que ela **não** separou: quanto do custo é **síntese do gesto**
/// (harness) e quanto é **trabalho de apresentação** (app). Este arquivo separa isso e serve de controle para o
/// experimento de coalescência (H4a), porque os dois lados da comparação têm de carregar a mesma chave.
///
/// Os dois métodos fazem o mesmo **deslocamento de leitura** com a mesma instrumentação
/// (`FEEDMINE_TRACE_CAPTURE=1` **e** `FEEDMINE_JOURNEY_CONSOLE=1` — a segunda entrou aqui justamente para que os
/// dois lados tenham a mesma carga de logging) e diferem só na síntese do gesto:
///
///   * `testA6FastSwipes` — 6 × `swipeUp(velocity: .fast)`: arrasto rápido, poucos passos sintetizados.
///     É o gesto da jornada de fluidez que mediu os engasgos.
///   * `testB6SlowMultiStepDrags` — 6 × arrasto **lento e em mais passos** com a mesma fração de deslocamento,
///     por `press(forDuration:thenDragTo:withVelocity:thenHoldForDuration:)`.
///
/// **O que decide H3:** se o custo (quadros severos, medido pelo app) seguir o **número de observações do app**
/// (`advance` no traço — medido pelo instrumento, não por este teste), o custo é do app; se seguir a síntese do
/// gesto, é do harness. Como o deslocamento alcançado por cada gesto não é o mesmo por construção, a comparação
/// é normalizada por ele: **quadros severos por posição de leitura movida**, com o deslocamento medido no traço
/// (`anchor` de `position_checkpoint`/`advance`), nunca estimado aqui.
///
/// **Por que o deslocamento importa:** um experimento que "melhora" os quadros porque o leitor andou menos é
/// refutação de si mesmo. Os dois métodos afirmam que o ponto de leitura **mudou** e o anexo carrega a carta
/// inicial e a final, além da fração de tela que o gesto pediu.
///
/// Não lê a árvore de acessibilidade durante os gestos: a própria consulta interfere na carga medida — a mesma
/// regra do `FluidityJourneyUITests.swift:37-38`.
@MainActor
final class HitchGestureExperimentUITests: XCTestCase {
    private static let gestures = 6
    private static let fixtureItems = "95"

    /// Lança o leitor como as jornadas de fluidez lançam, com as duas chaves do instrumento ligadas.
    private func launchReader(_ testCase: XCTestCase) throws -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["FEEDMINE_FIXTURE_ITEMS"] = Self.fixtureItems
        app.launchEnvironment["FEEDMINE_TRACE_CAPTURE"] = "1"
        // A linha de jornada passa a existir também na jornada dirigida: o teste declara a chave em vez de esperar
        // que o runner a propague (F48-HITCH §9.9 mediu que `TEST_RUNNER_*` não chega ao app).
        app.launchEnvironment["FEEDMINE_JOURNEY_CONSOLE"] = "1"
        app.launch()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 45), "o leitor deve chegar ao feed")
        return (app, scroll)
    }

    /// A carta no topo do que está visível — a mesma leitura da jornada de fluidez, para o anexo ser comparável.
    private func visibleCardIdentifier(_ app: XCUIApplication, _ scroll: XCUIElement) -> String? {
        let cards = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier MATCHES %@",
            "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"))
        let viewport = scroll.frame
        return cards.allElementsBoundByIndex
            .filter { $0.isHittable && $0.frame.intersects(viewport) }
            .min { $0.frame.minY < $1.frame.minY }?.identifier
    }

    /// A série que o próprio app publicou, lida do rótulo de evidência; espera ela existir antes de medir.
    private func publishedSeries(_ app: XCUIApplication) -> String {
        let proof = app.staticTexts["feed-frame-proof"]
        let started = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", ";seconds="), object: proof)
        XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 15), .completed,
            "o medidor deve publicar sua série")
        return proof.label
    }

    private func attach(_ name: String, _ text: String, _ app: XCUIApplication) {
        let evidence = XCTAttachment(string: text)
        evidence.name = name
        evidence.lifetime = .keepAlways
        add(evidence)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "\(name)-surface"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// Caminho comum: prepara, mede o antes, aplica os gestos, mede o depois e anexa a série com o que foi pedido.
    private func journey(variant: String, recipe: String,
        perform: (XCUIElement) -> Void) throws {
        let (app, scroll) = try launchReader(self)
        let cards = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier MATCHES %@",
            "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 30), "a rolagem exige conteúdo publicado")
        let initialCard = try XCTUnwrap(visibleCardIdentifier(app, scroll), "uma carta deve estar visível")
        let before = publishedSeries(app)

        // Nenhuma consulta à árvore durante os gestos.
        for _ in 0..<Self.gestures { perform(scroll) }

        XCTAssertEqual(app.state, .runningForeground)
        let finalCard = try XCTUnwrap(visibleCardIdentifier(app, scroll), "a rolagem deve deixar conteúdo visível")
        XCTAssertNotEqual(finalCard, initialCard, "os gestos devem levar a outro ponto de leitura")
        let after = publishedSeries(app)
        XCTAssertNotEqual(after, before, "a série deve continuar sendo registrada durante a jornada")

        attach("hitch-gesture-series", """
            variant=\(variant)
            recipe=\(recipe)
            gestures=\(Self.gestures)
            initial_card=\(initialCard)
            final_card=\(finalCard)
            before=\(before)
            after=\(after)
            Fluidez: série observada, sem limiar de aprovação. O deslocamento alcançado é medido no traço
            (`anchor`), não estimado aqui.
            """, app)
    }

    /// Controle da comparação: o gesto que mediu os engasgos na jornada de fluidez.
    func testA6FastSwipes() throws {
        try journey(variant: "A-fast-swipes",
            recipe: "6 × scroll.swipeUp(velocity: .fast)") { scroll in
            scroll.swipeUp(velocity: .fast)
        }
    }

    /// O outro lado: mesmo deslocamento pedido (0,5 da altura do leitor), **mais passos** e velocidade lenta, para
    /// o custo do harness ser diferente com o trabalho do app igual.
    func testB6SlowMultiStepDrags() throws {
        try journey(variant: "B-slow-multi-step-drags",
            recipe: "6 × press(forDuration: 0.4, thenDragTo: dy 0.8→0.3, withVelocity: .slow, thenHoldForDuration: 0.1)") { scroll in
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            start.press(forDuration: 0.4, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
    }
}
