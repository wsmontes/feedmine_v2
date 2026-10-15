import CryptoKit
import Foundation
import GRDB
import XCTest
import FeedMinePersistence
@testable import FeedMineComposition

/// PD-10's release criterion 4, end to end: a published revision is fetched from a real local authority,
/// downloaded, verified, compiled in staging and activated atomically — and a payload that does not match its
/// declaration activates nothing and leaves the snapshot that was active exactly as it was, proved against the
/// pointer on disk rather than asserted about the API.
final class CatalogUpdaterTests: XCTestCase {
    /// The inventory the authority publishes: two OPMLs, four sources between them.
    private static let published: [String: String] = [
        "Feeds/noticias.opml": """
            <?xml version="1.0" encoding="utf-8"?>
            <opml version="2.0">
              <head><title>noticias</title><language>pt</language></head>
              <body>
                <outline text="Mundo" title="Mundo">
                  <outline text="Alpha News" title="Alpha News" xmlUrl="https://alpha.example/feed" feedmineMediaKind="text" />
                  <outline text="Beta News" title="Beta News" xmlUrl="https://beta.example/feed" feedmineMediaKind="text" />
                </outline>
              </body>
            </opml>
            """,
        "Feeds/programas.opml": """
            <?xml version="1.0" encoding="utf-8"?>
            <opml version="2.0">
              <head><title>programas</title><language>pt</language></head>
              <body>
                <outline text="Programas" title="Programas">
                  <outline text="Gamma Cast" title="Gamma Cast" xmlUrl="https://gamma.example/feed" feedmineMediaKind="audio" />
                  <outline text="Delta Video" title="Delta Video" xmlUrl="https://delta.example/feed" feedmineMediaKind="video" />
                </outline>
              </body>
            </opml>
            """,
    ]
    private static let publishedPaths = ["Feeds/noticias.opml", "Feeds/programas.opml"]
    /// What those four outlines compile to, and therefore what the authority declares.
    private static let publishedSourceCount = 4
    private static let clock = Date(timeIntervalSince1970: 1_800_000_000)

    private var root: URL!
    private var appDirectory: URL!
    private var served: URL!
    private var server: CatalogAuthorityServer?
    private var installation: CatalogInstallation!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        appDirectory = root.appendingPathComponent("app", isDirectory: true)
        served = root.appendingPathComponent("published", isDirectory: true)
        try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        for (path, content) in Self.published {
            let url = served.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        // The device before the offer: revision 5, verified from the copy this build ships.
        let bundled = try makeCatalogue(in: root.appendingPathComponent("bundled"), sources: 2, revision: 5)
        let descriptor = root.appendingPathComponent("bundled-descriptor.json")
        _ = try writeDescriptor(for: bundled, revision: 5, into: descriptor)
        installation = CatalogInstallation(directory: installationDirectory, bundledCatalogue: bundled,
            bundledManifest: descriptor, now: { Self.clock })
        XCTAssertEqual(try XCTUnwrap(installation.bootstrap()).revision, 5)
        addTeardownBlock { [root] in try? FileManager.default.removeItem(at: root!) }
    }

    override func tearDown() {
        server?.stop()
        server = nil
    }

    // MARK: - An accepted offer, end to end

    func testAnAcceptedOfferIsDownloadedVerifiedCompiledAndActivated() async throws {
        let server = try authority()
        let channel = updateChannel(server)
        let published = try publishManifest()

        // The check the composition performs: one GET against the authority, then the offer rule.
        guard case .manifest(let data, etag: _) = await channel.fetch(), let fetched = try? CatalogManifest.decode(data)
        else { return XCTFail("the authority serves the manifest it published") }
        XCTAssertEqual(fetched, published, "the bytes served decode to the declaration that was published")
        guard case .accept(6) = CatalogOffer.decide(remote: fetched,
            active: installation.activeSnapshot()?.manifest) else {
            return XCTFail("revision 6 is newer than the active revision 5")
        }

        let runtime = try writePersonalData()
        let runtimeBefore = try Data(contentsOf: runtime)
        let work = root.appendingPathComponent("work", isDirectory: true)

        let outcome = await CatalogUpdater(installation: installation, channel: channel,
            workingDirectory: work).install(fetched)

        guard case .activated(let snapshot) = outcome else { return XCTFail("the offer activates: \(outcome)") }
        XCTAssertEqual(snapshot.revision, 6)
        XCTAssertEqual(snapshot.sourceCount, Self.publishedSourceCount,
            "the count the authority declared is the count the compiled catalogue holds")
        XCTAssertEqual(snapshot.fingerprint, try CatalogManifest.sha256(ofFile: snapshot.catalogueURL),
            "the fingerprint is the compiled artefact's own digest")
        XCTAssertEqual(installation.activeSnapshot()?.revision, 6)
        XCTAssertEqual(installation.activeSnapshot()?.fingerprint, snapshot.fingerprint)

        // (a) the catalogue that is now active is read by the reader the app always uses, unchanged.
        let reader = try LegacyCatalogReader(catalogURL: snapshot.catalogueURL)
        XCTAssertEqual(try reader.sourceCount(), Self.publishedSourceCount)
        XCTAssertEqual(try reader.metadata()?.sourceCount, Self.publishedSourceCount)
        XCTAssertEqual(try reader.matchingSources(query: "Alpha", limit: 10).map(\.title), ["Alpha News"],
            "the new snapshot answers the reader's own lookups")

        // (b) the ledger states where the revision came from: a fetched payload, not the copy this build ships.
        let records = installation.ledger()
        XCTAssertEqual(records.map(\.outcome), [.bootstrapped, .activated])
        XCTAssertEqual(records.map(\.kind), ["bootstrap", "update"])
        XCTAssertEqual(records.last?.revision, 6)
        XCTAssertEqual(records.last?.reason, "revision 6 verified from a fetched payload and activated")

        // The reader's own life is not on this path: their store is byte-identical.
        XCTAssertEqual(try Data(contentsOf: runtime), runtimeBefore, "personal data is byte-identical")
        XCTAssertEqual(try contents(of: work), [], "the working directory is removed when the attempt ends")
    }

    // MARK: - A payload that does not match its declaration

    func testAPayloadWhoseSha256IsWrongActivatesNothingAndKeepsThePreviousSnapshot() async throws {
        // The declaration is the authority's own and is true of the file it publishes; what the server hands over
        // is those bytes with one flipped — the same length, so it is the digest that has to refuse it.
        var tampered = try Data(contentsOf: served.appendingPathComponent("Feeds/noticias.opml"))
        tampered[tampered.startIndex] = tampered[tampered.startIndex] ^ 0xFF
        let server = try authority(replies: ["Feeds/noticias.opml": .init(status: 200, bytes: tampered)])
        let published = try publishManifest()
        let before = try XCTUnwrap(installation.activeSnapshot())
        let pointerBefore = try Data(contentsOf: installationDirectory.appendingPathComponent("active.json"))
        let snapshotsBefore = try contents(of: snapshotsDirectory)

        let outcome = await CatalogUpdater(installation: installation, channel: updateChannel(server),
            workingDirectory: root.appendingPathComponent("work", isDirectory: true)).install(published)

        guard case .rejected(let rejection) = outcome else {
            return XCTFail("a payload that is not what it declares is refused: \(outcome)")
        }
        guard case .checksumMismatch(let path, let declared, let present) = rejection else {
            return XCTFail("the reason is the digest: \(rejection)")
        }
        XCTAssertEqual(path, "Feeds/noticias.opml")
        XCTAssertEqual(declared, try CatalogManifest.sha256(ofFile: served.appendingPathComponent(path)))
        XCTAssertEqual(present, Self.sha256(of: tampered), "the digest the channel measured is the tampered bytes'")

        // Nothing moved. The pointer on disk is the one that was there, the snapshot it names still reads, and the
        // refused offer added no snapshot.
        XCTAssertEqual(try Data(contentsOf: installationDirectory.appendingPathComponent("active.json")), pointerBefore,
            "the active pointer is byte-identical")
        XCTAssertEqual(try contents(of: snapshotsDirectory), snapshotsBefore, "a refused offer adds no snapshot")
        XCTAssertEqual(installation.activeSnapshot()?.fingerprint, before.fingerprint)
        XCTAssertEqual(installation.activeSnapshot()?.revision, 5)
        XCTAssertEqual(try LegacyCatalogReader(catalogURL: before.catalogueURL).sourceCount(), 2,
            "the catalogue that was active is the one that still reads")

        let records = installation.ledger()
        XCTAssertEqual(records.map(\.outcome), [.bootstrapped, .rejected])
        XCTAssertEqual(records.last?.kind, "payload")
        XCTAssertEqual(records.last?.revision, 6)
        XCTAssertEqual(records.last?.reason, rejection.reason)
    }

    func testAPayloadMissingAFileItDeclaresIsRefusedAndKeepsThePreviousSnapshot() async throws {
        let server = try authority(replies: ["Feeds/programas.opml": .init(status: 404, bytes: nil)])
        let published = try publishManifest()
        let before = try XCTUnwrap(installation.activeSnapshot())

        let outcome = await CatalogUpdater(installation: installation, channel: updateChannel(server),
            workingDirectory: root.appendingPathComponent("work", isDirectory: true)).install(published)

        XCTAssertEqual(outcome, .rejected(.missingEntry("Feeds/programas.opml")))
        XCTAssertEqual(installation.activeSnapshot()?.fingerprint, before.fingerprint)
        XCTAssertEqual(installation.ledger().last?.kind, "payload")
    }

    // MARK: - Nothing to obtain

    func testAPayloadThatCannotBeFetchedIsStatedAndChangesNothing() async throws {
        let server = try authority()
        let published = try publishManifest()
        let channel = updateChannel(server)
        let before = try XCTUnwrap(installation.activeSnapshot())
        // The authority goes away between the manifest and the payload: a network failure, not a bad payload.
        server.stop()

        let outcome = await CatalogUpdater(installation: installation, channel: channel,
            workingDirectory: root.appendingPathComponent("work", isDirectory: true)).install(published)

        guard case .unavailable(let why) = outcome else {
            return XCTFail("no payload is not a verdict about the revision: \(outcome)")
        }
        XCTAssertFalse(why.isEmpty, "the reason is stated")
        XCTAssertEqual(installation.activeSnapshot()?.fingerprint, before.fingerprint,
            "an unavailable payload never changes the snapshot")
        let records = installation.ledger()
        XCTAssertEqual(records.map(\.outcome), [.bootstrapped, .deferred])
        XCTAssertEqual(records.last?.kind, "network")
        XCTAssertEqual(records.last?.revision, nil, "nothing was verified, so no revision is claimed")
        XCTAssertTrue(records.last?.reason.hasPrefix("no payload this time:") == true, records.last?.reason ?? "")
    }

    func testAManifestTheAuthorityDoesNotServeIsUnavailableAndVerifiesNothing() async throws {
        // The published directory holds the OPMLs and no `manifest.json`: the check degrades, exactly as it does
        // when the authority cannot be reached.
        let server = try authority()

        let fetched = await updateChannel(server).fetch()

        guard case .unavailable(let why) = fetched else {
            return XCTFail("no manifest this time: \(fetched)")
        }
        XCTAssertTrue(why.contains("404"), why)
        XCTAssertEqual(installation.activeSnapshot()?.revision, 5)
        XCTAssertEqual(installation.ledger().map(\.outcome), [.bootstrapped],
            "a check that verified nothing writes nothing but its own deferral")
    }

    // MARK: - Helpers

    private var installationDirectory: URL {
        appDirectory.appendingPathComponent("catalogue", isDirectory: true)
    }

    private var snapshotsDirectory: URL {
        installationDirectory.appendingPathComponent("snapshots", isDirectory: true)
    }

    private func authority(replies: [String: CatalogAuthorityServer.Reply] = [:]) throws -> CatalogAuthorityServer {
        let server = try CatalogAuthorityServer(root: served, replies: replies)
        self.server = server
        return server
    }

    private func updateChannel(_ server: CatalogAuthorityServer) -> CatalogUpdateChannel {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        return CatalogUpdateChannel(manifestURL: server.manifestURL, session: URLSession(configuration: configuration))
    }

    /// The manifest the authority publishes — revision 6, the OPMLs it serves and the source count those compile to
    /// — written beside the payload, which is where `CatalogUpdateChannel` reads it from.
    private func publishManifest() throws -> CatalogManifest {
        let files = try Self.publishedPaths.map { path in
            let url = served.appendingPathComponent(path)
            return CatalogManifestEntry(path: path,
                bytes: try XCTUnwrap(url.resourceValues(forKeys: [.fileSizeKey]).fileSize),
                sha256: try CatalogManifest.sha256(ofFile: url))
        }
        let manifest = CatalogManifest(revision: 6, generatedAt: "2026-10-11T00:00:00Z",
            sourceCount: Self.publishedSourceCount, fileCount: files.count, files: files)
        try manifest.encoded().write(to: served.appendingPathComponent("manifest.json"))
        return manifest
    }

    /// The descriptor a release ships beside its compiled snapshot: the catalogue's own entry, measured from the
    /// file, in the bundled shape (`FeedMineApp/Resources/catalog.manifest.json`).
    private func writeDescriptor(for catalogue: URL, revision: Int, into url: URL) throws -> URL {
        let sourceCount = try LegacyCatalogReader(catalogURL: catalogue).metadata()?.sourceCount ?? 0
        let manifest = CatalogManifest(revision: revision, sourceCount: sourceCount, fileCount: 1,
            files: [CatalogManifestEntry(path: "catalog.sqlite",
                bytes: try XCTUnwrap(catalogue.resourceValues(forKeys: [.fileSizeKey]).fileSize),
                sha256: try CatalogManifest.sha256(ofFile: catalogue))])
        try manifest.encoded().write(to: url)
        return url
    }

    /// The reader's own store, beside the managed catalogue and not behind it.
    private func writePersonalData() throws -> URL {
        let url = appDirectory.appendingPathComponent("runtime.sqlite")
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE reader_fixture (value TEXT NOT NULL)")
            try db.execute(sql: "INSERT INTO reader_fixture (value) VALUES ('saved')")
        }
        return url
    }

    private func contents(of directory: URL) throws -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    }

    private static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
