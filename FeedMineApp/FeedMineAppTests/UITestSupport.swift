// File: UITestSupport.swift
// Module: FeedMineUITests
// Owns: the few helpers every surface journey shares — launching the hermetic fixture feed, opening the reader
//       menu, reaching a row in a sheet's list, and waiting for an absence — plus the seeded, stratified picker
//       used by journeys that walk *real* published content.
// Does not own: any product decision or a second driver. Every helper performs the same gesture a reader does.

import XCTest
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif

enum SurfaceTest {
    static let feedTimeout: TimeInterval = 60

    /// The hermetic launch every surface journey starts from: the local fixture feed, no network, no discovery,
    /// no onboarding. The caller may override or add variables; the namespace is always fresh.
    @MainActor
    static func launchFixture(_ extra: [String: String] = [:],
        namespace: String = UUID().uuidString) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = namespace
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_FIXTURE_ITEMS"] = "12"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["FEEDMINE_BLOCK_RSS_NETWORK"] = "1"
        app.launchEnvironment["FEEDMINE_DISABLE_DISCOVERY"] = "1"
        for (key, value) in extra { app.launchEnvironment[key] = value }
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: feedTimeout),
            "the fixture feed must present before a surface journey starts")
        XCTAssertTrue(app.buttons["more-menu"].waitForExistence(timeout: 20),
            "the reader chrome is up")
        return app
    }

    /// Any element with this identifier, whatever role SwiftUI exposed it as (`Menu` is a pop-up button,
    /// a `Toggle` a switch, a `NavigationLink` a button).
    @MainActor
    static func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
    }

    @MainActor
    static func openMenu(_ app: XCUIApplication) {
        let menu = app.buttons["more-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20), "the header offers the overflow menu")
        menu.tap()
    }

    /// Opens the overflow menu and taps the entry with the localized label the build draws.
    @MainActor
    static func menuEntry(_ app: XCUIApplication, _ label: String) {
        openMenu(app)
        // Measured on iOS 26: a SwiftUI `Menu`'s items are exposed as plain buttons, not inside a `menus`
        // element. The button form is therefore tried first; the `menus` form is kept for the Mac host.
        let visible = app.buttons[label].firstMatch
        if visible.waitForExistence(timeout: 5) {
            visible.tap()
            return
        }
        let item = app.menus.buttons[label].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "menu entry \(label) is offered")
        item.tap()
    }

    /// A row of a scrolling list is not in the accessibility hierarchy until it has been scrolled into view.
    /// The gesture is the reader's own scroll, on the list that is on screen.
    @MainActor
    @discardableResult
    static func scrollIntoView(_ element: XCUIElement, in app: XCUIApplication,
        timeout: TimeInterval = 20) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.isHittable { return true }
            let table = app.tables.firstMatch
            if table.exists { table.swipeUp() } else { app.swipeUp() }
        }
        return element.exists && element.isHittable
    }

    /// `waitForExistence` cannot express absence: it returns at once while the element is still there.
    @MainActor
    static func waitForAbsence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    @MainActor
    static func waitForValue(_ element: XCUIElement, differentFrom value: String?,
        timeout: TimeInterval = 20) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", value ?? ""), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Replaces a focused text field's value with the reader's text, using the field's own delete key.
    @MainActor
    static func replaceText(_ field: XCUIElement, with text: String) {
        field.tap()
        if let value = field.value as? String, !value.isEmpty,
            value != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        field.typeText(text)
    }

    @MainActor
    static func dismissSystemSheet(_ app: XCUIApplication) {
        // The share sheet's own dismiss control, or a swipe when the platform draws none.
        for label in ["Close", "Fechar", "Cancel", "Cancelar", "Done", "Concluído"] {
            let button = app.buttons[label].firstMatch
            if button.exists && button.isHittable { button.tap(); return }
        }
        app.swipeDown()
    }

    /// A published card is an element whose identifier is the occurrence UUID. The first *visible* one is the
    /// reader's reading point; the app exposes its own card container with that identifier.
    @MainActor
    static func firstCard(_ app: XCUIApplication) -> XCUIElement? {
        let cards = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier MATCHES %@",
                "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"))
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            for index in 0..<min(cards.count, 6) {
                let card = cards.element(boundBy: index)
                if card.exists && card.isHittable { return card }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return nil
    }
}

/// Deterministic stratified sampling for journeys over *real* published content.
///
/// The universe is whatever identifiers the surface actually exposes (strata are supplied by the caller: e.g.
/// text/audio/video, short/long title). Within each stratum the order is `SHA-256(seed + stratum + id)`, so the
/// same seed and the same universe always produce the same picks. The seed and the picked identifiers (and the
/// fingerprint of the whole choice) are printed and attached by the caller, which is what makes a red run
/// replayable: `FEEDMINE_CONTENT_SEED=<seed>` reproduces exactly the same selection.
struct SeededStratifiedSample {
    let seed: String
    let picks: [(stratum: String, id: String)]

    init(seed: String, strata: [String: [String]], perStratum: Int = 1) {
        self.seed = seed
        var picked: [(String, String)] = []
        for stratum in strata.keys.sorted() {
            let ids = (strata[stratum] ?? []).sorted { lhs, rhs in
                Self.digest("\(seed)|\(stratum)|\(lhs)") < Self.digest("\(seed)|\(stratum)|\(rhs)")
            }
            for id in ids.prefix(perStratum) { picked.append((stratum, id)) }
        }
        self.picks = picked
    }

    /// The seed for this run: the environment's replay value, or a fresh one printed with the picks.
    static func seedFromEnvironment(_ variable: String = "FEEDMINE_CONTENT_SEED") -> String {
        ProcessInfo.processInfo.environment[variable] ?? UUID().uuidString
    }

    var fingerprint: String {
        Self.digest(picks.map { "\($0.stratum)=\($0.id)" }.joined(separator: ";"))
    }

    var record: String {
        "SEEDED_SAMPLE seed=\(seed) fingerprint=\(fingerprint) picks="
            + picks.map { "\($0.stratum):\($0.id)" }.joined(separator: ",")
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
