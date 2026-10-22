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

        // The actionable card surface is `card.open`; its label carries the title, which is the public
        // identifier this sample records. Strata are the visible window's top, middle and bottom.
        let opens = app.buttons.matching(identifier: "card.open")
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline && opens.count < 2 { Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertGreaterThanOrEqual(opens.count, 2, "the published edition presents at least two cards")

        var strata: [String: [String]] = [:]
        let visible = opens.allElementsBoundByIndex.filter { $0.exists && $0.frame.height > 20 }
        let ordered = visible.sorted { $0.frame.minY < $1.frame.minY }
        for (index, card) in ordered.enumerated() {
            let stratum: String
            if index < ordered.count / 3 { stratum = "top" }
            else if index < 2 * ordered.count / 3 { stratum = "middle" }
            else { stratum = "bottom" }
            strata[stratum, default: []].append(card.label)
        }
        let seed = SeededStratifiedSample.seedFromEnvironment()
        let sample = SeededStratifiedSample(seed: seed, strata: strata)
        XCTAssertFalse(sample.picks.isEmpty, "the visible window yields at least one stratified pick")
        print(sample.record)
        let proof = XCTAttachment(string: sample.record)
        proof.name = "seeded-content-sample"
        proof.lifetime = .keepAlways
        add(proof)

        let rank = ["top": 0, "middle": 1, "bottom": 2]
        let sampleOrder = sample.picks.sorted { (rank[$0.stratum] ?? 9) < (rank[$1.stratum] ?? 9) }
        guard let pick = sampleOrder.first else { return }
        let title = pick.id
        let chosen = app.buttons.matching(identifier: "card.open")
            .matching(NSPredicate(format: "label == %@", title)).firstMatch
        XCTAssertTrue(chosen.waitForExistence(timeout: 20), "the sampled card is still on screen")
        if !chosen.isHittable { _ = SurfaceTest.scrollIntoView(chosen, in: app, timeout: 20) }
        chosen.tap()

        let headline = app.staticTexts["reading.headline"]
        let address = app.buttons["URL"].firstMatch
        let opened = headline.waitForExistence(timeout: 60) || address.waitForExistence(timeout: 30)
        XCTAssertTrue(opened, "the sampled card opens the reader; card=\(title)")
        if headline.exists {
            XCTAssertFalse(headline.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertTrue(headline.label.contains(title) || title.contains(headline.label),
                "the reader states the sampled card's own headline; card=\(title) reader=\(headline.label)")
        } else {
            XCTAssertFalse((address.label).isEmpty, "the site reader states the card's address")
        }
    }
}
