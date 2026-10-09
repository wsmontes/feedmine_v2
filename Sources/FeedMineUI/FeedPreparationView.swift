// PD-3: first-launch preparation that entertains with real evidence, not a progress bar.
// Every element is a fact from the pipeline (PreparationProgress): sources being contacted,
// sources that brought news, headlines actually admitted, cards prepared. Motion comes from
// those facts arriving (insertion transitions) plus a gentle continuous drift; Reduce Motion
// turns the drift off. Execution stays external: this view only renders the supplied value.
import SwiftUI
import FeedMineRuntime

@MainActor
public struct FeedPreparationView: View {
    private let progress: PreparationProgress
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(progress: PreparationProgress) {
        self.progress = progress
    }

    public var body: some View {
        VStack(spacing: 28) {
            header
            headlineDeck
                .frame(maxWidth: 420, minHeight: 220)
            sourceCloud
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.55, dampingFraction: 0.78), value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilitySummary))
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Indo atrás do que vale a pena ler")
                .font(.system(.title2, design: .serif).weight(.semibold))
                .multilineTextAlignment(.center)
            Text(verbatim: status)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
    }

    private var status: String {
        let contributing = progress.contributingSources
        if progress.preparedCards > 0 { return "\(progress.preparedCards) histórias prontas para você" }
        if progress.isNearlyReady { return "Quase pronto — \(contributing) fontes já trouxeram novidades" }
        if contributing > 0 { return "\(contributing) de \(progress.sources.count) fontes já trouxeram novidades" }
        if !progress.sources.isEmpty { return "Conversando com \(progress.sources.count) fontes" }
        return "Abrindo as primeiras fontes"
    }

    /// Admitted headlines land on a loose deck as they arrive.
    private var headlineDeck: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(Array(progress.headlines.prefix(5).enumerated()), id: \.element) { index, headline in
                    HeadlineCard(text: headline, emphasized: index == 0)
                        .rotationEffect(.degrees(Double(index) * (index.isMultiple(of: 2) ? 2.5 : -2.5)
                            + (reduceMotion ? 0 : sin(t * 0.8 + Double(index)) * 1.2)))
                        .offset(x: reduceMotion ? 0 : cos(t * 0.6 + Double(index)) * 4,
                            y: CGFloat(index) * 14)
                        .scaleEffect(1 - CGFloat(index) * 0.05)
                        .zIndex(Double(10 - index))
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.8)),
                            removal: .opacity))
                }
                if progress.headlines.isEmpty {
                    HeadlineCard(text: "As primeiras manchetes aparecem aqui", emphasized: false)
                        .opacity(0.5)
                }
            }
        }
    }

    private var sourceCloud: some View {
        HStack(spacing: 8) {
            ForEach(progress.sources.prefix(8)) { source in
                SourceChip(name: source.name, state: source.state, animate: !reduceMotion)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: 520)
    }

    private var accessibilitySummary: String {
        var parts = ["Preparando seu feed.", status + "."]
        if let first = progress.headlines.first { parts.append("Última manchete: " + first) }
        return parts.joined(separator: " ")
    }
}

private struct HeadlineCard: View {
    let text: String
    let emphasized: Bool
    var body: some View {
        Text(verbatim: text)
            .font(emphasized ? .system(.headline, design: .serif) : .system(.subheadline, design: .serif))
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(FeedDesign.surface, in: RoundedRectangle(cornerRadius: FeedDesign.cardRadius, style: .continuous))
            .shadow(color: .black.opacity(emphasized ? 0.18 : 0.08), radius: emphasized ? 12 : 6, y: 4)
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
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10).padding(.vertical, 6)
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
        case .contacting: return .accentColor
        case .contributed: return .green
        case .quiet: return .secondary
        case .unreachable: return .orange
        }
    }
}
