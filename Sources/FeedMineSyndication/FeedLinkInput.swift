//
// File: FeedLinkInput.swift
// Module: FeedMineSyndication
//
// Responsibility:
// What the reader typed, as links: the free-form text of V1's "add feeds" field — one address, many, or prose
// with embedded ones — extracted, normalized and classified. Classification only *says* what an address looks
// like; turning it into a feed address is `FeedLinkResolver`'s business.
//
// The rules are V1's `InputParser`, copied rather than reinvented, because classification is what decides
// whether a YouTube channel becomes a channel feed or a page gets discovered:
//   - `NSDataDetector` finds links inside prose; a whitespace/comma separated token pass finds bare domains;
//   - a token with a scheme that is not http(s) is **refused**, never rewritten into `https://javascript:…`;
//   - an address with an `@` and no `/` is an e-mail, not a feed;
//   - classification is ordered, first hit wins (OPML → YouTube → GitHub → podcast hosts → feed path hints →
//     website), with exact-host or subdomain matching only, so `podcasts.apple.com.evil.org` is not a podcast.
//
// Does not own: fetching anything (the transport), deciding which feed an address resolves to (the resolver),
// or storing what the reader added (Composition/Persistence).
import Foundation

/// What an address looks like, exactly as V1 named the kinds.
public enum FeedLinkKind: String, Hashable, Sendable {
    /// A direct RSS/Atom/JSON feed address — only a guess until the resolver probes it.
    case feed
    /// An HTML page: the feed has to be discovered.
    case website
    /// A YouTube channel, video, playlist or handle.
    case youtube
    /// A GitHub repository or user.
    case github
    /// A podcast page or a podcast feed host.
    case podcast
    /// An OPML document, handled by the import pipeline rather than by discovery.
    case opml
    /// Nothing recognizable; treated as a website.
    case unknown
}

public struct FeedLink: Hashable, Sendable {
    /// The token as the reader wrote it.
    public let raw: String
    public let url: URL
    public let kind: FeedLinkKind

    public init(raw: String, url: URL, kind: FeedLinkKind) {
        self.raw = raw
        self.url = url
        self.kind = kind
    }
}

public enum FeedLinkInput {
    /// Every address in the reader's input, in the order they appear, duplicates removed.
    public static func parse(_ text: String) -> [FeedLink] {
        extract(from: text).compactMap { raw in
            guard let url = normalizeWebURL(raw) else { return nil }
            return FeedLink(raw: raw, url: url, kind: classify(url))
        }
    }

    /// A reader-supplied address as a web URL, or nil when it is not one. The scheme vocabulary is closed: a
    /// string that names a non-web scheme is refused rather than rewritten into an apparently-HTTPS address.
    public static func normalizeWebURL(_ raw: String) -> URL? {
        var str = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !str.isEmpty else { return nil }

        if let colon = str.firstIndex(of: ":") {
            let prefix = String(str[..<colon])
            let looksLikeScheme = !prefix.isEmpty
                && prefix.unicodeScalars.allSatisfy {
                    CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "+-.")).contains($0)
                }
            if looksLikeScheme {
                let scheme = prefix.lowercased()
                guard scheme == "http" || scheme == "https" else { return nil }
            }
        } else {
            // An e-mail address would otherwise become an https URL with userinfo, which is a garbage source.
            if str.contains("@") && !str.contains("/") { return nil }
            str = "https://\(str)"
        }

        guard let url = URL(string: str),
            let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// True when `host` is exactly `domain` or a subdomain of it — never a lookalike
    /// (`fake-podcasts.apple.com.evil.org` is not `podcasts.apple.com`).
    static func hostBelongsTo(_ host: String, _ domain: String) -> Bool {
        host == domain || host.hasSuffix(".\(domain)")
    }

    // MARK: - Extraction

    private static func extract(from text: String) -> [String] {
        var found: [(offset: Int, value: String)] = []
        var seen = Set<String>()

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, range: range) {
                guard let url = match.url?.absoluteString, seen.insert(url).inserted else { continue }
                found.append((match.range.location, url))
            }
        }

        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;|"))
        var searched = text.startIndex
        for token in text.components(separatedBy: separators) {
            guard let foundRange = text.range(of: token, range: searched..<text.endIndex) else { continue }
            searched = foundRange.upperBound
            let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'<>()[]{}"))
            guard !trimmed.isEmpty, trimmed.contains("."), !seen.contains(trimmed), !trimmed.contains("@") else { continue }
            let withScheme = trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)"
            guard let url = URL(string: withScheme), url.host != nil, seen.insert(withScheme).inserted else { continue }
            // The token pass runs after the detector, but the reader's own order is the order they typed:
            // a bare domain written first stays first.
            found.append((text.distance(from: text.startIndex, to: foundRange.lowerBound), withScheme))
        }
        return found.sorted { $0.offset < $1.offset }.map(\.value)
    }

    // MARK: - Classification

    static func classify(_ url: URL) -> FeedLinkKind {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        let fullURL = url.absoluteString.lowercased()

        if path.hasSuffix(".opml") || path.hasSuffix(".opml.xml") { return .opml }
        if hostBelongsTo(host, "youtube.com") || hostBelongsTo(host, "youtu.be") { return .youtube }
        if host == "github.com" || host == "www.github.com" { return .github }
        if podcastHosts.contains(where: { hostBelongsTo(host, $0) }) { return .podcast }

        let feedIndicators = ["/feed", "/rss", "/atom", ".xml", ".json", "/feeds/", "feed.xml", "rss.xml",
            "atom.xml", "index.xml", "/feed/"]
        if feedIndicators.contains(where: { path.contains($0) || fullURL.contains($0) }) { return .feed }
        if fullURL.contains("application/rss") || fullURL.contains("application/atom") { return .feed }
        return .website
    }

    /// Podcast platforms whose page or feed needs the podcast rules rather than page discovery. Exact host or
    /// subdomain only.
    static let podcastHosts = ["podcasts.apple.com", "itunes.apple.com", "open.spotify.com", "anchor.fm",
        "feeds.buzzsprout.com", "feeds.simplecast.com", "feeds.megaphone.fm", "rss.art19.com",
        "feeds.transistor.fm", "feeds.acast.com", "feeds.libsyn.com", "pinecast.com", "omny.fm",
        "podbean.com", "spreaker.com", "castbox.fm"]
}
