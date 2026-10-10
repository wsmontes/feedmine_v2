// Owns: protocol-local admission of image locators found in feed items (v1 lessons MD/IN).
// Does not own: downloading, choosing the final card image, or byte inspection (Media owns those).
//
// Real feeds put the wrong image everywhere (v1 commits b42d9a40, 99df7f9b, 71fa05bb, 42ecf862,
// ee1375ab): relative or entity-escaped URLs, tracking pixels, spacers, favicons, emoji, share
// buttons, tiny logos, SVG and audio/video files. These rules keep such locators out of canonical
// supply so later media choice starts from plausible card visuals only.

import Foundation
import FeedMineDomain

enum SyndicationMediaLocator {
    /// Resolves and admits one raw locator, or returns nil when it cannot be a card image.
    /// `allowingPlayableMedia` states what the caller is resolving: the rule below rejects audio/video containers
    /// because they cannot be raster *card visuals* (T9), and a card's own playable payload is exactly such a
    /// container. Every other check — routability, scheme, decoration, malformed nesting — applies to both.
    static func resolve(_ raw: String?, base: URL?, allowingPlayableMedia: Bool = false) -> URL? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        // Entity-escaped ampersands are common in attribute values copied from HTML.
        for escaped in ["&amp;", "&#038;", "&#38;"] { text = text.replacingOccurrences(of: escaped, with: "&") }
        let lower = text.lowercased()
        if lower.hasPrefix("data:") || lower.hasPrefix("javascript:") { return nil }
        let absolute: URL?
        if lower.hasPrefix("//") {
            absolute = URL(string: "https:" + text)
        } else if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            absolute = URL(string: text)
        } else if let base, let scheme = base.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            absolute = URL(string: text, relativeTo: base)?.absoluteURL
        } else {
            absolute = nil
        }
        guard let url = absolute, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
            NetworkHostPolicy.isPubliclyRoutable(host), // review R15: no loopback/LAN/metadata targets
            !isMalformedNestedScheme(lower), allowingPlayableMedia || !isUnsupported(url),
            !isDecorative(url.absoluteString) else { return nil }
        return url
    }

    /// Prefers the smallest `w` candidate that is at least `preferredWidth`, else the largest;
    /// for density descriptors, the first ≥2x, else the largest.
    static func preferredSrcsetCandidate(_ srcset: String?, preferredWidth: Double = 960) -> String? {
        guard let srcset else { return nil }
        let entries: [(url: String, value: Double, unit: Character)] = srcset.split(separator: ",").compactMap { entry in
            let parts = entry.split(whereSeparator: \.isWhitespace)
            guard let first = parts.first, let descriptor = parts.dropFirst().last, let unit = descriptor.last,
                unit == "w" || unit == "x", let number = Double(descriptor.dropLast()), number > 0 else { return nil }
            return (String(first), number, unit)
        }
        let widths = entries.filter { $0.unit == "w" }.sorted { $0.value < $1.value }
        if let sufficient = widths.first(where: { $0.value >= preferredWidth }) { return sufficient.url }
        if let largest = widths.last { return largest.url }
        let densities = entries.filter { $0.unit == "x" }.sorted { $0.value < $1.value }
        return densities.first(where: { $0.value >= 2 })?.url ?? densities.last?.url
    }

    /// First plausible content image in an HTML fragment, honoring lazy-loading attributes.
    /// Decorative images (avatars, share buttons, pixels) are skipped, not returned.
    static func firstContentImage(inHTML html: String?, base: URL?) -> URL? {
        guard let html, html.range(of: "<img", options: .caseInsensitive) != nil
            || html.range(of: "&lt;img", options: .caseInsensitive) != nil else { return nil }
        let unescaped = html.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
        for candidate in [html, unescaped] {
            let range = NSRange(candidate.startIndex..., in: candidate)
            for match in imgTag.matches(in: candidate, range: range) {
                guard let tagRange = Range(match.range, in: candidate) else { continue }
                let tag = String(candidate[tagRange])
                var attributes: [String: String] = [:]
                for attribute in attributePattern.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
                    guard let nameRange = Range(attribute.range(at: 1), in: tag) else { continue }
                    let valueRange = Range(attribute.range(at: 2), in: tag) ?? Range(attribute.range(at: 3), in: tag)
                    guard let valueRange else { continue }
                    let name = tag[nameRange].lowercased()
                    if attributes[name] == nil { attributes[name] = String(tag[valueRange]) }
                }
                func first(_ names: [String]) -> String? { names.lazy.compactMap { attributes[$0] }.first }
                let srcset = first(["data-lazy-srcset", "data-srcset", "srcset"])
                let source = preferredSrcsetCandidate(srcset)
                    ?? first(["data-lazy-src", "data-original", "data-orig-file", "data-src", "src"])
                if let url = resolve(source, base: base) { return url }
            }
        }
        return nil
    }

    // MARK: - Rules

    // Immutable after construction; NSRegularExpression matching is thread-safe.
    nonisolated(unsafe) private static let imgTag = try! NSRegularExpression(pattern: "<img\\b[^>]*>", options: [.caseInsensitive])
    nonisolated(unsafe) private static let attributePattern = try! NSRegularExpression(
        pattern: "([a-zA-Z_:][-a-zA-Z0-9_:.]*)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')", options: [])
    // Two to four digits per side so aspect ratios such as 16x9 or 4x3 are never mistaken for sizes.
    nonisolated(unsafe) private static let tinyDimension = try! NSRegularExpression(
        pattern: "(?:^|[-_./])(\\d{2,4})x(\\d{2,4})(?:[-_.?/&]|$)", options: [])

    private static let decorativeMarkers = [
        "favicon", "gravatar.com/avatar", "/emoji/", "s.w.org/images/core/emoji", "addtoany.com/buttons",
        "share_save", "icon_facebook", "icon_twitter", "feeds.feedburner.com/~ff", "feeds.feedburner.com/~r",
        "/tracker/", "count.gif", "pixel.gif", "track-rss-story", "blank.gif", "1x1.gif", "1x1.png", "spacer.gif",
        "spacer.png", "doubleclick.net", "pixel.wp.com", "stats.wordpress.com"
    ]

    /// Tracking pixels, spacers, avatars, emoji, share buttons and tiny (≤150 px) sized variants.
    static func isDecorative(_ text: String) -> Bool {
        let lower = text.lowercased()
        if decorativeMarkers.contains(where: { lower.contains($0) }) { return true }
        if lower.contains("tracking") && lower.contains("pixel") { return true }
        let range = NSRange(lower.startIndex..., in: lower)
        for match in tinyDimension.matches(in: lower, range: range) {
            guard let w = Range(match.range(at: 1), in: lower).flatMap({ Int(lower[$0]) }),
                let h = Range(match.range(at: 2), in: lower).flatMap({ Int(lower[$0]) }) else { continue }
            if w <= 150 && h <= 150 { return true }
        }
        return false
    }

    /// SVG and audio/video containers cannot be raster card visuals; embeds are pages, not images.
    private static func isUnsupported(_ url: URL) -> Bool {
        let lower = url.absoluteString.lowercased()
        if lower.contains("youtube.com/embed/") { return true }
        let ext = url.pathExtension.lowercased()
        return ["svg", "svgz", "mp3", "m4a", "aac", "wav", "ogg", "opus", "mp4", "m4v", "mov", "webm", "pdf", "html", "htm"]
            .contains(ext)
    }

    /// `image.jpghttps://...` is malformed; `/https://...` and `?url=https://...` are proxies.
    private static func isMalformedNestedScheme(_ lower: String) -> Bool {
        let schemeLength = lower.hasPrefix("https://") ? 8 : lower.hasPrefix("http://") ? 7 : 0
        guard schemeLength > 0 else { return false }
        let tail = lower.dropFirst(schemeLength)
        let nested = ["http://", "https://"].compactMap { tail.range(of: $0) }.min { $0.lowerBound < $1.lowerBound }
        guard let nested else { return false }
        let prefix = tail[..<nested.lowerBound]
        return prefix.last != "/" && prefix.last != "="
    }

    static func isImageMIMEType(_ value: String?) -> Bool {
        guard let type = value?.lowercased(), type.hasPrefix("image/") else { return false }
        return !type.contains("svg")
    }
}
