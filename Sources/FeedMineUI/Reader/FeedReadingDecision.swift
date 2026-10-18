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
// only a teaser keeps the site as its primary action, with no intermediate screen — but only when the card carries
// an address the app can open. Without one, the text the app already holds is still the reading it can offer, and
// the surface shows it honestly instead of leaving the tap with no target (review, 2026-10-17).
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
    /// chose to publish, and a summary is a summary, so completeness stays unconfirmed. The surface says exactly
    /// that — text the source supplied, completeness not confirmed — never that the article is on the site.
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

    /// The decision for one card. `nil` means the card supplies no text to read and no address to open: there is
    /// nothing to show and nothing a tap could promise.
    ///
    /// A teaser — a summary below `substantialSummaryCharacters` — keeps the site as its primary action when the
    /// card carries a usable address, with no intermediate screen. Without one, its own text is still the only
    /// reading the card has, so the app shows that text locally rather than dropping the tap: a saved article whose
    /// address no longer resolves must stay readable offline. The surface then states what the app knows and
    /// promises nothing more.
    public static func target(body: String?, summary: String?, sourceName: String, headline: String,
        publishedAt: Date?, siteURL: URL?) -> FeedReadingTarget? {
        let site = usableSiteURL(siteURL)
        let bodyText = trimmed(body)
        if !bodyText.isEmpty {
            return .local(FeedReadingContent(origin: .sourceBody, sourceName: sourceName, headline: headline,
                publishedAt: publishedAt, text: bodyText, siteURL: site))
        }
        let summaryText = trimmed(summary)
        if !summaryText.isEmpty {
            if summaryText.count >= substantialSummaryCharacters {
                return .local(FeedReadingContent(origin: .sourceSummary, sourceName: sourceName,
                    headline: headline, publishedAt: publishedAt, text: summaryText, siteURL: site))
            }
            if let site { return .site(site) }
            return .local(FeedReadingContent(origin: .sourceSummary, sourceName: sourceName, headline: headline,
                publishedAt: publishedAt, text: summaryText, siteURL: nil))
        }
        guard let site else { return nil }
        return .site(site)
    }

    /// An address the app can actually put in front of the reader: the in-app browser opens http(s) and needs a
    /// host. Anything else — `mailto:`, a reference the browser cannot load, an address with no host — is not a
    /// door, and offering it would be a control that cannot work.
    public static func usableSiteURL(_ url: URL?) -> URL? {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    private static func trimmed(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
