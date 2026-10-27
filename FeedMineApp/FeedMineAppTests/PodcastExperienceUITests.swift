import XCTest

/// **V1's podcast surface, proved where the reader touches it.**
///
/// Two hermetic runs, because one fixture shape cannot be both a published podcast card with an admitted image
/// and a real playable clock:
///
/// 1. `FEEDMINE_FIXTURE_MEDIA=audio-image` — the local transport's podcast cards declare both a card visual and a
///    podcast enclosure. The enclosure is `fixture.invalid`, so playback is refused without a network; the bar
///    still names the **published occurrence**, draws the image the pipeline admitted, states the program, and
///    keeps the item reachable. The full player's menu is the card's real save action: saving from the player
///    must change the card's own bookmark state, which is what proves the button is not decoration.
/// 2. `FEEDMINE_MEDIA_SIMULATION=1` — a real silent episode through the real adapter. The elapsed clock advances,
///    pause freezes it, a scrub commits on release (the position lands at the release point, not at every drag
///    sample), ±15 s is the real callback, and stop removes the bar.
///
/// The artwork assertions name the two states separately: `…-artwork-image` only exists when a decoded bitmap is
/// in the model, and `…-artwork-fallback` states the absence in words (V1's waveform). A run that shows the
/// fallback is not failing the image check; it is proving the product does not invent a cover.
@MainActor
final class PodcastExperienceUITests: XCTestCase {
    private static var cardIdentifier: NSPredicate {
        NSPredicate(format: "identifier MATCHES %@",
            "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")
    }

    private func launched(simulated: Bool) -> XCUIApplication {
        var extra: [String: String] = ["FEEDMINE_FIXTURE_ITEMS": "6"]
        if simulated {
            extra["FEEDMINE_MEDIA_SIMULATION"] = "1"
        } else {
            extra["FEEDMINE_FIXTURE_MEDIA"] = "audio-image"
        }
        // The player's own vocabulary is localized (`Pausar`/`Tocar`), and this device may run the app in English.
        // The journey states the locale it asserts instead of depending on the host's, exactly as the other journeys
        // do — the shared helper's defaults are left alone.
        return SurfaceTest.launchFixture(extra,
            arguments: ["-AppleLanguages", "(pt_BR)", "-AppleLocale", "pt_BR"])
    }

    /// The card that owns the play control, found by frame: descendants of a SwiftUI card are not reliably
    /// delimited by the tree, and the frame is the reader's own geometry.
    private func playableCard(_ app: XCUIApplication, timeout: TimeInterval = 60) -> (card: XCUIElement, play: XCUIElement)? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let cards = app.descendants(matching: .any).matching(Self.cardIdentifier)
            for index in 0..<min(cards.count, 8) {
                let card = cards.element(boundBy: index)
                guard card.exists else { continue }
                let play = card.buttons["card.play"]
                if play.exists, play.isHittable, card.frame.contains(play.frame) {
                    return (card, play)
                }
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return nil
    }

    /// Taps one entry of the player's `Menu`. SwiftUI exposes menu content in its own hierarchy on some iOS
    /// versions and as plain buttons on others, so the identifier is tried first and the repo's proven
    /// label-based pattern (`app.menus.buttons[…]`, then `app.buttons[…]`) is the fallback.
    @discardableResult
    private func tapMenuEntry(_ app: XCUIApplication, identifier: String, label: String,
        timeout: TimeInterval = 10) -> Bool {
        let byIdentifier = SurfaceTest.element(app, identifier)
        if byIdentifier.waitForExistence(timeout: timeout) { byIdentifier.tap(); return true }
        let inMenu = app.menus.buttons[label]
        if inMenu.waitForExistence(timeout: 3) { inMenu.tap(); return true }
        let plain = app.buttons[label]
        if plain.waitForExistence(timeout: 3) { plain.tap(); return true }
        return false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// `m:ss` or `h:mm:ss`, the player's own clock. A string that changes while keeping the same second is not
    /// evidence of playback; this is why the assertions compare whole seconds.
    private static func seconds(_ clock: String) -> Int? {
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 || parts.count == 3 else { return nil }
        return parts.count == 2 ? parts[0] * 60 + parts[1] : parts[0] * 3600 + parts[1] * 60 + parts[2]
    }

    private func waitForPosition(_ element: XCUIElement, within range: ClosedRange<Int>,
        timeout: TimeInterval = 20) -> Int? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let value = Self.seconds(element.label), range.contains(value) { return value }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return Self.seconds(element.label).flatMap { range.contains($0) ? $0 : nil }
    }

    /// A point on the scrub's own track for a fraction of the item, as a normalized offset of the control's frame.
    ///
    /// A `UISlider` begins tracking **on its thumb**, and the thumb's centre does not travel the whole frame: it
    /// moves along the track half a thumb inside each end — `centre = inset + fraction × (width − 2 × inset)`.
    /// The default thumb is as tall as the control's intrinsic 31 pt (the height the player frames the scrub to),
    /// so the inset is its half. A press at a constant fraction of the frame (0.97) missed a thumb resting at 0.23:
    /// no track began, so no release reached the product and the position stayed at the player's own 0:07
    /// (measured 2026-10-26). Starting from the position the player reports is what makes the press land.
    private static func scrubPoint(_ scrub: XCUIElement, at fraction: Double) -> XCUICoordinate {
        let inset: CGFloat = 15.5
        let width = max(1, scrub.frame.width)
        let track = max(1, width - 2 * inset)
        let clamped = CGFloat(min(max(fraction, 0), 1))
        return scrub.coordinate(withNormalizedOffset: CGVector(dx: (inset + clamped * track) / width, dy: 0.5))
    }

    // MARK: - Published podcast card: art, identity, menu, stop

    func testTheMiniPlayerShowsThePublishedCoverAndProgramAndTheFullPlayerRunsARealSave() throws {
        let app = launched(simulated: false)
        defer { app.terminate() }
        guard let found = playableCard(app) else {
            // Say what the launch actually reached: a feed that never published and a feed published under a cover
            // look identical from the card query alone, and the record separates them (`kind=`, `cards=`, `reason=`).
            let record = app.descendants(matching: .any)["feed-launch-record"].label
            attach(app, "podcast-no-playable-card")
            return XCTFail("no published podcast card with card.play: this journey requires the "
                + "FEEDMINE_FIXTURE_MEDIA=audio-image fixture shape; launch record=\(record)")
        }
        found.play.tap()

        let bar = app.otherElements["mini-player"]
        XCTAssertTrue(bar.waitForExistence(timeout: 30),
            "the refusal of the unplayable enclosure is stated by the bar, not by silence")
        XCTAssertEqual(bar.frame.height, 56, accuracy: 1,
            "V1's constant bar height, whatever the state")
        // The identity is the row that reserves those 56 pt, not the material that bleeds below it: the controls it
        // owns stay inside it and keep their target. A bar whose element grew to include the safe area would keep
        // this row true while claiming a height the feed never reserved.
        let playToggle = app.buttons["mini-player-toggle"]
        XCTAssertTrue(playToggle.waitForExistence(timeout: 10), "the bar owns the play control")
        XCTAssertEqual(playToggle.frame.height, 44, accuracy: 1, "the play control keeps V1's 44 pt target")
        XCTAssertTrue(bar.frame.contains(playToggle.frame),
            "the bar's own row contains the controls it draws; measured bar=\(bar.frame) control=\(playToggle.frame)")

        // Artwork: the pixels the published card was admitted with, on a real card identity.
        let cover = SurfaceTest.element(app, "mini-player-artwork-image")
        XCTAssertTrue(cover.waitForExistence(timeout: 10),
            "the bar draws the cover the presentation admitted for this card")
        XCTAssertGreaterThan(cover.frame.width, 30, "the cover is V1's 40 pt thumbnail")

        let source = app.staticTexts["mini-player-source"]
        XCTAssertTrue(source.waitForExistence(timeout: 10), "the bar states the program, as V1 did")
        XCTAssertFalse(source.label.isEmpty, "an empty program is not a program")
        XCTAssertTrue(source.label.hasPrefix("BBC "),
            "the source is the frozen feed title of the tapped card; measured '\(source.label)'")
        XCTAssertTrue(app.staticTexts["mini-player-elapsed"].exists, "the bar states its elapsed clock")

        let error = app.staticTexts["mini-player-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10),
            "the enclosure does not resolve in this hermetic run; the reason belongs on the bar")
        attach(app, "podcast-bar-artwork-source")

        // The full player names the same occurrence and the same published pixels.
        bar.tap()
        let full = app.otherElements["full-player"]
        XCTAssertTrue(full.waitForExistence(timeout: 15))
        XCTAssertTrue(SurfaceTest.element(app, "full-player-artwork-image").waitForExistence(timeout: 10),
            "the full player draws the same admitted cover")
        XCTAssertEqual(app.staticTexts["full-player-source"].label, source.label,
            "the sheet and the bar name the same program")
        // A length the player never measured is not a badge: this refusal has no duration.
        XCTAssertFalse(SurfaceTest.element(app, "full-player-duration-badge").exists,
            "no player-known duration means no podcast length badge")

        // The menu is the card's own action, executed by the host. Choosing it closes the player and the host runs
        // the action on dismissal, so the destination (a bookmark, a source, a share panel) is in front of the feed
        // — the journey therefore waits for the player to go **by itself** instead of tapping close again, which
        // used to race a sheet that was already dismissing.
        let menu = SurfaceTest.element(app, "full-player-menu")
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "the player offers V1's episode actions")
        menu.tap()
        XCTAssertTrue(tapMenuEntry(app, identifier: "full-player-action-save", label: "Salvar artigo"),
            "saving the occurrence is offered from the player's own menu")
        XCTAssertTrue(SurfaceTest.waitForAbsence(full, timeout: 15),
            "the player closes itself once the reader chose an action from it")
        XCTAssertTrue(bar.waitForExistence(timeout: 15), "closing the sheet keeps the episode bar")
        let bookmark = found.card.buttons["card.bookmark"].firstMatch
        let bookmarked = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "bookmarked"), object: bookmark)
        XCTAssertEqual(XCTWaiter.wait(for: [bookmarked], timeout: 15), .completed,
            "the save the player performed is the card's real bookmark state; measured "
                + "value='\(String(describing: bookmark.value))'")

        // Stop is V1's close: the occurrence leaves the bar and the feed keeps its geometry.
        Thread.sleep(forTimeInterval: 2)
        let stop = app.buttons["mini-player-stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10), "V1's close is on the bar")
        stop.tap()
        XCTAssertTrue(SurfaceTest.waitForAbsence(bar, timeout: 15), "stopping removes the bar")
        XCTAssertTrue(app.scrollViews.firstMatch.exists, "the feed remains the reader's page")
        attach(app, "podcast-stopped")
    }

    // MARK: - Simulated real playback: clock, scrub commit, skip, stop

    func testTheFullPlayerClockScrubsOnReleaseAndSkipsWithRealCallbacks() throws {
        let app = launched(simulated: true)
        defer { app.terminate() }
        let toggle = app.buttons["mini-player-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 30), "the simulated episode is in the real player")
        XCTAssertEqual(toggle.label, "Pausar", "it is playing")
        XCTAssertTrue(SurfaceTest.element(app, "mini-player-artwork-fallback").exists,
            "the simulated occurrence admits no cover; the bar states that instead of inventing one")

        let elapsed = app.staticTexts["mini-player-elapsed"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 10))
        guard let start = Self.seconds(elapsed.label) else {
            return XCTFail("the bar's clock is m:ss; measured '\(elapsed.label)'")
        }
        Thread.sleep(forTimeInterval: 2.5)
        guard let advanced = Self.seconds(elapsed.label), advanced > start else {
            return XCTFail("the elapsed clock advances while the item plays (start=\(start), now='\(elapsed.label)')")
        }

        // Pause freezes the clock: a label that keeps moving would be a view-local timer, not the player's state.
        toggle.tap()
        let pausedToggle = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Tocar"),
            object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [pausedToggle], timeout: 10), .completed,
            "the toggle reports the paused state")
        guard let paused = Self.seconds(elapsed.label) else { return XCTFail("a paused clock still states m:ss") }
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(Self.seconds(elapsed.label), paused, "the paused clock does not advance")

        // Full player: a measured length is a scale, and its badge is drawn from the same fact.
        app.otherElements["mini-player"].tap()
        XCTAssertTrue(app.otherElements["full-player"].waitForExistence(timeout: 15))
        let scrub = app.sliders["full-player-scrub"]
        XCTAssertTrue(scrub.waitForExistence(timeout: 15), "the full player states a length")
        let position = app.staticTexts["full-player-position"]
        XCTAssertTrue(position.waitForExistence(timeout: 10))
        XCTAssertTrue(SurfaceTest.element(app, "full-player-duration-badge").exists,
            "the player's measured length is stated as V1's podcast badge")
        XCTAssertTrue(SurfaceTest.element(app, "full-player-artwork-fallback").exists,
            "no admitted cover, stated honestly in the sheet too")

        // Scrub with **real touches**: `adjust(toNormalizedSliderPosition:)` writes the binding without raising
        // `onEditingChanged`, so it tests the thumb's value and not the release. A press-drag-release is the gesture
        // the product actually handles, and the commit-on-release is what makes the assertions below true. The press
        // has to begin where the thumb is — the position the player reports — because a `UISlider` starts tracking on
        // its thumb and not on an arbitrary point of its frame.
        let statedLength = Self.seconds(app.staticTexts["full-player-duration"].label) ?? 0
        XCTAssertGreaterThan(statedLength, 20, "the simulated episode states a length to scrub over")
        guard let held = Self.seconds(position.label), held < statedLength else {
            return XCTFail("the player states a position inside its length before the scrub; measured "
                + "'\(position.label)' of \(statedLength) s")
        }
        let expected = Int((Double(statedLength) * 0.75).rounded())
        let press = Self.scrubPoint(scrub, at: Double(held) / Double(statedLength))
        let release = Self.scrubPoint(scrub, at: 0.75)
        press.press(forDuration: 0.2, thenDragTo: release)
        guard let committed = waitForPosition(position, within: (expected - 3)...(expected + 3), timeout: 15) else {
            return XCTFail("the released scrub commits \(expected) s of a \(statedLength) s item from the thumb "
                + "at \(held) s; measured '\(position.label)'")
        }
        attach(app, "podcast-scrub-committed")

        // ±15 s is the real callback, applied to the released position.
        app.buttons["full-player-back15"].tap()
        guard let rewound = waitForPosition(position, within: (committed - 16)...(committed - 13),
            timeout: 15) else {
            return XCTFail("back 15 from \(committed) s rewinds to \(committed - 15) s; measured '\(position.label)'")
        }
        XCTAssertLessThanOrEqual(rewound, committed - 13)

        // The sheet's label is the thumb's draft while a gesture is in flight; the bar's clock is the **player's own**
        // statement, and it is frozen while paused. Closing the sheet therefore proves the player really took the
        // released scrub and the −15 s, not merely that a draft was drawn.
        app.buttons["full-player-close"].tap()
        XCTAssertTrue(SurfaceTest.waitForAbsence(app.otherElements["full-player"], timeout: 15),
            "closing the sheet returns to the feed's own bar")
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "closing the sheet keeps the episode in the bar")
        guard let barPosition = waitForPosition(elapsed, within: (rewound - 2)...(rewound + 2), timeout: 15) else {
            return XCTFail("the player holds \(rewound) s after the released scrub and −15 s; "
                + "the bar states '\(elapsed.label)'")
        }
        XCTAssertLessThanOrEqual(abs(barPosition - rewound), 2,
            "the bar's clock states the position the player holds, not the thumb's draft")

        // The bar drives the same occurrence the scrub did.
        toggle.tap()
        let resumed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Pausar"),
            object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 10), .completed,
            "the bar resumes the occurrence the player was scrubbed to")

        app.buttons["mini-player-stop"].tap()
        XCTAssertTrue(SurfaceTest.waitForAbsence(app.otherElements["mini-player"], timeout: 15),
            "stop ends the episode and takes the bar away")
        XCTAssertTrue(app.scrollViews.firstMatch.exists, "the feed is still the reader's page")
    }
}
