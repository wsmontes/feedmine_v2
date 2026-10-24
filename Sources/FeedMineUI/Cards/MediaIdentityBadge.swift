//
// File: MediaIdentityBadge.swift
// Module: FeedMineUI
//
// Responsibility:
//   Draw the word a card's declared media kind puts beside its source — "Podcast" for audio, "Vídeo" for video.
//
// Does not own:
//   Deciding the kind (the frozen presentation states it), or any control: the badge is a label, never a button.
//

import Foundation
import SwiftUI
import FeedMineRuntime

struct MediaIdentityBadge: View {
    let identity: PresentationMediaIdentity?

    @ViewBuilder
    var body: some View {
        switch identity {
        case .some(.audio): badge(String(localized: "Podcast"), color: .purple)
        case .some(.video): badge(String(localized: "Vídeo"), color: .blue)
        case .some(.none), nil: EmptyView()
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(verbatim: text)
            .font(.caption2)
            .fontWeight(.heavy)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }
}
