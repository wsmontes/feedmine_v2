// Factual absence/work presentation; execution remains external.
import SwiftUI

@MainActor
public struct FeedLoadingView: View {
    private let work: FeedPresentationState.Work
    @Environment(\.colorScheme) private var colorScheme

    public init(work: FeedPresentationState.Work) {
        self.work = work
    }

    public var body: some View {
        VStack(spacing: FeedDesignTokens.Spacing.page) {
            // U1-B: restrained branding on the absence surface. The factual work text below stays
            // the source of truth; the wordmark never replaces pipeline evidence.
            Image(FeedDesignTokens.AssetName.wordmark(for: colorScheme))
                .resizable()
                .scaledToFit()
                .frame(maxWidth: FeedDesignTokens.Measurement.wordmarkWidth)
                .accessibilityHidden(true)
            Group {
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
            .font(FeedDesignTokens.Typography.body)
            .multilineTextAlignment(.center)
        }
        .padding(FeedDesignTokens.Spacing.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
