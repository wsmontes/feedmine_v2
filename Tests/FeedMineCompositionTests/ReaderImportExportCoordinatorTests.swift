import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence
import FeedMineComposition
import FeedMineRuntime

/// T10: the two tools. Import is preview-then-commit, the commit is atomic and idempotent, and an export writes a
/// file another reader (or this one, later) can read back.
final class ReaderImportExportCoordinatorTests: XCTestCase {
    private func database() throws -> RuntimeDatabase {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
    }

    private func exportDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func opml(_ body: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0"><head><title>Importadas</title></head><body>\(body)</body></opml>
        """.utf8)
    }

    private func coordinator() throws -> (ReaderImportExportCoordinator, RuntimeDatabase) {
        let database = try database()
        return (ReaderImportExportCoordinator(database: database, exportDirectory: exportDirectory()), database)
    }

    /// The preview writes nothing: a reader can look at a file and walk away untouched.
    func testThePreviewWritesNothing() async throws {
        let (coordinator, database) = try coordinator()
        _ = try ReaderPreferencesStore(database: database).initialize(sourceKeys: ["https://existing.example/feed"])
        let before = try XCTUnwrap(try ReaderPreferencesStore(database: database).load())
        let preview = try await coordinator.previewImport(opml("""
        <outline type="rss" text="A" xmlUrl="https://a.example/feed"/>
        <outline type="rss" text="B" xmlUrl="https://b.example/feed"/>
        """))
        XCTAssertEqual(preview.entries.count, 2)
        XCTAssertEqual(preview.name, "Importadas")
        XCTAssertTrue(try ReaderLibraryStore(database: database).importedSources().isEmpty)
        XCTAssertEqual(try ReaderPreferencesStore(database: database).load(), before,
            "a preview does not touch the selection")
        XCTAssertTrue(coordinator.importedSources().isEmpty)
    }

    /// The commit selects what it imported, and running it twice adds nothing: identity is the primary key.
    func testCommitSelectsAndIsIdempotent() async throws {
        let (coordinator, database) = try coordinator()
        let preferences = ReaderPreferencesStore(database: database)
        let initial = try preferences.initialize(sourceKeys: ["https://existing.example/feed"])
        let preview = try await coordinator.previewImport(opml("""
        <outline type="rss" text="A" xmlUrl="https://www.a.example/feed/?utm_source=x"/>
        <outline type="rss" text="B" xmlUrl="https://b.example/feed"/>
        <outline type="rss" text="Quebrado" xmlUrl="example.com/not-a-url"/>
        """))
        XCTAssertEqual(preview.rejections.count, 1)
        let result = try await coordinator.commitImport(preview)
        XCTAssertEqual(result.insertedSources, 2)
        XCTAssertEqual(result.rejected, 1)
        let record = try XCTUnwrap(try preferences.load())
        XCTAssertEqual(Set(record.sourceKeys), ["https://existing.example/feed", "https://a.example/feed",
            "https://b.example/feed"])
        XCTAssertGreaterThan(record.selectionVersion, initial.selectionVersion,
            "an import is a selection change, and a session fences on the version")
        // The address is kept so a session can fetch what the catalog does not know.
        XCTAssertEqual(coordinator.importedSources().map(\.id).sorted(),
            ["https://a.example/feed", "https://b.example/feed"])
        XCTAssertEqual(coordinator.importedSources().first { $0.id == "https://a.example/feed" }?.requestURL,
            "https://www.a.example/feed/?utm_source=x",
            "the request address is what the file said, verbatim")
        // The same import again: nothing inserted, nothing duplicated, and the selection does not move.
        let again = try await coordinator.commitImport(preview)
        XCTAssertEqual(again.insertedSources, 0)
        XCTAssertEqual(again.alreadySelected, 2)
        XCTAssertEqual(try preferences.load()?.sourceKeys.count, 3)
        XCTAssertEqual(try preferences.load()?.selectionVersion, record.selectionVersion,
            "nothing changed, so no new version")
    }

    /// A file that names the same feed twice imports it once.
    func testRepeatsInTheFileAreCountedNotImported() async throws {
        let (coordinator, database) = try coordinator()
        _ = try ReaderPreferencesStore(database: database).initialize(sourceKeys: ["https://existing.example/feed"])
        let preview = try await coordinator.previewImport(opml("""
        <outline type="rss" text="A" xmlUrl="https://a.example/feed"/>
        <outline type="rss" text="A de novo" xmlUrl="HTTPS://a.example/feed/"/>
        """))
        XCTAssertEqual(preview.entries.count, 1)
        XCTAssertEqual(preview.repeats, 1)
        let result = try await coordinator.commitImport(preview)
        XCTAssertEqual(result.insertedSources, 1)
        XCTAssertEqual(try ReaderPreferencesStore(database: database).load()?.sourceKeys.count, 2)
    }

    /// What an export writes, an import reads back: the same identities, the same request addresses.
    func testExportingOPMLRoundTripsThroughTheImporter() async throws {
        let (coordinator, database) = try coordinator()
        let preferences = ReaderPreferencesStore(database: database)
        _ = try preferences.initialize(sourceKeys: ["https://a.example/feed", "https://b.example/feed"])
        let url = try coordinator.export(ReaderExportRequest(scope: .selection, format: .opml))
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("<title>Minhas fontes</title>"))
        XCTAssertTrue(url.lastPathComponent.hasSuffix(".opml"))
        let readBack = try await coordinator.previewImport(Data(text.utf8))
        XCTAssertEqual(readBack.entries.map(\.id), ["https://a.example/feed", "https://b.example/feed"])
        XCTAssertEqual(readBack.entries.map(\.requestURL), ["https://a.example/feed", "https://b.example/feed"])
        // The file an export wrote is one this build imports without changing the reader's list: both entries
        // are already selected, and a second import of the same file writes nothing new.
        let result = try await coordinator.commitImport(readBack)
        XCTAssertEqual(result.alreadySelected, 2)
        XCTAssertEqual(try ReaderPreferencesStore(database: database).load()?.sourceKeys.count, 2)
        let again = try await coordinator.commitImport(readBack)
        XCTAssertEqual(again.insertedSources, 0)
        XCTAssertEqual(try ReaderPreferencesStore(database: database).load()?.sourceKeys.count, 2)
    }

    /// Each format writes a document of its own kind, and a collection's export covers its members.
    func testEveryFormatWritesItsOwnDocumentAndACollectionExportsItsMembers() async throws {
        let (coordinator, database) = try coordinator()
        _ = try ReaderPreferencesStore(database: database).initialize(sourceKeys: ["https://a.example/feed"])
        let library = ReaderLibraryStore(database: database)
        let collection = try library.createCollection(named: "Ciência")
        try library.addToCollection(id: collection.id, sourceKeys: ["https://x.example/feed",
            "https://y.example/feed"], at: Date())

        let csv = try coordinator.export(ReaderExportRequest(scope: .selection, format: .csv))
        let csvText = try String(contentsOf: csv, encoding: .utf8)
        XCTAssertEqual(csvText.split(separator: "\n").first, "title,url,identity,category")
        XCTAssertTrue(csvText.contains("https://a.example/feed"))

        let markdown = try coordinator.export(ReaderExportRequest(scope: .selection, format: .markdown))
        XCTAssertTrue(try String(contentsOf: markdown, encoding: .utf8).contains("- [a.example](https://a.example/feed)"))

        let json = try coordinator.export(ReaderExportRequest(scope: .selection, format: .json))
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: json)) as? [String: Any])
        XCTAssertEqual((payload["sources"] as? [[String: Any]])?.count, 1)

        let text = try coordinator.export(ReaderExportRequest(scope: .selection, format: .text))
        XCTAssertEqual(try String(contentsOf: text, encoding: .utf8), "https://a.example/feed\n")

        let link = try coordinator.export(ReaderExportRequest(scope: .selection, format: .shareLink))
        XCTAssertEqual(try String(contentsOf: link, encoding: .utf8), "https://a.example/feed\n")

        // A box exports the sources its cards came from; a box with no cards has nothing to export.
        XCTAssertThrowsError(try coordinator.export(ReaderExportRequest(
            scope: .bookmarkBox(ReaderBookmarkList.defaultID), format: .opml))) { error in
            XCTAssertEqual(error as? ReaderImportExportError, .nothingToWrite)
        }

        let science = try coordinator.export(ReaderExportRequest(scope: .collection(collection.id), format: .opml))
        let scienceText = try String(contentsOf: science, encoding: .utf8)
        XCTAssertTrue(scienceText.contains("https://x.example/feed"))
        XCTAssertTrue(scienceText.contains("https://y.example/feed"))
        XCTAssertFalse(scienceText.contains("https://a.example/feed"), "a collection exports its own members only")
    }

    /// Exporting a list with nothing in it is reported, not written as an empty file.
    func testAnEmptyScopeIsReportedRatherThanWritten() throws {
        let (coordinator, database) = try coordinator()
        _ = try ReaderPreferencesStore(database: database).initialize(sourceKeys: [])
        XCTAssertThrowsError(try coordinator.export(ReaderExportRequest(scope: .selection, format: .opml))) { error in
            XCTAssertEqual(error as? ReaderImportExportError, .nothingToWrite)
        }
        XCTAssertThrowsError(try coordinator.export(ReaderExportRequest(scope: .collection("missing"),
            format: .opml)))
    }
}
