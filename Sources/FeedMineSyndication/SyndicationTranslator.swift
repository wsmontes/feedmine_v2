// FeedKit values remain inside this module; output is protocol-free acquisition facts.
import Foundation
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
            body: String? = nil, authored: Date?, modified: Date? = nil, language: String? = nil, link: String?,
            media: [AcquisitionMediaCandidateClaim]) -> Result<AcquisitionObservation, ItemFailure> {
            guard let object else { return .failure(.missingStableIdentity) }
            // v1 lesson IN-4 / review M12: a future-dated item would pin itself to the top of a
            // recency order forever. Clamp claimed times to the observation; identity is unchanged.
            func clamped(_ date: Date?) -> Date? { date.map { min($0, observedAt) } }
            guard let value = AcquisitionObservation(objectIdentity: object, versionIdentity: version, precedence: .makeCurrent,
                availability: .available, headline: title, summary: summary, bodyText: body, authoredAt: clamped(authored),
                modifiedAt: clamped(modified), observedAt: observedAt, language: language, primaryLink: Self.webURL(link),
                searchProjection: nil, providerID: nil, memberships: configuration.memberships, mediaCandidates: media)
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
            return observation(object, title: item.title, summary: item.description, authored: item.pubDate,
                language: language, link: item.link, media: Self.unique(media))
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
                return observation(object, version: version, title: item.title, summary: item.summary?.text,
                    authored: item.published, modified: item.updated, link: link, media: Self.unique(media))
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
                return observation(object, version: version, title: item.title, summary: item.summary, body: item.contentText,
                    authored: item.datePublished, modified: item.dateModified, language: item.language,
                    link: link, media: Self.unique(media))
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
    private static func nonempty(_ value: String?) -> String? { value.flatMap { $0.utf8.isEmpty ? nil : $0 } }
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
    private static func thumbnails(_ values: [MediaThumbnail]?, base: URL?) -> [AcquisitionMediaCandidateClaim] {
        (values ?? []).compactMap { value in
            media(value.attributes?.url, base: base, width: value.attributes?.width.flatMap(Int.init),
                height: value.attributes?.height.flatMap(Int.init))
        }
    }
    /// `media:content` entries that are images by medium or MIME type; audio/video are not card visuals.
    private static func contents(_ values: [MediaContent]?, base: URL?) -> [AcquisitionMediaCandidateClaim] {
        (values ?? []).compactMap { value in
            guard let attributes = value.attributes,
                attributes.medium?.lowercased() == "image" || SyndicationMediaLocator.isImageMIMEType(attributes.type) else { return nil }
            return media(attributes.url, base: base, width: attributes.width, height: attributes.height,
                mimeType: SyndicationMediaLocator.isImageMIMEType(attributes.type) ? attributes.type : nil)
        }
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
