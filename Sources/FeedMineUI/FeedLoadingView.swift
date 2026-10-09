// Factual absence/work presentation; execution remains external.
// While local preparation is pending, card-shaped placeholders show where the feed will be
// (perceived speed without inventing content: they carry no text). Their pulse is opacity only
// and stops under Reduce Motion.
import SwiftUI

@MainActor
public struct FeedLoadingView: View {
    private let work: FeedPresentationState.Work

    public init(work: FeedPresentationState.Work) {
        self.work = work
    }

    public var body: some View {
        VStack(spacing: 20) {
            switch work {
            case .idle:
                Text("Nenhuma apresentação local recebida")
            case .pending:
                Text("Preparando apresentação local")
                FeedSkeletonStack()
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

/// Three text-free card silhouettes in the real card proportions (hero, thumbnail, text).
private struct FeedSkeletonStack: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: FeedDesign.cardSpacing) {
            SkeletonCard(media: .hero)
            SkeletonCard(media: .thumbnail)
            SkeletonCard(media: nil)
        }
        .frame(maxWidth: 560)
        .phaseAnimator(reduceMotion ? [1.0] : [1.0, 0.55]) { view, phase in
            view.opacity(phase)
        } animation: { _ in .easeInOut(duration: 0.9) }
        .accessibilityHidden(true)
    }
}

private struct SkeletonCard: View {
    enum Media { case hero, thumbnail }
    let media: Media?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FeedDesign.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            if media == .hero {
                Rectangle().fill(FeedDesign.placeholder).aspectRatio(16.0 / 9.0, contentMode: .fit)
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    bar(width: 0.3, height: 9)
                    bar(width: 0.9, height: 14)
                    bar(width: 0.7, height: 14)
                    bar(width: 0.5, height: 9)
                }
                if media == .thumbnail {
                    RoundedRectangle(cornerRadius: FeedDesign.thumbnailRadius, style: .continuous)
                        .fill(FeedDesign.placeholder)
                        .frame(width: FeedDesign.thumbnailSide, height: FeedDesign.thumbnailSide)
                }
            }
            .padding(FeedDesign.cardPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FeedDesign.surface, in: shape)
        .clipShape(shape)
        .overlay { shape.strokeBorder(FeedDesign.hairline, lineWidth: 0.5) }
    }

    /// A bounded fraction of the card's text column; layout-only, no measurement.
    private func bar(width: CGFloat, height: CGFloat) -> some View {
        Capsule().fill(FeedDesign.placeholder)
            .frame(maxWidth: 420 * width, minHeight: height, maxHeight: height)
    }
}
