import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence

final class AvailabilityPrecedenceTests: XCTestCase {
    private typealias Store = AcquisitionAdmissionStore
    private struct Fixture {
        let location: RuntimeDatabaseLocation
        let database: RuntimeDatabase
        let targetID = AcquisitionTargetID()
        let sourceID = SourceID()
        var store: Store { .init(database: database) }
        var content: ContentStore { .init(database: database) }
        var targets: AcquisitionTargetStore { .init(database: database) }
        init(location: RuntimeDatabaseLocation) throws {
            self.location = location; database = try RuntimeDatabase(location: location)
            _ = try targets.register(id: targetID,connectorKind: .syndication, authorizedSources: [sourceID])
        }
        func observation(_ availability: OriginAvailability = .available,at: Double = 100,
            headline: String = "Original",mediaURL: String = "https://example.invalid/old",source: SourceID? = nil) -> Store.ObservationCommand {
            .init(objectIdentity: .init(connectorKind: .syndication,namespace: "objects",value: "X",role: .object),
                versionIdentity: .init(connectorKind: .syndication,namespace: "versions",value: "v1",role: .version),
                precedence: .makeCurrent,availability: availability,headline: headline,summary: nil,bodyText: nil,
                authoredAt: nil,modifiedAt: nil,observedAt: Date(timeIntervalSince1970: at),language: nil,
                primaryLink: nil,searchProjection: nil,providerID: nil,
                memberships: [.init(sourceID: source ?? sourceID,kind: .direct)],
                mediaCandidates: [.init(role: .cardVisual,mediaClass: .image,remoteURL: URL(string: mediaURL)!,
                    declaredMimeType: nil,declaredPixelWidth: nil,declaredPixelHeight: nil)!])
        }
        func admit(_ observations: [Store.ObservationCommand],checkpoint: Bool = false) throws -> Store.AdmissionRecord {
            let target = try XCTUnwrap(targets.target(id: targetID))
            return try store.admit(.init(targetID: targetID,targetGeneration: target.generation,
                expectedCheckpointRevision: target.checkpointRevision,observations: observations,
                nextCheckpoint: checkpoint ? .init(blob: Data([1]),serializationSchema: 1,connectorVersion: "test")! : nil))
        }
        func record() throws -> OriginRecord {
            let id = try database.read { try String.fetchOne($0,sql: "SELECT id FROM origin_records")! }
            return try XCTUnwrap(content.originRecord(id: OriginRecordID(rawValue: UUID(uuidString: id)!)))
        }
        func availabilityTime() throws -> Double {
            try database.read { try Double.fetchOne($0,sql: "SELECT availability_observed_at FROM origin_records")! }
        }
    }
    private func location() -> RuntimeDatabaseLocation {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return .init(directory: root)
    }
    func testA1MigrationBackfillsEveryStateWithoutChangingExistingDataAndReopens() throws {
        let location = location()
        try FileManager.default.createDirectory(at: location.directory,withIntermediateDirectories: true)
        let columns = "id, object_connector_kind, object_namespace, object_value, object_role, current_revision_id, availability, first_observed_at, last_observed_at"
        let before: [String]
        do {
            let pool = try DatabasePool(path: location.databaseURL.path)
            try RuntimeMigrations.current.migrate(pool,upTo: "publication-origin-exposure-index-v1")
            try pool.write { db in
                for (index,state) in [OriginAvailability.available,.updated,.removed,.revoked,.unknown].enumerated() {
                    try db.execute(sql: "INSERT INTO origin_records (\(columns)) VALUES (?, 'syndication', 'legacy', ?, 'object', NULL, ?, ?, ?)",
                        arguments: [UUID().uuidString.lowercased(),String(index),state.rawValue,Double(index),Double(100 + index)])
                }
            }
            before = try pool.read { try Row.fetchAll($0,sql: "SELECT \(columns) FROM origin_records ORDER BY object_value").map { $0.description } }
        }
        do {
            let database = try RuntimeDatabase(location: location)
            let after = try database.read { try Row.fetchAll($0,sql: "SELECT \(columns) FROM origin_records ORDER BY object_value").map { $0.description } }
            XCTAssertEqual(after,before)
            try database.read { db in
                XCTAssertEqual(try Int.fetchOne(db,sql: "SELECT COUNT(*) FROM origin_records"),5)
                XCTAssertEqual(try Int.fetchOne(db,sql: "SELECT COUNT(*) FROM origin_records WHERE availability_observed_at IS NULL OR availability_observed_at != last_observed_at"),0)
                XCTAssertEqual(try String.fetchOne(db,sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid DESC LIMIT 1"),"reader-imported-sources-v1")
            }
        }
        let reopened = try RuntimeDatabase(location: location)
        XCTAssertEqual(try reopened.read { try Double.fetchAll($0,sql: "SELECT availability_observed_at FROM origin_records ORDER BY object_value") },[100,101,102,103,104])
    }
    func testA17AvailabilityTimestampAndSelectableStateChangesDoNotInventSupplyChanges() throws {
        let f = try Fixture(location: location()); _ = try f.admit([f.observation()])
        let updated = try f.admit([f.observation(.updated,at: 200)])
        XCTAssertFalse(updated.selectableSupplyChanged)
        XCTAssertEqual(try f.record().availability,.updated); XCTAssertEqual(try f.availabilityTime(),200)
        let rejected = try f.admit([f.observation(.updated,at: 201,headline: "Conflict")])
        XCTAssertFalse(rejected.selectableSupplyChanged)
        XCTAssertEqual(try f.availabilityTime(),201)
        XCTAssertEqual(try f.record().lastObservedAt,Date(timeIntervalSince1970: 200))
    }
    func testA3NewOriginAlwaysInitializesAvailabilityTimestamp() throws {
        let f = try Fixture(location: location()); _ = try f.admit([f.observation()])
        XCTAssertEqual(try f.availabilityTime(),100)
        XCTAssertEqual(try f.record().lastObservedAt,Date(timeIntervalSince1970: 100))
    }
    func testA4ThroughA10PrecedenceRemovalRevocationAndExplicitReactivation() throws {
        for unavailable in [OriginAvailability.removed,.revoked] {
            let f = try Fixture(location: location()); _ = try f.admit([f.observation()])
            _ = try f.admit([f.observation(unavailable,at: 200)])
            XCTAssertEqual(try f.record().availability,unavailable); XCTAssertEqual(try f.availabilityTime(),200)
            for signal in [150.0,200.0] {
                _ = try f.admit([f.observation(.available,at: signal)])
                XCTAssertEqual(try f.record().availability,unavailable); XCTAssertEqual(try f.availabilityTime(),200)
                XCTAssertTrue(try f.content.candidateWindow(sourceID: nil,after: nil,examinedCapacity: 10).records.isEmpty)
            }
            _ = try f.admit([f.observation(unavailable,at: 200)])
            XCTAssertEqual(try f.availabilityTime(),200)
            _ = try f.admit([f.observation(.available,at: 201)])
            XCTAssertEqual(try f.record().availability,.available); XCTAssertEqual(try f.availabilityTime(),201)
            XCTAssertEqual(try f.content.candidateWindow(sourceID: nil,after: nil,examinedCapacity: 10).records.count,1)
        }
    }
    func testA11A12A13A17RejectedPayloadAndMediaApplyOnlyAvailabilityAndRealSupplyChange() throws {
        for mediaConflict in [false,true] {
            let f = try Fixture(location: location()); _ = try f.admit([f.observation()])
            let original = try f.record(), revision = try XCTUnwrap(f.content.currentRevision(originRecordID: original.id))
            let media = try f.content.mediaCandidates(originRevisionID: revision.id)
            let memberships = try f.content.memberships(originRecordID: original.id)
            let expectedMemberships = memberships.map {
                SourceMembership(originRecordID: $0.originRecordID,sourceID: $0.sourceID,kind: $0.kind,
                    firstObservedAt: $0.firstObservedAt,lastObservedAt: Date(timeIntervalSince1970: 200))
            }
            let rejected = f.observation(.removed,at: 200,headline: mediaConflict ? "Original" : "Conflict",
                mediaURL: mediaConflict ? "https://example.invalid/new" : "https://example.invalid/old",source: f.sourceID)
            let receipt = try f.admit([rejected],checkpoint: true)
            XCTAssertEqual(receipt.rejectedObservations,[.init(index: 0,reason: mediaConflict ? .knownVersionMediaConflict : .knownVersionPayloadConflict)])
            XCTAssertTrue(receipt.checkpointAdvanced); XCTAssertTrue(receipt.selectableSupplyChanged)
            XCTAssertEqual(try f.record().availability,.removed); XCTAssertEqual(try f.availabilityTime(),200)
            XCTAssertEqual(try f.record().currentRevisionID,original.currentRevisionID)
            XCTAssertEqual(try f.record().lastObservedAt,original.lastObservedAt)
            XCTAssertEqual(try f.content.currentRevision(originRecordID: original.id),revision)
            XCTAssertEqual(try f.content.mediaCandidates(originRevisionID: revision.id),media)
            XCTAssertEqual(try f.content.memberships(originRecordID: original.id),expectedMemberships)
            XCTAssertEqual(try f.database.read { try Int.fetchOne($0,sql: "SELECT COUNT(*) FROM origin_revisions") },1)
            let replay = try f.admit([rejected],checkpoint: true)
            XCTAssertFalse(replay.selectableSupplyChanged)
            let reopened = ContentStore(database: try RuntimeDatabase(location: f.location))
            XCTAssertEqual(try reopened.originRecord(id: original.id)?.availability,.removed)
            XCTAssertEqual(try reopened.currentRevision(originRecordID: original.id),revision)
            XCTAssertEqual(try reopened.memberships(originRecordID: original.id),expectedMemberships)
        }
    }
    func testA14A15AvailabilityAndCheckpointRollbackOnStructuralFailure() throws {
        let f = try Fixture(location: location()); _ = try f.admit([f.observation()])
        let before = try f.record()
        let beforeMemberships = try f.content.memberships(originRecordID: before.id)
        try f.database.write { try $0.execute(sql: "CREATE TRIGGER refuse_checkpoint BEFORE UPDATE OF checkpoint_revision ON acquisition_targets BEGIN SELECT RAISE(ABORT,'test structural failure'); END") }
        XCTAssertThrowsError(try f.admit([f.observation(.revoked,at: 200,headline: "Conflict")],checkpoint: true))
        XCTAssertEqual(try f.content.memberships(originRecordID: before.id),beforeMemberships)
        XCTAssertEqual(try f.record(),before); XCTAssertEqual(try f.availabilityTime(),100)
        XCTAssertEqual(try f.targets.target(id: f.targetID)?.checkpointRevision,0)
        XCTAssertEqual(try f.content.candidateWindow(sourceID: nil,after: nil,examinedCapacity: 10).records.count,1)
    }
    func testA2ReopenRejectsStaleAvailabilityAfterUnrelatedLastObservedAtRegresses() throws {
        let f = try Fixture(location: location()); _ = try f.admit([f.observation()])
        _ = try f.admit([f.observation(.removed,at: 200)])
        _ = try f.admit([f.observation(.available,at: 150)])
        XCTAssertEqual(try f.record().lastObservedAt,Date(timeIntervalSince1970: 150))
        let database = try RuntimeDatabase(location: f.location), store = Store(database: database)
        let target = try XCTUnwrap(f.targets.target(id: f.targetID))
        _ = try store.admit(.init(targetID: target.id,targetGeneration: target.generation,
            expectedCheckpointRevision: target.checkpointRevision,observations: [f.observation(.available,at: 175)],nextCheckpoint: nil))
        XCTAssertEqual(try ContentStore(database: database).originRecord(id: f.record().id)?.availability,.removed)
        XCTAssertEqual(try database.read { try Double.fetchOne($0,sql: "SELECT availability_observed_at FROM origin_records") },200)
    }
}
