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

    /// The namespace the 2026-10-11 diagnosis accidentally bookmarked a card in; the cleanup test below reads it
    /// and skips when the store no longer holds it. No other observation may depend on a fixed namespace: a rebuilt
    /// store makes it absent, which is exactly what happened to the real-article question below.
    private static let readerWithContent = "3E1B4C1A-6F2D-4A5B-9C7E-8D5A2F0B7C31"

    /// The site's control, as `SFSafariViewController` labels it on this device.
    private func siteReaderClose(_ app: XCUIApplication) -> XCUIElement { app.buttons["Close"] }

    /// The card's own *open* control. `FeedItemCardView.openingSurface` names it `card.open`; the compact row
    /// answers the same tap with a gesture and has no control of its own, hence the card itself.
    private func openControl(_ card: XCUIElement) -> XCUIElement {
        let control = card.buttons["card.open"]
        return control.exists ? control : card
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

    /// The declared fixture for the real-article question: a disposable namespace whose only supply is the app's
    /// own development feeds, served in process — no network, no server, no clock, and nothing carried over from a
    /// previous store. `longSummary` is the established shape that gives each story stored text long enough for the
    /// app's own reading surface (`ReadingSurfaceUITests.testASubstantialSummaryIsReadLocallyAndLabelledAsASummary`),
    /// so the tap opens a real article instead of the site.
    private func launchLocalArticle(_ namespace: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = namespace
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["FEEDMINE_FIXTURE_TEXT"] = "longSummary"
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

    /// The card's current frame in the tree, or `nil` while the lazy layout has not instantiated it. One element is
    /// resolved, not the whole tree — this is read once per sample while the reader is stopped.
    private func frame(_ app: XCUIApplication, of identifier: String) -> CGRect? {
        let element = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
        guard element.exists else { return nil }
        let frame = element.frame
        return frame.height > 40 ? frame : nil
    }

    /// The position the layout reports once the reader is stopped: three consecutive reads within half a point.
    /// A frame read while a gesture is still coming to rest is part of the gesture, not a position.
    private func settledFrame(_ app: XCUIApplication, of identifier: String,
        within seconds: TimeInterval = 30) -> CGRect? {
        let deadline = Date().addingTimeInterval(seconds)
        var previous: CGRect?
        var equalReads = 0
        while Date() < deadline {
            let current = frame(app, of: identifier)
            if let current {
                if let previous, abs(current.minY - previous.minY) < 0.5 { equalReads += 1 } else { equalReads = 0 }
                if equalReads >= 2 { return current }
            } else {
                equalReads = 0
            }
            previous = current
            Thread.sleep(forTimeInterval: 0.25)
        }
        return nil
    }

    /// What the renderer does while nobody touches the screen: the card's own `minY`, sampled with no gesture in
    /// flight, so every change is a write of the product's own. `leftTheTree` invalidates the sample; `span` is what
    /// makes the sample a *window* — the query itself costs a snapshot, so the count alone does not say how much of
    /// the idle interval was covered.
    private func restingSamples(_ app: XCUIApplication, of identifier: String,
        seconds: TimeInterval) -> (positions: [CGFloat], span: TimeInterval, leftTheTree: Bool) {
        let started = Date()
        let deadline = started.addingTimeInterval(seconds)
        var positions: [CGFloat] = []
        while Date() < deadline {
            guard let current = frame(app, of: identifier) else {
                return (positions, Date().timeIntervalSince(started), true)
            }
            positions.append(current.minY)
            Thread.sleep(forTimeInterval: 0.2)
        }
        return (positions, Date().timeIntervalSince(started), false)
    }

    /// The admitted IDs `feed-window-proof` publishes: its first field is `ids=<uuid>,<uuid>…`. The `ids=` prefix is
    /// part of that field, and treating it as an id made the first card of the Edition compare unequal to itself.
    private func admittedIDs(in proof: String) -> [String] {
        let first = proof.components(separatedBy: ";").first ?? ""
        guard first.hasPrefix("ids=") else { return [] }
        return first.dropFirst("ids=".count).components(separatedBy: ",").filter { !$0.isEmpty }
    }

    /// The admitted IDs once the surface has stopped changing them: two consecutive reads a second apart. A window
    /// read while publication is still admitting would make a later "it changed" comparison meaningless.
    private func settledAdmittedIDs(_ app: XCUIApplication, within seconds: TimeInterval = 60) -> [String] {
        XCTAssertTrue(app.staticTexts["feed-window-proof"].waitForExistence(timeout: 60),
            "a prova da janela admitida tem de existir (FEEDMINE_TRACE_CAPTURE)")
        let deadline = Date().addingTimeInterval(seconds)
        var previous: [String] = []
        while Date() < deadline {
            let current = admittedIDs(in: app.staticTexts["feed-window-proof"].label)
            if !current.isEmpty, current == previous { return current }
            previous = current
            Thread.sleep(forTimeInterval: 1.0)
        }
        return previous
    }

    /// One field of `feed-window-proof`, verbatim, or `nil` when the label does not carry it — a missing counter
    /// must never be read as the value the assertion wants.
    private func proofField(_ proof: String, _ key: String) -> String? {
        let prefix = key + "="
        return proof.components(separatedBy: ";").first { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
    }

    private func proofInt(_ proof: String, _ key: String) -> Int? {
        // The label is a `LocalizedStringKey`: an Int interpolates with the app's grouping separator (`1,563` in
        // pt-BR, `1.563` in en). Only the digits are the counter.
        guard let raw = proofField(proof, key) else { return nil }
        return Int(raw.filter(\.isNumber))
    }

    private func proofDouble(_ proof: String, _ key: String) -> Double? {
        // A CGFloat interpolates with the app's decimal separator: pt-BR prints `0,000000`. The LAST separator in
        // the field is the decimal one whether the locale groups with the other character or not.
        guard let raw = proofField(proof, key), !raw.isEmpty else { return nil }
        guard let decimal = raw.lastIndex(where: { $0 == "." || $0 == "," }) else { return Double(raw) }
        let whole = raw[..<decimal].filter(\.isNumber)
        let fraction = raw[raw.index(after: decimal)...].filter(\.isNumber)
        guard !whole.isEmpty else { return nil }
        return Double(whole + "." + fraction)
    }

    /// Where a moved frame moved *from*: the scroll view's own frame (its top is the shell's measured chrome
    /// padding, not feed content) and the first cards in content order, not only the tracked one.
    private func geometryDigest(_ app: XCUIApplication) -> String {
        let scroll = app.scrollViews.firstMatch
        let menu = app.buttons["more-menu"]
        let cards = containers(app).prefix(3).map {
            "\($0.identifier.prefix(8))@\(Int($0.frame.minY.rounded()))/h\(Int($0.frame.height.rounded()))"
        }
        let scrollText = scroll.exists
            ? "y=\(Int(scroll.frame.minY.rounded()))/h\(Int(scroll.frame.height.rounded()))" : "none"
        let menuText = menu.exists ? "maxY=\(Int(menu.frame.maxY.rounded()))" : "none"
        return "scroll[\(scrollText)] header[\(menuText)] cards=[\(cards.joined(separator: " "))]"
    }

    /// Every counter of `feed-window-proof` except the admitted ids, which make a line unreadable.
    private func counters(_ proof: String) -> String {
        proof.components(separatedBy: ";").dropFirst().joined(separator: ";")
    }

    /// The card's vertical position in the scroll view's own coordinate space — the coordinate the product's own
    /// visual proof publishes (`proxy.frame(in: .scrollView)`), and the only one that is a content position: the
    /// shell's header padding moves the scroll view, not the content.
    private func contentY(_ app: XCUIApplication, of card: CGRect) -> CGFloat {
        let scroll = app.scrollViews.firstMatch
        return scroll.exists ? card.minY - scroll.frame.minY : card.minY
    }

    /// What is drawn between the top of the scroll viewport and the first card, at the content's own top. A
    /// scroll-content margin is empty; a band the product inserts (a tip, a warning, a section) is an element here.
    private func elementsAboveFirstCard(_ app: XCUIApplication, firstCard: CGRect) -> [String] {
        let viewport = app.scrollViews.firstMatch.frame
        let band = CGRect(x: viewport.minX, y: viewport.minY, width: viewport.width,
            height: max(0, firstCard.minY - viewport.minY))
        guard band.height > 0.5 else { return [] }
        return app.descendants(matching: .any).allElementsBoundByIndex.compactMap { element in
            guard element.exists, element.identifier != "feed-window-proof",
                element.elementType != .scrollView, element.frame.height > 0.5,
                band.contains(element.frame) else { return nil }
            return "\(element.elementType.rawValue)/\(element.identifier.isEmpty ? "-" : element.identifier)/"
                + "\(element.label.prefix(24))@\(element.frame)"
        }
    }

    /// The card with the largest visible area in the viewport: the one the reader is actually looking at. Unlike
    /// `anchor`, it does not demand that the whole card fits — after a rest that lands between rows, the card that
    /// is most visible is still a valid object for an at-rest measurement.
    private func mostVisibleCard(_ app: XCUIApplication) -> XCUIElement? {
        let viewport = app.scrollViews.firstMatch.frame
        return containers(app).compactMap { card -> (XCUIElement, CGFloat)? in
            let visible = card.frame.intersection(viewport)
            guard !visible.isNull, visible.height > 0 else { return nil }
            return (card, visible.height)
        }.max { $0.1 < $1.1 }?.0
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

    /// **Experimento controlado**: leitor em movimento rápido, com a janela admitida mudando **durante** o gesto.
    ///
    /// O arranjo é o que torna o cenário válido: o fixture serve seis itens por feed por padrão (dois feeds, doze
    /// cartas) e a janela cobriria o conteúdo inteiro — uma corrida assim produziu 89 instalações com os MESMOS doze
    /// ids, isto é, re-projeções, não avanço. Com `FEEDMINE_FIXTURE_ITEMS=95` a edição passa de 190 cartas e os oito
    /// flings admitem cauda nova, então os ids mudam de verdade. O que se mede é a regra do gesto: nenhuma escrita de
    /// offset e nenhuma troca da janela **desenhada** enquanto o dedo (ou a desaceleração) manda.
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
        let sv = app.scrollViews.firstMatch
        print("DIAG scrollviews=\(app.scrollViews.count) exists=\(sv.exists) hittable=\(sv.isHittable) frame=\(sv.frame) window=\(app.windows.firstMatch.frame)")
        print("DIAG cards=\(app.buttons.matching(identifier: "card.bookmark").count) otherElements=\(app.scrollViews.count)")
        for _ in 0..<8 { app.scrollViews.firstMatch.swipeUp(velocity: .fast) }
        print("DIAG after swipes scrollviews=\(app.scrollViews.count) proof=\(app.staticTexts["feed-window-proof"].label.prefix(60))")
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
        // `activeLayoutStep` is emitted only when the drawn window actually changed during the gesture. With zero
        // active windows there is no step to bound; demanding one would fail a correct, static-window pass.
        if value("activeWindows") > 0 {
            let step = final.components(separatedBy: ";")
                .first { $0.hasPrefix("activeLayoutStep=") }
                .map { $0.dropFirst("activeLayoutStep=".count) }
            XCTAssertLessThan(Double(step ?? "999") ?? 999, 1,
                "a retained visible card must not jump while both measured and native offsets remain unchanged")
        }
    }

    @MainActor
    func testWindowUpdateDoesNotShiftAStableVisibleCardWhileStopped() throws {
        try exerciseKeptHeadWindowChanges(largeText: false)
    }

    @MainActor
    func testWindowPruningPreservesPositionWithLargeText() throws {
        try exerciseKeptHeadWindowChanges(largeText: true)
    }

    /// **O contrato de posição/história/pixel, sob a política que o produto realmente aplica.**
    ///
    /// A decisão do dono de 2026-10-13 instala a lista com `keepsAdmittedHead: true`
    /// (`AppComposition.presentationBounds`): a reserva à frente é limitada, mas nada acima do leitor é removido.
    /// Uma leitura para frente, portanto, **não** retira a carta que o leitor passou — a versão anterior exigia a
    /// remoção do default da biblioteca, não deste produto. O que a política promete, e o que este exercício mede:
    ///
    /// 1. **História**: a carta passada continua entre as admitidas depois de avançar (os `ids` que a própria tela
    ///    publica), e a janela admitida realmente mudou — sem isso o repouso medido seria o de uma tela estática.
    /// 2. **Posição**: com o leitor parado e sem gesto, a carta visível não se move (< 1 pt) enquanto a atualização
    ///    que o gesto deixou para trás é aplicada; e voltar ao início da Edição devolve a carta acompanhada à
    ///    **mesma coordenada de conteúdo** — `frame.minY - scrollView.minY`, a mesma leitura que
    ///    `FeedVisualCardGeometry` publica com `proxy.frame(in: .scrollView(axis: .vertical))` — com a mesma largura,
    ///    altura, coluna e o mesmo frame de ecrã (1 pt). A base é o topo do **conteúdo que o gesto alcança**: o app
    ///    abre com a âncora alinhada à borda do viewport, o que esconde a margem que `NativeFeedTargets.padding()`
    ///    deixa no topo do scroll (16 pt), e puxar a lista para cima revela exatamente essa margem. O exercício
    ///    assenta nesse topo, exige que um gesto a mais não o ultrapasse e exige que a faixa acima da primeira
    ///    carta seja **vazia** — margem de layout, não uma dica/aviso desenhado.
    /// 3. **Pixel**: toda correção aplicada foi medida no primeiro callback coerente e deixou `residual` e
    ///    `visualResidual` < 1 pt. Com a cabeça mantida uma passada correta pode não aplicar correção nenhuma, então
    ///    zero correções é um resultado válido — não se exige a correção que a política dispensa.
    @MainActor
    private func exerciseKeptHeadWindowChanges(largeText: Bool) throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        // Só o experimento liga o traço de diagnóstico: é o único que precisa da coordenada de conteúdo por carta, e
        // ele é desligado por padrão justamente para a operação normal não pagar o custo.
        app.launchEnvironment["FEEDMINE_TRACE_CAPTURE"] = "1"
        // **Edição mais funda que uma janela**: seis itens por feed (dois feeds) fazem a janela cobrir o conteúdo
        // inteiro e o exercício mediria uma tela que nunca mudou. Noventa e cinco itens por feed dão ~190 cartas, e a
        // borda à frente da janela avança com a leitura.
        app.launchEnvironment["FEEDMINE_FIXTURE_ITEMS"] = "95"
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 120), "o app tem de chegar ao feed")
        XCTAssertGreaterThan(waitForCards(app, within: 180), 3, "o arranjo precisa de cartas para admitir à frente")

        // A base é a posição de início que o **gesto** alcança, não a posição programática do app. O app abre com a
        // âncora alinhada à borda de cima do viewport (`.scrollPosition(id:)` sem âncora em `FeedNativeViewport`),
        // e esse alinhamento esconde a margem de 16 pt que `NativeFeedTargets.padding()` deixa em volta do conteúdo.
        // Puxar a lista para cima revela a margem e para no topo do próprio scroll: 16 pt além da posição inicial,
        // exatamente o `141,75` vs `125,75` medido. Comparar o retorno com a posição programática compararia duas
        // posições diferentes; a canônica — e reproduzível por gesto — é o topo do conteúdo.
        guard let tracked = anchor(app), tracked.frame != .zero else {
            return XCTFail("uma carta visível com identificador tem de existir antes do avanço")
        }
        let trackedID = tracked.identifier
        guard var baseline = settledFrame(app, of: trackedID) else {
            return XCTFail("a carta acompanhada tem de assentar antes da medida de base (\(trackedID))")
        }
        let alignedFrame = baseline
        var topGestures = 0
        while topGestures < 4 {
            app.scrollViews.firstMatch.swipeDown(velocity: .slow)
            topGestures += 1
            guard let next = settledFrame(app, of: trackedID) else { break }
            let moved = abs(next.minY - baseline.minY)
            baseline = next
            if moved < 0.5 { break }
        }
        // A base só vale como topo se o gesto não conseguir ir além dela: mais um swipeDown não pode mover a carta.
        app.scrollViews.firstMatch.swipeDown(velocity: .slow)
        guard let beyondTop = settledFrame(app, of: trackedID) else {
            return XCTFail("a carta tem de continuar visível no topo do conteúdo (\(trackedID))")
        }
        XCTAssertEqual(beyondTop.minY, baseline.minY, accuracy: 1,
            "a base tem de ser o topo de conteúdo alcançável: o gesto não pode ir além da margem do scroll")
        let marginAbove = elementsAboveFirstCard(app, firstCard: baseline)
        XCTAssertTrue(marginAbove.isEmpty,
            "o espaço acima da primeira carta no topo tem de ser margem de layout, não uma faixa desenhada: "
                + "\(marginAbove)")
        print("PROOF canonical-top aligned=\(alignedFrame) top=\(baseline) gestures=\(topGestures) "
            + "margin=[\(marginAbove.joined(separator: " "))]")
        let initialIDs = settledAdmittedIDs(app)
        let initialProof = app.staticTexts["feed-window-proof"].label
        XCTAssertTrue(initialIDs.contains(trackedID),
            "a carta medida tem de estar entre as admitidas na base (\(trackedID))")
        let baselineDigest = geometryDigest(app)
        let baselineContentY = contentY(app, of: baseline)
        print("PROOF baseline card=\(trackedID) frame=\(baseline) contentY=\(baselineContentY) "
            + "admitted=\(initialIDs.count) \(baselineDigest)")

        // 1. Avançar até a janela admitida mudar E a carta ter saído do viewport. Oito gestos fixos não bastam com
        //    texto acessível (XXXL pode desenhar menos de uma carta por gesto, e a reserva inicial é de 16); o limite
        //    é o orçamento de gestos, não uma distância estimada em cartas.
        let obscuringTop = app.scrollViews.firstMatch.frame.minY
        var rounds = 0
        var advancedProof = initialProof
        var trackedLeftTheViewport = false
        while rounds < 40 {
            app.scrollViews.firstMatch.swipeUp(velocity: .slow)
            rounds += 1
            Thread.sleep(forTimeInterval: 0.4)
            advancedProof = app.staticTexts["feed-window-proof"].label
            trackedLeftTheViewport = frame(app, of: trackedID).map { $0.maxY <= obscuringTop } ?? true
            if trackedLeftTheViewport, admittedIDs(in: advancedProof) != initialIDs { break }
        }
        XCTAssertTrue(trackedLeftTheViewport,
            "a passada tem de tirar a carta do viewport; sem isso ela não foi \"passada\" (\(trackedID))")
        let advancedIDs = admittedIDs(in: advancedProof)
        XCTAssertEqual(Array(advancedIDs.prefix(initialIDs.count)), initialIDs,
            "keepsAdmittedHead: toda carta admitida antes da passada tem de continuar admitida, na mesma ordem — "
                + "a cabeça é conservada, não re-projetada")
        XCTAssertGreaterThan(advancedIDs.count, initialIDs.count,
            "a passada tem de admitir cartas que a janela inicial não continha; uma janela estática não "
                + "exercita nada (depois de \(rounds) gestos)")
        XCTAssertTrue(advancedIDs.contains(trackedID),
            "keepsAdmittedHead: a carta passada tem de continuar admitida depois de \(rounds) gestos (\(trackedID))")
        XCTAssertEqual(proofInt(advancedProof, "activeWindows") ?? -1, 0,
            "a janela desenhada não pode mudar por baixo do gesto nativo")
        XCTAssertEqual(proofInt(advancedProof, "activeWrites") ?? -1, 0,
            "o renderer não pode sobrescrever o offset nativo enquanto um gesto o possui")
        print("PROOF advanced rounds=\(rounds) admitted=\(advancedIDs.count) counters=\(counters(advancedProof))")

        // 2. Com o leitor PARADO, sem gesto: a carta visível não pode se mover. Aqui cai a atualização que o gesto
        //    deixou para trás — exatamente o instante que a política da cabeça mantida alega proteger.
        guard let visible = mostVisibleCard(app) else {
            let cards = containers(app).prefix(6).map { "\($0.identifier.prefix(8))@\($0.frame)" }
            return XCTFail("uma carta visível tem de existir depois do avanço; "
                + "window=\(app.windows.firstMatch.frame) scroll=\(app.scrollViews.firstMatch.frame) "
                + "cards=[\(cards.joined(separator: " "))]")
        }
        let visibleID = visible.identifier
        guard settledFrame(app, of: visibleID) != nil else {
            return XCTFail("a rolagem tem de parar para a medida ser sem gesto concorrente (\(visibleID))")
        }
        let rest = restingSamples(app, of: visibleID, seconds: 20)
        XCTAssertFalse(rest.leftTheTree,
            "a carta em observação não pode sair da árvore durante a medida de repouso (\(visibleID))")
        XCTAssertGreaterThanOrEqual(rest.positions.count, 5,
            "a medida de repouso precisa de amostras distribuídas; \(rest.positions.count) não descreve um intervalo")
        XCTAssertGreaterThanOrEqual(rest.span, 15,
            "a medida tem de cobrir o intervalo de repouso, não só o começo dele (span \(rest.span) s)")
        let atRestShift = (rest.positions.max() ?? 0) - (rest.positions.min() ?? 0)
        print("PROOF rest card=\(visibleID) samples=\(rest.positions.count) "
            + "span=\(String(format: "%.1f", rest.span))s shift=\(atRestShift)pt")
        XCTAssertLessThan(atRestShift, 1,
            "com o leitor PARADO a janela moveu a carta visível em \(atRestShift) pt, sem gesto concorrente")

        // 3. Retorno: voltar ao início da Edição tem de devolver a carta ao MESMO frame — posição, largura e altura.
        //    Uma carta que só reaparece noutro lugar não é a mesma posição.
        var back = 0
        var returned: CGRect?
        while back < 48 {
            app.scrollViews.firstMatch.swipeDown(velocity: .slow)
            back += 1
            guard frame(app, of: trackedID) != nil else { continue }
            // A frame read while the top's rubber band is still returning is not a position — exactly the mistake
            // the original test made with a single read. Settle the card first; only a settled frame may be called
            // "not the baseline".
            guard let current = settledFrame(app, of: trackedID) else { continue }
            returned = current
            if abs(contentY(app, of: current) - baselineContentY) < 0.5 { break }
        }
        guard let returnedFrame = returned else {
            return XCTFail("a carta passada tem de reaparecer ao voltar (\(trackedID))")
        }
        let returnedContentY = contentY(app, of: returnedFrame)
        print("PROOF returned card=\(trackedID) frame=\(returnedFrame) contentY=\(returnedContentY) "
            + "baselineContentY=\(baselineContentY) gestures=\(back) \(geometryDigest(app))")
        XCTAssertEqual(returnedContentY, baselineContentY, accuracy: 1,
            "o retorno tem de devolver a carta à coordenada de conteúdo inicial (\(trackedID)); depois de \(back) "
                + "gestos ela está em \(returnedContentY), não em \(baselineContentY)")
        XCTAssertEqual(returnedFrame.minY, baseline.minY, accuracy: 1,
            "o retorno tem de devolver a carta à posição de ecrã inicial (\(trackedID)); depois de \(back) "
                + "gestos ela está em \(returnedFrame.minY), não em \(baseline.minY)")
        XCTAssertEqual(returnedFrame.minX, baseline.minX, accuracy: 1, "a coluna da carta não pode mudar")
        XCTAssertEqual(returnedFrame.height, baseline.height, accuracy: 1,
            "a mesma carta tem de ser desenhada com a mesma altura")
        XCTAssertEqual(returnedFrame.width, baseline.width, accuracy: 1, "e a mesma largura")

        // E, de volta ao repouso, ela também não se move: a volta não pode reagendar uma correção tardia.
        let returnedRest = restingSamples(app, of: trackedID, seconds: 10)
        XCTAssertFalse(returnedRest.leftTheTree, "a carta devolvida não pode sair da árvore no repouso")
        XCTAssertGreaterThanOrEqual(returnedRest.positions.count, 3,
            "o repouso do retorno precisa de amostras distribuídas (\(returnedRest.positions.count))")
        XCTAssertGreaterThanOrEqual(returnedRest.span, 7,
            "o repouso do retorno tem de cobrir o intervalo medido (span \(returnedRest.span) s)")
        let returnedShift = (returnedRest.positions.max() ?? 0) - (returnedRest.positions.min() ?? 0)
        print("PROOF returned-rest samples=\(returnedRest.positions.count) "
            + "span=\(String(format: "%.1f", returnedRest.span))s shift=\(returnedShift)pt")
        XCTAssertLessThan(returnedShift, 1,
            "depois do retorno a carta acompanhada andou \(returnedShift) pt sem gesto")

        let finalProof = app.staticTexts["feed-window-proof"].label
        print("PROOF final counters=\(counters(finalProof))")
        XCTAssertLessThan(proofDouble(finalProof, "residual") ?? 999, 1,
            "uma correção aplicada tem de remover o deslocamento nativo, não encolhê-lo")
        let corrections = proofInt(finalProof, "corrections") ?? 0
        let measured = proofInt(finalProof, "measured") ?? 0
        if corrections > 0 {
            XCTAssertEqual(measured, corrections,
                "cada correção executada precisa de uma medição coerente; testemunha perdida deixa o cenário incompleto")
            XCTAssertLessThan(proofDouble(finalProof, "visualResidual") ?? 999, 1,
                "o primeiro frame coerente após a correção deve preservar a carta, descontando apenas o gesto")
        } else {
            XCTAssertEqual(measured, 0,
                "nenhuma correção foi aplicada, então nenhuma pode ser contada como medida")
        }

        let evidence = XCTAttachment(string: "policy=keepsAdmittedHead tracked=\(trackedID) "
            + "aligned=\(alignedFrame) baseline=\(baseline) baselineContentY=\(baselineContentY) "
            + "top-gestures=\(topGestures) top-margin=\(baseline.minY - alignedFrame.minY) "
            + "forward-gestures=\(rounds) back-gestures=\(back) "
            + "returned=\(returnedFrame) returnedContentY=\(returnedContentY) "
            + "at-rest-samples=\(rest.positions.count) at-rest-span=\(rest.span) at-rest-shift=\(atRestShift)pt "
            + "returned-samples=\(returnedRest.positions.count) returned-span=\(returnedRest.span) "
            + "returned-shift=\(returnedShift)pt corrections=\(corrections) measured=\(measured) "
            + "residual=\(proofField(finalProof, "residual") ?? "?") "
            + "visualResidual=\(proofField(finalProof, "visualResidual") ?? "?")")
        evidence.name = "kept-head-position-history-pixels"
        evidence.lifetime = .keepAlways
        add(evidence)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "kept-head-policy-returned"
        shot.lifetime = .keepAlways
        add(shot)
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
    /// Both reader surfaces count: `Close` is `SFSafariViewController`'s control, `reading.close` and the body are
    /// the app's own local reading surface.
    private func readerIsUp(_ app: XCUIApplication) -> Bool {
        app.buttons["Close"].exists || app.buttons["reading.close"].exists
            || app.staticTexts["reading.body"].exists || app.webViews.count > 0
    }

    private func waitForReader(_ app: XCUIApplication, within seconds: TimeInterval = 25) -> Double? {
        let started = Date()
        while Date().timeIntervalSince(started) < seconds {
            if readerIsUp(app) { return Date().timeIntervalSince(started) }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return nil
    }

    private func waitForReaderToGo(_ app: XCUIApplication, within seconds: TimeInterval = 25) -> Double? {
        let started = Date()
        while Date().timeIntervalSince(started) < seconds {
            if !readerIsUp(app) { return Date().timeIntervalSince(started) }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return nil
    }

    /// The top chrome as a **frozen snapshot**. Resolving each button proxy (`.frame`, `.label`) re-queries the
    /// live tree, and an element that disappears between the enumeration and the read fails the test with "No
    /// matches found for Element at index N" — measured here on 2026-10-18, in the diagnostic and not in the
    /// behaviour it describes. A snapshot is one query, and the reader's own controls are what it states.
    private func chrome(of app: XCUIApplication) -> String {
        guard let snapshot = try? app.snapshot() else { return "controls=unavailable" }
        let controls = snapshot.children
            .filter { $0.elementType == .button && $0.frame.minY < 110 }
            .map { "\($0.identifier.isEmpty ? "-" : $0.identifier)/\($0.label)" }
        let address = app.buttons["URL"].firstMatch
        let value = address.exists ? String(describing: address.value) : "none"
        return "controls=[\(controls.joined(separator: ", "))] address=\(value)"
    }

    /// The diagnosis' first question, on a fixture that survives any rebuild: a reader opens a real article from a
    /// feed that really exists. The app's own development feeds are served in process (no network, no server, no
    /// clock) and `longSummary` gives each story stored text long enough for the local reading surface — the app's
    /// own reader, `reading.headline`/`reading.body`, not the site.
    ///
    /// The old fixed namespace came from a session's acceptance runs and stopped existing when the store was
    /// rebuilt, so the observation measured nothing after that. Everything this run needs is declared here: a fresh
    /// namespace, the declared fixture, the declared shape. What is asserted is the reader's behaviour and the
    /// position it returns to, not a printout: the stored text is drawn, closing the reader returns to the same
    /// card at the same frame.
    func testWhatHappensWhenAReaderOpensARealArticle() throws {
        let app = launchLocalArticle(UUID().uuidString)
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 120), "the app must reach the feed shell")
        let count = waitForCards(app, within: 180)
        XCTAssertGreaterThan(count, 0, "the declared local fixture must publish cards")
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
        XCTAssertNotNil(opened, "the article must present its reading surface")
        print("DIAGNOSIS reader chrome: \(chrome(of: app))")
        dump("READER_TREE", app)
        attach(app, "02-article")

        // The surface the tap opened is the app's own local reader, and it draws the story the card opened: the
        // whole stored text, its own headline, and the origin the fixture declares. This is the reader behaviour the
        // diagnosis is about — not a placeholder and not a skip.
        let body = byIdentifier(app, "reading.body")
        XCTAssertTrue(body.waitForExistence(timeout: 25), "the local reading surface must draw the stored article")
        XCTAssertGreaterThan(body.label.count, 3_000, "the whole stored text is there, not a teaser")
        XCTAssertTrue(byIdentifier(app, "reading.headline").label.hasPrefix("BBC"),
            "the headline the fixture's source published is the one drawn")
        XCTAssertEqual(byIdentifier(app, "reading.origin").label, "Resumo fornecido pela fonte",
            "a summary must be named as a summary")
        attach(app, "02b-article-body")

        let close = app.buttons["reading.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), "the reader's own close control must be reachable")
        close.tap()
        let closed = waitForReaderToGo(app)
        print("DIAGNOSIS reader-closed-seconds=\(closed.map { String(format: "%.2f", $0) } ?? "still up")")
        XCTAssertNotNil(closed, "the reader must go down when its own close control is used")
        XCTAssertTrue(body.waitForNonExistence(timeout: 20), "the reading surface must be gone")

        guard let after = containers(app).first(where: { $0.identifier == identity })?.frame else {
            return XCTFail("the card the reader left must still be there")
        }
        print("DIAGNOSIS returned-to-the-same-card=true delta=\(String(format: "%.1f", after.minY - before.minY))")
        XCTAssertEqual(after.minY, before.minY, accuracy: 1.0,
            "opening and closing the reader must return the feed to the exact position it left")
        XCTAssertEqual(after.minX, before.minX, accuracy: 1.0, "the card's column must not change")
        XCTAssertEqual(after.height, before.height, accuracy: 1.0, "the same card keeps its drawn height")
        XCTAssertEqual(after.width, before.width, accuracy: 1.0, "and its drawn width")
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

        if siteReaderClose(app).exists {
            siteReaderClose(app).tap()
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
        // The 2026-10-11 diagnosis recorded one occurrence id; a rebuilt fixture has new ids, so the hardcoded
        // id made this cleanup permanently unreachable. The accidental save is identified by its state, which is
        // what the control actually toggles.
        let saved = app.buttons.matching(identifier: "card.bookmark")
            .matching(NSPredicate(format: "value == 'bookmarked'")).firstMatch
        guard saved.waitForExistence(timeout: 30) else {
            throw XCTSkip("no accidental bookmark remains in this fixture; nothing to undo")
        }
        let control = saved
        print("DIAGNOSIS diagnosed-card value before: \(String(describing: control.value))")
        attach(app, "09-before-removal")
        control.tap()
        Thread.sleep(forTimeInterval: 3)
        print("DIAGNOSIS diagnosed-card value after: \(String(describing: control.value))")
        attach(app, "10-after-removal")
    }
}

