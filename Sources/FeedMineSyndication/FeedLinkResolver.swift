//
// File: FeedLinkResolver.swift
// Module: FeedMineSyndication
//
// Responsibility:
// Turning a link the reader pasted into the feed address to fetch. V1's `URLResolver`, with the same order and
// the same rules, because the order *is* the behaviour:
//
//   1. a "feed-looking" address is still only a guess — it is probed, and falls through to page discovery when
//      the probe says it is not a feed;
//   2. a page is read once (bounded) for `<link rel="alternate">` of a feed type, and only when that finds
//      nothing are the common feed paths probed — three at a time, under a deadline, first match wins;
//   3. YouTube, GitHub and podcast addresses have their own rules (`/channel/<id>` → the channel feed,
//      `/user/repo` → `releases.atom`, `podcasts.apple.com/…/id<digits>` → the iTunes lookup's `feedUrl`);
//   4. nothing found is reported as such, per input, so a surface can say which address failed and why.
//
// Does not own: typing rules (FeedLinkInput), the network (FeedDiscoveryTransport), or storing the result.
import Foundation

public enum FeedLinkMediaKind: String, Hashable, Sendable {
    case text
    case video
    case audio
}

/// One feed address a link resolved to.
public struct ResolvedFeedLink: Hashable, Sendable {
    /// The address to fetch.
    public let feedURL: String
    /// The title the page or the rule supplied, when there is one.
    public let title: String?
    /// The link the reader pasted.
    public let sourceURL: String
    public let mediaKind: FeedLinkMediaKind

    public init(feedURL: String, title: String?, sourceURL: String, mediaKind: FeedLinkMediaKind) {
        self.feedURL = feedURL
        self.title = title
        self.sourceURL = sourceURL
        self.mediaKind = mediaKind
    }
}

public enum FeedLinkFailure: String, Hashable, Sendable {
    /// The address answered but no feed could be found (no alternate link, no common path).
    case noFeedFound
    /// The address could not be reached at all.
    case unreachable
    /// The address named something this build cannot resolve (a GitHub owner with no repository, say).
    case invalidURL
    /// The address is one this app will not fetch (a private host), or answered with too much data.
    case refused
}

public struct FeedLinkResolution: Hashable, Sendable {
    public let link: FeedLink
    public let feeds: [ResolvedFeedLink]
    public let failure: FeedLinkFailure?

    public init(link: FeedLink, feeds: [ResolvedFeedLink], failure: FeedLinkFailure?) {
        self.link = link
        self.feeds = feeds
        self.failure = failure
    }

    var isEmpty: Bool { feeds.isEmpty }
}

public struct FeedLinkResolver: Sendable {
    /// The bounds and the pace. V1's own numbers, so discovery costs what it always cost.
    public struct Budget: Hashable, Sendable {
        public var pageByteCeiling = 256_000
        public var probeByteCeiling = 64_000
        public var channelByteCeiling = 512_000
        public var lookupByteCeiling = 1_000_000
        public var requestTimeout: TimeInterval = 8
        public var probeTimeout: TimeInterval = 5
        public var discoveryDeadline: TimeInterval = 8
        public var resolutionConcurrency = 5
        public var probeConcurrency = 3

        public init() {}
    }

    private let transport: any FeedDiscoveryTransport
    private let budget: Budget

    public init(transport: any FeedDiscoveryTransport, budget: Budget = Budget()) {
        self.transport = transport
        self.budget = budget
    }

    /// Every link resolved, in the order they were given, at most `resolutionConcurrency` in flight.
    public func resolveAll(_ links: [FeedLink]) async -> [FeedLinkResolution] {
        guard !links.isEmpty else { return [] }
        let width = max(1, budget.resolutionConcurrency)
        var results = [FeedLinkResolution?](repeating: nil, count: links.count)
        await withTaskGroup(of: (Int, FeedLinkResolution).self) { group in
            var next = 0
            while next < min(width, links.count) {
                let index = next
                let link = links[index]
                group.addTask { (index, await self.resolve(link)) }
                next += 1
            }
            while let (index, resolution) = await group.next() {
                results[index] = resolution
                if next < links.count {
                    let queued = next
                    let link = links[queued]
                    group.addTask { (queued, await self.resolve(link)) }
                    next += 1
                }
            }
        }
        return results.compactMap { $0 }
    }

    /// One link, by its kind.
    public func resolve(_ link: FeedLink) async -> FeedLinkResolution {
        switch link.kind {
        case .opml:
            // An OPML is the import pipeline's business: it is a list of feeds, not one.
            return FeedLinkResolution(link: link, feeds: [], failure: nil)
        case .feed:
            if await servesAFeed(link.url) {
                return .init(link: link, feeds: [ResolvedFeedLink(feedURL: link.url.absoluteString, title: nil,
                    sourceURL: link.raw, mediaKind: .text)], failure: nil)
            }
            return await discoverFeeds(link)
        case .website, .unknown:
            return await discoverFeeds(link)
        case .youtube:
            return await resolveYouTube(link)
        case .github:
            return await resolveGitHub(link)
        case .podcast:
            return await resolvePodcast(link)
        }
    }

    // MARK: - Probing

    /// Is this address serving a feed? A HEAD first, and a small ranged GET when the server refuses HEAD.
    private func servesAFeed(_ url: URL) async -> Bool {
        do {
            let response = try await transport.send(FeedDiscoveryRequest(url: url, method: .head,
                timeout: budget.probeTimeout, byteCeiling: budget.probeByteCeiling))
            if response.statusCode == 405 || response.statusCode == 501 { return await probeRanged(url) }
            return response.statusCode == 200 && Self.isFeedContentType(response.contentType)
        } catch {
            return await probeRanged(url)
        }
    }

    private func probeRanged(_ url: URL) async -> Bool {
        do {
            let response = try await transport.send(FeedDiscoveryRequest(url: url, method: .get,
                range: "bytes=0-511", timeout: budget.probeTimeout, byteCeiling: budget.probeByteCeiling))
            guard response.isUsable || response.statusCode == 206 else { return false }
            return Self.sniffsAsFeed(response.body)
        } catch {
            return false
        }
    }

    private func probeCandidate(_ urlString: String) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        do {
            let response = try await transport.send(FeedDiscoveryRequest(url: url, method: .get,
                range: "bytes=0-511", timeout: budget.probeTimeout, byteCeiling: budget.probeByteCeiling))
            guard response.isUsable else { return false }
            return Self.sniffsAsFeed(response.body)
        } catch {
            return false
        }
    }

    /// The content types a feed answers with. V1's list, including the JSON Feed type.
    static func isFeedContentType(_ raw: String?) -> Bool {
        let contentType = raw?.lowercased() ?? ""
        let feedTypes = ["application/rss+xml", "application/atom+xml", "application/feed+json",
            "application/json", "application/xml", "text/xml"]
        return feedTypes.contains { contentType.hasPrefix($0) }
    }

    /// The first bytes of a feed. V1's own sniff (`ImportPipeline.looksLikeFeedData`): an XML declaration, one
    /// of the three feed roots, or a JSON object.
    static func sniffsAsFeed(_ data: Data) -> Bool {
        let prefix = String(decoding: data.prefix(512), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix.hasPrefix("<?xml") || prefix.hasPrefix("<rss") || prefix.hasPrefix("<feed")
            || prefix.hasPrefix("<atom") || prefix.hasPrefix("<RDF") || prefix.hasPrefix("{")
    }

    // MARK: - Page discovery

    private func discoverFeeds(_ link: FeedLink) async -> FeedLinkResolution {
        if let declared = await declaredFeeds(on: link), !declared.isEmpty {
            return FeedLinkResolution(link: link, feeds: declared, failure: nil)
        }
        let root = "\(link.url.scheme ?? "https")://\(link.url.host ?? "")"
        let candidates = Self.commonFeedPaths.map { root + $0 }
        if let match = await firstServingFeed(candidates) {
            return FeedLinkResolution(link: link, feeds: [ResolvedFeedLink(feedURL: match, title: nil,
                sourceURL: link.raw, mediaKind: .text)], failure: nil)
        }
        return FeedLinkResolution(link: link, feeds: [], failure: .noFeedFound)
    }

    /// The common paths V1 probed, in its own order.
    static let commonFeedPaths = ["/feed", "/rss", "/atom.xml", "/feed.xml", "/rss.xml", "/index.xml", "/feed/",
        "/feeds/posts/default", "/?feed=rss2"]

    /// The page's own `<link rel="alternate">` declarations, if it has any. One bounded read of the page.
    private func declaredFeeds(on link: FeedLink) async -> [ResolvedFeedLink]? {
        guard let response = try? await transport.send(FeedDiscoveryRequest(url: link.url,
            timeout: budget.requestTimeout, byteCeiling: budget.pageByteCeiling)),
            response.isUsable, let html = String(data: response.body, encoding: .utf8) else { return nil }
        let pattern = #"<link[^>]+rel\s*=\s*["']alternate["'][^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let types = ["application/rss+xml", "application/atom+xml", "application/json", "application/feed+json"]
        var feeds: [ResolvedFeedLink] = []
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range, in: html) else { continue }
            let tag = String(html[range])
            guard types.contains(where: { tag.lowercased().contains($0) }) else { continue }
            guard let href = Self.attribute("href", in: tag) else { continue }
            var address = href
            if !address.hasPrefix("http") {
                // Relative addresses the string concatenation of a naive resolver gets wrong: `../feed.xml`,
                // `//cdn.example.com/feed`, `?output=rss`.
                address = URL(string: href, relativeTo: link.url)?.absoluteString ?? href
            }
            feeds.append(ResolvedFeedLink(feedURL: address, title: Self.attribute("title", in: tag),
                sourceURL: link.url.absoluteString, mediaKind: .text))
        }
        return feeds.isEmpty ? nil : feeds
    }

    /// Probes candidates in parallel and returns the first that serves a feed. A deadline bounds the whole
    /// search, and the group ends as soon as every candidate has answered — a site with no feed does not pay
    /// the full deadline for nothing (V1's S20 fix), and the deadline *returns* instead of waiting for probes
    /// that are still in flight.
    private enum ProbeEvent: Sendable {
        case match(String)
        case miss
        case deadline
    }

    private func firstServingFeed(_ candidates: [String]) async -> String? {
        await withTaskGroup(of: ProbeEvent.self) { group in
            let width = max(1, budget.probeConcurrency)
            var iterator = candidates.makeIterator()
            var started = 0
            var outstanding = 0
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(max(0, self.budget.discoveryDeadline) * 1_000_000_000))
                return .deadline
            }
            while started < width, let candidate = iterator.next() {
                group.addTask { await self.probeCandidate(candidate) ? .match(candidate) : .miss }
                started += 1
                outstanding += 1
            }
            while let event = await group.next() {
                switch event {
                case .match(let matched):
                    group.cancelAll()
                    return matched
                case .deadline:
                    group.cancelAll()
                    return nil
                case .miss:
                    outstanding -= 1
                    if let candidate = iterator.next() {
                        group.addTask { await self.probeCandidate(candidate) ? .match(candidate) : .miss }
                        outstanding += 1
                    } else if outstanding <= 0 {
                        // Every candidate has answered and none is a feed; the deadline child is all that is
                        // left, so the search ends now instead of waiting it out.
                        group.cancelAll()
                        return nil
                    }
                }
            }
            return nil
        }
    }

    // MARK: - YouTube

    private func resolveYouTube(_ link: FeedLink) async -> FeedLinkResolution {
        let url = link.url
        let components = url.pathComponents
        func video(_ feedURL: String) -> FeedLinkResolution {
            FeedLinkResolution(link: link, feeds: [ResolvedFeedLink(feedURL: feedURL, title: nil,
                sourceURL: link.raw, mediaKind: .video)], failure: nil)
        }
        if url.path.lowercased().contains("/feeds/") { return video(url.absoluteString) }
        if components.count >= 3, components[1].lowercased() == "channel" {
            return video("https://www.youtube.com/feeds/videos.xml?channel_id=\(components[2])")
        }
        if let playlist = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "list" })?.value {
            return video("https://www.youtube.com/feeds/videos.xml?playlist_id=\(playlist)")
        }
        if let channel = await youTubeChannelID(of: url) {
            return video("https://www.youtube.com/feeds/videos.xml?channel_id=\(channel)")
        }
        return FeedLinkResolution(link: link, feeds: [], failure: .noFeedFound)
    }

    /// A channel page carries its own id: the itemprop meta tag, the JSON payload, or a canonical link.
    private func youTubeChannelID(of url: URL) async -> String? {
        guard let response = try? await transport.send(FeedDiscoveryRequest(url: url,
            timeout: budget.requestTimeout, byteCeiling: budget.channelByteCeiling)),
            response.isUsable, let html = String(data: response.body, encoding: .utf8) else { return nil }
        let patterns = [
            #"<meta[^>]+itemprop\s*=\s*["']channelId["'][^>]+content\s*=\s*["']([^"']+)["']"#,
            #""channelId"\s*:\s*"(UC[^"]+)""#,
            #"/channel/(UC[a-zA-Z0-9_-]+)"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                let range = Range(match.range(at: 1), in: html) else { continue }
            return String(html[range])
        }
        return nil
    }

    // MARK: - GitHub

    private func resolveGitHub(_ link: FeedLink) async -> FeedLinkResolution {
        let components = link.url.pathComponents
        guard components.count >= 2 else {
            return FeedLinkResolution(link: link, feeds: [], failure: .invalidURL)
        }
        let user = components[1]
        if components.count >= 3 {
            let repo = components[2]
            return FeedLinkResolution(link: link, feeds: [ResolvedFeedLink(
                feedURL: "https://github.com/\(user)/\(repo)/releases.atom", title: "\(repo) releases",
                sourceURL: link.raw, mediaKind: .text)], failure: nil)
        }
        return FeedLinkResolution(link: link, feeds: [ResolvedFeedLink(feedURL: "https://github.com/\(user).atom",
            title: "\(user) activity", sourceURL: link.raw, mediaKind: .text)], failure: nil)
    }

    // MARK: - Podcasts

    private func resolvePodcast(_ link: FeedLink) async -> FeedLinkResolution {
        let host = link.url.host?.lowercased() ?? ""
        func audio(_ feedURL: String, title: String? = nil) -> FeedLinkResolution {
            FeedLinkResolution(link: link, feeds: [ResolvedFeedLink(feedURL: feedURL, title: title,
                sourceURL: link.raw, mediaKind: .audio)], failure: nil)
        }
        if FeedLinkInput.hostBelongsTo(host, "podcasts.apple.com") || FeedLinkInput.hostBelongsTo(host, "itunes.apple.com"),
            let feedURL = await applePodcastFeedURL(link.url) {
            return audio(feedURL)
        }
        if FeedLinkInput.hostBelongsTo(host, "anchor.fm") {
            return audio("https://anchor.fm\(link.url.path)/rss")
        }
        if Self.directPodcastFeedHosts.contains(where: { FeedLinkInput.hostBelongsTo(host, $0) }) {
            return audio(link.url.absoluteString)
        }
        return await discoverFeeds(link)
    }

    /// Feed hosts whose own page address is already the feed.
    static let directPodcastFeedHosts = ["feeds.buzzsprout.com", "feeds.simplecast.com", "feeds.megaphone.fm",
        "rss.art19.com", "feeds.transistor.fm", "feeds.acast.com", "feeds.libsyn.com", "pinecast.com", "omny.fm"]

    /// Apple Podcasts pages carry the show's id; the public lookup answers with the show's own feed.
    private func applePodcastFeedURL(_ url: URL) async -> String? {
        let path = url.path
        guard let regex = try? NSRegularExpression(pattern: #"id(\d+)"#),
            let match = regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)),
            let range = Range(match.range(at: 1), in: path) else { return nil }
        let identifier = String(path[range])
        guard let lookup = URL(string: "https://itunes.apple.com/lookup?id=\(identifier)&entity=podcast"),
            let response = try? await transport.send(FeedDiscoveryRequest(url: lookup,
                timeout: budget.requestTimeout, byteCeiling: budget.lookupByteCeiling)),
            response.isUsable,
            let json = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
            let results = json["results"] as? [[String: Any]],
            let feedURL = results.first?["feedUrl"] as? String else { return nil }
        return feedURL
    }

    // MARK: - HTML attributes

    /// One attribute's value from a tag, whatever order the attributes are written in.
    static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = #"\#(name)\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
            let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
            let range = Range(match.range(at: 1), in: tag) else { return nil }
        return String(tag[range])
    }
}
