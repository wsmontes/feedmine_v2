import Foundation
import XCTest
import FeedMineDomain
@testable import FeedMinePersistence
import FeedMineAcquisition
import FeedMineComposition

final class MembershipAuthorityIntegrationTests: XCTestCase {
    func testAuthoritySurvivesReopenAndReconfigureReplacesSources() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let location = RuntimeDatabaseLocation(directory: root)
        let x = SourceID(), y = SourceID(), id = AcquisitionTargetID()
        let authority = AcquisitionTargetAuthority(database: try RuntimeDatabase(location: location))
        let target = try authority.register(id: id,connectorKind: .syndication,authorizedSources: [x,y])
        XCTAssertEqual(try authority.authorizedSources(id: id),[x,y])
        let reopened = AcquisitionTargetAuthority(database: try RuntimeDatabase(location: location))
        XCTAssertEqual(try reopened.authorizedSources(id: id),[x,y])
        let next = try reopened.reconfigure(id: id,expectedGeneration: target.generation,connectorKind: .syndication,
            checkpoint: .preserve,authorizedSources: [y])
        XCTAssertEqual(next.generation,2)
        XCTAssertEqual(try reopened.authorizedSources(id: id),[y])
    }
    private func database() throws -> RuntimeDatabase {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try RuntimeDatabase(location: .init(directory: root))
    }
    private static func registration(_ target: AcquisitionTarget, sources: [SourceID]) -> SyndicationTargetRegistration {
        .init(targetID: target.id,targetGeneration: target.generation,endpoint: URL(string: "https://authority.test/feed")!,
            bindings: sources.map { .init(id: SourceBindingID(),sourceID: $0,
                externalPrincipal: .init(connectorKind: .syndication,namespace: "trusted",value: "principal",role: .principal),
                aliases: [],generation: 1,state: .enabled)! })!
    }
    private static func snapshot(_ database: RuntimeDatabase, _ registration: SyndicationTargetRegistration) throws -> SyndicationAcquisitionSnapshot {
        try .init(database: database,registrations: [registration],session: URLSession(configuration: .ephemeral),redirectCapacity: 0)
    }
    private static func observation(_ source: SourceID, headline: String = "original", media: Bool = false) -> AcquisitionObservation {
        .init(objectIdentity: .init(connectorKind: .syndication,namespace: "objects",value: "X",role: .object),
            versionIdentity: .init(connectorKind: .syndication,namespace: "versions",value: "v1",role: .version),
            precedence: .makeCurrent,availability: .available,headline: headline,summary: nil,bodyText: nil,
            authoredAt: nil,modifiedAt: nil,observedAt: Date(timeIntervalSince1970: 100),language: nil,
            primaryLink: nil,searchProjection: nil,providerID: nil,memberships: [.init(sourceID: source,kind: .direct)],
            mediaCandidates: media ? [.init(role: .cardVisual,mediaClass: .image,remoteURL: URL(string: "https://authority.test/image")!,
                declaredMimeType: nil,declaredPixelWidth: nil,declaredPixelHeight: nil)!] : [])!
    }
    func testMaterializationOrderIdempotenceDivergenceAndExplicitReconfigure() throws {
        let db = try database(), authority = AcquisitionTargetAuthority(database: db), x = SourceID(), y = SourceID(), z = SourceID()
        let target = try authority.register(id: AcquisitionTargetID(),connectorKind: .syndication,authorizedSources: [x,y])
        let old = try Self.snapshot(db,Self.registration(target,sources: [x,y]))
        _ = try Self.snapshot(db,Self.registration(target,sources: [y,x]))
        XCTAssertEqual(try authority.target(id: target.id),target)
        XCTAssertThrowsError(try Self.snapshot(db,Self.registration(target,sources: [x,z]))) {
            XCTAssertEqual($0 as? AcquisitionTargetStoreError,.sourceConfigurationConflict(target.id))
        }
        XCTAssertEqual(try authority.authorizedSources(id: target.id),[x,y])
        let next = try authority.reconfigure(id: target.id,expectedGeneration: 1,connectorKind: .syndication,
            checkpoint: .preserve,authorizedSources: [z])
        XCTAssertEqual(next.generation,2); XCTAssertEqual(try authority.authorizedSources(id: target.id),[z])
        XCTAssertThrowsError(try old.eligibleTargets(for: .init(request: .main)))
        XCTAssertThrowsError(try Self.snapshot(db,Self.registration(target,sources: [x,y])))
        XCTAssertEqual(try Self.snapshot(db,Self.registration(next,sources: [z])).eligibleTargets(for: .init(request: .main)),[next])
    }
    func testRevokeEnableKeepSourcesOnCurrentGenerationAndCannotAdmitOldBatch() throws {
        let db = try database(), authority = AcquisitionTargetAuthority(database: db), source = SourceID()
        let target = try authority.register(id: AcquisitionTargetID(),connectorKind: .syndication,authorizedSources: [source])
        let revoked = try authority.revoke(id: target.id,expectedGeneration: 1)
        _ = try Self.snapshot(db,Self.registration(revoked,sources: [source]))
        XCTAssertEqual(try authority.target(id: target.id)?.state,.revoked)
        XCTAssertThrowsError(try AdmissionPolicy(database: db).admit(.init(targetID: target.id,targetGeneration: revoked.generation,
            expectedCheckpointRevision: 0,observations: [Self.observation(source)],nextCheckpoint: nil)!))
        let enabled = try authority.enable(id: target.id,expectedGeneration: revoked.generation)
        XCTAssertEqual(enabled.generation,3); XCTAssertEqual(try authority.authorizedSources(id: target.id),[source])
        XCTAssertThrowsError(try AdmissionPolicy(database: db).admit(.init(targetID: target.id,targetGeneration: 1,
            expectedCheckpointRevision: 0,observations: [Self.observation(source)],nextCheckpoint: nil)!))
        XCTAssertTrue(try AdmissionPolicy(database: db).admit(.init(targetID: target.id,targetGeneration: enabled.generation,
            expectedCheckpointRevision: 0,observations: [Self.observation(source)],nextCheckpoint: nil)!).selectableSupplyChanged)
    }
    func testUnauthorizedClaimIsStructuralAndRollsBackWholeBatch() throws {
        let db = try database(), authority = AcquisitionTargetAuthority(database: db), x = SourceID(), y = SourceID()
        let target = try authority.register(id: AcquisitionTargetID(),connectorKind: .syndication,authorizedSources: [x])
        let checkpoint = AcquisitionCheckpoint(blob: Data([1]),serializationSchema: 1,connectorVersion: "fixture")!
        XCTAssertThrowsError(try AdmissionPolicy(database: db).admit(.init(targetID: target.id,targetGeneration: 1,
            expectedCheckpointRevision: 0,observations: [Self.observation(x),Self.observation(y)],nextCheckpoint: checkpoint)!)) {
            XCTAssertEqual($0 as? AcquisitionAdmissionStoreError,.unauthorizedSource(index: 1,targetID: target.id,sourceID: y))
            XCTAssertFalse($0 is ConnectorOperationalFailure)
        }
        XCTAssertEqual(try authority.target(id: target.id)?.checkpointRevision,0)
        XCTAssertTrue(try ContentStore(database: db).candidateWindow(sourceID: nil,after: nil,examinedCapacity: 10).records.isEmpty)
    }
    func testRejectedPayloadAndMediaApplyOnlyAuthorizedMembershipPreserveHistory() throws {
        for media in [false,true] {
            let db = try database(), authority = AcquisitionTargetAuthority(database: db), x = SourceID(), y = SourceID()
            let target = try authority.register(id: AcquisitionTargetID(),connectorKind: .syndication,authorizedSources: [x,y])
            let policy = AdmissionPolicy(database: db), content = ContentStore(database: db)
            _ = try policy.admit(.init(targetID: target.id,targetGeneration: 1,expectedCheckpointRevision: 0,
                observations: [Self.observation(x)],nextCheckpoint: nil)!)
            let candidate = try XCTUnwrap(content.candidateWindow(sourceID: x,after: nil,examinedCapacity: 10).records.first)
            let before = try content.currentRevision(originRecordID: candidate.originRecordID)
            let storedMedia = try content.mediaCandidates(originRevisionID: candidate.originRevisionID)
            let receipt = try policy.admit(.init(targetID: target.id,targetGeneration: 1,expectedCheckpointRevision: 0,
                observations: [Self.observation(y,headline: media ? "original" : "conflict",media: media)],
                nextCheckpoint: .init(blob: Data([1]),serializationSchema: 1,connectorVersion: "fixture")!)!)
            XCTAssertEqual(receipt.rejectedObservations,[.init(index: 0,reason: media ? .knownVersionMediaConflict : .knownVersionPayloadConflict)])
            XCTAssertTrue(receipt.checkpointAdvanced); XCTAssertTrue(receipt.selectableSupplyChanged)
            XCTAssertEqual(try content.currentRevision(originRecordID: candidate.originRecordID),before)
            XCTAssertEqual(try content.mediaCandidates(originRevisionID: candidate.originRevisionID),storedMedia)
            XCTAssertEqual(Set(try content.memberships(originRecordID: candidate.originRecordID).map(\.sourceID)),[x,y])
            _ = try authority.reconfigure(id: target.id,expectedGeneration: 1,connectorKind: .syndication,
                checkpoint: .preserve,authorizedSources: [y])
            XCTAssertEqual(Set(try content.memberships(originRecordID: candidate.originRecordID).map(\.sourceID)),[x,y])
        }
    }
    func testLookupAndRepeatedConstructionDoNotWriteAuthority() throws {
        let db = try database(), authority = AcquisitionTargetAuthority(database: db), x = SourceID()
        let target = try authority.register(id: AcquisitionTargetID(),connectorKind: .syndication,authorizedSources: [x])
        try db.write { db in
            try db.execute(sql: "CREATE TRIGGER forbid_authority_insert BEFORE INSERT ON acquisition_target_sources BEGIN SELECT RAISE(ABORT,'unexpected write'); END")
            try db.execute(sql: "CREATE TRIGGER forbid_authority_delete BEFORE DELETE ON acquisition_target_sources BEGIN SELECT RAISE(ABORT,'unexpected write'); END")
        }
        let snapshot = try Self.snapshot(db,Self.registration(target,sources: [x]))
        XCTAssertEqual(try snapshot.eligibleTargets(for: .init(request: .source(x))),[target])
        XCTAssertNotNil(snapshot.connector(for: target)); _ = snapshot.makeCoordinator()
        _ = try Self.snapshot(db,Self.registration(target,sources: [x]))
        XCTAssertEqual(try authority.target(id: target.id),target)
    }

    private func legacyDatabase() throws -> (RuntimeDatabaseLocation, AcquisitionTargetID, SourceID, OriginRecordID) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let location = RuntimeDatabaseLocation(directory: root), id = AcquisitionTargetID(), historicSource = SourceID(), historicOrigin = OriginRecordID()
        do {
            let db = try RuntimeDatabase(location: location)
            // Restore the exact preceding physical schema/history to model a populated upgrade fixture.
            // No authority grants or production registration API are used to fabricate a legacy target.
            try db.write { db in
                try db.execute(sql: "DROP TABLE acquisition_target_sources")
                try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'acquisition-target-sources-v1'")
                try db.execute(sql: "INSERT INTO acquisition_targets (id,connector_kind,generation,state,checkpoint_revision,checkpoint_blob,checkpoint_schema,checkpoint_connector_version) VALUES (?, 'syndication', 7, 'enabled', 2, ?, 1, 'legacy')",
                    arguments: [id.rawValue.uuidString.lowercased(),Data([1,2,3])])
                let origin = historicOrigin.rawValue.uuidString.lowercased()
                try db.execute(sql: "INSERT INTO origin_records (id,object_connector_kind,object_namespace,object_value,object_role,availability,first_observed_at,last_observed_at,availability_observed_at) VALUES (?, 'syndication', 'legacy', 'history', 'object', 'available', 100, 100, 100)",arguments: [origin])
                try db.execute(sql: "INSERT INTO source_memberships VALUES (?, ?, 'direct', 100, 100)",arguments: [origin,historicSource.rawValue.uuidString.lowercased()])
            }
        }
        return (location,id,historicSource,historicOrigin)
    }
    func testLegacySnapshotReconciliationPreservesCheckpointHistoryAndReopenIsIdempotent() throws {
        let (location,id,historicSource,historicOrigin) = try legacyDatabase(), trustedSource = SourceID()
        let db = try RuntimeDatabase(location: location), authority = AcquisitionTargetAuthority(database: db)
        let before = try XCTUnwrap(authority.target(id: id))
        XCTAssertNil(try authority.authorizedSources(id: id)) // Historical membership is not authorization.
        XCTAssertThrowsError(try AdmissionPolicy(database: db).admit(.init(targetID: id,targetGeneration: 7,
            expectedCheckpointRevision: 2,observations: [Self.observation(historicSource)],nextCheckpoint: nil)!))
        let configuration = Self.registration(before,sources: [trustedSource])
        let snapshot = try Self.snapshot(db,configuration)
        XCTAssertEqual(try snapshot.eligibleTargets(for: .init(request: .source(trustedSource))),[before])
        XCTAssertNotNil(snapshot.connector(for: before))
        XCTAssertEqual(try authority.target(id: id),before)
        XCTAssertEqual(try authority.authorizedSources(id: id),[trustedSource])
        XCTAssertEqual(before.checkpoint?.blob,Data([1,2,3])); XCTAssertEqual(before.checkpointRevision,2)
        let reopened = try RuntimeDatabase(location: location), reopenedAuthority = AcquisitionTargetAuthority(database: reopened)
        _ = try Self.snapshot(reopened,configuration)
        XCTAssertEqual(try reopenedAuthority.target(id: id),before)
        XCTAssertEqual(try reopenedAuthority.authorizedSources(id: id),[trustedSource])
        XCTAssertThrowsError(try Self.snapshot(reopened,Self.registration(before,sources: [historicSource])))
        XCTAssertEqual(try ContentStore(database: reopened).memberships(originRecordID: historicOrigin),[
            SourceMembership(originRecordID: historicOrigin,sourceID: historicSource,kind: .direct,
                firstObservedAt: Date(timeIntervalSince1970: 100),lastObservedAt: Date(timeIntervalSince1970: 100))
        ])
    }

    func testConcurrentLegacyMaterializationsIdenticalOrDivergentNeverUnionPermissions() async throws {
        for divergent in [false,true] {
            let (location,id,_,_) = try legacyDatabase(), db = try RuntimeDatabase(location: location)
            let authority = AcquisitionTargetAuthority(database: db), x = SourceID(), y = SourceID()
            let target = try XCTUnwrap(authority.target(id: id))
            let registrations = [Self.registration(target,sources: [x]),Self.registration(target,sources: [divergent ? y : x])]
            let successes = try await withThrowingTaskGroup(of: Bool.self) { group in
                for registration in registrations {
                    group.addTask {
                        do { _ = try Self.snapshot(db,registration); return true }
                        catch AcquisitionTargetStoreError.sourceConfigurationConflict { return false }
                    }
                }
                var values: [Bool] = []
                for try await value in group { values.append(value) }
                return values.filter { $0 }.count
            }
            XCTAssertEqual(successes,divergent ? 1 : 2)
            let sources = try XCTUnwrap(authority.authorizedSources(id: id))
            XCTAssertEqual(sources.count,1); XCTAssertTrue(sources == [x] || (divergent && sources == [y]))
            XCTAssertEqual(try authority.target(id: id),target)
        }
    }
    private struct ClaimConnector: FeedConnector {
        let observation: AcquisitionObservation
        func pull(_ request: FeedConnectorPull) async throws -> FeedConnectorEvent {
            .batch(.init(targetID: request.targetID,targetGeneration: request.targetGeneration,
                expectedCheckpointRevision: request.checkpointRevision,observations: [observation],nextCheckpoint: nil)!,transportByteCount: 0)
        }
    }
    func testCoordinatorDoesNotSettleUnauthorizedClaimAsOperationalFailure() async throws {
        let db = try database(), authority = AcquisitionTargetAuthority(database: db), x = SourceID(), y = SourceID()
        let target = try authority.register(id: AcquisitionTargetID(),connectorKind: .syndication,authorizedSources: [x])
        let connector = ClaimConnector(observation: Self.observation(y))
        let coordinator = AcquisitionCoordinator(database: db,connectorForTarget: { _ in connector })
        do {
            _ = try await coordinator.execute(.start(target: target,bounds: .init(batchCapacity: 1,observationCapacityPerBatch: 2,byteCapacityPerBatch: 512)!))
            XCTFail("Authority error must propagate")
        } catch {
            XCTAssertEqual(error as? AcquisitionAdmissionStoreError,.unauthorizedSource(index: 0,targetID: target.id,sourceID: y))
            XCTAssertFalse(error is ConnectorOperationalFailure)
        }
        XCTAssertEqual(try authority.target(id: target.id),target)
        XCTAssertTrue(try ContentStore(database: db).candidateWindow(sourceID: nil,after: nil,examinedCapacity: 10).records.isEmpty)
    }

}
