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

    /// **Experimento controlado** que o arquiteto pediu depois de eu retratar a medida anterior (ela comparava cartas
    /// diferentes sob um gesto concorrente): leitor **parado**, **uma** carta visível identificada e mantida na
    /// janela, e uma atualização que **poda** cartas acima dela. A medida é o frame **dessa mesma carta** enquanto
    /// nada rola — e, como a admissão é assíncrona, ela pode chegar depois de a rolagem assentar, que é a janela em
    /// que a atualização fica isolada.
    ///
    /// Se o frame mudar aqui, a atualização moveu o leitor: é **regressão real**, e o teste fica vermelho. Não há
    /// marcador de falha esperada — o arquiteto o retirou por ele se basear na comparação inválida.
    @MainActor
    func testWindowUpdateDoesNotShiftAStableVisibleCardWhileStopped() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 120), "o app tem de chegar ao feed")
        XCTAssertGreaterThan(waitForCards(app, within: 180), 3, "o arranjo precisa de cartas para admitir acima")

        // **Experimento controlado** (o arquiteto retirou a medida anterior: ela comparava cartas diferentes sob um
        // gesto concorrente). O desenho agora é: avançar com gestos, **esperar a rolagem parar**, escolher UMA carta
        // visível, e medir o frame dela **sem nenhum gesto** enquanto a atualização da janela chega. Como a admissão
        // é assíncrona, qualquer mudança nesse trecho parado só pode ter vindo da atualização.

        // Arrasto **por coordenadas** e **auto-calibrado**: a distância de um swipe é do sistema e variava, e uma
        // quantidade fixa de arrastos também não bastou (2750 pt deram ~8 cartas, e o corte exige mais de
        // `backwardCapacity` = 8). Aqui o teste arrasta até a âncora ter passado por 12 cartas distintas — por
        // construção além do limite. Sem isso o teste media uma janela que ainda tinha espaço e não exercitava nada.
        var distinct: Set<String> = []
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
        // 1. Avançar para que a admissão seguinte tenha trabalho a fazer. Gestos são permitidos aqui; a medida vem
        //    depois, com o leitor parado. A exigência de distância saiu: o arquiteto pediu "poda OU insere", e o que
        //    a medida precisa é de uma atualização chegando com o leitor parado — não de um número de cartas que os
        //    arrastos rendem de forma variável (medido: 2 numa corrida, 12 em outra). O quanto andou fica no anexo.
        advance(until: 12)
        XCTAssertGreaterThanOrEqual(distinct.count, 2,
            "o avanço tem de mover o leitor para haver uma admissão pendente (\(distinct.count) cartas distintas)")

        // 2. Esperar a rolagem **parar**: três leituras consecutivas iguais do frame do topo visível. Sem isto a
        //    medida teria gesto concorrente, que foi o que invalidou a anterior.
        var stableName: String?
        var stableY: CGFloat = 0
        var settled = false
        var seen: [CGFloat] = []
        let settleDeadline = Date().addingTimeInterval(30)
        while Date() < settleDeadline {
            if let element = anchor(app), element.frame != .zero {
                if seen.last == element.frame.minY { seen.append(element.frame.minY) } else { seen = [element.frame.minY] }
                if seen.count >= 3 {
                    stableName = element.identifier
                    stableY = element.frame.minY
                    settled = true
                    break
                }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(settled, "a rolagem tem de parar para a medida ser sem gesto concorrente")
        guard let trackedID = stableName, stableY != 0 else {
            return XCTFail("uma carta visível com identificador tem de existir depois do avanço")
        }
        let screenAtRest = XCTAttachment(screenshot: app.screenshot())
        screenAtRest.name = "at-rest-before-window-update"
        screenAtRest.lifetime = .keepAlways
        add(screenAtRest)

        // 3. Medir **sem nenhum gesto**. Nada rola aqui: qualquer mudança de frame só pode vir da atualização da
        //    janela, porque a admissão do avanço é assíncrona e pode chegar depois de a rolagem assentar. Se a carta
        //    sair da janela, a medida perdeu o objeto — e o teste diz isso em vez de fingir uma medida.
        var samples: [CGFloat] = [stableY]
        var leftTheWindow = false
        let watch = Date().addingTimeInterval(20)
        while Date() < watch {
            if let element = containers(app).first(where: { $0.identifier == trackedID }) {
                if element.frame != .zero { samples.append(element.frame.minY) }
            } else {
                leftTheWindow = true
                break
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        let low = samples.min() ?? stableY
        let high = samples.max() ?? stableY
        let shift = high - low
        let evidence = XCTAttachment(string: "carta=\(trackedID) no-repouso=\(stableY) min=\(low) max=\(high) "
            + "amostras=\(samples.count) saiu-da-janela=\(leftTheWindow) deslocamento=\(shift) pt "
            + "cartas-distintas-no-avanco=\(distinct.count)")
        evidence.name = "stable-card-shift-while-stopped"
        evidence.lifetime = .keepAlways
        add(evidence)
        XCTAssertFalse(leftTheWindow,
            "a carta acompanhada não pode sair da janela durante a medida — senão o objeto da medida se perdeu")
        XCTAssertLessThan(shift, 1,
            "com o leitor PARADO, a atualização da janela moveu a carta visível em \(shift) pt, sem gesto concorrente")
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
