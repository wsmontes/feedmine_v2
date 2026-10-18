import Foundation
import XCTest
import GRDB
@testable import FeedMinePersistence
@testable import FeedMineComposition
import FeedMineDomain
import FeedMineAcquisition
import FeedMineEditorial

/// R08: the traversal's derived indices and the materialization reservation. The catalogue page and the SQL work run
/// outside the lock; a page is installed only under the identity it was reserved with, and an older page's target is
/// recognised by the index instead of a scan over prior pages.
final class ReaderDiscoveryTraversalTests: XCTestCase {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var current: Int { lock.lock(); defer { lock.unlock() }; return value }
        func increment() { lock.lock(); value += 1; lock.unlock() }
    }

    private final class IdentityBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: String?
        init(_ value: String?) { storage = value }
        var value: String? {
            get { lock.lock(); defer { lock.unlock() }; return storage }
            set { lock.lock(); storage = newValue; lock.unlock() }
        }
    }

    /// A blocking materialization: the first call holds until `release`, so a second opportunity arrives while the
    /// page is being materialized outside the lock.
    private final class SyncGate: @unchecked Sendable {
        private let condition = NSCondition()
        private var open = false
        private var entered = false
        func enter() {
            condition.lock(); entered = true; condition.broadcast()
            while !open { condition.wait() }
            condition.unlock()
        }
        func waitForEntry(timeout: TimeInterval) -> Bool {
            condition.lock(); defer { condition.unlock() }
            if entered { return true }
            _ = condition.wait(until: Date().addingTimeInterval(timeout))
            return entered
        }
        func release() { condition.lock(); open = true; condition.broadcast(); condition.unlock() }
    }

    private enum Failure: Error { case expected }

    private func fixture(identity: (@Sendable () -> String?)? = nil) throws
        -> (ReaderDiscoveryTraversal, SyndicationAcquisitionSnapshot) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let catalogURL = try makeCatalogue(in: directory.appendingPathComponent("catalog"), sources: 12, revision: 5)
        let database = try RuntimeDatabase(location: .init(directory: directory.appendingPathComponent("db")))
        let transport = URLSession(configuration: .ephemeral)
        addTeardownBlock { transport.invalidateAndCancel() }
        let snapshot = try SyndicationAcquisitionSnapshot(database: database, registrations: [],
            session: transport, redirectCapacity: 0)
        let traversal = ReaderDiscoveryTraversal(builder: ReaderDiscoveryBuilder(catalogURL: catalogURL),
            profile: .init(topicNodeKeys: ["topics/science"]), contextKey: .init(request: .main),
            catalogueIdentity: identity)
        return (traversal, snapshot)
    }

    /// An older page's target is recognised by the index: adopting it again does not rematerialize or duplicate.
    /// With several pages installed, the check still costs one lookup — and the flattened entries are the index the
    /// connector lookup reads.
    func testConnectorLookupDoesNotScanPriorPages() throws {
        let (traversal, snapshot) = try fixture()
        let materializations = Counter()
        var installedPages = 0
        while let page = try traversal.advance(examinedCapacity: 3, materialize: { _ in
            materializations.increment()
            return snapshot
        }) {
            installedPages += 1
            XCTAssertFalse(page.entries.isEmpty)
            if installedPages >= 3 { break }
        }
        XCTAssertGreaterThanOrEqual(installedPages, 3, "premissa: três páginas instaladas")
        let first = try XCTUnwrap(traversal.entries.first)
        let before = materializations.current
        let adopted = try traversal.adopt([first], materialize: { _ in
            materializations.increment()
            return ([], snapshot)
        })
        XCTAssertTrue(adopted.isEmpty, "o alvo de uma página anterior é reconhecido sem varredura")
        XCTAssertEqual(materializations.current, before, "lookup repetido não rematerializa")
    }

    /// A second opportunity during materialization is refused by the reservation; the page installs once.
    func testAReservedMaterializationRefusesAConcurrentAdvance() async throws {
        let (traversal, snapshot) = try fixture()
        let gate = SyncGate(), materializations = Counter()
        let first = Task.detached { [traversal, snapshot, gate, materializations] in
            try traversal.advance(examinedCapacity: 3) { _ in
                materializations.increment()
                gate.enter()
                return snapshot
            }
        }
        XCTAssertTrue(gate.waitForEntry(timeout: 3), "premissa: a materialização começou")
        let concurrent = try traversal.advance(examinedCapacity: 3, materialize: { _ in
            materializations.increment()
            return snapshot
        })
        XCTAssertNil(concurrent, "a oportunidade concorrente é recusada pela reserva")
        gate.release()
        let page = try await first.value
        XCTAssertNotNil(page)
        XCTAssertEqual(materializations.current, 1, "uma materialização para uma instalação")
        XCTAssertFalse(traversal.entries.isEmpty)
    }

    /// A failing materialization releases the reservation without advancing: the same first page is retried.
    func testFailedMaterializationReleasesTheReservationWithoutAdvancing() throws {
        let (traversal, snapshot) = try fixture()
        var attempted: [AcquisitionTargetID] = []
        XCTAssertThrowsError(try traversal.advance(examinedCapacity: 3, materialize: { entries in
            attempted = entries.map(\.targetID)
            throw Failure.expected
        }))
        XCTAssertTrue(traversal.entries.isEmpty)
        let page = try XCTUnwrap(traversal.advance(examinedCapacity: 3, materialize: { entries in
            XCTAssertEqual(entries.map(\.targetID), attempted, "o cursor não avançou após a falha")
            return snapshot
        }))
        XCTAssertFalse(page.entries.isEmpty)
        XCTAssertEqual(traversal.entries.map(\.targetID), attempted)
    }

    /// A catalogue promotion/revocation during materialization: the page belongs to a superseded identity, so it is
    /// discarded (no target installed, cursor untouched) and the next opportunity runs under the new identity.
    func testCatalogueRevocationDuringMaterializationCannotReinstallTarget() throws {
        let identity = IdentityBox("catalog-A")
        let (traversal, snapshot) = try fixture(identity: { identity.value })
        let discarded = try traversal.advance(examinedCapacity: 3, materialize: { _ in
            identity.value = "catalog-B"
            return snapshot
        })
        XCTAssertNil(discarded, "a página materializada sob identidade superada não é instalada")
        XCTAssertTrue(traversal.entries.isEmpty, "nenhum alvo do catálogo superado entra na travessia")
        let page = try XCTUnwrap(traversal.advance(examinedCapacity: 3, materialize: { _ in snapshot }))
        XCTAssertFalse(page.entries.isEmpty, "a nova identidade volta a instalar")
        XCTAssertFalse(traversal.entries.isEmpty)
    }
}
