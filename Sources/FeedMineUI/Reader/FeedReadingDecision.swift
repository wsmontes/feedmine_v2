//
// File: FeedReadingDecision.swift
// Module: FeedMineUI
// Owns: the decision of *where* a card is read — locally, from text the app already stored, or on the site —
//       and the vocabulary of what that local text is.
// Does not own: reading data, resolving URLs, fetching anything, or presenting. It is a pure value judgement
//       over text the caller already holds.
//
// Why this exists (architect's approved design, 2026-10-11): a local reader shows the stored text when the feed
// published something substantial, and a summary is *never* presented as the article. A card whose stored text is
// only a teaser keeps the site as its primary action, with no intermediate screen.
import Foundation

/// What the local reading surface is showing, in the source's own terms.
public enum FeedReadingOrigin: String, Hashable, Sendable, CaseIterable {
    /// The body the feed itself published (`content` / `content:encoded`).
    case sourceBody
    /// The summary the source supplied. It is a summary, and the surface says so.
    case sourceSummary

    /// The label the reading surface shows for this origin.
    public var label: String {
        switch self {
        case .sourceBody: "Texto publicado pela fonte"
        case .sourceSummary: "Resumo fornecido pela fonte"
        }
    }
}

/// Everything the local reading surface needs, as a value: no storage handle, no view, no clock.
public struct FeedReadingContent: Hashable, Sendable {
    public let origin: FeedReadingOrigin
    public let sourceName: String
    public let headline: String
    public let publishedAt: Date?
    public let text: String
    /// The site, so the surface can offer the explicit way out the design requires. Nil when the card has none.
    public let siteURL: URL?
    /// Whether the app can claim this text is the whole article. It never can: a feed's body is what the feed
    /// chose to publish, and a summary is a summary. Both are shown as partial content, never as the article.
    public let isPartial: Bool

    public init(origin: FeedReadingOrigin, sourceName: String, headline: String, publishedAt: Date?,
        text: String, siteURL: URL? = nil, isPartial: Bool = true) {
        self.origin = origin
        self.sourceName = sourceName
        self.headline = headline
        self.publishedAt = publishedAt
        self.text = text
        self.siteURL = siteURL
        self.isPartial = isPartial
    }
}

/// Where a card's tap leads.
public enum FeedReadingTarget: Hashable, Sendable {
    /// Read it here: the app already holds text worth reading.
    case local(FeedReadingContent)
    /// Read it there: the site, in the app's own reader. This is the primary action for a teaser.
    case site(URL)
}

/// The one rule that decides between the two, so no surface has to invent one.
public enum FeedReadingDecision {
    /// A summary at least this long is worth opening locally. It is a threshold to *open* the reader, never a
    /// claim that the text is the article: 3.000 characters do not prove completeness.
    public static let substantialSummaryCharacters = 3_000

    /// The decision for one card. `nil` means the card offers nothing to read and no address to open.
    public static func target(body: String?, summary: String?, sourceName: String, headline: String,
        publishedAt: Date?, siteURL: URL?) -> FeedReadingTarget? {
        let bodyText = trimmed(body)
        if !bodyText.isEmpty {
            return .local(FeedReadingContent(origin: .sourceBody, sourceName: sourceName, headline: headline,
                publishedAt: publishedAt, text: bodyText, siteURL: siteURL))
        }
        let summaryText = trimmed(summary)
        if summaryText.count >= substantialSummaryCharacters {
            return .local(FeedReadingContent(origin: .sourceSummary, sourceName: sourceName, headline: headline,
                publishedAt: publishedAt, text: summaryText, siteURL: siteURL))
        }
        guard let siteURL else { return nil }
        return .site(siteURL)
    }

    private static func trimmed(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
