import XCTest

/// Real controls and process persistence. Publication A/B semantics are a separate acceptance gate.
final class SourceExclusionJourneyUITests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    @MainActor
    func testImportedRuleCancelConfirmRelaunchAndRemoveInPortuguese() throws {
        try journey(language: "pt-BR", locale: "pt_BR", largeType: false)
    }

    @MainActor
    func testImportedRuleCancelConfirmRelaunchAndRemoveInEnglishLargeType() throws {
        try journey(language: "en", locale: "en_US", largeType: true)
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
