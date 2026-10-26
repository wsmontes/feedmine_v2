// File: SourceAbsenceJourneyUITests.swift
// Module: FeedMineUITests
// Owns: UX12-D on the real surface — a **disabled** catalogue source, with no local payload and the network
//       refused, opened by the reader's own gesture from the Fontes surface. The absence must belong to that
//       source (named by the chip), state the feed's own limit, invent no card and leave the reader's previous
//       navigation reachable.
// Does not own: production, admission or any second driver; every step is the reader's own tap.

import XCTest

final class SourceAbsenceJourneyUITests: XCTestCase {
    /// F12/UX12-D: a catalogue source the reader has not enabled has no local payload. Opening it while the
    /// network is refused states absence **inside that source**: the chip names it, the surface says what a
    /// source surface can show (the feed's items, not the site's whole archive), no card appears, the
    /// selection is untouched, and closing the context returns to the empty-selection surface the reader
    /// came from.
    @MainActor
    func testADisabledCatalogueSourceWithNoPayloadStatesTheFeedBoundary() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(pt_BR)", "-AppleLocale", "pt_BR"]
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_BLOCK_RSS_NETWORK"] = "1"
        // No `FEEDMINE_LOCAL_FEEDS`: the point of UX12-D is a source the app has **no** payload for and cannot
        // reach. The local fixture transport would answer the visited endpoint and publish its cards instead,
        // which is the opposite premise (measured: 12 fixture cards were drawn when it was set).
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["FEEDMINE_DISABLE_CATALOGUE_SYNC"] = "1"
        app.launch()

        let sourceKey = "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml"
        let sectionRow = app.buttons["node-child-582585858"]
        let leafRow = app.buttons["node-child-560998273"]
        let toggle = app.switches["node-source-toggle-\(sourceKey)"]
        let open = app.buttons["node-source-\(sourceKey)"]
        let chip = app.staticTexts["reader-context-label"]

        func cards() -> Int {
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier MATCHES %@", Self.cardIdentifier)).count
        }
        /// The sheet's accessibility tree can be lost by the client on this runtime (measured: the same build
        /// lists it in one run and returns the Application element alone in another). The retry reopens the
        /// reader's own surface; every assertion below still asserts the product's values.
        func openSourcesWithList() {
            for attempt in 1...2 {
                if attempt > 1 { app.terminate(); app.launch() }
                // The empty-selection surface states its own way in; the header menu is the route once a feed is
                // mounted. Both are the reader's own controls.
                let emptyAction = app.buttons["feed-empty-action"]
                if emptyAction.waitForExistence(timeout: 30) { emptyAction.tap() }
                else { SurfaceTest.menuEntry(app, "Fontes") }
                if app.cells.firstMatch.waitForExistence(timeout: 30) { return }
            }
            XCTFail("a lista do sheet não chegou à árvore; árvore=\(app.debugDescription)")
        }

        // Premise: no sources are selected, so the main surface states the empty selection and there is no local
        // payload anywhere. That is what makes the absence the source's own fact.
        let mainEmpty = app.staticTexts["feed-empty-title"]
        XCTAssertTrue(mainEmpty.waitForExistence(timeout: 120),
            "premise: the launch has no selected sources; árvore=\(app.debugDescription)")

        openSourcesWithList()
        XCTAssertTrue(SurfaceTest.scrollIntoView(sectionRow, in: app, timeout: 120),
            "a superfície lista as seções do catálogo; árvore=\(app.debugDescription)")
        sectionRow.tap()
        XCTAssertTrue(leafRow.waitForExistence(timeout: 60), "a seção abre o nó Wildlife & Nature")
        leafRow.tap()
        XCTAssertTrue(SurfaceTest.scrollIntoView(toggle, in: app, timeout: 240), "o nó lista a chave do catálogo")
        XCTAssertEqual(toggle.value as? String, "0", "premise: the source is disabled")
        XCTAssertTrue(open.exists, "the row offers opening it even while disabled")

        // The reader's own gesture: open the row. This must not enable the source or select anything.
        open.tap()

        XCTAssertTrue(chip.waitForExistence(timeout: 120),
            "o contexto da fonte chega à tela; árvore=\(app.debugDescription)")
        XCTAssertEqual(chip.label, "BBC News", "the chip names the source the absence belongs to")
        let note = app.staticTexts["feed-source-scope-note"]
        XCTAssertTrue(note.waitForExistence(timeout: 60),
            "the absence states what a source surface can show; árvore=\(app.debugDescription)")
        XCTAssertTrue(note.label.contains("arquivo completo do site"),
            "the note states the feed/site boundary the S1 copy requires; observed: \(note.label)")
        let sourceName = chip.label
        let noteText = note.label
        XCTAssertTrue(app.otherElements["feed-loading-surface"].exists
                || app.descendants(matching: .any)
                    .matching(NSPredicate(format: "identifier == %@", "feed-loading-surface")).firstMatch.exists,
            "an absence surface is what is drawn")
        XCTAssertEqual(cards(), 0, "the source's absence never invents a card")
        XCTAssertFalse(mainEmpty.exists,
            "the absence is the source's, not the empty-selection surface")

        // The failure is stated by the product's own alert. Its identity is read before anything is tapped: only
        // the expected source-load failure is acknowledged, and only through its own OK button.
        let failureAlert = app.alerts["Não foi possível atualizar"]
        XCTAssertTrue(failureAlert.waitForExistence(timeout: 30),
            "a falha esperada é declarada pelo alerta do produto; árvore=\(app.debugDescription)")
        let alertTexts = failureAlert.staticTexts.allElementsBoundByIndex.map(\.label)
            .joined(separator: " | ")
        XCTAssertTrue(alertTexts.contains("Não foi possível abrir o feed desta fonte."),
            "o alerta é a falha esperada da fonte, não outro alerta; textos=\(alertTexts)")
        XCTAssertTrue(failureAlert.buttons["OK"].exists, "o alerta oferece o próprio OK")

        // Captured here, while the source context is still on screen: a screenshot taken after the way back
        // shows the empty-selection surface instead, which is what the reader came *from*, not the absence.
        let absenceShot = XCTAttachment(screenshot: app.screenshot())
        absenceShot.name = "ux12d-source-absence-before-return"
        absenceShot.lifetime = .keepAlways
        add(absenceShot)

        // Acknowledge the expected alert through the UI, then re-read the same absence without it covering the
        // note. An unrelated alert would already have failed the identity check above and is never dismissed.
        failureAlert.buttons["OK"].tap()
        XCTAssertTrue(failureAlert.waitForNonExistence(timeout: 20),
            "o OK reconhecido remove o alerta esperado")
        XCTAssertEqual(chip.label, sourceName, "the chip still names the same source after the alert")
        XCTAssertTrue(note.exists, "the source-boundary note is still present after the alert")
        XCTAssertEqual(note.label, noteText, "the note is the same after the alert; observed: \(note.label)")
        XCTAssertEqual(cards(), 0, "acknowledging the failure invents no card")
        XCTAssertFalse(mainEmpty.exists,
            "the source context remains stated, not the empty-selection surface")
        XCTAssertTrue(app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == %@", "feed-loading-surface")).firstMatch.exists,
            "a source-absence surface is still drawn after the alert")
        let readableShot = XCTAttachment(screenshot: app.screenshot())
        readableShot.name = "ux12d-source-absence-after-alert"
        readableShot.lifetime = .keepAlways
        add(readableShot)

        // The reader's previous navigation is reachable: closing the source returns to the empty selection the
        // journey started from, and the source stays disabled.
        chip.tap()
        let clear = SurfaceTest.element(app, "reader-context-clear")
        XCTAssertTrue(clear.waitForExistence(timeout: 20), "the source context offers its way back")
        clear.tap()
        XCTAssertTrue(mainEmpty.waitForExistence(timeout: 60),
            "closing the source restores the surface the reader came from")
        XCTAssertFalse(app.staticTexts["reader-context-label"].exists,
            "and no source context remains stated")

        openSourcesWithList()
        XCTAssertTrue(app.navigationBars["Wildlife & Nature"].waitForExistence(timeout: 60),
            "reopening Fontes returns to the same node: the path is preserved")
        XCTAssertTrue(SurfaceTest.scrollIntoView(toggle, in: app, timeout: 120))
        XCTAssertEqual(toggle.value as? String, "0", "opening the source enabled nothing")
        XCTAssertTrue(app.buttons["node-sources-done"].exists, "the node keeps its own Concluir")
        app.buttons["node-sources-done"].tap()

        let proof = XCTAttachment(string:
            "chip='\(sourceName)' note='\(noteText)' cards=0 main-empty-restored=true "
                + "source-still-disabled=true fontes-path=Wildlife&Nature")
        proof.name = "ux12d-disabled-source-absence"
        proof.lifetime = .keepAlways
        add(proof)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "ux12d-main-empty-after-return"
        shot.lifetime = .keepAlways
        add(shot)
    }

    private static let cardIdentifier =
        "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}"
}
