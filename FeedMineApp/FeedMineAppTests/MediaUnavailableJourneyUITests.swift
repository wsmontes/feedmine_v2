import XCTest

/// **A recusa de reprodução tem superfície nas duas larguras.**
///
/// O transporte local do próprio app (`FEEDMINE_LOCAL_FEEDS=1`, DEBUG) serve cartas de áudio cujo enclosure é
/// `https://fixture.invalid/...`: o nome passa a política de host do localizador, mas não resolve. O player
/// descobre que não pode tocar e a recusa precisa aparecer — a barra nomeia o episódio e diz o motivo
/// (`mini-player-error`), em vez de o toque parecer não fazer nada. A mesma carta, na largura regular, desenha a
/// linha compacta (`FeedItemView.usesRow`), que antes não tinha controle nenhum: `card.play` tem de existir e
/// tocar a **mesma** ocorrência publicada.
///
/// D11: esta é prova de superfície de recusa, não de mídia do catálogo real. Nenhuma afirmação sobre reprodução
/// de episódio real é feita aqui; a jornada de mídia real é `FeedMediaJourneyUITests`.
@MainActor
final class MediaUnavailableJourneyUITests: XCTestCase {
    private static var cardIdentifier: NSPredicate {
        NSPredicate(format: "identifier MATCHES %@",
            "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")
    }

    private func launched() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["FEEDMINE_FIXTURE_MEDIA"] = "audio"
        app.launchEnvironment["FEEDMINE_FIXTURE_ITEMS"] = "4"
        // A reader of this run only: no persistent namespace, no previously saved position or window.
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launch()
        return app
    }

    private func firstAudioCard(_ app: XCUIApplication) -> XCUIElement {
        let card = app.descendants(matching: .any).matching(Self.cardIdentifier).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 60), "a fixture publica cartas de áudio para esta medida")
        let play = card.buttons["card.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 15),
            "a carta de áudio declara o controle visível card.play (frame \(card.frame))")
        XCTAssertGreaterThanOrEqual(play.frame.height, 40,
            "o controle tem o alvo que o produto declara (44 pt mínimos); medido \(play.frame)")
        return card
    }

    /// A recusa medida: o toque não abre o artigo, a barra aparece com a **mesma** carta e a razão em palavras.
    private func measureRefusalAndAttach(_ app: XCUIApplication, expectedLabel: String) {
        let card = firstAudioCard(app)
        let expectedCardID = card.identifier
        let play = card.buttons["card.play"]
        XCTAssertTrue(play.isHittable, "o controle está na dobra e hittable; \(play.frame) em \(card.frame)")

        play.tap()
        let bar = app.otherElements["mini-player"]
        XCTAssertTrue(bar.waitForExistence(timeout: 30),
            "a recusa aparece na barra: sem item a superfície do erro era invisível (\(expectedLabel))")

        let identity = app.descendants(matching: .any).matching(identifier: "mini-player-card").firstMatch
        XCTAssertTrue(identity.waitForExistence(timeout: 10))
        XCTAssertEqual(identity.label, expectedCardID,
            "a barra nomeia a carta tocada, não outra ocorrência")

        let error = app.staticTexts["mini-player-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10),
            "o motivo da recusa é um texto visível na própria barra")
        XCTAssertFalse(error.label.isEmpty, "o motivo não é vazio")

        XCTAssertFalse(app.webViews.firstMatch.exists,
            "tocar o controle não abriu a leitura em vez de tentar reproduzir")
        XCTAssertFalse(app.staticTexts["reading.headline"].exists)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "audio-refusal-\(expectedLabel)"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// A largura compacta desenha o **card**; a barra é a superfície que faltava quando o item era nil.
    func testCompactCardsStateTheRefusalAndKeepTheOccurrence() throws {
        let app = launched()
        defer { app.terminate() }
        let width = app.windows.firstMatch.frame.width
        try XCTSkipUnless(width < 600, "medida da largura compacta; esta janela tem \(width) pt")
        measureRefusalAndAttach(app, expectedLabel: "compact")
    }

    /// A largura regular desenha a **linha** (`usesRow`): ela precisa do mesmo `card.play`, da mesma ocorrência
    /// e da mesma recusa. Esta é a regressão media-3.
    func testRegularWidthRowsOfferTheSamePlayAndIdentity() throws {
        let app = launched()
        defer { app.terminate() }
        let width = app.windows.firstMatch.frame.width
        try XCTSkipUnless(width >= 700, "medida da largura regular; esta janela tem \(width) pt")
        measureRefusalAndAttach(app, expectedLabel: "regular")
    }
}
