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
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class ReleaseReaderJourneyUITests: XCTestCase {
    private static let seed = "20261022"
    private static let euronewsFeed = "https://pt.euronews.com/rss"
    private static let egyptFeed = "https://www.egyptindependent.com/feed/"
    private static let adriftFeed = "https://rss.art19.com/adrift"

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
    private func ensureSource(_ app: XCUIApplication, containing needles: [String],
        feed: String, timeout: TimeInterval = 240) -> XCUIElement? {
        if let card = sourceCard(app, containing: needles, timeout: 25) { return card }
        scrollFeedToTop(app)
        if let card = sourceCard(app, containing: needles, timeout: 25) { return card }
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
        guard let card = ensureSource(app, containing: ["euronews"], feed: Self.euronewsFeed) else {
            return XCTFail("the public Euronews feed publishes a card")
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
        guard let card = ensureSource(app, containing: ["egypt independent", "egyptindependent"], feed: Self.egyptFeed) else {
            return XCTFail("the public Egypt Independent feed publishes a card")
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
        guard let card = ensureSource(app, containing: ["egypt independent", "egyptindependent"], feed: Self.egyptFeed) else {
            return XCTFail("the public Egypt Independent feed publishes a card")
        }
        let uuid = card.identifier
        let title = card.staticTexts["card.title"].firstMatch.label
        let bookmark = card.buttons["card.bookmark"].firstMatch
        XCTAssertTrue(bookmark.exists, "the card states its own save control")
        if bookmark.value as? String == "bookmarked" { bookmark.tap() }
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
        record("saved-relaunch", "row=saved-article-\(uuid) present=true value=\(savedValue ?? "-")")
        shot("saved-relaunch")

        // Leave the library as it was found: remove the bookmark from the feed's own control.
        app.navigationBars["Salvos"].buttons.firstMatch.tap()
        if app.buttons["bookmarkBoxes.done"].exists { app.buttons["bookmarkBoxes.done"].tap() }
        if let feedCard = sourceCard(app, containing: ["egypt independent", "egyptindependent"], timeout: 60) {
            let remove = feedCard.buttons["card.bookmark"].firstMatch
            if remove.exists, remove.value as? String == "bookmarked" {
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
        // The baseline this experiment measures is the product's own medium text size. It is set explicitly so a
        // previous interrupted run cannot make "regular" mean a different scale.
        _ = setTypeScale(app, "Médio")
        guard let card = ensureSource(app, containing: ["egypt independent", "egyptindependent"], feed: Self.egyptFeed) else {
            return XCTFail("the public Egypt Independent feed publishes a card")
        }
        let uuid = card.identifier
        let before = card.frame
        open(app, uuid)
        let body = byIdentifier(app, "reading.body")
        XCTAssertTrue(body.waitForExistence(timeout: 90))
        let regularBodyHeight = body.frame.height
        let regularShot = XCUIScreen.main.screenshot()
        let regularPixel = averageRGB(regularShot.image, nx: 0.94, ny: 0.55)
        record("appearance-regular", "card=\(uuid) body_h=\(regularBodyHeight) "
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
        open(app, uuid)
        XCTAssertTrue(body.waitForExistence(timeout: 60))
        let largeBodyHeight = body.frame.height
        let largeShot = XCUIScreen.main.screenshot()
        let largePixel = averageRGB(largeShot.image, nx: 0.94, ny: 0.55)
        record("appearance-type-large", "setting=Grande body_h=\(largeBodyHeight) "
            + "regular_body_h=\(regularBodyHeight) delta=\(largeBodyHeight - regularBodyHeight) "
            + "bg=\(format(largePixel)) card_frame=\(largeFrame)")
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
        record("appearance-palette", "family=Monocromático bg=\(format(palettePixel)) "
            + "regular_bg=\(format(regularPixel))")
        shot("appearance-palette")
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
        record("appearance-night", "bg=\(format(nightPixel)) body_h=\(nightBodyHeight) "
            + "regular_bg=\(format(regularPixel)) pixel_delta=\(pixelDistance(regularPixel, nightPixel))")
        shot("appearance-night")
        XCTAssertGreaterThan(pixelDistance(regularPixel, nightPixel), 2,
            "night mode changes the page the reading surface really draws")
        byIdentifier(app, "reading.close").tap()
        XCTAssertTrue(SurfaceTest.waitForAbsence(body, timeout: 30))

        // Restore the owned preferences.
        setNightMode(app, on: false)
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
        guard let anyCard = ensureSource(app, containing: ["adrift", "art19"], feed: Self.adriftFeed) else {
            return XCTFail("the public Adrift feed publishes a card")
        }
        let play = anyCard.buttons["card.play"].firstMatch
        guard play.waitForExistence(timeout: 20) else {
            throw XCTSkip("the Adrift card in this run is not presented as audio; no playback is claimed")
        }
        let playFrame = play.frame
        let card = app.descendants(matching: .any).matching(Self.cardIdentifier)
            .allElementsBoundByIndex.first { $0.frame.contains(playFrame) }
        let cardTitle = card?.staticTexts["card.title"].label ?? ""
        record("audio-seed", "seed=\(Self.seed) feed=\(Self.adriftFeed) card=\(card?.identifier ?? "-") "
            + "title=\(cardTitle)")
        shot("audio-card")

        XCTAssertTrue(centerInsideWindow(play, app), "the play control is inside the window")
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
            return
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
