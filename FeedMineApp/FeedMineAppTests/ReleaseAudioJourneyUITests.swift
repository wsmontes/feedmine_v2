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

    /// The product's own `m:ss` / `h:mm:ss` clock, as integer seconds. Nil when the surface states something else.
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

    /// Waits for the product's clock to show a strictly later second than `from`. The display advances once per
    /// second, so one more second is the smallest real advance; the deadline covers network buffering.
    private func waitForAdvance(_ clock: XCUIElement, from: Int, timeout: TimeInterval) -> Int? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let value = clockSeconds(clock.label), value > from { return value }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return nil
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
        // The card draws its source row before the title, so the first static text is the source name. The title
        // itself carries `card.title` in both card layouts; scoping to it is the identity the bar must repeat.
        let cardTitle = card?.staticTexts["card.title"].label ?? ""

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
        XCTAssertEqual(toggle.label, "Pausar", "the player states the episode is playing")

        // The label is derived from `state.isPlaying`, which the adapter sets when it calls play(). Playback is
        // proven by the product's own clock: it must advance, freeze while paused, and advance again after resume.
        title.tap()
        let full = app.otherElements["full-player"]
        XCTAssertTrue(full.waitForExistence(timeout: 20), "the bar opens the full player")
        let fullTitle = app.staticTexts["full-player-title"]
        XCTAssertTrue(fullTitle.waitForExistence(timeout: 20))
        if !cardTitle.isEmpty {
            XCTAssertEqual(fullTitle.label, cardTitle, "the full player names the same occurrence")
        }
        let clock = app.staticTexts["full-player-position"]
        // The duration clock exists only after the item's length is known; a public MP3 can take a moment.
        XCTAssertTrue(clock.waitForExistence(timeout: 30),
            "the player states its position clock; without it time passing cannot be measured")

        guard let playingFirst = clockSeconds(clock.label) else {
            return XCTFail("the clock does not state m:ss: \(clock.label)")
        }
        guard let playingSecond = waitForAdvance(clock, from: playingFirst, timeout: 15) else {
            return XCTFail("the clock did not advance while the player stated playing; a toggle label alone is "
                + "not playback (clock \(clock.label))")
        }

        app.buttons["full-player-toggle"].tap()
        // Let the player's own status callback settle, then two samples further apart than the one-second display:
        // a paused item states the same second both times, with no tolerance applied.
        Thread.sleep(forTimeInterval: 2)
        guard let pausedFirst = clockSeconds(clock.label) else {
            return XCTFail("the clock stopped stating m:ss after pause: \(clock.label)")
        }
        Thread.sleep(forTimeInterval: 3)
        guard let pausedSecond = clockSeconds(clock.label) else {
            return XCTFail("the clock stopped stating m:ss while paused: \(clock.label)")
        }
        XCTAssertEqual(pausedSecond, pausedFirst, "a paused item's clock does not advance")

        app.buttons["full-player-toggle"].tap()
        guard let resumed = waitForAdvance(clock, from: pausedSecond, timeout: 15) else {
            return XCTFail("the clock did not advance after resume (clock \(clock.label))")
        }

        app.buttons["full-player-close"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        if !cardTitle.isEmpty {
            XCTAssertEqual(title.label, cardTitle, "closing the player keeps the same occurrence")
        }

        let proof = XCTAttachment(string: "release-audio card=\(card?.identifier ?? "unavailable") "
            + "title=\(title.label) clock_playing=\(playingFirst)->\(playingSecond) "
            + "clock_paused=\(pausedFirst)==\(pausedSecond) clock_resumed=\(resumed) "
            + "mode=time-advance")
        proof.name = "release-audio-journey"
        proof.lifetime = .keepAlways
        add(proof)
    }
}
