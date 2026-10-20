import SwiftUI
#if DEBUG
import OSLog
#endif
import FeedMineRuntime
import FeedMineDomain

@available(iOS 18, macOS 15, *)
struct NativeFeedViewport: ViewModifier {
    @Binding var capture: FeedVisualCapture
    let store: FeedScreenStore

    /// A apresentação que a posição **segue**: a janela segurada enquanto um gesto está em curso, e a publicada
    /// fora dele — a mesma leitura que a lista fazia antes do desacoplamento, agora lida **dentro** do modificador
    /// (assim um avanço reavalia este modificador, barato, e não o corpo da lista, que é o desenho dos itens).
    ///
    /// Não trocar por `store.state.presentation`. Com o valor publicado aqui, o teste de escopo
    /// (`presentation(for:)?.window == presented.window`) passa a comparar a janela **segurada** com a **publicada**:
    /// a primeira atualização de janela que chega durante o gesto torna o escopo falso para sempre, e a saída do
    /// hold (ramo `phase == .idle`) mora atrás desse mesmo guard — medido no simulador em 2026-10-14: 8 flings
    /// rápidos produziram 1 avanço e nenhuma mudança da lista desenhada.
    private var presented: FeedPresentationSnapshot? { capture.interaction.presentation(for: store) }

    private var matchesScope: Bool {
        guard let current = store.state.presentation, let presented else { return false }
        return capture.renderOwner == ObjectIdentifier(store) &&
            capture.interaction.presentation(for: store)?.window == presented.window &&
            current.contextKey == presented.contextKey && current.editionID == presented.editionID &&
            current.provenance.sequenceID == presented.provenance.sequenceID
    }

    /// R04: the one place a requested position is accepted or deferred. A ready destination is applied; a released
    /// bitmap keeps the reader where they are and asks the session for the destination band; the prepared value
    /// applies the position (see `settlePendingJump`). VoiceOver, `scrollTo` and a programmatic jump all arrive here.
    private func requestPosition(_ id: PublicationCardID, presented: FeedPresentationSnapshot) {
        FeedPositionRequest.apply(id, presented: presented, capture: &capture, store: store)
    }

    /// Applies a position that was waiting for its pixels, or states that the destination is unavailable.
    private func settlePendingJump() {
        FeedPositionRequest.settle(&capture, store: store)
    }

    // Card bounds use the container viewport; visibleRect may also include safe-area insets.
    private func visualGeometry(_ geometry: ScrollGeometry) -> FeedVisualGeometry {
        .init(offset: geometry.contentOffset.y + geometry.contentInsets.top,
            extent: geometry.contentSize.height,
            height: geometry.containerSize.height,
            width: geometry.containerSize.width)
    }

    func body(content: Content) -> some View {
        return content
            .id(store.state.presentation?.editionID)
            .id(store.state.presentation?.contextKey)
            // A restauração honra a colocação que o registro carrega: o `scrollPosition` sem âncora alinha o card
            // identificado à borda de **cima** do viewport (medido duas vezes em 2026-10-14: o card da âncora
            // pousou com a borda superior exatamente na borda do viewport), que é o que a colocação `.top` — a
            // única que o registro durável agora escreve — significa. Uma linha antiga (`.center`, o card do leitor)
            // continua pousando presa no topo, exatamente como o build anterior fazia, e o próximo repouso a
            // reescreve como `.top`. Não passar uma âncora explícita é deliberado: com `anchor: .top` o SwiftUI
            // re-alinha o card identificado a cada mutação de janela, e a posição visível do leitor anda — medido em
            // `Tests/ArchitectureSmokeTests/FeedViewportCaptureTests.testNativeHostedLayoutPreservesPositionWithoutInventingReading`
            // (440 -> 369) quando a âncora explícita foi tentada.
            .scrollPosition(id: Binding(get: {
                capture.positionID ?? presented?.window.anchor.cardID
            }, set: { id in
                guard matchesScope, let id, let presented,
                    presented.window.items.contains(where: { $0.id == id }) else { return }
                requestPosition(id, presented: presented)
            }))
            .onScrollPhaseChange { oldPhase, phase, context in
                #if DEBUG
                FeedVisualCapture.scrollPhaseEvents += 1
                #endif
                // Uma animação programática não é um gesto do leitor: enquanto ela corre, o desenho não está em
                // repouso e nada do que ele mostrar no meio vira posição durável.
                capture.motion.animating = phase == .animating
                guard matchesScope else { return }
                #if DEBUG
                if FeedVisualCapture.tracesCapture {
                    Logger(subsystem: "com.feedmine.development", category: "native-capture").info("native SwiftUI phase=\(String(describing: oldPhase), privacy: .public)->\(String(describing: phase), privacy: .public)")
                }
                #endif
                if phase != .idle {
                    capture.interaction.begin(presented, owner: ObjectIdentifier(store))
                } else {
                    let reader = capture.position?.cardID ?? capture.motion.readerCardID
                    if capture.interaction.isHolding, let reader, let presented, let current = store.state.presentation,
                        !current.window.items.contains(where: { $0.id == reader }) {
                        store.submitViewport(.init(anchor: .init(cardID: reader, placement: .top)),
                            activity: .stationary, rendered: presented, reconciliation: true)
                    }
                    capture.interaction.end(afterReading: reader, store: store)
                }
                store.setReadingInteractionActive(phase != .idle || capture.interaction.isHolding)
                #if canImport(UIKit)
                capture.nativeScrollOffset.setInteractionActive(phase != .idle)
                #endif
                let wasReading = oldPhase == .interacting || oldPhase == .decelerating
                let isReading = phase == .interacting || phase == .decelerating
                #if canImport(UIKit)
                if phase == .tracking { capture.nativeScrollOffset.cancel(discardingSamples: false) }
                else if capture.nativeScrollOffset.isCorrecting {
                    capture.reading = isReading
                    capture.invalidateLayout()
                    _ = capture.observe(visualGeometry(context.geometry))
                    return
                }
                #endif
                if (!wasReading && isReading) || phase == .animating || phase == .tracking {
                    capture.invalidateLayout()
                }
                capture.phase(active: (wasReading || isReading) && phase != .animating && phase != .tracking, velocity: context.velocity)
                let geometry = context.geometry
                if let event = capture.observe(visualGeometry(geometry)) {
                    store.submitViewport(event.observation, activity: event.activity, rendered: presented)
                }
                capture.reading = isReading
                if phase == .animating || phase == .tracking { capture.invalidateLayout() }
                if phase == .idle, let event = capture.settle() {
                    store.submitViewport(event.observation, activity: event.activity, rendered: presented)
                }
                if phase == .idle {
                    // A chegada ao repouso é o momento em que a posição do viewport passa a ser uma posição que o
                    // leitor realmente segura — **inclusive** quando a tela se moveu sem gesto nenhum (uma rolagem
                    // de acessibilidade, uma animação do sistema): o host a grava pelo mesmo dono do cursor.
                    capture.reportPresentedPosition { anchor, atRest in
                        store.publishPresentedPosition(anchor, atRest: atRest)
                    }
                }
            }
            .onScrollGeometryChange(for: FeedVisualGeometry.self, of: { geometry in
                visualGeometry(geometry)
            }) { _, geometry in
                #if DEBUG
                FeedVisualCapture.scrollGeometryEvents += 1
                #endif
                guard matchesScope else {
                    #if DEBUG
                    FeedVisualCapture.scopeRejections += 1
                    #endif
                    return
                }
                #if canImport(UIKit)
                if capture.nativeScrollOffset.isCorrecting {
                    capture.invalidateLayout()
                    _ = capture.observe(geometry)
                    return
                }
                #endif
                if let event = capture.observe(geometry) {
                    store.submitViewport(event.observation, activity: event.activity, rendered: presented)
                }
                // Toda mudança da geometria do scroll é um movimento do viewport — inclusive os que **nenhum gesto**
                // produziu (uma rolagem de acessibilidade, uma re-layout do sistema, uma animação programática). A
                // posição onde o viewport começa é publicada aqui: em movimento o dono do cursor só a lembra, e no
                // repouso ela vira escrita. Sem isto, o leitor que morre depois de uma dessas volta a uma posição
                // que já tinha deixado (medido em B05, 2026-10-14: oito cards atrás da tela que o driver mediu).
                capture.reportPresentedPosition { anchor, atRest in
                    store.publishPresentedPosition(anchor, atRest: atRest)
                }
            }
            .onChange(of: presented?.window) { old, new in
                // A new layout must establish a fresh viewport proof. Native offset correction
                // is handled independently, before card geometry becomes a reader event.
                capture.invalidateLayout()
            }
            .onChange(of: store.state.presentation?.window) { _, _ in
                capture.interaction.noteIncoming(store)
                settlePendingJump()
            }
            // A failed reconstruction preserves the card and the window; only the unavailable fact changes. Without
            // observing it, the pending jump would keep waiting for a preparation the session already concluded.
            .onChange(of: store.state.presentation?.unavailableImageCardIDs) { _, _ in
                settlePendingJump()
            }
            .onChange(of: ObjectIdentifier(store), initial: true) { _, _ in
                capture.renderOwner = ObjectIdentifier(store)
            }
            .onDisappear {
                guard matchesScope else { return }
                capture.interaction.end()
                store.setReadingInteractionActive(false)
                #if canImport(UIKit)
                capture.nativeScrollOffset.setInteractionActive(false)
                capture.nativeScrollOffset.cancel()
                #endif
            }
            .onChange(of: ObjectIdentifier(store)) { _, _ in
                capture = FeedVisualCapture()
                capture.renderOwner = ObjectIdentifier(store)
                store.setReadingInteractionActive(false)
            }
            .onChange(of: store.state.presentation?.editionID) { _, _ in
                capture = FeedVisualCapture()
                capture.renderOwner = ObjectIdentifier(store)
                store.setReadingInteractionActive(false)
            }
            .onChange(of: store.state.presentation?.contextKey) { _, _ in
                capture = FeedVisualCapture()
                capture.renderOwner = ObjectIdentifier(store)
                store.setReadingInteractionActive(false)
            }
    }
}

/// One place where a requested position is accepted, deferred or refused (R04/P03). The scroll binding, VoiceOver,
/// `scrollTo`, a programmatic jump and "Voltar ao início" all pass through here — none of them may assign the
/// position directly, because a released head would be exposed without its pixels.
@MainActor
enum FeedPositionRequest {
    static func apply(_ id: PublicationCardID, presented: FeedPresentationSnapshot,
        capture: inout FeedVisualCapture, store: FeedScreenStore) {
        switch FeedDestinationGate.readiness(of: id, in: presented) {
        case .ready, .notAdmitted:
            capture.pendingJump = nil
            capture.positionID = id
            capture.motion.readerCardID = id
        case .needsPreparation:
            capture.pendingJump = id
            store.submitViewport(.init(anchor: .init(cardID: id, placement: .top)),
                activity: .stationary, rendered: presented, reconciliation: true)
        case .unavailableAfterPreparation:
            capture.pendingJump = nil
        }
    }

    static func settle(_ capture: inout FeedVisualCapture, store: FeedScreenStore) {
        guard let destination = capture.pendingJump else { return }
        switch FeedDestinationGate.readinessAfterPreparation(of: destination, in: store.state.presentation) {
        case .ready:
            capture.positionID = destination
            capture.motion.readerCardID = destination
            capture.pendingJump = nil
        case .unavailableAfterPreparation:
            capture.pendingJump = nil
            store.showToast(text: String(localized: "Este conteúdo não está disponível"),
                systemImage: "exclamationmark.triangle")
        case .needsPreparation, .notAdmitted:
            break
        }
    }
}

@available(iOS 18, macOS 15, *)
struct NativeFeedTargets: ViewModifier {
    func body(content: Content) -> some View {
        // Keep the page margins around the content, but not above its first card: `scrollPosition(id:)` aligns an
        // anchored card to the viewport's top edge. A top margin would make the very same card land 16 pt lower when
        // the reader returns from above (the first topmost card sits after the padding), so geometry would not be
        // preserved at ±1 pt (E03). Horizontal and bottom margins remain the design's own.
        content.scrollTargetLayout()
            .padding([.horizontal, .bottom])
            .coordinateSpace(name: "feed-visual-content")
    }
}
