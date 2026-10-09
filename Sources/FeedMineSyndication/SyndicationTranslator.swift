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
                ?? Self.nonempty(item.link).map { identity(kind + "-link", $0) }
            var media: [AcquisitionMediaCandidateClaim] = []
            if let image = Self.media(item.iTunes?.image?.attributes?.href) { media.append(image) }
            media += Self.thumbnails(item.media?.thumbnails)
            return observation(object, title: item.title, summary: item.description, authored: item.pubDate,
                language: language, link: item.link, media: media)
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
                    ?? link.map { identity("atom-link", $0) }
                let version = item.updated.map { identity("atom-updated", String($0.timeIntervalSinceReferenceDate.bitPattern, radix: 16), .version) }
                return observation(object, version: version, title: item.title, summary: item.summary?.text,
                    authored: item.published, modified: item.updated, link: link, media: Self.thumbnails(item.media?.thumbnails))
            }
        case .json(let document):
            return try window(document.items ?? [], kind: .json, start: startIndex, capacity: itemCapacity) { item in
                let object = Self.nonempty(item.id).map { identity("json-id", $0) }
                let version = item.dateModified.map { identity("json-modified", String($0.timeIntervalSinceReferenceDate.bitPattern, radix: 16), .version) }
                let media = [Self.media(item.image), Self.media(item.bannerImage)].compactMap { $0 }
                return observation(object, version: version, title: item.title, summary: item.summary, body: item.contentText,
                    authored: item.datePublished, modified: item.dateModified, language: item.language,
                    link: Self.nonempty(item.url) ?? item.externalURL, media: media)
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
    private static func media(_ text: String?, width: Int? = nil, height: Int? = nil) -> AcquisitionMediaCandidateClaim? {
        guard let url = webURL(text) else { return nil }
        return .init(role: .cardVisual, mediaClass: .image, remoteURL: url, declaredMimeType: nil,
            declaredPixelWidth: width, declaredPixelHeight: height)
    }
    private static func thumbnails(_ values: [MediaThumbnail]?) -> [AcquisitionMediaCandidateClaim] {
        (values ?? []).compactMap { value in
            let width = value.attributes?.width.flatMap(Int.init)
            let height = value.attributes?.height.flatMap(Int.init)
            if let width, let height, width > 0, height > 0 {
                return media(value.attributes?.url, width: width, height: height)
            }
            return media(value.attributes?.url)
        }
    }
}
