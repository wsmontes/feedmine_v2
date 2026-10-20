//
// File: EditorialOfferBudgetUITests.swift
// Module: FeedMineAppTests
//
// Responsibility:
// Round 10's offer budget, **measured on the real catalogue on the device**, which is what the acceptance left
// open: the PO accepted instrumentation first and required visual validation before the final acceptance, and the
// architect named the enlarged font and the accessibility tree. This test walks the real first run, reads the
// feed, and states as assertions what the PO asked for in words:
//
//   - the session's first offer asks the full question and the ones after it are compact, and the compact block
//     is measurably smaller than the full one (PO criterion: "as sugestões compactas ocupam menos que os 128 pt");
//   - answering preserves the reader's position, and the block states the answer where it was given;
//   - hiding removes the invitation controls from the accessibility tree — the tree VoiceOver reads — instead of
//     leaving them reachable but invisible (the PO's P0), and it does not move the reader either;
//   - while the invitations are hidden the feed offers none, however far the reader reads;
//   - showing the suggestions again from the existing preferences page restores them (the PO's P1).
//
// The order is deliberate: the first offer is **left unanswered** so the second one — the compact form — is
// reached by the budget alone. Measured on the device (2026-10-11): once the reader answers an offer, the
// discovery pool follows that answer, the subject on offer is the one already offered, and the budget correctly
// refuses to ask again — so the second offer is only reliably observable *before* the first is answered.
//
// It is not the benchmark's driver and it judges nothing: the frozen oracle owns acceptance. This is the visual
// evidence the acceptance asked for, and every measurement it makes is stated in the run's own attachments.
import SQLite3
import XCTest

@MainActor
final class EditorialOfferBudgetUITests: XCTestCase {
    /// A **fresh reader** per run. Measured on the device (2026-10-11): reusing one namespace made the second run
    /// answer nothing at all, because the previous run's answer had filled the discovery pool with the subject that
    /// was already answered — the budget then refuses, correctly, and the test reads as a product failure when it
    /// is a test-state failure. A new namespace is the state the acceptance talks about: a reader meeting the app.
    /// The device keeps each run's container; nothing of the reader's own is touched.
    private func freshNamespace() -> String { UUID().uuidString }

    private func launchForTheOfferBudget(_ namespace: String, firstRun: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = namespace
        // A fresh reader must meet the app: the gate is what gives discovery its profile. The relaunch in the last
        // step is the same reader, and says so.
        app.launchEnvironment["FEEDMINE_ONBOARDING"] = firstRun ? "1" : "0"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = firstRun ? "0" : "1"
        app.launch()
        return app
    }

    /// The first run, answered the way a reader answers it: languages and places, then the feed. The subjects are
    /// answered inside the feed — that is F02's whole point — so nothing here invents a subject answer. It runs
    /// only the first time this namespace is used; afterwards the reader's stored answers are the profile, which is
    /// what makes the test repeatable (and it is the reader's own state, not a fixture the test wrote).
    ///
    /// The answers are the point: an unanswered composer stores an empty profile (languages `[]`, no place), and
    /// the app then correctly draws `feed-empty-state` / "Nenhuma fonte habilitada" — discovery has nowhere to
    /// look, so there is no feed to be offered an invitation on and nothing here can be measured
    /// (measured 2026-10-18: the walk tapped "Abrir meu feed" at t+8 s and read the empty state, run-final3.log
    /// lines 34852-35901).
    private func walkTheFirstRun(_ app: XCUIApplication, namespace: String) throws {
        XCTAssertTrue(app.staticTexts["welcome-headline"].waitForExistence(timeout: 120),
            "the app meets the reader before the feed")
        app.buttons["welcome-shape"].tap()
        XCTAssertTrue(app.staticTexts["composer-subtitle"].waitForExistence(timeout: 60),
            "the first run states what it collects")
        let composer = app.otherElements["onboarding"].scrollViews.firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 30))

        // A language, by identifier: the interface language is the device's, so the answer is named by its code.
        let portuguese = app.buttons["composer-language-pt"]
        guard reveal(portuguese, in: composer) else {
            return XCTFail("the first run offers the language the reader reads in")
        }
        portuguese.tap()
        let languageSelected = portuguese.isSelected
        XCTAssertTrue(languageSelected, "the language the reader chose states itself selected")

        // A place, by the catalogue's own key. The places are drawn in a `LazyVGrid`, so a chip below the fold is
        // **not in the accessibility tree** until the composer scrolls it into view — which is why the earlier
        // instrument took whatever chip happened to be realised (`algeria`, 0 pt sources) as if it were Brazil.
        let brazil = app.buttons["composer-region-\(Self.brazilRegion)"]
        guard reveal(brazil, in: composer) else {
            return XCTFail("the first run's places include Brazil (\(Self.brazilRegion))")
        }
        brazil.tap()
        print("PROFILE_ANSWERED language=pt selected=\(languageSelected) "
            + "place=\(Self.brazilRegion) selected=\(brazil.isSelected)")
        XCTAssertTrue(brazil.isSelected, "the place the reader chose states itself selected")

        let open = app.buttons["composer-open-feed"]
        for _ in 0..<6 where !open.isHittable { composer.swipeUp() }
        XCTAssertTrue(open.isHittable, "the first run's own action opens the feed")
        open.tap()

        // The chain, read from the app's own store **before** a card or an offer is evaluated: the answers are the
        // stored profile, the profile makes sources eligible, and eligibility starts acquisition. Only after this
        // does the test require publication.
        let record = awaitTheRunRecord(namespace)
        print(record?.line ?? "PROFILE_PERSISTED absent")
        XCTAssertEqual(record?.languages ?? [], ["pt"], "the stored profile carries the language the reader chose")
        XCTAssertEqual(record?.preference, "more", "the stored profile carries the place the reader chose")
        XCTAssertGreaterThan(record?.eligibleSources ?? 0, 0,
            "the stored profile makes at least one catalogue source eligible")
        XCTAssertGreaterThan(record?.targets ?? 0, 0, "an eligible set starts acquisition targets")

        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 240),
            "the reader reaches content on the real catalogue")
        XCTAssertFalse(app.otherElements["feed-empty-state"].exists,
            "an answered profile reaches the catalogue instead of the empty state")
    }

    /// The catalogue's own node key for Brazil (`90_countries/brazil`): the identifier's tail, never its label.
    private static let brazilRegion = "90_countries/brazil"
    /// The recipe's own vocabulary for an answer on that place.
    private static let brazilPreference = "topic:90_countries/brazil"

    /// What the app itself recorded for this run, read from the file the app writes: `runtime.sqlite` under the
    /// launch's own runtime namespace (the path `RuntimeDatabaseLocation` names). The three facts are the chain the
    /// acceptance asks to see in order — the **stored** answers, the sources discovery made eligible, and the
    /// acquisition targets it started — so a run that publishes nothing says which link broke instead of reading
    /// as one undifferentiated failure.
    struct RunRecord {
        var languages: [String]
        var preferences: [String: String]
        var targets: Int
        var eligibleSources: Int

        var preference: String { preferences[Self.brazilPreference] ?? "absent" }
        var line: String {
            "PROFILE_PERSISTED languages=\(languages) place=\(Self.brazilPreference)=\(preference) "
                + "acquisition_targets=\(targets) eligible_sources=\(eligibleSources)"
        }
        private static let brazilPreference = "topic:90_countries/brazil"
    }

    /// The app's container in this simulator, found by the namespace the test chose: the UI-test runner lives in
    /// the simulator's own `Containers/Data/Application`, so the app's container is a sibling of its own.
    private func runDatabase(_ namespace: String) -> URL? {
        let runner = URL(fileURLWithPath: NSHomeDirectory())
        let containers = runner.deletingLastPathComponent()
        guard let children = try? FileManager.default.contentsOfDirectory(at: containers,
            includingPropertiesForKeys: nil) else { return nil }
        for container in children {
            let support = container.appendingPathComponent("Library/Application Support/FeedMine", isDirectory: true)
            let url = support.appendingPathComponent(namespace, isDirectory: true)
                .appendingPathComponent("runtime.sqlite")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    /// A private copy of the store: the app owns the original and may be writing while the test reads, and a
    /// read-only open of a WAL store can refuse recovery. Copying the three files is the snapshot; the copy is the
    /// test's own and opens like any store.
    private func copyOfRunDatabase(_ namespace: String) -> URL? {
        guard let source = runDatabase(namespace) else { return nil }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("fm-run-record-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            let from = URL(fileURLWithPath: source.path + suffix)
            guard FileManager.default.fileExists(atPath: from.path) else { continue }
            try? FileManager.default.copyItem(at: from,
                to: folder.appendingPathComponent("runtime.sqlite" + suffix))
        }
        let copy = folder.appendingPathComponent("runtime.sqlite")
        return FileManager.default.fileExists(atPath: copy.path) ? copy : nil
    }

    private func readRunRecord(_ url: URL) -> RunRecord? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
            let database else {
            sqlite3_close(database)
            return nil
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 2_000)

        func scalar(_ sql: String) -> Int {
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                sqlite3_step(statement) == SQLITE_ROW else { return -1 }
            return Int(sqlite3_column_int64(statement, 0))
        }
        func settings() -> [String: Any]? {
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(database,
                "SELECT settings_json FROM reader_preferences WHERE singleton_id = 1", -1, &statement, nil)
                == SQLITE_OK, sqlite3_step(statement) == SQLITE_ROW else { return nil }
            if sqlite3_column_type(statement, 0) == SQLITE_NULL { return nil }
            let bytes = sqlite3_column_blob(statement, 0)
            let count = Int(sqlite3_column_bytes(statement, 0))
            let data = bytes.map { Data(bytes: $0, count: count) }
                ?? String(cString: sqlite3_column_text(statement, 0)).data(using: .utf8)
            return data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        }

        guard let profile = (settings()?["discoveryProfile"] as? [String: Any]) else { return nil }
        let languages = profile["languages"] as? [String] ?? []
        let preferences = (profile["topicPreferences"] as? [String: Any] ?? [:])
            .compactMapValues { $0 as? String }
        return RunRecord(languages: languages, preferences: preferences,
            targets: scalar("SELECT COUNT(*) FROM acquisition_targets"),
            eligibleSources: scalar("SELECT COUNT(*) FROM acquisition_target_sources"))
    }

    /// Waits for the app's own record to state the whole chain the acceptance names, in order: the stored answers,
    /// then a non-empty eligible set, then acquisition actually started. Evaluated **before** any card or offer is
    /// read, so a later absence is a finding about publication rather than about the instrument.
    private func awaitTheRunRecord(_ namespace: String, within seconds: TimeInterval = 240) -> RunRecord? {
        let deadline = Date().addingTimeInterval(seconds)
        var last: RunRecord?
        while Date() < deadline {
            if let url = copyOfRunDatabase(namespace) {
                let record = readRunRecord(url)
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
                if let record {
                    last = record
                    if record.languages.contains("pt"), record.preference == "more",
                        record.targets > 0, record.eligibleSources > 0 {
                        return record
                    }
                }
            }
            Thread.sleep(forTimeInterval: 2)
        }
        return last
    }

    /// Makes an element the accessibility tree has not realised yet reachable: the discovery answers are a
    /// `LazyVGrid` inside the surface's scroll view, so a chip below the fold does not exist until the scroll
    /// brings it into view. Returns whether it is both present and hittable.
    @discardableResult
    private func reveal(_ element: XCUIElement, in scroller: XCUIElement, attempts: Int = 14) -> Bool {
        for _ in 0..<attempts {
            if element.exists, element.isHittable { return true }
            scroller.swipeUp()
            Thread.sleep(forTimeInterval: 0.4)
        }
        return element.exists && element.isHittable
    }

    /// The preferences page's own scroll surface. `scrollViews.firstMatch` is not it: the settings list this page
    /// is pushed from is still in the tree, and the order between the two is not a contract (measured 2026-10-20:
    /// swiping `firstMatch` scrolled the settings list behind the page, so the page's own chips were never realised
    /// and the toggle was never hittable).
    private func preferencesScroller(_ app: XCUIApplication) -> XCUIElement {
        let identified = app.scrollViews.matching(identifier: "discovery-preferences").firstMatch
        if identified.exists { return identified }
        return app.scrollViews.containing(.any, identifier: "discovery-editorial-tips").firstMatch
    }

    /// The profile the app **stored**, read where the app reads it: the discovery preferences page renders the
    /// same `ReaderSettingsStore` value the feed's discovery uses, and a chip states its selection to the
    /// accessibility tree (`.isSelected`). This is the "non-empty profile" the acceptance asks for, not the
    /// composer's own transient state.
    private func assertThePersistedProfile(_ app: XCUIApplication) {
        let page = preferencesScroller(app)
        XCTAssertTrue(page.waitForExistence(timeout: 20), "the preferences page has its own scroll surface")
        for _ in 0..<8 { page.swipeDown() }
        let language = app.buttons["discovery-language-pt"]
        let place = app.buttons["discovery-region-\(Self.brazilRegion)"]
        let languageReachable = reveal(language, in: page)
        let placeReachable = reveal(place, in: page)
        let languageSelected = languageReachable ? language.isSelected : false
        let placeSelected = placeReachable ? place.isSelected : false
        print("PROFILE_PREFERENCES_PAGE language=pt present=\(languageReachable) selected=\(languageSelected) "
            + "place=\(Self.brazilRegion) present=\(placeReachable) selected=\(placeSelected)")
        XCTAssertTrue(languageSelected, "the stored profile carries the language the reader answered")
        XCTAssertTrue(placeSelected, "the stored profile carries the place the reader answered")
    }

    /// The real catalogue is not the corpus: the first cards arrive about **fifty seconds** after the feed opens
    /// (measured on the device, 2026-10-11: `window` shows 0 cards at t+0 and 19 cards with 19 subjects at t+52,
    /// the first offer at t+53). A walk that starts before that walks an empty feed and reports a product failure
    /// that is a timing failure.
    ///
    /// The signal is "a card is there and stays there", not a count: the feed is a lazy stack, so the tree holds
    /// the cards near the viewport — with the enlarged text that is one or two of them, whatever the window holds.
    @discardableResult
    private func waitForTheFeed(_ app: XCUIApplication, within seconds: TimeInterval = 180,
        minimumCards: Int = 1) -> Int {
        let deadline = Date().addingTimeInterval(seconds)
        var stable = 0
        while Date() < deadline {
            let cards = app.buttons.matching(identifier: "card.bookmark").count
            if cards >= minimumCards { stable += 1; if stable >= 3 { return cards } } else { stable = 0 }
            Thread.sleep(forTimeInterval: 1.5)
        }
        let cards = app.buttons.matching(identifier: "card.bookmark").count
        print("FEED_TREE_BEGIN cards=\(cards)\n\(app.debugDescription)\nFEED_TREE_END")
        return cards
    }

    /// The app's own "Grande" text size: the architect asked for the enlarged-font evidence, and the app is where
    /// the reader sets it (the device's own size would move every screen, including the ones this test cannot see).
    private func chooseTheLargestTextSize(_ app: XCUIApplication) {
        openAdjustments(app)
        let picker = app.buttons["settings-type-scale"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "the adjustments state the text size")
        picker.tap()
        // "Grande" in the app's Portuguese, "Large" in the language this device is set to. The label is read
        // **before** the tap: the option is gone from the tree once the menu closes, and reading it afterwards
        // throws instead of comparing (measured on the device, 2026-10-11).
        let option = app.buttons.matching(labelled("Grande", "Large")).firstMatch
        guard option.waitForExistence(timeout: 8) else {
            return XCTFail("the reader can choose the largest text size")
        }
        let chosen = option.label
        option.tap()
        Thread.sleep(forTimeInterval: 1)
        // The row's own `value` is not the selection on this platform (`nil` measured), so the choice is proven
        // where it is stored — the app's preferences — and seen where it is drawn, in this run's screenshots.
        print("TYPE_SCALE_ROW value=\(String(describing: picker.value)) chosen=\(chosen)")
        app.buttons["settings-done"].tap()
        _ = app.scrollViews.firstMatch.waitForExistence(timeout: 30)
        let cards = waitForTheFeed(app)
        XCTAssertGreaterThanOrEqual(cards, 1,
            "the feed is still there after the reader's own preference round-trip")
    }

    private func invitationButtons(_ app: XCUIApplication, _ prefix: String) -> [XCUIElement] {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
            .allElementsBoundByIndex.filter { $0.exists }
    }

    /// Whether the element is really on the reader's screen: its centre inside the feed's own viewport. Used
    /// instead of `isHittable`, which is false for an element that is merely animating or partially covered —
    /// both of which happen while the feed is being scrolled, and neither of which means "the reader cannot see
    /// it" (measured on the device, 2026-10-11: the blocks were on screen while `isHittable` stayed false).
    private func onScreen(_ app: XCUIApplication, _ element: XCUIElement) -> Bool {
        guard element.exists, element.frame.height > 0 else { return false }
        let viewport = app.scrollViews.firstMatch.frame
        let centre = element.frame.midY
        return centre > viewport.minY + 8 && centre < viewport.maxY - 8
    }

    private func nudgeUp(_ app: XCUIApplication) { nudge(app, from: 0.72, to: 0.47) }

    private func nudge(_ app: XCUIApplication, from: CGFloat, to: CGFloat) {
        let feed = app.scrollViews.firstMatch
        guard feed.exists else { return }
        let start = feed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
        let end = feed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// Taps an element only once its frame has stopped moving. The feed keeps re-laying out while the window is
    /// admitted, and a tap between the query and the drop lands somewhere else — which is what the device showed:
    /// an answer that never applied, and an undo that was never reached (2026-10-11).
    @discardableResult
    private func settledTap(_ app: XCUIApplication, _ element: XCUIElement, attempts: Int = 3) -> Bool {
        for _ in 0..<attempts {
            guard element.exists else { Thread.sleep(forTimeInterval: 0.5); continue }
            var previous = element.frame
            for _ in 0..<8 {
                Thread.sleep(forTimeInterval: 0.3)
                guard element.exists else { break }
                let current = element.frame
                if abs(previous.minY - current.minY) <= 0.5, abs(previous.height - current.height) <= 0.5 {
                    break
                }
                previous = current
            }
            guard element.exists, onScreen(app, element) else { Thread.sleep(forTimeInterval: 0.5); continue }
            element.tap()
            return true
        }
        return false
    }

    private func offer(_ app: XCUIApplication, excluding seen: Set<String>) -> XCUIElement? {
        invitationButtons(app, "feed-invitation-more-")
            .first { onScreen(app, $0) && !seen.contains(subject(of: $0)) }
    }

    /// The next offer, read **forwards only**. The product places an offer on a card the reader has not been
    /// exposed to yet, so reading on is what meets it; a walk that had to look backwards would be hiding a product
    /// defect instead of testing one (architect, 2026-10-11).
    private func walkToNextOffer(_ app: XCUIApplication, excluding seen: Set<String>) -> XCUIElement? {
        walk(app, steps: 120, direction: nudgeUp, excluding: seen)
    }

    private func walk(_ app: XCUIApplication, steps: Int, direction: (XCUIApplication) -> Void,
        excluding seen: Set<String>) -> XCUIElement? {
        for step in 0..<steps {
            if let action = offer(app, excluding: seen) { return action }
            direction(app)
            Thread.sleep(forTimeInterval: 0.35)
            if step == steps - 1 {
                print("BUDGET_TREE_BEGIN\n\(app.debugDescription)\nBUDGET_TREE_END")
            }
        }
        return offer(app, excluding: seen)
    }

    private func subject(of offer: XCUIElement) -> String {
        offer.identifier.replacingOccurrences(of: "feed-invitation-more-", with: "")
    }

    /// The published cards carry their own identity (the frozen card id), which is what "the same card" means —
    /// a bookmark control is the same identifier on every card and cannot tell one card from another.
    private static let cardIdentifier = NSPredicate(format: "identifier MATCHES %@",
        "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")

    private func cards(_ app: XCUIApplication) -> [XCUIElement] {
        app.descendants(matching: .any).matching(Self.cardIdentifier).allElementsBoundByIndex
            .filter { $0.exists && $0.frame.height > 40 }
    }

    /// The card the reader is on: the topmost one whose top is at or below the viewport's own top edge. It is the
    /// card that must not move when the reader answers or hides an invitation.
    private func presentedCard(_ app: XCUIApplication) -> XCUIElement? {
        let viewport = app.scrollViews.firstMatch
        guard viewport.exists else { return nil }
        let top = viewport.frame.minY
        return cards(app).filter { $0.frame.minY >= top - 1 }.min { $0.frame.minY < $1.frame.minY }
    }

    private func frame(_ app: XCUIApplication, ofCard identifier: String) -> CGRect? {
        cards(app).first { $0.identifier == identifier }?.frame
    }

    /// The reader's card once the surface has stopped moving, with the identity captured so the *same* card can be
    /// measured afterwards. Answering an invitation rebuilds the session and the runtime re-admits the window
    /// afterwards — measuring in that gap measures the rebuild, not the reader — and the topmost card can change
    /// identity when a block below it grows or shrinks, which is why the identity travels with the measurement.
    private func settledAnchor(_ app: XCUIApplication, within seconds: TimeInterval = 10)
        -> (id: String, frame: CGRect)? {
        let deadline = Date().addingTimeInterval(seconds)
        var previous: (id: String, frame: CGRect)?
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.4)
            guard let card = presentedCard(app) else { previous = nil; continue }
            let current = (id: card.identifier, frame: card.frame)
            if let previous, previous.id == current.id,
                abs(previous.frame.minY - current.frame.minY) <= 1,
                abs(previous.frame.height - current.frame.height) <= 1 {
                return current
            }
            previous = current
        }
        return previous
    }

    /// The app speaks the reader's own language (round 9): on this device it is **English**, so a test that
    /// selects by Portuguese copy fails on a device that is working perfectly (measured on the iPhone,
    /// 2026-10-11: `app.buttons["Ajustes"]` never matched while the menu was open, its label being "Settings").
    /// Identifiers are the contract; where the app has none, both languages are accepted.
    private func labelled(_ portuguese: String, _ english: String) -> NSPredicate {
        NSPredicate(format: "label == %@ OR label == %@", portuguese, english)
    }

    /// The feed's menu → Ajustes, with the retry the device needed: the header's button exists before the header
    /// is ready to open it, and a first tap that only reaches the layout leaves the reader on the feed
    /// (measured on the device, 2026-10-11). On failure the tree is printed.
    private func openAdjustments(_ app: XCUIApplication) {
        for attempt in 0..<3 {
            let menu = app.buttons["more-menu"]
            if menu.waitForExistence(timeout: 20), menu.isHittable { menu.tap() }
            // The settings row carries the system symbol's own name as its identifier, which no language moves.
            let settings = app.buttons["gearshape"]
            if settings.waitForExistence(timeout: 8), settings.isHittable {
                settings.tap()
                XCTAssertTrue(app.buttons["settings-type-scale"].waitForExistence(timeout: 20),
                    "the adjustments opened")
                return
            }
            Thread.sleep(forTimeInterval: 1.5)
            if attempt == 2 { print("MENU_TREE_BEGIN\n\(app.debugDescription)\nMENU_TREE_END") }
        }
        XCTFail("the reader's own menu offers the adjustments")
    }

    /// The reader's own way back: the feed's menu → Ajustes → Preferências de descoberta, and the switch that
    /// shows and hides the invitations. Returns it so the caller can read and change the reader's choice.
    private func openDiscoveryPreferences(_ app: XCUIApplication) -> XCUIElement {
        openAdjustments(app)
        let row = app.buttons["settings-discovery-preferences"]
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the adjustments offer the discovery preferences")
        row.tap()
        let toggle = app.switches["discovery-editorial-tips"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 20), "the discovery preferences opened")
        let page = preferencesScroller(app)
        for _ in 0..<6 where !toggle.isHittable { page.swipeUp() }
        return toggle
    }

    /// The vertical room an invitation takes in the feed, measured the only way the surface allows: the distance
    /// between the card that hosts the block and the card that follows it. Both forms are measured the same way,
    /// so the comparison between them is the meaningful one — the absolute number is a layout fact, not a promise.
    private func blockExtent(_ app: XCUIApplication, host: String) -> CGFloat? {
        let id = subject(of: app.buttons[host])
        let block = app.buttons["feed-invitation-more-\(id)"]
        guard block.exists else { return nil }
        let published = cards(app).sorted { $0.frame.minY < $1.frame.minY }
        guard let mine = published.last(where: { $0.frame.maxY <= block.frame.minY + 1 }),
            let next = published.first(where: { $0.frame.minY > block.frame.minY }) else { return nil }
        return next.frame.minY - mine.frame.maxY
    }

    /// Every card the tree holds, by identity. The criterion the benchmark states for the reader's position is
    /// about **all** of what they already had, not only the card the reader happens to be on: a block that shrinks
    /// above them pulls everything under it up, and an anchor-based check misses exactly that case (measured on the
    /// device, 2026-10-11 — the corpus flow found the answer unstable while an anchor above the block read 0,0).
    private func visibleCardFrames(_ app: XCUIApplication) -> [String: CGRect] {
        var frames: [String: CGRect] = [:]
        for card in cards(app) where frames[card.identifier] == nil {
            frames[card.identifier] = card.frame
        }
        return frames
    }

    private func assertNothingMoved(_ app: XCUIApplication, from before: [String: CGRect],
        _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        let after = visibleCardFrames(app)
        for (identifier, frame) in before {
            guard let now = after[identifier] else { continue }
            XCTAssertEqual(frame.minY, now.minY, accuracy: 1,
                "card \(identifier) moved when \(what)", file: file, line: line)
        }
    }

    func testTheOfferBudgetHoldsOnTheRealCatalogue() throws {
        let namespace = freshNamespace()
        let app = launchForTheOfferBudget(namespace, firstRun: true)
        // A fresh reader meets the app; the first run is walked the way the product asks for it, and the profile it
        // gives is what makes discovery — and therefore the invitations — possible at all.
        try walkTheFirstRun(app, namespace: namespace)
        chooseTheLargestTextSize(app)
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 30))

        // 1. The session's first offer: the full question, with the sentence that states the consequence.
        let first = try XCTUnwrap(walkToNextOffer(app, excluding: []),
            "the feed offers an invitation on the real catalogue")
        let firstSubject = subject(of: first)
        XCTAssertTrue(app.staticTexts["feed-invitation-consequence-\(firstSubject)"].exists,
            "the session's first offer asks the full question")
        let fullExtent = blockExtent(app, host: first.identifier)
        attach(app, "first-offer-full")
        // It is deliberately **not** answered here: the next offer is what the budget owes the reader, and it is
        // reached by reading on.

        // 2. The next offer — a **different** subject, since the first block keeps its card and would otherwise be
        //    found again: compact, with no consequence sentence, and measurably less room than the full one.
        let second = try XCTUnwrap(walkToNextOffer(app, excluding: [firstSubject]),
            "the budget allows another offer after the interval")
        let secondSubject = subject(of: second)
        XCTAssertNotEqual(secondSubject, firstSubject, "the same subject is not asked twice")
        XCTAssertFalse(app.staticTexts["feed-invitation-consequence-\(secondSubject)"].exists,
            "the offers after the first are compact: they ask, they do not explain the product again")
        let compactExtent = blockExtent(app, host: second.identifier)
        attach(app, "second-offer-compact")
        if let fullExtent, let compactExtent {
            XCTAssertLessThan(compactExtent, fullExtent,
                "the compact block takes less room than the full one (\(compactExtent) < \(fullExtent))")
        }

        // 3. Answering it: the block states the answer where it was given, and the reader's card does not move.
        //    Taking the answer back holds too.
        let anchored = try XCTUnwrap(settledAnchor(app), "the reader is on a published card")
        let framesBeforeAnswer = visibleCardFrames(app)
        let undo = app.buttons["feed-invitation-undo-\(secondSubject)"]
        if !settledTap(app, second) || !undo.waitForExistence(timeout: 12) {
            // The block may have moved between the query and the tap: the reader's action is retried once, and
            // only then is its absence a finding.
            settledTap(app, second)
        }
        XCTAssertTrue(undo.waitForExistence(timeout: 12),
            "an answer taken offers the way back where it was taken")
        let afterAnswer = frame(app, ofCard: anchored.id)
        print("POSITION_ANSWER before=\(anchored.frame.minY) after=\(String(describing: afterAnswer?.minY))")
        if let after = afterAnswer?.minY {
            XCTAssertEqual(anchored.frame.minY, after, accuracy: 1,
                "answering an invitation does not move the card the reader is on")
        } else {
            XCTFail("the card the reader was on left the feed when the answer was applied")
        }
        assertNothingMoved(app, from: framesBeforeAnswer, "the invitation was answered")
        attach(app, "answered-in-place")
        settledTap(app, undo)
        Thread.sleep(forTimeInterval: 2.5)
        let afterUndoValue = frame(app, ofCard: anchored.id)?.minY
        print("POSITION_UNDO before=\(anchored.frame.minY) after=\(String(describing: afterUndoValue))")
        if let afterUndo = afterUndoValue {
            XCTAssertEqual(anchored.frame.minY, afterUndo, accuracy: 1,
                "taking the answer back does not move the card the reader is on either")
        }
        attach(app, "answer-taken-back-in-place")

        // 4. Hiding: the controls leave the accessibility tree — the tree VoiceOver reads — and the anchored card
        //    does not move. The block keeps its slot so the feed does not shift under the reader.
        let anchoredBeforeHide = try XCTUnwrap(settledAnchor(app), "the reader is on a published card")
        let framesBeforeHide = visibleCardFrames(app)
        let hide = invitationButtons(app, "feed-invitation-hide-").first(where: { onScreen(app, $0) })
        let hideButton = try XCTUnwrap(hide, "the offer carries the way to stop the offers")
        XCTAssertTrue(settledTap(app, hideButton), "the reader can press it where they see it")
        Thread.sleep(forTimeInterval: 3)
        let lingering = invitationButtons(app, "feed-invitation-")
        if !lingering.isEmpty {
            print("HIDE_LEFTOVERS \(lingering.map { "\($0.identifier)@\($0.frame)" }.joined(separator: " | "))")
            print("HIDE_TREE_BEGIN\n\(app.debugDescription)\nHIDE_TREE_END")
        }
        XCTAssertTrue(lingering.isEmpty,
            "a hidden invitation is gone from the accessibility tree, not merely invisible in it")
        // Nothing of the hidden suggestion is *announced* either: the architect's point — the absence of controls
        // does not prove the invisible words left the tree, and a reader with VoiceOver would still hear them.
        XCTAssertFalse(app.staticTexts["feed-invitation-consequence-\(secondSubject)"].exists,
            "not one word of the hidden suggestion is announced")
        XCTAssertEqual(app.staticTexts.matching(labelled("FeedMine sugere", "FeedMine suggests")).count, 0,
            "the block's own title is out of the tree as well")
        let afterHideValue = frame(app, ofCard: anchoredBeforeHide.id)?.minY
        print("POSITION_HIDE before=\(anchoredBeforeHide.frame.minY) after=\(String(describing: afterHideValue))")
        if let after = afterHideValue {
            XCTAssertEqual(anchoredBeforeHide.frame.minY, after, accuracy: 1,
                "hiding an invitation does not move the reader")
        }
        assertNothingMoved(app, from: framesBeforeHide, "the invitations were hidden")
        attach(app, "hidden-offers-gone-from-the-tree")

        // 5. Hiding stopped the offers: reading on — past the interval the budget would otherwise use — does not
        //    produce another one.
        let feed = app.scrollViews.firstMatch
        for _ in 0..<20 {
            feed.swipeUp()
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertTrue(invitationButtons(app, "feed-invitation-").isEmpty,
            "while the reader has hidden the invitations, the feed offers none")

        // 6. The way back, in the existing preferences page: the toggle restores them. The block that was offered
        //    keeps its card while hidden, so what the reader sees again is where they were — the walk looks both
        //    ways, because the reader read on before hiding. The reader's place survives the whole round-trip.
        let anchoredBeforePreferences = try XCTUnwrap(settledAnchor(app), "the reader is on a published card")
        let toggle = openDiscoveryPreferences(app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "the page offers the way back")
        XCTAssertEqual(toggle.value as? String, "0", "the switch states that the suggestions are hidden")
        // The same page reads the stored profile: the reader's own answers are the settings' value, which is what
        // the acceptance means by a non-empty profile.
        assertThePersistedProfile(app)
        for _ in 0..<10 where !toggle.isHittable { preferencesScroller(app).swipeUp() }
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "1", "the switch states what the reader chose")
        attach(app, "re-enable-in-the-existing-preferences")
        app.navigationBars.firstMatch.buttons.firstMatch.tap()   // back, whatever the page is called
        app.buttons["settings-done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 30))
        if let after = frame(app, ofCard: anchoredBeforePreferences.id)?.minY {
            XCTAssertEqual(anchoredBeforePreferences.frame.minY, after, accuracy: 1,
                "the reader's place survives the preferences round-trip that re-enabled the offers")
        }
        // The way back is bounded by **supply**, not by distance alone: re-enabling states its own interval, and the
        // product offers only on a card the reader has not been exposed to yet — a block behind the reader is one
        // they never meet, so it refuses that card. The step-5 walk ends at the tail, so the offer arrives with the
        // next publication; the loop keeps reading forward and waits when the tree did not grow, instead of walking
        // back over cards the ledger already counts (measured 2026-10-20: the backwards fallback found nothing in
        // 30 screens, because every card it crossed had been exposed before the offers were hidden).
        var restored: XCUIElement?
        let restoreDeadline = Date().addingTimeInterval(300)
        var seenCards = Set(visibleCardFrames(app).keys)
        let cardsAtReEnable = seenCards.count
        print("RESTORE_START cards=\(cardsAtReEnable)")
        var pass = 0
        while Date() < restoreDeadline, restored == nil {
            // Short passes, so the deadline measures supply and distance — not one long walk that spends it.
            restored = walk(app, steps: 40, direction: nudgeUp, excluding: [secondSubject])
            pass += 1
            if restored != nil { break }
            let now = Set(visibleCardFrames(app).keys)
            print("RESTORE_PASS \(pass) cards=\(now.count) new=\(now.subtracting(seenCards).count) "
                + "invitations=\(invitationButtons(app, "feed-invitation-").count)")
            if now == seenCards { Thread.sleep(forTimeInterval: 5) }
            seenCards = now
        }
        if restored == nil {
            print("RESTORE_MISS cards=\(seenCards.count) sinceReEnable=\(seenCards.count - cardsAtReEnable) "
                + "invitations=\(invitationButtons(app, "feed-invitation-").count)")
        }
        XCTAssertNotNil(restored, "showing the suggestions again restores them where the reader is")
        attach(app, "offers-restored")

        // 7. The reader's choice outlives the app: the same preference is what the page reads after a relaunch.
        app.terminate()
        Thread.sleep(forTimeInterval: 2)
        app.launchEnvironment["FEEDMINE_ONBOARDING"] = "0"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 120),
            "the feed returns after a relaunch")
        _ = waitForTheFeed(app)
        let toggleAgain = openDiscoveryPreferences(app)
        XCTAssertTrue(toggleAgain.waitForExistence(timeout: 10))
        XCTAssertEqual(toggleAgain.value as? String, "1",
            "the reader's answer about the suggestions is the database's, not the screen's")
        attach(app, "preference-survives-relaunch")
    }

    // Kiro K-06, achado 2 — a semântica que o arquiteto fixou é: ausência de oferta devolve `nil` (não uma linha
    // de altura zero, que o `LazyVStack` ainda espaçava) e esconder uma oferta já exposta preserva o slot. A
    // CORREÇÃO está no produto (`FeedMineApp.presented`), mas a MEDIÇÃO da metade "ausência" não é possível com os
    // instrumentos daqui: o frame do contêiner de card inclui o espaçamento da seção, então o vão entre contêineres
    // é sempre ≤ 0 (duas corridas perdidas nisso, 56 s cada), e a linha do slot escondido não tem identidade de
    // acessibilidade para medir. Reportado ao arquiteto com o pedido de uma costura observável no produto; a
    // metade "esconder preserva" continua coberta por `assertNothingMoved` no fluxo de esconder.

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
