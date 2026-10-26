import Darwin
import Foundation
import Synchronization
import XCTest
import FeedMineComposition
import FeedMinePersistence
@testable import FeedMine

/// The revision the authority publishes in this test: two OPMLs, four sources between them, and the count those
/// four outlines compile to. The inventory, the shapes the compiler accepts and the count it reports are the ones
/// the composition package's own update fixture proves (`Tests/FeedMineCompositionTests/CatalogUpdaterTests.swift`);
/// what is new here is the composition root that consumes them.
private enum PublishedRevision {
    static let revision = 6
    static let sourceCount = 4
    static let paths = ["Feeds/noticias.opml", "Feeds/programas.opml"]
    static let files: [String: String] = [
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
}

/// A real HTTP/1.1 server on loopback, serving one directory: `GET /<path>` answers the file's bytes, and 404 when
/// the directory holds no such file. It is the app test target's copy of the composition package's fixture
/// (`Tests/FeedMineCompositionTests/CatalogAuthorityServer.swift`) — repeated because an app target cannot import a
/// test-only module — with one addition this test needs: the log of the paths it answered, so "the app really made
/// the requests" is the socket's own record and not the URL the app was handed.
final class LocalCatalogueAuthority: @unchecked Sendable {
    private let root: URL
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "local-catalogue-authority")
    private var listening: Int32
    private var answered: [String] = []
    let port: UInt16

    init(root: URL) throws {
        let listener = try Self.loopbackListener()
        self.root = root
        self.listening = listener.descriptor
        self.port = listener.port
        queue.async { [self] in acceptLoop() }
    }

    /// `http://127.0.0.1:<port>/` — the payload's base, exactly as the published manifest's own directory is.
    var baseURL: URL { URL(string: "http://127.0.0.1:\(port)/")! }

    /// The manifest the app is pointed at: `manifest.json` at the served root, the same shape and the same relation
    /// to its payload as the published one.
    var manifestURL: URL { baseURL.appendingPathComponent("manifest.json") }

    /// Every path this server answered a request for, in order.
    var servedPaths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return answered
    }

    func stop() {
        lock.lock()
        let descriptor = listening
        listening = -1
        lock.unlock()
        if descriptor >= 0 { close(descriptor) }
    }

    deinit { stop() }

    // MARK: - Private

    private struct Listener {
        let descriptor: Int32
        let port: UInt16
    }

    private enum ListenError: Error {
        case failed(String)
    }

    /// A listening socket on loopback with an OS-assigned port.
    private static func loopbackListener() throws -> Listener {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw ListenError.failed("socket: errno \(errno)") }
        var reuse: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, Darwin.listen(descriptor, 16) == 0 else {
            close(descriptor)
            throw ListenError.failed("bind/listen: errno \(errno)")
        }
        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &actual) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        guard named == 0 else {
            close(descriptor)
            throw ListenError.failed("getsockname: errno \(errno)")
        }
        return Listener(descriptor: descriptor, port: UInt16(bigEndian: actual.sin_port))
    }

    private func acceptLoop() {
        while true {
            lock.lock()
            let descriptor = listening
            lock.unlock()
            guard descriptor >= 0 else { return }
            let connection = Darwin.accept(descriptor, nil, nil)
            guard connection >= 0 else { return }
            serve(connection)
            close(connection)
        }
    }

    /// One request per connection, answered and closed: enough for a client that asks for files, and nothing that
    /// can outlive the test that started it.
    private func serve(_ connection: Int32) {
        var request = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while !request.contains(Data([13, 10, 13, 10])) {
            let read = recv(connection, &buffer, buffer.count, 0)
            if read <= 0 { return }
            request.append(contentsOf: buffer[0..<read])
        }
        guard let text = String(data: request, encoding: .utf8),
            let line = text.split(separator: "\r\n").first else { return }
        let parts = line.split(separator: " ")
        guard parts.count >= 2 else { return }
        var path = String(parts[1])
        if let query = path.firstIndex(of: "?") { path = String(path[path.startIndex..<query]) }
        path = String(path.drop(while: { $0 == "/" }))
        path = path.removingPercentEncoding ?? path
        lock.lock()
        answered.append(path)
        lock.unlock()
        let file = path.split(separator: "/").reduce(root) { $0.appendingPathComponent(String($1)) }
        guard let bytes = try? Data(contentsOf: file) else {
            respond(connection, status: 404, body: Data())
            return
        }
        respond(connection, status: 200, body: bytes)
    }

    private func respond(_ connection: Int32, status: Int, body: Data) {
        let phrase = status == 200 ? "OK" : (status == 404 ? "Not Found" : "Error")
        var response = Data(
            "HTTP/1.1 \(status) \(phrase)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
        response.append(body)
        response.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < raw.count {
                let written = send(connection, base.advanced(by: sent), raw.count - sent, 0)
                if written <= 0 { return }
                sent += written
            }
        }
    }
}

/// PD-10's update path inside the app: the composition root's own `foreground()` — the call the app makes when it
/// comes back to the front — consults an authority that publishes revision 6 over a real socket, downloads and
/// verifies the OPML payload, compiles it on the device, and activates the new snapshot; the ledger says so with its
/// provenance, the active catalogue is the new one, and the reader's own store is left byte for byte as it was.
///
/// **How the app is pointed at a local authority.** `FEEDMINE_CATALOGUE_AUTHORITY` names the manifest URL
/// (`AppComposition.statedCatalogueAuthority()`), Debug only. A run that names an authority also states that the
/// daily window recorded about the *published* channel decides nothing about this one: `sync.json` is refreshed at
/// every launch from the installation of the bundled copy, so with the window respected the check would be skipped
/// and this branch could never run — which is exactly why it had never run before. Production reads neither the URL
/// nor the environment.
///
/// **Why this test closes the association before the pass.** `FeedAssociation.foreground()` works on the reader's
/// store on its own account and `driver.drive` publishes into it, so a byte-for-byte comparison across
/// `foreground()` could only fail. The test therefore runs the same `foreground()` the app runs, with the feed
/// transport refused and the association closed: the association's half is inert, and what the comparison
/// measures is the half under test — the update pass, which writes only under `catalogue/`.
@MainActor
final class CatalogueUpdateAcceptTests: XCTestCase {

    func testForegroundAcceptsTheAuthoritiesNewerRevisionWithoutTouchingTheReadersStore() async throws {
        // The device's directory, and the authority it is about to be pointed at.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let appDirectory = root.appendingPathComponent("app", isDirectory: true)
        let served = root.appendingPathComponent("published", isDirectory: true)
        try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        try writePublishedRevision(into: served)
        let authority = try LocalCatalogueAuthority(root: served)
        addTeardownBlock {
            authority.stop()
            try? FileManager.default.removeItem(at: root)
        }

        setenv("FEEDMINE_CATALOGUE_AUTHORITY", authority.manifestURL.absoluteString, 1)
        defer { unsetenv("FEEDMINE_CATALOGUE_AUTHORITY") }
        // The feeds are refused and everything else is real; the update path does not go through this transport.
        FixtureTransport.rejecting.withLock { $0 = true }
        defer { FixtureTransport.rejecting.withLock { $0 = false } }

        // What this build ships, read from the pair the launch verifies rather than assumed.
        let descriptorURL = try XCTUnwrap(Bundle.main.url(forResource: "catalog.manifest", withExtension: "json"))
        let descriptor = try CatalogManifest.decode(try Data(contentsOf: descriptorURL))
        XCTAssertEqual(descriptor.revision, 5, "the shipped descriptor is the revision the published authority is on")
        XCTAssertLessThan(descriptor.revision, PublishedRevision.revision, "the offer is newer, which is what accept means")

        // The app opens, as the app host opens it.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureTransport.self]
        configuration.timeoutIntervalForRequest = 10
        let composition = AppComposition(directory: appDirectory, feeds: TrustedFeed.development,
            transportConfiguration: configuration)
        await composition.launch()
        let association = try XCTUnwrap(composition.association, "the reader's session opened")
        XCTAssertNil(association.store.state.presentation,
            "nothing was published, so the association has no work of its own in the pass under test")
        await association.close()

        // The reader's own data, before the pass: the store's bytes, and the preferences that live in them.
        let storeURL = RuntimeDatabaseLocation(directory: appDirectory).databaseURL
        let storeBefore = try Data(contentsOf: storeURL)
        XCTAssertFalse(storeBefore.isEmpty, "the launch created and wrote the runtime store")
        let reader = try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: appDirectory))
        let preferencesBefore = try XCTUnwrap(ReaderPreferencesStore(database: reader).load())
        XCTAssertFalse(preferencesBefore.sourceKeys.isEmpty, "the comparison has reader's own data in it")

        // The pass under test: the composition root's foreground, exactly as the app calls it.
        await composition.foreground()

        // (a) The ledger: the launch installation, then the fetched revision, with the provenance that says which
        // of the two happened — "revision 6 verified from a fetched payload and activated" is a device update.
        let installation = CatalogInstallation(appDirectory: appDirectory)
        let records = installation.ledger()
        XCTAssertEqual(records.map(\.outcome), [.bootstrapped, .activated],
            "the launch installs the shipped copy and this pass activates the fetched one: \(records.map(\.reason))")
        XCTAssertEqual(records.map { $0.kind ?? "" }, ["bootstrap", "update"])
        XCTAssertEqual(records.first?.revision, descriptor.revision)
        XCTAssertEqual(records.last?.revision, PublishedRevision.revision)
        XCTAssertEqual(records.last?.reason, "revision 6 verified from a fetched payload and activated")
        XCTAssertFalse(records.contains { $0.outcome == .deferred },
            "the pass checked the stated authority rather than going through the window it never recorded")

        // The requests really were made: the authority's own log, not the URL the app was handed.
        XCTAssertEqual(Set(authority.servedPaths), Set(["manifest.json"] + PublishedRevision.paths))

        // (b) The active catalogue changed: the pointer names the fetched revision, it reads, and it holds the count
        // the authority declared. The file this build ships is where it was, still holding what it held — the
        // substitution moved the pointer, it did not rewrite the shipped copy.
        let active = try XCTUnwrap(installation.activeSnapshot())
        XCTAssertEqual(active.revision, PublishedRevision.revision)
        XCTAssertEqual(active.sourceCount, PublishedRevision.sourceCount)
        XCTAssertEqual(active.fingerprint, try CatalogManifest.sha256(ofFile: active.catalogueURL),
            "the fingerprint is the compiled artefact's own digest")
        let catalogue = try LegacyCatalogReader(catalogURL: active.catalogueURL)
        XCTAssertEqual(try catalogue.sourceCount(), PublishedRevision.sourceCount)
        XCTAssertEqual(try catalogue.metadata()?.sourceCount, PublishedRevision.sourceCount)
        XCTAssertEqual(try catalogue.matchingSources(query: "Alpha", limit: 10).map(\.title), ["Alpha News"],
            "the new snapshot answers the reader's own lookups")
        let shipped = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "sqlite"))
        XCTAssertNotEqual(active.catalogueURL.standardizedFileURL, shipped.standardizedFileURL)
        XCTAssertEqual(try LegacyCatalogReader(catalogURL: shipped).metadata()?.sourceCount, descriptor.sourceCount)

        // (c) The reader's own data is untouched: the store's bytes are the same bytes, and the reader's
        // preferences still read exactly as they did.
        XCTAssertEqual(try Data(contentsOf: storeURL), storeBefore,
            "the update path writes under catalogue/ only; runtime.sqlite is byte-identical")
        let preferencesAfter = try XCTUnwrap(ReaderPreferencesStore(database: reader).load())
        XCTAssertEqual(preferencesAfter, preferencesBefore)
    }

    // MARK: - Helpers

    /// Writes the authority's revision-6 inventory beside its manifest: sizes and digests measured from the bytes
    /// that are really served, because a declaration of something else is what the channel refuses.
    private func writePublishedRevision(into directory: URL) throws {
        for (path, content) in PublishedRevision.files {
            let url = directory.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        let files = try PublishedRevision.paths.map { path -> CatalogManifestEntry in
            let url = directory.appendingPathComponent(path)
            let bytes = try XCTUnwrap(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            return CatalogManifestEntry(path: path, bytes: bytes, sha256: try CatalogManifest.sha256(ofFile: url))
        }
        let manifest = CatalogManifest(revision: PublishedRevision.revision, generatedAt: "2026-10-11T00:00:00Z",
            sourceCount: PublishedRevision.sourceCount, fileCount: files.count, files: files)
        try manifest.encoded().write(to: directory.appendingPathComponent("manifest.json"))
    }
}
