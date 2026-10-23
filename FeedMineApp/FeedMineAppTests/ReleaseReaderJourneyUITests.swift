// File: ReleaseReaderJourneyUITests.swift
// Module: FeedMineUITests
// Owns: the permanent Release journeys over *real public content* — a short teaser that opens the site, a long
//       article read on the local surface, the saved/read-back path, the existing appearance controls measured on
//       the local surface, and a real audio episode. No DEBUG fixture, namespace or product test seam is used:
//       the reader starts the normal optimized app, adds the same public feeds a reader adds, and every step is a
//       gesture on the published UI.
//
// Opt in because these journeys reach the public catalogue and network:
//   xcrun simctl spawn <udid> launchctl setenv FEEDMINE_LIVE_READER 1
//   xcodebuild test-without-building … -only-testing:FeedMineUITests/ReleaseReaderJourneyUITests
//   xcrun simctl spawn <udid> launchctl unsetenv FEEDMINE_LIVE_READER
//
// The sample is the registered seed 20261022 over three public strata:
//   short teaser → site      https://pt.euronews.com/rss
//   long body → local reader https://www.egyptindependent.com/feed/
//   podcast/audio            https://rss.art19.com/rss (episode enclosures; see spec below)
// Public RSS changes: the tests assert the *shape* of each stratum (site vs local, body length, clock advance),
// never a frozen headline, and print the card UUID/title/label actually used so a red run is replayable.

import XCTest
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif

/// A tiny deterministic PRNG (SplitMix64). It exists so the seed selects the public occurrence instead of only
/// appearing in a log line; no framework and no dependency.
private struct SeededRandom {
    private var state: UInt64

    init(seed: String) {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        state = hash == 0 ? 0x9e3779b97f4a7c15 : hash
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }

    mutating func index(count: Int) -> Int {
        count > 0 ? Int(next() % UInt64(count)) : 0
    }
}

@MainActor
final class ReleaseReaderJourneyUITests: XCTestCase {
    private static let seed = ProcessInfo.processInfo.environment["FEEDMINE_CONTENT_SEED"] ?? "20261022"
    private static let euronewsFeed = "https://pt.euronews.com/rss"
    private static let egyptFeed = "https://www.egyptindependent.com/feed/"
    private static let adriftFeed = "https://rss.art19.com/adrift"
    /// Whether the last seeded pick had at least one real candidate (distinguishes an absent stratum from a
    /// harness reacquisition failure; only the former may skip).
    private var lastSampleHadCandidates = false

    private static var cardIdentifier: NSPredicate {
        NSPredicate(format: "identifier MATCHES %@",
            "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")
    }

    // MARK: - Entry

    private func launch(_ arguments: [String] = []) throws -> XCUIApplication {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FEEDMINE_LIVE_READER"] == "1",
            "opt-in: FEEDMINE_LIVE_READER=1 reaches the public catalogue and network")
        let app = XCUIApplication()
        // The product's source language is Portuguese and its labels are the ones the original journeys were
        // written against. The device language is an app-language preference, not a product seam: the same app,
        // the same catalogue, the same controls.
        app.launchArguments += ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launchArguments += arguments
        app.launch()
        // On a clean install the gate can arrive a little after the feed's chrome is already in the tree, and
        // while it covers the screen the header is not hittable. The gate is dismissed by its own broad action;
        // the loop waits for the reader's chrome to be really reachable, not merely present.
        let menu = app.buttons["more-menu"]
        let deadline = Date().addingTimeInterval(240)
        while Date() < deadline {
            if dismissGate(app) { continue }
            if centerInsideWindow(menu, app) { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(menu.exists, "the Release reader chrome is up")
        XCTAssertFalse(byIdentifier(app, "onboarding").exists,
            "the onboarding gate is dismissed before the journey starts")
        // An isolated reader with no selected source is a legitimate state: its own "Nenhuma fonte habilitada"
        // surface has no ScrollView. The chrome being usable is the readiness this helper can require; a source
        // journey asserts the content surface it actually needs.
        return app
    }

    private func byIdentifier(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func record(_ name: String, _ text: String) {
        print("REALREADER \(name): \(text)")
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Public sample

    /// The gate can be the first-run welcome, the composer it leads to, or the curated composer reached from the
    /// menu. Each has its own dismissal control; tapping the one really on screen is the reader's gesture.
    private func centerInsideWindow(_ element: XCUIElement, _ app: XCUIApplication) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        let window = app.windows.firstMatch.frame
        guard frame.width > 1, frame.height > 1 else { return false }
        return window.contains(CGPoint(x: frame.midX, y: frame.midY))
    }

    private func dismissGate(_ app: XCUIApplication) -> Bool {
        let gate = byIdentifier(app, "onboarding")
        guard gate.exists else { return false }
        // Close, not "start broad": the journeys isolate their own three public sources through Add Feed. A broad
        // discovery profile makes the first preparation enormous and is not part of the reader path being measured.
        for label in ["onboarding-close", "welcome-broad", "composer-start-broad"] {
            let control = byIdentifier(app, label)
            if centerInsideWindow(control, app) {
                control.tap()
                Thread.sleep(forTimeInterval: 1)
                return true
            }
        }
        return false
    }

    private func waitForMenu(_ app: XCUIApplication, timeout: TimeInterval = 60) -> Bool {
        let menu = app.buttons["more-menu"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if dismissGate(app) { continue }
            if centerInsideWindow(menu, app) { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return centerInsideWindow(menu, app)
    }

    /// The reading point is durable, so a previous failed run can leave the feed deep in the sequence. A new
    /// source's cards can then be above the viewport, and a downward-only scan would never see them. The reader's
    /// own status-bar gesture returns a scroll view to the top; bounded swipes finish the job.
    private func scrollFeedToTop(_ app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        guard scroll.exists else { return }
        let status = app.statusBars.firstMatch
        if status.exists { status.tap() } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).tap()
        }
        Thread.sleep(forTimeInterval: 0.8)
        for _ in 0..<18 {
            scroll.swipeDown(velocity: .fast)
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// Adds the public feed through the product's own add-feed sheet, then waits for its card. The sheet's
    /// resolution, selection and acquisition are the product's; nothing is injected.
    /// The product's own source-context control: `reader-contexts` lists the selected sources, and choosing one
    /// makes that source the reading context. A newly added source's publication is source-scoped, so the main
    /// context (which may hold an older edition from many sources) is not where its cards appear.
    private func selectSourceContext(_ app: XCUIApplication, containing needles: [String]) -> Bool {
        let label = byIdentifier(app, "reader-context-label")
        if label.exists, needles.contains(where: { label.label.range(of: $0, options: .caseInsensitive) != nil }) {
            return true
        }
        guard waitForMenu(app) else { return false }
        let contexts = app.buttons["reader-contexts"]
        guard centerInsideWindow(contexts, app) else { return false }
        contexts.tap()
        let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: needles.map {
            NSPredicate(format: "label CONTAINS[cd] %@", $0)
        })
        let item = app.buttons.matching(predicate).firstMatch
        guard item.waitForExistence(timeout: 10) else { return false }
        item.tap()
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            if label.exists, needles.contains(where: { label.label.range(of: $0, options: .caseInsensitive) != nil }) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    private func ensureSource(_ app: XCUIApplication, containing needles: [String],
        feed: String, timeout: TimeInterval = 240) -> XCUIElement? {
        var existing = sourceCard(app, containing: needles, timeout: 25)
        if existing == nil {
            scrollFeedToTop(app)
            existing = sourceCard(app, containing: needles, timeout: 25)
        }
        if existing == nil {
        XCTAssertTrue(waitForMenu(app), "the reader menu is reachable before adding a source")
        SurfaceTest.menuEntry(app, "Adicionar feed")
        XCTAssertTrue(app.navigationBars["Adicionar fontes"].waitForExistence(timeout: 30),
            "the add-feed sheet is up")
        let field = app.textFields["add-feed-input"]
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        field.tap()
        field.typeText(feed)
        let add = app.buttons["add-feed-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        // Up to five feeds are added in one action; more than that states a preview first. Wait until the sheet
        // either states a result or offers the preview, then finish the product's own confirmation.
        let result = byIdentifier(app, "add-feed-result-added")
        let preview = byIdentifier(app, "add-feed-preview-entry")
        let rejection = app.staticTexts["add-feed-error"]
        let already = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'já estava'")).firstMatch
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline, !result.exists, !preview.exists, !rejection.exists, !already.exists {
            Thread.sleep(forTimeInterval: 1)
        }
        if preview.exists && !result.exists {
            add.tap()
            _ = result.waitForExistence(timeout: 120)
        }
        if rejection.exists {
            record("add-feed-error", "feed=\(feed) error=\(rejection.label)")
        }
        record("add-feed", "feed=\(feed) added=\(result.exists) alreadySelected=\(already.exists) "
            + "preview=\(preview.exists) error=\(rejection.exists ? rejection.label : "-")")
        app.buttons["add-feed-cancel"].tap()
        _ = waitForMenu(app)
        _ = dismissGate(app)
        }
        let switched = selectSourceContext(app, containing: needles)
        record("source-context", "needles=\(needles.joined(separator: ",")) switched=\(switched)")
        scrollFeedToTop(app)
        return sourceCard(app, containing: needles, timeout: timeout)
    }

    /// The first visible card whose own label (or one of its texts) names the source and whose opening control
    /// can really be used. The reader scroll is the only way a card outside the window is reached.
    private func sourceCard(_ app: XCUIApplication, containing needles: [String],
        timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        var lastSwipe = Date()
        while Date() < deadline {
            if let card = match(app, containing: needles) { return card }
            if Date().timeIntervalSince(lastSwipe) > 6 {
                let scroll = app.scrollViews.firstMatch
                if scroll.exists { scroll.swipeUp() } else { app.swipeUp() }
                lastSwipe = Date()
            }
            Thread.sleep(forTimeInterval: 1)
        }
        return match(app, containing: needles)
    }

    private func match(_ app: XCUIApplication, containing needles: [String],
        requireHittable: Bool = true) -> XCUIElement? {
        let window = app.windows.firstMatch.frame
        let cards = app.descendants(matching: .any).matching(Self.cardIdentifier).allElementsBoundByIndex
        for card in cards where card.exists && card.frame.height > 40 && card.frame.intersects(window) {
            let open = card.buttons["card.open"].firstMatch
            guard open.exists else { continue }
            if requireHittable {
                let frame = open.frame
                let center = CGPoint(x: frame.midX, y: frame.midY)
                guard frame.width > 1, frame.height > 1, window.contains(center) else { continue }
            }
            let names = [card.label] + card.staticTexts.allElementsBoundByIndex.map(\.label)
            if names.contains(where: { name in
                needles.contains { name.range(of: $0, options: .caseInsensitive) != nil }
            }) {
                return card
            }
        }
        return nil
    }

    /// Visible cards matching the stratum's source, with a usable opening control (and a play control when the
    /// stratum is audio). Used only to enumerate candidates for a seeded pick.
    private func visibleMatchingCards(_ app: XCUIApplication, containing needles: [String],
        requirePlay: Bool) -> [XCUIElement] {
        let window = app.windows.firstMatch.frame
        return app.descendants(matching: .any).matching(Self.cardIdentifier).allElementsBoundByIndex.filter { card in
            guard card.exists, card.frame.height > 40, card.frame.intersects(window) else { return false }
            let open = card.buttons["card.open"].firstMatch
            guard open.exists, centerInsideWindow(open, app) else { return false }
            if requirePlay {
                let play = card.buttons["card.play"].firstMatch
                guard play.exists, centerInsideWindow(play, app) else { return false }
            }
            let names = [card.label] + card.staticTexts.allElementsBoundByIndex.map(\.label)
            return names.contains { name in
                needles.contains { name.range(of: $0, options: .caseInsensitive) != nil }
            }
        }
    }

    /// Bounded enumeration from the reader's current position — the position where `ensureSource` actually found
    /// the stratum card. Starting at the top would miss Adrift, whose card can sit far down the sequence, and the
    /// two-empty-screen stop is applied only after the first matching candidate exists. The sort makes the candidate
    /// list independent of scroll order; the seed selects the index within it.
    private func candidateUUIDs(_ app: XCUIApplication, containing needles: [String],
        requirePlay: Bool, screensScanned: inout Int) -> [String] {
        var seen = Set<String>()
        var emptyScreens = 0
        for screen in 0..<5 {
            let before = seen.count
            for card in visibleMatchingCards(app, containing: needles, requirePlay: requirePlay) {
                seen.insert(card.identifier)
            }
            screensScanned = screen + 1
            if !seen.isEmpty {
                emptyScreens = seen.count == before ? emptyScreens + 1 : 0
                if emptyScreens >= 2 { break }
            }
            let scroll = app.scrollViews.firstMatch
            if scroll.exists { scroll.swipeUp() } else { break }
        }
        return seen.sorted()
    }

    /// Reacquisition is bounded: first around the current position (rewound by the number of screens the candidate
    /// scan advanced), then a top-down fallback. No whole-feed linear search is added.
    private func bringIntoView(_ app: XCUIApplication, _ uuid: String, rewind screens: Int = 0) -> XCUIElement? {
        func visible() -> XCUIElement? {
            let card = cardWithUUID(app, uuid)
            return card.exists && centerInsideWindow(card, app) ? card : nil
        }
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<min(screens, 5) {
            if scroll.exists { scroll.swipeDown() }
        }
        if let card = visible() { return card }
        for _ in 0..<8 {
            if scroll.exists { scroll.swipeUp() } else { break }
            if let card = visible() { return card }
        }
        scrollFeedToTop(app)
        for _ in 0..<20 {
            if let card = visible() { return card }
            if scroll.exists { scroll.swipeUp() } else { break }
        }
        return nil
    }

    /// The mission's reproducible random pick: seed -> index over the actual available matching cards, bounded to
    /// the visible screens of the real feed. The record carries seed, candidate count, index, UUID, feed and title.
    private func pickCard(_ app: XCUIApplication, containing needles: [String], requirePlay: Bool = false,
        feed: String, label: String) -> XCUIElement? {
        var screensScanned = 0
        let candidates = candidateUUIDs(app, containing: needles, requirePlay: requirePlay,
            screensScanned: &screensScanned)
        lastSampleHadCandidates = !candidates.isEmpty
        guard !candidates.isEmpty else {
            record("\(label)-sample-empty", "seed=\(Self.seed) feed=\(feed) candidates=0")
            return nil
        }
        var random = SeededRandom(seed: Self.seed + "|\(label)|" + feed)
        let index = random.index(count: candidates.count)
        let uuid = candidates[index]
        guard let card = bringIntoView(app, uuid, rewind: screensScanned) else {
            record("\(label)-sample-missing", "seed=\(Self.seed) candidates=\(candidates.count) "
                + "index=\(index) uuid=\(uuid) feed=\(feed)")
            return nil
        }
        let title = card.staticTexts["card.title"].firstMatch.label
        let digest = SHA256.hash(data: Data(candidates.joined(separator: ",").utf8))
            .map { String(format: "%02x", $0) }.joined()
        record("\(label)-sample", "seed=\(Self.seed) candidates=\(candidates.count) index=\(index) "
            + "uuid=\(uuid) feed=\(feed) title=\(title) candidates_sha256=\(digest) "
            + "item_url=not-exposed-by-card body_hash=not-observed-in-app")
        return card
    }

    private func cardWithUUID(_ app: XCUIApplication, _ uuid: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", uuid)).firstMatch
    }

    /// The same published occurrence, never "another card of the same source". The feed keeps its scroll when a
    /// sheet closes, so the card is normally already in the tree; a bounded reader scroll finds it after a relaunch.
    private func sameCard(_ app: XCUIApplication, _ uuid: String, timeout: TimeInterval = 60) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        var swipes = 0
        let window = app.windows.firstMatch.frame
        while Date() < deadline {
            let card = cardWithUUID(app, uuid)
            if card.exists {
                let frame = card.frame
                let center = CGPoint(x: frame.midX, y: frame.midY)
                if frame.height > 1, window.contains(center) { return card }
                if swipes < 12, frame.height > 1 {
                    if frame.midY < window.midY { app.swipeDown() } else { app.swipeUp() }
                    swipes += 1
                }
            } else if swipes < 12 {
                let scroll = app.scrollViews.firstMatch
                if scroll.exists { scroll.swipeUp() }
                swipes += 1
            }
            Thread.sleep(forTimeInterval: 1)
        }
        return nil
    }

    /// One tap on the occurrence's own opening control, re-queried immediately before the tap: the feed admits
    /// new cards while a journey runs, and an element captured a moment earlier can be stale (its activation point
    /// stops being computable). The element query is live, so this is still one reader gesture on the card.
    private func open(_ app: XCUIApplication, _ uuid: String) {
        guard let card = sameCard(app, uuid, timeout: 30) else {
            return XCTFail("the card \(uuid) is available to open")
        }
        let window = app.windows.firstMatch.frame
        let control = card.buttons["card.open"].firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 10), "the card states its opening control")
        for _ in 0..<4 {
            let frame = control.frame
            let center = CGPoint(x: frame.midX, y: frame.midY)
            if frame.width > 1, frame.height > 1, window.contains(center) { break }
            if frame.midY < window.midY { app.swipeDown() } else { app.swipeUp() }
            Thread.sleep(forTimeInterval: 0.4)
        }
        let frame = control.frame
        let center = CGPoint(x: frame.midX, y: frame.midY)
        XCTAssertTrue(frame.width > 1 && frame.height > 1 && window.contains(center),
            "the opening control is inside the visible window before the tap")
        control.tap()
    }

    /// The site is the platform's `SFSafariViewController`: its chrome, not a fixture page.
    private func siteClose(_ app: XCUIApplication, timeout: TimeInterval = 40) -> XCUIElement? {
        let safari = XCUIApplication(bundleIdentifier: "com.apple.SafariViewService")
        let labels = ["Close", "Fechar", "Done", "Concluído"]
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for label in labels {
                if safari.buttons[label].exists { return safari.buttons[label] }
                let site = app.buttons.matching(NSPredicate(
                    format: "label == %@ AND identifier != %@", label, "reading.close")).firstMatch
                if site.exists { return site }
            }
            Thread.sleep(forTimeInterval: 0.4)
        } while Date() < deadline
        return nil
    }

    /// Exactly one tap at the close control's frame centre: remote Safari elements report an activation point
    /// that is not where the X is drawn, and a second attempt could land on the app already uncovered.
    private func tapSiteClose(_ app: XCUIApplication, _ close: XCUIElement) {
        let frame = close.frame
        XCTAssertGreaterThan(frame.width, 0, "Safari's close control has a frame")
        XCTAssertGreaterThan(frame.height, 0, "Safari's close control has a frame")
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
    }

    private func waitForNoAddress(_ app: XCUIApplication, timeout: TimeInterval = 30) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !app.buttons["URL"].exists { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return !app.buttons["URL"].exists
    }

    private func anchorDelta(_ app: XCUIApplication, uuid: String, from frame: CGRect,
        timeout: TimeInterval = 60) -> CGRect? {
        let card = cardWithUUID(app, uuid)
        guard card.waitForExistence(timeout: timeout) else { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if card.exists && card.frame.height > 1 {
                // A modal dismissal animates; the stable frame, not the first frame after the tap, is the anchor.
                Thread.sleep(forTimeInterval: 0.8)
                return cardWithUUID(app, uuid).frame
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return nil
    }

    /// The card's frame once the feed has settled. The pre-transition copy is taken here, after the same live
    /// re-query the tap uses, so a transient bounce is not recorded as the reading point.
    private func settledFrame(_ app: XCUIApplication, _ uuid: String,
        timeout: TimeInterval = 30) -> CGRect? {
        guard sameCard(app, uuid, timeout: timeout) != nil else { return nil }
        Thread.sleep(forTimeInterval: 0.8)
        return cardWithUUID(app, uuid).frame
    }

    // MARK: - Journeys

    /// Short teaser → the site. A single tap, the platform's close, and the exact same card line back in the feed.
    func test01ShortTeaserOpensSiteAndClosesToTheSameCard() throws {
        let app = try launch()
        guard ensureSource(app, containing: ["euronews"], feed: Self.euronewsFeed) != nil else {
            return XCTFail("the public Euronews feed publishes a card")
        }
        guard let card = pickCard(app, containing: ["euronews"], feed: Self.euronewsFeed,
            label: "short") else {
            return XCTFail("the seeded pick selects an available Euronews card")
        }
        let uuid = card.identifier
        guard let before = settledFrame(app, uuid) else {
            return XCTFail("the card settles at a measurable reading point")
        }
        let title = card.staticTexts["card.title"].firstMatch.label
        record("short-seed", "seed=\(Self.seed) feed=\(Self.euronewsFeed) card=\(uuid) frame=\(before) "
            + "title=\(title)")
        shot("short-feed")

        open(app, uuid)
        guard let close = siteClose(app) else {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "short-site-tree"
            tree.lifetime = .keepAlways
            add(tree)
            return XCTFail("the teaser opens the site with Safari's own chrome")
        }
        record("short-site", "url=\(app.buttons["URL"].firstMatch.value ?? "-") close=\(close.label)")
        shot("short-site")
        XCTAssertTrue(app.buttons["URL"].exists || app.webViews.firstMatch.exists,
            "the site page is really presented")

        tapSiteClose(app, close)
        XCTAssertTrue(waitForNoAddress(app), "Safari's chrome is gone, not merely covered")
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 30))
        guard let after = anchorDelta(app, uuid: uuid, from: before) else {
            return XCTFail("the feed returns with the same card \(uuid)")
        }
        // The contracted continuity is the same occurrence, the same line (y) and height within 1 pt. The horizontal
        // frame is recorded as an observation (it includes SwiftUI's transient edge artifact at the top of the feed),
        // not asserted as a user-visible jump.
        record("short-return", "card=\(uuid) before=\(before) after=\(after) "
            + "dx=\(after.minX - before.minX) dy=\(after.minY - before.minY) dh=\(after.height - before.height)")
        XCTAssertEqual(after.minY, before.minY, accuracy: 1,
            "the card line is preserved after the site closes")
        XCTAssertEqual(after.height, before.height, accuracy: 1,
            "the card height is preserved after the site closes")
        shot("short-return")
    }

    /// Long/rich body → the local reading surface. Its close and its explicit site request both return to the
    /// same card line; the body is the source's own text, longer than a teaser.
    func test02LongBodyOpensLocallyAndBothExitsReturnToTheSameCard() throws {
        let app = try launch()
        guard ensureSource(app, containing: ["egypt independent", "egyptindependent"], feed: Self.egyptFeed) != nil else {
            return XCTFail("the public Egypt Independent feed publishes a card")
        }
        guard let card = pickCard(app, containing: ["egypt independent", "egyptindependent"],
            feed: Self.egyptFeed, label: "long") else {
            return XCTFail("the seeded pick selects an available Egypt Independent card")
        }
        let uuid = card.identifier
        guard let before = settledFrame(app, uuid) else {
            return XCTFail("the card settles at a measurable reading point")
        }
        record("long-seed", "seed=\(Self.seed) feed=\(Self.egyptFeed) card=\(uuid) frame=\(before)")
        shot("long-feed")

        open(app, uuid)
        let body = byIdentifier(app, "reading.body")
        XCTAssertTrue(body.waitForExistence(timeout: 90), "the stored body opens on the local surface")
        let bodyLength = body.label.count
        XCTAssertGreaterThan(bodyLength, 1_000, "the card publishes a substantial body, not a teaser")
        record("long-local", "card=\(uuid) origin=\(byIdentifier(app, "reading.origin").label) "
            + "body_chars=\(bodyLength) headline=\(byIdentifier(app, "reading.headline").label)")
        shot("long-local")
        XCTAssertTrue(byIdentifier(app, "reading.open-site").exists, "the local surface offers the site")
        record("reading-controls", "close=\(byIdentifier(app, "reading.close").frame) "
            + "open_site=\(byIdentifier(app, "reading.open-site").frame) "
            + "open_site_footer=\(byIdentifier(app, "reading.open-site-footer").frame)")

        // Scrolling inside the article changes what is visible and does not change the card identity.
        let readerFrame = app.windows.firstMatch.frame
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
        from.press(forDuration: 0.05, thenDragTo: to)
        XCTAssertTrue(body.exists, "the article is still on the reader after its own scroll")
        shot("long-local-scrolled")
        byIdentifier(app, "reading.close").tap()
        XCTAssertTrue(SurfaceTest.waitForAbsence(body, timeout: 30), "close returns to the feed")
        guard let afterClose = anchorDelta(app, uuid: uuid, from: before) else {
            return XCTFail("the feed returns with the same card after the local reader closes")
        }
        record("long-close-return", "card=\(uuid) before=\(before) after=\(afterClose) "
            + "dx=\(afterClose.minX - before.minX) dy=\(afterClose.minY - before.minY) dh=\(afterClose.height - before.height)")
        XCTAssertEqual(afterClose.minY, before.minY, accuracy: 1, "the card line survives local close")
        XCTAssertEqual(afterClose.height, before.height, accuracy: 1, "the card height survives local close")
        shot("long-close-return")

        // Open the site explicitly from the local page: the site replaces the text page, and its own close ends
        // the reader at the surface that opened it — the feed, per the approved native contract.
        guard sameCard(app, uuid, timeout: 30) != nil else {
            return XCTFail("the same card \(uuid) is still in the feed")
        }
        open(app, uuid)
        XCTAssertTrue(body.waitForExistence(timeout: 60))
        byIdentifier(app, "reading.open-site").tap()
        guard let siteCloseControl = siteClose(app) else {
            return XCTFail("open-source presents the site with Safari's own chrome")
        }
        shot("long-site")
        tapSiteClose(app, siteCloseControl)
        XCTAssertTrue(waitForNoAddress(app), "Safari's chrome is gone")
        XCTAssertTrue(SurfaceTest.waitForAbsence(body, timeout: 20),
            "the site's close ends the reader instead of returning to the hidden text page")
        guard let afterSite = anchorDelta(app, uuid: uuid, from: before) else {
            return XCTFail("the feed returns with the same card after the site closes")
        }
        record("long-site-return", "card=\(uuid) before=\(before) after=\(afterSite) "
            + "dx=\(afterSite.minX - before.minX) dy=\(afterSite.minY - before.minY) dh=\(afterSite.height - before.height)")
        XCTAssertEqual(afterSite.minY, before.minY, accuracy: 1, "the card line survives the site close")
        XCTAssertEqual(afterSite.height, before.height, accuracy: 1, "the card height survives the site close")
        shot("long-site-return")
    }

    /// Save from the card, find it in the product's own saved list, open it, close it, and read the same saved row
    /// back after a process relaunch.
    func test03SavedCardIsFoundReadBackAndReopensAfterRelaunch() throws {
        let app = try launch()
        guard ensureSource(app, containing: ["egypt independent", "egyptindependent"], feed: Self.egyptFeed) != nil else {
            return XCTFail("the public Egypt Independent feed publishes a card")
        }
        guard let card = pickCard(app, containing: ["egypt independent", "egyptindependent"],
            feed: Self.egyptFeed, label: "saved") else {
            return XCTFail("the seeded pick selects an available Egypt Independent card")
        }
        let uuid = card.identifier
        let title = card.staticTexts["card.title"].firstMatch.label
        let bookmark = card.buttons["card.bookmark"].firstMatch
        XCTAssertTrue(bookmark.exists, "the card states its own save control")
        if bookmark.value as? String == "bookmarked" {
            bookmark.tap()
            XCTAssertTrue(SurfaceTest.waitForValue(bookmark, differentFrom: "bookmarked", timeout: 20),
                "the existing bookmark is removed before the save step")
        }
        XCTAssertEqual(bookmark.value as? String, "not bookmarked",
            "the save step starts from an unbookmarked card")
        let before = bookmark.value as? String
        bookmark.tap()
        XCTAssertTrue(SurfaceTest.waitForValue(bookmark, differentFrom: before, timeout: 20),
            "one tap saves the card")
        let savedValue = bookmark.value as? String
        XCTAssertEqual(savedValue, "bookmarked")
        record("save-seed", "seed=\(Self.seed) card=\(uuid) title=\(title) value=\(savedValue ?? "-")")
        shot("saved-card")

        // The product's own saved surface: menu → Salvos → Todos os salvos.
        SurfaceTest.menuEntry(app, "Salvos")
        XCTAssertTrue(app.navigationBars["Caixas de salvos"].waitForExistence(timeout: 30))
        let all = app.buttons["Todos os salvos"].firstMatch
        XCTAssertTrue(all.waitForExistence(timeout: 20), "the boxes offer the all-saved list")
        all.tap()
        XCTAssertTrue(app.navigationBars["Salvos"].waitForExistence(timeout: 30))
        let row = byIdentifier(app, "saved-article-\(uuid)")
        XCTAssertTrue(row.waitForExistence(timeout: 30), "the saved card is listed by the same identity")
        record("saved-list", "row=saved-article-\(uuid) label=\(row.label)")
        shot("saved-list")

        row.tap()
        let body = byIdentifier(app, "reading.body")
        XCTAssertTrue(body.waitForExistence(timeout: 90), "the saved article opens")
        shot("saved-open")
        byIdentifier(app, "reading.close").tap()
        XCTAssertTrue(SurfaceTest.waitForAbsence(body, timeout: 30))
        XCTAssertTrue(byIdentifier(app, "saved-article-\(uuid)").waitForExistence(timeout: 20),
            "closing the saved article returns to the same saved row")

        // Read-back across a process relaunch, not only across a sheet.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["more-menu"].waitForExistence(timeout: 180))
        SurfaceTest.menuEntry(app, "Salvos")
        XCTAssertTrue(app.navigationBars["Caixas de salvos"].waitForExistence(timeout: 30))
        app.buttons["Todos os salvos"].tap()
        XCTAssertTrue(app.navigationBars["Salvos"].waitForExistence(timeout: 30))
        let reopened = byIdentifier(app, "saved-article-\(uuid)")
        XCTAssertTrue(reopened.waitForExistence(timeout: 40),
            "the saved card is read back after the app process restarts")
        record("saved-relaunch", "row=saved-article-\(uuid) present=true")
        shot("saved-relaunch")

        // The read-back is the content, not only the row's presence: open the restored row and read its body.
        reopened.tap()
        let relaunchBody = byIdentifier(app, "reading.body")
        XCTAssertTrue(relaunchBody.waitForExistence(timeout: 90),
            "the saved occurrence reopens from the relaunched library")
        let relaunchCharacters = relaunchBody.label.count
        XCTAssertGreaterThan(relaunchCharacters, 1_000,
            "the reopened saved occurrence carries its substantial body")
        record("saved-relaunch-body", "row=saved-article-\(uuid) body_chars=\(relaunchCharacters)")
        shot("saved-relaunch-body")
        byIdentifier(app, "reading.close").tap()
        XCTAssertTrue(SurfaceTest.waitForAbsence(relaunchBody, timeout: 30))

        // Leave the library as it was found: read the current bookmark value from the feed, then remove it.
        app.navigationBars["Salvos"].buttons.firstMatch.tap()
        if app.buttons["bookmarkBoxes.done"].exists { app.buttons["bookmarkBoxes.done"].tap() }
        if let feedCard = sameCard(app, uuid, timeout: 90) {
            let remove = feedCard.buttons["card.bookmark"].firstMatch
            if remove.exists {
                XCTAssertEqual(remove.value as? String, "bookmarked",
                    "the saved occurrence is still bookmarked after the relaunch")
                remove.tap()
                _ = SurfaceTest.waitForValue(remove, differentFrom: "bookmarked", timeout: 20)
            }
        } else {
            record("saved-cleanup", "bookmark left in place: card/control not reachable from this scroll")
        }
    }

    /// The existing appearance controls measured on the local reading surface, plus the system's own Dynamic Type
    /// at regular and accessibility XXXL. Palette/night changes are asserted by rendered pixels; the app's own
    /// text-size setting is measured (it is the card scale in the approved vocabulary) instead of being presumed.
    func test04AppearanceControlsRenderOnTheLocalSurface() throws {
        let app = try launch()
        // The baseline this experiment measures is the product's own medium text size and its day period. Both are
        // set explicitly so a previous interrupted run cannot make "regular" mean a different scale or period.
        _ = setTypeScale(app, "Médio")
        setNightMode(app, on: false)
        guard ensureSource(app, containing: ["egypt independent", "egyptindependent"], feed: Self.egyptFeed) != nil else {
            return XCTFail("the public Egypt Independent feed publishes a card")
        }
        guard let card = pickCard(app, containing: ["egypt independent", "egyptindependent"],
            feed: Self.egyptFeed, label: "appearance") else {
            return XCTFail("the seeded pick selects an available Egypt Independent card")
        }
        let uuid = card.identifier
        guard let mediumFrame = settledFrame(app, uuid) else {
            return XCTFail("the medium card settles at a measurable frame")
        }
        open(app, uuid)
        let body = byIdentifier(app, "reading.body")
        XCTAssertTrue(body.waitForExistence(timeout: 90))
        let regularBodyHeight = body.frame.height
        let originFrame = byIdentifier(app, "reading.origin").frame
        XCTAssertGreaterThan(originFrame.width, 10, "the accent-bearing origin label has a measurable frame")
        let regularShot = XCUIScreen.main.screenshot()
        let regularPixel = averageRGB(regularShot.image, nx: 0.94, ny: 0.55)
        record("appearance-regular", "card=\(uuid) frame=\(mediumFrame) body_h=\(regularBodyHeight) "
            + "bg=\(format(regularPixel))")
        shot("appearance-regular")
        byIdentifier(app, "reading.close").tap()
        XCTAssertTrue(SurfaceTest.waitForAbsence(body, timeout: 30))

        // 1. The product's text-size setting (Medium → Grande). One tap on each control.
        _ = setTypeScale(app, "Grande")
        guard let cardLarge = sameCard(app, uuid) else {
            return XCTFail("the same card \(uuid) remains in the feed after changing text size")
        }
        XCTAssertEqual(cardLarge.identifier, uuid, "the large variant reopens the same occurrence")
        let largeFrame = cardLarge.frame
        XCTAssertGreaterThan(largeFrame.height, mediumFrame.height + 1,
            "the product's Grande text size grows the card (medium \(mediumFrame.height) -> \(largeFrame.height))")
        open(app, uuid)
        XCTAssertTrue(body.waitForExistence(timeout: 60))
        let largeBodyHeight = body.frame.height
        let largeShot = XCUIScreen.main.screenshot()
        let largePixel = averageRGB(largeShot.image, nx: 0.94, ny: 0.55)
        record("appearance-type-large", "setting=Grande body_h=\(largeBodyHeight) "
            + "regular_body_h=\(regularBodyHeight) delta=\(largeBodyHeight - regularBodyHeight) "
            + "card_medium=\(mediumFrame.height) card_large=\(largeFrame.height) "
            + "card_delta=\(largeFrame.height - mediumFrame.height) bg=\(format(largePixel))")
        shot("appearance-type-large")
        // Continuity *within* the stable large variant: close and return to the same card line.
        byIdentifier(app, "reading.close").tap()
        XCTAssertTrue(SurfaceTest.waitForAbsence(body, timeout: 30))
        guard let largeReturn = anchorDelta(app, uuid: uuid, from: largeFrame) else {
            return XCTFail("the same card returns after closing at the large setting")
        }
        record("appearance-large-return", "card=\(uuid) before=\(largeFrame) after=\(largeReturn) "
            + "dy=\(largeReturn.minY - largeFrame.minY) dh=\(largeReturn.height - largeFrame.height)")
        XCTAssertEqual(largeReturn.minY, largeFrame.minY, accuracy: 1,
            "within the large variant the same card line is preserved")
        XCTAssertEqual(largeReturn.height, largeFrame.height, accuracy: 1)

        // 2. An existing palette option: palette family, then night mode. The page tint under the text is what the
        // reader sees; its sampled pixel must move when the palette really changes.
        _ = setTypeScale(app, "Médio", required: false)
        let originalPalette = setPalette(app, "Monocromático")
        guard let cardPalette = sameCard(app, uuid) else {
            return XCTFail("the same card \(uuid) remains in the feed after changing the palette")
        }
        XCTAssertEqual(cardPalette.identifier, uuid, "the palette variant reopens the same occurrence")
        open(app, uuid)
        XCTAssertTrue(body.waitForExistence(timeout: 60))
        let paletteShot = XCUIScreen.main.screenshot()
        let palettePixel = averageRGB(paletteShot.image, nx: 0.94, ny: 0.55)
        let windowFrame = app.windows.firstMatch.frame
        let surfaceRect = CGRect(x: 0, y: 100, width: windowFrame.width,
            height: max(1, windowFrame.height - 160))
        let accentDifference = differingPixels(regularShot.image, paletteShot.image,
            rect: surfaceRect, window: windowFrame)
        let regularHash = SHA256.hash(data: regularShot.pngRepresentation).map { String(format: "%02x", $0) }.joined()
        let paletteHash = SHA256.hash(data: paletteShot.pngRepresentation).map { String(format: "%02x", $0) }.joined()
        record("appearance-palette", "family=Monocromático regular_sha=\(regularHash) "
            + "palette_sha=\(paletteHash) bg=\(format(palettePixel)) "
            + "regular_bg=\(format(regularPixel)) origin_frame=\(originFrame) "
            + "accent_pixels_changed=\(accentDifference)")
        XCTAssertGreaterThan(accentDifference, 20,
            "the palette family changes the accent actually drawn on the reading surface")
        shot("appearance-palette")
        byIdentifier(app, "reading.close").tap()
        XCTAssertTrue(SurfaceTest.waitForAbsence(body, timeout: 30))

        // Night mode can only be observed against a day period. The clock drives the period while adaptive
        // palette is on, so pin the day period, measure it, then turn night mode on and measure the same card.
        setNightMode(app, on: false)
        setFollowsClock(app, on: false)
        guard sameCard(app, uuid) != nil else {
            return XCTFail("the same card \(uuid) remains in the feed for the day baseline")
        }
        open(app, uuid)
        XCTAssertTrue(body.waitForExistence(timeout: 60))
        let dayShot = XCUIScreen.main.screenshot()
        let dayPixel = averageRGB(dayShot.image, nx: 0.94, ny: 0.55)
        byIdentifier(app, "reading.close").tap()
        XCTAssertTrue(SurfaceTest.waitForAbsence(body, timeout: 30))

        setNightMode(app, on: true)
        guard let cardNight = sameCard(app, uuid) else {
            return XCTFail("the same card \(uuid) remains in the feed after night mode")
        }
        XCTAssertEqual(cardNight.identifier, uuid, "the night variant reopens the same occurrence")
        open(app, uuid)
        XCTAssertTrue(body.waitForExistence(timeout: 60))
        let nightShot = XCUIScreen.main.screenshot()
        let nightPixel = averageRGB(nightShot.image, nx: 0.94, ny: 0.55)
        let nightBodyHeight = body.frame.height
        record("appearance-night", "day_bg=\(format(dayPixel)) night_bg=\(format(nightPixel)) "
            + "body_h=\(nightBodyHeight) pixel_delta=\(pixelDistance(dayPixel, nightPixel))")
        shot("appearance-night")
        XCTAssertGreaterThan(pixelDistance(dayPixel, nightPixel), 2,
            "night mode changes the page the reading surface really draws")
        byIdentifier(app, "reading.close").tap()
        XCTAssertTrue(SurfaceTest.waitForAbsence(body, timeout: 30))

        // Restore the owned preferences.
        setNightMode(app, on: false)
        setFollowsClock(app, on: true)
        _ = setPalette(app, originalPalette, required: false)
        _ = setTypeScale(app, "Médio", required: false)
        record("appearance-restored", "type=Médio palette=\(originalPalette) night=off")

        // 3. The system's own Dynamic Type at accessibility XXXL, same public article and same card identity.
        app.terminate()
        let large = try launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        guard let largeCard = sameCard(large, uuid, timeout: 180) else {
            return XCTFail("the same card \(uuid) is restored under accessibility text")
        }
        XCTAssertEqual(largeCard.identifier, uuid, "the accessibility variant reopens the same occurrence")
        let largeCardFrame = largeCard.frame
        open(large, uuid)
        let largeSystemBody = byIdentifier(large, "reading.body")
        XCTAssertTrue(largeSystemBody.waitForExistence(timeout: 90))
        let systemHeight = largeSystemBody.frame.height
        record("appearance-dynamic-type", "category=AccessibilityXXXL body_h=\(systemHeight) "
            + "regular_body_h=\(regularBodyHeight) ratio=\(systemHeight / max(regularBodyHeight, 1))")
        shot("appearance-accessibility-xxxl")
        XCTAssertGreaterThan(systemHeight, regularBodyHeight,
            "the local surface honours the system Dynamic Type category")
        byIdentifier(large, "reading.close").tap()
        XCTAssertTrue(SurfaceTest.waitForAbsence(largeSystemBody, timeout: 30))
        guard let largeSystemReturn = anchorDelta(large, uuid: uuid, from: largeCardFrame) else {
            return XCTFail("the card returns under accessibility text")
        }
        record("appearance-dynamic-return", "card=\(uuid) before=\(largeCardFrame) "
            + "after=\(largeSystemReturn) dy=\(largeSystemReturn.minY - largeCardFrame.minY)")
        XCTAssertEqual(largeSystemReturn.minY, largeCardFrame.minY, accuracy: 1,
            "within the accessibility variant the same card line is preserved")
    }

    /// A real episode from the public Adrift feed: the product's clock really advances, freezes while paused and
    /// advances again on resume, and every surface names the same occurrence.
    func test05RealAudioEpisodePlaysPausesAndResumes() throws {
        let app = try launch()
        guard ensureSource(app, containing: ["adrift", "art19"], feed: Self.adriftFeed) != nil else {
            return XCTFail("the public Adrift feed publishes a card")
        }
        guard let card = pickCard(app, containing: ["adrift", "art19"], requirePlay: true,
            feed: Self.adriftFeed, label: "audio") else {
            if lastSampleHadCandidates {
                return XCTFail("a playable Adrift candidate existed but the seeded pick could not be reacquired; "
                    + "see audio-sample-missing")
            }
            throw XCTSkip("the Adrift feed presents no playable card in this run; no playback is claimed")
        }
        let play = card.buttons["card.play"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 20), "the seeded card presents its play control")
        let cardTitle = card.staticTexts["card.title"].label
        record("audio-seed", "seed=\(Self.seed) feed=\(Self.adriftFeed) card=\(card.identifier) "
            + "title=\(cardTitle)")
        shot("audio-card")

        // The seeded card may sit at the window edge. The reader's own bounded scroll brings its play control into
        // the window before the single tap; the control is re-queried after each scroll.
        let windowFrame = app.windows.firstMatch.frame
        for _ in 0..<4 {
            if centerInsideWindow(play, app) { break }
            let frame = play.frame
            let scroll = app.scrollViews.firstMatch
            if frame.midY > windowFrame.midY { scroll.swipeUp() } else { scroll.swipeDown() }
            Thread.sleep(forTimeInterval: 0.4)
        }
        XCTAssertTrue(centerInsideWindow(play, app),
            "the play control is inside the window after the reader scroll")
        play.tap()
        let bar = app.otherElements["mini-player"]
        XCTAssertTrue(bar.waitForExistence(timeout: 60), "play reaches the player instead of looking dead")
        let title = app.staticTexts["mini-player-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        if !cardTitle.isEmpty { XCTAssertEqual(title.label, cardTitle) }
        let toggle = app.buttons["mini-player-toggle"]
        let error = app.staticTexts["mini-player-error"]
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline, toggle.label != "Pausar", !error.exists {
            Thread.sleep(forTimeInterval: 0.2)
        }
        if error.exists {
            record("audio-refused", "title=\(title.label) reason=\(error.label)")
            shot("audio-refused")
            // A product refusal is an observable failure of this journey, never a silent pass.
            return XCTFail("the product could not play the episode: \(error.label)")
        }
        XCTAssertEqual(toggle.label, "Pausar")

        title.tap()
        let full = app.otherElements["full-player"]
        XCTAssertTrue(full.waitForExistence(timeout: 20))
        let fullTitle = app.staticTexts["full-player-title"]
        XCTAssertTrue(fullTitle.waitForExistence(timeout: 20))
        if !cardTitle.isEmpty { XCTAssertEqual(fullTitle.label, cardTitle) }
        let clock = app.staticTexts["full-player-position"]
        XCTAssertTrue(clock.waitForExistence(timeout: 30))
        guard let first = clockSeconds(clock.label),
            let second = waitForAdvance(clock, from: first, timeout: 15) else {
            return XCTFail("the clock advances while playing; label alone is not playback")
        }
        shot("audio-playing")
        app.buttons["full-player-toggle"].tap()
        Thread.sleep(forTimeInterval: 2)
        guard let paused = clockSeconds(clock.label) else { return XCTFail("clock states m:ss") }
        Thread.sleep(forTimeInterval: 3)
        guard let pausedAgain = clockSeconds(clock.label) else { return XCTFail("clock states m:ss") }
        XCTAssertEqual(pausedAgain, paused, "a paused episode's clock does not advance")
        shot("audio-paused")
        app.buttons["full-player-toggle"].tap()
        guard let resumed = waitForAdvance(clock, from: pausedAgain, timeout: 15) else {
            return XCTFail("the clock advances after resume")
        }
        app.buttons["full-player-close"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        if !cardTitle.isEmpty { XCTAssertEqual(title.label, cardTitle) }
        record("audio-clock", "title=\(title.label) playing=\(first)->\(second) "
            + "paused=\(paused)==\(pausedAgain) resumed=\(resumed)")
        shot("audio-resumed")
    }

    // MARK: - Appearance controls

    /// A menu picker's option can surface as a button, a menu item or a plain text depending on the SwiftUI
    /// presentation; the product's own label is the identity in every case.
    @discardableResult
    private func chooseOption(_ app: XCUIApplication, _ label: String) -> Bool {
        // Diacritic-insensitive: the localized menu item and the Swift source literal can differ in Unicode
        // normalisation ("Médio" composed vs decomposed), which an exact label match does not bridge.
        let predicate = NSPredicate(format: "label ==[cd] %@", label)
        for candidate in [app.buttons.matching(predicate).firstMatch,
            app.menuItems.matching(predicate).firstMatch,
            app.staticTexts.matching(predicate).firstMatch] {
            if candidate.waitForExistence(timeout: 4) {
                candidate.tap()
                return true
            }
        }
        let any = app.descendants(matching: .any).matching(predicate).firstMatch
        if any.waitForExistence(timeout: 3) {
            any.tap()
            return true
        }
        return false
    }

    @discardableResult
    private func setTypeScale(_ app: XCUIApplication, _ label: String, required: Bool = true) -> String {
        SurfaceTest.menuEntry(app, "Ajustes")
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 30))
        let picker = byIdentifier(app, "settings-type-scale")
        XCTAssertTrue(SurfaceTest.scrollIntoView(picker, in: app, timeout: 20))
        let raw = picker.value as? String
        let original = (raw?.isEmpty == false) ? raw! : "Médio"
        picker.tap()
        let selected = chooseOption(app, label)
        if !selected, required {
            XCTFail("the type-size option \(label) is offered and selected")
        }
        if !selected, let current = picker.value as? String {
            record("settings-option-miss", "wanted=\(label) current=\(current)")
            _ = chooseOption(app, typeLabel(current))
        }
        app.buttons["settings-done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 30))
        return typeLabel(original)
    }

    @discardableResult
    private func setPalette(_ app: XCUIApplication, _ label: String, required: Bool = true) -> String {
        SurfaceTest.menuEntry(app, "Ajustes")
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 30))
        let clock = app.switches["settings-circadian-palette"]
        // A disabled palette-family picker is a picker that cannot run the experiment. The switch states its
        // own value; when it is not already on, one tap enables it.
        if (clock.value as? String) != "1" {
            clock.tap()
            let deadline = Date().addingTimeInterval(15)
            while Date() < deadline, (clock.value as? String) != "1" {
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
        let picker = byIdentifier(app, "settings-palette-family")
        XCTAssertTrue(SurfaceTest.scrollIntoView(picker, in: app, timeout: 20))
        let raw = picker.value as? String
        let original = (raw?.isEmpty == false) ? raw! : "Terra quente"
        picker.tap()
        let selected = chooseOption(app, label)
        if !selected, required {
            XCTFail("the palette option \(label) is offered and selected")
        }
        if !selected, let current = picker.value as? String {
            record("palette-option-miss", "wanted=\(label) current=\(current)")
            _ = chooseOption(app, paletteLabel(current))
        }
        record("palette-setting", "wanted=\(label) before=\(original) "
            + "after=\(byIdentifier(app, "settings-palette-family").value ?? "-")")
        app.buttons["settings-done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 30))
        return paletteLabel(original)
    }

    private func typeLabel(_ value: String) -> String {
        switch value.lowercased() {
        case "small", "pequeno": "Pequeno"
        case "medium", "médio", "medio": "Médio"
        case "large", "grande": "Grande"
        default: value
        }
    }

    private func paletteLabel(_ value: String) -> String {
        switch value.lowercased() {
        case "warmearth", "terra quente": "Terra quente"
        case "coolsky", "céu frio": "Céu frio"
        case "botanical", "botânico": "Botânico"
        case "lavenderhour", "hora lavanda": "Hora lavanda"
        case "monochrome", "monocromático": "Monocromático"
        default: value
        }
    }

    private func setFollowsClock(_ app: XCUIApplication, on: Bool) {
        SurfaceTest.menuEntry(app, "Ajustes")
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 30))
        let clock = app.switches["settings-circadian-palette"]
        // The switch may sit below the visible sheet: a bounded scroll makes it hittable, but its stored value is
        // readable even when the row is still settling. The effect assertion below is about the period, not the row.
        _ = SurfaceTest.scrollIntoView(clock, in: app, timeout: 20)
        XCTAssertTrue(clock.exists, "the adaptive-palette switch exists")
        let expected = on ? "1" : "0"
        if (clock.value as? String) != expected {
            let control = clock.switches.firstMatch
            (control.exists ? control : clock).tap()
            let deadline = Date().addingTimeInterval(20)
            while Date() < deadline, (clock.value as? String) != expected {
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
        record("clock-setting", "followsClock=\(on) value=\(clock.value ?? "-")")
        app.buttons["settings-done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 30))
    }

    private func setNightMode(_ app: XCUIApplication, on: Bool) {
        SurfaceTest.menuEntry(app, "Ajustes")
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 30))
        let night = app.switches["settings-night-mode"]
        XCTAssertTrue(SurfaceTest.scrollIntoView(night, in: app, timeout: 20))
        let isOn = (night.value as? String) == "1"
        if isOn != on {
            let control = night.switches.firstMatch
            (control.exists ? control : night).tap()
            let expected = on ? "1" : "0"
            let deadline = Date().addingTimeInterval(20)
            while Date() < deadline, (night.value as? String) != expected {
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
        record("night-setting", "wanted=\(on) value=\(night.value ?? "-")")
        app.buttons["settings-done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 30))
    }

    // MARK: - Pixels and clock

    /// Average sRGB over a small patch, normalised to the screenshot. The screenshot is the rendering the reader
    /// saw; the sample point is a margin the reading surface paints with its page colour.
    private func averageRGB(_ image: UIImage, nx: CGFloat, ny: CGFloat) -> (Double, Double, Double)? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width, height = cg.height
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &bytes, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let cx = min(max(Int(nx * CGFloat(width)), 2), width - 3)
        let cy = min(max(Int(ny * CGFloat(height)), 2), height - 3)
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        for dy in -2...2 {
            for dx in -2...2 {
                // CGContext draws with the origin at the bottom-left; the sample is stated from the top.
                let y = height - 1 - (cy + dy)
                let x = cx + dx
                let index = (y * width + x) * 4
                r += Double(bytes[index])
                g += Double(bytes[index + 1])
                b += Double(bytes[index + 2])
                n += 1
            }
        }
        return (r / n, g / n, b / n)
    }

    private func pixelDistance(_ a: (Double, Double, Double)?, _ b: (Double, Double, Double)?) -> Double {
        guard let a, let b else { return 0 }
        return abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2)
    }

    /// Counts pixels that differ beyond `threshold` in the given window-space rect. Both screenshots come from the
    /// same device and size; the rect is mapped to image pixels. Used for the accent-bearing label, not the page
    /// tint (which belongs to the period).
    private func differingPixels(_ a: UIImage, _ b: UIImage, rect: CGRect, window: CGRect,
        threshold: Int = 12) -> Int {
        guard let cgA = a.cgImage, let cgB = b.cgImage,
            let dataA = cgA.dataProvider?.data as Data?, let dataB = cgB.dataProvider?.data as Data?,
            window.width > 0, window.height > 0 else { return 0 }
        let width = cgA.width, height = cgA.height
        guard cgB.width == width, cgB.height == height,
            cgA.bitsPerPixel == cgB.bitsPerPixel, cgA.bytesPerRow == cgB.bytesPerRow else { return 0 }
        let bpp = max(1, cgA.bitsPerPixel / 8)
        let row = cgA.bytesPerRow
        let sx = CGFloat(width) / window.width
        let sy = CGFloat(height) / window.height
        let x0 = max(0, Int(rect.minX * sx)), x1 = min(width - 1, Int(rect.maxX * sx))
        let y0 = max(0, Int(rect.minY * sy)), y1 = min(height - 1, Int(rect.maxY * sy))
        guard x0 < x1, y0 < y1 else { return 0 }
        var changed = 0
        dataA.withUnsafeBytes { (bytesA: UnsafeRawBufferPointer) in
            dataB.withUnsafeBytes { (bytesB: UnsafeRawBufferPointer) in
                for y in y0...y1 {
                    let rowOffset = y * row
                    for x in x0...x1 {
                        let index = rowOffset + x * bpp
                        guard index + 2 < bytesA.count, index + 2 < bytesB.count else { continue }
                        var delta = 0
                        for channel in 0..<3 {
                            delta = max(delta, abs(Int(bytesA[index + channel]) - Int(bytesB[index + channel])))
                        }
                        if delta > threshold { changed += 1 }
                    }
                }
            }
        }
        return changed
    }

    private func format(_ value: (Double, Double, Double)?) -> String {
        guard let value else { return "unavailable" }
        return String(format: "%.1f/%.1f/%.1f", value.0, value.1, value.2)
    }

    private func clockSeconds(_ text: String) -> Int? {
        let parts = text.split(separator: ":").map(String.init)
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        var seconds = 0
        for part in parts {
            guard let value = Int(part) else { return nil }
            seconds = seconds * 60 + value
        }
        return seconds
    }

    private func waitForAdvance(_ clock: XCUIElement, from: Int, timeout: TimeInterval) -> Int? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let value = clockSeconds(clock.label), value > from { return value }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return nil
    }
}
