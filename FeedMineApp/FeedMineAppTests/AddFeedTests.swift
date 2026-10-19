import XCTest
import Foundation
import FeedMineDomain
import FeedMinePersistence
import FeedMineUI
import FeedMineComposition
import FeedMineSyndication
@testable import FeedMine

/// Adding a feed from a link, end to end and inside the app: the address the reader pasted is discovered, stored
/// beside their own sources, resolved into a session source, and acquired — and it is still there after a
/// relaunch.
///
/// The site and its feed are served by the app's own debug fixture, so no test touches the network. What is
/// under test is the real path: `ReaderAddFeedStore` → `ReaderAddFeedAdapter` → `FeedLinkResolver` →
/// `reader_imported_sources` → `TrustedFeed.resolveAvailable` → the runtime.
#if DEBUG
@MainActor
final class AddFeedTests: XCTestCase {
    private func directory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func composition(directory: URL) -> AppComposition {
        AppComposition(directory: directory, feeds: TrustedFeed.development,
            transportConfiguration: Self.fixtureConfiguration())
    }

    /// No public RSS in this test: the fixture answers the site and its feed, and the developer feeds fail like
    /// an unreachable host, so the only supply is what the added feed carried.
    private static func fixtureConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        AddFeedFixtureSite.apply(to: configuration)
        configuration.timeoutIntervalForRequest = 5
        return configuration
    }

    /// The whole path: a pasted address becomes a feed the session acquires and publishes a card from.
    func testAddingAFeedByLinkDiscoversStoresAndAcquiresIt() async throws {
        let directory = directory()
        let root = composition(directory: directory)
        let store = try XCTUnwrap(root.makeAddFeedStore())
        store.setInput("Olha este site: \(AddFeedFixtureSite.siteURL)")

        await store.submit()

        let adoption = try XCTUnwrap(store.adoption, "adding a link must report what it did")
        XCTAssertEqual(adoption.added, 1)
        XCTAssertEqual(adoption.alreadySelected, 0)
        XCTAssertEqual(store.pendingProposal, nil, "one feed is added without a confirmation step")

        // The feed is written beside the reader's own sources and selected — one action, one transaction.
        let library = ReaderLibraryStore(database: try RuntimeDatabase(location: .init(directory: directory)))
        let imported = try library.importedSources()
        XCTAssertEqual(imported.map(\.id), ["https://site.feedmine.test/feed.xml"])
        XCTAssertEqual(imported.first?.title, AddFeedFixtureSite.siteTitle)
        let preferences = try XCTUnwrap(try ReaderPreferencesStore(
            database: try RuntimeDatabase(location: .init(directory: directory))).load())
        XCTAssertTrue(preferences.sourceKeys.contains("https://site.feedmine.test/feed.xml"),
            "an added feed is part of the reader's selection")

        // And the composition resolves it into a source a session can acquire. This is the step an imported or
        // pasted key used to die at: the key was selected and then dropped when the feed list was resolved.
        await root.adoptSelectionChange()
        let added = try XCTUnwrap(root.feeds.first { $0.principal == "https://site.feedmine.test/feed.xml" },
            "the reader's own source must become a session source")
        XCTAssertEqual(added.endpoint.absoluteString, AddFeedFixtureSite.feedURL)
        XCTAssertEqual(added.displayName, AddFeedFixtureSite.siteTitle)

        // The session really fetches it, and the feed the reader added is what the reader is shown: its own
        // headline is published as a card. The fetch belongs to the session's own opportunity, so it is awaited
        // rather than assumed to have happened by the time the selection change returns.
        let association = try XCTUnwrap(root.association)
        let asked = await Self.waitUntil(20) {
            AddFeedFixtureSite.recordedRequests().contains(AddFeedFixtureSite.feedURL)
        }
        XCTAssertTrue(asked,
            "the session must ask for the feed the reader added; it asked for \(AddFeedFixtureSite.recordedRequests())")
        let published = await Self.waitUntil(20) { association.store.state.presentation != nil }
        XCTAssertTrue(published, "the added feed must publish a first Edition")
        _ = try await association.driver.drive(resources: association.resources)
        let cards = try XCTUnwrap(association.store.state.presentation).window.items
        XCTAssertFalse(cards.isEmpty, "the feed the reader just added must produce cards")
        XCTAssertTrue(cards.contains { $0.sourceDisplayName == AddFeedFixtureSite.siteTitle },
            "the added feed's own attribution is on the card")
        XCTAssertTrue(cards.contains { AddFeedFixtureSite.headlines.contains($0.title ?? "") },
            "the added feed's own headline is published; published: \(cards.compactMap(\.title))")
        await association.close()
    }

    /// Waits for a fact the session produces on its own schedule, so a test asserts what happened instead of
    /// racing it.
    private static func waitUntil(_ seconds: TimeInterval, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    /// What the reader added is theirs after a relaunch: the key, its address and its identities are all durable.
    func testAFeedAddedByLinkSurvivesRelaunch() async throws {
        let directory = directory()
        var firstRunSourceID: SourceID?
        var firstRunTargetID: AcquisitionTargetID?
        do {
            let root = composition(directory: directory)
            let store = try XCTUnwrap(root.makeAddFeedStore())
            store.setInput(AddFeedFixtureSite.siteURL)
            await store.submit()
            XCTAssertEqual(try XCTUnwrap(store.adoption).added, 1)
            await root.adoptSelectionChange()
            let added = try XCTUnwrap(root.feeds.first { $0.principal == "https://site.feedmine.test/feed.xml" })
            firstRunSourceID = added.sourceID
            firstRunTargetID = added.targetID
            await root.association?.close()
        }
        let reopened = composition(directory: directory)
        let added = try XCTUnwrap(reopened.feeds.first { $0.principal == "https://site.feedmine.test/feed.xml" },
            "the feed the reader added is theirs after a relaunch")
        XCTAssertEqual(added.endpoint.absoluteString, AddFeedFixtureSite.feedURL)
        XCTAssertEqual(added.displayName, AddFeedFixtureSite.siteTitle)
        // The same identities on both sides of the relaunch: the target and the source are derived from the key,
        // never minted again.
        XCTAssertEqual(added.sourceID, firstRunSourceID)
        XCTAssertEqual(added.targetID, firstRunTargetID)
        // And the reopened app acquires it again: the feed address is the one the session asks for.
        AddFeedFixtureSite.resetRequests()
        await reopened.launch()
        let asked = await Self.waitUntil(20) {
            AddFeedFixtureSite.recordedRequests().contains(AddFeedFixtureSite.feedURL)
        }
        XCTAssertTrue(asked,
            "the relaunched session must ask for the feed the reader added; it asked for \(AddFeedFixtureSite.recordedRequests())")
        await reopened.association?.close()
    }

    /// Adding the same feed twice is not two feeds: the identity is the primary key and the selection is a set.
    func testAddingTheSameFeedTwiceAddsNothingTheSecondTime() async throws {
        let directory = directory()
        let root = composition(directory: directory)
        let store = try XCTUnwrap(root.makeAddFeedStore())
        store.setInput(AddFeedFixtureSite.siteURL)
        await store.submit()
        XCTAssertEqual(try XCTUnwrap(store.adoption).added, 1)

        // The same feed reached by a second address (its own feed URL, with a tracking parameter): one identity.
        store.setInput("https://site.feedmine.test/feed.xml?utm_source=newsletter")
        await store.submit()
        let second = try XCTUnwrap(store.adoption)
        XCTAssertEqual(second.added, 0, "the feed is already there")
        XCTAssertEqual(second.alreadySelected, 1, "and it is stated as already selected")
        let library = ReaderLibraryStore(database: try RuntimeDatabase(location: .init(directory: directory)))
        XCTAssertEqual(try library.importedSources().count, 1)
    }

    /// An unsuccessful paste must not wedge the sheet: the reader fixes the typo and adds, in the same run.
    func testAFailedPasteDoesNotWedgeTheSheet() async throws {
        let directory = directory()
        let root = composition(directory: directory)
        let store = try XCTUnwrap(root.makeAddFeedStore())
        store.setInput("https://no-feed.feedmine.test/")
        await store.submit()
        XCTAssertEqual(try XCTUnwrap(store.pendingProposal).rejections.map(\.reason), [.noFeedFound],
            "the failure is stated")

        // The reader types the address they meant; the sheet must resolve it rather than re-adopting the failure.
        store.setInput(AddFeedFixtureSite.siteURL)
        XCTAssertNil(store.pendingProposal, "typing something else clears what the last attempt resolved")
        await store.submit()
        let adoption = try XCTUnwrap(store.adoption, "the second attempt must add")
        XCTAssertEqual(adoption.added, 1)

        // And a second tap on the same failing address still resolves instead of doing nothing.
        let again = try XCTUnwrap(root.makeAddFeedStore())
        again.setInput("https://no-feed.feedmine.test/")
        await again.submit()
        await again.submit()
        XCTAssertNil(again.adoption)
        XCTAssertEqual(try XCTUnwrap(again.pendingProposal).rejections.map(\.reason), [.noFeedFound])
    }

    /// A feed address that carries credentials is refused at the preview: the library never holds an address the
    /// identities would refuse (the package test covers both boundary shapes against a stub transport).
    func testACredentialedAddressIsRefusedAndWritesNothing() async throws {
        let directory = directory()
        let adapter = ReaderAddFeedAdapter(database: try RuntimeDatabase(location: .init(directory: directory)),
            resolver: FeedLinkResolver(transport: URLSessionFeedDiscoveryTransport(session: URLSession(
                configuration: Self.fixtureConfiguration()))))
        let proposal = await adapter.resolve("https://letme:in@site.feedmine.test/feed.xml")
        XCTAssertTrue(proposal.feeds.isEmpty)
        XCTAssertEqual(proposal.rejections.map(\.reason), [.refused])
    }

    /// An address that answers with no feed is reported, and nothing is written for it.
    func testAnAddressWithNoFeedIsReportedAndWritesNothing() async throws {
        let directory = directory()
        let root = composition(directory: directory)
        let store = try XCTUnwrap(root.makeAddFeedStore())
        store.setInput("https://no-feed.feedmine.test/")

        await store.submit()

        XCTAssertNil(store.adoption)
        let proposal = try XCTUnwrap(store.pendingProposal)
        XCTAssertTrue(proposal.feeds.isEmpty)
        XCTAssertEqual(proposal.rejections.map(\.reason), [.noFeedFound])
        let library = ReaderLibraryStore(database: try RuntimeDatabase(location: .init(directory: directory)))
        XCTAssertTrue(try library.importedSources().isEmpty)
    }

    /// The reader may file the feeds they add into a collection in the same action (V1's picker).
    func testAddingAFeedFilesItIntoTheChosenCollection() async throws {
        let directory = directory()
        let root = composition(directory: directory)
        let library = ReaderLibraryStore(database: try RuntimeDatabase(location: .init(directory: directory)))
        let collection = try library.createCollection(named: "Minhas fontes")
        let store = try XCTUnwrap(root.makeAddFeedStore())
        await store.loadCollections()
        store.selectedCollectionID = collection.id
        store.setInput(AddFeedFixtureSite.siteURL)

        await store.submit()

        let adoption = try XCTUnwrap(store.adoption)
        XCTAssertEqual(adoption.filedInCollection, 1)
        XCTAssertEqual(adoption.collectionName, "Minhas fontes")
        XCTAssertEqual(try library.sourceKeys(inCollection: collection.id), ["https://site.feedmine.test/feed.xml"])
    }

    /// A filing that cannot land takes the whole add with it: the reader is not left with feeds they believed
    /// were in a collection, and the selection is not silently extended either.
    func testAFilingThatCannotLandTakesTheWholeAddWithIt() async throws {
        let directory = directory()
        let root = composition(directory: directory)
        let library = ReaderLibraryStore(database: try RuntimeDatabase(location: .init(directory: directory)))
        let store = try XCTUnwrap(root.makeAddFeedStore())
        store.selectedCollectionID = "00000000-0000-4000-8000-00000000dead"

        let adapter = ReaderAddFeedAdapter(database: try RuntimeDatabase(location: .init(directory: directory)),
            resolver: FeedLinkResolver(transport: URLSessionFeedDiscoveryTransport(session: URLSession(
                configuration: Self.fixtureConfiguration()))))
        let proposal = await adapter.resolve(AddFeedFixtureSite.siteURL)
        XCTAssertEqual(proposal.feeds.count, 1)
        do {
            _ = try await adapter.adopt(proposal, collectionID: "00000000-0000-4000-8000-00000000dead")
            XCTFail("filing into a collection that does not exist must fail")
        } catch {
            // The whole write is refused, which is what the assertions below state.
        }
        XCTAssertTrue(try library.importedSources().isEmpty, "nothing was written for a filing that failed")
        let preferences = try XCTUnwrap(try ReaderPreferencesStore(
            database: try RuntimeDatabase(location: .init(directory: directory))).load())
        XCTAssertFalse(preferences.sourceKeys.contains("https://site.feedmine.test/feed.xml"),
            "the selection is the transaction's own, so it was not extended either")
    }

    /// A key is owned by one authority, on every launch and in every session: a key the shipped catalogue
    /// carries keeps the catalogue's identities even when the reader imported it (an OPML file full of popular
    /// feeds must not mint a second identity per feed), and a key only the reader brought is theirs.
    func testAKeysAuthorityDoesNotDependOnTheSession() async throws {
        let directory = directory()
        // The catalogue this app test host carries, handed to `resolveAvailable` the way the app hands its own.
        let catalogueURL = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "sqlite"))
        let catalogueKey = try XCTUnwrap(try TrustedFeed.catalog(limit: 4,
            resourceURL: catalogueURL).first).principal
        let importedCatalogue = ReaderImportEntry(id: catalogueKey, title: "Do leitor",
            requestURL: "https://feeds.bbci.co.uk/news/rss.xml", categoryPath: [])
        let mineOnly = ReaderImportEntry(id: "https://site.feedmine.test/feed.xml", title: "Site",
            requestURL: "https://site.feedmine.test/feed.xml", categoryPath: [])

        // The session's own list plays no part: the same keys resolve the same way with it and without it.
        let withSession = try TrustedFeed.resolveAvailable(keys: [catalogueKey, mineOnly.id],
            fallback: TrustedFeed.development, readerSources: [importedCatalogue, mineOnly],
            catalogueURL: catalogueURL)
        let withoutSession = try TrustedFeed.resolveAvailable(keys: [catalogueKey, mineOnly.id],
            fallback: [], readerSources: [importedCatalogue, mineOnly], catalogueURL: catalogueURL)
        XCTAssertEqual(withSession.map(\.sourceID), withoutSession.map(\.sourceID))
        XCTAssertEqual(withSession.map(\.targetID), withoutSession.map(\.targetID))
        XCTAssertEqual(withSession.map(\.principalNamespace), withoutSession.map(\.principalNamespace))

        let catalogueEntry = try XCTUnwrap(TrustedFeed.catalog(limit: 4,
            resourceURL: catalogueURL)
            .first { $0.principal == catalogueKey })
        XCTAssertEqual(withSession.first?.sourceID, catalogueEntry.sourceID,
            "the catalogue owns a key it carries, imported or not")
        XCTAssertNil(withSession.first?.principalNamespace, "and the binding stays the catalogue's")
        XCTAssertEqual(withSession.last?.sourceID, ReaderSourceIdentity.entry(mineOnly)?.source.id,
            "a key only the reader brought is the reader's")
        XCTAssertEqual(withSession.last?.principalNamespace, ReaderSourceIdentity.principalNamespace)

        // And the app itself resolves them the same way after a relaunch.
        do {
            let first = composition(directory: directory)
            try await ReaderLibraryStore(database: try RuntimeDatabase(location: .init(directory: directory)))
                .commitImport([mineOnly], rejected: 0, at: Date())
            await first.adoptSelectionChange()
            XCTAssertEqual(first.feeds.first { $0.principal == mineOnly.id }?.sourceID,
                ReaderSourceIdentity.entry(mineOnly)?.source.id)
            await first.association?.close()
        }
        let reopened = composition(directory: directory)
        XCTAssertEqual(reopened.feeds.first { $0.principal == mineOnly.id }?.sourceID,
            ReaderSourceIdentity.entry(mineOnly)?.source.id, "the same identity after a relaunch")
    }
}
#endif
