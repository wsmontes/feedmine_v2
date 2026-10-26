import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence

/// S1: the `.visit` authority at the **store** level. The visit licence is process-scoped, but the store is where
/// the durable guarantees live: nothing is created, no stored cursor moves, the armed source set is the whole
/// licence, and a durable row — enabled or revoked — outranks the visit even when the caller says otherwise.
/// These cases exist because a public `AuthorityStamp` can be constructed by any persistence consumer.
final class TransientAdmissionTests: XCTestCase {
    private typealias Store = AcquisitionAdmissionStore
    private typealias Command = Store.BatchCommand

    private final class Fixture {
        let root: URL
        let database: RuntimeDatabase
        let targetID: AcquisitionTargetID
        let sourceID: SourceID
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            database = try RuntimeDatabase(location: .init(directory: root))
            targetID = AcquisitionTargetID()
            sourceID = SourceID()
        }
        var store: Store { Store(database: database) }
        var targets: AcquisitionTargetStore { AcquisitionTargetStore(database: database) }
        func count(_ table: String) throws -> Int {
            try database.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table)")! }
        }
        func canonicalCounts() throws -> [String: Int] {
            var result: [String: Int] = [:]
            for table in ["origin_records", "origin_revisions", "source_memberships", "acquisition_targets"] {
                result[table] = try count(table)
            }
            return result
        }
    }

    private func fixture() throws -> Fixture {
        let f = try Fixture()
        let root = f.root
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return f
    }

    private static func identity(_ value: String, role: ExternalIdentityRole = .object) -> ExternalIdentity {
        .init(connectorKind: .syndication, namespace: " transient-test ", value: value, role: role)
    }

    private func observation(_ f: Fixture, object: String = "object", version: String = "v1",
        memberships: [Store.MembershipCommand]? = nil) -> Store.ObservationCommand {
        .init(objectIdentity: Self.identity(object),
            versionIdentity: Self.identity(version, role: .version), precedence: .makeCurrent,
            availability: .available, headline: "Headline", summary: nil, bodyText: nil,
            authoredAt: nil, modifiedAt: nil, observedAt: Date(timeIntervalSince1970: 10),
            language: nil, primaryLink: nil, searchProjection: nil, providerID: nil,
            memberships: memberships ?? [.init(sourceID: f.sourceID, kind: .direct)], mediaCandidates: [])
    }

    private func checkpoint() -> AcquisitionTargetStore.CheckpointRecord {
        .init(blob: Data([1, 2, 3]), serializationSchema: 2, connectorVersion: "v")!
    }

    private func visitCommand(_ f: Fixture, observations: [Store.ObservationCommand],
        sources: Set<SourceID>? = nil) -> Command {
        .init(targetID: f.targetID, targetGeneration: 1, expectedCheckpointRevision: 0,
            observations: observations, nextCheckpoint: checkpoint(),
            authority: .visit(connectorKind: .syndication,
                authorizedSources: sources ?? [f.sourceID]))
    }

    /// The visit admits canonical supply without creating or enabling a durable target, and its cursor is not a
    /// stored cursor: the receipt reports no durable advance even though a next checkpoint was supplied.
    func testVisitAdmitsCanonicalSupplyWithoutCreatingOrMovingADurableTarget() throws {
        let f = try fixture()
        let record = try f.store.admit(visitCommand(f, observations: [observation(f)]))
        XCTAssertTrue(record.selectableSupplyChanged)
        XCTAssertFalse(record.checkpointAdvanced,
            "a visit's cursor must never be reported as a durable cursor")
        XCTAssertEqual(try f.count("acquisition_targets"), 0,
            "opening a source must not create its durable target")
        XCTAssertEqual(try f.count("origin_records"), 1)
        XCTAssertEqual(try f.count("source_memberships"), 1)
    }

    /// The armed source set is the whole licence: a membership the arming did not name is refused before any
    /// canonical write, and the batch leaves no residue.
    func testVisitRefusesAMembershipOutsideItsArmedSources() throws {
        let f = try fixture()
        let other = SourceID()
        let before = try f.canonicalCounts()
        XCTAssertThrowsError(try f.store.admit(visitCommand(f,
            observations: [observation(f, memberships: [.init(sourceID: other, kind: .direct)])]))) {
            XCTAssertEqual($0 as? AcquisitionAdmissionStoreError,
                .unauthorizedSource(index: 0, targetID: f.targetID, sourceID: other))
        }
        XCTAssertEqual(try f.canonicalCounts(), before)
    }

    /// D1: a durable row — in **either** state — is the only authority for its target. A `.visit` stamp that tries
    /// to admit while that row exists is refused inside the same write transaction, including the revoked row the
    /// S1 contract says cannot be resurrected. The durable path still reports its own error, so the refusal did not
    /// replace the structural fence callers already handle.
    func testVisitIsRefusedForEnabledAndRevokedDurableRowsAndWritesNothing() throws {
        let f = try fixture()
        _ = try f.targets.register(id: f.targetID, connectorKind: .syndication, authorizedSources: [f.sourceID])

        let enabledBefore = try f.canonicalCounts()
        XCTAssertThrowsError(try f.store.admit(visitCommand(f, observations: [observation(f)]))) {
            XCTAssertEqual($0 as? AcquisitionAdmissionStoreError, .durableTargetExists(f.targetID))
        }
        XCTAssertEqual(try f.canonicalCounts(), enabledBefore,
            "the refused batch wrote nothing while the row was enabled")

        _ = try f.targets.revoke(id: f.targetID, expectedGeneration: 1)
        let revokedBefore = try f.canonicalCounts()
        XCTAssertThrowsError(try f.store.admit(visitCommand(f, observations: [observation(f)]))) {
            XCTAssertEqual($0 as? AcquisitionAdmissionStoreError, .durableTargetExists(f.targetID))
        }
        XCTAssertEqual(try f.canonicalCounts(), revokedBefore,
            "a revoked row was not resurrected by a visit stamp")

        // Control: the durable authority is still the one that says "revoked", with its own error.
        XCTAssertThrowsError(try f.store.admit(.init(targetID: f.targetID, targetGeneration: 2,
            expectedCheckpointRevision: 0, observations: [observation(f)], nextCheckpoint: nil))) {
            XCTAssertEqual($0 as? AcquisitionTargetStoreError, .targetRevoked(f.targetID))
        }
    }

    /// D3(b) at its source: a visit licence that names no source cannot admit an observation without memberships.
    func testVisitAuthorityWithoutSourcesIsRefused() throws {
        let f = try fixture()
        let before = try f.canonicalCounts()
        XCTAssertThrowsError(try f.store.admit(visitCommand(f,
            observations: [observation(f, memberships: [])], sources: []))) {
            XCTAssertEqual($0 as? AcquisitionAdmissionStoreError, .visitAuthorityWithoutSources(f.targetID))
        }
        XCTAssertEqual(try f.canonicalCounts(), before)
    }

    /// A visit for one target never moves another target's durable cursor: the supplied next checkpoint is the
    /// visit's own, and only the durable branch is allowed to store it.
    func testVisitLeavesAnotherTargetsDurableCursorUntouched() throws {
        let f = try fixture()
        let durable = try f.targets.register(id: AcquisitionTargetID(), connectorKind: .syndication,
            authorizedSources: [f.sourceID])
        let stored = try f.targets.compareAndSwapCheckpoint(id: durable.id, expectedGeneration: 1,
            expectedCheckpointRevision: 0, next: checkpoint())
        _ = try f.store.admit(visitCommand(f, observations: [observation(f)]))
        XCTAssertEqual(try f.targets.target(id: durable.id), stored,
            "only the durable branch owns a stored cursor")
    }
}
