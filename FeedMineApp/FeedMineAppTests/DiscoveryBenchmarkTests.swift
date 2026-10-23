import XCTest
import Foundation

/// The acceptance benchmark's **driver**. It is not production code and it judges nothing: it walks the journey
/// the benchmark describes through the real app, with native gestures, and leaves the verdict to the frozen oracle
/// (`bench/oracle.py`), which reads the corpus's own labels, the local transport's request log and the app's
/// database afterwards.
///
/// Gate names are the benchmark's own (`docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md` §3). The durations,
/// thresholds and corpus composition are the benchmark's; nothing here may shorten them, and a run that cannot
/// finish records NOT_RUN rather than a smaller trace.
@MainActor
final class DiscoveryBenchmarkTests: XCTestCase {
    private struct Profile {
        let interests: [String]
        let languages: [String]
        /// The place the profile names, or nil when the corpus states that this profile is **not**
        /// country-scoped: the driver answers places the corpus names, never one it invents.
        let region: String?
    }

    private var environment: [String: String] { ProcessInfo.processInfo.environment }

    /// Where this run's phase record is written. On the simulator `bench/run.sh` names a path on the Mac, which a
    /// simulator can write because it reads the Mac's filesystem. A device cannot: the runner's container is not a
    /// host path. So when the runner names no path the record goes to the runner's own container, and `tearDown`
    /// attaches it to the result bundle, from which the runner extracts it into the place the oracle already reads.
    private var phasesURL: URL?

    /// The run's identity, provided by `bench/run.sh`: where the corpus is, where the transport's log lands, and
    /// the namespace this run's app state lives under.
    private func runIdentity() throws -> (corpus: URL, namespace: String, phases: URL?, profile: String) {
        guard environment["FEEDMINE_BENCHMARK"] == "1" else {
            throw XCTSkip("the acceptance benchmark runs through bench/run.sh, never from a bare test invocation")
        }
        // Where the run's labels live. The driver uses the corpus for exactly one thing — `profiles.json` — and it
        // reads it from its own test bundle, which is the one location that exists in both modes. A host path
        // worked on the simulator only because a simulator reads the Mac's filesystem; on a device there is no
        // such path, and a difference that exists in one mode is exactly what this benchmark exists to measure.
        let bundled = Bundle(for: DiscoveryBenchmarkTests.self).bundleURL
        let corpus = environment["FEEDMINE_BENCH_CORPUS"].map { URL(fileURLWithPath: $0) } ?? bundled
        // An explicit path that cannot be read is a configuration error, and it refuses rather than falling back
        // silently: a run whose labels came from somewhere else is not the run that was asked for.
        precondition(FileManager.default.isReadableFile(atPath: corpus.appendingPathComponent("profiles.json").path),
            "the run's labels are unreadable at \(corpus.path) — refusing before any measurement")
        let namespace = try XCTUnwrap(environment["FEEDMINE_BENCH_NAMESPACE"])
        let phases = environment["FEEDMINE_BENCH_PHASES"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("phases-\(namespace).txt")
        phasesURL = phases
        return (corpus, namespace, phases, environment["FEEDMINE_BENCH_PROFILE"] ?? "A")
    }

    /// The phase record rides out with the result bundle. It is the one input the oracle takes from the runner
    /// rather than from the host's own files: on a device there is no host path to write it to, and a journey whose
    /// phases never arrive must read as NOT_RUN, never as a quiet pass. `keepAlways` because the default lifetime
    /// deletes attachments on success — which is precisely the case this exists to record.
    override func tearDown() {
        if let phasesURL, let data = try? Data(contentsOf: phasesURL) {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.plain-text")
            attachment.name = "phases"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        super.tearDown()
    }

    /// The profile the corpus was labelled for, as data — the driver answers the Composer with it.
    private func profile(_ name: String, in corpus: URL) throws -> Profile {
        let data = try Data(contentsOf: corpus.appendingPathComponent("profiles.json"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entry = try XCTUnwrap(json[name] as? [String: Any])
        return Profile(interests: try XCTUnwrap(entry["interests"] as? [String]),
            languages: try XCTUnwrap(entry["languages"] as? [String]),
            region: entry["region"] as? String)
    }

    private func launch(_ namespace: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = namespace
        app.launchEnvironment["FEEDMINE_ONBOARDING"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "0"
        app.launch()
        return app
    }

    /// The catalogue's own node key, as the surfaces name it.
    private static func nodeKey(_ key: String) -> String {
        key.hasPrefix("topic:") ? String(key.dropFirst("topic:".count)) : key
    }

    /// The card containers now on screen, topmost first: the frozen card elements carry their own identity.
    private func visibleCards(_ app: XCUIApplication) -> [XCUIElement] {
        let viewport = app.scrollViews.firstMatch
        guard viewport.exists else { return [] }
        let top = viewport.frame.minY
        let cards = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@", "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"))
        return cards.allElementsBoundByIndex
            .filter { $0.frame.height > 40 && $0.frame.minY >= top - 1 }
            .sorted { $0.frame.minY < $1.frame.minY }
    }

    /// The card the reader is **on**: the topmost one whose top is at or below the viewport's own top edge. The
    /// measurement must watch that card, not merely the first one on screen — content below a removed block
    /// necessarily shifts up, and calling that "the reader moved" would be measuring the wrong thing.
    ///
    /// It is the card **itself** (the published card carries its own identity), not a control inside it: every
    /// card's save control is the same identifier, so a measurement built on it cannot tell one card from another
    /// and reported "stable" whatever moved (architect, 2026-10-11). The criterion is unchanged: the card the
    /// reader is on must not move.
    private func presentedCard(_ app: XCUIApplication) -> XCUIElement? {
        visibleCards(app).first
    }

    /// The frame of **this** card, wherever it is now. Following the identity is what makes a stability
    /// measurement mean "the card the reader was on did not move" instead of "some card is where some card was".
    private func frame(_ app: XCUIApplication, ofCard identifier: String) -> CGRect? {
        laidOutCard(app, identifier)?.frame
    }

    /// The card with this identity, if the surface has laid it out. Every card, wherever it is: following the
    /// identity through a viewport filter would report "moved" for a card that merely crossed the reference line.
    private func laidOutCard(_ app: XCUIApplication, _ identifier: String) -> XCUIElement? {
        everyCardElement(app).first { $0.exists && $0.frame.height > 40 && $0.identifier == identifier }
    }

    private func everyCardElement(_ app: XCUIApplication) -> [XCUIElement] {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@",
                "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"))
            .allElementsBoundByIndex
    }

    /// Whether this card is inside the feed's viewport right now — the only state in which a stability measurement
    /// is about what the reader sees rather than about the window being re-admitted around them.
    private func onScreenCard(_ app: XCUIApplication, _ card: String) -> Bool {
        guard let frame = frame(app, ofCard: card) else { return false }
        let viewport = app.scrollViews.firstMatch.frame
        return frame.midY > viewport.minY + 8 && frame.midY < viewport.maxY - 8
    }

    /// Why a stability fact could not be measured, stated precisely: a card that is **absent** from the tree is a
    /// different fact from one that is present but has not been laid out (a degenerate frame), and both are
    /// different from the card being kept (architect, 2026-10-11).
    private func unmeasurableReason(_ app: XCUIApplication, card: String) -> String {
        if let element = everyCardElement(app).first(where: { $0.exists && $0.identifier == card }) {
            return "card-not-laid-out(height=\(Int(element.frame.height)))"
        }
        let top = visibleCards(app).prefix(2).map(\.identifier).joined(separator: ",")
        return "card-absent(on-screen=\(top.isEmpty ? "none" : top))"
    }

    /// The three outcomes a stability fact may have. **Not measurable** is its own value: frames that never came
    /// (`-9999`) neither show movement nor prove stability, and the oracle must not read them as a pass
    /// (architect, 2026-10-11). The product criterion is unchanged: `stable` is `true`.
    private enum Stability: String {
        case stable = "true"
        case unstable = "false"
        case notMeasurable = "not-measurable"
    }

    /// Whether **this** card is where it was, with the reason, and never a substitute card.
    private func stability(_ app: XCUIApplication, card: String, from before: CGRect) -> (Stability, String) {
        guard let after = frame(app, ofCard: card) else {
            return (.notMeasurable, unmeasurableReason(app, card: card))
        }
        let held = abs(before.minY - after.minY) < 1 && abs(before.height - after.height) < 1
        return (held ? .stable : .unstable, "\(Int(before.minY))->\(Int(after.minY))")
    }

    /// Brings this card back into the rendered window so the next measurement is about the same card. The driver
    /// never substitutes another card for the one it is following (architect, 2026-10-11).
    @discardableResult
    private func bringIntoView(_ app: XCUIApplication, card: String, within steps: Int = 8) -> Bool {
        // Both directions, and the reason is measured: supply arrives *above* an idle reader, which pushes their
        // card down and out of the instantiated window — scrolling back is what finds it again, not only scrolling
        // forward (architect, 2026-10-11).
        // "On screen", not "in the tree": a card that is laid out but outside the viewport is still found by the
        // query, so a check built on that never scrolls and the measurement never becomes possible (measured on the
        // device, 2026-10-11 — the reason read `card-not-laid-out(height=185)` for a card that had a frame).
        let directions: [(XCUIElement) -> Void] = [{ $0.swipeUp() }, { $0.swipeDown() }]
        for direction in directions {
            for _ in 0..<steps {
                if onScreenCard(app, card) { return true }
                direction(app.scrollViews.firstMatch)
                Thread.sleep(forTimeInterval: 0.4)
            }
        }
        return onScreenCard(app, card)
    }

    /// Polls a condition until it holds or the bound expires. The bound is stated by the caller; there is no
    /// unconditional sleep in the protocol — a wait exists to let the product's own decision be observed.
    private func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return condition()
    }

    /// The product's context-menu entries, in the order the menu declares them: the main context first, then one
    /// entry per selected source. A SwiftUI `Menu` exposes its items as buttons with **no identifier** and a
    /// localized label, so neither an identifier nor a literal string can name them; every app control on this
    /// surface carries an identifier, which is what separates the menu's own rows from the feed underneath.
    private func contextMenuItems(_ app: XCUIApplication) -> [XCUIElement] {
        app.buttons.allElementsBoundByIndex
            .filter { $0.exists && $0.isHittable && $0.identifier.isEmpty && !$0.label.isEmpty }
            .sorted { $0.frame.minY < $1.frame.minY }
    }

    /// Returns to the main context through the product's own control. The identity witness is
    /// `reader-context-label`: present only while a source (or search) context is shown.
    private func returnToMainContext(_ app: XCUIApplication) -> Bool {
        let chip = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "reader-contexts")).firstMatch
        let label = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "reader-context-label")).firstMatch
        if !label.exists { return true }
        guard chip.waitForExistence(timeout: 60), waitUntil(60, { chip.isHittable }) else { return false }
        chip.tap()
        guard waitUntil(10, { !contextMenuItems(app).isEmpty }),
            let main = contextMenuItems(app).first else { return false }
        main.tap()
        return waitUntil(30) { !label.exists }
    }

    /// Frozen-corpus identities for B05's precondition (`bench/corpus/catalog.sqlite` + `items.json`):
    /// * the section nodes a section-scoped profile's interests name (ids are the catalogue's own);
    /// * the exact source each profile enables, pinned by its catalogue key: A → ArchDaily em Português
    ///   (`https://feeds.feedburner.com/ArchdailyBR`, 8/8 items eligible for A), B → Twenty Thousand Hertz
    ///   (`https://feed.20k.org`, 9/9 eligible for B). The source is selected by key, never by display order.
    private static let benchmarkSectionNodes: [String: Int64] = [
        "04-technology-science": 3_192_345_324,
        "01-news-current-affairs": 1_681_750_652,
    ]
    private static let benchmarkSourceKeys: [String: String] = [
        "A": "https://feeds.feedburner.com/ArchdailyBR",
        "B": "https://feed.20k.org",
    ]

    /// B05's declared input — **two real reading contexts** — established through the product's own surfaces and
    /// reported as facts, before A is named or measured. The benchmark's reader starts with no selected source
    /// (`reader_preferences.source_keys` empty), which is the product's honest empty selection; `reader-contexts`
    /// then lists only the main context. The reader's own act creates the second one: the overflow menu's Sources
    /// sheet and one **profile-compatible** catalogue source. The route is chosen from the frozen corpus, not
    /// from display order: profile A's region node, or the section node its interests name. Nothing is injected.
    @discardableResult
    private func prepareB05Contexts(_ app: XCUIApplication, phases: URL?, profile: Profile,
        runProfile: String) -> Bool {
        // The overflow menu's entries carry the SF Symbol as their identifier (ReaderNavigation.standard), so the
        // Sources entry is language-independent. A first open can precede installed destinations: same gesture.
        var opened = false
        for _ in 0..<4 {
            let menu = app.buttons["more-menu"]
            guard menu.waitForExistence(timeout: 20) else { break }
            menu.tap()
            let entry = app.buttons["antenna.radiowaves.left.and.right"].firstMatch
            if entry.waitForExistence(timeout: 5) {
                entry.tap()
                opened = true
                break
            }
            if menu.exists { menu.tap() }
            Thread.sleep(forTimeInterval: 1)
        }
        guard opened else {
            record("b05-precondition:not-opened", to: phases)
            return false
        }
        // Route: a region-scoped profile opens its own country; a section-scoped profile opens the first section
        // its interests name. Both nodes lead, by the catalogue's own order, to a source that can publish here.
        let countrySlug = profile.region?.split(separator: "/").last.map(String.init)
        let section = profile.interests.lazy.compactMap { key in
            Self.benchmarkSectionNodes[key].map { (key, $0) }
        }.first
        if let countrySlug {
            guard reveal(app, app.buttons["sources-open-countries"]) else {
                record("b05-precondition:no-countries-link", to: phases)
                closeSourcesSheet(app)
                return false
            }
            app.buttons["sources-open-countries"].tap()
            let row = app.buttons["country-\(countrySlug)"]
            guard reveal(app, row), row.isHittable else {
                record("b05-precondition:no-country:\(countrySlug)", to: phases)
                closeSourcesSheet(app)
                return false
            }
            record("b05-precondition-route:country/\(countrySlug)", to: phases)
            row.tap()
        } else if let section {
            let row = app.buttons["node-child-\(section.1)"]
            guard reveal(app, row), row.isHittable else {
                record("b05-precondition:no-section:\(section.0)", to: phases)
                closeSourcesSheet(app)
                return false
            }
            record("b05-precondition-route:section/\(section.0)", to: phases)
            row.tap()
        } else {
            record("b05-precondition:no-route", to: phases)
            closeSourcesSheet(app)
            return false
        }
        // The exact source this profile can publish, pinned by its catalogue key. The node's rows are lazy, so the
        // switch is brought into view; if the route did not reach a node that holds it, the step fails with the
        // key it wanted instead of falling back to whatever row happens to be first.
        guard let expectedKey = Self.benchmarkSourceKeys[runProfile] else {
            record("b05-precondition:no-pinned-source-for-profile:\(runProfile)", to: phases)
            closeSourcesSheet(app)
            return false
        }
        record("b05-precondition-source-expected:\(expectedKey)", to: phases)
        let pinned = app.switches["node-source-toggle-\(expectedKey)"]
        var found = false
        for _ in 0..<6 {
            if reveal(app, pinned, attempts: 4) { found = true; break }
            let child = app.buttons.matching(NSPredicate(
                format: "identifier BEGINSWITH 'node-child-'")).firstMatch
            guard child.waitForExistence(timeout: 8) else { break }
            child.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard found else {
            record("b05-precondition:no-pinned-source:\(expectedKey)", to: phases)
            closeSourcesSheet(app)
            return false
        }
        let sourceName = pinned.label
        pinned.tap()
        Thread.sleep(forTimeInterval: 1)
        record("b05-precondition-source:\(expectedKey)", to: phases)
        record("b05-precondition-source-name:\(sourceName)", to: phases)
        record("b05-precondition-source-selected:\(String(describing: pinned.value))", to: phases)
        closeSourcesSheet(app)
        _ = waitUntil(20) { !app.buttons["sources-done"].exists }
        // Return **immediately**, before waiting for any card: one selected source makes it the reading context,
        // and the shell (mounted even while that context has no item) is what offers the way back. Waiting for the
        // source's content first is what made the driver mistake an empty context for a missing control.
        let returned = returnToMainContext(app)
        record("b05-precondition-main:\(returned)", to: phases)
        // Only now wait for A's own publication; the anchor is measured on the final main feed.
        _ = waitUntil(120) { presentedCard(app) != nil }
        return returned
    }

    /// Scrolls a list until the control is really reachable. The sheets' rows are lazy, so existence alone does
    /// not mean the reader's own row is on screen.
    private func reveal(_ app: XCUIApplication, _ element: XCUIElement, attempts: Int = 10) -> Bool {
        for _ in 0..<attempts {
            if element.exists && element.isHittable { return true }
            let list = app.tables.firstMatch
            if list.exists { list.swipeUp() } else { app.swipeUp() }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return element.exists && element.isHittable
    }

    /// Leaves the source surface without changing anything else: back to its root, then its own Done control.
    private func closeSourcesSheet(_ app: XCUIApplication) {
        for _ in 0..<8 where !app.buttons["sources-done"].exists {
            let back = app.navigationBars.buttons.firstMatch
            guard back.exists, back.isHittable else { break }
            back.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
        let done = app.buttons["sources-done"]
        if done.exists && done.isHittable { done.tap() }
    }

    /// The scene B04 measures: an invitation block that is on screen **above** the reader's card, plus that
    /// card's identity and frame. The block above the reader is the case an anchor-only check cannot see: when the
    /// block's own form changes (answering makes it shorter), everything under it moves, and the anchor is under it
    /// (architect, 2026-10-11). Returns nil when no offer can be brought into that relation within the walk.
    private func prepareTheAnswerScene(_ app: XCUIApplication)
        -> (block: XCUIElement, identifier: String, frame: CGRect)? {
        let feed = app.scrollViews.firstMatch
        // The offers are asked for first and the (expensive) card query only runs when one is visible: the app is a
        // Debug build doing real work, and a preparation leaning on heavy element queries can hold it up until a
        // query times out (measured on the device, 2026-10-11).
        for _ in 0..<20 {
            let viewport = feed.frame
            let offers = app.buttons
                .matching(NSPredicate(format: "identifier BEGINSWITH 'feed-invitation-more-'"))
                .allElementsBoundByIndex
                .filter { $0.exists && $0.frame.height > 0
                    && $0.frame.midY > viewport.minY + 8 && $0.frame.midY < viewport.maxY - 8 }
                .sorted { $0.frame.minY < $1.frame.minY }
            guard !offers.isEmpty else {
                feed.swipeUp()
                Thread.sleep(forTimeInterval: 0.5)
                continue
            }
            let published = visibleCards(app)
            for offer in offers {
                // The reader's card is the first published card **below** the block, and it has to be on screen:
                // the block sits above the reader, which is the relation this gate measures.
                if let anchor = published.first(where: { $0.frame.minY > offer.frame.maxY }),
                    anchor.frame.midY < viewport.maxY - 8 {
                    return (offer, anchor.identifier, anchor.frame)
                }
            }
            feed.swipeUp()
            Thread.sleep(forTimeInterval: 0.5)
        }
        return nil
    }

    /// The way to hide the invitations, wherever the feed is currently offering one.
    private func hideTipsButton(_ app: XCUIApplication) -> XCUIElement? {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'feed-invitation-hide-'"))
            .allElementsBoundByIndex.first { $0.exists && $0.isHittable }
    }

    /// Scrolls until the subject's own invitation is on screen (bounded), or gives up without inventing anything.
    private func invitation(moreFor node: String, in app: XCUIApplication, feed: XCUIElement,
        within swipes: Int = 30) -> XCUIElement? {
        let button = app.buttons["feed-invitation-more-\(node)"]
        for _ in 0..<swipes {
            if button.exists && button.isHittable { return button }
            feed.swipeUp()
        }
        return nil
    }

    /// The phases the driver actually walked, appended where the runner can read them. The oracle needs this: a
    /// journey that never reached a phase must be **NOT_RUN** there, never a quiet pass.
    /// The **throwing** `write(contentsOf:)` is deliberate: `NSFileHandle.write(_:)` raises an Objective-C
    /// exception when the syscall fails (measured: ENOSPC on a nearly full host volume aborted the app's own
    /// trace), and an exception on a full disk would take the whole runner down instead of losing one line.
    private func record(_ phase: String, to file: URL?) {
        guard let file else { return }
        let data = Data((phase + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: file)
        }
    }

    /// The journey the product promises now (2026-10-10): the reader answers **idiomas e lugares**, enters the
    /// feed, and the subjects are answered **inside it** — B01's own alignment, and F02's rule that no form stands
    /// between the person and a genuinely interesting feed. Two phases are walked and recorded separately: the
    /// neutral feed, and the feed after two thematic answers.
    private func walkTheFirstRunJourney(_ app: XCUIApplication, profile: Profile, name: String,
        phases: URL?, hidesTheTips: Bool = true, answersInTheFeed: Bool = true) throws {
        XCTAssertTrue(app.staticTexts["welcome-headline"].waitForExistence(timeout: 90),
            "the app meets the reader before the feed")
        app.buttons["welcome-shape"].tap()
        XCTAssertTrue(app.staticTexts["composer-subtitle"].waitForExistence(timeout: 30),
            "the first run states what it collects")

        // Languages: the reader's own set. A chip the reader does not want is turned off (V1 kept at least one).
        let chips = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'composer-language-'"))
        for index in 0..<chips.count {
            let chip = chips.element(boundBy: index)
            guard chip.exists, let code = chip.identifier.split(separator: "-").last.map(String.init) else { continue }
            let wanted = profile.languages.contains(code)
            let isOn = chip.isSelected || chip.value as? String == "1"
            if wanted != isOn {
                chip.tap()
            }
        }

        let composer = app.otherElements["onboarding"].scrollViews.firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 20))

        // Places: more than one is allowed, and each is an interest like any other. A profile the corpus does
        // not scope to a country answers no place at all — the driver never invents one.
        if let region = profile.region {
            let place = app.buttons["composer-region-\(region)"]
            var placeFound = false
            for _ in 0..<8 where !placeFound {
                if place.exists && place.isHittable { placeFound = true; break }
                composer.swipeUp()
            }
            guard placeFound else {
                return XCTFail("the first run does not offer the place \(region) the profile names")
            }
            if !place.isSelected { place.tap() }
            XCTAssertTrue(place.isSelected, "the reader's place is stated")
        }

        // F02: the first run asks no subject at all. A subject question here is the questionnaire the product
        // refuses to put in front of discovery.
        let subjectChips = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'composer-topic-'"))
        XCTAssertEqual(subjectChips.count, 0,
            "the first run collects languages and places only; subjects are answered inside the feed")

        // Save and open: from here on the reader only reads.
        let open = app.buttons["composer-open-feed"]
        for _ in 0..<6 where !open.isHittable { composer.swipeUp() }
        XCTAssertTrue(open.isHittable, "the first run's own action starts the feed")
        open.tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 180),
            "the reader reaches content without opening the sources screen")
        record("neutral", to: phases)

        // The second phase: two thematic answers **inside the feed**, on cards the reader is already reading. The
        // driver looks for the surface and answers it if it is really there; the phase is recorded only then, so
        // an unbuilt surface cannot be mistaken for a walked journey.
        //
        // A gate that measures the invitations itself says so and keeps them for its own protocol: the answers
        // spent here are offers the gate would no longer have (architect, 2026-10-11).
        let feed = app.scrollViews.firstMatch
        guard answersInTheFeed else {
            record("neutral", to: phases)
            return
        }
        // The two answers are taken **inside the feed**, as a reader takes them: from the top, by touching the
        // block that the feed renders after the card it is asking about. The driver acts and records the act; the
        // oracle judges the result from the reader's own stored answers — an element query is not the product.
        for _ in 0..<12 { feed.swipeDown() }
        var tapped = 0
        while tapped < 2 {
            // The action first: the surface exposes its buttons, so the benchmark answers the way any reader — or
            // any assistive technology — does. The coordinate tap is the fallback for a block the tree has not
            // published yet, never the primary path.
            let action = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'feed-invitation-more-'"))
                .firstMatch
            if action.exists && action.isHittable {
                let node = action.identifier.replacingOccurrences(of: "feed-invitation-more-", with: "")
                action.tap()
                tapped += 1
                record("answered:\(node)", to: phases)
                Thread.sleep(forTimeInterval: 3.0)
                continue
            }
            // No action on screen yet: the feed moves to the next subject as the reader reads. The search moves a
            // screen at a time and looks again — still by action, never by pixel — and gives up after a bounded
            // walk so a feed with nothing to ask cannot hang the journey.
            var walked = 0
            while walked < 20, !(action.exists && action.isHittable) {
                feed.swipeUp()
                Thread.sleep(forTimeInterval: 0.5)
                walked += 1
            }
            if action.exists && action.isHittable {
                let node = action.identifier.replacingOccurrences(of: "feed-invitation-more-", with: "")
                action.tap()
                tapped += 1
                record("answered:\(node)", to: phases)
                Thread.sleep(forTimeInterval: 3.0)
                continue
            }
            break
        }
        if tapped >= 1 { record("thematic-attempted", to: phases) }
        if tapped < 2 {
            // Whatever the tree had when the phase ended, in the log: the alternative is another guess.
            print("BENCH_TREE_BEGIN\n\(app.debugDescription)\nBENCH_TREE_END")
        }

        // B04's geometry question, measured on the real surface (the reviewer's point): hiding the tips takes a
        // block **out of** the feed, and the card the reader is looking at must not move because of it.
        // A gate that measures the invitations itself needs them enabled: B04 answers, takes back and hides its
        // own, and hiding here would leave it nothing to measure (architect, 2026-10-11). No preference outside the
        // isolated test environment is touched — this runs in the run's own namespace.
        if hidesTheTips, let card = presentedCard(app), let hide = hideTipsButton(app) {
            let before = card.frame
            let cardID = card.identifier
            hide.tap()
            Thread.sleep(forTimeInterval: 3.0)
            let after = frame(app, ofCard: cardID) ?? .zero
            let stable = abs(before.minY - after.minY) < 1 && abs(before.height - after.height) < 1
            record("hide-stable:\(stable)", to: phases)
            record("hide-frames:\(Int(before.minY))->\(Int(after.minY))", to: phases)
        }

        // The PRD's profile B adds a **negative answer and a reversal** (its §"Perfil B"): "menos disso", and then
        // the way back. Both are the reader's own actions, taken through the real surface.
        guard name == "B" else { return }
        // The block asking a subject the reader has not answered yet offers both actions; the negative answer is
        // taken **there**, while it is offered — a block that was answered shows only the way back.
        let less = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'feed-invitation-less-'")).firstMatch
        for _ in 0..<20 where !(less.exists && less.isHittable) {
            feed.swipeUp()
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard less.exists, less.isHittable else {
            record("negative:not-offered", to: phases)
            return
        }
        less.tap()
        let undo = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'feed-invitation-undo-'")).firstMatch
        guard undo.waitForExistence(timeout: 15) else {
            return XCTFail("an answer taken must offer the way back")
        }
        record("negative", to: phases)
        undo.tap()
        record("reversed", to: phases)
    }

    /// B01 — discovery without a subscription. The journey above; the oracle then counts the sources the corpus
    /// was actually asked for and the ones that contributed, both of which are its own evidence.
    func testB01DiscoveryWithoutASubscription() throws {
        let (corpus, namespace, phases, runProfile) = try runIdentity()
        let app = launch(namespace)
        try walkTheFirstRunJourney(app, profile: try profile(runProfile, in: corpus), name: runProfile,
            phases: phases)
        // Read for a while: the first screen is a promise, the next minutes are the product.
        let feed = app.scrollViews.firstMatch
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            feed.swipeUp()
            if Date().timeIntervalSince(deadline) > -100 { continue }
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "b01-first-run"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// B04 — the presented feed is sacred. What the reader already has must not move, reorder or retract, and only
    /// a legitimate advance admits new stories. The two crossings the product review prioritised are measured
    /// against an anchored card: answering/undoing/hiding an invitation inside the feed, and a suspended candidate
    /// becoming ready while the reader is stopped.
    ///
    /// Every measurement is recorded as a fact in the run's phase file; the oracle judges them, never this driver.
    func testB04PresentedFeedIsSacred() throws {
        let (corpus, namespace, phases, runProfile) = try runIdentity()
        let app = launch(namespace)
        // The journey is walked **without hiding the invitations**: this gate answers, takes back and hides its own
        // block, and hiding during the journey would leave it nothing to measure (architect, 2026-10-11).
        try walkTheFirstRunJourney(app, profile: try profile(runProfile, in: corpus), name: runProfile,
            phases: phases, hidesTheTips: false, answersInTheFeed: false)
        let feed = app.scrollViews.firstMatch

        // 1. The anchor and the admitted order, as the reader sees them.
        //
        // D4 holds the laid-out cards out of the accessibility tree behind the preparation cover until the
        // measured layout reaches the viewport bottom (or the product's own captured wait expires; bootstrap 5 s,
        // then the run's measured tolerance). B04 measures the **reading** surface: querying right after the
        // onboarding tap measures the cover, not the feed. Measured, run `20261023T192530Z`: the card was published
        // and admitted 1.30 s before the driver's query, the cover was still up, and the driver aborted.
        //
        // So the driver waits for the cover's own element to be gone and for `presentedCard` — bounded by that
        // product readiness, not by a new threshold and not by an unconditional sleep. The elapsed wait is
        // recorded after the card is found, so a run where the first card really is late still shows it; a card
        // that never arrives still fails the driver (no B04 fact is recorded before it, so the gate cannot turn
        // that failure into a quiet pass).
        let readinessStarted = Date()
        let readinessDeadline = readinessStarted.addingTimeInterval(30)
        let cover = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "feed-loading-surface")).firstMatch
        var readyCard: XCUIElement?
        var readinessFailure = "the first-screen cover never lifted within the product's readiness bound"
        while Date() < readinessDeadline {
            if !cover.exists {
                if let card = presentedCard(app) {
                    readyCard = card
                    break
                }
                readinessFailure = "the cover lifted but no card was presented within the readiness bound"
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard let anchor = readyCard else {
            return XCTFail(readinessFailure)
        }
        record("b04-readiness-seconds:"
            + String(format: "%.1f", Date().timeIntervalSince(readinessStarted)), to: phases)
        let anchorBefore = anchor.frame
        let anchorID = anchor.identifier
        let orderBefore = presentedIdentifiers(app)
        record("b04-anchor0:\(Int(anchorBefore.minY))", to: phases)
        _ = (anchorBefore, anchorID, orderBefore)

        // 2. The invitation **above the reader**: answer it, take it back, hide the invitations. Position and order
        //    are measured on the same card, never on a substitute; a measurement that could not be taken is
        //    recorded as such instead of being read as a pass.
        var attempt = 0
        var primaryRecorded = false
        while attempt < 2 {
            attempt += 1
            guard let scene = prepareTheAnswerScene(app) else {
                record("\(primaryRecorded ? "b04-retry" : "b04")-invitation:not-offered", to: phases)
                break
            }
            let before = scene.frame
            let card = scene.identifier
            let orderAtStart = presentedIdentifiers(app)
            if !primaryRecorded {
                record("b04-block-above-reader:true", to: phases)
                record("b04-anchor0:\(Int(before.minY))", to: phases)
            }
            scene.block.tap()
            Thread.sleep(forTimeInterval: 2.5)
            let answered = stability(app, card: card, from: before)
            let orderAfterAnswer = presentedIdentifiers(app)

            let undo = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'feed-invitation-undo-'"))
                .firstMatch
            var undone: (Stability, String) = (.notMeasurable, "no-undo-offered")
            if undo.exists {
                undo.tap()
                Thread.sleep(forTimeInterval: 2.5)
                undone = stability(app, card: card, from: before)
            }

            let hide = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'feed-invitation-hide-'"))
                .firstMatch
            var hidden: (Stability, String) = (.notMeasurable, "no-hide-offered")
            if hide.exists {
                hide.tap()
                Thread.sleep(forTimeInterval: 3.0)
                hidden = stability(app, card: card, from: before)
            }

            // The repeat **is** the measurement: when the card left the tree the reader is repositioned and the
            // cycle runs again, and it is that run which states the fact — never a substitute card, and never a
            // first attempt that could not be measured (architect, 2026-10-11). The first attempt is kept beside
            // it, so a repeated measurement can always be told from a first one.
            if primaryRecorded {
                record("b04-first-answer:\(answered.0.rawValue)", to: phases)
                record("b04-first-undo:\(undone.0.rawValue)", to: phases)
                record("b04-first-hide:\(hidden.0.rawValue)", to: phases)
            }
            record("b04-after-answer-stable:\(answered.0.rawValue)", to: phases)
            record("b04-after-answer-frames:\(answered.1)", to: phases)
            record("b04-after-answer-order:\(orderAtStart == orderAfterAnswer)", to: phases)
            record("b04-after-undo-stable:\(undone.0.rawValue)", to: phases)
            record("b04-after-undo-frames:\(undone.1)", to: phases)
            record("b04-after-hide-stable:\(hidden.0.rawValue)", to: phases)
            record("b04-after-hide-frames:\(hidden.1)", to: phases)
            record("b04-cycle-attempts:\(attempt)", to: phases)
            primaryRecorded = true
            let measurable = [answered.0, undone.0, hidden.0].allSatisfy { $0 != .notMeasurable }
            if measurable { break }
        }

        // 3. A late image with the reader stopped: the slot's geometry is frozen at publication, so nothing moves
        // when pixels arrive. Measured on the same card, made visible again first — and never read as a pass when
        // it could not be measured (architect, 2026-10-11).
        var idleAttempt = 0
        while idleAttempt < 2 {
            idleAttempt += 1
            // The measurement is only clean with the card **on screen**: a window that was trimmed above the
            // reader changes what the viewport shows, and a capture taken off-screen measures that trim, not the
            // reader. So the card is brought into the viewport first, and the capture is taken there
            // (architect, 2026-10-11).
            if !onScreenCard(app, anchorID) {
                bringIntoView(app, card: anchorID)
            }
            guard onScreenCard(app, anchorID), let beforeIdle = frame(app, ofCard: anchorID) else {
                record("b04-idle-stable:not-measurable", to: phases)
                record("b04-idle-frames:\(unmeasurableReason(app, card: anchorID))", to: phases)
                break
            }
            Thread.sleep(forTimeInterval: 12)
            let idle = stability(app, card: anchorID, from: beforeIdle)
            if idleAttempt > 1 {
                record("b04-idle-first:\(idle.0.rawValue)", to: phases)
            }
            record("b04-idle-stable:\(idle.0.rawValue)", to: phases)
            record("b04-idle-frames:\(idle.1)", to: phases)
            record("b04-idle-attempts:\(idleAttempt)", to: phases)
            if idle.0 != .notMeasurable { break }
            if !bringIntoView(app, card: anchorID) { break }
        }

        // 4. Rotation and a system change the reader did not ask for: the same reader stays on the same story.
        // Rotation is measured the way this project already proved it (T12): the app publishes its own viewport
        // counters, and a rotation is not an update the reader asked for, so those counters may not change.
        // Card identity on screen is not the measure here — a re-layout legitimately changes what fits.
        let counters = app.staticTexts["native-viewport-delivery"]
        let countersBefore = counters.exists ? counters.label : nil
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 3)
        let countersAfter = counters.exists ? counters.label : nil
        record("b04-rotation-holds:\(countersBefore != nil && countersBefore == countersAfter)", to: phases)
        record("b04-rotation-counters:\(countersBefore ?? "none")->\(countersAfter ?? "none")", to: phases)
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 3)

        // 5. Background and return: work happens while the app is away, and the reading position survives it.
        // The reader's place survives leaving and returning. Measured on the **same card**: "the topmost card"
        // changes identity when the viewport's top edge lands on a boundary, which says nothing about the reader
        // (architect, 2026-10-11). The identity fact is kept beside it, informational.
        let backgroundCard = presentedCard(app)
        let beforeBackground = backgroundCard?.identifier
        let beforeBackgroundFrame = backgroundCard?.frame
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 5)
        app.activate()
        Thread.sleep(forTimeInterval: 3)
        record("b04-background-same-topmost:"
            + "\(beforeBackground != nil && presentedCard(app)?.identifier == beforeBackground)", to: phases)
        if let beforeBackgroundFrame, let beforeBackground {
            let after = stability(app, card: beforeBackground, from: beforeBackgroundFrame)
            record("b04-background-stable:\(after.0.rawValue)", to: phases)
            record("b04-background-frames:\(after.1)", to: phases)
        } else {
            record("b04-background-stable:not-measurable", to: phases)
            record("b04-background-frames:no-anchor-before-the-background", to: phases)
        }

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "b04-sacred-feed"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The card containers now on screen, in reading order: their identity is what "nothing was reordered" means.
    private func presentedIdentifiers(_ app: XCUIApplication) -> [String] {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@", "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"))
            .allElementsBoundByIndex
            .filter { $0.frame.height > 40 && $0.frame.minY >= (app.scrollViews.firstMatch.frame.minY - 1) }
            .sorted { $0.frame.minY < $1.frame.minY }
            .map(\.identifier)
            .prefix(3)
            .map { $0 }
    }

    /// Whether a card's measured frame survived a change the reader did not ask for.
    private func stable(_ before: CGRect?, _ after: CGRect?) -> Bool {
        guard let before, let after else { return false }
        return abs(before.minY - after.minY) < 1 && abs(before.height - after.height) < 1
    }

    /// B02 — relevance, variety and editorial identity over the first published cards. The driver only produces
    /// them; the oracle compares the sequence against the corpus's own labels.
    func testB02RelevanceAndVariety() throws {
        let (corpus, namespace, phases, runProfile) = try runIdentity()
        let app = launch(namespace)
        try walkTheFirstRunJourney(app, profile: try profile(runProfile, in: corpus), name: runProfile,
            phases: phases)
        let feed = app.scrollViews.firstMatch
        // Enough real scrolling for the runtime to publish well past the first two hundred cards.
        let deadline = Date().addingTimeInterval(240)
        while Date() < deadline {
            feed.swipeUp()
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "b02-after-consumption"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// B05 — A → B → A, local memory and the offline return: the reader's place, the story they saved and the
    /// stories already published all survive leaving, switching context, being reopened with the network cut.
    /// The driver **acts and records**; the oracle judges the record and the app's own database.
    func testB05ContextsReopenOfflineAndSaved() throws {
        let (corpus, namespace, phases, runProfile) = try runIdentity()
        let app = launch(namespace)
        let profileData = try profile(runProfile, in: corpus)
        try walkTheFirstRunJourney(app, profile: profileData, name: runProfile, phases: phases)
        let feed = app.scrollViews.firstMatch

        // B05's declared input is **two real reading contexts**. They are established by the reader's own act —
        // the product's Sources sheet, one **profile-compatible** catalogue source chosen from the frozen corpus —
        // before A is named, so A's publication and anchor are measured on the final main feed. The benchmark's
        // reader otherwise starts with no selected source (source_keys empty), and a main-only menu is that honest
        // state, not a product defect.
        let contextsPrepared = prepareB05Contexts(app, phases: phases, profile: profileData,
            runProfile: runProfile)
        record("b05-precondition:\(contextsPrepared ? "true" : "false")", to: phases)
        _ = waitUntil(120) { presentedCard(app) != nil }

        // A card the reader saves, and the anchor they are reading. The card is **named first**, and its own
        // control is then asked for **inside it**: `card.bookmark` is the same identifier on every card, so a
        // `firstMatch` over the drawn list cannot tell one card from another (see the note on `presentedCard`), and
        // it resolves to whatever the surface instantiated first — the reader's card while the admitted list was a
        // band around them, and the Edition's first card once the head is kept. Measured 2026-10-14: the `firstMatch`
        // sat 793 pt above the viewport, XCTest scrolled the feed to reach it, and the run saved the head card
        // (`126C1A86`, index 0) instead of the card the driver was following (`BF12004E`, index 13), while the
        // app's own position checkpoints recorded where that scroll left it (index 0 at the tap, index 8 just
        // after) — the instrument moved the reader, not the product.
        guard let anchorBefore = presentedCard(app)?.identifier else {
            return XCTFail("the feed presented no card to save")
        }
        let bookmark = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", anchorBefore))
            .firstMatch.buttons.matching(identifier: "card.bookmark").firstMatch
        guard bookmark.waitForExistence(timeout: 30) else {
            return XCTFail("the card the reader is on offers no save control")
        }
        bookmark.tap()
        Thread.sleep(forTimeInterval: 1.5)
        record("b05-saved:\(bookmark.value as? String == "bookmarked")", to: phases)
        record("b05-anchor-before:\(anchorBefore)", to: phases)

        // A → B → A: another reading context and back, through the product's own context control. The original
        // branch walked `more-menu` → `Salvos`, a label the product has never had (the frozen log shows ten seconds
        // of failed existence checks), so the test never left A and `b05-return-preserves-anchor` was vacuously
        // true. This is the actual control (`FeedMineApp.contextChip`): its menu states the main context and one
        // entry per source the reader selected. A missing control, or a menu with no second context, is recorded
        // as a **failure** — never skipped.
        // The chip is a SwiftUI `Menu`: XCUITest sees a pop-up button, so it is resolved by identifier across
        // types (the same rule the other context tests state). The **identity** of the context is
        // `reader-context-label` — absent while the main context is shown, present and naming the source when the
        // reader is on one. The chip's own label also carries the work short-description ("Feedmine, · …"), so it
        // is evidence, not the witness.
        let contextChip = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "reader-contexts")).firstMatch
        let contextLabel = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "reader-context-label")).firstMatch
        let contextA = contextChip.exists ? contextChip.label : ""
        record("b05-context-a:\(contextA)", to: phases)
        record("b05-context-a-is-main:\(!contextLabel.exists)", to: phases)
        // What the control offered. `not-offered` is the failure the clause must state when the product has no
        // second context for this reader; `false` is a second context offered but not reached.
        var contextOutcome = "not-offered"
        var reachedB = false
        var returned = false
        var bName = ""
        if contextChip.waitForExistence(timeout: 15), waitUntil(10, { contextChip.isHittable }) {
            contextChip.tap()
            // The menu is open when its own entries exist. A SwiftUI `Menu` exposes items as buttons with **no
            // identifier** (every control of this surface carries one), and the main-context copy is a localized
            // string — `Button("Principal")` renders as "Main" in an English UI — so the entry is identified by
            // the menu's declared order, never by text. Measured failure, run 20261023T213928Z: the tree held
            // `Button, label: 'Main'` while the driver waited for an identifier "Principal", so the menu looked
            // absent and both profiles recorded not-offered.
            if waitUntil(10, { !contextMenuItems(app).isEmpty }) {
                let items = contextMenuItems(app)
                record("b05-context-menu-items:\(items.count)", to: phases)
                record("b05-context-main-label:\(items.first?.label ?? "none")", to: phases)
                // The product declares the main context first and one entry per selected source after it.
                let sources = Array(items.dropFirst())
                record("b05-context-source-entries:\(sources.count)", to: phases)
                if let source = sources.first {
                    contextOutcome = "false"
                    bName = source.label
                    source.tap()
                    // "Changed" is the product's own context label naming the source — the witness the context
                    // surface offers the reader — not a count of taps.
                    reachedB = waitUntil(30) {
                        contextChip.exists && contextLabel.exists
                            && contextLabel.label.range(of: bName, options: .caseInsensitive) != nil
                    }
                    if reachedB {
                        record("b05-context-b:\(bName)", to: phases)
                        record("b05-context-b-label:\(contextLabel.label)", to: phases)
                        // Identity is the criterion; the card is the bounded proof that B is a real reading
                        // context for this profile too, not merely a label the driver selected.
                        let bCard = waitUntil(120) { presentedCard(app) != nil }
                        record("b05-context-b-card:\(bCard)", to: phases)
                        // Back to A: the menu's first entry is the main context. The source context publishes its
                        // own feed and may draw its preparation surface first, where the reader's header is not
                        // mounted; the chip's return is awaited (bounded) rather than tapped blind.
                        if waitUntil(60, { contextChip.exists && contextChip.isHittable }) {
                            contextChip.tap()
                            if waitUntil(10, { !contextMenuItems(app).isEmpty }),
                                let back = contextMenuItems(app).first {
                                back.tap()
                                returned = waitUntil(30) { !contextLabel.exists }
                            }
                        }
                        record("b05-context-return-label:\(contextLabel.exists ? contextLabel.label : "none")",
                            to: phases)
                    }
                }
            }
        }
        record("b05-context-b-reached:\(reachedB ? "true" : contextOutcome)", to: phases)
        record("b05-context-return-reached:\(returned)", to: phases)
        // The returned-to-A anchor is only measurable after B was really reached: a comparison taken without
        // leaving A says nothing and must not read as a pass.
        let walkedTheContexts = reachedB && returned
        if walkedTheContexts {
            // The main context republishes from local state. Give the reading surface its own bounded moment
            // before reading the anchor, and never substitute another card.
            _ = waitUntil(30) { presentedCard(app) != nil }
            let anchorAfterReturn = presentedCard(app)?.identifier
            record("b05-return-preserves-anchor:\(anchorAfterReturn != nil && anchorAfterReturn == anchorBefore)",
                to: phases)
        } else {
            record("b05-return-preserves-anchor:not-measured", to: phases)
        }

        // Suspend and reopen: the same reader, the same place, the same saved story.
        //
        // Measurement correction (2026-10-11): this reopen used to inherit `FEEDMINE_SKIP_ONBOARDING=0` from the
        // run's first launch — deliberate there, because B01's journey *starts* at the gate — so the gate was
        // presented again over a feed that had already been restored, and `b05-reopen-keeps-saved` ended up
        // consulting the feed's control underneath a `fullScreenCover`. Instrumentation proved the saved state was
        // present and applied to the restored card; the clause was timing-dependent, not the product. The reopen
        // now says what it is — a run testing something else — exactly as the app's own comment invites, and as the
        // offline relaunch below already did. The persistence requirements are unchanged.
        // The reopen clause is judged on the named card; the visible UUIDs at both sides of the kill are recorded
        // beside it, so a false read can be compared with the card the reader was actually on rather than waived.
        record("b05-reopen-visible-before:\(presentedIdentifiers(app).joined(separator: ","))", to: phases)
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.terminate()
        Thread.sleep(forTimeInterval: 2)
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 60), "the feed returns after a reopen")
        // The reader's surface is identified before its control is consulted: a gate that covers the feed must not
        // be mistaken for the feed's own absence of state. The absence is awaited as one — `waitForExistence`
        // returns true while the element still exists and cannot express "gone".
        let gateGone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["welcome-headline"])
        XCTAssertEqual(XCTWaiter().wait(for: [gateGone], timeout: 30), .completed,
            "the reader is on the feed, not behind the first-run gate")
        Thread.sleep(forTimeInterval: 4)
        let anchorAfterReopen = presentedCard(app)?.identifier
        record("b05-reopen-preserves-anchor:\(anchorAfterReopen != nil && anchorAfterReopen == anchorBefore)",
            to: phases)
        record("b05-reopen-visible-after:\(presentedIdentifiers(app).joined(separator: ","))", to: phases)
        record("b05-reopen-keeps-saved:\(app.buttons.matching(identifier: "card.bookmark").allElementsBoundByIndex.contains { $0.value as? String == "bookmarked" })",
            to: phases)

        // Offline: the network is cut for a real relaunch, and the stories already published must still be
        // readable. No mock connector — the app's own transport fault configuration.
        app.terminate()
        Thread.sleep(forTimeInterval: 2)
        let offline = XCUIApplication()
        offline.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = namespace
        offline.launchEnvironment["FEEDMINE_ONBOARDING"] = "1"
        offline.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        offline.launchEnvironment["FEEDMINE_BLOCK_RSS_NETWORK"] = "1"
        offline.launch()
        let offlineFeed = offline.scrollViews.firstMatch
        record("b05-offline-shows-local:\(offlineFeed.waitForExistence(timeout: 60))", to: phases)
        if offlineFeed.exists {
            let cards = offline.buttons.matching(identifier: "card.bookmark")
            record("b05-offline-cards:\(cards.count > 0)", to: phases)
            // The reader can still read: the first card opens.
            let offlineShot = XCTAttachment(screenshot: offline.screenshot())
            offlineShot.name = "b05-offline"
            offlineShot.lifetime = .keepAlways
            add(offlineShot)
        }
        // The rest of the protocol still ran and is recorded above; the failure is stated last so a run that
        // could not leave A is not mistaken for one that did. The oracle reads the same facts.
        if !walkedTheContexts {
            XCTFail("B05 did not walk A → B → A: the product's context control offered no second context "
                + "(b05-context-entries states what the menu held; A was '\(contextA)')")
        }
        _ = feed
    }

    /// B03 — a real runway: **thirty minutes** of effective advances, one card per second, with bursts of three
    /// per second for twenty seconds every five minutes, through native gestures. The trace is the benchmark's;
    /// a run that cannot hold it is NOT_RUN, never a shorter trace.
    func testB03ThirtyMinuteRunway() throws {
        let (corpus, namespace, phases, runProfile) = try runIdentity()
        guard environment["FEEDMINE_BENCH_FULL_TRACE"] == "1" else {
            throw XCTSkip("the thirty-minute trace runs through bench/run.sh --gate B03")
        }
        let app = launch(namespace)
        try walkTheFirstRunJourney(app, profile: try profile(runProfile, in: corpus), name: runProfile,
            phases: phases)
        let feed = app.scrollViews.firstMatch

        let started = Date()
        var burstStarted: Date? = nil
        var lastBurstEnd = started
        while Date().timeIntervalSince(started) < 1_800 {
            let elapsed = Date().timeIntervalSince(started)
            let inBurst = elapsed.truncatingRemainder(dividingBy: 300) < 20
            // One advance per second, three per second inside a burst: the benchmark's own replay shape.
            let advances = inBurst ? 3 : 1
            for _ in 0..<advances { feed.swipeUp() }
            if inBurst, burstStarted == nil { burstStarted = Date() }
            if !inBurst, let began = burstStarted {
                burstStarted = nil
                lastBurstEnd = began
            }
            // The rest of the second: a replay at 1/s must not be a burst.
            let spent = Date().timeIntervalSince(started) - elapsed
            if spent < 1 { Thread.sleep(forTimeInterval: 1 - spent) }
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "b03-end-of-trace"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertGreaterThan(lastBurstEnd, started, "the trace really ran")
    }
}
