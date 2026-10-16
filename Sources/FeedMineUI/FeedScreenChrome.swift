import SwiftUI

/// Contadores de fluxo que o **host** também precisa ler (a instalação é decidida lá). Públicos de propósito,
/// só de diagnóstico: uma janela que não cresce é uma instalação rejeitada a mais.
public enum FeedFlowCounters {
    public nonisolated(unsafe) static var installAttempts = 0
    public nonisolated(unsafe) static var installAccepts = 0
    public nonisolated(unsafe) static var installRejects = 0
}

/// A linha editorial desenhada no **próprio corpo**: o que ela lê (posição do leitor, orçamento de ofertas,
/// preferências) invalida só ela, nunca a lista. A V1 tinha a mesma forma — a linha era uma view dentro da
/// `LazyVStack`. Sem isso, a leitura de posição feita aqui dentro voltava a re-renderizar o feed a cada avanço.
@MainActor
struct EditorialSlot: View {
    private let content: @MainActor () -> AnyView?

    init(content: @escaping @MainActor () -> AnyView?) { self.content = content }

    var body: some View {
        if let content = content() { content }
    }
}

/// Reserved, non-interactive work feedback (T3): constant height, no hit testing, so reporting work can
/// never change the scroll geometry the reader was admitted into.
@MainActor
struct FeedWorkFeedback: View {
    let work: FeedPresentationState.Work
    var body: some View {
        FeedWorkBadge(work: work)
            .frame(height: FeedDesignTokens.Measurement.workFeedbackHeight, alignment: .bottom)
            .allowsHitTesting(false)
    }
}

/// Review M17: work that continues after cards are visible is shown without touching the cards.
struct FeedWorkBadge: View {
    let work: FeedPresentationState.Work
    var body: some View {
        switch work {
        case .pending, .preparing:
            Label("Buscando novidades", systemImage: "arrow.triangle.2.circlepath")
                .modifier(BadgeStyle())
        case .failed(let message):
            Label { Text(verbatim: message) } icon: { Image(systemName: "exclamationmark.triangle") }
                .modifier(BadgeStyle())
        case .idle, .unavailable, .deferred, .unreachable, .endOfContent:
            EmptyView()
        }
    }
}

private struct BadgeStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.font(FeedDesignTokens.Typography.badge)
            .padding(.horizontal, FeedDesignTokens.Spacing.normal)
            .padding(.vertical, FeedDesignTokens.Spacing.compact)
            .background(.thinMaterial, in: Capsule())
            .padding(.bottom, FeedDesignTokens.Spacing.compact)
    }
}
