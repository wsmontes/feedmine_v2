import UIKit
import XCTest

/// The facts the architect asked to see, measured instead of argued in a report:
///
///  1. **the first presented screen is full** — one criterion, no average and no fraction: at the **first exposure**
///     the bottom of the last laid-out card is at (or below) the viewport bottom, with 1 pt of tolerance. The number
///     of distinct render-ready cards is recorded as information, **never** as a threshold: the PM's corrected D4
///     states no universal two-card floor. The measurement comes from the app's own record (`FeedLaunchWitness`,
///     `feed-launch-record`: `content_bottom`, `viewport_height`, `render_ready_cards`), taken where `FeedScreen`
///     lays the cards out, because `XCUIApplication.launch()` only returns after the app is idle and can never
///     witness the first frame.
///
///     The record states the **exposure**, not the first layout pass: the product now holds the preparation
///     surface over the laid-out cards until the measured layout fills the viewport (`FeedFirstScreenGate`), so a
///     layout measured under that cover was never a first screen. The recorded red run of 2026-10-20
///     (`docs/reviews/evidence/2026-10-20-first-screen/`: one card, `content_bottom=141` of `viewport_height=730`)
///     is the case this criterion exists for, and its failing-before/passing-after unit counterpart is
///     `Tests/FeedMineCompositionTests/FirstScreenPresentationTests.swift`.
///  2. **the visible failure recovers** — the fixture transport (`FEEDMINE_LOCAL_FEEDS`) fails until the reader
///     taps "Tentar novamente" (`FEEDMINE_FAIL_FIRST_FEED_ATTEMPT=1`, DEBUG only). The surface must be the approved
///     `.unreachable` copy, and the retry itself must deliver cards and remove the wait surface.
///  3. **a failure behind presented content preserves it** — the same namespace is reopened with every transport
///     refused while the reader's durable window is already restored. The failure must not blank, shrink or move
///     the cards.
///
/// The generic non-transport branch (`.failed(message: "Falha ao atualizar o feed")` in
/// `AppComposition.reportFailure`) still has no launch knob that reaches it: `FEEDMINE_EMPTY_FEEDS=1` states
/// `.unavailable`, `FEEDMINE_EMPTY_SELECTION=1` draws the source empty state, and a transport fault states
/// `.unreachable`. No production failure path was invented for it.
@MainActor
final class FeedVisibleExperienceUITests: XCTestCase {
    /// A card carries its published id as the accessibility identifier (`FeedItemView`); no other element in the
    /// tree carries a bare UUID. Computed per use because a stored `NSPredicate` is not sendable.
    private static var cardIdentifier: NSPredicate {
        NSPredicate(format: "identifier MATCHES %@",
            "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")
    }

    // MARK: - 1. Preparation → feed, first screen already filled

    /// Deterministic and local: the app's own fixture transport answers every endpoint in-process
    /// (`FEEDMINE_LOCAL_FEEDS=1`) while the public network is refused (`FEEDMINE_BLOCK_RSS_NETWORK=1`), so the
    /// number measured cannot be a network timing accident.
    func testFirstPresentedScreenReachesTheViewportBottom() throws {
        let app = XCUIApplication()
        let namespace = UUID().uuidString
        let environment = configured(app, namespace: namespace, items: "12")
        let started = Date()
        app.launch()
        let idleMS = milliseconds(since: started)

        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 120), "o feed precisa chegar à tela")
        // XCTest's launch returns once the app is idle, so this sample is only the state the reader can still see.
        // The criterion itself is the app's own record: the geometry of the **first exposure**, stated by
        // `FeedScreen` when the reading surface is first shown (`FeedLaunchWitness.noteFirstExposure`).
        let first = sampleFirstScreen(app, scroll: scroll, since: started)
        let record = try launchRecord(app, name: "first-screen")

        let epsilonPoints = 1.0
        var violations: [String] = []
        if first.loadingSurface {
            violations.append("feed-loading-surface is on screen with the feed")
        }
        if first.launchProgress {
            violations.append("feed-launch-progress is on screen with the feed")
        }
        if first.emptySurface {
            violations.append("feed-empty-state is on screen with the feed")
        }
        if !first.placeholderTexts.isEmpty {
            violations.append("placeholder copy is on screen: \(first.placeholderTexts.joined(separator: " | "))")
        }
        if record.cards < 1 {
            violations.append("the app's record never carried cards")
        }
        let contentBottom = record.contentBottom
        let renderReady = record.renderReadyCards
        let viewportHeight = record.viewportHeight
        if contentBottom == nil || viewportHeight == nil {
            violations.append("the app's record did not capture the first card-carrying layout")
        } else if let contentBottom, let viewportHeight,
            contentBottom < viewportHeight - epsilonPoints {
            violations.append("the first presented content stops at \(compact(contentBottom)) pt of a "
                + "\(compact(viewportHeight)) pt viewport: a \(compact(viewportHeight - contentBottom)) pt gap below "
                + "the last laid-out card (epsilon \(epsilonPoints) pt)")
        }
        // `render_ready_cards` is recorded as information, never as a threshold: the PM's corrected D4 has no
        // universal two-card floor. The criterion is the geometry above; the count says how the prefix was made.

        let evidence: [String: Any] = [
            "test": "first-presented-screen",
            "namespace": namespace,
            "env": environment,
            "launch_returned_ms": idleMS,
            "first_sample_ms": first.sampleMS,
            "window": rect(first.window),
            "viewport": rect(first.viewport),
            "card_frames_total": first.totalCardFrames,
            "cards_fully_visible": first.fullyVisibleCards,
            "tallest_card_height": first.tallestCardHeight,
            "epsilon_points": epsilonPoints,
            "loading_surface": first.loadingSurface,
            "launch_progress": first.launchProgress,
            "empty_surface": first.emptySurface,
            "placeholder_texts": first.placeholderTexts,
            "launch_record": record.raw,
            "record_cards": record.cards,
            "record_first_cards_ms": record.firstCardsMS ?? -1,
            "record_content_bottom": contentBottom ?? -1,
            "record_viewport_height": viewportHeight ?? -1,
            "record_render_ready_cards": renderReady ?? -1,
            "record_wait_passes": record.waitPasses,
            "violations": violations
        ]
        let line = jsonLine(evidence)
        print("VISIBLE_FIRST_SCREEN_JSON=\(line)")
        attach(app, name: "first-presented-screen", json: line)

        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(violations.isEmpty, "a primeira apresentação do feed não alcança o fim do viewport: "
            + "\(violations.joined(separator: " | ")) — record=\(record.raw) json=\(line)")
    }

    // MARK: - 2. The visible failure

    /// The transport fault is the app's own fixture transport, made to fail until the reader's retry: the first
    /// attempt cannot produce content, so `.unreachable` is the only honest surface, and "Tentar novamente" runs a
    /// real opportunity that must actually deliver cards.
    /// **D4 no catálogo publicado, com fixtures desligadas.**
    ///
    /// O teste de fixture prova a mecânica; este prova a experiência: nenhuma variável de fixture é ligada, o app
    /// sobe no catálogo embarcado, atravessa o onboarding pelo próprio toque e a superfície de leitura só pode
    /// aparecer quando o conteúdo medido alcança o fim do viewport real. A regra é a do próprio app (1 pt de
    /// tolerância); a contagem de cartas é informação, nunca limiar.
    func testFirstPresentedScreenReachesTheViewportBottomOnThePublishedCatalogue() throws {
        let app = XCUIApplication()
        // Nada de fixture: sem FEEDMINE_USE_DEVELOPMENT_FEEDS, sem FEEDMINE_LOCAL_FEEDS, sem itens de fixture.
        // Só o namespace (D11, o mesmo padrão da jornada de mídia): um diretório novo não tem janela durável nem
        // `hasSeenOnboarding`, então o primeiro passo aparece sozinho e o app lê o catálogo embarcado. É o que
        // torna a medição repetível: o diretório padrão guarda o primeiro passo concluído por uma corrida
        // anterior, e uma medição de primeira tela precisa de um leitor de primeira abertura.
        let namespace = UUID().uuidString
        #if DEBUG
        // Debug keeps the D11 unique-directory pattern. Release does not read this variable at all
        // (`AppComposition` guards it with `#if DEBUG`); the Release proof uses a dedicated fresh simulator and
        // the app's default product container, with the real onboarding.
        app.launchEnvironment = ["FEEDMINE_RUNTIME_NAMESPACE": namespace]
        #endif
        let started = Date()
        app.launch()
        completeOnboardingIfPresented(app)

        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 240),
            "o feed do catálogo publicado precisa chegar à tela (onboarding: \(app.buttons.allElementsBoundByIndex.map(\.label)))")
        waitForExposure(app, scroll: scroll, name: "published-first-screen")
        let first = sampleFirstScreen(app, scroll: scroll, since: started)
        // `feed-launch-record` exists only in DEBUG. In Release (the shipped app) the same first exposure is
        // measured from the native accessibility frames already on screen: the viewport and the card frames. The
        // element is not even queried in Release: waiting on an identifier the product never draws is dead
        // instrumentation, not a measurement.
        let recordAvailable: Bool
        let record: LaunchRecord?
        #if DEBUG
        let recordElement = app.descendants(matching: .any)["feed-launch-record"]
        recordAvailable = recordElement.waitForExistence(timeout: 5)
        record = recordAvailable ? try launchRecord(app, name: "published-first-screen") : nil
        #else
        recordAvailable = false
        record = nil
        #endif

        let epsilonPoints = 1.0
        var violations: [String] = []
        if first.loadingSurface { violations.append("feed-loading-surface is on screen with the feed") }
        if first.launchProgress { violations.append("feed-launch-progress is on screen with the feed") }
        if first.emptySurface { violations.append("feed-empty-state is on screen with the feed") }
        let cards = record?.cards ?? first.totalCardFrames
        let contentBottom = record?.contentBottom ?? Double(first.contentBottom)
        let viewportHeight = record?.viewportHeight ?? Double(first.viewport.height)
        if cards < 1 { violations.append("the first presented layout never carried cards") }
        if contentBottom < viewportHeight - epsilonPoints {
            violations.append("o primeiro conteúdo apresentado termina em \(compact(contentBottom)) pt de um "
                + "viewport de \(compact(viewportHeight)) pt: \(compact(viewportHeight - contentBottom)) pt vazios")
        }
        attach(app, name: "published-first-screen",
            json: jsonLine(["namespace": recordAvailable ? namespace : "fresh-device-default-container",
                "measurement": recordAvailable ? "app-record" : "native-AX",
                "cards": cards, "content_bottom": contentBottom,
                "viewport_height": viewportHeight, "render_ready": record?.renderReadyCards ?? -1,
                "threshold_points": viewportHeight,
                "threshold_basis": recordAvailable
                    ? "app record viewport_height (proof.height)" :
                    "AX ScrollView height; the app proof.height is smaller by the bottom inset",
                "launch_record": record?.raw ?? "", "violations": violations]))
        XCTAssertTrue(violations.isEmpty, "published-first-screen: " + violations.joined(separator: " | "))
    }

    /// A outra entrada visível da primeira tela: o leitor escolhe explicitamente **"Todos os idiomas"** no
    /// Composer, sem nomear lugar ("Mundo todo"), e abre o feed. O rótulo é uma resposta — elegibilidade sem
    /// restrição de idioma — e não "nenhuma configuração": antes desta correção o perfil ficava vazio, o pool não
    /// produzia nada e a pessoa caía em "Escolher fontes". A prova é a exposição da superfície de leitura com
    /// cartas no catálogo publicado e sem fixtures; a geometria D4 fica registrada como informação, porque oferta
    /// viva varia e a régua dela precisa de oferta suficiente (a jornada broad e o fixture determinístico a medem).
    func testTheAllLanguagesEntryReachesDiscoveryOnThePublishedCatalogue() throws {
        let app = XCUIApplication()
        let namespace = UUID().uuidString
        app.launchEnvironment = ["FEEDMINE_RUNTIME_NAMESPACE": namespace]
        let started = Date()
        app.launch()

        let shape = app.buttons["welcome-shape"]
        XCTAssertTrue(shape.waitForExistence(timeout: 30),
            "o primeiro passo aparece num namespace novo; árvore=\(app.debugDescription)")
        shape.tap()
        let unrestricted = app.buttons["composer-languages-unrestricted"]
        XCTAssertTrue(unrestricted.waitForExistence(timeout: 30),
            "o Composer oferece a resposta 'Todos os idiomas'")
        unrestricted.tap()
        let open = app.buttons["composer-open-feed"]
        XCTAssertTrue(open.waitForExistence(timeout: 30), "o Composer oferece abrir o feed")
        XCTAssertTrue(open.isEnabled)
        open.tap()

        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 240),
            "'Todos os idiomas' precisa chegar à superfície de leitura, não a 'Escolher fontes' "
                + "(onboarding: \(app.buttons.allElementsBoundByIndex.map(\.label)))")
        waitForExposure(app, scroll: scroll, name: "all-languages-first-screen")
        let first = sampleFirstScreen(app, scroll: scroll, since: started)
        let record = try launchRecord(app, name: "all-languages-first-screen")

        // The clause under test is the variant itself: the explicit "Todos os idiomas" answer must reach discovery
        // instead of the source selection surface. D4's geometry is asserted by the broad-catalogue journey and by
        // the deterministic fixture journey; here the record's geometry is reported as information, because live
        // supply varies (measured 2026-10-20: one published card where the gate lifted).
        var violations: [String] = []
        if first.loadingSurface { violations.append("feed-loading-surface is on screen with the feed") }
        if first.launchProgress { violations.append("feed-launch-progress is on screen with the feed") }
        if first.emptySurface { violations.append("feed-empty-state is on screen with the feed") }
        if !first.placeholderTexts.isEmpty {
            violations.append("placeholder copy is on screen: \(first.placeholderTexts.joined(separator: " | "))")
        }
        if record.cards < 1 { violations.append("the app's record never carried cards") }
        let line = jsonLine(["test": "all-languages-first-screen", "namespace": namespace,
            "cards": record.cards, "content_bottom": record.contentBottom ?? -1,
            "viewport_height": record.viewportHeight ?? -1, "render_ready": record.renderReadyCards ?? -1,
            "d4_geometry": "informative", "launch_record": record.raw, "violations": violations])
        attach(app, name: "all-languages-first-screen", json: line)
        XCTAssertTrue(violations.isEmpty, "all-languages-first-screen: " + violations.joined(separator: " | "))
    }

    /// O onboarding do catálogo publicado, pela entrada **ampla** ("Começar amplo"): a pessoa não preenche
    /// formulário, aceita a sugestão de idioma que o host oferece (F02 §2.1) e entra no feed. É a jornada mais
    /// curta do produto e a que a primeira tela precisa medir; idioma e lugar explícitos são um cenário adicional,
    /// coberto por `testRealCatalogueCardsStayReachableByScrolling`.
    ///
    /// Pelos **identificadores** e nunca pelo texto: a língua das chaves é o português e o inglês é tradução, então
    /// uma jornada que pergunta por "Build my feed" não acha o botão quando roda com `-testLanguage pt-BR` (medido
    /// em 2026-10-20: onboarding ficou aberto até o timeout de 240 s).
    ///
    /// Returns without tapping when the installation was already prepared (the gate is not presented): a first
    /// run in this journey always has a fresh namespace, so the tap is the normal path.
    private func completeOnboardingIfPresented(_ app: XCUIApplication) {
        let broad = app.buttons["welcome-broad"]
        guard broad.waitForExistence(timeout: 20) else { return }
        broad.tap()
    }


    func testConnectionFailureSurfaceOffersARetryThatBringsContent() throws {
        let app = XCUIApplication()
        let namespace = UUID().uuidString
        var environment = configured(app, namespace: namespace, items: "12")
        // Local fixture on (the retry must have something to deliver), the public proxy off (it would block the
        // fixture too only if it claimed first — it does not, but the run does not need it), and the recoverable
        // fault that only the reader's retry clears.
        app.launchEnvironment["FEEDMINE_BLOCK_RSS_NETWORK"] = "0"
        app.launchEnvironment["FEEDMINE_FAIL_FIRST_FEED_ATTEMPT"] = "1"
        environment["FEEDMINE_BLOCK_RSS_NETWORK"] = "0"
        environment["FEEDMINE_FAIL_FIRST_FEED_ATTEMPT"] = "1"

        let started = Date()
        app.launch()
        let title = app.staticTexts["Não foi possível conectar."]
        XCTAssertTrue(title.waitForExistence(timeout: 120),
            "a falha de transporte precisa chegar à superfície aprovada; árvore=\(app.debugDescription)")
        let detail = app.staticTexts["Não conseguimos buscar novas histórias agora."]
        XCTAssertTrue(detail.exists, "a superfície diz o que não foi possível fazer")
        let surface = app.descendants(matching: .any)["feed-loading-surface"]
        XCTAssertTrue(surface.exists, "a falha vive na superfície que o leitor vê")
        let retry = app.buttons["Tentar novamente"]
        XCTAssertTrue(retry.exists, "a falha comprovada oferece tentar novamente")
        XCTAssertFalse(app.buttons["Ajustar interesses"].exists,
            "uma falha de conexão não pede para ajustar interesses")
        XCTAssertTrue(app.descendants(matching: .any)["feed-recovery-actions"].exists)

        let titleText = title.label
        let detailText = detail.label
        let before = try launchRecord(app, name: "connection-failure", waitForCards: false)
        XCTAssertEqual(before.cards, 0, "a falha inicial não carrega cartas")
        let failedAt = milliseconds(since: started)

        // The retry is the act under test. Everything below is the proof that it did real work.
        retry.tap()
        let card = app.descendants(matching: .any).matching(Self.cardIdentifier).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 120),
            "Tentar novamente precisa trazer conteúdo de verdade; árvore=\(app.debugDescription)")
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
            object: app.descendants(matching: .any)["feed-loading-surface"])
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 60), .completed,
            "a superfície de espera sai quando o conteúdo chega")
        let cardCount = app.descendants(matching: .any).matching(Self.cardIdentifier).count
        XCTAssertGreaterThan(cardCount, 0, "a tentativa de verdade publica cartas")
        let after = try launchRecord(app, name: "connection-recovered", waitForCards: true)
        let recoveredAt = milliseconds(since: started)

        let evidence: [String: Any] = [
            "test": "visible-connection-failure-retry",
            "namespace": namespace,
            "env": environment,
            "failed_at_ms": failedAt,
            "recovered_at_ms": recoveredAt,
            "surface_identifier": "feed-loading-surface",
            "title": titleText,
            "detail": detailText,
            "retry_offered": retry.exists,
            "adjust_offered": false,
            "before_record": before.raw,
            "before_cards": before.cards,
            "after_record": after.raw,
            "after_cards": after.cards,
            "card_count_after_retry": cardCount,
            "loading_surface_after_retry": app.descendants(matching: .any)["feed-loading-surface"].exists,
            "app_state": "\(app.state.rawValue)"
        ]
        let line = jsonLine(evidence)
        print("VISIBLE_FAILURE_JSON=\(line)")
        attach(app, name: "visible-connection-failure-retry", json: line)

        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertFalse(title.exists, "o conteúdo substitui a superfície de falha")
        XCTAssertFalse(app.descendants(matching: .any)["feed-loading-surface"].exists)
    }

    /// A failure behind content that is already on screen. The same namespace is opened once with the local fixture
    /// (content is admitted and its window is durable), then relaunched with every transport refused
    /// (`FEEDMINE_BLOCK_RSS_NETWORK=1`, no local fixture): the acquisition fails while the reader's own window is
    /// already restored, so the failure must never blank it or move it.
    func testFailureBehindPresentedContentPreservesCardsAndPosition() throws {
        let app = XCUIApplication()
        let namespace = UUID().uuidString
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = namespace
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_BLOCK_RSS_NETWORK"] = "0"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["FEEDMINE_FIXTURE_ITEMS"] = "12"
        app.launchEnvironment["FEEDMINE_TRACE_CAPTURE"] = "1"
        app.launch()

        let card = app.descendants(matching: .any).matching(Self.cardIdentifier).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 120), "o conteúdo é admitido antes da falha")
        let proof = app.staticTexts["feed-window-proof"]
        XCTAssertTrue(proof.waitForExistence(timeout: 60), "a janela admitida publica a sua prova")
        Thread.sleep(forTimeInterval: 2)
        let before = presentedState(app)
        let beforeProof = proof.label
        let beforeWindowCards = app.descendants(matching: .any).matching(Self.cardIdentifier).count
        XCTAssertFalse(before.visible.isEmpty, "há cartas visíveis antes da falha")

        // The same container, now with every connection refused and no fixture answering: the restored content is
        // the only thing that can be on screen, and a failure must leave it exactly as it was.
        app.terminate()
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "0"
        app.launchEnvironment["FEEDMINE_BLOCK_RSS_NETWORK"] = "1"
        let started = Date()
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any).matching(Self.cardIdentifier).firstMatch
            .waitForExistence(timeout: 120), "o conteúdo restaurado aparece com a rede recusada")
        Thread.sleep(forTimeInterval: 8)
        let after = presentedState(app)
        let afterProof = proof.label
        let afterWindowCards = app.descendants(matching: .any).matching(Self.cardIdentifier).count

        var violations: [String] = []
        if after.visible.isEmpty {
            violations.append("the failure blanked the presented cards")
        }
        if after.visible.map({ $0.identifier }) != before.visible.map({ $0.identifier }) {
            violations.append("the visible cards changed: \(before.visible.map({ $0.identifier })) -> "
                + "\(after.visible.map({ $0.identifier }))")
        }
        // Reading position is the vertical placement and the order; the horizontal inset is the shell's, not the
        // reader's position, and it legitimately settles after a relaunch.
        for (old, new) in zip(before.visible, after.visible)
        where abs(old.frame.minY - new.frame.minY) > 1 || abs(old.frame.height - new.frame.height) > 1 {
            violations.append("card \(old.identifier) moved: \(old.frame) -> \(new.frame)")
        }
        if admittedIDs(afterProof) != admittedIDs(beforeProof) {
            violations.append("the admitted window changed: \(admittedIDs(beforeProof)) -> "
                + "\(admittedIDs(afterProof))")
        }
        if afterWindowCards != beforeWindowCards {
            violations.append("the drawn window shrank: \(beforeWindowCards) -> \(afterWindowCards)")
        }
        if app.descendants(matching: .any)["feed-loading-surface"].exists {
            violations.append("the failure surface replaced the presented content")
        }
        if app.staticTexts["Não foi possível conectar."].exists
            || app.staticTexts["Falha ao atualizar o feed"].exists {
            violations.append("a failure banner is on screen over the content")
        }

        let record = try launchRecord(app, name: "failure-behind-content", waitForCards: false)
        let evidence: [String: Any] = [
            "test": "failure-behind-presented-content",
            "namespace": namespace,
            "env": ["second_launch": app.launchEnvironment],
            "before_proof": beforeProof,
            "after_proof": afterProof,
            "before_window_cards": beforeWindowCards,
            "after_window_cards": afterWindowCards,
            "before_visible": before.visible.map { ["id": $0.identifier, "frame": rect($0.frame)] },
            "after_visible": after.visible.map { ["id": $0.identifier, "frame": rect($0.frame)] },
            "launch_record_after_failure": record.raw,
            "elapsed_after_relaunch_ms": milliseconds(since: started),
            "violations": violations
        ]
        let line = jsonLine(evidence)
        print("VISIBLE_FAILURE_JSON=\(line)")
        attach(app, name: "failure-behind-presented-content", json: line)

        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(violations.isEmpty, "a falha por trás do conteúdo o alterou: "
            + "\(violations.joined(separator: " | ")) — json=\(line)")
    }

    // MARK: - Presented state

    private struct PresentedState {
        let visible: [(identifier: String, frame: CGRect)]
    }

    /// First field of `feed-window-proof`: the admitted ids, without the diagnostics that settle differently.
    private func admittedIDs(_ proof: String) -> String {
        proof.components(separatedBy: ";").first ?? proof
    }

    /// The cards the reader can see, in reading order, with the frames the tree reports.
    private func presentedState(_ app: XCUIApplication) -> PresentedState {
        let viewport = app.scrollViews.firstMatch.frame
        let visible = app.descendants(matching: .any).matching(Self.cardIdentifier).allElementsBoundByIndex
            .compactMap { element -> (identifier: String, frame: CGRect)? in
                let frame = element.frame
                guard frame.width > 0, frame.height > 0, frame.intersects(viewport) else { return nil }
                return (element.identifier, frame)
            }
            .sorted { $0.frame.minY < $1.frame.minY }
        return PresentedState(visible: visible)
    }

    // MARK: - Launch configuration

    /// The deterministic local run both tests start from. Returns the environment as it was actually handed to the
    /// app, for the evidence line.
    @discardableResult
    private func configured(_ app: XCUIApplication, namespace: String, items: String) -> [String: String] {
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = namespace
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_BLOCK_RSS_NETWORK"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["FEEDMINE_FIXTURE_ITEMS"] = items
        return app.launchEnvironment
    }

    // MARK: - First-screen measurement

    private struct FirstScreen {
        let window: CGRect
        let viewport: CGRect
        let totalCardFrames: Int
        /// The bottom of the lowest card frame, in viewport coordinates. `0` when no card frame exists.
        let contentBottom: CGFloat
        let fullyVisibleCards: Int
        let tallestCardHeight: CGFloat
        let loadingSurface: Bool
        let launchProgress: Bool
        let emptySurface: Bool
        let placeholderTexts: [String]
        let sampleMS: Int
    }

    /// One query of the live tree. The card list is read first so the state it describes is the moment the feed
    /// is on screen; the absence checks follow immediately.
    private func sampleFirstScreen(_ app: XCUIApplication, scroll: XCUIElement,
        since started: Date) -> FirstScreen {
        let window = app.windows.firstMatch.frame
        let viewport = scroll.frame
        let cards = app.descendants(matching: .any).matching(Self.cardIdentifier)
        let frames = cards.allElementsBoundByIndex.map(\.frame)
            .filter { $0.width > 0 && $0.height > 0 }
            .sorted { $0.minY < $1.minY }
        // A card counts as fully visible only when its whole frame is inside the viewport (1 pt of tolerance for
        // the fractional coordinates SwiftUI reports).
        let tolerance = viewport.insetBy(dx: -1, dy: -1)
        let fullyVisible = frames.filter { tolerance.contains($0) }
        let tallest = fullyVisible.map(\.height).max() ?? 0
        let contentBottom = frames.map(\.maxY).max().map { $0 - viewport.minY } ?? 0
        let placeholders = [
            "Descobrindo histórias para você…",
            "Ainda não encontramos histórias para você.",
            "Procurando mais novidades…",
            "Nenhuma fonte habilitada"
        ].filter { app.staticTexts[$0].exists }
        return FirstScreen(
            window: window,
            viewport: viewport,
            totalCardFrames: frames.count,
            contentBottom: contentBottom,
            fullyVisibleCards: fullyVisible.count,
            tallestCardHeight: tallest,
            loadingSurface: app.descendants(matching: .any)["feed-loading-surface"].exists,
            launchProgress: app.descendants(matching: .any)["feed-launch-progress"].exists,
            emptySurface: app.descendants(matching: .any)["feed-empty-state"].exists,
            placeholderTexts: placeholders,
            sampleMS: milliseconds(since: started))
    }

    // MARK: - The app's own launch record

    private struct LaunchRecord {
        let raw: String
        let waitPasses: Int
        let cards: Int
        let firstCardsMS: Int?
        let contentBottom: Double?
        let viewportHeight: Double?
        let renderReadyCards: Int?

        func value(_ field: String) -> String? {
            raw.split(separator: " ").map(String.init).first { $0.hasPrefix(field + "=") }
                .map { String($0.dropFirst(field.count + 1)) }
        }
    }

    /// D4 measures the **first exposure**, not the layout drawn under the preparation gate: while the gate holds,
    /// `feed-loading-surface` is still on screen over the laid-out cards, and a sample there judges the cover. The
    /// app's own record already froze the first exposure it must be compared with, so waiting (bounded) for the
    /// surface to leave is what "exposure" means; a gate that never lifts still fails the geometry and the surface
    /// presence below.
    private func waitForExposure(_ app: XCUIApplication, scroll: XCUIElement, name: String,
        timeout: TimeInterval = 120) {
        let surface = app.descendants(matching: .any)["feed-loading-surface"]
        if surface.exists {
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: surface)
            XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: timeout), .completed,
                "\(name): a superfície de preparação não saiu em \(Int(timeout)) s")
        }
        // The first **interactive** feed: the cover is gone and the scroll accepts a touch. This is not a wait for
        // content to cover the viewport; one card is the minimum that makes the surface the feed, not a blank hold.
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: scroll)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: timeout), .completed,
            "\(name): o feed não ficou interativo em \(Int(timeout)) s")
        let card = app.descendants(matching: .any).matching(Self.cardIdentifier).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: timeout), "\(name): o feed interativo não apresentou uma carta")
    }

    /// The record is an invisible text the app publishes (`feed-launch-record`). With `waitForCards` the read waits
    /// until the first pass that carried cards is on the record — the fact the first-screen test judges.
    private func launchRecord(_ app: XCUIApplication, name: String,
        waitForCards: Bool = true) throws -> LaunchRecord {
        let element = app.descendants(matching: .any)["feed-launch-record"]
        XCTAssertTrue(element.waitForExistence(timeout: 60), "\(name): o registro do próprio app é publicado")
        if waitForCards {
            let settled = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label MATCHES %@", ".*cards=[1-9].*content_bottom=-?[0-9].*"), object: element)
            _ = XCTWaiter.wait(for: [settled], timeout: 60)
        }
        let raw = element.label
        func text(_ field: String) -> String? {
            raw.split(separator: " ").map(String.init).first { $0.hasPrefix(field + "=") }
                .map { String($0.dropFirst(field.count + 1)) }
        }
        func integer(_ field: String) -> Int? { text(field).flatMap(Int.init) }
        func number(_ field: String) -> Double? { text(field).flatMap(Double.init) }
        return LaunchRecord(raw: raw,
            waitPasses: integer("wait_passes") ?? -1,
            cards: integer("cards") ?? -1,
            firstCardsMS: integer("first_cards_ms"),
            contentBottom: number("content_bottom"),
            viewportHeight: number("viewport_height"),
            renderReadyCards: integer("render_ready_cards"))
    }

    /// One decimal place, for assertion text only.
    private func compact(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    // MARK: - Evidence

    private func attach(_ app: XCUIApplication, name: String, json: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "\(name)-screenshot"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "\(name)-accessibility-tree"
        tree.lifetime = .keepAlways
        add(tree)

        let evidence = XCTAttachment(string: json)
        evidence.name = "\(name)-state-json"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    private func jsonLine(_ fields: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
            let text = String(data: data, encoding: .utf8) else {
            return "{\"error\":\"state not encodable\"}"
        }
        return text
    }

    private func rect(_ frame: CGRect) -> [String: Any] {
        ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]
    }

    private func milliseconds(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }
}
