// FeedKit values remain inside this module; output is protocol-free acquisition facts.
import Foundation
import CryptoKit
import FeedKit
import FeedMineDomain
import FeedMineAcquisition

public enum SyndicationDocumentKind: Hashable, Sendable { case rss, rdf, atom, json }
public enum SyndicationItemRejectionReason: Hashable, Sendable { case missingStableIdentity, invalidCanonicalObservation }
public struct SyndicationItemRejection: Hashable, Sendable {
    public let index: Int
    public let reason: SyndicationItemRejectionReason
    public init(index: Int, reason: SyndicationItemRejectionReason) { self.index = index; self.reason = reason }
}
public struct SyndicationTranslation: Hashable, Sendable {
    public let documentKind: SyndicationDocumentKind
    public let observations: [AcquisitionObservation]
    public let rejections: [SyndicationItemRejection]
    public let declaredItemCount: Int
    public let examinedItemCount: Int
    public let nextItemIndex: Int?
    public var consumedWholeDocument: Bool { nextItemIndex == nil }
    fileprivate init(documentKind: SyndicationDocumentKind, observations: [AcquisitionObservation],
        rejections: [SyndicationItemRejection], declaredItemCount: Int, examinedItemCount: Int, nextItemIndex: Int?) {
        self.documentKind = documentKind; self.observations = observations; self.rejections = rejections
        self.declaredItemCount = declaredItemCount; self.examinedItemCount = examinedItemCount; self.nextItemIndex = nextItemIndex
    }
}
public enum SyndicationTranslationError: Error, Equatable, Sendable {
    case invalidObservedAt, invalidStartIndex, invalidItemCapacity, parseFailed
}
public struct SyndicationTranslator: Sendable {
    public init() {}
    public func translate(data: Data, configuration: SyndicationTargetConfiguration, observedAt: Date,
        startIndex: Int, itemCapacity: Int) throws -> SyndicationTranslation {
        guard observedAt.timeIntervalSince1970.isFinite else { throw SyndicationTranslationError.invalidObservedAt }
        guard startIndex >= 0 else { throw SyndicationTranslationError.invalidStartIndex }
        guard itemCapacity > 0 else { throw SyndicationTranslationError.invalidItemCapacity }
        let feed: Feed
        do { feed = try Feed(data: data) } catch { throw SyndicationTranslationError.parseFailed }
        let prefix = "syndication:" + configuration.targetID.rawValue.uuidString.lowercased()
        func identity(_ suffix: String, _ value: String, _ role: ExternalIdentityRole = .object) -> ExternalIdentity {
            .init(connectorKind: .syndication, namespace: prefix + ":" + suffix, value: value, role: role)
        }
        func observation(_ object: ExternalIdentity?, version: ExternalIdentity? = nil, title: String?, summary: String?,
            body: String? = nil, bodySourceElement: String? = nil, fingerprintGeneration: Int = 1,
            authored: Date?, modified: Date? = nil, language: String? = nil, link: String?,
            media: [AcquisitionMediaCandidateClaim], declaredSubjects: StoryDeclaredSubjects? = nil) -> Result<AcquisitionObservation, ItemFailure> {
            guard let object else { return .failure(.missingStableIdentity) }
            // v1 lesson IN-4 / review M12: a future-dated item would pin itself to the top of a
            // recency order forever, so the accepted value is clamped to the observation; identity is
            // unchanged. TX-07D: the clamp is not silent at the boundary that applies it. The origin's own
            // claim travels beside the accepted value (`declaredAuthoredAt` / `declaredModifiedAt`) and the
            // acceptance rule is the domain's `OriginDeclaredInstant.accepted(observingAt:)`, stated once and
            // nowhere else. The claim is transient: admission validates it and does not persist it, so
            // canonical supply keeps the accepted value only and the editorial contract states the resulting
            // ambiguity instead of calling that value a declared date.
            let declaredAuthored = authored.map(OriginDeclaredInstant.init(claimed:))
            let declaredModified = modified.map(OriginDeclaredInstant.init(claimed:))
            func accepted(_ declared: OriginDeclaredInstant?) -> Date? {
                declared.map { $0.accepted(observingAt: observedAt) }
            }
            // PD-1 / review H1 follow-up 1: publishers edit articles without touching `updated` /
            // `date_modified`. The version identity is the claimed date plus a fingerprint of the
            // material content, so a real edit is a genuinely new version and identical replay is
            // still recognized. Whitespace churn is not material.
            let legacyVersion = version.map { claimed in
                ExternalIdentity(connectorKind: claimed.connectorKind, namespace: claimed.namespace,
                    value: claimed.value + ":" + Self.materialFingerprint(title: title, summary: summary,
                        body: fingerprintGeneration == 2 ? nil : body, link: link, media: media), role: claimed.role)
            }
            let materialVersion: ExternalIdentity?
            if fingerprintGeneration == 2 {
                materialVersion = version.map { claimed in
                    ExternalIdentity(connectorKind: claimed.connectorKind, namespace: claimed.namespace,
                        value: claimed.value + ":g2:" + Self.materialFingerprint(title: title, summary: summary,
                            body: body, link: link, media: media, sourceElement: bodySourceElement), role: claimed.role)
                }
            } else {
                materialVersion = legacyVersion
            }
            guard let value = AcquisitionObservation(objectIdentity: object, versionIdentity: materialVersion, precedence: .makeCurrent,
                availability: .available, headline: title, summary: summary, bodyText: body, authoredAt: accepted(declaredAuthored),
                modifiedAt: accepted(declaredModified), observedAt: observedAt, language: language, primaryLink: Self.webURL(link),
                searchProjection: nil, providerID: nil, memberships: configuration.memberships, mediaCandidates: media,
                fingerprintGeneration: fingerprintGeneration, legacyVersionIdentity: fingerprintGeneration == 2 ? legacyVersion : nil,
                bodySourceElement: bodySourceElement, declaredAuthoredAt: authored, declaredModifiedAt: modified,
                declaredSubjects: declaredSubjects)
            else { return .failure(.invalidCanonicalObservation) }
            return .success(value)
        }
        func rss(_ item: RSSFeedItem, kind: String, language: String?) -> Result<AcquisitionObservation, ItemFailure> {
            let object = Self.nonempty(item.guid?.text).map { identity(kind + "-guid", $0) }
                ?? Self.nonempty(item.link).map { identity(kind + "-link", SyndicationItemIdentity.linkIdentity($0)) }
            let base = Self.webURL(item.link)
            var media: [AcquisitionMediaCandidateClaim] = []
            if let image = Self.media(item.iTunes?.image?.attributes?.href, base: base) { media.append(image) }
            media += Self.thumbnails(item.media?.thumbnails, base: base)
            media += Self.contents(item.media?.contents, base: base)
            media += Self.thumbnails(item.media?.group?.thumbnails, base: base)
            media += Self.contents(item.media?.group?.contents, base: base)
            if let enclosure = item.enclosure?.attributes, SyndicationMediaLocator.isImageMIMEType(enclosure.type),
                let image = Self.media(enclosure.url, base: base, mimeType: enclosure.type) { media.append(image) }
            if let image = Self.htmlImage(item.content?.encoded ?? item.description, base: base) { media.append(image) }
            if let enclosure = item.enclosure?.attributes,
                let playable = Self.playback(enclosure.url, base: base, mimeType: enclosure.type) {
                media.append(playable)
            }
            // Spec 2026-10-24 §2.2: at most one playback per revision, and the item's own enclosure is its
            // canonical payload, so a video `media:content` declares only when the enclosure claimed nothing.
            if !media.contains(where: { $0.role == .playback }),
                let video = Self.contentPlayback((item.media?.contents ?? []) + (item.media?.group?.contents ?? []),
                    base: base) {
                media.append(video)
            }
            let body = Self.readableBody(item.content?.encoded)
            return observation(object, title: item.title, summary: item.description, body: body,
                bodySourceElement: body == nil ? nil : "content:encoded", fingerprintGeneration: 2,
                authored: item.pubDate, language: language, link: item.link, media: Self.unique(media),
                declaredSubjects: Self.declaredSubjects(in: item.categories))
        }
        switch feed {
        case .rss(let document):
            return try window(document.channel?.items ?? [], kind: .rss, start: startIndex, capacity: itemCapacity) {
                rss($0, kind: "rss", language: document.channel?.language)
            }
        case .rdf(let document):
            return try window(document.items ?? [], kind: .rdf, start: startIndex, capacity: itemCapacity) {
                rss($0, kind: "rdf", language: nil)
            }
        case .atom(let document):
            return try window(document.entries ?? [], kind: .atom, start: startIndex, capacity: itemCapacity) { item in
                let link = item.links?.first { link in
                    (link.attributes?.rel == nil || link.attributes?.rel?.lowercased() == "alternate")
                        && Self.nonempty(link.attributes?.href) != nil
                }?.attributes?.href
                let object = Self.nonempty(item.id).map { identity("atom-id", $0) }
                    ?? link.map { identity("atom-link", SyndicationItemIdentity.linkIdentity($0)) }
                let version = item.updated.map { identity("atom-updated", String($0.timeIntervalSinceReferenceDate.bitPattern, radix: 16), .version) }
                let base = Self.webURL(link)
                var media = Self.thumbnails(item.media?.thumbnails, base: base) + Self.contents(item.media?.contents, base: base)
                    + Self.thumbnails(item.media?.group?.thumbnails, base: base) + Self.contents(item.media?.group?.contents, base: base)
                for enclosure in item.links ?? [] where enclosure.attributes?.rel?.lowercased() == "enclosure"
                    && SyndicationMediaLocator.isImageMIMEType(enclosure.attributes?.type) {
                    if let image = Self.media(enclosure.attributes?.href, base: base, mimeType: enclosure.attributes?.type) {
                        media.append(image)
                    }
                }
                if let image = Self.htmlImage(item.content?.text ?? item.summary?.text, base: base) { media.append(image) }
                for enclosure in item.links ?? [] where enclosure.attributes?.rel?.lowercased() == "enclosure" {
                    if let playable = Self.playback(enclosure.attributes?.href, base: base,
                        mimeType: enclosure.attributes?.type) { media.append(playable) }
                }
                // Spec 2026-10-24 §2.2: at most one playback per revision, and the entry's own enclosure is its
                // canonical payload, so a video `media:content` declares only when the enclosure claimed nothing.
                if !media.contains(where: { $0.role == .playback }),
                    let video = Self.contentPlayback((item.media?.contents ?? []) + (item.media?.group?.contents ?? []),
                        base: base) {
                    media.append(video)
                }
                // Atom src is an external resource, not content provided by the feed.
                let contentType = (item.content?.attributes?.type ?? "text").lowercased()
                let body: String?
                if item.content?.attributes?.src != nil {
                    body = nil
                } else {
                    switch contentType {
                    case "text", "text/plain":
                        // Atom text constructs carry literal text; do not interpret escaped angle brackets.
                        body = Self.literalBody(item.content?.text)
                    case "html", "xhtml", "text/html", "application/xhtml+xml":
                        body = Self.readableBody(item.content?.text)
                    default:
                        body = nil
                    }
                }
                return observation(object, version: version, title: item.title, summary: item.summary?.text,
                    body: body, bodySourceElement: body == nil ? nil : "content", fingerprintGeneration: 2,
                    authored: item.published, modified: item.updated, link: link, media: Self.unique(media),
                    declaredSubjects: Self.declaredSubjects(in: item.categories))
            }
        case .json(let document):
            return try window(document.items ?? [], kind: .json, start: startIndex, capacity: itemCapacity) { item in
                let object = Self.nonempty(item.id).map { identity("json-id", $0) }
                let version = item.dateModified.map { identity("json-modified", String($0.timeIntervalSinceReferenceDate.bitPattern, radix: 16), .version) }
                let link = Self.nonempty(item.url) ?? item.externalURL
                let base = Self.webURL(link)
                var media = [Self.media(item.image, base: base), Self.media(item.bannerImage, base: base)].compactMap { $0 }
                for attachment in item.attachments ?? [] where SyndicationMediaLocator.isImageMIMEType(attachment.mimeType) {
                    if let image = Self.media(attachment.url, base: base, mimeType: attachment.mimeType) { media.append(image) }
                }
                if let image = Self.htmlImage(item.contentHtml, base: base) { media.append(image) }
                for attachment in item.attachments ?? [] {
                    if let playable = Self.playback(attachment.url, base: base, mimeType: attachment.mimeType) {
                        media.append(playable)
                    }
                }
                return observation(object, version: version, title: item.title, summary: item.summary, body: item.contentText,
                    authored: item.datePublished, modified: item.dateModified, language: item.language,
                    link: link, media: Self.unique(media), declaredSubjects: Self.declaredSubjects(in: item.tags))
            }
        }
    }
    private enum ItemFailure: Error { case missingStableIdentity, invalidCanonicalObservation }
    private func window<Item>(_ items: [Item], kind: SyndicationDocumentKind, start: Int, capacity: Int,
        translate: (Item) -> Result<AcquisitionObservation, ItemFailure>) throws -> SyndicationTranslation {
        guard start <= items.count else { throw SyndicationTranslationError.invalidStartIndex }
        let examined = min(capacity, items.count - start)
        let end = start + examined
        var observations: [AcquisitionObservation] = []
        var rejections: [SyndicationItemRejection] = []
        for index in start..<end {
            switch translate(items[index]) {
            case .success(let value): observations.append(value)
            case .failure(let reason): rejections.append(.init(index: index,
                reason: reason == .missingStableIdentity ? .missingStableIdentity : .invalidCanonicalObservation))
            }
        }
        return .init(documentKind: kind, observations: observations, rejections: rejections,
            declaredItemCount: items.count, examinedItemCount: examined, nextItemIndex: end < items.count ? end : nil)
    }
    /// The item's own `<category>` declarations as neutral claims: the element text is the declared
    /// subject and its optional `domain` attribute names the taxonomy — exactly what FeedKit's
    /// `RSSFeedItem.categories` carries (`XMLElement<RSSFeedCategoryAttributes>`, whose `text` and
    /// `attributes.domain` the decoder fills from `<category>movies</category>` and
    /// `<category domain="...">1983/V</category>`). The channel's own `<category>` elements are the feed's
    /// taxonomy, not the story's subject, and are never consulted here.
    private static func declaredSubjects(in categories: [RSSFeedCategory]?) -> StoryDeclaredSubjects? {
        StoryDeclaredSubjects((categories ?? []).compactMap { element in
            DeclaredSubjectClaim(surface: .rssItemCategory, scheme: element.attributes?.domain, label: element.text)
        })
    }

    /// The entry's own `atom:category` declarations. FeedKit's `AtomFeedEntry.categories` is an
    /// `XMLAttributesElement<AtomFeedCategoryAttributes>`: it carries no element text, only attributes, so
    /// the declared subject is `term` and the named taxonomy is `scheme`. Atom's `label` attribute is
    /// display text for an end-user application rather than the declared subject, so it is not carried and
    /// cannot change an identity. The feed's own categories are not consulted.
    private static func declaredSubjects(in categories: [AtomFeedCategory]?) -> StoryDeclaredSubjects? {
        StoryDeclaredSubjects((categories ?? []).compactMap { element in
            DeclaredSubjectClaim(surface: .atomEntryCategory, scheme: element.attributes?.scheme,
                label: element.attributes?.term)
        })
    }

    /// The item's own `tags`, which name no taxonomy (`JSONFeedItem.tags`, whose own documentation notes
    /// that some formats call these categories). The feed's own tags are not consulted.
    private static func declaredSubjects(in tags: [String]?) -> StoryDeclaredSubjects? {
        StoryDeclaredSubjects((tags ?? []).compactMap { tag in
            DeclaredSubjectClaim(surface: .jsonFeedItemTag, label: tag)
        })
    }

    private static func nonempty(_ value: String?) -> String? { value.flatMap { $0.utf8.isEmpty ? nil : $0 } }
    private static func literalBody(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return normalized.isEmpty ? nil : normalized
    }
    private static func readableBody(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = ReadablePublicationText.convert(value).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
    /// First 16 hex digits of SHA-256 over whitespace-collapsed material fields.
    static func materialFingerprint(title: String?, summary: String?, body: String?, link: String?,
        media: [AcquisitionMediaCandidateClaim], sourceElement: String? = nil) -> String {
        func collapse(_ text: String?) -> String {
            (text ?? "").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        }
        let material = [collapse(title), collapse(summary), collapse(body), collapse(link)]
            + media.map(\.remoteURL.absoluteString)
            + (sourceElement.map { ["sourceElement", $0] } ?? [])
        let digest = SHA256.hash(data: Data(material.joined(separator: "\u{1F}").utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
    private static func webURL(_ text: String?) -> URL? {
        guard let text, let url = URL(string: text), let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https", let host = url.host, !host.isEmpty else { return nil }
        return url
    }
    private static func media(_ text: String?, base: URL? = nil, width: Int? = nil, height: Int? = nil,
        mimeType: String? = nil) -> AcquisitionMediaCandidateClaim? {
        guard let url = SyndicationMediaLocator.resolve(text, base: base) else { return nil }
        let dimensions: (Int?, Int?) = (width ?? 0) > 0 && (height ?? 0) > 0 ? (width, height) : (nil, nil)
        // Declared tiny visuals are logos/icons, not card art (v1 isLikelyFaviconOrLogo).
        if let w = dimensions.0, let h = dimensions.1, w <= 150 && h <= 150 { return nil }
        return .init(role: .cardVisual, mediaClass: .image, remoteURL: url, declaredMimeType: mimeType,
            declaredPixelWidth: dimensions.0, declaredPixelHeight: dimensions.1)
    }
    /// V1's enclosure for an audio or video episode: the one playable payload an item can carry. The store
    /// enforces the same rule (at most one per revision), and it is appended *after* the visuals so it never
    /// takes the card's own ordinal 0.
    private static func playback(_ text: String?, base: URL? = nil, mimeType: String?) -> AcquisitionMediaCandidateClaim? {
        guard let declared = mimeType, let klass = MediaCandidateClass.playback(forMIME: declared),
            let url = SyndicationMediaLocator.resolve(text, base: base, allowingPlayableMedia: true) else {
            return nil
        }
        return .init(role: klass.role, mediaClass: klass, remoteURL: url, declaredMimeType: declared,
            declaredPixelWidth: nil, declaredPixelHeight: nil)
    }

    private static func thumbnails(_ values: [MediaThumbnail]?, base: URL?) -> [AcquisitionMediaCandidateClaim] {
        (values ?? []).compactMap { value in
            media(value.attributes?.url, base: base, width: value.attributes?.width.flatMap(Int.init),
                height: value.attributes?.height.flatMap(Int.init))
        }
    }
    /// `media:content` entries that are images by medium or MIME type; audio/video are not card visuals.
    /// An entry that declares video (`declaresVideo`) is never admitted here, so one element cannot be both a
    /// card visual and a payload.
    private static func contents(_ values: [MediaContent]?, base: URL?) -> [AcquisitionMediaCandidateClaim] {
        (values ?? []).compactMap { value in
            guard let attributes = value.attributes, !declaresVideo(value),
                attributes.medium?.lowercased() == "image" || SyndicationMediaLocator.isImageMIMEType(attributes.type) else { return nil }
            return media(attributes.url, base: base, width: attributes.width, height: attributes.height,
                mimeType: SyndicationMediaLocator.isImageMIMEType(attributes.type) ? attributes.type : nil)
        }
    }

    /// What the live YouTube Atom feed still declares as its video's `type`: a container no player here takes,
    /// named by the publisher as a video nonetheless.
    private static let flashVideoMIMEType = "application/x-shockwave-flash"

    /// `media:content` declares a video when it says `medium="video"`, names a `video/*` MIME, or names the Flash
    /// type YouTube emits. The medium is the publisher's own word and wins over a contradictory MIME on the same
    /// element.
    private static func declaresVideo(_ value: MediaContent) -> Bool {
        guard let attributes = value.attributes else { return false }
        if attributes.medium?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "video" { return true }
        guard let type = declaredMediaType(attributes.type) else { return false }
        return type.hasPrefix("video/") || type == flashVideoMIMEType
    }

    /// The MIME type a `media:content` `type` attribute names, compared as the media type it declares:
    /// lowercased and without parameters (`video/mp4; codecs=avc1` still names MP4). nil when it declares none.
    private static func declaredMediaType(_ type: String?) -> String? {
        guard let type else { return nil }
        let essence = (type.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return essence.isEmpty ? nil : essence
    }

    /// The video payload a `media:content` list declares, at most one: the first admissible declaration in
    /// document order, so replaying one document always yields the same claim. The caller passes the item's own
    /// lists in document order and only asks when no enclosure already claimed playback (spec 2026-10-24 §2.2).
    /// Audio `media:content` is deliberately not read: an episode's audio comes from its enclosure, and that
    /// behaviour is unchanged.
    private static func contentPlayback(_ values: [MediaContent], base: URL?) -> AcquisitionMediaCandidateClaim? {
        for value in values {
            guard let attributes = value.attributes, declaresVideo(value),
                let url = SyndicationMediaLocator.resolve(attributes.url, base: base, allowingPlayableMedia: true) else {
                continue
            }
            return .init(role: .playback, mediaClass: .video, remoteURL: url, declaredMimeType: attributes.type,
                declaredPixelWidth: nil, declaredPixelHeight: nil)
        }
        return nil
    }
    private static func htmlImage(_ html: String?, base: URL?) -> AcquisitionMediaCandidateClaim? {
        SyndicationMediaLocator.firstContentImage(inHTML: html, base: base).flatMap { media($0.absoluteString) }
    }
    /// Same locator from several elements is one candidate; first occurrence keeps its declared facts.
    private static func unique(_ values: [AcquisitionMediaCandidateClaim]) -> [AcquisitionMediaCandidateClaim] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.remoteURL.absoluteString).inserted }
    }
}
