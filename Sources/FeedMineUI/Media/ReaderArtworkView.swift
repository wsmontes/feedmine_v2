//
// File: ReaderArtworkView.swift
// Module: FeedMineUI
//
// Responsibility:
// The playing episode's cover, as V1 drew it in both the bar (40 pt) and the full player (up to 280 pt), plus the
// fallback that states the truth when the card carries no prepared image. The pixels are a Runtime value the
// presentation layer already decoded; this view performs no I/O, no download and no decoding.
//
// Does not own: which image belongs to the occurrence (Composition/Runtime), playback, or layout decisions the
// player surfaces make about size.
import SwiftUI
import FeedMineRuntime

public struct ReaderArtworkView: View {
    private let artwork: PresentationImage?
    private let size: CGFloat
    private let cornerRadius: CGFloat
    private let identifier: String
    private let fallbackIdentifier: String
    private let symbolSize: CGFloat
    private let appearance: ReaderAppearance

    /// `identifier` names the decoded image; `fallbackIdentifier` names the placeholder, so a journey can state
    /// which of the two it saw instead of treating "something is drawn" as artwork.
    public init(artwork: PresentationImage?, size: CGFloat, cornerRadius: CGFloat = 10,
        identifier: String, fallbackIdentifier: String, symbolSize: CGFloat = 18,
        appearance: ReaderAppearance = .standard) {
        self.artwork = artwork
        self.size = max(0, size)
        self.cornerRadius = max(0, cornerRadius)
        self.identifier = identifier
        self.fallbackIdentifier = fallbackIdentifier
        self.symbolSize = symbolSize
        self.appearance = appearance
    }

    public var body: some View {
        Group {
            if let artwork {
                Image(decorative: artwork.cgImage, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(shape)
                    .overlay {
                        shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier(identifier)
                    .accessibilityLabel(Text(verbatim: String(localized: "Capa do episódio")))
            } else {
                // No cover was admitted. V1's waveform states "this is audio" without claiming an image exists;
                // the label says the same in words, so VoiceOver is not told a picture is there.
                shape
                    .fill(LinearGradient(colors: [appearance.accent.opacity(0.18),
                        appearance.accent.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay {
                        Image(systemName: "waveform")
                            .font(.system(size: symbolSize, weight: .medium))
                            .foregroundStyle(appearance.accent.opacity(0.75))
                    }
                    .overlay {
                        shape.strokeBorder(appearance.accent.opacity(0.16), lineWidth: 0.5)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier(fallbackIdentifier)
                    .accessibilityLabel(Text(verbatim: String(localized: "Sem capa para este episódio")))
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.2), value: artwork?.key)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}
