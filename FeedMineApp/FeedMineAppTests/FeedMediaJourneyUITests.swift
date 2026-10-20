import XCTest

/// **A jornada de mídia real** — o que a bateria de fixtures não podia responder.
///
/// A direção do arquiteto (2026-10-20): uma corrida longa só de texto não é argumento de qualidade. Esta jornada
/// percorre o **catálogo publicado que o app entrega** (nenhuma fixture local, rede de verdade — D11), responde ao
/// onboarding como um leitor novo e **conta** o que viu: quantas cartas, quantas com imagem desenhada, um item de
/// áudio tocando e o que o vídeo faz, além das funções visitadas. O resumo sai numa linha só (`MEDIA_JOURNEY`).
///
/// Testemunhas estruturais que tornam a afirmação observável (nenhuma delas depende de estado interno):
///  * o slot da imagem declara `«card-id»-media-image` **somente** quando há um bitmap decodificado nele
///    (`card.image?.cgImage != nil`, o tipo cujo `cgImage` é não-opcional); o placeholder do mesmo slot declara
///    `«card-id»-media-slot`. A asserção lê a existência do primeiro, o frame não-zero e a **interseção com o
///    viewport** — uma imagem abaixo da dobra não é uma imagem que o leitor viu;
///  * o relógio do player declara `full-player-position` em segundos (`MiniPlayerBar.swift:190`), para que "o
///    progresso avança" não dependa de porcentagem arredondada, e a barra declara `mini-player-card` com o id
///    publicado da carta (`MiniPlayerBar.swift:88`), para que a identidade do item seja a carta tocada e não um
///    título que duas cartas podem compartilhar.
///
/// D2 (build 54): vídeo não tem player nativo. A exigência é identidade de vídeo, abrir a origem, nunca oferecer
/// "Tocar" e não existir o aviso "Mídia indisponível nesta compilação". Onde o produto ainda não tem a identidade,
/// o teste fica **vermelho** e nomeia a lacuna com arquivo:linha — nunca troca a exigência por uma mais fraca.
///
/// A jornada declara um orçamento total (`journeyBudget`): cada espera é limitada pelo tempo que resta e o resumo
/// falha se o relógio passar de seis minutos. O teste **não** aceita silêncio: se um tipo de mídia não aparecer no
/// orçamento, ele falha com o motivo medido e anexa a tela.
@MainActor
final class FeedMediaJourneyUITests: XCTestCase {
    /// A carta carrega o próprio id publicado como identificador (`FeedItemView`), e é ele que diz que a **mesma**
    /// carta voltou — nenhum outro elemento da árvore carrega um UUID nu.
    private static var cardIdentifier: NSPredicate {
        NSPredicate(format: "identifier MATCHES %@",
            "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")
    }

    /// O aviso que a build 54 **não pode ter em lugar nenhum** (D2). O `case .media` de `FeedAssociation.perform`
    /// passou a executar o alvo (AppComposition.swift:2330-2335), então a frase só pode aparecer como resíduo: se
    /// aparecer na árvore, é uma regressão e o teste a nomeia.
    private static let unavailableMediaNotice = "Mídia indisponível nesta compilação"

    /// O orçamento medido da jornada. Cada espera recebe `min(pedido, restante)`, então uma rede lenta encurta a
    /// medida em vez de transformar o teste numa corrida de dez minutos; o resumo falha se passar de seis minutos.
    private static let journeyBudget: TimeInterval = 330
    private static let journeyLimit: TimeInterval = 360

    /// D11: uma imagem gerada por fixture não é prova. O processo do runner é o primeiro lugar onde a variável
    /// apareceria (`TEST_RUNNER_` prefix), e o `launchEnvironment` do app é conferido de novo em `launched()`.
    private static let fixtureVariables = ["FEEDMINE_USE_DEVELOPMENT_FEEDS", "FEEDMINE_LOCAL_FEEDS",
        "FEEDMINE_MEDIA_SIMULATION", "FEEDMINE_FIXTURE_MEDIA", "FEEDMINE_FIXTURE_ITEMS"]

    private var journeyDeadline = Date.distantFuture

    private func budget(_ requested: TimeInterval) -> TimeInterval {
        max(1, min(requested, journeyDeadline.timeIntervalSinceNow))
    }

    // MARK: - A jornada

    func testTheShippedCatalogueDeliversAnImageAnAudioItemAndAVideoItem() throws {
        let started = Date()
        journeyDeadline = started.addingTimeInterval(Self.journeyBudget)
        var failures: [String] = []
        var functionsVisited: Set<String> = []
        var playerInstalled = false
        var audioPlayed = false
        let videoPlayed = false
        var verdicts: [String: Bool] = ["feed": false, "image": false, "audio": false, "video": false]
        var playbackNotes: [String] = []

        // D11: nenhuma variável de fixture pode estar ligada. Se estiver, a prova de imagem/áudio não vale e o
        // teste diz isso antes de medir qualquer coisa.
        let fixtures = Self.fixtureVariables.filter { ProcessInfo.processInfo.environment[$0] == "1" }
        playbackNotes.append("fixtures=\(fixtures.isEmpty ? "off" : "ON \(fixtures)") (D11)")
        if !fixtures.isEmpty {
            failures.append("D11: a corrida foi lançada com \(fixtures.joined(separator: ",")); mídia de fixture "
                + "não conta como mídia real")
        }

        let app = launched()
        attach(app, name: "0-lancamento")

        // (0) O primeiro encontro, respondido como o leitor responde: boas-vindas → compositor → feed.
        XCTAssertTrue(app.staticTexts["welcome-headline"].waitForExistence(timeout: budget(90)),
            "o app encontra o leitor antes do feed")
        app.buttons["welcome-shape"].tap()
        XCTAssertTrue(app.staticTexts["composer-subtitle"].waitForExistence(timeout: budget(60)),
            "o primeiro passo declara o que coleta")
        let composer = app.otherElements["onboarding"].scrollViews.firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: budget(30)))
        // O leitor **responde** ao primeiro passo em vez de aceitar um default que pode não nomear nada: duas
        // escolhas de idioma distintas (o chip é o mesmo controle que o leitor toca). Sem ao menos uma, o perfil
        // enviado à descoberta não nomeia interesse nenhum e o app abre "Nenhuma fonte habilitada" — medido nesta
        // máquina na primeira corrida, com o perfil gravado em `languages: []`.
        var answered: Set<String> = []
        for _ in 0..<2 {
            let chip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "composer-language-"))
                .allElementsBoundByIndex.first {
                    $0.exists && $0.isHittable && !answered.contains($0.identifier)
                        && !$0.identifier.contains("-regions-") && !$0.identifier.contains("-variant-")
                }
            guard let chip else { break }
            answered.insert(chip.identifier)
            chip.tap()
            Thread.sleep(forTimeInterval: 0.4)
        }
        playbackNotes.append("onboarding languages answered=\(answered.sorted())")
        let openFeed = app.buttons["composer-open-feed"]
        for _ in 0..<6 where !openFeed.isHittable { composer.swipeUp() }
        XCTAssertTrue(openFeed.isHittable, "a ação do próprio primeiro passo abre o feed")
        openFeed.tap()

        // (1) O feed publicado pelo catálogo real. A primeira publicação não é instantânea (medido no aparelho:
        //     ~50 s até a primeira oferta); o orçamento é generoso e o número medido vai para o resumo.
        let firstCards = waitForFirstScreen(app, within: budget(150))
        if firstCards.isEmpty {
            let state = app.staticTexts["feed-empty-title"].exists
                ? "feed-empty-title='\(app.staticTexts["feed-empty-title"].label)'"
                : "loading='\(app.otherElements["feed-loading-surface"].exists)'"
            playbackNotes.append("feed after onboarding: cards=0 \(state)")
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "1-arvore-sem-cartas"
            tree.lifetime = .keepAlways
            add(tree)
        }
        XCTAssertFalse(firstCards.isEmpty,
            "o catálogo entregue publica cartas para a jornada — sem elas não há o que medir")
        let cardsSeen = firstCards.count
        verdicts["feed"] = !firstCards.isEmpty
        let images = firstCards.filter { isImageDrawn(of: $0, in: app) }
        attach(app, name: "1-primeira-tela")

        // (2) Uma carta com imagem: o bitmap decodificado está no slot, o slot está dentro da carta, e a carta
        //     abre e volta à **mesma posição**. O frame antes/depois é a medida da preservação de posição.
        // A imagem falhar **não** encerra a jornada: o áudio e o vídeo ainda têm de ser medidos, e uma publicação
        // que chega só com texto é exatamente o resultado que o arquiteto pediu para enxergar.
        if let imageCard = images.first {
            // A imagem que o leitor vê: a carta tem de estar de fato na dobra **antes** da medida. Medido na
            // primeira corrida: a carta estava a 20 pt da dobra, o toque em `card.open` fez o framework rolar o
            // feed e a volta do leitor mostrou a carta a 567 pt de distância — uma posição "perdida" que era só a
            // rolagem do toque.
            let imageID = imageCard.identifier
            let prepared = bringIntoView(app, identifier: imageID, minimum: 0.95)
            playbackNotes.append("image card brought into view: "
                + "\(prepared.map { "\($0.frame)" } ?? "unavailable") viewport=\(viewport(app))")
            let settledCard = card(app, identifier: imageID)
            let marker = mediaImage(of: settledCard, in: app)
            let slotNonZero = marker.exists && marker.frame.width > 1 && marker.frame.height > 1
            XCTAssertTrue(slotNonZero, "a imagem da carta existe com frame não-zero (\(marker.frame))")
            let cardFrame = settledCard.frame
            let slotInsideCard = cardFrame.intersects(marker.frame)
            XCTAssertTrue(slotInsideCard,
                "o slot da imagem está dentro do frame da carta (slot \(marker.frame), carta \(cardFrame))")
            let slotVisible = marker.frame.intersection(viewport(app))
            // A correção do auditor: o slot tem de **intersectar o viewport** com área visível. Uma carta abaixo
            // da dobra existe na árvore e não é uma imagem que o leitor viu.
            let slotInViewport = !slotVisible.isNull && slotVisible.width * slotVisible.height > 1
            XCTAssertTrue(slotInViewport,
                "o slot da imagem intersecta o viewport com área visível (slot \(marker.frame), "
                    + "viewport \(viewport(app)))")
            print("MEDIA_JOURNEY image card=\(imageID) cardFrame=\(cardFrame) slot=\(marker.frame) "
                + "visibleArea=\(slotVisible.width * slotVisible.height)")

            settledCard.buttons["card.open"].firstMatch.tap()
            functionsVisited.insert("open")
            var openedReader = false
            if waitForReader(app, within: budget(40)) {
                openedReader = true
                attach(app, name: "3-leitor")
                closeReader(app)
                functionsVisited.insert("back")
            } else {
                failures.append("a carta com imagem não abriu leitura no orçamento da jornada")
            }
            var positionPreserved = false
            if let returned = restoredCard(app, identifier: imageID, expected: cardFrame, within: budget(20)) {
                positionPreserved = abs(returned.frame.minY - cardFrame.minY) <= 2
                    && abs(returned.frame.height - cardFrame.height) <= 2
                XCTAssertEqual(returned.frame.minY, cardFrame.minY, accuracy: 2,
                    "a posição da carta é preservada ao voltar do leitor "
                        + "(antes \(cardFrame), depois \(returned.frame))")
                XCTAssertEqual(returned.frame.height, cardFrame.height, accuracy: 2,
                    "a geometria da carta não mudou ao voltar do leitor")
            } else {
                failures.append("a carta \(imageID) não voltou ao frame em que o leitor a deixou "
                    + "(esperado \(cardFrame), lido \(card(app, identifier: imageID).frame))")
            }
            verdicts["image"] = slotNonZero && slotInsideCard && slotInViewport && openedReader
                && positionPreserved
        } else {
            attach(app, name: "2-sem-imagem")
            failures.append("nenhuma das \(cardsSeen) cartas visíveis declarou -media-image com bitmap "
                + "decodificado; imagens reais não chegaram no orçamento")
            playbackNotes.append("image gap: cards=\(cardsSeen) cardsWithImage=0; a publicação chegou sem "
                + "bitmap decodificado no orçamento")
            verdicts["image"] = false
        }

        // (3) Duas funções curtas, registradas no resumo. Nenhuma delas substitui a medida de mídia. O toque só
        //     acontece com o controle realmente hittable: uma interação com elemento coberto é falha do teste,
        //     não medida (medido: o primeiro card.bookmark ainda estava sob a transição do leitor).
        if let bookmarkCard = visibleCards(app).first(where: {
            $0.buttons["card.bookmark"].exists && $0.buttons["card.bookmark"].isHittable
        }) {
            let bookmark = bookmarkCard.buttons["card.bookmark"]
            let before = bookmark.value as? String
            bookmark.tap()
            let changed = NSPredicate(format: "value != %@", before ?? "")
            let waiter = XCTNSPredicateExpectation(predicate: changed, object: bookmark)
            if XCTWaiter.wait(for: [waiter], timeout: 5) == .completed { functionsVisited.insert("save") }
        }
        if app.buttons["search-button"].waitForExistence(timeout: 5) {
            app.buttons["search-button"].tap()
            if app.textFields["reader-search-field"].waitForExistence(timeout: 5) {
                functionsVisited.insert("search")
                app.buttons["reader-search-cancel"].tap()
            }
        }

        // (4) FILTRO: a folha do próprio app é aberta e fechada. **O tipo de conteúdo não é oferecido**: o
        //     conjunto `ReaderFilterCriterion.enforceable` desta build é `[preset, languages, mood]`
        //     (ReaderFilter.swift:168), então não há como isolar podcasts/vídeos por filtro. O teste registra a
        //     ausência como fato medido em vez de inventar um caminho.
        if app.buttons["filter-button"].waitForExistence(timeout: 10) {
            app.buttons["filter-button"].tap()
            if app.buttons["filter-done"].waitForExistence(timeout: 15) {
                functionsVisited.insert("filter")
                let contentTypes = app.buttons.matching(
                    NSPredicate(format: "identifier BEGINSWITH %@", "content-type-")).count
                playbackNotes.append("filter content-type-options=\(contentTypes) "
                    + "(enforceable=[preset,languages,mood])")
                app.buttons["filter-done"].tap()
            }
        }

        // (5) ÁUDIO: o critério é o que o toque **faz**, não o selo que a carta desenha. A seleção anterior por
        //     selo escolheu duas vezes um artigo: o AX mostrou o "Podcast" de uma carta vizinha respondendo pela
        //     outra (a consulta por descendentes de uma carta não delimita de forma confiável no SwiftUI). Agora
        //     cada candidato é tocado e só conta quando o player aparece; um hero de artigo abre leitura e é
        //     descartado com essa medida, nunca reclassificado como áudio.
        playbackNotes.append("audio path code: hero emits openMedia (FeedItemCardView.swift:238-240); "
            + "FeedAssociation.perform executes the card's own target (AppComposition.swift:2330-2335) through "
            + "ReaderMediaCoordinator.toggle (ReaderMediaCoordinator.swift:32-40); the payload is the item's "
            + "enclosure candidate (AppComposition.swift:2948-2952) published as mediaPlayback "
            + "(AppComposition.swift:3184)")
        var audioCard: XCUIElement?
        var audioStart: PlaybackStart?
        var audioAttempts: [String] = []
        var tried: Set<String> = []
        let audioDeadline = Date().addingTimeInterval(budget(110))
        while audioStart == nil && Date() < audioDeadline {
            guard let candidate = findPlayableCard(app, within: budget(35), excluding: tried) else { break }
            tried.insert(candidate.identifier)
            let candidateTitle = title(of: candidate, in: app)
            let result = startPlayback(app, card: candidate)
            switch result {
            case .playing:
                audioCard = candidate
                audioStart = result
            case .article, .notice, .unavailable:
                audioAttempts.append(describe(result, title: candidateTitle))
            }
        }
        playbackNotes.append("audio attempts=\(audioAttempts.count) [\(audioAttempts.joined(separator: " | "))]")
        if let audioCard, let audioStart {
            let expectedTitle = title(of: audioCard, in: app)
            switch audioStart {
            case .playing(let observedTitle):
                playerInstalled = true
                attach(app, name: "5-audio-tocando")
                let measured = measurePlayback(app, expectedTitle: expectedTitle,
                    expectedCardID: audioCard.identifier, within: budget(20))
                audioPlayed = measured.countsAsPlayed
                verdicts["audio"] = audioPlayed
                playbackNotes.append("audio expected='\(expectedTitle)' id='\(audioCard.identifier)' "
                    + "observed='\(observedTitle)' \(measured.description)")
                if !measured.identityMatches {
                    failures.append("o player não nomeia a carta tocada: esperado '\(expectedTitle)'/"
                        + "id '\(audioCard.identifier)', mini='\(observedTitle)'/card '\(measured.playerCard)', "
                        + "completo='\(measured.fullTitle)'")
                }
                if !measured.advancedWhilePlaying {
                    failures.append("o áudio abriu mas os segundos não aumentaram no orçamento da medida "
                        + "(\(measured.description))")
                }
                if !measured.frozenWhilePaused {
                    failures.append("a pausa não congelou o relógio: "
                        + "\(measured.pausedFirst.map(String.init) ?? "-")→"
                        + "\(measured.pausedSecond.map(String.init) ?? "-") s")
                }
                if !measured.advancedAfterResume {
                    failures.append("o resume não voltou a avançar o relógio: "
                        + "\(measured.pausedSecond.map(String.init) ?? "-")→"
                        + "\(measured.resumed.map(String.init) ?? "-") s")
                }
            case .article, .notice, .unavailable:
                break // the loop only selects a candidate that played
            }
        } else {
            attach(app, name: "5-audio-sem-player")
            failures.append("nenhuma carta publicada abriu o player no orçamento de áudio; tentativas: "
                + "\(audioAttempts.isEmpty ? "nenhuma" : audioAttempts.joined(separator: " | "))")
        }

        // O estado da oferta de áudio, medido no feed misto: quantas cartas tocáveis visíveis não oferecem alvo
        // de toque nenhum. Uma carta `mediaPlayback` sem imagem não tem hero (FeedItemCardView.swift:238-240) e
        // o corpo dela emite `.open`; o único caminho para "Tocar" é a ação de acessibilidade, que um toque comum
        // não alcança. É um fato do produto, e não se confunde com "não há áudio no catálogo".
        let podcastCards = visibleCards(app).filter { podcastBadge(of: $0) != nil }
        let withoutTouchTarget = podcastCards.filter { heroIdentifier(of: $0, in: app) == nil }.count
        playbackNotes.append("audio offers: podcastsVisible=\(podcastCards.count) "
            + "withoutTouchTarget=\(withoutTouchTarget)")
        if withoutTouchTarget > 0 {
            playbackNotes.append("audio gap: \(withoutTouchTarget) carta(s) tocável(is) sem imagem não têm hero; "
                + "o corpo emite .open e só a ação de acessibilidade nomeia Tocar "
                + "(FeedItemCardView.swift:107-108,238-240)")
        }

        // (6) VÍDEO — o critério D2, medido onde é medível e vermelho onde o produto ainda não o cumpre.
        //     D2 (build 54): nenhum player nativo; uma carta de vídeo identifica-se como vídeo, abre a origem, não
        //     oferece "Tocar", e o aviso "Mídia indisponível nesta compilação" não existe em lugar nenhum.
        //
        //     A única cláusula que esta build hoje consegue medir é a ausência do aviso. As outras três falham na
        //     primeira premissa — não existe identidade de vídeo para observar:
        //       * `PresentationPrimaryActionKind` só tem `externalURL`, `mediaPlayback`, `localContentDetail`
        //         (PresentationCard.swift:28-32), e a carta apresentada não carrega mime/classe de mídia;
        //       * todo `mediaPlayback` é desenhado como áudio: `isAudio` é o próprio kind
        //         (FeedItemCardView.swift:58) e o selo é "Podcast" (FeedItemCardView.swift:327);
        //       * "abrir a origem" só existe para `primaryActionKind == "externalURL"`
        //         (ReaderActionCoordinator.swift:87-90), então uma carta de vídeo não tem caminho de origem;
        //       * e toda carta tocável oferece a ação "Tocar" (FeedItemCardView.swift:108), que D2 proíbe em vídeo.
        //     O player é só `AVPlayer()` sem camada (MediaPlaybackAdapter.swift:35): tocar um vídeo tocaria o som
        //     sem imagem. Por isso `videoPlayed` fica 0 e a lacuna é nomeada, nunca mascarada.
        attach(app, name: "6-video-lacuna")
        let videoNamedCards = visibleCards(app).filter {
            $0.staticTexts.matching(NSPredicate(format: "label == %@", "Vídeo")).count > 0
        }.count
        let noticeVisible = app.staticTexts[Self.unavailableMediaNotice].exists
        XCTAssertFalse(noticeVisible,
            "D2: o aviso '\(Self.unavailableMediaNotice)' não existe em lugar nenhum")
        playbackNotes.append("video identity=absent cardsNamedVideo=\(videoNamedCards) "
            + "noticeVisible=\(noticeVisible) surface=AVPlayer-only (MediaPlaybackAdapter.swift:35)")
        playbackNotes.append("video D2 unverifiable clauses: identity (PresentationCard.swift:28-32), origin "
            + "(ReaderActionCoordinator.swift:87-90), no-Tocar (FeedItemCardView.swift:108); badge is always "
            + "'Podcast' (FeedItemCardView.swift:327); the notice's key still ships unused at "
            + "Localizable.xcstrings:1921")
        if noticeVisible {
            failures.append("D2: o aviso '\(Self.unavailableMediaNotice)' reapareceu na árvore")
        }
        verdicts["video"] = false
        failures.append("D2 vermelho — não há identidade de vídeo no produto para afirmar 'vídeo exibido': "
            + "PresentationPrimaryActionKind não tem caso de vídeo (PresentationCard.swift:28-32); todo "
            + "mediaPlayback desenha o selo 'Podcast' (FeedItemCardView.swift:58,327); a origem só é alcançável "
            + "para externalURL (ReaderActionCoordinator.swift:87-90); 'Tocar' é oferecido a toda carta tocável "
            + "(FeedItemCardView.swift:108); e o player é AVPlayer sem camada "
            + "(MediaPlaybackAdapter.swift:35). Das cláusulas D2, só a ausência do aviso é medível hoje "
            + "(noticeVisible=\(noticeVisible))")

        if !playerInstalled {
            attach(app, name: "8-estado-final")
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "8-arvore-final"
            tree.lifetime = .keepAlways
            add(tree)
        }

        report(app, started: started, failures: failures, functions: functionsVisited, verdicts: verdicts,
            cardsSeen: cardsSeen, cardsWithImage: images.count, imagesDrawn: images.count,
            audioPlayed: audioPlayed, videoPlayed: videoPlayed, notes: playbackNotes)
    }

    // MARK: - Lançamento

    /// **O catálogo entregue e a rede de verdade.** Nada de `FEEDMINE_USE_DEVELOPMENT_FEEDS`,
    /// `FEEDMINE_LOCAL_FEEDS`, `FEEDMINE_FIXTURE_*` ou `FEEDMINE_MEDIA_SIMULATION`: a mídia tem de vir do que o
    /// app publica a partir das fontes reais. Um namespace novo dá ao run um leitor novo, que é quem responde ao
    /// primeiro passo; nada do leitor real deste Mac é tocado.
    private func launched() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        // D11: o app recebe **só** o namespace. Nenhuma fixture, nenhum feed local, nenhuma rede bloqueada: a
        // mídia provada aqui tem de vir da rede e do catálogo publicado.
        let extra = app.launchEnvironment.keys
            .filter { $0.hasPrefix("FEEDMINE_") && $0 != "FEEDMINE_RUNTIME_NAMESPACE" }
        XCTAssertTrue(extra.isEmpty, "D11: o app foi lançado com \(extra.sorted()); fixtures não contam")
        // **Nenhuma força de onboarding.** O namespace novo já não tem `hasSeenOnboarding`, então o gate abre
        // sozinho; `FEEDMINE_ONBOARDING=1` é uma força que re-apresenta o gate se a task de launch rodar de novo
        // (medido: a superfície voltou sobre o feed depois de fechar o leitor, e o feed ficou inalcançável).
        app.launch()
        return app
    }

    // MARK: - O feed e a imagem

    private func visibleCards(_ app: XCUIApplication) -> [XCUIElement] {
        let scroll = app.scrollViews.firstMatch
        let viewport = scroll.exists ? scroll.frame : app.windows.firstMatch.frame
        return app.descendants(matching: .any).matching(Self.cardIdentifier).allElementsBoundByIndex
            .filter { element in
                guard element.exists else { return false }
                let frame = element.frame
                // A feed card fills the column. The onboarding preview cards are wraps of the same published
                // cards and carry the same identity; they are ~260 pt wide at this device and must not be counted
                // twice (measured: 249.8 pt during the onboarding→feed handoff).
                return frame.height > 40 && frame.width > viewport.width * 0.75 && viewport.intersects(frame)
            }
    }

    /// The card the reader actually has in the feed, after the reading surface has finished going away: the
    /// frame has to be back to the width the feed draws and stay there for two consecutive reads. The reader is
    /// a transition, and measured right after the close its feed is still scaled (249.8 pt wide instead of
    /// 370.5 pt) — comparing that frame with the pre-open one would report a position change that never happened.
    private func restoredCard(_ app: XCUIApplication, identifier: String, expected: CGRect,
        within seconds: TimeInterval = 20) -> XCUIElement? {
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

    /// A primeira tela é contada **depois** que a rajada parou e a imagem de ao menos uma carta foi decodificada:
    /// a publicação chega em rajada e o bitmap chega depois dela, então uma contagem no primeiro instante mediria
    /// o relógio (medido: 1 carta às t=15 s, ainda sem `-media-image`; a imagem chega em seguida). O orçamento
    /// cobre a espera e o número medido vai para o resumo.
    private func waitForFirstScreen(_ app: XCUIApplication, within seconds: TimeInterval) -> [XCUIElement] {
        let deadline = Date().addingTimeInterval(seconds)
        var lastCount = -1
        var stable = 0
        while Date() < deadline {
            let cards = visibleCards(app)
            let hasDrawnImage = cards.contains { isImageDrawn(of: $0, in: app) }
            if !cards.isEmpty && hasDrawnImage { stable = cards.count == lastCount ? stable + 1 : 0 }
            else { stable = 0 }
            if stable >= 2 { return cards }
            lastCount = cards.count
            Thread.sleep(forTimeInterval: 1)
        }
        return visibleCards(app)
    }

    private func mediaImage(of card: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        element(app, card.identifier + "-media-image")
    }

    /// O viewport desenhado: a janela recortada pela lista. O slot tem de **estar dentro dele**, não apenas
    /// pertencer a uma carta que existe na árvore — a árvore admitida desenha cartas fora da dobra, e uma imagem
    /// lá embaixo não é uma imagem que o leitor viu.
    private func viewport(_ app: XCUIApplication) -> CGRect {
        let window = app.windows.firstMatch.frame
        let scroll = app.scrollViews.firstMatch
        let visible = scroll.exists ? scroll.frame.intersection(window) : window
        return visible.isNull || visible.isEmpty ? window : visible
    }

    /// Traz o frame de um elemento para o viewport desenhado com ao menos `minimum` da área visível, usando o
    /// gesto do próprio feed. Um toque num elemento que o framework tem de rolar até a tela move o feed, e a
    /// jornada leria essa rolagem como posição perdida (medido: a carta com imagem estava a 20 pt da dobra e a
    /// volta do leitor a mostrou 567 pt adiante). Devolve o elemento como o feed o desenhou depois de assentar.
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
            // O gesto de arrasto sintético não move este feed (medido: a carta ficou parada em y = -391). O gesto
            // do próprio ScrollView move; o limite de tentativas é o que impede o swipe cego de passar do alvo
            // (medido: seis swipes levaram uma carta de 193 pt para y = -453).
            if frame.midY > view.midY { feed.swipeUp(velocity: .slow) }
            else { feed.swipeDown(velocity: .slow) }
            Thread.sleep(forTimeInterval: 0.8)
        }
        let element = self.element(app, identifier)
        return element.exists ? element : nil
    }

    /// A testemunha da imagem é o **próprio slot** que o card declara quando há bitmap decodificado nele. A
    /// existência é o fato; o frame não-zero prova que ele foi desenhado com geometria, não registrado vazio; e a
    /// interseção com o viewport prova que o leitor podia vê-lo.
    private func isImageDrawn(of card: XCUIElement, in app: XCUIApplication) -> Bool {
        let marker = mediaImage(of: card, in: app)
        guard marker.exists else { return false }
        let frame = marker.frame
        guard frame.width > 1 && frame.height > 1 && card.frame.intersects(frame) else { return false }
        let visible = frame.intersection(viewport(app))
        return !visible.isNull && visible.width * visible.height > 1
    }

    private func title(of card: XCUIElement, in app: XCUIApplication) -> String {
        // A consulta por descendentes de uma carta não é confiável para delimitar: medido no AX, a carta do
        // artigo 'Francia…' respondia por um selo 'Podcast' que pertencia à carta seguinte. O frame da própria
        // carta é o limite que não depende de como o SwiftUI agrupa a árvore.
        let frame = card.frame
        let identified = card.staticTexts.matching(identifier: "card.title").allElementsBoundByIndex
            .first { $0.exists && frame.contains($0.frame) }
        if let identified { return identified.label }
        return card.staticTexts.allElementsBoundByIndex.first { $0.exists && frame.contains($0.frame) }?.label ?? ""
    }

    /// O selo "Podcast" que pertence a **esta** carta: existir e cair dentro do frame dela. Sem essa checagem o
    /// teste escolheu um artigo (Alto Nivel) e o hero dele abriu leitura em vez de tocar.
    private func podcastBadge(of card: XCUIElement) -> XCUIElement? {
        let frame = card.frame
        return card.staticTexts.matching(NSPredicate(format: "label == %@", "Podcast"))
            .allElementsBoundByIndex.first { $0.exists && frame.contains($0.frame) }
    }

    private func card(_ app: XCUIApplication, identifier: String) -> XCUIElement {
        element(app, identifier)
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", identifier))
            .firstMatch
    }

    // MARK: - Leitura

    private func waitForReader(_ app: XCUIApplication, within seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if app.staticTexts["reading.headline"].exists || app.webViews.firstMatch.exists { return true }
            Thread.sleep(forTimeInterval: 1)
        }
        return false
    }

    /// A volta do leitor: o controle do leitor local, o botão do navegador in-app (Safari's own `close`), ou o
    /// gesto. Só conta como volta quando a superfície não está mais na árvore.
    private func closeReader(_ app: XCUIApplication) {
        if app.buttons["reading.close"].exists {
            app.buttons["reading.close"].tap()
        } else {
            for label in ["Fechar", "Close", "Done", "Concluído"] {
                let button = app.buttons[label].firstMatch
                if button.exists && button.isHittable { button.tap(); break }
            }
        }
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if !app.staticTexts["reading.headline"].exists && !app.webViews.firstMatch.exists {
                // The surface being gone from the tree is not the end of its transition: the feed is still
                // scaled while it settles back (measured: a 249.8 pt-wide card right after the close). The
                // caller measures the card only after this pause and after the frame matches the pre-open one.
                Thread.sleep(forTimeInterval: 1.2)
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        app.swipeDown(velocity: .fast)
    }

    // MARK: - Filtros e mídia

    /// Uma carta tocável declara o selo "Podcast" na linha da fonte (`isAudio` é `mediaPlayback`). Cartas sem
    /// payload tocável não o declaram, e tocá-las abriria o artigo — o teste não confunde uma coisa com a outra.
    ///
    /// O alvo de toque para tocar é o **hero**. Uma carta tocável que a publicação decidiu `textOnly` não tem
    /// hero: o `openingSurface` dela declara a ação `Tocar` só como ação de acessibilidade, e um toque comum abre
    /// o artigo (`emit(.open)`). Por isso o teste procura, primeiro, uma carta tocável com hero; a sem hero fica
    /// como último recurso, para que a lacuna seja medida e não escondida.
    private func findPlayableCard(_ app: XCUIApplication, within seconds: TimeInterval,
        excluding tried: Set<String> = []) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(seconds)
        var fallback: XCUIElement?
        while Date() < deadline {
            let candidates = visibleCards(app)
                .filter { podcastBadge(of: $0) != nil && !tried.contains($0.identifier) }
            if let card = candidates.first(where: { heroIdentifier(of: $0, in: app) != nil }) { return card }
            if fallback == nil { fallback = candidates.first }
            let feed = app.scrollViews.firstMatch
            if feed.exists { feed.swipeUp(velocity: .slow) }
            Thread.sleep(forTimeInterval: 1.2)
        }
        return fallback
    }

    /// O slot visual da carta, decodificado ou ainda em placeholder — o alvo que o hero entrega a `openMedia`.
    private func heroIdentifier(of card: XCUIElement, in app: XCUIApplication) -> String? {
        for suffix in ["-media-image", "-media-slot"] {
            let identifier = card.identifier + suffix
            let candidate = element(app, identifier)
            if candidate.exists && candidate.frame.height > 1 { return identifier }
        }
        return nil
    }

    private enum PlaybackStart {
        case playing(String)
        /// O toque abriu leitura: a carta não é tocável (ou o hero não é o alvo de mídia dela).
        case article
        case notice(String)
        case unavailable(String)
    }

    private func describe(_ outcome: PlaybackStart, title: String) -> String {
        switch outcome {
        case .playing(let observed): return "\(title)=PLAYING(\(observed))"
        case .article: return "\(title)=abriuLeitura"
        case .notice(let text): return "\(title)=aviso(\(text))"
        case .unavailable(let reason): return "\(title)=semPlayer(\(reason))"
        }
    }

    /// Toca a **área da mídia** da carta (o hero): ela é o alvo de `openMedia` no card; o texto abaixo abre o
    /// artigo e por isso não é usado. O player (barra) é a primeira coisa a aparecer.
    ///
    /// O hero tem de estar na dobra **antes** do toque. Medido: tocar uma coordenada de um hero que o framework
    /// precisava rolar até a tela não abriu player nenhum — o toque caiu fora do alvo. Depois do toque, a espera é
    /// de 25 s porque o adapter só instala o item depois de `AVURLAsset.load(.isPlayable)` responder
    /// (MediaPlaybackAdapter.swift:276-284): uma URL de rede lenta não é uma carta sem mídia.
    private func startPlayback(_ app: XCUIApplication, card: XCUIElement) -> PlaybackStart {
        guard let hero = heroIdentifier(of: card, in: app) else {
            // A lacuna medida, não inferida: a carta tocável sem imagem não tem hero, então o toque do leitor cai
            // no corpo dela. O teste faz esse toque e diz o que abriu — leitura, ou nada. A carta é trazida à
            // dobra antes, porque um controle sob a borda não é hittable (medido: a primeira tentativa devolveu
            // 'sem corpo tocável' com a carta na dobra inferior).
            _ = bringIntoView(app, identifier: card.identifier, minimum: 0.9)
            let settled = self.card(app, identifier: card.identifier)
            let frame = settled.frame
            let body = settled.buttons.matching(identifier: "card.open").allElementsBoundByIndex
                .first { $0.exists && frame.contains($0.frame) }
            guard let body, body.isHittable else {
                return .unavailable("a carta tocável não tem hero nem corpo tocável hittable "
                    + "(frame \(frame), viewport \(viewport(app)))")
            }
            body.tap()
            let openedReading = waitForReader(app, within: budget(15))
            let playerAppeared = app.otherElements["mini-player"].exists
            if openedReading {
                attach(app, name: "5-audio-corpo-abre-leitura")
                closeReader(app)
            }
            let playerSurface = playerAppeared ? "sim" : "não"
            if openedReading {
                return .article
            }
            return .unavailable("a carta tocável não tem hero (publicação textOnly, sem imagem): o toque no "
                + "corpo não abriu leitura nem player (player=\(playerSurface)); o único caminho para 'Tocar' é "
                + "a ação de acessibilidade, que um toque comum não alcança "
                + "(FeedItemCardView.swift:107-108,238-240)")
        }
        guard let target = bringIntoView(app, identifier: hero, minimum: 0.9) else {
            return .unavailable("o hero \(hero) não pôde ser trazido ao viewport")
        }
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let player = app.otherElements["mini-player"]
        let notice = app.staticTexts[Self.unavailableMediaNotice]
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            if player.exists { return .playing(app.staticTexts["mini-player-title"].label) }
            // A leitura abrir é o resultado **medido** de um hero que não é alvo de mídia: a carta é um artigo.
            // Ele é descartado como candidato, nunca contado como áudio.
            if app.staticTexts["reading.headline"].exists || app.webViews.firstMatch.exists {
                closeReader(app)
                return .article
            }
            if notice.exists { return .notice(notice.label) }
            let toast = app.otherElements["reader-toast"]
            if toast.exists {
                let text = toast.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
                if !text.isEmpty { return .notice(text) }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return .unavailable("o player não apareceu em 25 s (hero \(hero) em \(target.frame)); sem item, o app "
            + "não tem superfície para o erro de mídia (FeedMineApp.swift:308)")
    }

    private struct PlaybackMeasurement {
        let identityMatches: Bool
        let fullTitle: String
        let playerCard: String
        let first: Int?
        let second: Int?
        let pausedFirst: Int?
        let pausedSecond: Int?
        let resumed: Int?
        let error: String?

        var advancedWhilePlaying: Bool {
            guard let first, let second else { return false }
            return second > first
        }
        var frozenWhilePaused: Bool {
            guard let pausedFirst, let pausedSecond else { return false }
            return pausedSecond <= pausedFirst
        }
        var advancedAfterResume: Bool {
            guard let pausedSecond, let resumed else { return false }
            return resumed > pausedSecond
        }
        var countsAsPlayed: Bool {
            error == nil && identityMatches && advancedWhilePlaying && frozenWhilePaused && advancedAfterResume
        }
        var description: String {
            "title='\(fullTitle)' card='\(playerCard)' identity=\(identityMatches) seconds=\(first.map(String.init) ?? "-")→"
                + "\(second.map(String.init) ?? "-") paused=\(pausedFirst.map(String.init) ?? "-")→"
                + "\(pausedSecond.map(String.init) ?? "-") resumed=\(resumed.map(String.init) ?? "-")"
                + (error.map { " error='\($0)'" } ?? "")
        }
    }

    /// O relógio do player é a medida fina: porcentagem arredondada não distingue 3 s de 11 s numa hora de áudio.
    /// O teste lê **segundos** (não a string), exige aumento estrito enquanto toca, congela durante a pausa e
    /// volta a aumentar no resume — e exige que o item que o player nomeia seja a carta que o leitor tocou.
    private func measurePlayback(_ app: XCUIApplication, expectedTitle: String, expectedCardID: String,
        within seconds: TimeInterval) -> PlaybackMeasurement {
        let bar = app.otherElements["mini-player"]
        guard bar.exists else {
            return PlaybackMeasurement(identityMatches: false, fullTitle: "", playerCard: "", first: nil,
                second: nil, pausedFirst: nil, pausedSecond: nil, resumed: nil, error: "no-mini-player")
        }
        let playerTitle = app.staticTexts["mini-player-title"].label
        let playerCard = app.staticTexts["mini-player-card"].label
        bar.tap()
        let full = app.otherElements["full-player"]
        guard full.waitForExistence(timeout: budget(10)) else {
            return PlaybackMeasurement(identityMatches: false, fullTitle: playerTitle, playerCard: playerCard,
                first: nil, second: nil, pausedFirst: nil, pausedSecond: nil, resumed: nil,
                error: "no-full-player")
        }
        defer { if app.buttons["full-player-close"].exists { app.buttons["full-player-close"].tap() } }
        let fullTitle = app.staticTexts["full-player-title"].label
        let identityMatches = !expectedTitle.isEmpty && playerTitle == expectedTitle
            && fullTitle == expectedTitle && playerCard == expectedCardID
        let clock = element(app, "full-player-position")
        guard clock.waitForExistence(timeout: budget(15)) else {
            let error = app.staticTexts["full-player-error"].exists
                ? app.staticTexts["full-player-error"].label : "no-duration-clock"
            return PlaybackMeasurement(identityMatches: identityMatches, fullTitle: fullTitle,
                playerCard: playerCard, first: nil, second: nil, pausedFirst: nil, pausedSecond: nil,
                resumed: nil, error: error)
        }
        let first = Self.seconds(clock.label)
        let second = waitForClockIncrease(clock: clock, above: first, within: budget(seconds))
        guard let second, let first, second > first else {
            return PlaybackMeasurement(identityMatches: identityMatches, fullTitle: fullTitle,
                playerCard: playerCard, first: first, second: second, pausedFirst: nil, pausedSecond: nil,
                resumed: nil, error: "position-did-not-advance")
        }
        let toggle = app.buttons["full-player-toggle"]
        guard toggle.exists && toggle.isHittable else {
            return PlaybackMeasurement(identityMatches: identityMatches, fullTitle: fullTitle,
                playerCard: playerCard, first: first, second: second, pausedFirst: nil, pausedSecond: nil,
                resumed: nil, error: "no-pause-control")
        }
        toggle.tap()
        Thread.sleep(forTimeInterval: 0.5)
        let pausedFirst = Self.seconds(clock.label)
        // A janela da pausa é declarada: 5 s. Se o relógio subir nela, a pausa não congelou a reprodução.
        Thread.sleep(forTimeInterval: 5)
        let pausedSecond = Self.seconds(clock.label)
        toggle.tap()
        let resumed = waitForClockIncrease(clock: clock, above: pausedSecond, within: budget(seconds))
        return PlaybackMeasurement(identityMatches: identityMatches, fullTitle: fullTitle,
            playerCard: playerCard, first: first, second: second, pausedFirst: pausedFirst,
            pausedSecond: pausedSecond, resumed: resumed, error: nil)
    }

    private func waitForClockIncrease(clock: XCUIElement, above value: Int?,
        within seconds: TimeInterval) -> Int? {
        guard let value else { return nil }
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let current = Self.seconds(clock.label), current > value { return current }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return Self.seconds(clock.label)
    }

    /// `m:ss` or `h:mm:ss` (FullPlayerView.clock) in seconds. A string that changes but keeps the same second is
    /// not evidence of playback, and neither is a percentage rounded to the same integer.
    private static func seconds(_ clock: String) -> Int? {
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2: return parts[0] * 60 + parts[1]
        default: return nil
        }
    }

    // MARK: - Resumo e evidência

    private func report(_ app: XCUIApplication, started: Date, failures: [String], functions: Set<String>,
        verdicts: [String: Bool], cardsSeen: Int, cardsWithImage: Int, imagesDrawn: Int, audioPlayed: Bool,
        videoPlayed: Bool, notes: [String]) {
        var allFailures = failures
        let elapsed = Int(Date().timeIntervalSince(started).rounded())
        // A linha única pedida pelo arquiteto: o que a jornada viu, e se ela foi só texto (nenhuma imagem
        // desenhada, nenhum áudio, nenhum vídeo).
        let textOnly = imagesDrawn == 0 && !audioPlayed && !videoPlayed
        let summary = "MEDIA_JOURNEY cards=\(cardsSeen) cardsWithImage=\(cardsWithImage) "
            + "imagesDrawn=\(imagesDrawn) audioPlayed=\(audioPlayed ? 1 : 0) "
            + "videoPlayed=\(videoPlayed ? 1 : 0) "
            + "functions=[\(functions.sorted().joined(separator: ","))] "
            + "textOnly=\(textOnly ? 1 : 0) elapsed=\(elapsed)s"
        let criteria = ["feed", "image", "audio", "video"].map { name in
            "\(name)=\(verdicts[name] == true ? "PASS" : "FAIL")"
        }.joined(separator: " ")
        print(summary)
        print("MEDIA_JOURNEY criteria \(criteria)")
        for note in notes { print("MEDIA_JOURNEY note \(note)") }
        if elapsed > Int(Self.journeyLimit) {
            allFailures.append("a jornada levou \(elapsed) s, acima do limite de \(Int(Self.journeyLimit)) s")
        }
        let artifact = XCTAttachment(string: summary + "\n" + criteria + "\n"
            + notes.joined(separator: "\n"))
        artifact.name = "MEDIA_JOURNEY summary"
        artifact.lifetime = .keepAlways
        add(artifact)
        if allFailures.isEmpty {
            print("MEDIA_JOURNEY PASS")
        } else {
            for failure in allFailures { print("MEDIA_JOURNEY FAIL \(failure)") }
            XCTFail("MEDIA_JOURNEY FAIL: " + allFailures.joined(separator: " | "))
        }
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
