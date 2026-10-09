// Factual absence/work presentation; execution remains external.
import SwiftUI

@MainActor
public struct FeedLoadingView: View {
    private let work: FeedPresentationState.Work

    public init(work: FeedPresentationState.Work) {
        self.work = work
    }

    public var body: some View {
        VStack {
            switch work {
            case .idle:
                Text("Nenhuma apresentação local recebida")
            case .pending:
                Text("Preparando apresentação local")
            case .unavailable:
                Text("Apresentação indisponível no momento")
            case .deferred:
                Text("Preparação adiada")
            case .failed(let message):
                Text(verbatim: message)
            case .preparing(let progress):
                FeedPreparationView(progress: progress)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FeedDesign.page.ignoresSafeArea())
    }
}
