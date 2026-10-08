import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineAcquisition

final class AdmissionPolicyTests: XCTestCase {
    private func location() -> RuntimeDatabaseLocation {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return RuntimeDatabaseLocation(directory: root)
    }
    private let source = SourceID(), provider = ProviderID()
    private func identity(_ value: String = " Opaque ", role: ExternalIdentityRole = .object,
        connector: String = "syndication") -> ExternalIdentity {
        ExternalIdentity(connectorKind: ConnectorKind(rawValue: connector),namespace: " NAMESPACE ",value: value,role: role)
    }
    private func media(_ path: String) -> AcquisitionMediaCandidateClaim {
        AcquisitionMediaCandidateClaim(role: .cardVisual,mediaClass: .image,remoteURL: URL(string: "https://example.test/"+path)!,
            declaredMimeType: " IMAGE/opaque ",declaredPixelWidth: 10,declaredPixelHeight: 20)!
    }
    private func observation(object: ExternalIdentity? = nil, version: ExternalIdentity? = nil,
        precedence: AcquisitionPrecedence = .makeCurrent, headline: String = " e\u{301} ", time: Double = 10,
        authored: Date? = nil, modified: Date? = nil, memberships: [AcquisitionMembershipClaim]? = nil) -> AcquisitionObservation? {
        AcquisitionObservation(objectIdentity: object ?? identity(),versionIdentity: version,precedence: precedence,
            availability: .available,headline: headline,summary: " Summary ",bodyText: " Body ",authoredAt: authored,
            modifiedAt: modified,observedAt: Date(timeIntervalSince1970: time),language: " PT ",
            primaryLink: URL(string: "https://example.test/Article?Case=A"),searchProjection: " Search ",providerID: provider,
            memberships: memberships ?? [.init(sourceID: source,kind: .direct)],mediaCandidates: [media("B"),media("A")])
    }
    private func batch(_ id: AcquisitionTargetID, _ observations: [AcquisitionObservation], revision: UInt64 = 0,
        checkpoint: AcquisitionCheckpoint? = nil, generation: UInt64 = 1) -> AcquisitionBatch? {
        AcquisitionBatch(targetID: id,targetGeneration: generation,expectedCheckpointRevision: revision,
            observations: observations,nextCheckpoint: checkpoint)
    }
    func testStructuralValidationAndOpaqueValues() {
        XCTAssertNil(observation(object: identity(role: .alias)))
        XCTAssertNil(observation(object: identity(connector: "")))
        XCTAssertNil(observation(version: identity("v",role: .object)))
        XCTAssertNil(observation(version: identity("v",role: .version,connector: "SYNDICATION")))
        // Swift String equality regards these as equal; the boundary must compare UTF-8 bytes.
        XCTAssertNil(observation(object: identity(connector: "é"),version: identity("v",role: .version,connector: "e\u{301}")))
        XCTAssertNil(observation(time: .infinity)); XCTAssertNil(observation(time: .nan))
        XCTAssertNil(observation(authored: Date(timeIntervalSince1970: -.infinity)))
        XCTAssertNil(observation(modified: Date(timeIntervalSince1970: .nan)))
        XCTAssertNil(observation(memberships: [.init(sourceID: source,kind: .direct),.init(sourceID: source,kind: .derived)]))
        let value = observation()!
        XCTAssertEqual(Array(value.objectIdentity.value.utf8),Array(" Opaque ".utf8))
        XCTAssertEqual(value.objectIdentity.namespace," NAMESPACE ")
        XCTAssertEqual(Array(value.headline!.utf8),Array(" e\u{301} ".utf8))
        for url in ["file:///a","relative","https:/missing","ftp://example.test/a"] {
            XCTAssertNil(AcquisitionMediaCandidateClaim(role: .cardVisual,mediaClass: .image,remoteURL: URL(string: url)!,
                declaredMimeType: nil,declaredPixelWidth: nil,declaredPixelHeight: nil))
        }
        for pair: (Int?,Int?) in [(0,1),(1,0),(-1,2),(nil,2),(2,nil)] {
            XCTAssertNil(AcquisitionMediaCandidateClaim(role: .cardVisual,mediaClass: .image,remoteURL: URL(string: "https://example.test/a")!,
                declaredMimeType: nil,declaredPixelWidth: pair.0,declaredPixelHeight: pair.1))
        }
        XCTAssertNotNil(AcquisitionMediaCandidateClaim(role: .cardVisual,mediaClass: .image,remoteURL: URL(string: "http://example.test/a")!,
            declaredMimeType: nil,declaredPixelWidth: nil,declaredPixelHeight: nil))
    }
    func testBatchValidationAndHistoricalRefusalWithoutMutation() throws {
        let db = try RuntimeDatabase(location: location()), id = AcquisitionTargetID()
        let authority = AcquisitionTargetAuthority(database: db)
        let before = try authority.register(id: id,connectorKind: .syndication)
        let checkpoint = AcquisitionCheckpoint(blob: Data(),serializationSchema: 1,connectorVersion: "v")!
        XCTAssertNil(batch(id,[],generation: 0)); XCTAssertNil(batch(id,[]))
        XCTAssertNotNil(batch(id,[],checkpoint: checkpoint)); XCTAssertNotNil(batch(id,[observation()!]))
        XCTAssertNotNil(batch(id,[observation()!],checkpoint: checkpoint))
        let historical = observation(precedence: .historicalOnly)!
        XCTAssertThrowsError(try AdmissionPolicy(database: db).admit(batch(id,[historical],checkpoint: checkpoint)!)) {
            XCTAssertEqual($0 as? AdmissionPolicyError,.unsupportedUnversionedHistorical(index: 0))
        }
        XCTAssertEqual(try authority.target(id: id),before)
        XCTAssertTrue(try ContentStore(database: db).candidateWindow(sourceID: nil,after: nil,examinedCapacity: 10).records.isEmpty)
    }
    func testVersionedSemanticMappingReplayAndDurableCheckpoint() throws {
        let location = location(), id = AcquisitionTargetID()
        let revision: OriginRevision, candidates: [MediaCandidate], origin: OriginRecord
        let checkpoint = AcquisitionCheckpoint(blob: Data([0,255]),serializationSchema: 2,connectorVersion: " V ")!
        do {
            let db = try RuntimeDatabase(location: location), authority = AcquisitionTargetAuthority(database: db)
            _ = try authority.register(id: id,connectorKind: .syndication)
            let policy = AdmissionPolicy(database: db), content = ContentStore(database: db)
            let first = try policy.admit(batch(id,[observation(version: identity(" V1 ",role: .version))!],checkpoint: checkpoint)!)
            XCTAssertEqual(first.targetID,id); XCTAssertTrue(first.checkpointAdvanced); XCTAssertTrue(first.selectableSupplyChanged)
            let window = try content.candidateWindow(sourceID: source,after: nil,examinedCapacity: 10)
            XCTAssertEqual(window.records.count,1)
            origin = try XCTUnwrap(content.originRecord(id: window.records[0].originRecordID))
            revision = try XCTUnwrap(content.currentRevision(originRecordID: origin.id))
            candidates = try XCTUnwrap(content.mediaCandidates(originRevisionID: revision.id))
            XCTAssertEqual(revision.providerID,provider); XCTAssertEqual(revision.summary," Summary ")
            XCTAssertEqual(revision.bodyText," Body "); XCTAssertEqual(revision.searchProjection," Search ")
            XCTAssertNil(revision.authoredAt); XCTAssertNil(revision.modifiedAt)
            XCTAssertEqual(revision.language," PT "); XCTAssertEqual(revision.primaryLink?.absoluteString,"https://example.test/Article?Case=A")
            XCTAssertEqual(origin.externalObjectIdentity,identity()); XCTAssertEqual(revision.externalVersionIdentity,identity(" V1 ",role: .version))
            XCTAssertEqual(candidates.map(\.remoteURL.absoluteString),["https://example.test/B","https://example.test/A"])
            XCTAssertEqual(candidates.map(\.declaredMimeType),[" IMAGE/opaque "," IMAGE/opaque "])
            XCTAssertEqual(candidates.map(\.declaredPixelWidth),[10,10]); XCTAssertEqual(candidates.map(\.declaredPixelHeight),[20,20])
            let replay = try policy.admit(batch(id,[observation(version: identity(" V1 ",role: .version),time: 20)!],revision: 1)!)
            XCTAssertFalse(replay.checkpointAdvanced); XCTAssertFalse(replay.selectableSupplyChanged)
            XCTAssertEqual(try content.currentRevision(originRecordID: origin.id),revision)
            XCTAssertEqual(try content.mediaCandidates(originRevisionID: revision.id),candidates)
            XCTAssertEqual(try content.originRecord(id: origin.id)?.lastObservedAt,Date(timeIntervalSince1970: 20))
            let memberships = try content.memberships(originRecordID: origin.id)
            XCTAssertEqual(memberships.count,1); XCTAssertEqual(memberships[0].sourceID,source); XCTAssertEqual(memberships[0].kind,.direct)
            XCTAssertEqual(memberships[0].firstObservedAt,Date(timeIntervalSince1970: 10)); XCTAssertEqual(memberships[0].lastObservedAt,Date(timeIntervalSince1970: 20))
        }
        let db = try RuntimeDatabase(location: location), content = ContentStore(database: db)
        XCTAssertEqual(try content.currentRevision(originRecordID: origin.id),revision)
        XCTAssertEqual(try content.mediaCandidates(originRevisionID: revision.id),candidates)
        let target = try AcquisitionTargetAuthority(database: db).target(id: id)
        XCTAssertEqual(target?.checkpoint,checkpoint); XCTAssertEqual(target?.checkpointRevision,1); XCTAssertEqual(target?.generation,1)
        XCTAssertEqual(try content.candidateWindow(sourceID: source,after: nil,examinedCapacity: 10).records.map(\.originRevisionID),[revision.id])
    }
    func testUnversionedChangeAndExactCurrentReplay() throws {
        let db = try RuntimeDatabase(location: location()), id = AcquisitionTargetID()
        _ = try AcquisitionTargetAuthority(database: db).register(id: id,connectorKind: .syndication)
        let policy = AdmissionPolicy(database: db), content = ContentStore(database: db)
        _ = try policy.admit(batch(id,[observation(headline: "A")!])!)
        let origin = try content.candidateWindow(sourceID: nil,after: nil,examinedCapacity: 10).records[0].originRecordID
        let a = try XCTUnwrap(content.currentRevision(originRecordID: origin))
        let mediaA = try XCTUnwrap(content.mediaCandidates(originRevisionID: a.id))
        XCTAssertTrue(try policy.admit(batch(id,[observation(headline: "B",time: 20)!])!).selectableSupplyChanged)
        let b = try XCTUnwrap(content.currentRevision(originRecordID: origin))
        XCTAssertNotEqual(a.id,b.id); XCTAssertNil(b.externalVersionIdentity)
        XCTAssertEqual(try content.originRevision(id: a.id),a)
        XCTAssertNotEqual(try content.mediaCandidates(originRevisionID: b.id)?.map(\.id),mediaA.map(\.id))
        XCTAssertFalse(try policy.admit(batch(id,[observation(headline: "B",time: 30)!])!).selectableSupplyChanged)
        XCTAssertEqual(try content.currentRevision(originRecordID: origin),b)
    }
}
