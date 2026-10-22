// File: ReleaseAudioJourneyUITests.swift
// Module: FeedMineUITests
// Owns: the Release proof of the OUVIR journey — a real audio card from the public catalogue, played, paused and
//       resumed in the optimized app. No DEBUG fixture, namespace or instrument: the card comes from the same
//       discovery path a reader uses, and the network is the product's own.
//
// Opt-in because it reaches public content:
//   xcrun simctl spawn <udid> launchctl setenv FEEDMINE_LIVE_AUDIO 1
//   xcodebuild test-without-building -scheme FeedMineSurfaces -configuration Release \
//     -only-testing:FeedMineUITests/ReleaseAudioJourneyUITests
//   xcrun simctl spawn <udid> launchctl unsetenv FEEDMINE_LIVE_AUDIO
//
// When the broad Release feed carries no audio card in the run, the test skips with that concrete observation:
// audio readiness then depends on public content, and no playback claim is made.

import XCTest

final class ReleaseAudioJourneyUITests: XCTestCase {
    private static var cardIdentifier: NSPredicate {
        NSPredicate(format: "identifier MATCHES %@",
            "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")
    }

    private func waitForLabel(_ element: XCUIElement, _ label: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.label == label { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return element.label == label
    }

    @MainActor
    func testReleaseAudioCardPlaysPausesAndResumesWithItsOwnContext() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FEEDMINE_LIVE_AUDIO"] == "1",
            "opt-in: FEEDMINE_LIVE_AUDIO=1 reaches the public catalogue and network")

        let app = XCUIApplication()
        app.launch()
        if app.staticTexts["welcome-headline"].waitForExistence(timeout: 90) {
            let broad = app.buttons["welcome-broad"]
            XCTAssertTrue(broad.waitForExistence(timeout: 20), "the Release gate offers the broad start")
            broad.tap()
        }
        XCTAssertTrue(app.buttons["more-menu"].waitForExistence(timeout: 180),
            "the Release app reaches its reader chrome")
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 180),
            "the Release association is up")

        // A card draws `card.play` only when it is audio and carries an openMedia action: the control is the
        // product's own statement that this occurrence can be heard.
        let play = app.buttons["card.play"].firstMatch
        guard SurfaceTest.scrollIntoView(play, in: app, timeout: 180) else {
            throw XCTSkip("the broad Release feed produced no audio card in this run; "
                + "audio readiness depends on public content, and no playback is claimed")
        }
        let playFrame = play.frame
        let card = app.descendants(matching: .any).matching(Self.cardIdentifier)
            .allElementsBoundByIndex.first { $0.frame.contains(playFrame) }
        let cardTitle = card?.staticTexts.allElementsBoundByIndex.map(\.label).first { !$0.isEmpty } ?? ""

        play.tap()
        let bar = app.otherElements["mini-player"]
        XCTAssertTrue(bar.waitForExistence(timeout: 60),
            "the play control reaches the player instead of looking dead")
        let title = app.staticTexts["mini-player-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        XCTAssertFalse(title.label.isEmpty, "the bar names the occurrence that plays")
        if !cardTitle.isEmpty {
            XCTAssertEqual(title.label, cardTitle, "the bar names the same occurrence the card showed")
        }

        let toggle = app.buttons["mini-player-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 20))
        let error = app.staticTexts["mini-player-error"]

        // Public audio either proves playback (the product's pause intent appears) or states why it could not
        // play in words. Both are observable outcomes; silence is the failure this journey exists to catch.
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline, toggle.label != "Pausar", !error.exists {
            Thread.sleep(forTimeInterval: 0.2)
        }
        if error.exists {
            XCTAssertFalse(error.label.isEmpty, "a refusal states its reason in words")
            XCTAssertNotEqual(toggle.label, "Pausar")
            let proof = XCTAttachment(string: "release-audio card=\(card?.identifier ?? "unavailable") "
                + "outcome=refused reason=\(error.label)")
            proof.name = "release-audio-journey"
            proof.lifetime = .keepAlways
            add(proof)
            return
        }
        XCTAssertEqual(toggle.label, "Pausar", "the public audio card is really playing")

        toggle.tap()
        XCTAssertTrue(waitForLabel(toggle, "Tocar", timeout: 20), "the reader pauses the episode")
        if !cardTitle.isEmpty {
            XCTAssertEqual(title.label, cardTitle, "pausing does not change the occurrence")
        }
        toggle.tap()
        XCTAssertTrue(waitForLabel(toggle, "Pausar", timeout: 20), "the reader resumes the same episode")
        if !cardTitle.isEmpty {
            XCTAssertEqual(title.label, cardTitle, "resuming does not change the occurrence")
        }

        let proof = XCTAttachment(string: "release-audio card=\(card?.identifier ?? "unavailable") "
            + "played=true paused=true resumed=true title=\(title.label)")
        proof.name = "release-audio-journey"
        proof.lifetime = .keepAlways
        add(proof)
    }
}
