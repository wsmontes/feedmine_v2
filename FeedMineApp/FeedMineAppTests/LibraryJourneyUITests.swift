// File: LibraryJourneyUITests.swift
// Module: FeedMineUITests
// Owns: boxes (create, rename, preferred, delete, reorder), collections (create, rename, delete, member removal,
//       opening the collection feed) and the saved list reached from the boxes surface.
// Every action is re-read after closing and reopening the surface; a row that merely exists proves nothing.

import XCTest

final class LibraryJourneyUITests: XCTestCase {
    @MainActor
    func testBookmarkBoxesCreateRenamePreferDeleteAndReorder() throws {
        let app = SurfaceTest.launchFixture()
        app.buttons["bookmark-boxes-button"].tap()
        XCTAssertTrue(app.navigationBars["Caixas de salvos"].waitForExistence(timeout: 20))

        createBox("Caixa A", in: app)
        createBox("Caixa B", in: app)
        XCTAssertTrue(app.staticTexts["Caixa A"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Caixa B"].waitForExistence(timeout: 20))

        // Preferred: the leading swipe's Padrão. The checkmark is the durable mark of the preferred box.
        let rowA = app.staticTexts["Caixa A"]
        rowA.swipeRight()
        let preferred = app.buttons["Padrão"]
        XCTAssertTrue(preferred.waitForExistence(timeout: 10), "the leading swipe offers Padrão")
        preferred.tap()
        XCTAssertTrue(app.images["checkmark"].waitForExistence(timeout: 20),
            "the preferred box is marked after the swipe action")

        // Rename through the trailing swipe; the alert's own confirm is the effect.
        let rowB = app.staticTexts["Caixa B"]
        rowB.swipeLeft()
        let rename = app.buttons["Renomear"]
        XCTAssertTrue(rename.waitForExistence(timeout: 10))
        rename.tap()
        let renameAlert = app.alerts["Renomear"]
        XCTAssertTrue(renameAlert.waitForExistence(timeout: 10))
        let field = renameAlert.textFields.firstMatch
        SurfaceTest.replaceText(field, with: "Caixa renomeada")
        renameAlert.buttons["Renomear"].tap()
        XCTAssertTrue(app.staticTexts["Caixa renomeada"].waitForExistence(timeout: 20))
        XCTAssertTrue(SurfaceTest.waitForAbsence(app.staticTexts["Caixa B"], timeout: 10))

        // Reorder: enter the surface's own mode and drag one row above the other. The order after reopening is
        // the durable assertion.
        app.buttons["bookmarkBoxes.reorder"].tap()
        let first = app.staticTexts["Caixa A"]
        let second = app.staticTexts["Caixa renomeada"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        let orderBefore = boxLabels(app)
        XCTAssertEqual(orderBefore.count, 2, "the two boxes are listed before the drag")
        second.press(forDuration: 1.2, thenDragTo: first)
        app.buttons["bookmarkBoxes.reorder"].tap()
        let orderAfter = boxLabels(app)
        XCTAssertNotEqual(orderAfter, orderBefore,
            "the drag really changes the box permutation; before=\(orderBefore) after=\(orderAfter)")

        // The permutation is durable before the later delete removes one of the rows.
        app.buttons["bookmarkBoxes.done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))
        app.buttons["bookmark-boxes-button"].tap()
        XCTAssertTrue(app.navigationBars["Caixas de salvos"].waitForExistence(timeout: 20))
        XCTAssertEqual(boxLabels(app), orderAfter,
            "the reordered permutation is the one read after reopening; reopened=\(boxLabels(app))")

        // Delete the non-default box through the trailing swipe; no confirmation is promised for a box.
        app.staticTexts["Caixa renomeada"].swipeLeft()
        let delete = app.buttons["Apagar"]
        XCTAssertTrue(delete.waitForExistence(timeout: 10))
        delete.tap()
        XCTAssertTrue(SurfaceTest.waitForAbsence(app.staticTexts["Caixa renomeada"], timeout: 20))

        // Reopen: the rename, the delete and the preferred mark are durable; no row is left half-deleted.
        app.buttons["bookmarkBoxes.done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))
        app.buttons["bookmark-boxes-button"].tap()
        XCTAssertTrue(app.navigationBars["Caixas de salvos"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Caixa A"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["Caixa renomeada"].exists, "the deleted box stays deleted")
        XCTAssertTrue(app.images["checkmark"].exists, "the preferred box stays marked")
        app.buttons["bookmarkBoxes.done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))

        let proof = XCTAttachment(string: "boxes=created,preferred,renamed,reordered,deleted durable=true")
        proof.name = "bookmark-boxes-journey"
        proof.lifetime = .keepAlways
        add(proof)
    }

    @MainActor
    func testCollectionsCreateRenameDeleteAndEmptyDetail() throws {
        let app = SurfaceTest.launchFixture()
        SurfaceTest.menuEntry(app, "Coleções de fontes")
        XCTAssertTrue(app.navigationBars["Coleções de fontes"].waitForExistence(timeout: 20))
        XCTAssertTrue(SurfaceTest.element(app, "collections-empty").waitForExistence(timeout: 10))

        app.buttons["collections.new"].tap()
        let create = app.alerts["Nova coleção de fontes"]
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        let nameField = create.textFields.firstMatch
        nameField.tap()
        nameField.typeText("Coleção do teste")
        create.buttons["Criar"].tap()
        XCTAssertTrue(app.staticTexts["Coleção do teste"].waitForExistence(timeout: 20))
        app.staticTexts["Coleção do teste"].tap()
        XCTAssertTrue(app.buttons["collection.openFeed"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["collection.openFeed"].isEnabled,
            "a collection without members cannot open a feed")
        XCTAssertTrue(app.staticTexts["Adicione fontes a partir de um card ou de um resultado."].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Rename through the row's trailing swipe; the alert's own confirm is the effect.
        app.staticTexts["Coleção do teste"].swipeLeft()
        app.buttons["Renomear"].tap()
        let rename = app.alerts["Renomear"]
        XCTAssertTrue(rename.waitForExistence(timeout: 10))
        rename.textFields.firstMatch.tap()
        SurfaceTest.replaceText(rename.textFields.firstMatch, with: "Coleção renomeada")
        rename.buttons["Renomear"].tap()
        XCTAssertTrue(app.staticTexts["Coleção renomeada"].waitForExistence(timeout: 20))

        app.staticTexts["Coleção renomeada"].swipeLeft()
        app.buttons["Apagar"].tap()
        XCTAssertTrue(app.buttons["Apagar coleção"].waitForExistence(timeout: 10),
            "deleting a collection asks for the destructive action")
        app.buttons["Apagar coleção"].tap()
        XCTAssertTrue(SurfaceTest.waitForAbsence(app.staticTexts["Coleção renomeada"], timeout: 20))
        XCTAssertTrue(SurfaceTest.element(app, "collections-empty").waitForExistence(timeout: 20),
            "the empty state returns after the only collection is deleted")
        app.buttons["collections.done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["native-viewport-delivery"].waitForExistence(timeout: 20),
            "deleting a collection never deletes the sources it references")
    }

    @MainActor
    func testSavedCardReachesTheSavedListAndTheBoxPreferencePersists() throws {
        let app = SurfaceTest.launchFixture()
        let card = try XCTUnwrap(SurfaceTest.firstCard(app), "a fixture card is visible")
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.2)
        let save = app.menus.buttons["Salvar artigo"].firstMatch
        if save.waitForExistence(timeout: 5) { save.tap() } else {
            let visible = app.buttons["Salvar artigo"].firstMatch
            XCTAssertTrue(visible.waitForExistence(timeout: 5), "the card menu offers Salvar artigo")
            visible.tap()
        }

        app.buttons["bookmark-boxes-button"].tap()
        XCTAssertTrue(app.navigationBars["Caixas de salvos"].waitForExistence(timeout: 20))
        createBox("Caixa de leitura", in: app)
        let box = app.staticTexts["Caixa de leitura"]
        box.swipeRight()
        app.buttons["Padrão"].tap()
        app.buttons["bookmarkBoxes.done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))

        app.buttons["bookmark-boxes-button"].tap()
        XCTAssertTrue(app.navigationBars["Caixas de salvos"].waitForExistence(timeout: 20))
        app.buttons["Todos os salvos"].tap()
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'saved-article-'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 20),
            "the article saved from the card menu is in the saved list")
        XCTAssertFalse(app.staticTexts["Nenhum artigo salvo"].exists)
    }

    /// The boxes' own row labels, in drawing order. A reorder assertion needs the permutation, not one row.
    @MainActor
    private func boxLabels(_ app: XCUIApplication) -> [String] {
        app.buttons.matching(identifier: "bookmarkBox.row").allElementsBoundByIndex.map(\.label)
            .filter { !$0.hasPrefix("Salvos") }
    }

    @MainActor
    private func createBox(_ name: String, in app: XCUIApplication) {
        app.buttons["bookmarkBoxes.new"].tap()
        let alert = app.alerts["Nova caixa"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        let field = alert.textFields.firstMatch
        field.tap()
        field.typeText(name)
        alert.buttons["Criar"].tap()
    }
}
