// File: ReaderContentSeedJourneyUITests.swift
// Module: FeedMineUITests
// Owns: the opt-in journey that walks *real* published content with a registered, stratified seed. It is not part
//       of the smoke profile: the product's smoke must not depend on the network. When it runs, it states the seed,
//       the picked identifiers and their fingerprint, so a failure is replayable with FEEDMINE_CONTENT_SEED.
//
// Opt in with FEEDMINE_REAL_CONTENT_SEEDED=1. Replay a red run with the printed seed.

import XCTest

final class ReaderContentSeedJourneyUITests: XCTestCase {
    @MainActor
    func testStratifiedPublishedCardOpensItsOwnHeadline() throws {
        guard ProcessInfo.processInfo.environment["FEEDMINE_REAL_CONTENT_SEEDED"] == "1" else {
            throw XCTSkip("Opt in with FEEDMINE_REAL_CONTENT_SEEDED=1; this journey uses the public catalogue and network")
        }
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_ONBOARDING"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["welcome-headline"].waitForExistence(timeout: 60))
        app.buttons["welcome-shape"].tap()
        XCTAssertTrue(app.staticTexts["composer-subtitle"].waitForExistence(timeout: 30))
        let places = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'composer-region-'"))
        if places.firstMatch.waitForExistence(timeout: 30) {
            let brazil = places.matching(NSPredicate(format: "label CONTAINS[c] 'Brazil'")).firstMatch
            (brazil.exists ? brazil : places.firstMatch).tap()
        }
        app.buttons["composer-open-feed"].tap()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 180), "the first run reaches the feed")

        let cards = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier MATCHES %@",
                "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"))
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline && cards.count < 2 { Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertGreaterThanOrEqual(cards.count, 2, "the published edition presents at least two cards")

        // Strata: the visible window's own top, middle and bottom. The card's title is the public identifier the
        // sample records; the element identifier (the occurrence UUID) is what the test taps.
        var strata: [String: [String]] = [:]
        var titles: [String: String] = [:]
        let visible = cards.allElementsBoundByIndex.filter { $0.exists && $0.frame.height > 40 }
        let ordered = visible.sorted { $0.frame.minY < $1.frame.minY }
        for (index, card) in ordered.enumerated() {
            let stratum: String
            if index < ordered.count / 3 { stratum = "top" }
            else if index < 2 * ordered.count / 3 { stratum = "middle" }
            else { stratum = "bottom" }
            let title = card.label.isEmpty ? card.identifier : card.label
            strata[stratum, default: []].append(card.identifier)
            titles[card.identifier] = title
        }
        let seed = SeededStratifiedSample.seedFromEnvironment()
        let sample = SeededStratifiedSample(seed: seed, strata: strata)
        XCTAssertFalse(sample.picks.isEmpty, "the visible window yields at least one stratified pick")
        print(sample.record)
        let proof = XCTAttachment(string: sample.record)
        proof.name = "seeded-content-sample"
        proof.lifetime = .keepAlways
        add(proof)

        guard let pick = sample.picks.first else { return }
        let chosen = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@", pick.id)).firstMatch
        XCTAssertTrue(chosen.waitForExistence(timeout: 20), "the sampled card is still on screen")
        let title = titles[pick.id] ?? chosen.label
        chosen.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let headline = app.staticTexts["reading.headline"]
        XCTAssertTrue(headline.waitForExistence(timeout: 60), "the sampled card opens the reader")
        XCTAssertFalse(headline.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(headline.label.contains(title) || title.contains(headline.label),
            "the reader states the sampled card's own headline; card=\(title) reader=\(headline.label)")
    }
}
