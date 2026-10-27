// PD-3 / next-experience: the page the reader sees while a new feed is being made.
//
// It is a page, not a scrim: the feed underneath is measured but hidden and untouchable, and this surface is opaque,
// readable and coherent on its own. Every element is a fact from the pipeline — sources being contacted, which
// brought news, headlines actually admitted, prepared cards — plus the **prepared pixels** the media pipeline
// already decoded, so the page can be image-bearing without inventing a single story. Execution stays external:
// this view only renders the value and the published cards it was handed.
//
// When nothing has arrived yet, frozen-aspect slots carry the geometry and the motion of the feed that is coming.
// They carry no text and no identity: a skeleton is a slot, never a claim.
import SwiftUI
import FeedMineRuntime

@MainActor
public struct FeedPreparationView: View {
    /// The pipeline's evidence. Nil when the page is drawn for a context whose Edition was already installed and no
    /// preparation run is speaking for it: then every fact on the page comes from `publishedPreview`, and nothing
    /// claims network work that is not happening.
    private let progress: PreparationProgress?
    /// Cards already installed for this context. Their pixels and headlines are the page's second source of real
    /// content: on a filter change the new association may restore a cached Edition before its own preparation
    /// evidence exists, and the page shows what was really published instead of an empty deck.
    private let publishedPreview: [PresentationCard]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How many images the mosaic draws. Six is the same floor the readiness targets state: one screenful of a
    /// feed that is meant to be image-bearing.
    public static let mosaicCapacity = 6

    public init(progress: PreparationProgress?, publishedPreview: [PresentationCard] = []) {
        self.progress = progress
        self.publishedPreview = publishedPreview
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: FeedDesignTokens.Spacing.deck) {
                header
                mosaic
                headlineDeck
                    .frame(maxWidth: FeedDesignTokens.Measurement.headlineDeckWidth, minHeight: 200)
                sourceCloud
            }
            .padding(FeedDesignTokens.Spacing.page)
            .frame(maxWidth: .infinity)
        }
        // The page scrolls only so a small screen or a large Dynamic Type can reach every fact; its content is a
        // fixed page, not a feed.
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.8), value: progress)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("first-screen-page")
        .accessibilityLabel(Text(verbatim: accessibilitySummary))
    }

    private var header: some View {
        VStack(spacing: FeedDesignTokens.Spacing.tight) {
            Image(FeedDesignTokens.AssetName.symbolGradient)
                .resizable()
                .scaledToFit()
                .frame(width: FeedDesignTokens.Measurement.deckSymbolWidth)
                .accessibilityHidden(true)
            Text("Indo atrás do que vale a pena ler")
                .font(FeedDesignTokens.Typography.pageTitle)
                .multilineTextAlignment(.center)
            Text(verbatim: status)
                .font(FeedDesignTokens.Typography.label)
                .foregroundStyle(FeedDesignTokens.Palette.secondaryText)
                .contentTransition(.numericText())
                .accessibilityIdentifier("first-screen-status")
        }
        .padding(.top, FeedDesignTokens.Spacing.page)
    }

    private var status: String {
        guard let progress else {
            // A page drawn for an Edition that was already installed: the page states what it is doing with the
            // content it has, and claims no source contact and no count that was not produced.
            return String(localized: "Organizando as histórias que já chegaram")
        }
        if progress.preparedCards > 0 {
            return String(localized: "\(progress.preparedCards) histórias prontas para você")
        }
        if progress.isNearlyReady {
            return String(localized: "Quase pronto — \(progress.contributingSources) fontes já trouxeram novidades")
        }
        if progress.contributingSources > 0 {
            return String(localized: "\(progress.contributingSources) de \(progress.sources.count) fontes já trouxeram novidades")
        }
        if !progress.sources.isEmpty {
            return String(localized: "Conversando com \(progress.sources.count) fontes")
        }
        return String(localized: "Abrindo as primeiras fontes")
    }

    // MARK: - Real pixels

    /// Prepared images, in the order the pipeline produced them, then the pixels of cards already published for
    /// this context. No placement draws an image it was not handed.
    private var mosaicImages: [PresentationImage] {
        var seen = Set<String>()
        var images: [PresentationImage] = []
        for image in (progress?.previewImages ?? []) + publishedPreview.compactMap(\.image) {
            guard seen.insert(image.key).inserted else { continue }
            images.append(image)
            if images.count >= Self.mosaicCapacity { break }
        }
        return images
    }

    @ViewBuilder private var mosaic: some View {
        let images = mosaicImages
        if images.isEmpty {
            skeletonRow
        } else {
            // An asymmetric page: the newest prepared image leads, the rest form a varied strip. Aspect is frozen
            // per slot so an image arriving never moves what is already drawn.
            VStack(spacing: FeedDesignTokens.Spacing.compact) {
                ForEach(Array(images.enumerated()), id: \.element.key) { index, image in
                    Image(decorative: image.cgImage, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: index == 0 ? 220 : 108)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: FeedDesignTokens.Radius.overlay,
                            style: .continuous))
                        .accessibilityIdentifier("first-screen-image-\(index)")
                        .transition(reduceMotion
                            ? .opacity
                            : .asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity),
                                removal: .opacity))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Frozen slots: the geometry of the page that is coming, with the same gentle drift the deck uses. No text,
    /// no logo, no identity — the reader is never told a story exists before one does.
    private var skeletonRow: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            VStack(spacing: FeedDesignTokens.Spacing.compact) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: FeedDesignTokens.Radius.overlay, style: .continuous)
                        .fill(FeedDesignTokens.Palette.secondaryText.opacity(0.10))
                        .frame(height: index == 0 ? 200 : 96)
                        .overlay {
                            RoundedRectangle(cornerRadius: FeedDesignTokens.Radius.overlay, style: .continuous)
                                .fill(LinearGradient(
                                    colors: [.clear, .white.opacity(reduceMotion ? 0 : 0.18), .clear],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                                .rotationEffect(.degrees(reduceMotion ? 0 : sin(t * 0.7 + Double(index)) * 2))
                        }
                        .accessibilityIdentifier("first-screen-skeleton-\(index)")
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Real headlines

    /// Admitted headlines land on a loose deck as they arrive; a context whose Edition is already installed states
    /// the headlines it published, so a filter change never shows an empty page.
    private var deckHeadlines: [String] {
        if let headlines = progress?.headlines, !headlines.isEmpty { return headlines }
        return publishedPreview.compactMap(\.title).filter { !$0.isEmpty }
    }

    private var headlineDeck: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(Array(deckHeadlines.prefix(5).enumerated()), id: \.element) { index, headline in
                    HeadlineCard(text: headline, emphasized: index == 0)
                        .rotationEffect(.degrees(Double(index) * (index.isMultiple(of: 2) ? 2.5 : -2.5)
                            + (reduceMotion ? 0 : sin(t * 0.8 + Double(index)) * 1.2)))
                        .offset(x: reduceMotion ? 0 : cos(t * 0.6 + Double(index)) * 4,
                            y: CGFloat(index) * 14)
                        .scaleEffect(1 - CGFloat(index) * 0.05)
                        .zIndex(Double(10 - index))
                        .accessibilityIdentifier(index == 0 ? "first-screen-headline" : "first-screen-headline-\(index)")
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.8)),
                            removal: .opacity))
                }
            }
        }
    }

    @ViewBuilder private var sourceCloud: some View {
        let sources = progress?.sources ?? []
        if !sources.isEmpty {
            HStack(spacing: FeedDesignTokens.Spacing.compact) {
                ForEach(sources.prefix(8)) { source in
                    SourceChip(name: source.name, state: source.state, animate: !reduceMotion)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: FeedDesignTokens.Measurement.sourceCloudWidth)
            .padding(.bottom, FeedDesignTokens.Spacing.page)
        }
    }

    private var accessibilitySummary: String {
        // With no run speaking for the page, "Preparando seu feed" would claim preparation that is not happening:
        // the summary states only what the page proves — the published content it is organizing.
        var parts: [String] = progress == nil
            ? [String(localized: "Organizando as histórias que já chegaram.")]
            : [String(localized: "Preparando seu feed."), String(localized: "\(status).")]
        if let first = deckHeadlines.first {
            parts.append(String(localized: "Última manchete: \(first)"))
        }
        return parts.joined(separator: " ")
    }
}

private struct HeadlineCard: View {
    let text: String
    let emphasized: Bool
    var body: some View {
        Text(verbatim: text)
            .font(emphasized ? FeedDesignTokens.Typography.cardTitle : FeedDesignTokens.Typography.label)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(FeedDesignTokens.Spacing.card)
            .background(.background, in: RoundedRectangle(cornerRadius: FeedDesignTokens.Radius.overlay))
            .shadow(color: FeedDesignTokens.Palette.shadow.opacity(emphasized ? 0.18 : 0.08), radius: emphasized ? 12 : 6, y: 4)
    }
}

private struct SourceChip: View {
    let name: String
    let state: PreparationProgress.SourceState
    let animate: Bool
    var body: some View {
        Label {
            Text(verbatim: name).lineLimit(1)
        } icon: {
            Image(systemName: icon)
        }
        .font(FeedDesignTokens.Typography.badge)
        .padding(.horizontal, FeedDesignTokens.Spacing.compact)
        .padding(.vertical, FeedDesignTokens.Spacing.tight)
        .background(tint.opacity(0.15), in: Capsule())
        .foregroundStyle(tint)
        .phaseAnimator(state == .contacting && animate ? [1.0, 0.55] : [1.0]) { view, phase in
            view.opacity(phase)
        } animation: { _ in .easeInOut(duration: 0.8) }
    }
    private var icon: String {
        switch state {
        case .contacting: return "antenna.radiowaves.left.and.right"
        case .contributed: return "sparkles"
        case .quiet: return "checkmark"
        case .unreachable: return "wifi.slash"
        }
    }
    private var tint: Color {
        switch state {
        case .contacting: return FeedDesignTokens.Palette.accent
        case .contributed: return FeedDesignTokens.Palette.statusPositive
        case .quiet: return FeedDesignTokens.Palette.secondaryText
        case .unreachable: return FeedDesignTokens.Palette.statusCaution
        }
    }
}
