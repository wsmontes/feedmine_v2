import FeedMineDomain
import FeedMineRuntime

/// O livro das janelas adiadas durante um gesto.
///
/// É um tipo de **referência** porque `feedBody` lê o `@State` que contém este valor: um contador guardado no
/// struct fazia cada janela canônica que chega durante o gesto escrever esse `@State` e reavaliar a lista inteira,
/// uma segunda vez, depois da reavaliação que a própria loja já provoca. A lista é dona do que desenha; a contagem
/// é escrituração da prova, não uma mudança de desenho. Não é `@Observable` de propósito: o corpo não deve ser
/// notificado dela.
@MainActor
final class FeedDeferralLedger {
    private(set) var windows = 0
    func recordWindow() { windows += 1 }
}

/// A borrowed value for one native interaction, not another admission or history store.
@MainActor
struct FeedInteractionPresentation {
    /// O que uma janela canônica que chega pode significar para o empréstimo.
    enum Incoming: Equatable {
        /// O gesto continua dono do que está desenhado: nada do estado observado mudou.
        case retained
        /// A janela recebida encerra o empréstimo; quem guarda o capture chama `end()`.
        case released
    }

    private var held: FeedPresentationSnapshot?
    private var owner: ObjectIdentifier?
    private var releaseAnchor: PublicationCardID?
    private let deferrals = FeedDeferralLedger()
    /// Quantas janelas canônicas chegaram sob o gesto. Vivem no livro acima, fora do estado observado.
    var deferredWindows: Int { deferrals.windows }
    var isHolding: Bool { held != nil }

    mutating func begin(_ presentation: FeedPresentationSnapshot?, owner: ObjectIdentifier) {
        // A new gesture supersedes an idle acknowledgement still in flight.
        releaseAnchor = nil
        guard held == nil else { return }
        held = presentation
        self.owner = owner
    }
    mutating func end() { held = nil; owner = nil; releaseAnchor = nil }
    mutating func end(afterReading card: PublicationCardID?, store: FeedScreenStore) {
        guard let held, presentation(for: store) == held else { end(); return }
        if let card, let current = store.state.presentation,
            !current.window.items.contains(where: { $0.id == card }) {
            releaseAnchor = card
            return
        }
        end()
    }

    func presentation(for store: FeedScreenStore) -> FeedPresentationSnapshot? {
        guard let current = store.state.presentation, let held,
            owner == ObjectIdentifier(store), current.contextKey == held.contextKey,
            current.editionID == held.editionID,
            current.provenance.sequenceID == held.provenance.sequenceID else { return store.state.presentation }
        return held
    }

    /// A janela **segurada** durante um gesto, quando ela ainda pertence ao que a loja publicou para a lista.
    ///
    /// A comparação é contra a identidade publicada (edição, contexto) e **não** contra a posição do leitor: durante
    /// o gesto a lista não pode mudar sob o dedo, e fora dele quem manda é o conteúdo publicado. É esta leitura que
    /// mantém a posição fora do corpo da lista (princípio do dono, 2026-10-14).
    func heldItems(matching store: FeedScreenStore) -> [PresentationCard]? {
        guard let held, owner == ObjectIdentifier(store),
            held.contextKey == store.renderedContextKey, held.editionID == store.renderedEditionID else { return nil }
        return held.window.items
    }

    /// Uma janela canônica chegou. **Não muta**: enquanto o gesto dura, o que muda é a contagem de janelas
    /// adiadas, e ela não faz parte do estado observado pelo corpo da lista. Só o `released` pede uma escrita —
    /// a do `end()`, que muda o que a lista desenha e por isso é feita por quem guarda o capture.
    func incoming(_ store: FeedScreenStore) -> Incoming {
        guard let held else { return .retained }
        guard presentation(for: store) == held, let current = store.state.presentation else { return .released }
        if let releaseAnchor, current.window.items.contains(where: { $0.id == releaseAnchor }) {
            return .released
        }
        if held.window.items.map(\.id) != current.window.items.map(\.id) { deferrals.recordWindow() }
        return .retained
    }
}
