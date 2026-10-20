import UIKit
import XCTest

/// The two facts the architect asked to see, measured on the screen instead of argued in a report:
///
///  1. **the preparation → feed transition**: at the first observable moment the feed is on screen, the visible
///     viewport is already covered by ready cards — not one card that completes later. The app's own launch record
///     (`FeedLaunchWitness`, `feed-launch-record`) says how many cards the **first pass that carried cards** had;
///     the XCTest side measures the geometry of that moment (cards fully inside the viewport, the tallest card, the
///     largest gap between them, the covered fraction). A single card cannot pass both halves.
///  2. **the visible failure**: the deterministic transport fault the app itself installs
///     (`FEEDMINE_BLOCK_RSS_NETWORK=1`, a closed local proxy) must end on the approved surface — "Não foi possível
///     conectar." plus its explanation and "Tentar novamente" — and that surface is captured (screenshot,
///     accessibility tree, JSON) rather than described.
///
/// The generic non-transport branch (`.failed(message: "Falha ao atualizar o feed")` in
/// `AppComposition.reportFailure`) has no launch knob that reaches it: `FEEDMINE_EMPTY_FEEDS=1` states
/// `.unavailable` ("Ainda não encontramos histórias para você."), `FEEDMINE_EMPTY_SELECTION=1` draws the source
/// empty state, and the transport fault states `.unreachable`. Producing `.failed` from a test would mean adding a
/// production failure path, which this delivery does not do.
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
    func testFirstScreenIsFilledWhenTheFeedAppears() throws {
        let app = XCUIApplication()
        let namespace = UUID().uuidString
        let environment = configured(app, namespace: namespace, items: "12")
        let started = Date()
        app.launch()
        let idleMS = milliseconds(since: started)

        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 120), "o feed precisa chegar à tela")
        // The first sample XCTest can take: `launch()` returns once the app is idle. What happened *before* this
        // sample is the app's own record, read right after, on the process's own clock.
        let first = sampleFirstScreen(app, scroll: scroll, since: started)
        let record = try launchRecord(app, name: "first-screen")

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
        if first.fullyVisibleCards < 2 {
            violations.append("only \(first.fullyVisibleCards) card(s) fully inside the viewport")
        }
        if first.fullyVisibleCards >= 2, first.largestGap > first.tallestCardHeight {
            violations.append("a \(Int(first.largestGap)) pt gap between cards is wider than the tallest card "
                + "(\(Int(first.tallestCardHeight)) pt)")
        }
        // The record is captured, not thresholded: it counts the **body passes** that carried cards, and a pass can
        // be replaced before it is drawn (the witness's own documentation says so). What the criterion measures is
        // the first observable screen, which is the geometry above. `record.cards` and `record_first_cards_ms` stay
        // in the evidence so the app-side order (wait surfaces, first card-carrying pass) is never lost.
        if record.firstCardsMS == nil {
            violations.append("the app's record never observed a pass that carried cards")
        }

        let evidence: [String: Any] = [
            "test": "first-screen-filled",
            "namespace": namespace,
            "env": environment,
            "launch_returned_ms": idleMS,
            "first_sample_ms": first.sampleMS,
            "window": rect(first.window),
            "viewport": rect(first.viewport),
            "card_frames_total": first.totalCardFrames,
            "cards_fully_visible": first.fullyVisibleCards,
            "tallest_card_height": first.tallestCardHeight,
            "largest_gap": first.largestGap,
            "covered_fraction": first.coveredFraction,
            "loading_surface": first.loadingSurface,
            "launch_progress": first.launchProgress,
            "empty_surface": first.emptySurface,
            "placeholder_texts": first.placeholderTexts,
            "launch_record": record.raw,
            "record_cards": record.cards,
            "record_first_cards_ms": record.firstCardsMS ?? -1,
            "record_wait_passes": record.waitPasses,
            "violations": violations
        ]
        let line = jsonLine(evidence)
        print("VISIBLE_FIRST_SCREEN_JSON=\(line)")
        attach(app, name: "first-screen-filled", json: line)

        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(violations.isEmpty, "a primeira tela do feed não estava preenchida: "
            + "\(violations.joined(separator: " | ")) — record=\(record.raw) json=\(line)")
    }

    // MARK: - 2. The visible failure

    /// The transport fault is the app's own configuration, not a mock: the session refuses every public connection
    /// through a closed local proxy, the development feeds cannot answer, and the handoff states `.unreachable`.
    func testConnectionFailureSurfaceIsVisibleAndCaptured() throws {
        let app = XCUIApplication()
        let namespace = UUID().uuidString
        var environment = configured(app, namespace: namespace, items: "12")
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "0"
        app.launchEnvironment["FEEDMINE_BLOCK_RSS_NETWORK"] = "1"
        environment["FEEDMINE_LOCAL_FEEDS"] = "0"
        environment["FEEDMINE_BLOCK_RSS_NETWORK"] = "1"

        let started = Date()
        app.launch()
        let title = app.staticTexts["Não foi possível conectar."]
        XCTAssertTrue(title.waitForExistence(timeout: 300),
            "a falha de transporte precisa chegar à superfície aprovada; árvore=\(app.debugDescription)")
        let detail = app.staticTexts["Não conseguimos buscar novas histórias agora."]
        XCTAssertTrue(detail.exists, "a superfície diz o que não foi possível fazer")
        let surface = app.descendants(matching: .any)["feed-loading-surface"]
        XCTAssertTrue(surface.exists, "a falha vive na superfície que o leitor vê")
        let retry = app.buttons["Tentar novamente"]
        XCTAssertTrue(retry.exists, "a falha comprovada oferece tentar novamente")
        let adjust = app.buttons["Ajustar interesses"]
        XCTAssertFalse(adjust.exists, "uma falha de conexão não pede para ajustar interesses")
        XCTAssertTrue(app.descendants(matching: .any)["feed-recovery-actions"].exists)

        let record = try launchRecord(app, name: "connection-failure", waitForCards: false)
        let elapsedMS = milliseconds(since: started)

        let evidence: [String: Any] = [
            "test": "visible-connection-failure",
            "namespace": namespace,
            "env": environment,
            "elapsed_ms": elapsedMS,
            "surface_identifier": "feed-loading-surface",
            "title": title.label,
            "detail": detail.label,
            "retry_offered": retry.exists,
            "adjust_offered": adjust.exists,
            "launch_record": record.raw,
            "record_cards": record.cards,
            "record_wait_passes": record.waitPasses,
            "app_state": "\(app.state.rawValue)"
        ]
        let line = jsonLine(evidence)
        print("VISIBLE_FAILURE_JSON=\(line)")
        attach(app, name: "visible-connection-failure", json: line)

        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertEqual(title.label, "Não foi possível conectar.")
        XCTAssertEqual(record.cards, 0, "uma falha de conexão não carrega cartas")
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
        let largestGap: CGFloat
        let coveredFraction: Double
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
        let gaps: [CGFloat] = fullyVisible.indices.dropFirst().map { index in
            max(0, fullyVisible[index].minY - fullyVisible[index - 1].maxY)
        }
        let largestGap = gaps.max() ?? 0
        let coveredFraction = fullyVisible.isEmpty
            ? 0 : Self.coveredHeight(fullyVisible, in: viewport) / max(1, viewport.height)
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
            largestGap: largestGap,
            coveredFraction: coveredFraction,
            loadingSurface: app.descendants(matching: .any)["feed-loading-surface"].exists,
            launchProgress: app.descendants(matching: .any)["feed-launch-progress"].exists,
            emptySurface: app.descendants(matching: .any)["feed-empty-state"].exists,
            placeholderTexts: placeholders,
            sampleMS: milliseconds(since: started))
    }

    /// The union of the card rectangles clipped to the viewport, as a height: cards span the viewport's width, so
    /// this is the part of the visible area a ready card covers.
    private static func coveredHeight(_ frames: [CGRect], in viewport: CGRect) -> CGFloat {
        let intervals = frames.map { frame in
            let clipped = frame.intersection(viewport)
            return (minY: max(0, clipped.minY - viewport.minY), maxY: max(0, clipped.maxY - viewport.minY))
        }.sorted { $0.minY < $1.minY }
        var covered: CGFloat = 0
        var cursor: CGFloat = 0
        for interval in intervals where interval.maxY > cursor {
            let start = max(cursor, interval.minY)
            covered += interval.maxY - start
            cursor = interval.maxY
        }
        return covered
    }

    // MARK: - The app's own launch record

    private struct LaunchRecord {
        let raw: String
        let waitPasses: Int
        let cards: Int
        let firstCardsMS: Int?

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
                predicate: NSPredicate(format: "label MATCHES %@", ".*cards=[1-9].*"), object: element)
            _ = XCTWaiter.wait(for: [settled], timeout: 60)
        }
        let raw = element.label
        func integer(_ field: String) -> Int? { Int(raw.split(separator: " ").map(String.init)
            .first { $0.hasPrefix(field + "=") }?.dropFirst(field.count + 1) ?? "") }
        return LaunchRecord(raw: raw,
            waitPasses: integer("wait_passes") ?? -1,
            cards: integer("cards") ?? -1,
            firstCardsMS: integer("first_cards_ms"))
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
