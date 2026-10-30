import XCTest

/// Real controls and process persistence. Publication A/B semantics are a separate acceptance gate.
final class SourceExclusionJourneyUITests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    @MainActor
    func testLegacyRecoveryContinuesPreviousCriteriaInPortuguese() throws {
        try legacyRecovery(previous: true, english: false)
    }

    @MainActor
    func testLegacyRecoveryOpensCurrentCriteriaInEnglishLargeType() throws {
        try legacyRecovery(previous: false, english: true)
    }

    @MainActor
    private func legacyRecovery(previous: Bool, english: Bool) throws {
        var arguments = ["-AppleLanguages", english ? "(en)" : "(pt-BR)", "-AppleLocale", english ? "en_US" : "pt_BR"]
        if english { arguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        let app = SurfaceTest.launchFixture(["FEEDMINE_RECOVERY_LEGACY_FIXTURE": "1",
            "FEEDMINE_DISABLE_CATALOGUE_SYNC": "1", "FEEDMINE_FIXTURE_ITEMS": "6", "FEEDMINE_TRACE_CAPTURE": "1"], arguments: arguments)
        defer { app.terminate() }
        let marker = app.descendants(matching: .any)["history-recovery-reader"].firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["search-button"].isEnabled)
        let proof = app.staticTexts["feed-window-proof"]
        XCTAssertTrue(proof.exists)
        let feed = app.scrollViews.firstMatch
        if previous {
            for _ in 0..<12 {
                let ids = String(proof.label.split(separator: ";")[0]).dropFirst(4).split(separator: ",")
                let tail = SurfaceTest.element(app, try XCTUnwrap(ids.last).description)
                if tail.exists, tail.frame.maxY <= feed.frame.maxY + 1, tail.frame.intersection(feed.frame).height > 30 { break }
                feed.swipeUp(velocity: .slow)
            }
        }
        let initial = String(proof.label.split(separator: ";")[0])
        let tailID = try XCTUnwrap(initial.dropFirst(4).split(separator: ",").last).description
        let tail = SurfaceTest.element(app, tailID)
        let before = previous ? tail.frame : .zero
        if previous { XCTAssertGreaterThan(before.intersection(feed.frame).height, 30) }
        let beforeDelta = before.minY - feed.frame.minY
        app.buttons["more-menu"].tap()
        let action = app.buttons["history-recovery-action"]
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        action.tap()
        XCTAssertTrue(app.staticTexts[english ? "Choose how to continue" : "Escolha como continuar"].waitForExistence(timeout: 10))
        app.buttons[english ? "Done" : "Concluir"].tap()
        XCTAssertTrue(SurfaceTest.waitForAbsence(app.buttons["history-recovery-previous"], timeout: 10))
        if previous {
            XCTAssertEqual(tail.frame.minY, before.minY, accuracy: 1, "opening and cancelling recovery must not move the tail")
        }
        app.buttons["more-menu"].tap()
        app.buttons["history-recovery-action"].tap()
        let chosen = app.buttons[previous ? "history-recovery-previous" : "history-recovery-current"]
        XCTAssertTrue(SurfaceTest.scrollIntoView(chosen, in: app, timeout: 15))
        chosen.tap()
        XCTAssertTrue(SurfaceTest.waitForAbsence(marker, timeout: 40))
        XCTAssertTrue(SurfaceTest.waitForAbsence(chosen, timeout: 15))
        XCTAssertTrue(proof.waitForExistence(timeout: 20))
        if previous { XCTAssertEqual(String(proof.label.split(separator: ";")[0]), initial, "continuing frozen criteria preserves the exact reading") }
        if previous {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Retained reading after choice"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertEqual(tail.frame.minY - feed.frame.minY, beforeDelta, accuracy: 2,
                "continuing must preserve the visible retained card relative to the viewport; before=\(before), after=\(tail.frame)")
            XCTAssertGreaterThan(tail.frame.intersection(feed.frame).height, 20)
        }
        let installed = String(proof.label.split(separator: ";")[0])
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["more-menu"].waitForExistence(timeout: 30))
        XCTAssertTrue(proof.waitForExistence(timeout: 30))
        XCTAssertFalse(marker.exists)
        XCTAssertEqual(String(proof.label.split(separator: ";")[0]), installed, "the system process relaunch honours the chosen history")
        if previous {
            XCTAssertGreaterThan(tail.frame.intersection(feed.frame).height, 20)
            XCTAssertEqual(tail.frame.minY - feed.frame.minY, beforeDelta, accuracy: 2,
                "process relaunch must restore the chosen visible position, not only its IDs")
        }
    }

    @MainActor
    func testImportedRuleCancelConfirmRelaunchAndRemoveInPortuguese() throws {
        try journey(language: "pt-BR", locale: "pt_BR", largeType: false)
    }

    @MainActor
    func testImportedRuleCancelConfirmRelaunchAndRemoveInEnglishLargeType() throws {
        try journey(language: "en", locale: "en_US", largeType: true)
    }

    /// This rule names an imported source outside the fixture supply. It proves the real recovery route
    /// and geometry, not that excluded fixture supply became publishable (a separate acceptance case).
    @MainActor
    func testRecoveryRouteRemovesRuleWithoutMovingTheLastAdmittedCard() throws {
        try recoveryRoute(largeType: false)
    }

    @MainActor
    func testRecoveryRouteKeepsTailInEnglishLargeType() throws {
        try recoveryRoute(largeType: true)
    }

    @MainActor
    private func recoveryRoute(largeType: Bool) throws {
        let language = largeType ? "en" : "pt-BR"
        var arguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", largeType ? "en_US" : "pt_BR"]
        if largeType { arguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        let app = SurfaceTest.launchFixture([
            "FEEDMINE_IMPORT_FIXTURE": "1", "FEEDMINE_DISABLE_CATALOGUE_SYNC": "1",
            "FEEDMINE_FIXTURE_ITEMS": "6", "FEEDMINE_TRACE_CAPTURE": "1"
        ], arguments: arguments)
        defer { app.terminate() }
        let importAction = app.buttons["import-confirm"]
        XCTAssertTrue(importAction.waitForExistence(timeout: 30))
        importAction.tap()
        XCTAssertTrue(SurfaceTest.waitForAbsence(importAction, timeout: 30))
        SurfaceTest.menuEntry(app, largeType ? "Sources" : "Fontes")
        let row = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'imported-source-'")).firstMatch
        XCTAssertTrue(SurfaceTest.scrollIntoView(row, in: app, timeout: 30))
        let key = String(row.identifier.dropFirst("imported-source-".count))
        row.press(forDuration: 1.2)
        let exclude = app.buttons["source-exclusion-action-\(key)"]
        XCTAssertTrue(exclude.waitForExistence(timeout: 15))
        exclude.tap()
        let confirm = app.buttons["source-exclusion-confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 15))
        confirm.tap()
        XCTAssertTrue(SurfaceTest.waitForAbsence(confirm, timeout: 15))
        app.buttons["sources-done"].tap()

        let feed = app.scrollViews.firstMatch
        let proof = app.staticTexts["feed-window-proof"]
        XCTAssertTrue(proof.exists)
        feed.swipeUp(velocity: .slow)
        for _ in 0..<16 {
            let current = String(proof.label.split(separator: ";")[0])
            let tailID = try XCTUnwrap(current.dropFirst("ids=".count).split(separator: ",").last).description
            let tail = SurfaceTest.element(app, tailID)
            if tail.exists, tail.frame.intersection(feed.frame).height > 40,
                tail.frame.maxY <= feed.frame.maxY + 1 { break }
            feed.swipeUp(velocity: .slow)
        }
        let admitted = String(proof.label.split(separator: ";")[0])
        let lastID = try XCTUnwrap(admitted.dropFirst("ids=".count).split(separator: ",").last).description
        let last = SurfaceTest.element(app, lastID)
        XCTAssertTrue(last.exists)
        let before = last.frame
        let viewportBefore = feed.frame
        XCTAssertLessThanOrEqual(before.maxY, feed.frame.maxY + 1,
            "the gesture must reach the admitted tail, not only a partially visible final card")
        XCTAssertGreaterThan(before.intersection(feed.frame).height, 40,
            "the last admitted card must still be visible at the tail")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "source-recovery-tail-before-\(language)"; shot.lifetime = .keepAlways; add(shot)
        let activeValue = largeType ? "Excluded sources" : "Fontes excluídas"
        XCTAssertEqual(app.buttons["more-menu"].value as? String, activeValue)
        SurfaceTest.openMenu(app)
        let recovery = app.buttons["source-exclusion-recovery"].firstMatch
        XCTAssertTrue(recovery.waitForExistence(timeout: 15), app.debugDescription)
        recovery.tap()
        let remove = app.buttons.matching(NSPredicate(format:
            "identifier BEGINSWITH 'content-filter-remove-source-'")).firstMatch
        XCTAssertTrue(SurfaceTest.scrollIntoView(remove, in: app, timeout: 20), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Revista"].exists)
        if largeType {
            XCTAssertGreaterThan(app.staticTexts["Revista"].frame.height, 30,
                "the recovery route actually draws accessibility-sized content")
        }
        remove.tap()
        XCTAssertTrue(SurfaceTest.element(app, "content-filter-sources-empty").waitForExistence(timeout: 15))
        let done = app.buttons[largeType ? "Done" : "Concluir"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 15))
        done.tap()
        XCTAssertTrue(SurfaceTest.waitForAbsence(done, timeout: 15))
        XCTAssertTrue(SurfaceTest.waitForAbsence(recovery, timeout: 15))
        XCTAssertNotEqual(app.buttons["more-menu"].value as? String, activeValue)
        XCTAssertEqual(String(proof.label.split(separator: ";")[0]), admitted,
            "removing an unrelated rule preserves this admitted window")
        XCTAssertTrue(last.exists)
        XCTAssertEqual(feed.frame.minY, viewportBefore.minY, accuracy: 1)
        XCTAssertEqual(feed.frame.height, viewportBefore.height, accuracy: 1)
        let frames = (0..<5).map { _ -> CGRect in
            Thread.sleep(forTimeInterval: 0.2)
            return last.frame
        }
        let finalShot = XCTAttachment(screenshot: app.screenshot())
        finalShot.name = "source-recovery-tail-after-\(language)"; finalShot.lifetime = .keepAlways; add(finalShot)
        let geometry = XCTAttachment(string: "\(admitted) last=\(lastID) before=\(before) afterSamples=\(frames) viewportBefore=\(viewportBefore) viewportAfter=\(feed.frame) proof=\(proof.label)")
        geometry.name = "source-recovery-tail-geometry"; geometry.lifetime = .keepAlways; add(geometry)
        for after in frames {
            XCTAssertGreaterThan(after.intersection(feed.frame).height, 40)
            XCTAssertEqual(after.minY, before.minY, accuracy: 1,
                "the last admitted card keeps its viewport position in consecutive observations")
        }
    }

    @MainActor
    private func journey(language: String, locale: String, largeType: Bool) throws {
        let portuguese = language == "pt-BR"
        var arguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        if largeType { arguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        let app = SurfaceTest.launchFixture(["FEEDMINE_IMPORT_FIXTURE": "1", "FEEDMINE_DISABLE_CATALOGUE_SYNC": "1"], arguments: arguments)
        defer { app.terminate() }
        let confirmImport = app.buttons["import-confirm"]
        XCTAssertTrue(confirmImport.waitForExistence(timeout: 30))
        confirmImport.tap()
        XCTAssertTrue(SurfaceTest.waitForAbsence(confirmImport, timeout: 30))
        app.launchEnvironment.removeValue(forKey: "FEEDMINE_IMPORT_FIXTURE")

        func openSources() -> XCUIElement {
            SurfaceTest.menuEntry(app, portuguese ? "Fontes" : "Sources")
            let row = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH 'imported-source-'")).firstMatch
            XCTAssertTrue(SurfaceTest.scrollIntoView(row, in: app, timeout: 40), app.debugDescription)
            return row
        }
        func requestExclusion(_ row: XCUIElement) {
            let key = String(row.identifier.dropFirst("imported-source-".count))
            row.press(forDuration: 1.2)
            let action = app.buttons["source-exclusion-action-\(key)"]
            XCTAssertTrue(action.waitForExistence(timeout: 15), app.debugDescription)
            action.tap()
            XCTAssertTrue(app.buttons["source-exclusion-confirm"].firstMatch.waitForExistence(timeout: 15))
        }
        func openRules() {
            SurfaceTest.menuEntry(app, portuguese ? "Ajustes" : "Settings")
            let rules = SurfaceTest.element(app, "settings-content-filter-rules")
            XCTAssertTrue(SurfaceTest.scrollIntoView(rules, in: app, timeout: 30))
            rules.tap()
            XCTAssertTrue(app.switches["content-filter-enabled"].waitForExistence(timeout: 20))
        }
        func closeRules() {
            app.navigationBars.buttons.element(boundBy: 0).tap()
            let done = app.buttons["settings-done"]
            XCTAssertTrue(done.waitForExistence(timeout: 20))
            done.tap()
        }

        // Cancelling the explicit confirmation must not create a durable source rule.
        requestExclusion(openSources())
        let cancel = app.buttons[portuguese ? "Cancelar" : "Cancel"].firstMatch
        if cancel.exists && cancel.isHittable {
            cancel.tap()
        } else {
            let dismiss = SurfaceTest.element(app, "PopoverDismissRegion")
            XCTAssertTrue(dismiss.waitForExistence(timeout: 10), app.debugDescription)
            // The enlarged native panel covers Done; its visible right margin remains outside.
            // Use the dismiss region itself and prove cancellation by absence below.
            dismiss.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
        }
        XCTAssertTrue(SurfaceTest.waitForAbsence(app.buttons["source-exclusion-confirm"].firstMatch, timeout: 15))
        app.buttons["sources-done"].tap()
        openRules()
        XCTAssertTrue(SurfaceTest.element(app, "content-filter-sources-empty").waitForExistence(timeout: 20))
        closeRules()
        let anchor = try XCTUnwrap(SurfaceTest.firstCard(app)).identifier

        requestExclusion(openSources())
        app.buttons["source-exclusion-confirm"].firstMatch.tap()
        XCTAssertTrue(SurfaceTest.waitForAbsence(app.buttons["source-exclusion-confirm"].firstMatch, timeout: 20))
        app.buttons["sources-done"].tap()
        XCTAssertEqual(try XCTUnwrap(SurfaceTest.firstCard(app)).identifier, anchor,
            "the source rule keeps the reader's existing occurrence")
        openRules()
        let remove = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'content-filter-remove-source-'")).firstMatch
        XCTAssertTrue(SurfaceTest.scrollIntoView(remove, in: app, timeout: 20), app.debugDescription)
        let ruleIdentifier = remove.identifier
        let name = app.staticTexts.matching(NSPredicate(format: "label == %@", "Revista")).firstMatch
        XCTAssertTrue(name.exists, "the stored rule names the imported source")
        if largeType { XCTAssertGreaterThan(name.frame.height, 30, "the journey must actually draw enlarged type") }
        let master = app.switches["content-filter-enabled"]
        XCTAssertEqual(master.value as? String, "1")
        let masterControl = master.switches.firstMatch
        (masterControl.exists ? masterControl : master).tap()
        XCTAssertTrue(SurfaceTest.waitForValue(master, differentFrom: "1", timeout: 20))
        XCTAssertTrue(app.buttons[ruleIdentifier].exists, "master off retains the rule")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "source-rule-\(language)-master-off-large-\(largeType)"
        shot.lifetime = .keepAlways
        add(shot)
        closeRules()

        // A real process restart, keeping this journey's namespace and durable reader state.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["more-menu"].waitForExistence(timeout: 40))
        XCTAssertEqual(try XCTUnwrap(SurfaceTest.firstCard(app)).identifier, anchor)
        openRules()
        XCTAssertEqual(app.switches["content-filter-enabled"].value as? String, "0")
        let retained = app.buttons[ruleIdentifier]
        XCTAssertTrue(SurfaceTest.scrollIntoView(retained, in: app, timeout: 20))
        retained.tap()
        XCTAssertTrue(SurfaceTest.element(app, "content-filter-sources-empty").waitForExistence(timeout: 20))
        XCTAssertEqual(app.switches["content-filter-enabled"].value as? String, "0")
        closeRules()
        XCTAssertEqual(try XCTUnwrap(SurfaceTest.firstCard(app)).identifier, anchor)
        let proof = XCTAttachment(string: "language=\(language) large=\(largeType) rule=\(ruleIdentifier) cancelled-absent=true confirmed=true master-off-retained=true process-relaunch-retained=true removed=true anchor=\(anchor)")
        proof.name = "source-rule-controls-and-process-persistence"
        proof.lifetime = .keepAlways
        add(proof)
    }
}
