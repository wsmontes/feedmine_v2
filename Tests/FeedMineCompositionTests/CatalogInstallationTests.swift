import Foundation
import XCTest
import GRDB
import FeedMinePersistence
@testable import FeedMinePersistence
@testable import FeedMineComposition

/// PD-10 exercised through the app's own owner: install a verified snapshot, keep it when an offer is refused,
/// never touch personal data, and record every decision so an external report can read it.
final class CatalogInstallationTests: XCTestCase {
    private var root: URL!
    private var appDirectory: URL!
    private var catalogue: URL!
    private var manifestURL: URL!
    private let clock = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        appDirectory = root.appendingPathComponent("app", isDirectory: true)
        try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        catalogue = try makeCatalogue(in: root.appendingPathComponent("built"))
        manifestURL = try writeManifest(for: catalogue, revision: 5, into: root, name: "bundled.json")
        addTeardownBlock { [root] in try? FileManager.default.removeItem(at: root!) }
    }

    private func installation() -> CatalogInstallation {
        let clock = clock
        return CatalogInstallation(directory: appDirectory.appendingPathComponent("catalogue", isDirectory: true),
            bundledCatalogue: catalogue, bundledManifest: manifestURL, now: { clock })
    }

    // MARK: - Valid, idempotent, offline

    func testAVerifiedBundledSnapshotIsInstalledAndReadLocally() throws {
        let installation = installation()
        let snapshot = try XCTUnwrap(installation.bootstrap())
        XCTAssertEqual(snapshot.revision, 5)
        XCTAssertEqual(snapshot.sourceCount, 2)
        XCTAssertEqual(snapshot.declaredRevision, 5, "the snapshot's own declared revision is reported")
        XCTAssertEqual(snapshot.fingerprint, try CatalogManifest.sha256(ofFile: catalogue))
        XCTAssertEqual(try LegacyCatalogReader(catalogURL: snapshot.catalogueURL).sourceCount(), 2,
            "the installed snapshot is a catalogue this build reads")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installation.ledgerURL.path))
        XCTAssertEqual(installation.ledger().map(\.outcome), [.bootstrapped])
    }

    func testReinstallingTheSameRevisionDoesNotSubstituteTheSnapshot() throws {
        let installation = installation()
        let first = try XCTUnwrap(installation.bootstrap())
        let snapshotCount = try contents(of: installation.directory.appendingPathComponent("snapshots")).count
        let second = try XCTUnwrap(installation.bootstrap())
        XCTAssertEqual(first.fingerprint, second.fingerprint)
        XCTAssertEqual(try contents(of: installation.directory.appendingPathComponent("snapshots")).count,
            snapshotCount, "an equal revision adds no snapshot")
        XCTAssertEqual(installation.ledger().map(\.outcome), [.bootstrapped],
            "an equal revision is a no-op and is not recorded as a new verification")
    }

    func testTheLaunchPathPresentsLocalContentWithoutNetwork() throws {
        // Nothing here performs or can perform a request: the owner holds no session, no URL and no network
        // type — the offline floor is structural, not a policy that could be turned off.
        let installation = installation()
        let snapshot = try XCTUnwrap(installation.bootstrap())
        XCTAssertEqual(try LegacyCatalogReader(catalogURL: snapshot.catalogueURL).sourceCount(), 2)
        XCTAssertNil(installation.bootstrap()?.catalogueURL.scheme.flatMap { $0.hasPrefix("http") ? $0 : nil })
    }

    // MARK: - A newer valid revision installs; an invalid one is refused and preserves the snapshot

    func testANewerValidRevisionInstallsAndBecomesActive() throws {
        let installation = installation()
        _ = try XCTUnwrap(installation.bootstrap())
        let newer = try makeCatalogue(in: root.appendingPathComponent("newer"), sources: 3, revision: 6)
        let newerManifest = try manifestData(for: newer, revision: 6)
        let outcome = installation.install(manifestData: newerManifest, catalogue: newer)
        guard case .installed(let snapshot) = outcome else { return XCTFail("a newer valid revision installs") }
        XCTAssertEqual(snapshot.revision, 6)
        XCTAssertEqual(installation.activeSnapshot()?.revision, 6)
        XCTAssertEqual(installation.ledger().map(\.outcome), [.bootstrapped, .activated])
    }

    func testAnInvalidManifestKeepsTheActiveSnapshotAndRecordsWhy() throws {
        let installation = installation()
        let active = try XCTUnwrap(installation.bootstrap())
        let newer = try makeCatalogue(in: root.appendingPathComponent("newer"), sources: 3, revision: 6)
        let tampered = try manifestData(for: newer, revision: 6,
            overrideChecksum: String(repeating: "0", count: 64))
        let outcome = installation.install(manifestData: tampered, catalogue: newer)
        guard case .rejected(let rejection) = outcome else { return XCTFail("an invalid revision is refused") }
        guard case .checksumMismatch = rejection else { return XCTFail("the reason is the checksum") }
        let stillActive = try XCTUnwrap(installation.activeSnapshot())
        XCTAssertEqual(stillActive.fingerprint, active.fingerprint, "the previous snapshot is untouched")
        XCTAssertEqual(stillActive.revision, 5)
        let records = installation.ledger()
        XCTAssertEqual(records.last?.outcome, .rejected)
        XCTAssertEqual(records.last?.revision, 6)
        XCTAssertEqual(records.last?.kind, "payload", "a declaration that does not match the bytes is a payload refusal")
        XCTAssertEqual(records.last?.reason, rejection.reason)
    }

    func testAMalformedManifestIsRefusedAndRecorded() throws {
        let installation = installation()
        _ = try XCTUnwrap(installation.bootstrap())
        let outcome = installation.install(manifestData: Data("{".utf8), catalogue: catalogue)
        XCTAssertEqual(outcome, .rejected(.malformedManifest))
        XCTAssertEqual(installation.ledger().last?.reason, CatalogRejection.malformedManifest.reason)
        XCTAssertEqual(installation.activeSnapshot()?.revision, 5)
    }

    func testARevisionCollisionIsRefusedRatherThanSilentlyAccepted() throws {
        let installation = installation()
        _ = try XCTUnwrap(installation.bootstrap())
        // Same revision, different bytes: the declaration and the snapshot disagree, which must not be a no-op.
        let divergent = try makeCatalogue(in: root.appendingPathComponent("divergent"), sources: 3, revision: 5)
        let data = try manifestData(for: divergent, revision: 5)
        let outcome = installation.install(manifestData: data, catalogue: divergent)
        XCTAssertEqual(outcome, .rejected(.revisionCollision(5, active: 5)))
        XCTAssertEqual(installation.activeSnapshot()?.revision, 5)
    }

    func testAStaleRevisionIsRefusedAndNeverReplacesANewerOne() throws {
        let installation = installation()
        _ = try XCTUnwrap(installation.bootstrap())
        let newer = try makeCatalogue(in: root.appendingPathComponent("newer"), sources: 3, revision: 6)
        _ = installation.install(manifestData: try manifestData(for: newer, revision: 6), catalogue: newer)
        let stale = try makeCatalogue(in: root.appendingPathComponent("stale"), sources: 4, revision: 4)
        let outcome = installation.install(manifestData: try manifestData(for: stale, revision: 4), catalogue: stale)
        XCTAssertEqual(outcome, .rejected(.revisionNotNewer(4, active: 6)))
        XCTAssertEqual(installation.activeSnapshot()?.revision, 6, "a stale offer never moves the snapshot back")
    }

    // MARK: - A fetched offer: payload verified before the build, previous snapshot preserved on failure

    func testNoOpmlInventoryMeansTheOfferIsRefusedWithoutBuilding() {
        // A manifest that names no OPML has nothing to verify, so it is refused before any build runs. The
        // pre-build stages (structure, then payload) are where a bad offer stops.
        let installation = installation()
        _ = try! XCTUnwrap(installation.bootstrap())
        let payload = try! writePayload(in: root.appendingPathComponent("payload"), contents: "one")
        let manifest = CatalogManifest(revision: 6, sourceCount: 2, fileCount: 1,
            files: [CatalogManifestEntry(path: "catalog.sqlite", bytes: 10,
                sha256: String(repeating: "a", count: 64))])
        var built = false
        let outcome = installation.installOffer(manifestData: try! manifest.encoded(), payload: payload) { _ in
            built = true
            return self.catalogue
        }
        XCTAssertEqual(outcome, .rejected(.inventoryEmpty))
        XCTAssertFalse(built, "the build callback is never reached for an unverified payload")
        XCTAssertEqual(installation.activeSnapshot()?.revision, 5)
    }

    func testAFailingBuildKeepsThePreviousSnapshot() throws {
        let installation = installation()
        _ = try XCTUnwrap(installation.bootstrap())
        let built = try makeCatalogue(in: root.appendingPathComponent("built-newer"), sources: 3, revision: 6)
        let payload = try writePayload(in: root.appendingPathComponent("payload"), contents: "one")
        let manifest = try payloadManifest(payload: payload, revision: 6, catalogue: built)
        let outcome = installation.installOffer(manifestData: try manifest.encoded(), payload: payload) { _ in
            throw CatalogManifest.DecodeError.malformed
        }
        guard case .rejected(let rejection) = outcome else { return XCTFail("a failed build is a refusal") }
        XCTAssertEqual(rejection.kind, "compiled-catalogue")
        XCTAssertEqual(installation.activeSnapshot()?.revision, 5, "the previous snapshot is kept")
        XCTAssertEqual(installation.ledger().last?.outcome, .rejected)
    }

    func testACompleteOfferInstallsAndCanBeRolledBackToThePreviousSnapshot() throws {
        let installation = installation()
        let original = try XCTUnwrap(installation.bootstrap())
        let built = try makeCatalogue(in: root.appendingPathComponent("built-newer"), sources: 3, revision: 6)
        let catalogueData = try Data(contentsOf: built)
        let payload = try writePayload(in: root.appendingPathComponent("payload"), contents: "one")
        let manifest = try payloadManifest(payload: payload, revision: 6, catalogue: built)
        var materialized: URL?
        let outcome = installation.installOffer(manifestData: try manifest.encoded(), payload: payload) { _ in
            // The build step produces an artefact whose bytes match what the manifest will declare.
            let file = self.root.appendingPathComponent("built-output.sqlite")
            try catalogueData.write(to: file)
            materialized = file
            return file
        }
        guard case .installed(let installed) = outcome else { return XCTFail("a complete offer installs") }
        XCTAssertEqual(installed.revision, 6)
        let rolledBack = try XCTUnwrap(installation.rollback())
        XCTAssertEqual(rolledBack.fingerprint, original.fingerprint)
        XCTAssertEqual(installation.activeSnapshot()?.revision, 5)
        XCTAssertEqual(installation.ledger().last?.kind, "rollback")
        _ = materialized
    }

    // MARK: - PD10-P0B: recovery and pointer-failure guarantees

    /// B5: active.json is not itself proof of a valid snapshot; both missing and malformed
    /// pointers recover the verified previous revision rather than reinstalling or trusting the bad active.
    func testB5MissingOrMalformedActiveRecoversVerifiedPrevious() throws {
        for corruption in ["missing", "malformed"] {
            let app = root.appendingPathComponent("case-\(corruption)")
            let owner = try recoveryFixture(at: app)
            let activeURL = owner.directory.appendingPathComponent("active.json")
            if corruption == "missing" {
                try FileManager.default.removeItem(at: activeURL)
            } else {
                try Data("not json".utf8).write(to: activeURL)
            }
            let result = try XCTUnwrap(owner.bootstrap())
            XCTAssertEqual(result.revision, 5)
            XCTAssertEqual(owner.activeSnapshot()?.fingerprint, result.fingerprint)
            XCTAssertTrue(owner.ledger().contains { $0.kind == "recovery" && $0.outcome == .activated })
        }
    }

    /// B5: a decodable pointer plus an existing filename is insufficient. Missing bytes, modified
    /// SQLite contents and a corrupt descriptor each force the previous checksum-verified snapshot.
    func testB5MissingCorruptedSqliteOrManifestRecoverPrevious() throws {
        for corruption in ["missing-sqlite", "corrupt-sqlite", "invalid-manifest", "divergent-manifest"] {
            let owner = try recoveryFixture(at: root.appendingPathComponent(corruption))
            let active = try XCTUnwrap(owner.activeSnapshot())
            let pointerURL = owner.directory.appendingPathComponent("active.json")
            let pointer = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: pointerURL))
                as? [String: String])
            let descriptor = try XCTUnwrap(pointer["manifestPath"])
            switch corruption {
            case "missing-sqlite":
                try FileManager.default.removeItem(at: active.catalogueURL)
            case "corrupt-sqlite":
                // Preserve file size so a size-only check would incorrectly accept it.
                let handle = try FileHandle(forWritingTo: active.catalogueURL)
                try handle.write(contentsOf: Data(repeating: 0xFF, count: 12))
                try handle.close()
            case "invalid-manifest":
                try Data("{bad manifest".utf8).write(to: URL(fileURLWithPath: descriptor))
            default:
                let altered = CatalogManifest(revision: 6, sourceCount: 3, fileCount: 1,
                    files: [CatalogManifestEntry(path: "catalog.sqlite",
                        bytes: try XCTUnwrap(active.catalogueURL.resourceValues(forKeys: [.fileSizeKey]).fileSize),
                        sha256: String(repeating: "0", count: 64))])
                try altered.encoded().write(to: URL(fileURLWithPath: descriptor))
            }
            let restored = try XCTUnwrap(owner.bootstrap())
            XCTAssertEqual(restored.revision, 5, "failed case: \(corruption)")
            XCTAssertEqual(owner.activeSnapshot()?.revision, 5)
            XCTAssertTrue(owner.ledger().contains { $0.kind == "recovery" && $0.outcome == .activated })
        }
    }

    /// B5: an unusable previous pointer cannot be recovered; the bundled bytes are the last valid floor.
    func testB5InvalidPreviousFallsBackToVerifiedBundle() throws {
        let owner = try recoveryFixture(at: root.appendingPathComponent("invalid-previous"))
        let activeURL = owner.directory.appendingPathComponent("active.json")
        let previousURL = owner.directory.appendingPathComponent("previous.json")
        try Data("{broken active".utf8).write(to: activeURL)
        try Data("{broken previous".utf8).write(to: previousURL)
        let restored = try XCTUnwrap(owner.bootstrap())
        XCTAssertEqual(restored.revision, 5)
        XCTAssertEqual(owner.activeSnapshot()?.fingerprint, restored.fingerprint)
        XCTAssertTrue(owner.ledger().contains { $0.kind == "recovery"
            && $0.reason.contains("previous catalogue") })
    }

    /// B5: corrupted historical SQLite cannot be revived even when the manifest and pointer decode.
    func testB5PreviousSqliteCorruptionFallsBackToBundle() throws {
        let owner = try recoveryFixture(at: root.appendingPathComponent("invalid-previous-bytes"))
        let pointerURL = owner.directory.appendingPathComponent("previous.json")
        let pointer = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: pointerURL))
            as? [String: String])
        let previousPath = try XCTUnwrap(pointer["cataloguePath"])
        // The previous is the in-place bundled copy: restore its bytes after the test if it lives in
        // the shared fixture. Here the recovery fixture owns an isolated copy.
        try Data("corrupt".utf8).write(to: URL(fileURLWithPath: previousPath))
        try Data("{broken active".utf8).write(to: owner.directory.appendingPathComponent("active.json"))
        let degraded = try XCTUnwrap(owner.bootstrap())
        XCTAssertEqual(degraded.revision, 0, "no unverifiable revision may be claimed as installed")
        XCTAssertNil(owner.activeSnapshot(), "there is no verified active pointer")
        XCTAssertEqual(owner.ledger().last?.kind, "degraded")
        XCTAssertFalse(owner.ledger().contains { $0.kind == "recovery" && $0.outcome == .activated })
    }

    /// B5/B7 diagnostic: reports the incremental cost of strict verification on both cold and warm
    /// bootstrap. The Mac run is the measurement; this test deliberately invents no fixed time ceiling.
    func testB5MeasuresColdAndWarmLocalBootstrapCost() throws {
        let owner = installation()
        let coldStarted = ProcessInfo.processInfo.systemUptime
        let cold = try XCTUnwrap(owner.bootstrap())
        let coldMs = (ProcessInfo.processInfo.systemUptime - coldStarted) * 1000
        let warmStarted = ProcessInfo.processInfo.systemUptime
        let warm = try XCTUnwrap(owner.bootstrap())
        let warmMs = (ProcessInfo.processInfo.systemUptime - warmStarted) * 1000
        XCTAssertEqual(cold.fingerprint, warm.fingerprint)
        print("PD10_B5_BOOTSTRAP cold_ms=\(coldMs) warm_ms=\(warmMs)")
    }

    /// B6: failure to preserve previous.json is not a successful activation.
    func testB6PreviousPointerWriteFailureKeepsActiveAndDoesNotLogActivation() throws {
        let owner = installation()
        let initial = try XCTUnwrap(owner.bootstrap())
        let previousURL = owner.directory.appendingPathComponent("previous.json")
        try FileManager.default.createDirectory(at: previousURL, withIntermediateDirectories: true)
        let newer = try makeCatalogue(in: root.appendingPathComponent("failed-previous"), sources: 3, revision: 6)
        let outcome = owner.install(manifestData: try manifestData(for: newer, revision: 6), catalogue: newer)
        guard case .rejected = outcome else { return XCTFail("failed previous write must reject activation") }
        XCTAssertEqual(owner.activeSnapshot()?.fingerprint, initial.fingerprint)
        XCTAssertEqual(installation().bootstrap()?.fingerprint, initial.fingerprint,
            "relaunch cannot reinterpret the failed activation as a new revision")
        XCTAssertFalse(owner.ledger().contains { $0.outcome == .activated })
    }

    /// B6: neither an active-pointer failure nor rollback's failed pointer write may announce success.
    func testB6FailedActivePointerAndRollbackNeverReportFalseActivation() throws {
        let owner = installation()
        _ = try XCTUnwrap(owner.bootstrap())
        let newer = try makeCatalogue(in: root.appendingPathComponent("failed-active-new"), sources: 3, revision: 6)
        _ = owner.install(manifestData: try manifestData(for: newer, revision: 6), catalogue: newer)
        XCTAssertEqual(owner.activeSnapshot()?.revision, 6)
        let activatedCount = owner.ledger().filter { $0.outcome == .activated }.count
        let activeURL = owner.directory.appendingPathComponent("active.json")
        try FileManager.default.removeItem(at: activeURL)
        try FileManager.default.createDirectory(at: activeURL, withIntermediateDirectories: true)
        XCTAssertNil(owner.rollback(), "rollback must not succeed when active.json cannot be written")
        XCTAssertEqual(owner.ledger().filter { $0.outcome == .activated }.count, activatedCount)
        let newerAgain = try makeCatalogue(in: root.appendingPathComponent("failed-active-next"), sources: 4, revision: 7)
        guard case .rejected = owner.install(manifestData: try manifestData(for: newerAgain, revision: 7),
            catalogue: newerAgain) else { return XCTFail("active pointer failure must reject installation") }
        XCTAssertEqual(owner.ledger().filter { $0.outcome == .activated }.count, activatedCount)
        try FileManager.default.removeItem(at: activeURL)
        // Restart sees the verified previous snapshot, not the uncommitted revision 7.
        XCTAssertEqual(owner.bootstrap()?.revision, 5)
    }

    private func recoveryFixture(at root: URL) throws -> CatalogInstallation {
        let base = try makeCatalogue(in: root.appendingPathComponent("bundled"), sources: 2, revision: 5)
        let descriptor = try writeManifest(for: base, revision: 5, into: root, name: "bundle.json")
        let frozenClock = self.clock
        let owner = CatalogInstallation(directory: root.appendingPathComponent("catalogue"),
            bundledCatalogue: base, bundledManifest: descriptor, now: { frozenClock })
        XCTAssertEqual(owner.bootstrap()?.revision, 5)
        let later = try makeCatalogue(in: root.appendingPathComponent("newer"), sources: 3, revision: 6)
        guard case .installed = owner.install(manifestData: try manifestData(for: later, revision: 6),
            catalogue: later) else { throw CatalogManifest.DecodeError.malformed }
        XCTAssertEqual(owner.activeSnapshot()?.revision, 6)
        return owner
    }

    // MARK: - Personal data and the catalogue are separate

    func testRejectingARevisionNeverTouchesTheReadersPersonalData() throws {
        // The reader's data lives in runtime.sqlite under the app's own directory. The catalogue owner is given
        // a sibling directory and no path to it, and this test states the separation as a fact about the bytes.
        let runtimeURL = try writePersonalDatabase()
        let before = try Data(contentsOf: runtimeURL)
        let installation = installation()
        _ = try XCTUnwrap(installation.bootstrap())
        let tampered = try manifestData(for: catalogue, revision: 6,
            overrideChecksum: String(repeating: "0", count: 64))
        XCTAssertEqual(installation.install(manifestData: tampered, catalogue: catalogue),
            .rejected(.checksumMismatch(path: "catalog.sqlite", declared: String(repeating: "0", count: 64),
                present: try CatalogManifest.sha256(ofFile: catalogue))))
        XCTAssertEqual(try Data(contentsOf: runtimeURL), before, "personal data is byte-identical")
        let database = try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: appDirectory))
        XCTAssertTrue(try database.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM catalog_reader_fixture LIMIT 1")
        } == "saved", "a rejected catalogue revision leaves the reader's data readable")
    }

    // MARK: - Degraded first run

    func testWithNoVerifiedSnapshotTheBundledCopyIsServedAndStatedAsUnverified() throws {
        // A descriptor that does not describe the bytes: nothing verifies, but the app must still present a feed
        // on a first run with no network. It serves the bundled copy and says so — never a silent pass.
        let bogus = root.appendingPathComponent("bogus.json")
        try Data("""
        {"schemaVersion":1,"revision":9,"sourceCount":2,"fileCount":1,
         "files":[{"path":"catalog.sqlite","bytes":3,"sha256":"\(String(repeating: "0", count: 64))"}]}
        """.utf8).write(to: bogus)
        let clock = clock
        let installation = CatalogInstallation(
            directory: appDirectory.appendingPathComponent("catalogue", isDirectory: true),
            bundledCatalogue: catalogue, bundledManifest: bogus, now: { clock })
        let snapshot = try XCTUnwrap(installation.bootstrap())
        XCTAssertEqual(snapshot.catalogueURL, catalogue, "the bundled copy is what is read")
        XCTAssertNil(installation.activeSnapshot(), "nothing verified was installed")
        let records = installation.ledger()
        XCTAssertEqual(records.map(\.outcome), [.rejected, .deferred])
        XCTAssertEqual(records.last?.kind, "degraded")
        XCTAssertEqual(records.last?.reason,
            "serving the bundled catalogue unverified: no verified snapshot is installed")
    }

    func testABuildWithNoBundledCatalogueStatesThatInsteadOfInventingOne() {
        let clock = clock
        let installation = CatalogInstallation(
            directory: appDirectory.appendingPathComponent("catalogue", isDirectory: true),
            bundledCatalogue: nil, bundledManifest: nil, now: { clock })
        XCTAssertNil(installation.bootstrap())
        XCTAssertTrue(installation.ledger().isEmpty)
    }

    // MARK: - The ledger the external report reads

    func testTheLedgerIsDurableAcrossInstancesAndHoldsEveryDecisionInOrder() throws {
        let first = installation()
        _ = try XCTUnwrap(first.bootstrap())
        _ = first.install(manifestData: Data("{".utf8), catalogue: catalogue)
        let reopened = installation()
        let records = reopened.ledger()
        XCTAssertEqual(records.map(\.outcome), [.bootstrapped, .rejected])
        XCTAssertEqual(records.map(\.at), [ISO8601DateFormatter.string(clock), ISO8601DateFormatter.string(clock)])
        XCTAssertTrue(FileManager.default.fileExists(atPath: reopened.ledgerURL.path))
    }

    // MARK: - Helpers

    private func contents(of directory: URL) throws -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    }

    private func writePersonalDatabase() throws -> URL {
        let url = appDirectory.appendingPathComponent("runtime.sqlite")
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE catalog_reader_fixture (value TEXT NOT NULL)")
            try db.execute(sql: "INSERT INTO catalog_reader_fixture (value) VALUES ('saved')")
        }
        return url
    }

    private func writeManifest(for catalogue: URL, revision: Int, into directory: URL,
        name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try manifestData(for: catalogue, revision: revision).write(to: url)
        return url
    }

    private func manifestData(for catalogue: URL, revision: Int, sourceCount: Int? = nil,
        overrideChecksum: String? = nil) throws -> Data {
        let bytes = try XCTUnwrap(catalogue.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        let digest = try CatalogManifest.sha256(ofFile: catalogue)
        let manifest = CatalogManifest(revision: revision,
            sourceCount: sourceCount ?? declaredSourceCount(of: catalogue), fileCount: 1,
            files: [CatalogManifestEntry(path: "catalog.sqlite", bytes: bytes,
                sha256: overrideChecksum ?? digest)])
        return try manifest.encoded()
    }

    /// The count the catalogue itself declares — the value a manifest must agree with.
    private func declaredSourceCount(of catalogue: URL) -> Int {
        guard let reader = try? LegacyCatalogReader(catalogURL: catalogue) else { return 2 }
        return (try? reader.metadata())?.sourceCount ?? 2
    }

    /// A staging directory a caller would have downloaded: the OPML input, and the compiled catalogue when the
    /// fake builder has already produced one (`catalogue`), or none when the payload is the un-built input.
    private func writePayload(in directory: URL, contents: String, catalogue: URL? = nil) throws -> URL {
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("Feeds"),
            withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: directory.appendingPathComponent("Feeds/01.opml"))
        if let catalogue {
            try FileManager.default.copyItem(at: catalogue, to: directory.appendingPathComponent("catalog.sqlite"))
        }
        return directory
    }

    /// A manifest covering a payload: the OPML inventory the payload is verified against, and the compiled
    /// catalogue it must build into. The caller supplies the expected catalogue because it exists only after the
    /// build — which is exactly the order the install enforces.
    private func payloadManifest(payload: URL, revision: Int, catalogue: URL) throws -> CatalogManifest {
        let opml = payload.appendingPathComponent("Feeds/01.opml")
        return CatalogManifest(revision: revision, sourceCount: declaredSourceCount(of: catalogue), fileCount: 2,
            files: [CatalogManifestEntry(path: "Feeds/01.opml", bytes: try fileSize(opml),
                sha256: try CatalogManifest.sha256(ofFile: opml)),
                CatalogManifestEntry(path: "catalog.sqlite", bytes: try fileSize(catalogue),
                    sha256: try CatalogManifest.sha256(ofFile: catalogue))])
    }

    private func fileSize(_ url: URL) throws -> Int {
        try XCTUnwrap(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
    }
}

private extension ISO8601DateFormatter {
    static func string(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
