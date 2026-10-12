import Foundation
import XCTest
import FeedMineDomain
@testable import FeedMinePersistence
import FeedMineComposition
import FeedMineRuntime

/// The reader's own sources: a key brought by a pasted link or an imported file is not in the shipped catalogue,
/// so it needs identities of its own — deterministic, and never the catalogue's.
///
/// This is the half of the defect an imported feed died of: the key was written and selected, but nothing could
/// turn it into a Source/Target/Binding, so the session dropped it and the reader's own feed produced no card.
final class ReaderSourceIdentityTests: XCTestCase {
    private func database() throws -> RuntimeDatabase {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
    }

    private func entry(key: String = "https://a.example/feed", requestURL: String = "https://a.example/feed",
        title: String = "A") -> ReaderImportEntry {
        ReaderImportEntry(id: key, title: title, requestURL: requestURL, categoryPath: [])
    }

    /// The same key is the same feed on every launch, and two keys are two feeds: the identities are derived
    /// from the key itself, never minted fresh.
    func testTheSameKeyAlwaysMintsTheSameIdentities() throws {
        let first = try XCTUnwrap(ReaderSourceIdentity.entry(entry()))
        let second = try XCTUnwrap(ReaderSourceIdentity.entry(entry()))
        XCTAssertEqual(first.source.id, second.source.id)
        XCTAssertEqual(first.targetID, second.targetID)
        XCTAssertEqual(first.bindingID, second.bindingID)
        let other = try XCTUnwrap(ReaderSourceIdentity.entry(entry(key: "https://b.example/feed",
            requestURL: "https://b.example/feed")))
        XCTAssertNotEqual(first.source.id, other.source.id)
        XCTAssertNotEqual(first.targetID, other.targetID)
        XCTAssertEqual(Set([first.source.id.rawValue.uuidString, first.targetID.rawValue.uuidString,
            first.bindingID.rawValue.uuidString]).count, 3,
            "source, target and binding are three identities, not one repeated")
    }

    /// A reader's key never collides with a catalogue key: the namespaces are different authorities even when
    /// both keys look like URLs (PD-2 keeps the catalogue's derivation for the catalogue's own records).
    func testTheReaderNamespaceIsNotTheCatalogNamespace() throws {
        let key = "https://feeds.bbci.co.uk/news/rss.xml"
        let mine = try XCTUnwrap(ReaderSourceIdentity.entry(entry(key: key, requestURL: key)))
        XCTAssertNotEqual(mine.source.id.rawValue,
            LegacyCatalogImport.stableUUID(namespace: "feedmine.v1-catalog.source", key: key))
        XCTAssertEqual(mine.principal, key, "the key is the principal the binding states")
    }

    /// The entry keeps V1's two addresses: the identity is what the reader's key is, and the endpoint is the
    /// address to fetch — signed parameters and all.
    func testTheEndpointKeepsTheRequestAddressAndThePrincipalIsTheKey() throws {
        let mapped = try XCTUnwrap(ReaderSourceIdentity.entry(entry(
            key: "https://a.example/feed",
            requestURL: "https://a.example/feed?token=abc&x-amz-signature=1", title: "  A Source  ")))
        XCTAssertEqual(mapped.endpoint.absoluteString, "https://a.example/feed?token=abc&x-amz-signature=1")
        XCTAssertEqual(mapped.principal, "https://a.example/feed")
        XCTAssertEqual(mapped.source.displayName, "A Source")
        XCTAssertTrue(mapped.source.isEnabled, "a feed the reader added is one they want to read")
    }

    /// An entry this build could never fetch is refused here rather than failing acquisition later: no
    /// scheme, no host, credentials in the address, or no identity at all.
    func testAnUnusableEntryIsRefused() {
        XCTAssertNil(ReaderSourceIdentity.entry(entry(key: "", requestURL: "https://a.example/feed")))
        XCTAssertNil(ReaderSourceIdentity.entry(entry(requestURL: "ftp://a.example/feed")))
        XCTAssertNil(ReaderSourceIdentity.entry(entry(requestURL: "https:///feed")))
        XCTAssertNil(ReaderSourceIdentity.entry(entry(requestURL: "https://user:secret@a.example/feed")))
        XCTAssertNotNil(ReaderSourceIdentity.entry(entry(requestURL: "http://a.example/feed")),
            "plain http is still a fetchable address")
    }

    /// What an import writes is what a session can now be built from. Before this mapping the key was written,
    /// selected and then dropped when the feeds were resolved: this walks the whole boundary — commit, read
    /// back, map — and asserts the reader's own feed comes out with a fetchable endpoint.
    func testAnImportedFeedMapsToAnAcquirableIdentity() async throws {
        let database = try database()
        let coordinator = ReaderImportExportCoordinator(database: database,
            exportDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        _ = try ReaderPreferencesStore(database: database).initialize(sourceKeys: ["https://existing.example/feed"])
        let preview = try await coordinator.previewImport(Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0"><head><title>Importadas</title></head><body>
        <outline type="rss" text="Mine" xmlUrl="https://www.mine.example/feed/?utm_source=newsletter"/>
        </body></opml>
        """.utf8))
        _ = try await coordinator.commitImport(preview)

        let imported = coordinator.importedSources()
        XCTAssertEqual(imported.map(\.id), ["https://mine.example/feed"])
        let record = try XCTUnwrap(try ReaderPreferencesStore(database: database).load())
        XCTAssertTrue(record.sourceKeys.contains("https://mine.example/feed"),
            "the commit selects what it imported")
        let mapped = try XCTUnwrap(ReaderSourceIdentity.entry(try XCTUnwrap(imported.first)))
        XCTAssertEqual(mapped.endpoint.absoluteString, "https://www.mine.example/feed/?utm_source=newsletter",
            "the fetch address is the file's own, not the identity")
        XCTAssertEqual(mapped.principal, "https://mine.example/feed")
        XCTAssertEqual(mapped.source.displayName, "Mine")
    }
}
