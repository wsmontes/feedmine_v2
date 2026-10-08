import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineEditorial
import FeedMinePublication
import FeedMineRuntime

private struct InitialSliceFixture: Sendable {
    let database: RuntimeDatabase
    let plan: FeedPlan
    let editionID: FeedEditionID

    static func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x",n))!
    }
    static func revision(_ n: Int, version: Int? = nil) -> OriginRevision {
        OriginRevision(id: OriginRevisionID(rawValue: uuid(1000 + (version ?? n))),originRecordID: OriginRecordID(rawValue: uuid(n)),externalVersionIdentity: nil,
            headline: n == 1 ? nil : n == 2 ? "" : " exact e\u{301} ",summary: "Summary \(n)",bodyText: nil,
            authoredAt: Date(timeIntervalSince1970: Double(version ?? n)),modifiedAt: nil,observedAt: Date(timeIntervalSince1970: 999),language: nil,primaryLink: nil,searchProjection: nil,providerID: nil)
    }
    static func candidate(_ r: OriginRevision) -> Candidate {
        Candidate(originRecordID: r.originRecordID,originRevisionID: r.id,headline: r.headline,summary: r.summary,
            timestamp: CandidateTimestamp(value: r.authoredAt ?? r.observedAt,kind: r.authoredAt == nil ? .observed : .authored),language: r.language,providerID: r.providerID)
    }
    static func cardID(_ candidate: Candidate) -> PublicationCardID {
        let n = Int(candidate.originRevisionID.rawValue.uuidString.suffix(12),radix: 16)!
        return PublicationCardID(rawValue: uuid(10000+n))
    }
    static func prepared(_ selection: SelectionResult, presentation: PublicationPresentation = .textOnly) -> LocalPreparedPublication {
        LocalPreparedPublication(inputs: selection.orderedCandidates.map { c in
            PublicationPreparationInput(origin: PublishedOrigin(originRecordID: c.originRecordID,originRevisionID: c.originRevisionID,
                sourceID: nil,providerID: c.providerID,sourceDisplayName: "Caller Source",providerDisplayName: nil),
                contentEntityID: nil,contentClusterID: nil,primaryAction: .localContentDetail,presentation: presentation)
        },cardIDs: selection.orderedCandidates.map(cardID))
    }
    init(database: RuntimeDatabase) throws {
        self.database = database
        let context = FeedContext(request: .main), version = PolicyVersion(rawValue: 1)
        plan = try XCTUnwrap(FeedPlan(context: context,revision: EditorialRevision(id: EditorialRevisionID(rawValue: Self.uuid(40000)),contextKey: context.key,
            catalogGeneration: CatalogGeneration(rawValue: 1),userSelectionVersion: version,eligibilityPolicyVersion: version,scoringPolicyVersion: version,
            sequencingPolicyVersion: version,exposurePolicyVersion: version,selectionSchemaVersion: SelectionSchemaVersion(rawValue: 1))))
        editionID = FeedEditionID(rawValue: Self.uuid(41000))
    }
    func policy(_ exposure: ResolvedSelectionPolicy.ExposureBehavior = .excludePublishedRevisions) -> ResolvedSelectionPolicy {
        let r = plan.revision
        return ResolvedSelectionPolicy(contextKey: r.contextKey,userSelectionVersion: r.userSelectionVersion,eligibilityPolicyVersion: r.eligibilityPolicyVersion,
            scoringPolicyVersion: r.scoringPolicyVersion,sequencingPolicyVersion: r.sequencingPolicyVersion,exposurePolicyVersion: r.exposurePolicyVersion,
            selectionSchemaVersion: r.selectionSchemaVersion,eligibility: .structuralOnly,scoring: .equal,sequencing: .recencyDescending,exposure: exposure)
    }
    func admit(_ revision: OriginRevision, previous: OriginRevisionID? = nil) throws {
        try ContentStore(database: database).commitCanonicalChange(.init(recordID: revision.originRecordID,
            externalObjectIdentity: ExternalIdentity(connectorKind: ConnectorKind(rawValue: "test"),namespace: "objects",value: revision.originRecordID.rawValue.uuidString,role: .object),
            revision: revision,mediaCandidates: [],availability: .available,observedAt: revision.observedAt,
            expectedCurrent: previous.map { .revision($0) } ?? .none,currentUpdate: .useSuppliedRevision,
            membershipMutations: [.upsert(sourceID: SourceID(rawValue: Self.uuid(43000)),kind: .direct,observedAt: revision.observedAt)]))
    }
    func request(capacity: Int = 10, exposure: ResolvedSelectionPolicy.ExposureBehavior = .excludePublishedRevisions,
        placement: AnchorPlacement = .center, checkpointTime: Double = 20) -> InitialProductionSlice.Request {
        .init(plan: plan, policy: policy(exposure), examinedCapacity: capacity, editionID: editionID,
            publicationSchemaVersion: PublicationSchemaVersion(rawValue: 1), selectionSeed: 7,
            editionCreatedAt: Date(timeIntervalSince1970: 10), segmentID: FeedSegmentID(rawValue: Self.uuid(42000)),
            segmentSeed: 8, segmentCreatedAt: Date(timeIntervalSince1970: 11), anchorPlacement: placement,
            checkpointedAt: Date(timeIntervalSince1970: checkpointTime))
    }
}

final class InitialProductionSliceTests: XCTestCase {
    private enum PreparationFailure: Error, Equatable { case refused }
    private func fixture(_ count: Int = 0) throws -> InitialSliceFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let f = try InitialSliceFixture(database: RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root)))
        for n in 1..<(count + 1) { try f.admit(InitialSliceFixture.revision(n)) }
        return f
    }
    private func published(_ outcome: InitialProductionSliceOutcome) throws -> (LocalProductionProgress, PublicationReceipt) {
        guard case .published(let p, let r) = outcome else { throw PreparationFailure.refused }
        return (p,r)
    }
    private func assertAbsent(_ f: InitialSliceFixture) throws {
        XCTAssertNil(try PublicationStore(database: f.database).edition(id: f.editionID))
        XCTAssertNil(try SessionStore(database: f.database).checkpoint())
        for n in 1...4 {
            XCTAssertNil(try PublicationStore(database: f.database).card(id: InitialSliceFixture.cardID(InitialSliceFixture.candidate(InitialSliceFixture.revision(n)))))
        }
    }
    func testR1LocalSupplyCreatesImmediatelyRestorableEdition() throws {
        let f = try fixture(3), request = f.request(placement: .top)
        let (_,receipt) = try published(InitialProductionSlice(database: f.database).run(request) { InitialSliceFixture.prepared($0) })
        XCTAssertEqual(receipt.segmentOrdinal, 0)
        let restored = try XCTUnwrap(PublicationHistory(database: f.database).restore(backwardCapacity: 0, forwardCapacity: 10))
        XCTAssertEqual(restored.edition.id, f.editionID)
        XCTAssertEqual(restored.cursor.editionID, f.editionID)
        XCTAssertEqual(restored.cursor.anchor.cardID, receipt.cardIDs[0])
        XCTAssertEqual(restored.cursor.anchor.placement, .top)
        XCTAssertEqual(restored.window.cards.map(\.id), receipt.cardIDs)
        XCTAssertEqual(try PublicationStore(database: f.database).segments(editionID: f.editionID).map(\.ordinal), [0])
    }
    func testR2EmptySupplyCreatesNothing() throws {
        let f = try fixture()
        let outcome = try InitialProductionSlice(database: f.database).run(f.request()) { _ in throw PreparationFailure.refused }
        guard case .advancedWithoutPublication(let p) = outcome else { return XCTFail("Expected empty progress") }
        XCTAssertEqual(p.examinedCount, 0); XCTAssertNil(p.nextCursor); XCTAssertTrue(p.exhausted)
        try assertAbsent(f)
    }
    func testR3ExactBoundedWindowWithoutRefill() throws {
        let f = try fixture(4)
        let window = try CandidateProvider(contentStore: ContentStore(database: f.database)).candidates(for: f.plan, after: nil, examinedCapacity: 2)
        let (p,r) = try published(InitialProductionSlice(database: f.database).run(f.request(capacity: 2)) { selection in
            XCTAssertEqual(selection.orderedCandidates.map(\.originRevisionID), window.candidates.map(\.originRevisionID))
            return InitialSliceFixture.prepared(selection)
        })
        XCTAssertEqual(p.examinedCount, window.examinedCount); XCTAssertLessThanOrEqual(p.examinedCount, 2)
        XCTAssertEqual(p.nextCursor, window.nextCursor); XCTAssertEqual(p.exhausted, window.exhausted)
        XCTAssertFalse(p.exhausted)
        XCTAssertEqual(r.cardIDs.count, 2)
        let store = PublicationStore(database: f.database)
        XCTAssertEqual(try store.segments(editionID: f.editionID).map(\.cardIDs), [r.cardIDs])
        XCTAssertEqual(try r.cardIDs.map { try XCTUnwrap(store.card(id: $0)).originRevisionID }, window.candidates.map(\.originRevisionID))
        XCTAssertNil(try store.card(id: InitialSliceFixture.cardID(InitialSliceFixture.candidate(InitialSliceFixture.revision(1)))))
    }
    func testR4SmallSupplyPreservesExhaustion() throws {
        let f = try fixture(1)
        let (p,_) = try published(InitialProductionSlice(database: f.database).run(f.request(capacity: 10)) { InitialSliceFixture.prepared($0) })
        XCTAssertTrue(p.exhausted); XCTAssertEqual(p.examinedCount, 1)
    }
    func testR5PreparationErrorPropagatesWithoutPublication() throws {
        let f = try fixture(1)
        XCTAssertThrowsError(try InitialProductionSlice(database: f.database).run(f.request()) { _ in throw PreparationFailure.refused }) {
            XCTAssertEqual($0 as? PreparationFailure, .refused)
        }
        try assertAbsent(f)
    }
    func testR6AutomaticExposurePolicyRequired() throws {
        let f = try fixture(1)
        XCTAssertThrowsError(try InitialProductionSlice(database: f.database).run(f.request(exposure: .none)) { _ in throw PreparationFailure.refused }) {
            XCTAssertEqual($0 as? InitialProductionSliceError, .automaticExposurePolicyRequired)
        }
        try assertAbsent(f)
    }
    func testR7OldEditionExposureDoesNotSuppressNewEdition() throws {
        let f = try fixture(1), revision = InitialSliceFixture.revision(1)
        let selection = SelectionResult(editorialRevision: f.plan.revision, orderedCandidates: [InitialSliceFixture.candidate(revision)],
            supplyReport: SelectionSupplyReport(examinedCount: 1, nextCursor: nil, exhausted: true))
        let ready = InitialSliceFixture.prepared(selection), oldID = FeedEditionID(rawValue: InitialSliceFixture.uuid(50000))
        _ = try PublicationCoordinator(database: f.database).createEdition(.init(selection: selection,
            drafts: PublicationPreparation.drafts(selection: selection, inputs: ready.inputs), editionID: oldID,
            publicationSchemaVersion: PublicationSchemaVersion(rawValue: 1), selectionSeed: 1, editionCreatedAt: Date(timeIntervalSince1970: 1),
            segmentID: FeedSegmentID(rawValue: InitialSliceFixture.uuid(50001)), segmentSeed: 2, segmentCreatedAt: Date(timeIntervalSince1970: 2),
            cardIDs: [PublicationCardID(rawValue: InitialSliceFixture.uuid(50002))]))
        XCTAssertNil(try SessionStore(database: f.database).checkpoint())
        let (_,receipt) = try published(InitialProductionSlice(database: f.database).run(f.request()) { InitialSliceFixture.prepared($0) })
        XCTAssertEqual(try PublicationStore(database: f.database).card(id: receipt.cardIDs[0])?.originRevisionID, revision.id)
        XCTAssertEqual(receipt.editionID, f.editionID)
    }
    func testR8FirstCallerCardBecomesExactCursor() throws {
        let f = try fixture(3)
        let ids = (1...3).map { PublicationCardID(rawValue: InitialSliceFixture.uuid(60000 + $0)) }
        let (_,r) = try published(InitialProductionSlice(database: f.database).run(f.request(placement: .center)) { selection in
            LocalPreparedPublication(inputs: InitialSliceFixture.prepared(selection).inputs, cardIDs: ids)
        })
        XCTAssertEqual(r.cardIDs, ids)
        let cp = try XCTUnwrap(SessionStore(database: f.database).checkpoint())
        XCTAssertEqual(cp.cardID, ids[0]); XCTAssertEqual(cp.editionID, f.editionID); XCTAssertEqual(cp.anchorPlacement, "center")
    }
    func testR9FinalCheckpointFailureThroughSliceRollsBack() throws {
        let f = try fixture(3)
        XCTAssertThrowsError(try InitialProductionSlice(database: f.database).run(f.request(checkpointTime: .infinity)) { InitialSliceFixture.prepared($0) }) {
            XCTAssertEqual($0 as? SessionStoreError, .invalidRepresentation("updated_at"))
        }
        try assertAbsent(f)
    }
    func testR10EmptyLocalAttemptNeedsNoAcquisitionFixture() throws {
        let f = try fixture()
        let outcome = try InitialProductionSlice(database: f.database).run(f.request(capacity: 1)) { _ in throw PreparationFailure.refused }
        guard case .advancedWithoutPublication(let progress) = outcome else { return XCTFail("Expected local no-publication outcome") }
        XCTAssertEqual(progress.examinedCount, 0)
        XCTAssertNil(progress.nextCursor)
        XCTAssertTrue(progress.exhausted)
        try assertAbsent(f)
    }
}
