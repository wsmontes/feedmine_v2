//
// File: ArticleReadingDiagnosisUITests.swift
// Module: FeedMineAppTests
//
// Responsibility:
// The next UX front's **diagnosis**: what really happens when a reader opens an article from the feed, with the
// app on a real catalogue and real URLs. It changes nothing in the product — it observes, measures and dumps what
// the surfaces actually are, so a proposal can be argued from facts instead of from the synthetic links that
// produced round 1's Safari finding.
//
// Two readers, two questions:
//   1. a reader with a real feed opens a real article — the transition, the surface, the return, the position;
//   2. a reader whose article cannot be resolved (the app's own fixture stories point at `site.feedmine.test`,
//      which its URLProtocol deliberately does not answer, so the name never resolves) — what is on screen when
//      the article cannot be fetched.
//
// Round 1's first pass got three things wrong and this file is the correction: the "transition time" was a sleep
// (now polled), the "offline" case did not cut the web view's network at all (`FEEDMINE_BLOCK_RSS_NETWORK` blocks
// the app's RSS transport, not Safari's — the page came from cache), and the anchored card was picked from the
// whole tree, including off-screen cards (now only a card fully inside the viewport is anchored).
import XCTest

@MainActor
final class ArticleReadingDiagnosisUITests: XCTestCase {
    private static let cardIdentifier = NSPredicate(format: "identifier MATCHES %@",
        "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")

    /// The reader's own namespace from this session's acceptance runs: it already holds a real feed, which is what
    /// these observations need — a fresh reader would spend minutes publishing before there was an article to open.
    private static let readerWithContent = "3E1B4C1A-6F2D-4A5B-9C7E-8D5A2F0B7C31"

    /// The reader's control, as `SFSafariViewController` labels it on this device.
    private func readerClose(_ app: XCUIApplication) -> XCUIElement { app.buttons["Close"] }

    /// The card's own *open* control. `FeedItemCardView` draws the whole card as `Button { emit(.open) }` with no
    /// identifier, and the bookmark as `Button { emit(.save) }` with `card.bookmark` — and the bookmark comes
    /// first in the tree, so "the card's first button" bookmarks the article instead of opening it.
    private func openControl(_ card: XCUIElement) -> XCUIElement {
        let candidate = card.buttons.matching(NSPredicate(format: "identifier == '' AND label != ''")).firstMatch
        return candidate.exists ? candidate : card
    }

    /// A OBSERVAÇÃO que o arquiteto mandou verificar e **não** concluir: no simulador, toques sintéticos do HOST
    /// navegaram a tela de fontes mas não viraram nenhum switch. Ele ordenou o instrumento certo — XCUITest **pelo
    /// identificador do controle** — e três eixos de comparação: estado visual, valor de acessibilidade e
    /// preferência persistida.
    ///
    /// O achado do T7, que já vive neste repositório, explica o fenômeno melhor que qualquer teoria: a **linha**
    /// envolve o switch, e o toque tem de ir no controle **interno** (`country.switches.firstMatch`), não na linha
    /// — que abre o drill-in. Era isso que meu toque de host acertava: a linha. Este teste mede o controle interno
    /// nos três eixos, em namespace próprio e descartável (o namespace do soak não é tocado).
    @MainActor
    func testSourceSwitchStateIsVisibleAnnouncedAndPersisted() throws {
        let namespace = UUID().uuidString
        let app = launch(namespace, firstRun: false)
        XCTAssertTrue(app.buttons["more-menu"].waitForExistence(timeout: 120), "o app tem de chegar à casca do leitor")
        app.buttons["more-menu"].tap()
        app.buttons.matching(NSPredicate(format: "label IN {'Fontes', 'Sources'}")).firstMatch.tap()
        let openCountries = app.buttons["sources-open-countries"]
        XCTAssertTrue(waitWhileScrolling(openCountries, in: app), "a folha de fontes tem de oferecer os países")
        for _ in 0..<8 where !openCountries.isHittable { app.swipeUp() }
        openCountries.tap()

        let country = app.switches["country-toggle-argentina"]
        XCTAssertTrue(waitWhileScrolling(country, in: app), "o controle tem de existir PELO IDENTIFICADOR")
        for _ in 0..<12 where !country.isHittable { app.swipeUp() }
        // Eixo 1 (acessibilidade), medido: o controle **externo** anuncia o estado semântico ("selected" /
        // "not selected") e o **interno** é o UISwitch cru, que reporta "0"/"1". Eles não anunciam o mesmo texto —
        // a asserção anterior supunha que sim e media a coisa errada. O que importa: existe um valor semântico,
        // ele está no elemento que a linha publica pelo identificador, e é ele que muda ao tocar.
        let announcedBefore = try XCTUnwrap(country.value as? String, "o controle anuncia um valor")
        XCTAssertTrue(["selected", "not selected"].contains(announcedBefore),
            "o elemento do identificador tem de anunciar o estado semântico, e anunciou: \(announcedBefore)")
        // O controle interno é o que aceita toque; a linha abre o drill-in (T7).
        let inner = country.switches.firstMatch
        XCTAssertTrue(inner.waitForExistence(timeout: 10), "a linha envolve o switch")
        XCTAssertTrue(["0", "1"].contains(inner.value as? String ?? ""),
            "e o interno reporta o valor cru do UISwitch, e reportou: \(inner.value ?? "nil")")
        // Eixo 2 (visual): a tela antes do toque, anexada.
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "sources-before-tap"
        before.lifetime = .keepAlways
        add(before)

        inner.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "selected"),
            object: country)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 60), .completed,
            "tocar o controle INTERNO tem de virar o estado anunciado (antes: \(announcedBefore))")
        let after = XCTAttachment(screenshot: app.screenshot())
        after.name = "sources-after-tap"
        after.lifetime = .keepAlways
        add(after)

        // Eixo 3 (persistência): fechar adota a seleção; reabrir com o MESMO namespace tem de mostrá-la.
        app.buttons["countries-done"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["more-menu"].waitForExistence(timeout: 120), "reabrir tem de voltar à casca")
        app.buttons["more-menu"].tap()
        app.buttons.matching(NSPredicate(format: "label IN {'Fontes', 'Sources'}")).firstMatch.tap()
        XCTAssertTrue(waitWhileScrolling(openCountries, in: app))
        for _ in 0..<8 where !openCountries.isHittable { app.swipeUp() }
        openCountries.tap()
        let again = app.switches["country-toggle-argentina"]
        XCTAssertTrue(waitWhileScrolling(again, in: app))
        for _ in 0..<12 where !again.isHittable { app.swipeUp() }
        let persisted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "selected"),
            object: again)
        XCTAssertEqual(XCTWaiter.wait(for: [persisted], timeout: 60), .completed,
            "a preferência tem de SOBREVIVER ao fechar e reabrir — é o eixo que um toque sintético não mede")
        let proof = XCTAttachment(string: "namespace=\(namespace) antes=\(announcedBefore) depois=\(again.value ?? "nil")")
        proof.name = "source-switch-three-axes"
        proof.lifetime = .keepAlways
        add(proof)
    }

    private func launch(_ namespace: String, firstRun: Bool, fixtures: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = namespace
        app.launchEnvironment["FEEDMINE_ONBOARDING"] = firstRun ? "1" : "0"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = firstRun ? "0" : "1"
        if fixtures {
            // The app's own fixture site, reached the way T12 reaches it: development feeds plus the fixture,
            // with no source selected, so what gets published can only be the feed the reader added.
            app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
            app.launchEnvironment["FEEDMINE_ADD_FEED_FIXTURE"] = "1"
            app.launchEnvironment["FEEDMINE_EMPTY_SELECTION"] = "1"
        }
        app.launch()
        return app
    }

    private func containers(_ app: XCUIApplication) -> [XCUIElement] {
        app.descendants(matching: .any).matching(Self.cardIdentifier).allElementsBoundByIndex
            .filter { $0.exists && $0.frame.height > 40 }
            .sorted { $0.frame.minY < $1.frame.minY }
    }

    /// Only a card the reader can actually see: anchoring something scrolled off the top measures a tap the reader
    /// never made.
    private func anchor(_ app: XCUIApplication) -> XCUIElement? {
        let window = app.windows.firstMatch.frame
        return containers(app).first { $0.frame.minY > window.minY + 120 && $0.frame.maxY < window.maxY - 80 }
    }

    private func walkTheFirstRun(_ app: XCUIApplication) {
        if app.staticTexts["welcome-headline"].waitForExistence(timeout: 25) {
            app.buttons["welcome-shape"].tap()
            let composer = app.otherElements["onboarding"].scrollViews.firstMatch
            if composer.waitForExistence(timeout: 30) {
                let open = app.buttons["composer-open-feed"]
                for _ in 0..<6 where !open.isHittable { composer.swipeUp() }
                if open.isHittable { open.tap() }
            }
        }
        _ = app.scrollViews.firstMatch.waitForExistence(timeout: 240)
    }

    @discardableResult
    private func waitForCards(_ app: XCUIApplication, within seconds: TimeInterval = 180) -> Int {
        let deadline = Date().addingTimeInterval(seconds)
        var stable = 0
        while Date() < deadline {
            let count = containers(app).count
            if count >= 1 { stable += 1; if stable >= 3 { return count } } else { stable = 0 }
            Thread.sleep(forTimeInterval: 1.0)
        }
        return containers(app).count
    }

    /// A segunda demonstração que o arquiteto exigiu ao aceitar o reparo: **posição visual preservada ao inserir
    /// cards acima**, e ele foi explícito de que "identidade e placement não substituem essa medição". Então a
    /// medição é de TELA: o próprio app publica o elemento da sua âncora, e o teste lê onde ele está.
    ///
    /// O gesto é pequeno de propósito: um arrasto para trás (na direção do histórico) já faz o app emitir
    /// `.backward`, ou seja, a admissão acontece, mas o leitor não troca de carta. Se o prepend empurrasse o
    /// conteúdo, a âncora saltaria centenas de pontos na tela — a medida anterior desta família registrou 139 pt e
    /// 912 pt em corridas reais. Sem inserção, o esperado é não haver salto.
    @MainActor
    func testBackwardAdmissionDoesNotJumpTheReadersVisualPosition() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 120), "o app tem de chegar ao feed")
        XCTAssertGreaterThan(waitForCards(app, within: 180), 3, "o arranjo precisa de cartas para admitir acima")

        guard let anchorBefore = anchor(app), anchorBefore.frame != .zero else {
            return XCTFail("o app tem de publicar a âncora E ela tem de estar visível para a medida ser de tela")
        }
        let frameBefore = anchorBefore.frame
        let identityBefore = anchorBefore.identifier
        let screenBefore = XCTAttachment(screenshot: app.screenshot())
        screenBefore.name = "anchor-before-backward-gesture"
        screenBefore.lifetime = .keepAlways
        add(screenBefore)

        // Pequeno arrasto na direção do histórico (para cima do conteúdo): dispara `.backward` no app — a admissão —
        // sem tirar o leitor da carta em que está.
        app.scrollViews.firstMatch.swipeDown(velocity: .slow)
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))
        let screenAfter = XCTAttachment(screenshot: app.screenshot())
        screenAfter.name = "anchor-after-backward-gesture"
        screenAfter.lifetime = .keepAlways
        add(screenAfter)

        guard let anchorAfter = anchor(app), anchorAfter.frame != .zero else {
            return XCTFail("depois do gesto a âncora tem de continuar visível para a medida ser comparável")
        }
        let jump = abs(anchorAfter.frame.minY - frameBefore.minY)
        XCTAssertEqual(anchorAfter.identifier, identityBefore,
            "um gesto pequeno não troca a carta do leitor — se trocou, a medida perdeu o objeto")
        XCTAssertLessThan(jump, 24,
            "inserir histórico acima não pode empurrar a posição visual do leitor: salto de \(jump) pt")

        // **Baseline**: um gesto que NÃO dispara admissão. `.forward` no meio da janela só move a posição — é o
        // movimento do próprio dedo —, então a medida dele calibra o teste. Sem isto o teste mede o arrasto e chama
        // de salto: foi o que aconteceu na primeira versão, que acusou 70 pt como se fosse defeito. Um salto de
        // reconstrução tem outra ordem de grandeza (a altura das cartas que saem da lista, centenas de pontos).
        var baseline: CGFloat = 0
        var moved = false
        do {
            let before = anchor(app)?.frame.minY
            app.scrollViews.firstMatch.swipeUp(velocity: .slow)
            XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))
            if let after = anchor(app)?.frame.minY, let before, after != 0 {
                baseline = abs(after - before)
                moved = baseline > 1
            }
        }
        XCTAssertTrue(moved, "a baseline precisa de um gesto que de fato mova a posição, senão não calibra nada")

        // E o resto do que o arquiteto exigiu: a posição visual medida também quando cards ACIMA são **removidos**
        // (o leitor afasta-se dessa borda e a janela desliza, cortando o que ficou atrás) e quando são
        // **acrescentados de novo** (ele volta). Os cortes acontecem fora do campo de visão — é por isso que
        // precisam ser medidos. O que o teste discrimina: o delta não pode passar do que o PRÓPRIO gesto produz.
        var report = "antes: \(identityBefore) y=\(frameBefore.minY) · inserir-acima: "
            + "\(anchorAfter.identifier) y=\(anchorAfter.frame.minY) salto=\(jump) pt · baseline (sem admissão)="
            + "\(baseline) pt"
        var lastY = anchorAfter.frame.minY
        // Arrasto **por coordenadas** e **auto-calibrado**: a distância de um swipe é do sistema e variava, e uma
        // quantidade fixa de arrastos também não bastou (2750 pt deram ~8 cartas, e o corte exige mais de
        // `backwardCapacity` = 8). Aqui o teste arrasta até a âncora ter passado por 12 cartas distintas — por
        // construção além do limite — e só então mede. Sem isso ele media uma janela que ainda tinha espaço e o
        // marcador acusava "expected failure que não ocorreu".
        var distinct: Set<String> = [anchorAfter.identifier]
        func advance(until target: Int) {
            let area = app.scrollViews.firstMatch
            var guardCount = 0
            while distinct.count < target, guardCount < 40 {
                let from = area.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                let to = area.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
                from.press(forDuration: 0.05, thenDragTo: to)
                guardCount += 1
                if let element = anchor(app), element.frame != .zero { distinct.insert(element.identifier) }
            }
        }
        let steps: [(String, () -> Void)] = [
            ("remover-acima (frente)", { advance(until: 12) }),
            ("readicionar-acima (trás)", {
                let area = app.scrollViews.firstMatch
                for _ in 0..<8 {
                    let from = area.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
                    let to = area.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
                    from.press(forDuration: 0.05, thenDragTo: to)
                }
            }),
        ]
        for step in steps {
            let (label, gesture) = step
            gesture()
            XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))
            guard let element = anchor(app), element.frame != .zero else {
                return XCTFail("depois de \(label) a âncora tem de continuar visível para a medida valer")
            }
            let delta = abs(element.frame.minY - lastY)
            report += " · \(label): \(element.identifier) y=\(element.frame.minY) delta=\(delta) pt"
            // **DEFEITO MEDIDO, rastreado aqui em vez de suprimido.** O corte em volta da âncora remove cartas
            // ACIMA do leitor, e o SwiftUI preserva o offset em pontos: o conteúdo sob a viewport desloca-se pela
            // altura do que saiu (medido duas vezes: 545 e 555 pt, contra 69–96 pt do próprio gesto — e só quando o
            // corte de fato acontece). Não é o id preso da captura: normalizei-o e o número não mudou, então a
            // normalização foi revertida por não ter prova que a justifique. Candidatos: compensar o offset pela
            // geometria removida, ou virtualizar com `List`. Os dois são decisão de arquitetura, relatada.
            // Quando o produto for corrigido, este marcador vira "expected failure que não ocorreu" — o sinal de
            // que ele deve sair daqui.
            XCTExpectFailure("corte acima do leitor move o conteúdo: \(delta) pt contra \(baseline) pt do gesto")
            XCTAssertLessThan(delta, baseline + 24,
                "\(label) moveu \(delta) pt, além do que o gesto produz (\(baseline) pt) — "
                    + "um salto de reconstrução tem a ordem da altura das cartas removidas")
            lastY = element.frame.minY
        }
        XCTAssertGreaterThanOrEqual(distinct.count, 12,
            "o gesto para frente tem de levar o leitor além do limite da janela (\(distinct.count) cartas distintas) "
                + "— senão a medida não exercita o corte")
        let evidence = XCTAttachment(string: report)
        evidence.name = "anchor-visual-jump"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    /// Espera **rolando**, como o gate faz: numa folha preguiçosa o controle não EXISTE até aparecer, então
    /// `waitForExistence` sozinho falha para um controle que está abaixo da dobra — foi assim que a minha primeira
    /// versão deste teste reprovou a folha de fontes que existe.
    private func waitWhileScrolling(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 10) -> Bool {
        if element.waitForExistence(timeout: 5) { return true }
        for _ in 0..<attempts {
            app.swipeUp()
            if element.waitForExistence(timeout: 3) { return true }
        }
        return false
    }

    private func byIdentifier(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
    }

    private func dump(_ label: String, _ element: XCUIElement) {
        print("\(label)_BEGIN\n\(element.debugDescription)\n\(label)_END")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Polls instead of sleeping: the number reported has to be the reader's own latency, not the test's patience.
    private func waitForReader(_ app: XCUIApplication, within seconds: TimeInterval = 25) -> Double? {
        let started = Date()
        while Date().timeIntervalSince(started) < seconds {
            if app.buttons["Close"].exists || app.webViews.count > 0 { return Date().timeIntervalSince(started) }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return nil
    }

    private func waitForReaderToGo(_ app: XCUIApplication, within seconds: TimeInterval = 25) -> Double? {
        let started = Date()
        while Date().timeIntervalSince(started) < seconds {
            if !app.buttons["Close"].exists && app.webViews.count == 0 { return Date().timeIntervalSince(started) }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return nil
    }

    private func chrome(of app: XCUIApplication) -> String {
        let controls = app.buttons.allElementsBoundByIndex
            .filter { $0.exists && $0.frame.minY < 110 }
            .map { "\($0.identifier.isEmpty ? "-" : $0.identifier)/\($0.label)" }
        let address = app.buttons["URL"].firstMatch
        let value = address.exists ? String(describing: address.value) : "none"
        return "controls=[\(controls.joined(separator: ", "))] address=\(value)"
    }

    func testWhatHappensWhenAReaderOpensARealArticle() throws {
        let app = launch(Self.readerWithContent, firstRun: false)
        _ = app.scrollViews.firstMatch.waitForExistence(timeout: 120)
        let count = waitForCards(app, within: 120)
        print("DIAGNOSIS cards=\(count)")
        attach(app, "01-feed")

        guard let card = anchor(app) else { return XCTFail("no card fully inside the viewport") }
        let identity = card.identifier
        let before = card.frame
        print("DIAGNOSIS anchor=\(identity) before=\(before)")

        let headline = openControl(card)
        print("DIAGNOSIS open-control=\(headline.identifier.isEmpty ? "unnamed" : headline.identifier) label=\(headline.label.prefix(60))")
        if headline.exists && headline.isHittable { headline.tap() } else { card.tap() }
        let opened = waitForReader(app)
        print("DIAGNOSIS transition-seconds=\(opened.map { String(format: "%.2f", $0) } ?? "never presented")")
        print("DIAGNOSIS reader chrome: \(chrome(of: app))")
        dump("READER_TREE", app)
        attach(app, "02-article")

        guard readerClose(app).exists else {
            print("DIAGNOSIS no reader control: cannot measure the return")
            return
        }
        readerClose(app).tap()
        let closed = waitForReaderToGo(app)
        print("DIAGNOSIS reader-closed-seconds=\(closed.map { String(format: "%.2f", $0) } ?? "still up")")
        let after = containers(app).first { $0.identifier == identity }?.frame
        let delta = after.map { $0.minY - before.minY }
        print("DIAGNOSIS returned-to-the-same-card=\(after != nil) delta=\(delta.map { String(format: "%.1f", $0) } ?? "-")")
        print("DIAGNOSIS topmost-card-now=\(anchor(app)?.identifier ?? "none")")
        attach(app, "03-back-in-the-feed")
    }

    func testWhatAReaderSeesWhenTheArticleCannotBeFetched() throws {
        let app = launch(UUID().uuidString, firstRun: false, fixtures: true)
        // T12's own way in: the reader adds the fixture site by its address from the app menu.
        XCTAssertTrue(byIdentifier(app, "feed-empty-state").waitForExistence(timeout: 60),
                      "the fixture run starts with no sources")
        let menu = app.buttons["more-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30), "the header must offer the overflow menu")
        menu.tap()
        // The app is localised (`en.lproj` + `pt-BR.lproj`) and follows the device: this device runs English,
        // so matching a single language's label would fail for a reason that has nothing to do with the feed.
        let addFeed = app.buttons.matching(NSPredicate(format: "label IN {'Adicionar feed', 'Add feed'}")).firstMatch
        XCTAssertTrue(addFeed.waitForExistence(timeout: 15), "the menu must offer adding a feed")
        addFeed.tap()
        let field = app.textFields["add-feed-input"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("https://site.feedmine.test/")
        app.buttons["add-feed-add"].tap()
        _ = app.otherElements["add-feed-result-added"].waitForExistence(timeout: 30)
        app.buttons["add-feed-cancel"].tap()
        XCTAssertTrue(app.staticTexts["Fixture site story 3"].waitForExistence(timeout: 90),
                      "the fixture feed publishes its own stories")
        app.scrollViews.firstMatch.swipeUp()
        let count = waitForCards(app, within: 180)
        print("DIAGNOSIS fixture cards=\(count)")
        attach(app, "04-fixture-feed")

        guard let card = anchor(app) else {
            print("DIAGNOSIS fixture: no card inside the viewport")
            return
        }
        let identity = card.identifier
        let before = card.frame
        let headline = openControl(card)
        if headline.exists && headline.isHittable { headline.tap() } else { card.tap() }
        let opened = waitForReader(app)
        print("DIAGNOSIS fixture transition-seconds=\(opened.map { String(format: "%.2f", $0) } ?? "never presented")")
        Thread.sleep(forTimeInterval: 12)   // give the unresolvable name its chance to fail on screen
        print("DIAGNOSIS fixture reader chrome: \(chrome(of: app))")
        dump("FAILED_READER_TREE", app)
        attach(app, "05-unresolvable-article")

        if readerClose(app).exists {
            readerClose(app).tap()
            _ = waitForReaderToGo(app)
            let after = containers(app).first { $0.identifier == identity }?.frame
            print("DIAGNOSIS fixture returned-to-the-same-card=\(after != nil) delta=\(after.map { String(format: "%.1f", $0.minY - before.minY) } ?? "-")")
        }
        attach(app, "06-fixture-back")
    }

    /// The first pass of this diagnosis tapped "the card's first button" and bookmarked a card instead of opening
    /// it: `card.bookmark` comes first in the tree, and the button is a toggle. This puts the saved list back where
    /// the diagnosis found it, through the app's own control.
    func testTheAccidentalBookmarkIsRemovedThroughTheAppsOwnControl() throws {
        let app = launch(Self.readerWithContent, firstRun: false)
        _ = app.scrollViews.firstMatch.waitForExistence(timeout: 120)
        let control = app.descendants(matching: .any)["892695AB-41A8-4A21-8506-1D8CDB195BC2"].buttons["card.bookmark"]
        XCTAssertTrue(control.waitForExistence(timeout: 30), "the diagnosed card must be reachable in the feed")
        print("DIAGNOSIS diagnosed-card value before: \(String(describing: control.value))")
        attach(app, "09-before-removal")
        control.tap()
        Thread.sleep(forTimeInterval: 3)
        print("DIAGNOSIS diagnosed-card value after: \(String(describing: control.value))")
        attach(app, "10-after-removal")
    }
}
