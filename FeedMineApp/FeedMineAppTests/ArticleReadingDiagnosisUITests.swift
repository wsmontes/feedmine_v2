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

    /// **Experimento controlado** que o arquiteto desenhou, depois de retirar duas medidas minhas: leitor parado,
    /// **uma** carta visível identificada, e uma atualização que **poda** cartas acima dela.
    ///
    /// O que faz este cenário ser válido é o **arranjo**: o fixture do app serve seis itens por feed por padrão (dois
    /// feeds, doze cartas), o que faz a janela cobrir o conteúdo inteiro — e uma corrida assim produziu 89
    /// instalações com os MESMOS doze ids, isto é, re-projeções, não podas. Com `FEEDMINE_FIXTURE_ITEMS=95` a edição
    /// passa de 190 cartas e a janela desliza de verdade.
    ///
    /// Por isso o teste **exige** a poda: a carta acompanhada está no topo, tem de **sair** da árvore quando a janela
    /// desliza, e tem de **voltar** quando o leitor retorna. Sem a retirada a execução é **INCOMPLETA, nunca PASS** —
    /// medir repouso numa janela que nunca mudou foi exatamente o erro que ele apontou. A estabilidade da coordenada
    /// de conteúdo é medida depois, sem gesto, e o anexo casa frame e offset do MESMO card com a mutação.
    @MainActor
    func testFastFlingWindowChangesDoNotWriteIntoAnActiveGesture() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["FEEDMINE_TRACE_CAPTURE"] = "1"
        app.launchEnvironment["FEEDMINE_FIXTURE_ITEMS"] = "95"
        app.launch()
        XCTAssertGreaterThan(waitForCards(app, within: 180), 3)
        let initial = app.staticTexts["feed-window-proof"].label
        for _ in 0..<8 { app.scrollViews.firstMatch.swipeUp(velocity: .fast) }
        Thread.sleep(forTimeInterval: 1)
        let final = app.staticTexts["feed-window-proof"].label
        let evidence = XCTAttachment(string: "initial=\(initial)\nfinal=\(final)")
        evidence.name = "fast-fling-native-state"
        evidence.lifetime = .keepAlways
        add(evidence)
        func value(_ key: String) -> Int {
            let prefix = key + "="
            return Int(final.components(separatedBy: ";").first { $0.hasPrefix(prefix) }?.dropFirst(prefix.count) ?? "-1") ?? -1
        }
        // The correction machinery's own magnitude, stated rather than assumed: how many offset corrections the
        // eight fast flings applied, how far the retained visible card moved when they did, and how often the
        // feed surface re-evaluated while they ran. The ids are dropped: they are the whole window and make the
        // line unreadable.
        func counters(_ label: String) -> String {
            label.components(separatedBy: ";").dropFirst().joined(separator: ";")
        }
        print("WINDOW_PROOF initial \(counters(initial))\nWINDOW_PROOF final \(counters(final))")
        XCTAssertNotEqual(initial.components(separatedBy: ";").first, final.components(separatedBy: ";").first,
            "the admitted IDs must change; a fling in a static window cannot reproduce this regression")
        XCTAssertGreaterThan(value("deferredWindows"), 0,
            "canonical window updates must arrive during the gesture; a static-window walk is incomplete")
        XCTAssertEqual(value("activeWindows"), 0,
            "the drawn window must not change underneath the native gesture")
        XCTAssertEqual(value("activeWrites"), 0,
            "the renderer must not overwrite the native offset while a drag or deceleration owns it")
        let step = final.components(separatedBy: ";").first { $0.hasPrefix("activeLayoutStep=") }?.dropFirst("activeLayoutStep=".count)
        XCTAssertLessThan(Double(step ?? "999") ?? 999, 1,
            "a retained visible card must not jump while both measured and native offsets remain unchanged")
    }

    @MainActor
    func testWindowUpdateDoesNotShiftAStableVisibleCardWhileStopped() throws {
        try exercisePruningAndReinsertion(largeText: false)
    }

    @MainActor
    func testWindowPruningPreservesPositionWithLargeText() throws {
        try exercisePruningAndReinsertion(largeText: true)
    }

    @MainActor
    private func exercisePruningAndReinsertion(largeText: Bool) throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        // Só o experimento liga o traço de diagnóstico: é o único que precisa da coordenada de conteúdo por carta, e
        // ele é desligado por padrão justamente para a operação normal não pagar o custo.
        app.launchEnvironment["FEEDMINE_TRACE_CAPTURE"] = "1"
        // **Edição mais funda que uma janela**, e é isto que torna o teste válido: o fixture serve seis itens por
        // feed por padrão (dois feeds, doze cartas), o que faz a janela cobrir o conteúdo INTEIRO — sem poda
        // nenhuma, e o teste antigo passava sem exercitar nada. Noventa e cinco itens por feed dão ~190 cartas.
        app.launchEnvironment["FEEDMINE_FIXTURE_ITEMS"] = "95"
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 120), "o app tem de chegar ao feed")
        XCTAssertGreaterThan(waitForCards(app, within: 180), 3, "o arranjo precisa de cartas para admitir acima")

        // **O arranjo tem de conter uma poda de verdade.** A edição servida é mais funda que uma janela (acima), então
        // avançar faz a janela deslizar e **retirar** a carta que estava no topo. Sem essa retirada a execução é
        // INCOMPLETA — nunca PASS —, porque medir repouso numa janela que nunca mudou foi exatamente o erro que o
        // arquiteto apontou ao retirar a conclusão anterior.
        guard let tracked = anchor(app), tracked.frame != .zero else {
            return XCTFail("uma carta visível com identificador tem de existir antes do avanço")
        }
        let trackedID = tracked.identifier

        // 1. Exigir retirada real dos IDs admitidos. A prova da posição não vem da
        // consulta LazyVStack nem de uma comparação após o gesto: o adaptador mede
        // o mesmo card no primeiro callback coerente após cada correção de janela.
        var rounds = 0
        var removed = false
        var stayingID: String?
        var stayingFrameBefore: CGFloat = 0
        while rounds < 40, !removed {
            app.scrollViews.firstMatch.swipeUp(velocity: .slow)
            rounds += 1
            // Espera a rolagem parar: três leituras iguais do topo visível. Orçamento curto de propósito — a versão
            // anterior esperava 8 s por rodada e quarenta rodadas davam mais de cinco minutos, com o teste caindo
            // por tempo e não por medida.
            var still: [CGFloat] = []
            let settleUntil = Date().addingTimeInterval(3.5)
            while Date() < settleUntil, still.count < 3 {
                if let element = anchor(app), element.frame != .zero {
                    if still.last == element.frame.minY { still.append(element.frame.minY) } else { still = [element.frame.minY] }
                }
                Thread.sleep(forTimeInterval: 0.25)
            }
            // Uma carta que FICA: a segunda inteiramente visível, depois da que vai sair.
            let visible = containers(app).filter { $0.frame != .zero }
            if let candidate = visible.dropFirst().first, candidate.identifier != trackedID {
                let before = candidate.frame.minY
                Thread.sleep(forTimeInterval: 1.2)
                removed = app.staticTexts["feed-window-proof"].exists && !app.staticTexts["feed-window-proof"].label.contains(trackedID)
                if removed, stayingID == nil {
                    stayingID = candidate.identifier
                    stayingFrameBefore = before
                }
            } else {
                removed = app.staticTexts["feed-window-proof"].exists && !app.staticTexts["feed-window-proof"].label.contains(trackedID)
            }
        }
        let nativeProof = app.staticTexts["feed-window-proof"].label
        let proofAttachment = XCTAttachment(string: nativeProof)
        proofAttachment.name = "native-window-proof-after-pruning"
        proofAttachment.lifetime = .keepAlways
        add(proofAttachment)
        let removalShot = XCTAttachment(screenshot: app.screenshot())
        removalShot.name = "after-tracked-card-was-pruned"
        removalShot.lifetime = .keepAlways
        add(removalShot)
        XCTAssertTrue(removed,
            "INCOMPLETO: a janela não retirou a carta acompanhada (\(trackedID)) em \(rounds) gestos — sem poda "
                + "efetiva este cenário não prova nada, e execução incompleta nunca é PASS")


        // 2. Voltar até ela REAPARECER: a reinserção é a outra metade da exigência.
        var backRounds = 0
        var restored = false
        while backRounds < 40, !restored {
            app.scrollViews.firstMatch.swipeDown(velocity: .slow)
            backRounds += 1
            Thread.sleep(forTimeInterval: 0.4)
            let candidate = containers(app).first { $0.identifier == trackedID }
            restored = app.staticTexts["feed-window-proof"].exists
                && app.staticTexts["feed-window-proof"].label.contains(trackedID)
                && candidate.map { $0.frame.height > 0 && $0.frame.intersects(app.scrollViews.firstMatch.frame) } == true
        }
        XCTAssertTrue(restored,
            "a carta retirada tem de VOLTAR quando o leitor retorna (\(trackedID) não reapareceu em \(backRounds) gestos)")

        // 3. A rolagem assentou e a carta voltou: medir **sem nenhum gesto**, e exigir que a coordenada de conteúdo
        //    dela não mude. As amostras e o instante ficam no anexo, onde o log do dispositivo casa frame e offset do
        //    MESMO card com a mutação da janela.
        var stableY: CGFloat = 0
        var settled = false
        var seen: [CGFloat] = []
        let settleDeadline = Date().addingTimeInterval(30)
        while Date() < settleDeadline {
            if let element = containers(app).first(where: { $0.identifier == trackedID }), element.frame != .zero {
                if seen.last == element.frame.minY { seen.append(element.frame.minY) } else { seen = [element.frame.minY] }
                if seen.count >= 3 { stableY = element.frame.minY; settled = true; break }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(settled, "a rolagem tem de parar para a medida ser sem gesto concorrente")
        let screenAtRest = XCTAttachment(screenshot: app.screenshot())
        screenAtRest.name = "at-rest-after-reinsertion"
        screenAtRest.lifetime = .keepAlways
        add(screenAtRest)

        var samples: [CGFloat] = [stableY]
        var leftAgain = false
        let watch = Date().addingTimeInterval(20)
        while Date() < watch {
            if let element = containers(app).first(where: { $0.identifier == trackedID }) {
                if element.frame != .zero { samples.append(element.frame.minY) }
            } else {
                leftAgain = true
                break
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        let low = samples.min() ?? stableY
        let high = samples.max() ?? stableY
        let shift = high - low
        let evidence = XCTAttachment(string: "carta=\(trackedID) retirada-em=\(rounds)-gestos "
            + "reinserida-em=\(backRounds)-gestos carta-que-fica=\(stayingID ?? "?") "
            + "frame-assentado-apos-retirada=\(stayingFrameBefore) "
            + "no-repouso=\(stableY) min=\(low) max=\(high) "
            + "amostras=\(samples.count) saiu-de-novo=\(leftAgain) deslocamento=\(shift) pt")
        evidence.name = "prune-reinsert-and-stability"
        evidence.lifetime = .keepAlways
        add(evidence)
        XCTAssertFalse(leftAgain,
            "a carta acompanhada não pode sair da janela durante a medida — senão o objeto da medida se perdeu")
        let finalProof = app.staticTexts["feed-window-proof"].label
        let correctionValue = finalProof.components(separatedBy: ";").first { $0.hasPrefix("corrections=") }?.dropFirst("corrections=".count)
        XCTAssertGreaterThan(Int(correctionValue ?? "0") ?? 0, 0,
            "a poda real tem de exercitar a compensação nativa, não apenas sair da árvore preguiçosa")
        let residualValue = finalProof.components(separatedBy: ";").first { $0.hasPrefix("residual=") }?.dropFirst("residual=".count)
        XCTAssertLessThan(Double(residualValue ?? "999") ?? 999, 1, "a correção remove o deslocamento de layout")
        let measured = finalProof.components(separatedBy: ";").first { $0.hasPrefix("measured=") }?.dropFirst("measured=".count)
        let visualResidual = finalProof.components(separatedBy: ";").first { $0.hasPrefix("visualResidual=") }?.dropFirst("visualResidual=".count)
        XCTAssertGreaterThan(Int(measured ?? "0") ?? 0, 0,
            "a mesma carta deve ser medida depois de uma correção ligada à mutação real da janela")
        XCTAssertEqual(Int(measured ?? "0") ?? 0, Int(correctionValue ?? "0") ?? 0,
            "cada correção executada precisa de uma medição coerente; testemunha perdida deixa o cenário incompleto")
        XCTAssertLessThan(Double(visualResidual ?? "999") ?? 999, 1,
            "o primeiro frame coerente após a correção deve preservar a carta, descontando apenas o gesto")
        XCTAssertLessThan(shift, 1,
            "com o leitor PARADO, a janela moveu a carta visível em \(shift) pt, sem gesto concorrente")
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

