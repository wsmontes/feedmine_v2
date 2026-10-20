import UIKit
import XCTest

/// The facts the architect asked to see, measured instead of argued in a report:
///
///  1. **the first presented screen reaches the bottom of the viewport** — a single criterion, no average and no
///     fraction: in the first card-carrying presentation the bottom of the last laid-out card is at (or below) the
///     viewport bottom, with 1 pt of tolerance. The measurement comes from the app's own record
///     (`FeedLaunchWitness`, `feed-launch-record`: `content_bottom`, `viewport_height`, `cards`), taken where
///     `FeedScreen` lays the cards out, because `XCUIApplication.launch()` only returns after the app is idle and
///     can never witness the first frame. Today the record carries one card, so this test is expected to FAIL: the
///     product fix (hold the presentation until the screen is covered) is the architect's, not the test's.
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
        // The criterion itself is the app's own record: the geometry of the **first card-carrying presentation**,
        // measured where the cards were laid out (`FeedLaunchWitness.noteCardsGeometry`).
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
        let viewportHeight = record.viewportHeight
        if contentBottom == nil || viewportHeight == nil {
            violations.append("the app's record did not capture the first card-carrying layout")
        } else if let contentBottom, let viewportHeight,
            contentBottom < viewportHeight - epsilonPoints {
            violations.append("the first presented content stops at \(compact(contentBottom)) pt of a "
                + "\(compact(viewportHeight)) pt viewport: a \(compact(viewportHeight - contentBottom)) pt gap below "
                + "the last laid-out card (epsilon \(epsilonPoints) pt)")
        }

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

        func value(_ field: String) -> String? {
            raw.split(separator: " ").map(String.init).first { $0.hasPrefix(field + "=") }
                .map { String($0.dropFirst(field.count + 1)) }
        }
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
            viewportHeight: number("viewport_height"))
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
