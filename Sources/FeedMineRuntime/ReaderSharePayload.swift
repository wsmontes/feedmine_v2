//
// File: ReaderSharePayload.swift
// Module: FeedMineRuntime
//
// Responsibility:
// What a share carries, as a value: the occurrence's title, its frozen link and the source it came from. The
// text is composed here (V1's template order) so the platform surface and any test read the same words.
//
// Does not own: presenting a share sheet or touching the pasteboard (platform adapters, app target).
import Foundation

public struct ReaderSharePayload: Hashable, Sendable {
    public let title: String?
    public let url: URL
    public let source: String?

    public init(title: String?, url: URL, source: String?) {
        self.title = title; self.url = url; self.source = source
    }

    /// V1 shared exactly the link (`ShareLink(item: URL(item.url))`): the title and the source are there for a
    /// share sheet's own subject line, never prefixed onto the item.
    public var text: String { url.absoluteString }

    /// The subject a share sheet may state beside the link. V1 composed the same two facts for its social
    /// card; it is a value here so a test can read it without a sheet.
    public var subject: String {
        [title, source].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
