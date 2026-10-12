//
// File: ReaderAddFeedAdapter.swift
// Module: FeedMineComposition
//
// Responsibility:
// The "add a feed from a link" tool: what the reader pasted is parsed into links (Syndication), each link is
// resolved into a feed address (Syndication, over a bounded transport), and the resolved feeds are written to
// the same place an imported file's feeds go — `reader_imported_sources` plus the reader's selection, in one
// transaction — with an optional personal collection filing in the same action.
//
// It is the **same authority** the OPML import writes and the same one a session resolves its targets from, so a
// feed the reader pasted is a feed the app acquires. A second store for pasted links would be a second truth
// about which sources the reader brought.
//
// Does not own: the network bounds (FeedDiscoveryTransport), the identity derivation (ReaderSourceIdentity) or
// the surfaces (UI).
import Foundation
import FeedMineDomain
import FeedMinePersistence
import FeedMineSyndication
import FeedMineUI

public struct ReaderAddFeedAdapter: ReaderAddFeedBackend {
    private let database: RuntimeDatabase
    private let resolver: FeedLinkResolver

    public init(database: RuntimeDatabase, resolver: FeedLinkResolver) {
        self.database = database
        self.resolver = resolver
    }

    /// The reader's input, resolved: every feed the links named, and every address that produced none.
    public func resolve(_ text: String) async -> ReaderFeedProposal {
        let links = FeedLinkInput.parse(text)
        guard !links.isEmpty else {
            return ReaderFeedProposal(feeds: [], rejections: [], opmlLinks: [])
        }
        let resolutions = await resolver.resolveAll(links)
        var feeds: [ReaderFeedCandidate] = []
        var rejections: [ReaderFeedRejection] = []
        var opmlLinks: [String] = []
        var seen = Set<String>()
        for resolution in resolutions {
            if resolution.link.kind == .opml {
                opmlLinks.append(resolution.link.url.absoluteString)
                continue
            }
            if let failure = resolution.failure {
                rejections.append(ReaderFeedRejection(input: resolution.link.raw, reason: Self.reason(failure)))
            }
            for feed in resolution.feeds {
                let identity = FeedAddress.identity(feed.feedURL)
                let request = FeedAddress.request(feed.feedURL)
                // The same boundary the identities use: an address this build could never resolve (a non-http
                // alternate link, credentials in the URL) is refused here, so the preview is honest and the
                // selection never names a source that can never produce a card.
                guard ReaderSourceIdentity.entry(ReaderImportEntry(id: identity, title: feed.title ?? "",
                    requestURL: request, categoryPath: [])) != nil else {
                    rejections.append(ReaderFeedRejection(input: feed.feedURL, reason: .refused))
                    continue
                }
                // Two links can name the same feed (a channel page and its own feed): the reader adds one.
                guard seen.insert(identity).inserted else { continue }
                feeds.append(ReaderFeedCandidate(id: identity,
                    title: feed.title ?? Self.title(forFeedURL: feed.feedURL),
                    feedURL: request, mediaKind: Self.kind(feed.mediaKind)))
            }
        }
        return ReaderFeedProposal(feeds: feeds, rejections: rejections, opmlLinks: opmlLinks)
    }

    public func adopt(_ proposal: ReaderFeedProposal, collectionID: String?) async throws -> ReaderFeedAdoption {
        try adopt(proposal, collectionID: collectionID, at: Date())
    }

    /// Writes the proposal's feeds and selects them, **and files them into the reader's collection when they
    /// asked for one, in the same transaction**, so the reader's own feed becomes part of the selection the
    /// session acquires — the step an imported key used to die at — and a filing that cannot land takes the
    /// whole add with it instead of leaving feeds the reader believed were in a collection.
    func adopt(_ proposal: ReaderFeedProposal, collectionID: String?, at date: Date) throws -> ReaderFeedAdoption {
        let store = ReaderLibraryStore(database: database)
        let entries = proposal.feeds.map { feed in
            ReaderImportEntry(id: feed.id, title: feed.title, requestURL: feed.feedURL, categoryPath: [])
        }
        let result = try store.commitImport(entries, rejected: proposal.rejections.count,
            collectionID: collectionID, at: date)
        // The name is for the surface's own sentence, never a claim about the write: the memberships above are
        // already the transaction's own.
        let name = collectionID.flatMap { id in try? store.collections().first { $0.id == id }?.name }
        return ReaderFeedAdoption(added: result.insertedSources, alreadySelected: result.alreadySelected,
            rejected: result.rejected, collectionName: name, filedInCollection: result.filedInCollection)
    }

    public func collections() async throws -> [ReaderFeedCollectionOption] {
        try ReaderLibraryStore(database: database).collections().map {
            ReaderFeedCollectionOption(id: $0.id, name: $0.name)
        }
    }

    public func createCollection(named name: String) async throws -> ReaderFeedCollectionOption {
        let collection = try ReaderLibraryStore(database: database).createCollection(named: name)
        return ReaderFeedCollectionOption(id: collection.id, name: collection.name)
    }

    /// V1's `ImportPipeline.titleFromURL`: the host, without the prefixes a feed address usually carries.
    static func title(forFeedURL feedURL: String) -> String {
        guard let host = URL(string: feedURL)?.host else { return feedURL }
        var name = host
        for prefix in ["www.", "feeds.", "rss.", "feed."] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
        }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    static func kind(_ mediaKind: FeedLinkMediaKind) -> ReaderFeedMediaKind {
        switch mediaKind {
        case .text: return .text
        case .video: return .video
        case .audio: return .audio
        }
    }

    static func reason(_ failure: FeedLinkFailure) -> ReaderFeedFailureReason {
        switch failure {
        case .noFeedFound: return .noFeedFound
        case .unreachable: return .unreachable
        case .invalidURL: return .invalidURL
        case .refused: return .refused
        }
    }
}
