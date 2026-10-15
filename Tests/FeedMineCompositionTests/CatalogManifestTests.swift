import Foundation
import XCTest
import GRDB
@testable import FeedMinePersistence
@testable import FeedMineComposition

/// PD-10's manifest rules: the published shape decodes, the bundled descriptor stays true to the bytes it
/// describes, and a manifest that does not match what it claims is refused — before anything is built.
final class CatalogManifestTests: XCTestCase {
    private let byteCount = 2_048
    private let digest = String(repeating: "a", count: 64)

    private var root: URL!
    private var personal: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        personal = root.appendingPathComponent("app", isDirectory: true)
        try FileManager.default.createDirectory(at: personal, withIntermediateDirectories: true)
        addTeardownBlock { [root] in try? FileManager.default.removeItem(at: root!) }
    }

    // MARK: - Decoding

    func testThePublishedManifestShapeDecodesAndKeepsEveryDeclaredFile() throws {
        let json = """
        {"schemaVersion":1,"revision":5,"generatedAt":"2026-08-03T23:35:34Z","sourceCount":77443,
         "fileCount":2,"files":[
          {"path":"Feeds/01.opml","bytes":123,"sha256":"\(String(repeating: "b", count: 64))"},
          {"path":"catalog.sqlite","bytes":2048,"sha256":"\(digest)"}]}
        """
        let manifest = try CatalogManifest.decode(Data(json.utf8))
        XCTAssertEqual(manifest.revision, 5)
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.sourceCount, 77_443)
        XCTAssertEqual(manifest.fileCount, 2)
        XCTAssertEqual(manifest.opmlEntries.map(\.path), ["Feeds/01.opml"])
        XCTAssertEqual(manifest.catalogueEntry?.path, "catalog.sqlite")
        XCTAssertNil(CatalogManifest.validate(manifest))
    }

    /// Criteria 3/4: only the compiled artefact is excluded from the public comparison inventory.
    func testPublishedAndLocalManifestKeepTheSameOpmlEntries() {
        let opml = (0..<118).map { index in
            CatalogManifestEntry(path: String(format: "Feeds/%03d.opml", index), bytes: 10,
                sha256: String(repeating: "a", count: 64))
        }
        let sqlite = entry("catalog.sqlite")
        let published = CatalogManifest(revision: 5, sourceCount: 77_443, fileCount: 118, files: opml)
        let installed = CatalogManifest(revision: 5, sourceCount: 77_443, fileCount: 119,
            files: opml + [sqlite])
        XCTAssertEqual(published.opmlEntries, installed.opmlEntries)
        XCTAssertEqual(installed.catalogueEntry, sqlite)
        XCTAssertNil(published.catalogueEntry)
        XCTAssertEqual(published.fileCount, 118)
        XCTAssertEqual(installed.fileCount, 119)
    }

    func testTheBundledDescriptorDescribesTheCatalogueThisBuildShips() throws {
        // This module no longer carries a descriptor: the descriptor is the app's asset, and it must be read
        // beside the catalogue it describes (`FeedMineApp/FeedMineApp/Resources/catalog.manifest.json`).
        // `CatalogInstallation(appDirectory:)` now takes both from that one bundle. What is verified here is the
        // contract the shipped descriptor has to satisfy — the same decode the installer performs, and a
        // validation that only passes against the bytes it declares.
        let catalogue = try makeCatalogue(in: root.appendingPathComponent("built"))
        let declared = try XCTUnwrap(try XCTUnwrap(LegacyCatalogReader(catalogURL: catalogue).metadata()).sourceCount)
        let manifest = CatalogManifest(revision: 5, sourceCount: declared, fileCount: 1,
            files: [CatalogManifestEntry(path: "catalog.sqlite", bytes: try fileSize(catalogue),
                sha256: try CatalogManifest.sha256(ofFile: catalogue))])
        let decoded = try CatalogManifest.decode(try manifest.encoded())
        XCTAssertEqual(decoded.revision, 5, "the public revision this snapshot was built from")
        XCTAssertEqual(decoded.schemaVersion, CatalogManifest.supportedSchemaVersion)
        XCTAssertEqual(decoded.catalogueEntry?.path, "catalog.sqlite")
        XCTAssertNil(CatalogManifest.validate(decoded), "a descriptor valid in structure names the pair it describes")
        XCTAssertNil(CatalogManifest.validate(decoded, catalogue: catalogue),
            "and the pair the descriptor declares is the pair this build ships")
    }

    func testAMalformedManifestIsRefusedInsteadOfGuessedAt() throws {
        XCTAssertThrowsError(try CatalogManifest.decode(Data("{".utf8))) { error in
            XCTAssertEqual(error as? CatalogManifest.DecodeError, .malformed)
        }
        // `schemaVersion` is the one field a manifest may not omit: the format is stated, never assumed.
        let missing = Data("""
        {"revision":5,"sourceCount":77443,"fileCount":0,"files":[]}
        """.utf8)
        XCTAssertThrowsError(try CatalogManifest.decode(missing))
    }

    // MARK: - Structural validation

    func testUnsupportedManifestSchemaIsRefused() {
        let manifest = CatalogManifest(revision: 6, schemaVersion: 99, sourceCount: 1, fileCount: 1,
            files: [entry("catalog.sqlite")])
        XCTAssertEqual(CatalogManifest.validate(manifest), .unsupportedManifestSchema(99))
    }

    func testFileCountThatDoesNotMatchTheDeclarationIsRefused() {
        let manifest = CatalogManifest(revision: 6, sourceCount: 1, fileCount: 9,
            files: [entry("catalog.sqlite")])
        XCTAssertEqual(CatalogManifest.validate(manifest), .fileCountMismatch(declared: 9, actual: 1))
    }

    func testAnUnsafeOrDuplicatedPathIsRefused() {
        for path in ["/etc/passwd", "../escape.sqlite", "a/../../b", ""] {
            XCTAssertFalse(CatalogManifest.isSafeRelativePath(path), "\(path) must not be addressable")
            let manifest = CatalogManifest(revision: 6, sourceCount: 1, fileCount: 1, files: [entry(path)])
            XCTAssertEqual(CatalogManifest.validate(manifest), .unsafePath(path))
        }
        let duplicated = CatalogManifest(revision: 6, sourceCount: 1, fileCount: 2,
            files: [entry("catalog.sqlite"), entry("catalog.sqlite")])
        XCTAssertEqual(CatalogManifest.validate(duplicated), .unsafePath("catalog.sqlite"))
    }

    func testAZeroByteOrNonHexEntryIsRefused() {
        let zero = CatalogManifest(revision: 6, sourceCount: 1, fileCount: 1,
            files: [CatalogManifestEntry(path: "catalog.sqlite", bytes: 0, sha256: digest)])
        XCTAssertEqual(CatalogManifest.validate(zero), .invalidDeclaration("zero-byte entry: catalog.sqlite"))
        let short = CatalogManifest(revision: 6, sourceCount: 1, fileCount: 1,
            files: [CatalogManifestEntry(path: "catalog.sqlite", bytes: 10, sha256: "abc")])
        XCTAssertEqual(CatalogManifest.validate(short), .invalidDeclaration("malformed sha256 for catalog.sqlite"))
    }

    func testANonPositiveRevisionOrSourceCountIsRefused() {
        XCTAssertEqual(CatalogManifest.validate(CatalogManifest(revision: 0, sourceCount: 1, fileCount: 1,
            files: [entry("catalog.sqlite")])), .invalidDeclaration("revision must be positive"))
        XCTAssertEqual(CatalogManifest.validate(CatalogManifest(revision: 1, sourceCount: 0, fileCount: 1,
            files: [entry("catalog.sqlite")])), .invalidDeclaration("sourceCount must be positive"))
    }

    // MARK: - Payload validation (schema, inventory, size, SHA-256 — before any build)

    func testAnOpmlWhoseSizeOrChecksumDoesNotMatchIsRefused() throws {
        let payload = try makePayloadDirectory()
        let file = payload.appendingPathComponent("Feeds/01.opml")
        try Data(repeating: 0x41, count: 10).write(to: file)
        let size = CatalogManifest(revision: 6, sourceCount: 1, fileCount: 1,
            files: [CatalogManifestEntry(path: "Feeds/01.opml", bytes: 11,
                sha256: try CatalogManifest.sha256(ofFile: file))])
        XCTAssertEqual(CatalogManifest.validate(size, payload: payload),
            .sizeMismatch(path: "Feeds/01.opml", declared: 11, present: 10))

        let checksum = CatalogManifest(revision: 6, sourceCount: 1, fileCount: 1,
            files: [CatalogManifestEntry(path: "Feeds/01.opml", bytes: 10,
                sha256: String(repeating: "0", count: 64))])
        XCTAssertEqual(CatalogManifest.validate(checksum, payload: payload),
            .checksumMismatch(path: "Feeds/01.opml", declared: String(repeating: "0", count: 64),
                present: try CatalogManifest.sha256(ofFile: file)))
    }

    func testAnOpmlMissingFromThePayloadIsRefused() throws {
        let payload = try makePayloadDirectory()
        let manifest = CatalogManifest(revision: 6, sourceCount: 1, fileCount: 1, files: [entry("Feeds/none.opml")])
        XCTAssertEqual(CatalogManifest.validate(manifest, payload: payload), .missingEntry("Feeds/none.opml"))
    }

    func testAManifestWithNoOpmlInventoryIsRefused() throws {
        let payload = try makePayloadDirectory()
        let manifest = CatalogManifest(revision: 6, sourceCount: 1, fileCount: 1,
            files: [entry("catalog.sqlite")])
        XCTAssertEqual(CatalogManifest.validate(manifest, payload: payload), .inventoryEmpty)
    }

    // MARK: - Compiled catalogue validation

    func testACatalogueWhoseBytesDifferFromTheDeclarationIsRefused() throws {
        let catalogue = try makeCatalogue(in: root.appendingPathComponent("built"))
        let manifest = CatalogManifest(revision: 6, sourceCount: 2, fileCount: 1,
            files: [CatalogManifestEntry(path: "catalog.sqlite",
                bytes: try fileSize(catalogue), sha256: String(repeating: "0", count: 64))])
        XCTAssertEqual(CatalogManifest.validate(manifest, catalogue: catalogue),
            .checksumMismatch(path: "catalog.sqlite", declared: String(repeating: "0", count: 64),
                present: try CatalogManifest.sha256(ofFile: catalogue)))
    }

    func testACatalogueDeclaringAnUnsupportedSchemaIsRefused() throws {
        let catalogue = try makeCatalogue(in: root.appendingPathComponent("built"), schemaVersion: 99)
        let manifest = try manifest(describing: catalogue, sourceCount: 2)
        XCTAssertEqual(CatalogManifest.validate(manifest, catalogue: catalogue),
            .catalogueSchemaUnsupported(99))
    }

    func testACatalogueDeclaringNoSchemaVersionIsRefused() throws {
        let catalogue = try makeCatalogue(in: root.appendingPathComponent("built"), schemaVersion: nil)
        let manifest = try manifest(describing: catalogue, sourceCount: 2)
        XCTAssertEqual(CatalogManifest.validate(manifest, catalogue: catalogue), .catalogueSchemaUnknown)
    }

    func testACatalogueWhoseSourceCountDiffersFromTheManifestIsRefused() throws {
        let catalogue = try makeCatalogue(in: root.appendingPathComponent("built"))
        let manifest = try manifest(describing: catalogue, sourceCount: 77_443)
        XCTAssertEqual(CatalogManifest.validate(manifest, catalogue: catalogue),
            .sourceCountMismatch(declared: 77_443, built: 2))
    }

    func testACatalogueThatCannotBeOpenedAtAllIsRefused() throws {
        let directory = root.appendingPathComponent("built", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let catalogue = directory.appendingPathComponent("catalog.sqlite")
        try Data("not a catalogue".utf8).write(to: catalogue)
        let manifest = try manifest(describing: catalogue, sourceCount: 2)
        guard case .catalogueUnreadable = CatalogManifest.validate(manifest, catalogue: catalogue) else {
            return XCTFail("a file that is not a catalogue must be refused")
        }
    }

    // MARK: - Helpers

    private func entry(_ path: String) -> CatalogManifestEntry {
        CatalogManifestEntry(path: path, bytes: byteCount, sha256: digest)
    }

    private func manifest(describing catalogue: URL, sourceCount: Int) throws -> CatalogManifest {
        CatalogManifest(revision: 6, sourceCount: sourceCount, fileCount: 1,
            files: [CatalogManifestEntry(path: "catalog.sqlite", bytes: try fileSize(catalogue),
                sha256: try CatalogManifest.sha256(ofFile: catalogue))])
    }

    private func makePayloadDirectory() throws -> URL {
        let payload = root.appendingPathComponent("payload", isDirectory: true)
        try FileManager.default.createDirectory(at: payload.appendingPathComponent("Feeds"),
            withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 10).write(to: payload.appendingPathComponent("Feeds/01.opml"))
        return payload
    }

    private func fileSize(_ url: URL) throws -> Int {
        try XCTUnwrap(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
    }
}

/// A compiled catalogue for a test: the v1 tables `LegacyCatalogReader` reads, plus the `catalog_metadata` table
/// the external preparation publishes. Named here so both suites build the same fixture.
func makeCatalogue(in directory: URL, sources: Int = 2, schemaVersion: Int? = 2,
    revision: Int64 = 5) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("catalog.sqlite")
    let queue = try DatabaseQueue(path: url.path)
    try queue.write { db in
        try db.execute(sql: """
            CREATE TABLE catalog_node (id INTEGER PRIMARY KEY, key TEXT NOT NULL UNIQUE, parent_id INTEGER,
                name TEXT NOT NULL, kind INTEGER NOT NULL, source_count INTEGER NOT NULL DEFAULT 0,
                child_count INTEGER NOT NULL DEFAULT 0, language TEXT);
            CREATE TABLE catalog_source (id INTEGER PRIMARY KEY, key TEXT NOT NULL UNIQUE, title TEXT NOT NULL,
                declared_url TEXT NOT NULL, request_url TEXT NOT NULL, display_host TEXT, media_kind TEXT NOT NULL,
                language TEXT, site_url TEXT, description TEXT, tags TEXT, nature TEXT, activity TEXT,
                latest_item_at TEXT, quality_score INTEGER, default_enabled INTEGER NOT NULL DEFAULT 1,
                contact_email TEXT, contact_name TEXT, contact_source TEXT, contact_type TEXT);
            CREATE TABLE catalog_placement (id INTEGER PRIMARY KEY, source_id INTEGER NOT NULL,
                node_id INTEGER NOT NULL, node_name TEXT NOT NULL, opml_file TEXT NOT NULL,
                sort_order INTEGER NOT NULL, title_override TEXT, language_override TEXT, media_kind_override TEXT);
            CREATE TABLE catalog_metadata (key TEXT NOT NULL UNIQUE, value TEXT NOT NULL);
            INSERT INTO catalog_node (id, key, parent_id, name, kind) VALUES (1, 'topics/science', NULL, 'Science', 0);
            """)
        for index in 0..<sources {
            try db.execute(sql: """
                INSERT INTO catalog_source (id, key, title, declared_url, request_url, media_kind, language)
                VALUES (?, ?, ?, ?, ?, 'text', 'pt')
                """, arguments: [Int64(index + 1), "https://exemplo.pt/feed\(index)",
                    "Exemplo \(index)", "https://exemplo.pt/feed\(index)", "https://exemplo.pt/feed\(index)"])
            try db.execute(sql: """
                INSERT INTO catalog_placement (source_id, node_id, node_name, opml_file, sort_order)
                VALUES (?, 1, 'Science', 'x.opml', ?)
                """, arguments: [Int64(index + 1), Int64(index)])
        }
        var rows: [(String, String)] = [("catalog_version", String(revision)),
            ("source_count", String(sources)), ("node_count", "1"), ("placement_count", String(sources)),
            ("file_count", "1"), ("invalid_source_count", "0"), ("failed_file_count", "0")]
        if let schemaVersion { rows.append(("schema_version", String(schemaVersion))) }
        for (key, value) in rows {
            try db.execute(sql: "INSERT INTO catalog_metadata (key, value) VALUES (?, ?)", arguments: [key, value])
        }
    }
    return url
}
