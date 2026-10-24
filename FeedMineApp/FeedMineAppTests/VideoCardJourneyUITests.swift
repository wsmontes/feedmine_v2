import XCTest

/// **A carta de vídeo, ponta a ponta, com o feed que o leitor adiciona.**
///
/// A direção (2026-10-20): provar o caminho D2 numa corrida real, sem fixture de mídia e sem caminho de depuração
/// no produto. O leitor **adiciona** o feed de vídeo pelo próprio menu (menu → Adicionar feed → endereço →
/// Adicionar), o app o adquire pela rede de verdade, e a carta que ele publica é medida nas quatro cláusulas:
///
///  1. a carta **declara a própria identidade de mídia** — o selo "Vídeo" dentro do frame dela (nunca o tipo da
///     fonte, que pode ser texto e ainda assim carregar um item de vídeo);
///  2. **não** oferece o player do app: nenhum `card.play` e nenhuma ação "Tocar" dentro do frame (D2: a build não
///     tem player de vídeo, e o silêncio do player não pode ser confundido com uma carta de áudio);
///  3. tocar a carta abre o navegador in-app no **link do próprio item** — o teste lê o feed público que o app
///     adicionou, casa a carta com o item dele pelo título e compara a URL que o navegador mostra a esse link,
///     nunca a um endereço de mídia;
///  4. a URL que o leitor **tem** na barra do navegador é o link do item (inteira, pelo caminho, ou pelo host quando
///     o Safari só mostra o host), e a página aberta é o conteúdo **correspondente** — o título do item aparece no
///     texto da página, não uma página genérica.
///
/// A reprodução dentro do app **não** é prometida aqui (direção do dono, 2026-10-20): a build não tem player de
/// vídeo, e o navegador in-app é do sistema. O que a metade do simulador prova é a carta e o destino; o vídeo
/// tocando no Safari é provado no **aparelho físico**, separadamente. Tornar a reprodução uma condição do
/// simulador e não conseguir medi-la (o `SFSafariViewController` roda fora do processo e o XCTest não tem ponte de
/// JavaScript) seria substituir a promessa por um mecanismo que não existe.
///
/// Depois: fechar o navegador, voltar ao feed e medir que a **mesma carta** está na **mesma posição** (±2 pt) — a
/// carta que o leitor deixou é a que ele encontra.
///
/// A carta é a testemunha: sem carta de vídeo no orçamento o teste **falha** (nunca pula) e anexa o estado medido,
/// porque uma lacuna nomeada é exatamente o resultado que esta jornada existe para enxergar.
@MainActor
final class VideoCardJourneyUITests: XCTestCase {
    /// O feed que o leitor adiciona. A identidade de mídia de cada carta vem do invólucro do **item**
    /// (`video/mp4` neste feed), nunca do tipo da fonte.
    private static let feedURL = "https://feeds.twit.tv/twit_video_hd.xml"
    private static let unavailableMediaNotices = ["Mídia indisponível nesta compilação",
        "Media unavailable in this build"]
    /// D11: nenhuma variável de fixture pode estar ligada nesta corrida.
    private static let fixtureVariables = ["FEEDMINE_USE_DEVELOPMENT_FEEDS", "FEEDMINE_LOCAL_FEEDS",
        "FEEDMINE_MEDIA_SIMULATION", "FEEDMINE_FIXTURE_MEDIA", "FEEDMINE_FIXTURE_ITEMS",
        "FEEDMINE_ADD_FEED_FIXTURE"]

    /// A carta carrega o próprio id publicado; nenhum outro elemento da árvore carrega um UUID nu.
    private static var cardIdentifier: NSPredicate {
        NSPredicate(format: "identifier MATCHES %@",
            "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")
    }

    private static let journeyBudget: TimeInterval = 900
    private var journeyDeadline = Date.distantFuture

    private func budget(_ requested: TimeInterval) -> TimeInterval {
        max(1, min(requested, journeyDeadline.timeIntervalSinceNow))
    }

    // MARK: - A jornada

    func testTheVideoCardOpensItsOriginAndReturningKeepsTheReadingPosition() async throws {
        let started = Date()
        journeyDeadline = started.addingTimeInterval(Self.journeyBudget)
        var notes: [String] = []
        var failures: [String] = []

        // D11: a corrida tem de ser de rede de verdade. Uma fixture ligada invalidaria a carta publicada.
        let fixtures = Self.fixtureVariables.filter { ProcessInfo.processInfo.environment[$0] == "1" }
        if !fixtures.isEmpty {
            failures.append("D11: a corrida foi lançada com \(fixtures.joined(separator: ",")); mídia de fixture "
                + "não conta como mídia real")
        }

        let app = launched()
        stamp(started, "launch")
        attach(app, name: "0-lancamento")

        // (1) O leitor adiciona o feed pelo caminho do próprio app: menu → Adicionar feed → endereço → Adicionar.
        //     A seleção começa vazia (`FEEDMINE_EMPTY_SELECTION`), o que é um estado que o leitor pode escolher e
        //     que a superfície do app declara; o feed adicionado é então a única fonte da sessão, e o que for
        //     publicado só pode vir dele. O caminho medido é o normal: o menu do leitor e a folha do app.
        XCTAssertTrue(app.staticTexts["feed-empty-title"].waitForExistence(timeout: budget(90)),
            "a corrida começa num leitor sem fontes, que é o estado de onde se adiciona a primeira")
        stamp(started, "empty-state")
        openMenu(app)
        let addFeedEntry = app.buttons.matching(NSPredicate(format: "label IN {'Adicionar feed', 'Add feed'}"))
            .firstMatch
        XCTAssertTrue(addFeedEntry.waitForExistence(timeout: budget(15)),
            "o menu do leitor oferece adicionar um feed")
        addFeedEntry.tap()
        // A folha é provada pelo próprio campo que ela oferece; o título da barra é localizado e já mudou de
        // idioma entre execuções (medido: "Add sources" no simulador em inglês).
        let field = element(app, "add-feed-input")
        XCTAssertTrue(field.waitForExistence(timeout: budget(20)), "a folha de fontes do app abre")
        field.tap()
        field.typeText(Self.feedURL)
        XCTAssertEqual(field.value as? String, Self.feedURL, "o campo recebe o endereço que o leitor digita")
        let addButton = app.buttons["add-feed-add"]
        XCTAssertTrue(addButton.exists && addButton.isEnabled, "a ação de adicionar está disponível")
        addButton.tap()

        let added = element(app, "add-feed-result-added")
        let adopted = added.waitForExistence(timeout: budget(180))
        let addResult = "result=\(adopted ? added.label : "absent") "
            + "sheetError='\(app.staticTexts["add-feed-error"].exists ? app.staticTexts["add-feed-error"].label : "-")'"
        notes.append("add feed: \(addResult)")
        XCTAssertTrue(adopted, "o app adiciona o feed que o leitor digita (\(addResult))")
        if !adopted {
            attach(app, name: "1-folha-sem-resultado")
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "1-folha-arvore"
            tree.lifetime = .keepAlways
            add(tree)
        }
        stamp(started, "feed-added \(addResult)")
        attach(app, name: "1-adicionado")
        app.buttons["add-feed-cancel"].tap()

        // (2) A carta publicada. A sessão é reconstruída com a fonte adicionada quando a folha fecha
        //     (`adoptSelectionChange`), e a primeira publicação não é instantânea: o orçamento cobre a aquisição
        //     do feed, a imagem de cada item e a montagem da edição.
        let published = waitForCards(app, within: budget(420))
        stamp(started, "cards=\(published.count)")
        let firstTitle = published.first.map { title(of: $0) } ?? "-"
        notes.append("published cards visible=\(published.count) first='\(firstTitle)' "
            + "badges=\(published.compactMap { videoBadge(of: $0)?.label })")
        attach(app, name: "2-feed")
        if published.isEmpty {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "2-arvore-sem-cartas"
            tree.lifetime = .keepAlways
            add(tree)
            failures.append("o feed adicionado não publicou nenhuma carta no orçamento "
                + "(loading=\(app.otherElements["feed-loading-surface"].exists), "
                + "empty='\(app.staticTexts["feed-empty-title"].exists ? app.staticTexts["feed-empty-title"].label : "-")')")
        }

        guard let found = findVideoCard(app, within: budget(90)) else {
            attach(app, name: "3-sem-carta-de-video")
            failures.append("D2: nenhuma carta declarou o selo 'Vídeo' depois do feed de vídeo adicionado "
                + "(cartas visíveis=\(visibleCards(app).count), selos="
                + "\(visibleCards(app).compactMap { videoBadge(of: $0)?.label })"
                + ") — sem carta de vídeo não há jornada; a lacuna é reportada, não pulada")
            report(app, started: started, failures: failures, notes: notes)
            return
        }

        _ = bringIntoView(app, identifier: found.identifier, minimum: 0.9)
        let videoCard = self.card(app, identifier: found.identifier)
        let cardFrame = videoCard.frame
        let cardTitle = title(of: videoCard)
        notes.append("video card id=\(found.identifier) title='\(cardTitle)' frame=\(cardFrame)")
        stamp(started, "video-card '\(cardTitle)'")

        // (2a) A identidade é da **carta**: o selo "Vídeo" está dentro do frame dela.
        let badge = videoBadge(of: videoCard)
        XCTAssertNotNil(badge, "D2: a carta declara o selo 'Vídeo' dentro do frame \(cardFrame)")
        if badge == nil {
            failures.append("D2: a carta \(found.identifier) não declara o selo 'Vídeo' dentro do frame")
        }
        // (2b) O player do app não existe para esta carta: nem `card.play`, nem o controle/ação "Tocar".
        let play = playButton(of: videoCard)
        let tocar = videoCard.buttons.matching(NSPredicate(format:
            "label BEGINSWITH %@ OR label BEGINSWITH %@", "Tocar", "Play"))
            .allElementsBoundByIndex.first { $0.exists && cardFrame.contains($0.frame) }
        XCTAssertNil(play, "D2: uma carta de vídeo não oferece o controle visível card.play")
        XCTAssertNil(tocar, "D2: uma carta de vídeo não oferece 'Tocar'")
        if play != nil || tocar != nil {
            failures.append("D2: a carta de vídeo oferece um player (card.play=\(play != nil), "
                + "Tocar='\(tocar?.label ?? "-")')")
        }
        let noticeVisible = Self.unavailableMediaNotices.contains { app.staticTexts[$0].exists }
        XCTAssertFalse(noticeVisible, "D2: o aviso de mídia indisponível não existe em lugar nenhum")
        stamp(started, "identity badge=\(badge?.label ?? "-") play=\(play != nil) tocar=\(tocar?.label ?? "-")")
        attach(app, name: "3-carta-de-video")

        // (3) O destino: o link do **próprio item**, nunca o invólucro de mídia. A expectativa não é um palpite:
        //     o teste lê o feed público que o app adicionou (a mesma URL, sem fixture) e casa a carta com o item
        //     dele pelo título; o link do item é então o alvo esperado. O endereço que o navegador in-app mostra é
        //     comparado a ele — inteiro quando o Safari mostra a URL, pelo host quando mostra só o host — e nunca
        //     pode nomear um arquivo de mídia.
        let feed = await Self.readFeed(URL(string: Self.feedURL)!)
        notes.append("feed items=\(feed.count) links=\(feed.compactMap(\.link).count) "
            + "enclosures=\(feed.flatMap(\.enclosures).count)")
        let item = feed.first { Self.sameTitle($0.title, cardTitle) }
        let itemLink = item?.link
        notes.append("card title matched feed item=" + (item.map { "'\($0.title)' link='\($0.link ?? "-")'" }
            ?? "none"))
        if item == nil {
            failures.append("o título da carta '\(cardTitle)' não casa com nenhum item do feed adicionado; "
                + "a página aberta não pôde ser ligada ao item")
        }
        if let itemLink, let enclosure = Self.enclosure(in: itemLink) {
            failures.append("D2: o link do item é um endereço de mídia (\(enclosure)): '\(itemLink)'")
        }

        _ = bringIntoView(app, identifier: found.identifier, minimum: 0.9)
        let fresh = self.card(app, identifier: found.identifier)
        let open = fresh.buttons["card.open"].firstMatch
        XCTAssertTrue(open.exists && open.isHittable,
            "a carta de vídeo oferece o controle de abertura (frame \(fresh.frame))")
        var address: String?
        var readerHeadline: String?
        if open.exists && open.isHittable {
            open.tap()
            // A carta abre **o que o app tem do item** — a leitura local quando há texto —, e o caminho do leitor
            // para a origem é o controle que essa leitura declara ("Abrir no site"). A origem é medida depois dele;
            // o teste não inventa um toque no corpo da página nem troca o alvo.
            let surfaceDeadline = Date().addingTimeInterval(budget(45))
            var reachedOrigin = false
            while Date() < surfaceDeadline {
                if let headline = app.staticTexts["reading.headline"] as XCUIElement?,
                    headline.exists, !headline.label.isEmpty {
                    readerHeadline = headline.label
                }
                if app.buttons["URL"].exists || app.webViews.firstMatch.exists {
                    reachedOrigin = true
                    break
                }
                let localSite = app.buttons["Abrir no site"].firstMatch
                if localSite.exists && localSite.isHittable {
                    localSite.tap()
                    reachedOrigin = true
                    break
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            notes.append("reader headline='\(readerHeadline ?? "-")' reachedOrigin=\(reachedOrigin)")
            if reachedOrigin { address = browserAddress(app, within: budget(45)) }
        }
        notes.append("destination=\(address ?? "none")")
        // A árvore do navegador é evidência do que o leitor tem: o endereço, os controles e o conteúdo que o
        // Safari in-app expõe. Ela vai anexada mesmo quando o endereço chega, para que a precisão medida (host ou
        // URL inteira) seja auditável sem repetir a corrida.
        let browserTree = XCTAttachment(string: app.debugDescription)
        browserTree.name = address == nil ? "4-arvore-sem-endereco" : "4-arvore-do-navegador"
        browserTree.lifetime = .keepAlways
        add(browserTree)
        stamp(started, "destination=\(address ?? "none")")
        attach(app, name: "4-origem")
        if let address {
            if let enclosure = Self.enclosure(in: address) {
                failures.append("D2: o navegador abriu um endereço de mídia (\(enclosure)): '\(address)'")
            }
            let verdict = itemLink.map { Self.destinationVerdict(address: address, link: $0) }
                ?? .mismatch("o item do feed não declarou link")
            notes.append("destination verdict=\(String(describing: verdict))")
            switch verdict {
            case .matched(let precision):
                notes.append("destination precision=\(precision)")
            case .mismatch(let why):
                failures.append("D2: a carta de vídeo não abriu o link do item — \(why) "
                    + "(endereço='\(address)', link='\(itemLink ?? "-")')")
            }
        } else {
            failures.append("D2: a carta de vídeo não alcançou a origem no navegador in-app no orçamento "
                + "(leitura local='\(readerHeadline ?? "-")')")
        }

        // (3a) O conteúdo aberto é o do item da carta, não uma página genérica: a leitura local declara o título
        //      do item e a página do navegador o expõe quando carrega. A consulta é por contagem de um predicado —
        //      varrer todos os rótulos de uma página que recarrega falha no meio (medido: os elementos somem entre
        //      o snapshot e a leitura, e o XCTest registra um erro por índice).
        let titleProbe = String(cardTitle.prefix(18))
        let readerShowsItem = readerHeadline.map { Self.sameTitle($0, cardTitle) || $0.contains(cardTitle) } ?? false
        let pageShowsItem = app.webViews.staticTexts
            .matching(NSPredicate(format: "label CONTAINS[c] %@", titleProbe)).count > 0
        notes.append("item content: readerHeadline=\(readerShowsItem) browserTitle=\(pageShowsItem) "
            + "webViews=\(app.webViews.count) probe='\(titleProbe)'")
        XCTAssertTrue(readerShowsItem || pageShowsItem,
            "o que abriu é o item da carta ('\(cardTitle)'), não uma página genérica; leitura="
                + "'\(readerHeadline ?? "-")', título na página=\(pageShowsItem)")
        if !(readerShowsItem || pageShowsItem) {
            failures.append("o conteúdo aberto não é o item da carta ('\(cardTitle)'); leitura="
                + "'\(readerHeadline ?? "-")', título na página=\(pageShowsItem)")
        }

        // (3b) A página carregou: o próprio navegador declara `IsPageLoaded` no identificador da `BrowserView`, e
        //      o texto da página expõe o título do item. A barra do Safari in-app mostra só o host (é o que o
        //      leitor tem); o conteúdo do item é o que diz que a página é a correspondente, não uma genérica.
        let browserView = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "BrowserView?")).firstMatch
        var pageLoaded = false
        var pageTitleVisible = false
        let loadDeadline = Date().addingTimeInterval(budget(40))
        while Date() < loadDeadline {
            if browserView.exists && browserView.identifier.contains("IsPageLoaded=true") { pageLoaded = true }
            pageTitleVisible = app.webViews.staticTexts
                .matching(NSPredicate(format: "label CONTAINS[c] %@", titleProbe)).count > 0
            if pageLoaded || pageTitleVisible { break }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        notes.append("browser page loaded=\(pageLoaded) itemTitleOnPage=\(pageTitleVisible) "
            + "probe='\(titleProbe)' browser='\(browserView.exists ? browserView.identifier : "none")'")
        XCTAssertTrue(pageLoaded || pageTitleVisible,
            "a página do item carregou no navegador in-app (loaded=\(pageLoaded), título na página="
                + "\(pageTitleVisible), browser='\(browserView.exists ? browserView.identifier : "none")')")
        if !(pageLoaded || pageTitleVisible) {
            failures.append("a página do item não carregou no navegador in-app no orçamento")
        }

        // (4) A volta: fechar o navegador devolve o leitor ao feed, na **mesma** carta e na mesma posição.
        closeReader(app)
        let restored = restoredCard(app, identifier: found.identifier, expected: cardFrame, within: budget(30))
        if let restored {
            XCTAssertEqual(restored.frame.minY, cardFrame.minY, accuracy: 2,
                "a posição da carta de vídeo é preservada ao voltar (antes \(cardFrame), depois \(restored.frame))")
            XCTAssertEqual(restored.frame.height, cardFrame.height, accuracy: 2,
                "a geometria da carta não mudou ao voltar do navegador")
            if abs(restored.frame.minY - cardFrame.minY) > 2 {
                failures.append("a carta de vídeo voltou \(restored.frame.minY - cardFrame.minY) pt fora da "
                    + "posição (antes \(cardFrame.minY), depois \(restored.frame.minY))")
            }
        } else {
            failures.append("a carta \(found.identifier) não voltou ao feed no frame em que o navegador a deixou "
                + "(esperado \(cardFrame), lido \(card(app, identifier: found.identifier).frame))")
        }
        stamp(started, "return restored=\(restored != nil)")
        attach(app, name: "6-volta")

        report(app, started: started, failures: failures, notes: notes)
    }

    // MARK: - Lançamento

    /// Um namespace novo dá ao run um leitor novo; nenhuma fixture de mídia é ligada. A seleção começa vazia
    /// porque é dela que o leitor adiciona a primeira fonte, e assim o que a sessão publicar só pode vir do feed
    /// que o teste adicionou.
    private func launched() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_EMPTY_SELECTION"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        let extra = app.launchEnvironment.keys.filter {
            $0.hasPrefix("FEEDMINE_") && !["FEEDMINE_RUNTIME_NAMESPACE", "FEEDMINE_EMPTY_SELECTION",
                "FEEDMINE_SKIP_ONBOARDING"].contains($0)
        }
        XCTAssertTrue(extra.isEmpty, "D11: o app foi lançado com \(extra.sorted()); fixtures não contam")
        app.launch()
        return app
    }

    private func openMenu(_ app: XCUIApplication) {
        let menu = app.buttons["more-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: budget(30)), "o cabeçalho oferece o menu do leitor")
        menu.tap()
    }

    // MARK: - O feed e a carta

    private func visibleCards(_ app: XCUIApplication) -> [XCUIElement] {
        let scroll = app.scrollViews.firstMatch
        let viewport = scroll.exists ? scroll.frame : app.windows.firstMatch.frame
        return app.descendants(matching: .any).matching(Self.cardIdentifier).allElementsBoundByIndex
            .filter { element in
                guard element.exists else { return false }
                let frame = element.frame
                return frame.height > 40 && frame.width > viewport.width * 0.75 && viewport.intersects(frame)
            }
    }

    /// A primeira publicação chega em rajada: a contagem é lida depois que ela para por duas leituras seguidas,
    /// e o orçamento é o que limita a espera.
    private func waitForCards(_ app: XCUIApplication, within seconds: TimeInterval) -> [XCUIElement] {
        let deadline = Date().addingTimeInterval(seconds)
        var lastCount = -1
        var stable = 0
        while Date() < deadline {
            let cards = visibleCards(app)
            if !cards.isEmpty && cards.count == lastCount { stable += 1 } else { stable = 0 }
            if stable >= 2 { return cards }
            lastCount = cards.count
            Thread.sleep(forTimeInterval: 1)
        }
        return visibleCards(app)
    }

    /// A carta de vídeo: o selo "Vídeo" **dentro do frame dela**. O feed rola com o gesto do próprio ScrollView
    /// (o arrasto sintético não move este feed, medido na Jornada de mídia).
    private func findVideoCard(_ app: XCUIApplication, within seconds: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let card = visibleCards(app).first(where: { videoBadge(of: $0) != nil }) { return card }
            let feed = app.scrollViews.firstMatch
            guard feed.exists else { break }
            feed.swipeUp(velocity: .slow)
            Thread.sleep(forTimeInterval: 1.2)
        }
        return visibleCards(app).first { videoBadge(of: $0) != nil }
    }

    private func videoBadge(of card: XCUIElement) -> XCUIElement? {
        let frame = card.frame
        return card.staticTexts.matching(NSPredicate(format: "label IN %@", ["Vídeo", "Video"]))
            .allElementsBoundByIndex.first { $0.exists && frame.contains($0.frame) }
    }

    private func playButton(of card: XCUIElement) -> XCUIElement? {
        let frame = card.frame
        return card.buttons.matching(identifier: "card.play").allElementsBoundByIndex
            .first { $0.exists && frame.contains($0.frame) && $0.frame.height >= 40 }
    }

    private func title(of card: XCUIElement) -> String {
        let frame = card.frame
        let identified = card.staticTexts.matching(identifier: "card.title").allElementsBoundByIndex
            .first { $0.exists && frame.contains($0.frame) }
        if let identified { return identified.label }
        return card.staticTexts.allElementsBoundByIndex.first { $0.exists && frame.contains($0.frame) }?.label ?? ""
    }

    private func card(_ app: XCUIApplication, identifier: String) -> XCUIElement {
        element(app, identifier)
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", identifier))
            .firstMatch
    }

    /// A carta depois de a superfície de leitura ir embora: o frame tem de ser o que o feed desenha e ficar assim
    /// por duas leituras. Logo após o fechamento o feed ainda está escalado (~250 pt de largura em vez de 370).
    private func restoredCard(_ app: XCUIApplication, identifier: String, expected: CGRect,
        within seconds: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(seconds)
        var stable = 0
        while Date() < deadline {
            let candidate = card(app, identifier: identifier)
            if candidate.exists {
                let frame = candidate.frame
                let matches = abs(frame.width - expected.width) <= 2 && abs(frame.height - expected.height) <= 2
                stable = matches ? stable + 1 : 0
                if stable >= 2 { return candidate }
            } else {
                stable = 0
            }
            Thread.sleep(forTimeInterval: 0.4)
        }
        return nil
    }

    @discardableResult
    private func bringIntoView(_ app: XCUIApplication, identifier: String, minimum: CGFloat,
        attempts: Int = 3) -> XCUIElement? {
        let feed = app.scrollViews.firstMatch
        for _ in 0..<attempts {
            let element = self.element(app, identifier)
            guard element.exists else { return nil }
            let frame = element.frame
            let view = viewport(app)
            let visible = frame.intersection(view)
            let area = frame.width * frame.height
            let fraction = area > 0 ? visible.width * visible.height / area : 0
            if fraction >= minimum { return element }
            guard feed.exists else { break }
            if frame.midY > view.midY { feed.swipeUp(velocity: .slow) }
            else { feed.swipeDown(velocity: .slow) }
            Thread.sleep(forTimeInterval: 0.8)
        }
        let element = self.element(app, identifier)
        return element.exists ? element : nil
    }

    private func viewport(_ app: XCUIApplication) -> CGRect {
        let window = app.windows.firstMatch.frame
        let scroll = app.scrollViews.firstMatch
        let visible = scroll.exists ? scroll.frame.intersection(window) : window
        return visible.isNull || visible.isEmpty ? window : visible
    }

    // MARK: - O feed adicionado, e o destino

    struct FeedItem {
        let title: String
        let link: String?
        let enclosures: [String]
    }

    /// O feed público que o app adiciona, lido pelo próprio teste: os títulos e os links dos itens são a
    /// expectativa do destino, medida fora do app (a mesma URL, sem fixture). O leitor do app não é consultado:
    /// o que o app declara na tela é medido na interface.
    static func readFeed(_ url: URL, within seconds: TimeInterval = 45) async -> [FeedItem] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = seconds
        configuration.timeoutIntervalForResource = seconds
        let session = URLSession(configuration: configuration)
        guard let (data, _) = try? await session.data(from: url) else { return [] }
        let parser = FeedItemParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.parse()
        return parser.items
    }

    /// O título da carta e o do item podem diferir em espaços e em HTML decodificado; o mesmo item é o que casa
    /// por igualdade ou por prefixo dos dois lados, e um prefixo tem de ser longo o bastante para não ser acaso.
    static func sameTitle(_ left: String, _ right: String) -> Bool {
        let a = normalized(left), b = normalized(right)
        guard a.count > 8, b.count > 8 else { return false }
        return a == b || a.hasPrefix(b) || b.hasPrefix(a)
    }

    private static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Um invólucro de mídia é qualquer extensão que o navegador abriria como arquivo, não como site.
    private static func enclosure(in link: String) -> String? {
        let lowered = link.lowercased()
        let media = [".mp3", ".m4a", ".mp4", ".m4v", ".mov", ".m3u8", ".webm", ".aac", ".wav", ".ogg"]
        return media.first { lowered.contains($0) }
    }

    private func browserAddress(_ app: XCUIApplication, within seconds: TimeInterval) -> String? {
        let control = app.buttons["URL"].firstMatch
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if control.exists {
                let value = String(describing: control.value)
                if !value.isEmpty && value != "nil" { return value }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return nil
    }

    private enum DestinationVerdict: CustomStringConvertible {
        /// O navegador mostrou o link do item. `full` é a URL inteira; `path` é o caminho do item; `host` é a forma
        /// mais fraca que o Safari mostra, e nela só o host é comparável.
        case matched(String)
        case mismatch(String)

        var description: String {
            switch self {
            case .matched(let precision): return "matched(\(precision))"
            case .mismatch(let why): return "mismatch(\(why))"
            }
        }
    }

    /// D2: o endereço é o link do item, nunca o invólucro de mídia. Quando o navegador mostra a URL inteira a
    /// comparação é exata; quando mostra só o host, o host tem de ser o do item e o endereço não pode nomear um
    /// arquivo de mídia.
    private static func destinationVerdict(address: String, link: String) -> DestinationVerdict {
        let shown = address.lowercased(), expected = link.lowercased()
        guard let expectedURL = URL(string: link), let host = expectedURL.host?.lowercased(), !host.isEmpty else {
            return .mismatch("o link do item não é uma URL utilizável: '\(link)'")
        }
        if let media = enclosure(in: shown) {
            return .mismatch("o navegador abriu um endereço de mídia (\(media)): '\(address)'")
        }
        if shown.contains(expected) { return .matched("full") }
        let path = expectedURL.path.lowercased()
        if path.count > 1, shown.contains(path) { return .matched("path") }
        guard shown.contains(host) else {
            return .mismatch("o endereço '\(address)' não é o host do link do item '\(link)'")
        }
        return .matched("host")
    }

    // MARK: - A volta

    /// A volta do navegador: o controle de fechar do Safari (o botão que o `SFSafariViewController` desenha) ou o
    /// gesto. Só conta como volta quando o conteúdo web não está mais na árvore.
    private func closeReader(_ app: XCUIApplication) {
        if app.buttons["reading.close"].exists {
            app.buttons["reading.close"].tap()
        } else {
            for label in ["Fechar", "Close", "Done", "Concluído"] {
                let button = app.buttons[label].firstMatch
                if button.exists && button.isHittable { button.tap(); break }
            }
        }
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if !app.staticTexts["reading.headline"].exists && !app.webViews.firstMatch.exists {
                // A superfície sair da árvore não é o fim da transição: o feed ainda está escalado por um instante.
                Thread.sleep(forTimeInterval: 1.2)
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        app.swipeDown(velocity: .fast)
    }

    // MARK: - Resumo e evidência
    /// O relógio da corrida, impresso nos pontos em que ela pode parar. O log do XCTest é a única testemunha de
    /// onde uma corrida ficou: sem estas linhas um bloqueio de oito minutos parece uma espera de orçamento.
    private func stamp(_ started: Date, _ step: String) {
        print("VIDEO_CARD_JOURNEY t=\(Int(Date().timeIntervalSince(started).rounded()))s \(step)")
    }


    private func report(_ app: XCUIApplication, started: Date, failures: [String], notes: [String]) {
        let elapsed = Int(Date().timeIntervalSince(started).rounded())
        let summary = "VIDEO_CARD_JOURNEY result=\(failures.isEmpty ? "PASS" : "FAIL") elapsed=\(elapsed)s"
        print(summary)
        for note in notes { print("VIDEO_CARD_JOURNEY note \(note)") }
        let artifact = XCTAttachment(string: summary + "\n" + notes.joined(separator: "\n"))
        artifact.name = "VIDEO_CARD_JOURNEY summary"
        artifact.lifetime = .keepAlways
        add(artifact)
        if failures.isEmpty {
            print("VIDEO_CARD_JOURNEY PASS")
        } else {
            for failure in failures { print("VIDEO_CARD_JOURNEY FAIL \(failure)") }
            XCTFail("VIDEO_CARD_JOURNEY FAIL: " + failures.joined(separator: " | "))
        }
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// O leitor mínimo do RSS público que o app adiciona: título, link e invólucros de cada item.
///
/// `qualifiedName` separa o `<title>` do item do `itunes:title` do mesmo item (o feed da TWiT traz os dois, e o
/// primeiro a chegar é o do iTunes): o que o app publica como título da carta é o `<title>` do RSS, e é ele que
/// casa a carta com o item do feed.
private final class FeedItemParser: NSObject, XMLParserDelegate {
    private struct Draft {
        var title = ""
        var link: String?
        var enclosures: [String] = []
    }

    private var current: Draft?
    private var text = ""
    private(set) var items: [VideoCardJourneyUITests.FeedItem] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        text = ""
        if elementName == "item" {
            current = Draft()
            return
        }
        guard current != nil else { return }
        if elementName == "enclosure", let url = attributeDict["url"] {
            current?.enclosures.append(url)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let decoded = String(data: CDATABlock, encoding: .utf8) { text += decoded }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?) {
        guard var item = current else {
            text = ""
            return
        }
        let plain = qName == nil || qName == elementName
        if elementName == "title", plain, item.title.isEmpty {
            item.title = Self.trimmed(text)
        }
        if elementName == "link", plain, item.link == nil {
            item.link = Self.trimmed(text)
        }
        if elementName == "item" {
            items.append(VideoCardJourneyUITests.FeedItem(title: item.title, link: item.link,
                enclosures: item.enclosures))
            current = nil
        } else {
            current = item
        }
        text = ""
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
