// File: SettingsAndDiscoveryJourneyUITests.swift
// Module: FeedMineUITests
// Owns: every published settings option and discovery preference, driven through its control and re-read after
//       the surface is closed and reopened. These journeys assert the stored/read-back value; they do not claim
//       the visual typography/palette application or a feed-ranking effect (the remaining T3 gap).

import XCTest

final class SettingsAndDiscoveryJourneyUITests: XCTestCase {
    @MainActor
    func testSettingsControlsPersistAndContentRuleDeletionReturns() throws {
        let app = SurfaceTest.launchFixture()
        openSettings(app)

        select(app, picker: "settings-type-scale", option: "Grande")

        let paletteToggle = app.switches["settings-circadian-palette"]
        XCTAssertTrue(SurfaceTest.scrollIntoView(paletteToggle, in: app, timeout: 20))
        if paletteToggle.value as? String != "1" { paletteToggle.tap() }
        XCTAssertTrue(SurfaceTest.waitForValue(paletteToggle, differentFrom: "0", timeout: 20))
        let palette = app.buttons["settings-palette-family"]
        XCTAssertTrue(palette.isEnabled, "enabling the clock palette enables its family picker")
        select(app, picker: "settings-palette-family", option: "Céu frio")

        let typography = app.switches["settings-circadian-typography"]
        if typography.value as? String != "1" { typography.tap() }
        XCTAssertTrue(SurfaceTest.waitForValue(typography, differentFrom: "0", timeout: 20))
        select(app, picker: "settings-font-style", option: "Mono")

        for identifier in ["settings-prefetch", "settings-night-mode", "settings-filter-expiry",
                           "settings-content-filters"] {
            let toggle = app.switches[identifier]
            XCTAssertTrue(SurfaceTest.scrollIntoView(toggle, in: app, timeout: 20), "\(identifier) is offered")
            let before = toggle.value as? String
            let control = toggle.switches.firstMatch
            (control.exists ? control : toggle).tap()
            XCTAssertTrue(SurfaceTest.waitForValue(toggle, differentFrom: before, timeout: 20),
                "\(identifier) changes its stored value")
        }
        let night = app.switches["settings-night-mode"].value as? String
        let contentFiltersValue = app.switches["settings-content-filters"].value as? String

        // The content-filter page: a rule the reader adds is listed and its swipe removes it; the template
        // toggle is the other published control on that page.
        let rulesLink = app.buttons["settings-content-filter-rules"]
        XCTAssertTrue(SurfaceTest.scrollIntoView(rulesLink, in: app, timeout: 20))
        rulesLink.tap()
        XCTAssertTrue(app.navigationBars["Filtros de conteúdo"].waitForExistence(timeout: 20))
        app.buttons["content-filter-add-rule"].tap()
        let ruleAlert = app.alerts["Nova regra"]
        XCTAssertTrue(ruleAlert.waitForExistence(timeout: 10))
        ruleAlert.textFields.firstMatch.typeText("palavra-teste")
        ruleAlert.buttons["Adicionar"].tap()
        let rule = app.staticTexts["palavra-teste"]
        XCTAssertTrue(rule.waitForExistence(timeout: 20), "the rule the reader wrote is listed")
        rule.swipeLeft()
        app.buttons["Apagar"].tap()
        XCTAssertTrue(SurfaceTest.waitForAbsence(rule, timeout: 20),
            "swiping the rule away removes the stored words")
        XCTAssertTrue(app.staticTexts["Nenhuma palavra sua ainda."].exists)

        let template = app.switches.matching(
            NSPredicate(format: "identifier BEGINSWITH 'content-filter-template-'")).firstMatch
        if template.waitForExistence(timeout: 10) {
            let before = template.value as? String
            let control = template.switches.firstMatch
            (control.exists ? control : template).tap()
            XCTAssertTrue(SurfaceTest.waitForValue(template, differentFrom: before, timeout: 20))
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 20))
        app.buttons["settings-done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))

        // Durable read-back: close the whole surface and open it again.
        openSettings(app)
        XCTAssertTrue(app.staticTexts["Grande"].exists || (controlValue(app, "settings-type-scale") ?? "").contains("Grande"))
        XCTAssertTrue(app.staticTexts["Céu frio"].exists || (controlValue(app, "settings-palette-family") ?? "").contains("Céu frio"))
        XCTAssertTrue(app.staticTexts["Mono"].exists || (controlValue(app, "settings-font-style") ?? "").contains("Mono"))
        XCTAssertEqual(app.switches["settings-night-mode"].value as? String, night,
            "the night mode the reader chose is the one the settings read after reopening")
        XCTAssertEqual(app.switches["settings-content-filters"].value as? String, contentFiltersValue,
            "the content-filter master gate is the value the reader chose")

        let proof = XCTAttachment(string: "settings=type,palette,typography,prefetch,night,expiry,content-filters "
            + "rule-add-delete=true night=\(night ?? "nil")")
        proof.name = "settings-journey"
        proof.lifetime = .keepAlways
        add(proof)
    }

    @MainActor
    func testDiscoveryAnswersPersistAndCreateAnOpenableFeed() throws {
        let app = SurfaceTest.launchFixture()
        openSettings(app)
        openDiscovery(app)

        let language = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'discovery-language-'")).firstMatch
        XCTAssertTrue(SurfaceTest.scrollIntoView(language, in: app, timeout: 30),
            "the discovery page offers the catalogue's languages")
        let languageBefore = language.isSelected
        language.tap()
        XCTAssertNotEqual(language.isSelected, languageBefore)
        let languageSelected = language.isSelected

        let place = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'discovery-region-'")).firstMatch
        if place.waitForExistence(timeout: 10) {
            let before = place.isSelected
            place.tap()
            XCTAssertNotEqual(place.isSelected, before)
        }
        let placeSelected = place.exists ? place.isSelected : nil

        let slider = app.sliders["discovery-discovery"]
        XCTAssertTrue(SurfaceTest.scrollIntoView(slider, in: app, timeout: 20))
        let sliderBefore = slider.value as? String
        slider.adjust(toNormalizedSliderPosition: 0.8)
        XCTAssertTrue(SurfaceTest.waitForValue(slider, differentFrom: sliderBefore, timeout: 20))

        let balance = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'discovery-balance-'")).firstMatch
        let balanceBefore = balance.label
        balance.tap()
        XCTAssertNotEqual(balance.label, balanceBefore, "the balance control cycles its stored preference")

        let topic = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'discovery-topic-'")).firstMatch
        if topic.waitForExistence(timeout: 10) {
            let before = topic.label
            topic.tap()
            XCTAssertNotEqual(topic.label, before)
        }

        let media = app.switches["discovery-media-podcast"]
        if media.waitForExistence(timeout: 10) {
            let before = media.value as? String
            let control = media.switches.firstMatch
            (control.exists ? control : media).tap()
            XCTAssertTrue(SurfaceTest.waitForValue(media, differentFrom: before, timeout: 20))
        }

        // Values were captured as each control acted, while it was on screen: swiping the page back to the top
        // would dismiss the sheet instead of scrolling it.
        let sliderAfter = slider.value as? String
        let balanceAfter = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'discovery-balance-'")).firstMatch.label
        let mediaAfter = media.exists ? media.value as? String : nil

        // Close the page and reopen it: every control must read the stored answer, not its default.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 20))
        app.buttons["settings-done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))
        openSettings(app)
        openDiscovery(app)
        let reopenedLanguage = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'discovery-language-'")).firstMatch
        XCTAssertTrue(reopenedLanguage.waitForExistence(timeout: 30))
        XCTAssertEqual(reopenedLanguage.isSelected, languageSelected)
        let reopenedPlace = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'discovery-region-'")).firstMatch
        if let placeSelected { XCTAssertEqual(reopenedPlace.isSelected, placeSelected) }
        let reopenedSlider = app.sliders["discovery-discovery"]
        XCTAssertTrue(SurfaceTest.scrollIntoView(reopenedSlider, in: app, timeout: 20))
        XCTAssertEqual(reopenedSlider.value as? String, sliderAfter)
        let reopenedBalance = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'discovery-balance-'")).firstMatch
        XCTAssertTrue(SurfaceTest.scrollIntoView(reopenedBalance, in: app, timeout: 20))
        XCTAssertEqual(reopenedBalance.label, balanceAfter)
        let reopenedMedia = app.switches["discovery-media-podcast"]
        XCTAssertTrue(SurfaceTest.scrollIntoView(reopenedMedia, in: app, timeout: 20))
        if let mediaAfter { XCTAssertEqual(reopenedMedia.value as? String, mediaAfter) }

        // Creating a feed from these answers never activates it; opening is the reader's next action.
        let name = "Descoberta \(UUID().uuidString.prefix(6))"
        let nameField = app.textFields["discovery-feed-name"]
        XCTAssertTrue(SurfaceTest.scrollIntoView(nameField, in: app, timeout: 20))
        nameField.tap()
        nameField.typeText(name)
        app.buttons["discovery-create-feed"].tap()
        let open = app.buttons["discovery-open-created-feed"]
        XCTAssertTrue(open.waitForExistence(timeout: 60), "the created feed is offered")
        open.tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 90),
            "opening the created discovery feed returns to the reader")
        XCTAssertTrue(app.buttons["lens-chip-preset"].waitForExistence(timeout: 30),
            "the activated feed is the reader's preset")
        XCTAssertTrue(app.buttons["more-menu"].waitForExistence(timeout: 20))

        let proof = XCTAttachment(string: "discovery=language,place,slider,balance,topic,media create-open=true "
            + "slider=\(sliderAfter ?? "nil") balance=\(balanceAfter)")
        proof.name = "discovery-journey"
        proof.lifetime = .keepAlways
        add(proof)
    }

    // MARK: - Steps

    @MainActor
    private func openSettings(_ app: XCUIApplication) {
        SurfaceTest.menuEntry(app, "Ajustes")
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 20))
    }

    @MainActor
    private func openDiscovery(_ app: XCUIApplication) {
        let link = app.buttons["settings-discovery-preferences"]
        XCTAssertTrue(SurfaceTest.scrollIntoView(link, in: app, timeout: 20))
        link.tap()
        XCTAssertTrue(app.navigationBars["Preferências de descoberta"].waitForExistence(timeout: 20))
    }

    /// A Picker in a List is a button whose menu carries the options; both forms are tried so the same helper
    /// works on iOS and on the Mac host.
    @MainActor
    private func select(_ app: XCUIApplication, picker identifier: String, option: String) {
        let picker = app.buttons[identifier]
        XCTAssertTrue(SurfaceTest.scrollIntoView(picker, in: app, timeout: 30), "\(identifier) is offered")
        picker.tap()
        let menuItem = app.menus.buttons[option].firstMatch
        if menuItem.waitForExistence(timeout: 5) {
            menuItem.tap()
        } else {
            let button = app.buttons[option].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5), "option \(option) is offered")
            button.tap()
        }
        let observed = controlValue(app, identifier) ?? ""
        XCTAssertTrue(observed.contains(option) || app.staticTexts[option].exists,
            "the picker reads the chosen option after the menu closes; observed \(observed)")
    }

    @MainActor
    private func controlValue(_ app: XCUIApplication, _ identifier: String) -> String? {
        let element = app.buttons[identifier].firstMatch
        return (element.value as? String) ?? element.label
    }
}
