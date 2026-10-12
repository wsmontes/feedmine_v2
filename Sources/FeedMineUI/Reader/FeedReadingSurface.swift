//
// File: FeedReadingSurface.swift
// Module: FeedMineUI
// Owns: the local reading surface — what the reader sees when the app already holds text worth reading.
// Does not own: which card was opened, where the text came from, whether there is a network, or the site itself.
//       It renders the value it is given and reports the one request a reader can make from it: open the site.
//
// Architect's approved design (2026-10-11): source, headline, date and the stored text, with the origin of that
// text stated ("Resumo fornecido pela fonte" for a summary), partial content never presented as the article, and
// "Abrir no site" in the header *and* at the end. It honours Dynamic Type (the module's tokens are Dynamic Type
// styles, never fixed point sizes) and allows text selection; it reads nothing and fetches nothing.
import SwiftUI

public struct FeedReadingSurface: View {
    public let content: FeedReadingContent
    public let appearance: ReaderAppearance
    /// The site, offered as an explicit request. Absent when the card carries no address: the surface then shows
    /// no way out rather than a control that cannot work.
    public let onOpenSite: (() -> Void)?
    public let onClose: () -> Void

    public init(content: FeedReadingContent, appearance: ReaderAppearance,
        onOpenSite: (() -> Void)? = nil, onClose: @escaping () -> Void) {
        self.content = content
        self.appearance = appearance
        self.onOpenSite = onOpenSite
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(appearance.separatorOpacity)
            ScrollView {
                VStack(alignment: .leading, spacing: FeedDesignTokens.Spacing.section) {
                    Text(verbatim: content.headline)
                        .font(FeedDesignTokens.Typography.cardTitle)
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("reading.headline")
                    metadata
                    origin
                    Text(verbatim: content.text)
                        .font(FeedDesignTokens.Typography.body)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("reading.body")
                }
                .frame(maxWidth: FeedDesignTokens.Measurement.readableContentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, FeedDesignTokens.Spacing.page)
                .padding(.vertical, FeedDesignTokens.Spacing.section)
            }
            footer
        }
        .background(appearance.pageBackground)
    }

    /// The source, and the one exit the reader can take from here.
    private var header: some View {
        HStack(spacing: FeedDesignTokens.Spacing.normal) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("reading.close")
            .accessibilityLabel(String(localized: "Fechar"))

            Text(verbatim: content.sourceName)
                .font(FeedDesignTokens.Typography.label)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityIdentifier("reading.source")

            Spacer(minLength: 0)

            if let onOpenSite {
                Button(action: onOpenSite) {
                    Text("Abrir no site")
                        .font(FeedDesignTokens.Typography.label)
                        .lineLimit(1)
                }
                .accessibilityIdentifier("reading.open-site")
            }
        }
        .tint(appearance.accent)
        .padding(.horizontal, FeedDesignTokens.Spacing.compact)
        .padding(.vertical, FeedDesignTokens.Spacing.tight)
    }

    private var metadata: some View {
        HStack(spacing: FeedDesignTokens.Spacing.compact) {
            if let publishedAt = content.publishedAt {
                Text(publishedAt, format: .dateTime.day().month().year())
                    .font(FeedDesignTokens.Typography.metadata)
                    .foregroundStyle(FeedDesignTokens.Palette.secondaryText)
                    .accessibilityIdentifier("reading.date")
            }
        }
    }

    /// What this text is, and whether it is the whole article. A summary is a summary; a feed's body is what the
    /// source chose to publish. Neither is presented as completeness, because the app cannot verify either.
    private var origin: some View {
        VStack(alignment: .leading, spacing: FeedDesignTokens.Spacing.tight) {
            Text(verbatim: content.origin.label)
                .font(FeedDesignTokens.Typography.badge)
                .foregroundStyle(appearance.accent)
                .accessibilityIdentifier("reading.origin")
            if content.isPartial {
                Text("Conteúdo parcial: o artigo completo está no site.")
                    .font(FeedDesignTokens.Typography.metadata)
                    .foregroundStyle(FeedDesignTokens.Palette.statusCaution)
                    .accessibilityIdentifier("reading.partial")
            }
        }
    }

    private var footer: some View {
        Group {
            if let onOpenSite {
                VStack(spacing: 0) {
                    Divider().opacity(appearance.separatorOpacity)
                    Button(action: onOpenSite) {
                        Text("Abrir no site")
                            .font(FeedDesignTokens.Typography.body.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, FeedDesignTokens.Spacing.normal)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("reading.open-site-footer")
                }
            }
        }
    }
}
