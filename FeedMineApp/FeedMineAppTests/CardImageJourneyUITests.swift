import UIKit
import XCTest

/// **"Imagens precisam aparecer"** — a jornada que a bateria não media.
///
/// Nenhum teste da V2 afirmava que uma imagem foi **desenhada**: os dois desenhos do slot de um card
/// (`FeedItemCardView.placeholderView` e `decodedImage`) são decorativos e estão fora da árvore de
/// acessibilidade, então nenhuma asserção de árvore pode responder por eles — só o desenho pode. E as fontes de
/// desenvolvimento da V2 não declaravam mídia nenhuma, então a jornada nem era construível. Este arquivo faz as
/// duas coisas.
///
/// O app é lançado com o fixture de mídia do próprio app (`FEEDMINE_FIXTURE_MEDIA=image`): cada item passa a
/// declarar um `<enclosure>` (RSS) e um `"image"` (JSON Feed) apontando para um PNG magenta de 16:9 que o próprio
/// processo serve — sem rede, sem servidor, e percorrendo o caminho de produção inteiro: candidato, busca,
/// materialização, decodificação e o slot congelado do card. A cor é a testemunha: magenta não é desenhado por
/// nenhuma paleta, placeholder, texto ou chrome do app, e o **controle** deste mesmo arquivo mede a mesma coisa
/// numa corrida sem a declaração de mídia, encontrando zero pixels da testemunha. É isso que torna o número da
/// jornada atribuível à imagem, e não "há algo ali".
///
/// Três afirmações, que são as três metades que faltavam da doutrina "o feed é sagrado — card montado, imagem
/// aparecendo, nada se movendo sozinho":
///  1. a imagem é **desenhada**, com a geometria 16:9 congelada no topo da carta;
///  2. o frame da carta **não muda** depois que a imagem está ali — nem quando o resto do burst entra;
///  3. a imagem **sobrevive** a sair e voltar: a carta é retirada da janela admitida e volta com a mesma
///     identidade, a mesma geometria e o mesmo desenho.
///
/// **Isto não conserta um defeito de imagem.** Medido no iPhone do dono (build de desenvolvimento, catálogo
/// público, uso normal): 40 cards publicados, 19 `hero` + 21 `thumbnail`, 0 `textOnly`, todos com blob no disco —
/// a produção **já mostra imagens**. O que faltava era a **testemunha**: nenhuma asserção da bateria olhava o
/// desenho. Por isso o controle deste arquivo não é "a imagem não aparece" e sim duas corridas do mesmo app em
/// que **a mesma amostra** é feita com e sem o bitmap: (i) o teste do controle, com a fixture que não declara
/// mídia (as cartas ficam text-only, como o censo das fontes de desenvolvimento já mostrava), mede **zero** pixels
/// da testemunha na janela inteira; (ii) a corrida do controle positivo em que só o desenho do bitmap é retirado
/// (`decodedImage` em `FeedItemCardView`, edição local, nunca commitada) mantém a carta, o slot e a geometria
/// exatamente iguais e troca a tinta pela do **placeholder** — e a asserção desta jornada falha ali, com a mesma
/// técnica de amostragem. Failing-before, passing-after, mesma régua.
///
/// A medida de pixels exige screenshot, e screenshot no aparelho não existe hoje (`idevicescreenshot`:
/// `Could not start screenshotr service`, e não há janela de espelhamento) — esta jornada roda **no simulador**,
/// por `XCUIScreenshotProviding` (`XCUIElement.screenshot()`), e é aqui que ela é declarada.
@MainActor
final class CardImageJourneyUITests: XCTestCase {
    /// A carta carrega o próprio id publicado como identificador (`FeedItemView`), e é ele que diz que a **mesma**
    /// carta voltou — nenhum outro elemento da árvore carrega um UUID nu. (Computado: um `NSPredicate` guardado
    /// num `static let` não é sendable, e cada uso constrói o seu.)
    private static var cardIdentifier: NSPredicate {
        NSPredicate(format: "identifier MATCHES %@",
            "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")
    }

    /// A identidade que o leitor vê é o título, e o fixture nomeia os seus ("BBC World story 1"). É um regex
    /// sobre a string: um `NSPredicate` de KVC espera o **elemento** (é lá que `label` é uma chave), não o texto.
    private static func isFixtureTitle(_ label: String) -> Bool {
        label.range(of: "^BBC (World|Science) story [0-9]+$", options: .regularExpression) != nil
    }

    /// **Edição mais funda que uma janela**, o arranjo já provado em `ArticleReadingDiagnosisUITests`: com os seis
    /// itens por feed do default o fixture dá doze cartas, a janela cobre o conteúdo INTEIRO e uma carta nunca sai
    /// — "sair e voltar" seria uma re-projeção, não uma viagem. Noventa e cinco itens por feed dão ~190 cartas.
    private static let itemsPerFeed = "95"

    // MARK: - Lançamento

    private func launched(declaringImages: Bool, items: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["FEEDMINE_FIXTURE_ITEMS"] = items ?? Self.itemsPerFeed
        // A prova da janela admitida (`feed-window-proof`) é o instrumento que diz se a carta foi de fato
        // retirada. Ligada só aqui: nenhuma corrida comum paga o custo do traço.
        app.launchEnvironment["FEEDMINE_TRACE_CAPTURE"] = "1"
        app.launchEnvironment["FEEDMINE_FIXTURE_MEDIA"] = declaringImages ? "image" : "off"
        app.launch()
        return app
    }

    // MARK: - O controle

    /// **A mesma medida, sem nenhuma imagem declarada.** É o primeiro controle, e o que torna a cor da testemunha
    /// atribuível: se o app desenhasse magenta por qualquer outro motivo (paleta, placeholder, texto, chrome), o
    /// controle a encontraria. Ele não encontra nenhuma — e as cartas aqui são as text-only que o censo das fontes
    /// de desenvolvimento já registrava (`mediaKind: "text"`, 12 cartas sem mídia), o que também reconstrói que a
    /// lacuna não era um defeito de desenho: era a fixture não declarar imagem nenhuma.
    func testWithNoImageDeclaredNothingInTheWindowCarriesTheWitnessColour() throws {
        let app = launched(declaringImages: false, items: "6")
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 180), "o feed abre")
        guard let card = awaitTrackableCard(app, within: 180) else {
            return XCTFail("o fixture publica cartas para o controle olhar")
        }
        XCTAssertTrue(card.exists, "a carta do controle está desenhada")

        let window = drawnImage(in: app.windows.firstMatch)
        XCTAssertEqual(window.witnessPixels, 0,
            "sem imagem declarada, a cor da testemunha não pode aparecer em lugar nenhum da janela "
                + "(\(window.witnessPixels) pixels de \(window.sampledPixels) amostrados) — se aparecesse, a "
                + "medida da jornada não estaria medindo a imagem")
    }

    // MARK: - A jornada

    func testAnImageIsDrawnInTheCardAndSurvivesTheBurstAndTheWayBack() throws {
        let app = launched(declaringImages: true)
        let feed = app.scrollViews.firstMatch
        XCTAssertTrue(feed.waitForExistence(timeout: 180), "o feed abre com o conteúdo que o leitor já tem")

        guard let opening = arrangement(app, within: 180) else {
            return XCTFail("o fixture com mídia precisa publicar duas cartas inteiramente visíveis para acompanhar")
        }
        let identifier = opening.tracked.identifier
        let first = opening.tracked
        attach(app, name: "1-carta-com-a-imagem")
        print("JOURNEY first frame=\(first.frame) witness=\(first.drawn.witnessPixels)/\(first.drawn.sampledPixels) "
            + "bounds=\(first.drawn.bounds) spacing=\(String(describing: opening.spacing))")

        // (1) A imagem está desenhada — e o desenho é o dela.
        XCTAssertGreaterThan(first.drawn.fraction, 0.4,
            "o slot do hero é ~62% da carta; a imagem do fixture tem de estar desenhada ali, não em alguns pixels "
                + "(\(first.drawn.witnessPixels)/\(first.drawn.sampledPixels))")
        let band = first.drawn.bounds
        XCTAssertGreaterThan(band.width, first.frame.width * 0.85,
            "o slot do hero vai de borda a borda da carta (tinta \(band.width) pt de \(first.frame.width) pt)")
        XCTAssertEqual(Double(band.height / band.width), 9.0 / 16.0, accuracy: 0.03,
            "a geometria desenhada é a congelada na publicação (16:9), não a de outra imagem qualquer")
        XCTAssertLessThanOrEqual(band.minY, 4,
            "o hero é a primeira coisa da carta: a imagem está no topo, não empurrada para o meio")

        // Todos os outros cards inteiramente visíveis também estão prontos: "o feed só contém conteúdo pronto —
        // card montado, imagem aparecendo". Um card visível com o slot vazio seria imagem quebrada.
        let unprepared = trackableCards(app).filter { $0.identifier != identifier }
            .filter { drawnImage(in: $0).witnessPixels == 0 }
        XCTAssertEqual(unprepared.count, 0,
            "\(unprepared.count) cartas visíveis estão sem a imagem que declararam")

        // (2) O frame não muda depois que a imagem está ali: o resto do burst entra, e o que o leitor vê fica onde
        //     estava. O instrumento é a própria janela admitida, que para de mudar.
        let settled = awaitSettledWindow(app, within: 120)
        print("JOURNEY settled window=\(settled.prefix(120))")
        guard let after = arrangement(app, around: identifier) else {
            return XCTFail("a carta acompanhada continua desenhada depois do burst")
        }
        assertSameGeometry(after.tracked, as: first, because: "o burst entrou sem mover a carta que o leitor via")
        assertSameArrangement(after, as: opening, because: "o burst não reordenou nem re-layoutou o que já estava")
        attach(app, name: "2-depois-do-burst")

        // (3) A imagem sobrevive a sair e voltar: a carta sai da **árvore desenhada** (a lista solta o que está
        //     longe) e volta, com a mesma identidade, a mesma geometria e o mesmo desenho. Medido nesta corrida: a
        //     janela **admitida** mantém o head (`keepsAdmittedHead`), então o instrumento da saída é a própria
        //     árvore — e o `stillAdmitted` abaixo é relatado, não exigido, para que a medida diga o que é.
        var rounds = 0
        var leftTheTree = false
        while rounds < 40, !leftTheTree {
            feed.swipeUp(velocity: .slow)
            rounds += 1
            Thread.sleep(forTimeInterval: 0.3)
            leftTheTree = !card(app, identifier: identifier).exists
        }
        print("JOURNEY away rounds=\(rounds) stillAdmitted=\(admittedIDs(app).contains(identifier))")
        XCTAssertTrue(leftTheTree,
            "INCOMPLETO: a carta acompanhada não saiu da árvore desenhada em \(rounds) gestos — sem essa saída a "
                + "volta não prova nada, e execução incompleta nunca é PASS")
        attach(app, name: "3-longe-da-carta")

        var backRounds = 0
        var restored = false
        while backRounds < 40, !restored {
            feed.swipeDown(velocity: .slow)
            backRounds += 1
            Thread.sleep(forTimeInterval: 0.3)
            let candidate = card(app, identifier: identifier)
            restored = candidate.exists && candidate.frame.height > 0 && candidate.frame.intersects(feed.frame)
        }
        XCTAssertTrue(restored, "a carta retirada tem de voltar quando o leitor retorna (em \(backRounds) gestos)")

        // Volta até o **topo**: a primeira medida foi feita com o leitor no começo do feed. A posição absoluta não
        // é comparável (medido: o topo depois de rolar fica 16 pt abaixo do lançamento, que é o inset da barra, não
        // conteúdo) — por isso a comparação de arranjo é feita no **espaçamento**, que não depende do offset.
        var previous = card(app, identifier: identifier).frame
        for _ in 0..<20 {
            feed.swipeDown(velocity: .slow)
            Thread.sleep(forTimeInterval: 0.5)
            let current = card(app, identifier: identifier).frame
            if abs(current.minY - previous.minY) < 1 { break }
            previous = current
        }
        guard let returned = arrangement(app, around: identifier) else {
            return XCTFail("a carta retirada voltou à árvore mas não a um arranjo inteiramente visível")
        }
        attach(app, name: "4-de-volta")
        print("JOURNEY returned frame=\(returned.tracked.frame) witness=\(returned.tracked.drawn.witnessPixels)/"
            + "\(returned.tracked.drawn.sampledPixels) bounds=\(returned.tracked.drawn.bounds) "
            + "spacing=\(String(describing: returned.spacing))")
        XCTAssertGreaterThan(returned.tracked.drawn.fraction, 0.4,
            "a imagem está de volta com a carta — ela nunca virou text-only nem placeholder no caminho "
                + "(\(returned.tracked.drawn.witnessPixels)/\(returned.tracked.drawn.sampledPixels))")
        assertSameGeometry(returned.tracked, as: first, because: "a carta que sai e volta é a mesma, no mesmo lugar")
        assertSameArrangement(returned, as: opening, because: "a volta ao topo redesenha o mesmo arranjo")
    }

    // MARK: - A medida

    /// O desenho dentro do frame deste elemento: quantos pixels amostrados carregam a cor da testemunha e onde
    /// eles estão — em pontos, **nas coordenadas do próprio elemento**, para que a medida não dependa de onde a
    /// rolagem está.
    private struct DrawnImage {
        let witnessPixels: Int
        let sampledPixels: Int
        let bounds: CGRect

        var fraction: Double { sampledPixels == 0 ? 0 : Double(witnessPixels) / Double(sampledPixels) }
    }

    private struct Measurement {
        let identifier: String
        let frame: CGRect
        let drawn: DrawnImage
    }

    /// A carta acompanhada e o **espaçamento até a carta seguinte**: o espaçamento é a medida de conteúdo que não
    /// depende de onde a rolagem está, então é ela que é comparável entre o lançamento e a volta ao topo.
    private struct Arrangement {
        let tracked: Measurement
        let neighbourID: String?
        let spacing: CGFloat?
    }

    private func measurement(of element: XCUIElement) -> Measurement {
        Measurement(identifier: element.identifier, frame: element.frame, drawn: drawnImage(in: element))
    }

    private func arrangement(_ app: XCUIApplication, around identifier: String? = nil,
        within seconds: TimeInterval = 60) -> Arrangement? {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            let cards = trackableCards(app)
            let tracked = identifier.map { card(app, identifier: $0) } ?? cards.first
            if let tracked, tracked.exists, tracked.frame.height > 40,
                let neighbour = cards.first(where: { $0.identifier != tracked.identifier }) {
                let value = measurement(of: tracked)
                return Arrangement(tracked: value, neighbourID: neighbour.identifier,
                    spacing: neighbour.frame.minY - value.frame.minY)
            }
            Thread.sleep(forTimeInterval: 1)
        } while Date() < deadline
        return nil
    }

    /// A cor da testemunha: o núcleo do magenta do fixture, com a folga que a gestão de cor impõe. O PNG do
    /// fixture é escrito em sRGB, e o campo sólido chega à tela convertido — **medido** no desenho da carta:
    /// `#F4F` domina (255 pixels de vermelho e azul, verde entre 64 e 79), embora o fixture declare (255, 0, 255).
    /// A folga de 96 no verde é essa medida, e quem responde por ela não deixar passar mais nada é o **controle**:
    /// na mesma corrida, numa janela inteira sem mídia declarada, esta função encontra **zero** pixels (as cores
    /// dominantes ali são a superfície clara do cartão `#EED`, com verde ≥ 224).
    private static func isWitness(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Bool {
        red >= 232 && green <= 96 && blue >= 232
    }

    /// Lê os pixels que **o app desenhou** dentro do frame deste elemento. `XCUIElement.screenshot()` é a tela
    /// recortada nesse frame, em pixels de tela; a leitura é feita a cada `stride` pixels (frações importam, não
    /// contagens absolutas) e o resultado volta em pontos do elemento.
    private func drawnImage(in element: XCUIElement, stride: Int = 2) -> DrawnImage {
        let screenshot = element.screenshot().image
        guard let source = screenshot.cgImage else {
            return DrawnImage(witnessPixels: 0, sampledPixels: 0, bounds: .null)
        }
        let width = source.width, height = source.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return DrawnImage(witnessPixels: 0, sampledPixels: 0, bounds: .null) }

        var witness = 0
        var sampled = 0
        var minX = width, minY = height, maxX = -1, maxY = -1
        var histogram: [UInt32: Int] = [:]
        for y in Swift.stride(from: 0, to: height, by: stride) {
            for x in Swift.stride(from: 0, to: width, by: stride) {
                let index = (y * width + x) * 4
                let red = pixels[index], green = pixels[index + 1], blue = pixels[index + 2]
                sampled += 1
                histogram[(UInt32(red >> 4) << 8) | (UInt32(green >> 4) << 4) | UInt32(blue >> 4), default: 0] += 1
                guard Self.isWitness(red, green, blue) else { continue }
                witness += 1
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        // As cores que o desenho realmente tem, para que uma testemunha errada se descubra por medição e não por
        // suposição (foi assim que se descobriu que os primeiros bytes saíam (255, 64, 255)).
        let dominant = histogram.sorted { $0.value > $1.value }.prefix(5)
            .map { "\(Self.describe($0.key))=\($0.value)" }.joined(separator: " ")
        print("JOURNEY drawn \(width)x\(height)px sampled=\(sampled) dominant=\(dominant)")

        let scale = Double(screenshot.scale)
        let bounds = witness == 0 ? CGRect.null : CGRect(x: Double(minX) / scale, y: Double(minY) / scale,
            width: Double(maxX - minX + stride) / scale, height: Double(maxY - minY + stride) / scale)
        return DrawnImage(witnessPixels: witness, sampledPixels: sampled, bounds: bounds)
    }

    private static func describe(_ key: UInt32) -> String {
        String(format: "#%1X%1X%1X", (key >> 8) & 0xF, (key >> 4) & 0xF, key & 0xF)
    }

    private func assertSameGeometry(_ later: Measurement, as earlier: Measurement, because reason: String) {
        XCTAssertEqual(later.identifier, earlier.identifier, "a identidade da carta não muda (\(reason))")
        XCTAssertEqual(later.frame.width, earlier.frame.width, accuracy: 0.5, "largura (\(reason))")
        XCTAssertEqual(later.frame.height, earlier.frame.height, accuracy: 0.5, "altura (\(reason))")
        XCTAssertNotEqual(later.drawn.bounds, .null, "a imagem continua desenhada (\(reason))")
        XCTAssertEqual(later.drawn.bounds.minX, earlier.drawn.bounds.minX, accuracy: 1.5, "o slot (\(reason))")
        XCTAssertEqual(later.drawn.bounds.minY, earlier.drawn.bounds.minY, accuracy: 1.5, "o slot (\(reason))")
        XCTAssertEqual(later.drawn.bounds.width, earlier.drawn.bounds.width, accuracy: 1.5, "o slot (\(reason))")
        XCTAssertEqual(later.drawn.bounds.height, earlier.drawn.bounds.height, accuracy: 1.5, "o slot (\(reason))")
    }

    private func assertSameArrangement(_ later: Arrangement, as earlier: Arrangement, because reason: String) {
        guard let before = earlier.spacing, let now = later.spacing else {
            return XCTFail("o espaçamento entre as duas cartas visíveis tinha de ser medido nos dois momentos")
        }
        XCTAssertEqual(later.neighbourID, earlier.neighbourID,
            "a carta seguinte é a mesma, não outra no lugar dela (\(reason))")
        XCTAssertEqual(now, before, accuracy: 0.5, "o espaçamento entre as cartas (\(reason))")
    }

    // MARK: - O arranjo

    private func card(_ app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
    }

    /// A área em que uma carta está **inteiramente** visível e desimpedida: abaixo da barra de navegação (medida
    /// na própria árvore, não um número inventado) e dentro da janela. Uma carta meio coberta apareceria coberta
    /// no screenshot do próprio elemento, e a medida de pixels seria de outra coisa.
    private func unobstructedViewport(_ app: XCUIApplication) -> CGRect {
        let window = app.windows.firstMatch.frame
        let navigation = app.navigationBars.firstMatch
        let top = navigation.exists ? navigation.frame.maxY : window.minY
        let viewport = CGRect(x: window.minX, y: min(top + 8, window.maxY), width: window.width,
            height: max(0, window.maxY - top - 8))
        // Medido: as cartas saem em x = -0,25 pt (o arredondamento do recorte do cartão), então "inteiramente
        // visível" tem de tolerar uma fração de ponto — sem isso nenhuma carta passa e o teste não mede nada.
        return viewport.insetBy(dx: -1, dy: -1)
    }

    /// As cartas do fixture inteiramente visíveis e desimpedidas, na ordem da árvore.
    private func trackableCards(_ app: XCUIApplication) -> [XCUIElement] {
        let viewport = unobstructedViewport(app)
        return app.descendants(matching: .any).matching(Self.cardIdentifier).allElementsBoundByIndex
            .filter { element in
                guard element.exists else { return false }
                let frame = element.frame
                guard frame.height > 40, viewport.contains(frame) else { return false }
                return element.staticTexts.allElementsBoundByIndex.contains { Self.isFixtureTitle($0.label) }
            }
    }

    @discardableResult
    private func awaitTrackableCard(_ app: XCUIApplication, within seconds: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            if let element = trackableCards(app).first { return element }
            Thread.sleep(forTimeInterval: 1)
        } while Date() < deadline
        return nil
    }

    /// Os ids admitidos, como a própria tela os publica: primeiro campo de `feed-window-proof`.
    private func admittedIDs(_ app: XCUIApplication) -> String {
        let proof = app.staticTexts["feed-window-proof"]
        guard proof.exists else { return "" }
        return proof.label.components(separatedBy: ";").first ?? ""
    }

    /// Espera o burst assentar: a **janela admitida** para de mudar. O rótulo inteiro não serve — ele carrega
    /// contadores que mudam sozinhos —, então só o campo `ids=` é comparado.
    @discardableResult
    private func awaitSettledWindow(_ app: XCUIApplication, within seconds: TimeInterval) -> String {
        XCTAssertTrue(app.staticTexts["feed-window-proof"].waitForExistence(timeout: 60),
            "a prova da janela admitida tem de existir (FEEDMINE_TRACE_CAPTURE)")
        let deadline = Date().addingTimeInterval(seconds)
        var last = admittedIDs(app)
        var stableSince = Date()
        while Date() < deadline {
            let current = admittedIDs(app)
            if current != last {
                last = current
                stableSince = Date()
            } else if Date().timeIntervalSince(stableSince) >= 3, !current.isEmpty {
                return current
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return last
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
