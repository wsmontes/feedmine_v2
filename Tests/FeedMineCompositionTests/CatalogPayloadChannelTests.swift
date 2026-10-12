import CryptoKit
import Foundation
import XCTest
@testable import FeedMineComposition

/// The payload half of the authority channel: what it obtains, what it refuses by name, and what it reports when
/// there is nothing to obtain. Exercised against a real HTTP server on loopback, so URL construction, status
/// handling and byte handling are all the shipping ones.
final class CatalogPayloadChannelTests: XCTestCase {
    private static let opml = """
        <?xml version="1.0" encoding="utf-8"?>
        <opml version="2.0">
          <head><title>um</title><language>pt</language></head>
          <body>
            <outline text="Notícias" title="Notícias">
              <outline text="Alpha News" title="Alpha News" xmlUrl="https://alpha.example/feed" />
            </outline>
          </body>
        </opml>
        """

    private var root: URL!
    private var served: URL!
    private var server: CatalogAuthorityServer?

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        served = root.appendingPathComponent("published", isDirectory: true)
        let opmlURL = served.appendingPathComponent("Feeds/01.opml")
        try FileManager.default.createDirectory(at: opmlURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Data(Self.opml.utf8).write(to: opmlURL)
        addTeardownBlock { [root] in try? FileManager.default.removeItem(at: root!) }
    }

    override func tearDown() {
        server?.stop()
        server = nil
    }

    // MARK: - What it obtains

    func testTheDeclaredPayloadIsDownloadedUnderItsOwnPathsAndVerified() async throws {
        let server = try authority()
        let manifest = try manifest(files: [declaration(path: "Feeds/01.opml")])
        let destination = root.appendingPathComponent("payload", isDirectory: true)

        let fetched = await channel(server).download(manifest, into: destination)

        guard case .payload(let payload) = fetched else { return XCTFail("a served, matching payload is a payload: \(fetched)") }
        XCTAssertEqual(payload.root, destination)
        XCTAssertEqual(payload.feedsRoot, destination.appendingPathComponent("Feeds"),
            "the compiler's tree is derived from the declared paths, not from a hard-coded name")
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("Feeds/01.opml")),
            Data(Self.opml.utf8), "the bytes are the authority's, unchanged")
    }

    func testATreeDeclaredAtThePayloadRootIsTheCompilerRoot() async throws {
        // The same payload, declared without the `Feeds/` directory: the root the compiler takes follows the
        // declaration rather than a convention about where OPMLs live.
        try FileManager.default.moveItem(at: served.appendingPathComponent("Feeds/01.opml"),
            to: served.appendingPathComponent("01.opml"))
        let server = try authority()
        let manifest = try manifest(files: [declaration(path: "01.opml")])
        let destination = root.appendingPathComponent("payload", isDirectory: true)

        let fetched = await channel(server).download(manifest, into: destination)

        guard case .payload(let payload) = fetched else { return XCTFail("a served, matching payload is a payload: \(fetched)") }
        XCTAssertEqual(payload.feedsRoot, destination)
    }

    // MARK: - What it refuses, by name

    func testAFileTheAuthorityDoesNotServeIsAMissingDeclaredFile() async throws {
        // The declaration is true of the file on disk; the authority simply does not serve it.
        let server = try authority(replies: ["Feeds/01.opml": .init(status: 404, bytes: nil)])
        let manifest = try manifest(files: [declaration(path: "Feeds/01.opml")])

        let fetched = await channel(server).download(manifest, into: root.appendingPathComponent("payload"))

        XCTAssertEqual(fetched, .rejected(.missingEntry("Feeds/01.opml")))
    }

    func testBytesThatDoNotMatchTheDeclaredDigestAreRefused() async throws {
        // The same length, one byte different: it is the declared digest that refuses this, not the size.
        var tampered = Data(Self.opml.utf8)
        tampered[tampered.startIndex] = tampered[tampered.startIndex] ^ 0xFF
        let server = try authority(replies: ["Feeds/01.opml": .init(status: 200, bytes: tampered)])
        let declared = try declaration(path: "Feeds/01.opml")
        let manifest = try manifest(files: [declared])

        let fetched = await channel(server).download(manifest, into: root.appendingPathComponent("payload"))

        XCTAssertEqual(fetched, .rejected(.checksumMismatch(path: "Feeds/01.opml",
            declared: declared.sha256, present: Self.sha256(of: tampered))))
    }

    func testAByteCountThatDisagreesWithTheDeclarationIsRefused() async throws {
        let server = try authority()
        let manifest = try manifest(files: [try declaration(path: "Feeds/01.opml", bytes: 4_096)])

        let fetched = await channel(server).download(manifest, into: root.appendingPathComponent("payload"))

        guard case .rejected(.sizeMismatch(let path, let declared, let present)) = fetched else {
            return XCTFail("an overstated size is a refusal, not a pass: \(fetched)")
        }
        XCTAssertEqual(path, "Feeds/01.opml")
        XCTAssertEqual(declared, 4_096)
        XCTAssertEqual(present, Data(Self.opml.utf8).count)
    }

    func testADeclarationThatEscapesTheRootIsRefusedBeforeAnythingIsWritten() async throws {
        let server = try authority()
        let escaping = CatalogManifestEntry(path: "../escaped.opml", bytes: 8,
            sha256: String(repeating: "a", count: 64))
        let manifest = try manifest(files: [escaping])
        let destination = root.appendingPathComponent("payload", isDirectory: true)

        let fetched = await channel(server).download(manifest, into: destination)

        XCTAssertEqual(fetched, .rejected(.unsafePath("../escaped.opml")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("escaped.opml").path),
            "nothing was written outside the download root")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path), "nothing was written at all")
    }

    func testAManifestThatDeclaresACompiledCatalogueIsRefused() async throws {
        // This build compiles the tree it verified; taking the authority's `.sqlite` would install a snapshot
        // nothing on the device built.
        let server = try authority()
        let compiled = CatalogManifestEntry(path: "catalog.sqlite", bytes: 4_096,
            sha256: String(repeating: "b", count: 64))
        let manifest = try manifest(files: [declaration(path: "Feeds/01.opml"), compiled])

        let fetched = await channel(server).download(manifest, into: root.appendingPathComponent("payload"))

        guard case .rejected(.invalidDeclaration(let detail)) = fetched else {
            return XCTFail("a compiled catalogue in the inventory is refused: \(fetched)")
        }
        XCTAssertTrue(detail.contains("catalog.sqlite"), detail)
    }

    func testAnInventoryWithNoOpmlIsRefused() async throws {
        let server = try authority()
        let manifest = try manifest(files: [])

        let fetched = await channel(server).download(manifest, into: root.appendingPathComponent("payload"))

        XCTAssertEqual(fetched, .rejected(.inventoryEmpty))
    }

    // MARK: - What it reports when there is nothing to obtain

    func testAnAuthorityThatIsNotListeningIsUnavailable() async throws {
        let server = try authority()
        let manifest = try manifest(files: [declaration(path: "Feeds/01.opml")])
        let authorityChannel = channel(server)
        server.stop()

        let fetched = await authorityChannel.download(manifest, into: root.appendingPathComponent("payload"))

        guard case .unavailable(let why) = fetched else {
            return XCTFail("no authority is not a verdict about the payload: \(fetched)")
        }
        XCTAssertFalse(why.isEmpty, "the reason is stated")
    }

    // MARK: - Helpers

    private func authority(replies: [String: CatalogAuthorityServer.Reply] = [:]) throws -> CatalogAuthorityServer {
        let server = try CatalogAuthorityServer(root: served, replies: replies)
        self.server = server
        return server
    }

    private func channel(_ server: CatalogAuthorityServer) -> CatalogUpdateChannel {
        CatalogUpdateChannel(manifestURL: server.manifestURL, session: Self.session())
    }

    private static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        return URLSession(configuration: configuration)
    }

    /// The declaration of a served file, measured from the file on disk unless the test overrides a field: the
    /// declaration is what the payload must match, so a test changes it rather than the payload when it wants them
    /// to disagree.
    private func declaration(path: String, bytes: Int? = nil, digest: String? = nil) throws
        -> CatalogManifestEntry {
        let url = served.appendingPathComponent(path)
        let size: Int
        if let bytes { size = bytes } else {
            size = try XCTUnwrap(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        }
        let sha256: String
        if let digest { sha256 = digest } else {
            sha256 = try CatalogManifest.sha256(ofFile: url)
        }
        return CatalogManifestEntry(path: path, bytes: size, sha256: sha256)
    }

    private func manifest(files: [CatalogManifestEntry]) throws -> CatalogManifest {
        CatalogManifest(revision: 6, generatedAt: "2026-10-11T00:00:00Z", sourceCount: 1,
            fileCount: files.count, files: files)
    }

    /// The digest of bytes in memory, for asserting what the channel reports it received.
    private static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
