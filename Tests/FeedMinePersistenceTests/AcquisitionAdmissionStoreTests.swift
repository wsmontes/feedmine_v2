import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence

final class AcquisitionAdmissionStoreTests: XCTestCase {
    private typealias Store = AcquisitionAdmissionStore
    private struct Fixture: Sendable {
        let database: RuntimeDatabase
        let targetID: AcquisitionTargetID
        let sourceID: SourceID
        var store: Store { Store(database: database) }
        var targets: AcquisitionTargetStore { AcquisitionTargetStore(database: database) }
        var content: ContentStore { ContentStore(database: database) }
        func command(_ observations: [Store.ObservationCommand], generation: UInt64 = 1, revision: UInt64 = 0,
            checkpoint: AcquisitionTargetStore.CheckpointRecord? = nil) -> Store.BatchCommand {
            .init(targetID: targetID,targetGeneration: generation,expectedCheckpointRevision: revision,
                observations: observations,nextCheckpoint: checkpoint)
        }
        func snapshot(includeTarget: Bool = true, includeOrigin: Bool = true) throws -> [String] {
            try database.read { db in
                var result: [String] = []
                for table in ["origin_records","origin_revisions","source_memberships","selection_supply","media_candidates"] + (includeTarget ? ["acquisition_targets"] : []) {
                    if table == "origin_records" && !includeOrigin { continue }
                    result.append(table)
                    result += try Row.fetchAll(db,sql: "SELECT * FROM \(table) ORDER BY 1,2").map { String(describing: $0) }
                }
                return result
            }
        }
        func record(_ object: String = "object") throws -> OriginRecord? {
            try database.read { try content.admissionRecord(matching: AcquisitionAdmissionStoreTests.identity(object),in: $0) }
        }
        func revision(_ version: String, object: String = "object") throws -> OriginRevision? {
            guard let record = try record(object) else { return nil }
            return try database.read {
                try content.admissionRevision(originRecordID: record.id,matching: AcquisitionAdmissionStoreTests.identity(version,role: .version),in: $0)
            }
        }
        func current(_ object: String = "object") throws -> OriginRevision? {
            guard let record = try record(object) else { return nil }
            return try content.currentRevision(originRecordID: record.id)
        }
        func count(_ table: String) throws -> Int {
            try database.read { try Int.fetchOne($0,sql: "SELECT COUNT(*) FROM \(table)")! }
        }
    }
    private func location() -> RuntimeDatabaseLocation {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return RuntimeDatabaseLocation(directory: root)
    }
    private func fixture(at location: RuntimeDatabaseLocation? = nil, connector: String = "syndication") throws -> Fixture {
        let result = Fixture(database: try RuntimeDatabase(location: location ?? self.location()),targetID: AcquisitionTargetID(),sourceID: SourceID())
        _ = try result.targets.register(id: result.targetID,connectorKind: ConnectorKind(rawValue: connector))
        return result
    }
    private static func identity(_ value: String, role: ExternalIdentityRole = .object, connector: String = "syndication") -> ExternalIdentity {
        .init(connectorKind: ConnectorKind(rawValue: connector),namespace: " namespace ",value: value,role: role)
    }
    private func media(_ path: String = "one", mime: String? = " image/opaque ", width: Int? = 10, height: Int? = 20) -> Store.MediaCandidateCommand {
        .init(role: .cardVisual,mediaClass: .image,remoteURL: URL(string: "https://example.test/"+path)!,
            declaredMimeType: mime,declaredPixelWidth: width,declaredPixelHeight: height)!
    }
    private func observation(_ f: Fixture, object: String = "object", version: String? = "v1",
        objectIdentity: ExternalIdentity? = nil, versionIdentity: ExternalIdentity? = nil,
        precedence: Store.PrecedenceCommand = .makeCurrent, availability: OriginAvailability = .available,
        headline: String? = " headline ", summary: String? = " summary ", body: String? = " body ",
        authored: Date? = Date(timeIntervalSince1970: 5), modified: Date? = nil, time: Double = 10,
        language: String? = " PT ", link: URL? = URL(string: "https://example.test/Article?A=a"),
        search: String? = " search ", provider: ProviderID? = nil,
        memberships: [Store.MembershipCommand]? = nil, media: [Store.MediaCandidateCommand]? = nil) -> Store.ObservationCommand {
        .init(objectIdentity: objectIdentity ?? Self.identity(object),versionIdentity: versionIdentity ?? version.map { Self.identity($0,role: .version) },
            precedence: precedence,availability: availability,headline: headline,summary: summary,bodyText: body,
            authoredAt: authored,modifiedAt: modified,observedAt: Date(timeIntervalSince1970: time),language: language,
            primaryLink: link,searchProjection: search,providerID: provider,
            memberships: memberships ?? [.init(sourceID: f.sourceID,kind: .direct)],mediaCandidates: media ?? [self.media("one"),self.media("two")])
    }
    private func checkpoint() -> AcquisitionTargetStore.CheckpointRecord {
        .init(blob: Data([0,255,1]),serializationSchema: 2,connectorVersion: " V ")!
    }
    private func targetFailure(_ expected: AcquisitionTargetStoreError, _ work: () throws -> Void,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try work(),file: file,line: line) { XCTAssertEqual($0 as? AcquisitionTargetStoreError,expected,file: file,line: line) }
    }

    func testTargetFencesBeforeCanonicalWorkAndMissingTarget() throws {
        let f = try fixture(), observation = observation(f)
        let before = try f.snapshot()
        targetFailure(.staleGeneration(expected: 2,actual: 1)) { _ = try f.store.admit(f.command([observation],generation: 2,checkpoint: checkpoint())) }
        targetFailure(.staleCheckpoint(expected: 1,actual: 0)) { _ = try f.store.admit(f.command([observation],revision: 1,checkpoint: checkpoint())) }
        XCTAssertEqual(try f.snapshot(),before)
        let missing = AcquisitionTargetID()
        targetFailure(.missingTarget(missing)) {
            _ = try f.store.admit(.init(targetID: missing,targetGeneration: 1,expectedCheckpointRevision: 0,observations: [observation],nextCheckpoint: checkpoint()))
        }
        XCTAssertEqual(try f.snapshot(),before)
        _ = try f.targets.revoke(id: f.targetID,expectedGeneration: 1)
        let revoked = try f.snapshot()
        targetFailure(.targetRevoked(f.targetID)) { _ = try f.store.admit(f.command([observation],checkpoint: checkpoint())) }
        XCTAssertEqual(try f.snapshot(),revoked)
    }
    func testDefensiveObservationValidationAndExactConnectorFence() throws {
        let f = try fixture(), before = try f.snapshot()
        let invalid: [(Store.ObservationCommand,AcquisitionAdmissionStoreError)] = [
            (observation(f,objectIdentity: Self.identity("o",role: .alias)),.invalidObservation(index: 0,field: "objectIdentity.role")),
            (observation(f,objectIdentity: Self.identity("o",connector: "")),.invalidObservation(index: 0,field: "objectIdentity.connectorKind")),
            (observation(f,objectIdentity: Self.identity("o",connector: "SYNDICATION")),.connectorMismatch(index: 0)),
            (observation(f,versionIdentity: Self.identity("v",role: .object)),.invalidObservation(index: 0,field: "versionIdentity.role")),
            (observation(f,versionIdentity: Self.identity("v",role: .version,connector: "other")),.invalidObservation(index: 0,field: "versionIdentity.connectorKind")),
            (observation(f,version: nil,precedence: .historicalOnly),.unsupportedUnversionedHistorical(index: 0)),
            (observation(f,time: .nan),.invalidObservation(index: 0,field: "observedAt")),
            (observation(f,authored: Date(timeIntervalSince1970: .infinity)),.invalidObservation(index: 0,field: "authoredAt")),
            (observation(f,modified: Date(timeIntervalSince1970: -.infinity)),.invalidObservation(index: 0,field: "modifiedAt")),
            (observation(f,memberships: [.init(sourceID: f.sourceID,kind: .direct),.init(sourceID: f.sourceID,kind: .derived)]),.invalidObservation(index: 0,field: "memberships"))
        ]
        for (value,error) in invalid {
            XCTAssertThrowsError(try f.store.admit(f.command([value],checkpoint: checkpoint()))) { XCTAssertEqual($0 as? AcquisitionAdmissionStoreError,error) }
            XCTAssertEqual(try f.snapshot(),before)
        }
        let unicode = try fixture(connector: "é")
        XCTAssertThrowsError(try unicode.store.admit(unicode.command([observation(unicode,objectIdentity: Self.identity("o",connector: "e\u{301}"))]))) {
            XCTAssertEqual($0 as? AcquisitionAdmissionStoreError,.connectorMismatch(index: 0))
        }
        // Preflight the entire command before applying observation 0.
        XCTAssertThrowsError(try f.store.admit(f.command([observation(f),observation(f,objectIdentity: Self.identity("o",connector: "other"))]))) {
            XCTAssertEqual($0 as? AcquisitionAdmissionStoreError,.connectorMismatch(index: 1))
        }
        XCTAssertEqual(try f.snapshot(),before)
    }
    func testMechanicalMediaStructuralValidation() {
        for url in ["file:///a","relative","https:/missing","ftp://example.test/a"] {
            XCTAssertNil(Store.MediaCandidateCommand(role: .cardVisual,mediaClass: .image,remoteURL: URL(string: url)!,declaredMimeType: nil,declaredPixelWidth: nil,declaredPixelHeight: nil))
        }
        for pair: (Int?,Int?) in [(0,1),(1,0),(-1,2),(nil,2),(2,nil)] {
            XCTAssertNil(Store.MediaCandidateCommand(role: .cardVisual,mediaClass: .image,remoteURL: URL(string: "https://example.test/a")!,declaredMimeType: nil,declaredPixelWidth: pair.0,declaredPixelHeight: pair.1))
        }
    }
    func testVersionedReplayPreservesIdentityAndImmutableTime() throws {
        let f = try fixture()
        XCTAssertTrue(try f.store.admit(f.command([observation(f)])).selectableSupplyChanged)
        let record = try XCTUnwrap(f.record()), revision = try XCTUnwrap(f.current())
        let media = try XCTUnwrap(f.content.mediaCandidates(originRevisionID: revision.id))
        let receipt = try f.store.admit(f.command([observation(f,time: 20)]))
        XCTAssertFalse(receipt.checkpointAdvanced); XCTAssertFalse(receipt.selectableSupplyChanged)
        XCTAssertTrue(receipt.rejectedObservations.isEmpty)
        XCTAssertEqual(try f.current(),revision); XCTAssertEqual(try f.record()?.id,record.id)
        XCTAssertEqual(try f.content.mediaCandidates(originRevisionID: revision.id),media)
        XCTAssertEqual(try f.record()?.lastObservedAt,Date(timeIntervalSince1970: 20))
        XCTAssertEqual(try f.content.memberships(originRecordID: record.id).first?.lastObservedAt,Date(timeIntervalSince1970: 20))
        XCTAssertEqual(try f.count("origin_records"),1); XCTAssertEqual(try f.count("origin_revisions"),1); XCTAssertEqual(try f.count("media_candidates"),2)
        XCTAssertNil(try f.targets.target(id: f.targetID)?.checkpoint); XCTAssertEqual(try f.targets.target(id: f.targetID)?.checkpointRevision,0)
    }
    func testOpaqueObjectAndVersionTuplesRemainByteDistinct() throws {
        let f = try fixture()
        _ = try f.store.admit(f.command([observation(f,object: "é",version: "é"),observation(f,object: "e\u{301}",version: "e\u{301}")]))
        let a = try XCTUnwrap(f.record("é")), b = try XCTUnwrap(f.record("e\u{301}"))
        XCTAssertNotEqual(a.id,b.id)
        _ = try f.store.admit(f.command([observation(f,object: "é",version: "e\u{301}")]))
        XCTAssertEqual(try f.count("origin_records"),2); XCTAssertEqual(try f.count("origin_revisions"),3)
        XCTAssertNotEqual(try f.revision("é",object: "é")?.id,try f.revision("e\u{301}",object: "é")?.id)
    }
    func testKnownVersionPayloadConflictsRejectOnlyObservationAndAdvanceCheckpoint() throws {
        let f = try fixture()
        _ = try f.store.admit(f.command([observation(f)]))
        let before = try f.snapshot(includeTarget: false)
        let values = [observation(f,headline: "changed"),observation(f,summary: "changed"),observation(f,body: "changed"),
            observation(f,authored: nil),observation(f,modified: Date(timeIntervalSince1970: 2)),observation(f,language: "pt"),
            observation(f,link: URL(string: "https://example.test/other")),observation(f,search: "changed"),observation(f,provider: ProviderID())]
        for (index, value) in values.enumerated() {
            let receipt = try f.store.admit(f.command([value],revision: UInt64(index),checkpoint: checkpoint()))
            XCTAssertTrue(receipt.checkpointAdvanced)
            XCTAssertFalse(receipt.selectableSupplyChanged)
            XCTAssertEqual(receipt.rejectedObservations, [.init(index: 0, reason: .knownVersionPayloadConflict)])
            XCTAssertEqual(try f.targets.target(id: f.targetID)?.checkpointRevision, UInt64(index + 1))
            XCTAssertEqual(try f.snapshot(includeTarget: false),before)
        }
    }
    func testKnownVersionMediaConflictsRejectCompleteOrderedCollectionWithoutMutation() throws {
        let f = try fixture()
        _ = try f.store.admit(f.command([observation(f)]))
        let before = try f.snapshot(includeTarget: false)
        let collections = [
            [media("changed"),media("two")],
            [media("one",mime: "IMAGE/opaque"),media("two")],
            [media("one",width: 11,height: 20),media("two")],
            [media("one"),media("two"),media("three")],
            [media("one")],
            [media("two"),media("one")],
            []
        ]
        for (index, collection) in collections.enumerated() {
            let receipt = try f.store.admit(f.command([observation(f,media: collection)],revision: UInt64(index),checkpoint: checkpoint()))
            XCTAssertEqual(receipt.rejectedObservations, [.init(index: 0, reason: .knownVersionMediaConflict)])
            XCTAssertTrue(receipt.checkpointAdvanced)
            XCTAssertFalse(receipt.selectableSupplyChanged)
            XCTAssertEqual(try f.snapshot(includeTarget: false),before)
            XCTAssertEqual(try f.targets.target(id: f.targetID)?.checkpointRevision, UInt64(index + 1))
        }
    }
    func testNewVersionHistoricalInsertionAndOldReplayNeverRollBackCurrent() throws {
        let f = try fixture()
        _ = try f.store.admit(f.command([observation(f)]))
        let v1 = try XCTUnwrap(f.current())
        XCTAssertTrue(try f.store.admit(f.command([observation(f,version: "v2",time: 20)])).selectableSupplyChanged)
        let v2 = try XCTUnwrap(f.current())
        XCTAssertNotEqual(v1.id,v2.id); XCTAssertEqual(try f.content.originRevision(id: v1.id),v1)
        XCTAssertFalse(try f.store.admit(f.command([observation(f,version: "older-opaque",precedence: .historicalOnly,time: 30)])).selectableSupplyChanged)
        let old = try XCTUnwrap(f.revision("older-opaque"))
        XCTAssertEqual(try f.current(),v2)
        XCTAssertFalse(try f.store.admit(f.command([observation(f,version: "older-opaque",time: 40)])).selectableSupplyChanged)
        XCTAssertEqual(try f.current(),v2); XCTAssertEqual(try f.revision("older-opaque"),old)
        XCTAssertFalse(try f.store.admit(f.command([observation(f,time: 50)])).selectableSupplyChanged)
        XCTAssertEqual(try f.current(),v2)
        XCTAssertEqual(try f.content.candidateWindow(sourceID: nil,after: nil,examinedCapacity: 10).records.map(\.originRevisionID),[v2.id])
        XCTAssertEqual(try f.count("origin_revisions"),3)
    }
    func testKnownHistoricalVersionPromotesOnlyWhenNoCurrent() throws {
        let f = try fixture()
        XCTAssertFalse(try f.store.admit(f.command([observation(f,precedence: .historicalOnly)])).selectableSupplyChanged)
        let historical = try XCTUnwrap(f.revision("v1"))
        XCTAssertNil(try f.current()); XCTAssertEqual(try f.count("selection_supply"),0)
        XCTAssertTrue(try f.store.admit(f.command([observation(f,time: 20)])).selectableSupplyChanged)
        XCTAssertEqual(try f.current(),historical); XCTAssertEqual(try f.count("origin_revisions"),1)
    }
    func testUnversionedReplayAndByteExactPayloadChange() throws {
        let f = try fixture()
        _ = try f.store.admit(f.command([observation(f,version: nil,headline: "é")]))
        let a = try XCTUnwrap(f.current()), aMedia = try XCTUnwrap(f.content.mediaCandidates(originRevisionID: a.id))
        XCTAssertFalse(try f.store.admit(f.command([observation(f,version: nil,headline: "é",time: 20)])).selectableSupplyChanged)
        XCTAssertEqual(try f.current(),a); XCTAssertEqual(try f.content.mediaCandidates(originRevisionID: a.id),aMedia)
        XCTAssertEqual(try f.record()?.lastObservedAt,Date(timeIntervalSince1970: 20))
        XCTAssertTrue(try f.store.admit(f.command([observation(f,version: nil,headline: "e\u{301}",time: 30)])).selectableSupplyChanged)
        let b = try XCTUnwrap(f.current())
        XCTAssertNotEqual(a.id,b.id); XCTAssertNil(b.externalVersionIdentity)
        XCTAssertEqual(try f.content.originRevision(id: a.id),a)
        XCTAssertNotEqual(try f.content.mediaCandidates(originRevisionID: b.id)?.map(\.id),aMedia.map(\.id))
        XCTAssertFalse(try f.store.admit(f.command([observation(f,version: nil,headline: "e\u{301}",time: 40)])).selectableSupplyChanged)
        XCTAssertEqual(try f.current(),b); XCTAssertEqual(try f.count("origin_revisions"),2)
    }
    func testUnversionedMediaChangesCreateRevisionsIncludingOrderAndCollectionSize() throws {
        let f = try fixture()
        _ = try f.store.admit(f.command([observation(f,version: nil)]))
        for collection in [[media("one",mime: "changed"),media("two")],[media("one",width: 11,height: 20),media("two")],
            [media("two"),media("one")],[media("one")],[media("one"),media("two"),media("three")]] {
            let before = try XCTUnwrap(f.current())
            XCTAssertTrue(try f.store.admit(f.command([observation(f,version: nil,media: collection)])).selectableSupplyChanged)
            let after = try XCTUnwrap(f.current())
            XCTAssertNotEqual(after.id,before.id); XCTAssertNil(after.externalVersionIdentity)
            XCTAssertEqual(try f.content.originRevision(id: before.id),before)
            XCTAssertFalse(try f.store.admit(f.command([observation(f,version: nil,time: 20,media: collection)])).selectableSupplyChanged)
            XCTAssertEqual(try f.current(),after)
        }
        XCTAssertEqual(try f.count("origin_revisions"),6)
    }
    func testVersionedCurrentFollowedByUnversionedAlwaysCreatesDistinctRevision() throws {
        let f = try fixture()
        _ = try f.store.admit(f.command([observation(f)]))
        let versioned = try XCTUnwrap(f.current())
        XCTAssertTrue(try f.store.admit(f.command([observation(f,version: nil)])).selectableSupplyChanged)
        let unversioned = try XCTUnwrap(f.current())
        XCTAssertNotEqual(versioned.id,unversioned.id); XCTAssertNil(unversioned.externalVersionIdentity)
        XCTAssertEqual(try f.content.originRevision(id: versioned.id),versioned)
    }
    func testMixedBatchOriginalIndicesReasonsAndValidAdmissionOrder() throws {
        let f = try fixture()
        _ = try f.store.admit(f.command([observation(f,object: "B"),observation(f,object: "D")]))
        let b = try XCTUnwrap(f.current("B")), d = try XCTUnwrap(f.current("D"))
        let receipt = try f.store.admit(f.command([
            observation(f,object: "A",version: "v1"),
            observation(f,object: "B",summary: "conflicting",time: 20),
            observation(f,object: "C"),
            observation(f,object: "D",time: 20,media: []),
            observation(f,object: "A",version: "v2",headline: "latest valid",time: 30)
        ],checkpoint: checkpoint()))
        XCTAssertEqual(receipt.rejectedObservations, [
            .init(index: 1, reason: .knownVersionPayloadConflict),
            .init(index: 3, reason: .knownVersionMediaConflict)
        ])
        XCTAssertTrue(receipt.checkpointAdvanced); XCTAssertTrue(receipt.selectableSupplyChanged)
        XCTAssertNotNil(try f.record("A")); XCTAssertNotNil(try f.record("C"))
        XCTAssertEqual(try f.current("A")?.externalVersionIdentity, Self.identity("v2",role: .version))
        XCTAssertEqual(try f.current("A")?.headline, "latest valid")
        XCTAssertEqual(try f.current("B"), b); XCTAssertEqual(try f.current("D"), d)
        XCTAssertEqual(try f.count("origin_records"),4)
        XCTAssertEqual(try f.count("origin_revisions"),5)
        XCTAssertEqual(try f.targets.target(id: f.targetID)?.checkpointRevision,1)
    }

    func testAllRejectedPreserveRevisionAndMembershipApplyAvailabilityAndAdvanceCheckpoint() throws {
        let f = try fixture()
        _ = try f.store.admit(f.command([observation(f)]))
        let before = try f.snapshot(includeTarget: false,includeOrigin: false)
        let origin = try XCTUnwrap(f.record())
        let receipt = try f.store.admit(f.command([
            observation(f,availability: .removed,summary: "changed",time: 20,
                memberships: [.init(sourceID: SourceID(),kind: .derived)]),
            observation(f,availability: .updated,time: 30,memberships: [],media: [])
        ],checkpoint: checkpoint()))
        XCTAssertEqual(receipt.rejectedObservations, [
            .init(index: 0,reason: .knownVersionPayloadConflict),
            .init(index: 1,reason: .knownVersionMediaConflict)
        ])
        XCTAssertFalse(receipt.selectableSupplyChanged); XCTAssertTrue(receipt.checkpointAdvanced)
        XCTAssertEqual(try f.snapshot(includeTarget: false,includeOrigin: false),before)
        XCTAssertEqual(try f.record(),OriginRecord(id: origin.id,externalObjectIdentity: origin.externalObjectIdentity,
            currentRevisionID: origin.currentRevisionID,availability: .updated,
            firstObservedAt: origin.firstObservedAt,lastObservedAt: origin.lastObservedAt))
        XCTAssertEqual(try f.database.read { try Double.fetchOne($0,sql: "SELECT availability_observed_at FROM origin_records") },30)
        XCTAssertEqual(try f.targets.target(id: f.targetID)?.checkpointRevision,1)
        XCTAssertEqual(try f.targets.target(id: f.targetID)?.checkpoint,checkpoint())
    }

    func testStoredMediaCorruptionIsFatalEvenWithConflictingPayload() throws {
        let f = try fixture()
        _ = try f.store.admit(f.command([observation(f)]))
        try f.database.write { try $0.execute(sql: "UPDATE media_candidates SET ordinal = 9 WHERE ordinal = 0") }
        let before = try f.snapshot()
        XCTAssertThrowsError(try f.store.admit(f.command([
            observation(f,object: "valid"),observation(f,summary: "changed")
        ],checkpoint: checkpoint()))) {
            XCTAssertEqual($0 as? ContentStoreError,.corruption("media candidate ordinal"))
        }
        XCTAssertEqual(try f.snapshot(),before)
        XCTAssertNil(try f.record("valid"))
    }

    func testRejectedObservationDoesNotBypassFatalTargetFences() throws {
        let f = try fixture()
        _ = try f.store.admit(f.command([observation(f)]))
        let before = try f.snapshot()
        let values = [observation(f,summary: "poison"),observation(f,object: "valid")]
        targetFailure(.staleGeneration(expected: 2,actual: 1)) {
            _ = try f.store.admit(f.command(values,generation: 2,checkpoint: checkpoint()))
        }
        targetFailure(.staleCheckpoint(expected: 1,actual: 0)) {
            _ = try f.store.admit(f.command(values,revision: 1,checkpoint: checkpoint()))
        }
        XCTAssertEqual(try f.snapshot(),before)
    }

    func testLaterMediaStorageFailureRollsBackEntireBatchWithoutProductionHook() throws {
        let f = try fixture()
        _ = try f.store.admit(f.command([observation(f,object: "poison")]))
        try f.database.write { db in
            try db.execute(sql: """
                CREATE TRIGGER reject_later_media BEFORE INSERT ON media_candidates
                WHEN NEW.remote_locator = 'https://example.test/abort'
                BEGIN SELECT RAISE(ABORT, 'test media storage failure'); END
                """)
        }
        let before = try f.snapshot()
        XCTAssertThrowsError(try f.store.admit(f.command([observation(f,object: "poison",summary: "conflict"),observation(f,object: "A"),observation(f,object: "B",media: [media("abort")])],checkpoint: checkpoint()))) {
            guard case .storage(let code,_) = $0 as? RuntimeDatabaseError else { return XCTFail("Expected storage error, got \($0)") }
            XCTAssertEqual(code & 0xff,19)
        }
        XCTAssertEqual(try f.snapshot(),before); XCTAssertNil(try f.record("A")); XCTAssertNil(try f.record("B"))
    }
    func testContentAndCheckpointPersistTogetherAndLostReceiptIsFenced() throws {
        let location = location()
        let target: AcquisitionTargetStore.TargetRecord, canonical: [String], id: AcquisitionTargetID
        do {
            let f = try fixture(at: location); id = f.targetID
            let command = f.command([observation(f)],checkpoint: checkpoint())
            let receipt = try f.store.admit(command)
            XCTAssertEqual(receipt.targetID,id); XCTAssertTrue(receipt.checkpointAdvanced); XCTAssertTrue(receipt.selectableSupplyChanged)
            target = try XCTUnwrap(f.targets.target(id: id)); canonical = try f.snapshot()
            XCTAssertEqual(target.generation,1); XCTAssertEqual(target.checkpointRevision,1); XCTAssertEqual(target.checkpoint,checkpoint())
            targetFailure(.staleCheckpoint(expected: 0,actual: 1)) { _ = try f.store.admit(command) }
            XCTAssertEqual(try f.snapshot(),canonical)
        }
        let reopened = Fixture(database: try RuntimeDatabase(location: location),targetID: id,sourceID: SourceID())
        XCTAssertEqual(try reopened.targets.target(id: id),target); XCTAssertEqual(try reopened.snapshot(),canonical)
        XCTAssertEqual(try reopened.count("origin_records"),1); XCTAssertEqual(try reopened.count("origin_revisions"),1)
        XCTAssertEqual(try reopened.count("selection_supply"),1)
    }
    func testCheckpointOnlyAndIdenticalCheckpointAlwaysAdvanceWithoutCanonicalChange() throws {
        let f = try fixture(), before = try f.snapshot(includeTarget: false)
        for revision in UInt64(0)...1 {
            let receipt = try f.store.admit(f.command([],revision: revision,checkpoint: checkpoint()))
            XCTAssertTrue(receipt.checkpointAdvanced); XCTAssertFalse(receipt.selectableSupplyChanged)
            XCTAssertEqual(try f.targets.target(id: f.targetID)?.checkpointRevision,revision+1)
            XCTAssertEqual(try f.targets.target(id: f.targetID)?.checkpoint,checkpoint())
            XCTAssertEqual(try f.snapshot(includeTarget: false),before)
        }
    }
    func testCheckpointOverflowRollsBackNewCanonicalContent() throws {
        let f = try fixture()
        try f.database.write { try $0.execute(sql: "UPDATE acquisition_targets SET checkpoint_revision=?",arguments: [Int64.max]) }
        let before = try f.snapshot()
        targetFailure(.checkpointRevisionExhausted(f.targetID)) {
            _ = try f.store.admit(f.command([observation(f)],revision: UInt64(Int64.max),checkpoint: checkpoint()))
        }
        XCTAssertEqual(try f.snapshot(),before); XCTAssertNil(try f.record())
    }
    func testSelectableReceiptTracksSourceSetNotObservationOrMembershipKind() throws {
        let f = try fixture(), secondSource = SourceID()
        _ = try f.store.admit(f.command([observation(f)]))
        XCTAssertFalse(try f.store.admit(f.command([observation(f,time: 20)])).selectableSupplyChanged)
        XCTAssertFalse(try f.store.admit(f.command([observation(f,time: 30,memberships: [.init(sourceID: f.sourceID,kind: .derived)])])).selectableSupplyChanged)
        let record = try XCTUnwrap(f.record())
        XCTAssertEqual(try f.content.memberships(originRecordID: record.id).first?.kind,.derived)
        XCTAssertTrue(try f.store.admit(f.command([observation(f,time: 40,memberships: [.init(sourceID: secondSource,kind: .direct)])])).selectableSupplyChanged)
        XCTAssertEqual(Set(try f.content.memberships(originRecordID: record.id).map(\.sourceID)),[f.sourceID,secondSource])
        XCTAssertEqual(try f.content.candidateWindow(sourceID: secondSource,after: nil,examinedCapacity: 10).records.count,1)
        XCTAssertFalse(try f.store.admit(f.command([observation(f,version: "historical",precedence: .historicalOnly,time: 50)])).selectableSupplyChanged)
    }
    func testAvailabilityRemovalAndNonSelectableMembershipChanges() throws {
        let f = try fixture()
        _ = try f.store.admit(f.command([observation(f)]))
        let revision = try XCTUnwrap(f.current())
        XCTAssertTrue(try f.store.admit(f.command([observation(f,availability: .removed,time: 20)])).selectableSupplyChanged)
        XCTAssertEqual(try f.count("selection_supply"),0); XCTAssertEqual(try f.current(),revision)
        XCTAssertFalse(try f.store.admit(f.command([observation(f,availability: .removed,time: 30,memberships: [.init(sourceID: SourceID(),kind: .direct)])])).selectableSupplyChanged)
        XCTAssertEqual(try f.count("origin_revisions"),1)
    }
    func testFingerprintCapturedOnceAndComparedAfterAllObservations() throws {
        let f = try fixture()
        _ = try f.store.admit(f.command([observation(f)]))
        // Intermediate projection disappears then returns; final candidate-visible facts are identical.
        XCTAssertFalse(try f.store.admit(f.command([observation(f,availability: .removed,time: 20),observation(f,time: 30)])).selectableSupplyChanged)
        XCTAssertEqual(try f.count("origin_revisions"),1); XCTAssertEqual(try f.count("selection_supply"),1)
        let empty = try fixture()
        XCTAssertFalse(try empty.store.admit(empty.command([observation(empty,version: nil,memberships: [])])).selectableSupplyChanged)
        XCTAssertEqual(try empty.count("selection_supply"),0)
        XCTAssertTrue(try empty.store.admit(empty.command([observation(empty,version: nil,time: 20)])).selectableSupplyChanged)
    }
    func testSchemaAndMigrationHistoryRemainIdenticalAcrossAdmission() throws {
        let f = try fixture()
        func schema() throws -> [String] {
            try f.database.read { db in
                try Row.fetchAll(db,sql: "SELECT type,name,tbl_name,sql FROM sqlite_schema ORDER BY type,name").map { String(describing: $0) }
                + String.fetchAll(db,sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid")
            }
        }
        let before = try schema()
        _ = try f.store.admit(f.command([observation(f)],checkpoint: checkpoint()))
        XCTAssertEqual(try schema(),before)
    }
}
