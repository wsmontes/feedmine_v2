// File: ClipboardBanner.swift
// Module: FeedMineUI
// Owns: the "a feed link was found in your clipboard" banner, copied from V1
//       `Views/ClipboardBanner.swift`.
// Does not own: reading the pasteboard or importing. The host detects the link (T10 owns import) and
// states it here; the banner only offers add or dismiss.

import SwiftUI

public struct ClipboardBanner: View {
    public let feedURL: String
    public let appearance: ReaderAppearance
    public let onAdd: () -> Void
    public let onDismiss: () -> Void

    public init(feedURL: String, appearance: ReaderAppearance, onAdd: @escaping () -> Void,
        onDismiss: @escaping () -> Void) {
        self.feedURL = feedURL
        self.appearance = appearance
        self.onAdd = onAdd
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .foregroundStyle(appearance.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Link de feed no clipboard"))
                    .font(.subheadline).fontWeight(.medium)
                Text(verbatim: feedURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            Button(String(localized: "Adicionar"), action: onAdd)
                .font(.subheadline).fontWeight(.medium)
                .accessibilityIdentifier("clipboard-banner-add")
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark").font(.caption)
            }
            .accessibilityIdentifier("clipboard-banner-dismiss")
            .accessibilityLabel(String(localized: "Dispensar"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(appearance.cardSurface)
        .overlay(RoundedRectangle(cornerRadius: appearance.landscapeCardRadius)
            .stroke(appearance.cardBorder, lineWidth: appearance.borderWidth))
        .clipShape(RoundedRectangle(cornerRadius: appearance.landscapeCardRadius))
        .padding(.horizontal, appearance.contentPadding)
        .accessibilityIdentifier("clipboard-banner")
    }
}
