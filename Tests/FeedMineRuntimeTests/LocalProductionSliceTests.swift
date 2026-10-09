import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineEditorial
import FeedMinePublication
import FeedMineMedia
import FeedMineRuntime

private struct LocalSliceFixture: Sendable {
    let database: RuntimeDatabase
    let plan: FeedPlan
    let editionID: FeedEditionID
    let initialCardIDs: [PublicationCardID]

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
    init(database: RuntimeDatabase, initial: [OriginRevision]) throws {
        self.database = database
        let context = FeedContext(request: .main), version = PolicyVersion(rawValue: 1)
        plan = try XCTUnwrap(FeedPlan(context: context,revision: EditorialRevision(id: EditorialRevisionID(rawValue: Self.uuid(40000)),contextKey: context.key,
            catalogGeneration: CatalogGeneration(rawValue: 1),userSelectionVersion: version,eligibilityPolicyVersion: version,scoringPolicyVersion: version,
            sequencingPolicyVersion: version,exposurePolicyVersion: version,selectionSchemaVersion: SelectionSchemaVersion(rawValue: 1))))
        editionID = FeedEditionID(rawValue: Self.uuid(41000))
        let selected = SelectionResult(editorialRevision: plan.revision,orderedCandidates: initial.map(Self.candidate),supplyReport: SelectionSupplyReport(examinedCount: 0,nextCursor: nil,exhausted: true))
        let prepared = Self.prepared(selected)
        initialCardIDs = prepared.cardIDs
        _ = try PublicationCoordinator(database: database).createEdition(.init(selection: selected,
            drafts: PublicationPreparation.drafts(selection: selected,inputs: prepared.inputs),editionID: editionID,
            publicationSchemaVersion: PublicationSchemaVersion(rawValue: 1),selectionSeed: 7,editionCreatedAt: Date(timeIntervalSince1970: 10),
            segmentID: FeedSegmentID(rawValue: Self.uuid(42000)),segmentSeed: 8,segmentCreatedAt: Date(timeIntervalSince1970: 11),cardIDs: prepared.cardIDs))
    }
    func policy(_ exposure: ResolvedSelectionPolicy.ExposureBehavior = .excludePublishedRevisions) -> ResolvedSelectionPolicy {
        let r = plan.revision
        return ResolvedSelectionPolicy(contextKey: r.contextKey,userSelectionVersion: r.userSelectionVersion,eligibilityPolicyVersion: r.eligibilityPolicyVersion,
            scoringPolicyVersion: r.scoringPolicyVersion,sequencingPolicyVersion: r.sequencingPolicyVersion,exposurePolicyVersion: r.exposurePolicyVersion,
            selectionSchemaVersion: r.selectionSchemaVersion,eligibility: .structuralOnly,scoring: .equal,sequencing: .recencyDescending,exposure: exposure)
    }
    func admit(_ revision: OriginRevision, previous: OriginRevisionID? = nil, media: [MediaCandidate] = [], identity: ExternalIdentity? = nil) throws {
        try ContentStore(database: database).commitCanonicalChange(.init(recordID: revision.originRecordID,
            externalObjectIdentity: identity ?? ExternalIdentity(connectorKind: ConnectorKind(rawValue: "test"),namespace: "objects",value: revision.originRecordID.rawValue.uuidString,role: .object),
            revision: revision,mediaCandidates: media,availability: .available,observedAt: revision.observedAt,
            expectedCurrent: previous.map { .revision($0) } ?? .none,currentUpdate: .useSuppliedRevision,
            membershipMutations: [.upsert(sourceID: SourceID(rawValue: Self.uuid(43000)),kind: .direct,observedAt: revision.observedAt)]))
    }
    func request(capacity: Int = 10, after: CandidateSupplyCursor? = nil, exposure: ResolvedSelectionPolicy.ExposureBehavior = .excludePublishedRevisions,
        edition: FeedEditionID? = nil, segment: Int = 44000) -> LocalProductionSlice.Request {
        .init(plan: plan,policy: policy(exposure),editionID: edition ?? editionID,after: after,examinedCapacity: capacity,
            segmentID: FeedSegmentID(rawValue: Self.uuid(segment)),segmentSeed: 9,segmentCreatedAt: Date(timeIntervalSince1970: 12))
    }
    func externalAppend(_ revision: OriginRevision) throws {
        let selection = SelectionResult(editorialRevision: plan.revision,orderedCandidates: [Self.candidate(revision)],supplyReport: SelectionSupplyReport(examinedCount: 0,nextCursor: nil,exhausted: false))
        let ready = Self.prepared(selection)
        _ = try PublicationCoordinator(database: database).append(.init(selection: selection,drafts: PublicationPreparation.drafts(selection: selection,inputs: ready.inputs),
            editionID: editionID,segmentID: FeedSegmentID(rawValue: Self.uuid(45000)),segmentSeed: 10,segmentCreatedAt: Date(timeIntervalSince1970: 13),cardIDs: ready.cardIDs))
    }
}

private final class LocalPreparationCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func mark() { lock.lock(); defer { lock.unlock() }; count += 1 }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

final class LocalProductionSliceTests: XCTestCase {
    private enum PreparationFailure: Error { case refused }
    private func fixture(initial: [OriginRevision] = [LocalSliceFixture.revision(900)]) throws -> LocalSliceFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try LocalSliceFixture(database: RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root)),initial: initial)
    }
    private func published(_ outcome: LocalProductionSliceOutcome) throws -> (LocalProductionProgress,PublicationReceipt) {
        guard case .published(let progress,let receipt) = outcome else { throw PreparationFailure.refused }
        return (progress,receipt)
    }
    private func assertOnlyInitial(_ f: LocalSliceFixture, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try PublicationStore(database: f.database).segments(editionID: f.editionID).map(\.cardIDs),[f.initialCardIDs],file: file,line: line)
    }

    func testOneBoundedWindowPublishesExactSelectionOrderIDsReceiptAndProgress() throws {
        let f = try fixture()
        for n in [1,4,2,3] { try f.admit(LocalSliceFixture.revision(n)) }
        let window = try CandidateProvider(contentStore: ContentStore(database: f.database)).candidates(for: f.plan,after: nil,examinedCapacity: 2)
        let calls = LocalPreparationCalls(), request = f.request(capacity: 2)
        let (progress,receipt) = try published(LocalProductionSlice(database: f.database).run(request) { selected in
            calls.mark(); XCTAssertEqual(selected.orderedCandidates.map(\.originRecordID),[LocalSliceFixture.revision(4).originRecordID,LocalSliceFixture.revision(3).originRecordID])
            return LocalSliceFixture.prepared(selected)
        })
        XCTAssertEqual(calls.value,1)
        XCTAssertEqual(progress.examinedCount,window.examinedCount); XCTAssertEqual(progress.nextCursor,window.nextCursor); XCTAssertEqual(progress.exhausted,window.exhausted)
        XCTAssertEqual(receipt.editionID,f.editionID); XCTAssertEqual(receipt.segmentID,request.segmentID); XCTAssertEqual(receipt.segmentOrdinal,1)
        let expected = [LocalSliceFixture.candidate(LocalSliceFixture.revision(4)),LocalSliceFixture.candidate(LocalSliceFixture.revision(3))]
        XCTAssertEqual(receipt.cardIDs,expected.map(LocalSliceFixture.cardID))
        let store = PublicationStore(database: f.database), segments = try store.segments(editionID: f.editionID)
        XCTAssertEqual(segments.count,2); XCTAssertEqual(segments[1].cardIDs,receipt.cardIDs)
        XCTAssertEqual(try receipt.cardIDs.map { try XCTUnwrap(store.card(id: $0)).originRevisionID },expected.map(\.originRevisionID))
        XCTAssertNil(try store.card(id: LocalSliceFixture.cardID(LocalSliceFixture.candidate(LocalSliceFixture.revision(2)))))
    }

    func testHeadRestartPublishesOnlyNewRevisionAndAllExposedWindowsReturnHonestProgress() throws {
        let a = LocalSliceFixture.revision(1), b = LocalSliceFixture.revision(2), n = LocalSliceFixture.revision(3)
        let f = try fixture(initial: [a,b])
        for revision in [a,b,n] { try f.admit(revision) }
        let first = try published(LocalProductionSlice(database: f.database).run(f.request()) { LocalSliceFixture.prepared($0) })
        XCTAssertEqual(first.1.cardIDs,[LocalSliceFixture.cardID(LocalSliceFixture.candidate(n))])
        let calls = LocalPreparationCalls()
        let outcome = try LocalProductionSlice(database: f.database).run(f.request(capacity: 2,segment: 44001)) { selected in calls.mark(); return LocalSliceFixture.prepared(selected) }
        guard case .advancedWithoutPublication(let progress) = outcome else { return XCTFail("Expected exposed-window progress") }
        XCTAssertEqual(progress.examinedCount,2); XCTAssertNotNil(progress.nextCursor); XCTAssertFalse(progress.exhausted); XCTAssertEqual(calls.value,0)
        let final = try LocalProductionSlice(database: f.database).run(f.request(capacity: 10,after: progress.nextCursor,segment: 44002)) { _ in throw PreparationFailure.refused }
        guard case .advancedWithoutPublication(let exhausted) = final else { return XCTFail("Expected exhausted progress") }
        XCTAssertTrue(exhausted.exhausted); XCTAssertEqual(exhausted.examinedCount,1)
        XCTAssertEqual(try PublicationStore(database: f.database).segments(editionID: f.editionID).count,2)
    }

    func testNewRevisionOfSameOriginAdvancesWithoutRepublicationAndAnotherEditionCanSelectIt() throws {
        let old = LocalSliceFixture.revision(1), new = LocalSliceFixture.revision(1,version: 20)
        let f = try fixture(initial: [old])
        try f.admit(old); try f.admit(new,previous: old.id)
        XCTAssertEqual(try ContentStore(database: f.database).currentRevision(originRecordID: old.originRecordID),new)
        let store = PublicationStore(database: f.database)
        let original = try XCTUnwrap(store.card(id: f.initialCardIDs[0]))
        let calls = LocalPreparationCalls()
        let outcome = try LocalProductionSlice(database: f.database).run(f.request()) { selected in
            calls.mark(); return LocalSliceFixture.prepared(selected)
        }
        guard case .advancedWithoutPublication(let progress) = outcome else { return XCTFail("Expected origin exclusion") }
        XCTAssertEqual(progress.examinedCount,1); XCTAssertTrue(progress.exhausted)
        XCTAssertNotNil(progress.nextCursor); XCTAssertEqual(calls.value,0)
        XCTAssertEqual(try store.card(id: original.id),original)
        try assertOnlyInitial(f)
        let other = FeedEditionID(rawValue: LocalSliceFixture.uuid(41001))
        let seed = LocalSliceFixture.revision(901)
        let initial = SelectionResult(editorialRevision: f.plan.revision, orderedCandidates: [LocalSliceFixture.candidate(seed)],
            supplyReport: .init(examinedCount: 0,nextCursor: nil,exhausted: true))
        let prepared = LocalSliceFixture.prepared(initial)
        _ = try PublicationCoordinator(database: f.database).createEdition(.init(selection: initial,
            drafts: PublicationPreparation.drafts(selection: initial,inputs: prepared.inputs), editionID: other,
            publicationSchemaVersion: .init(rawValue: 1),selectionSeed: 1,editionCreatedAt: Date(),
            segmentID: .init(),segmentSeed: 2,segmentCreatedAt: Date(),cardIDs: prepared.cardIDs))
        let (_,receipt) = try published(LocalProductionSlice(database: f.database).run(f.request(edition: other)) { LocalSliceFixture.prepared($0) })
        XCTAssertEqual(try store.card(id: receipt.cardIDs[0])?.originRevisionID,new.id)
        XCTAssertEqual(try store.card(id: original.id),original)
    }

    func test3R5CanonicalPayloadAndMediaChangesRemainExcludedAfterReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let location = RuntimeDatabaseLocation(directory: root)
        let old = LocalSliceFixture.revision(2)
        let changed = OriginRevision(id: OriginRevisionID(),originRecordID: old.originRecordID,externalVersionIdentity: nil,
            headline: "Edited RSS title",summary: "Edited description",bodyText: old.bodyText,authoredAt: old.authoredAt,
            modifiedAt: old.modifiedAt,observedAt: old.observedAt,language: old.language,primaryLink: old.primaryLink,
            searchProjection: old.searchProjection,providerID: old.providerID)
        let mediaOnly = OriginRevision(id: OriginRevisionID(),originRecordID: old.originRecordID,externalVersionIdentity: nil,
            headline: changed.headline,summary: changed.summary,bodyText: changed.bodyText,authoredAt: changed.authoredAt,
            modifiedAt: changed.modifiedAt,observedAt: changed.observedAt,language: changed.language,primaryLink: changed.primaryLink,
            searchProjection: changed.searchProjection,providerID: changed.providerID)
        let identity = ExternalIdentity(connectorKind: ConnectorKind(rawValue: "syndication"),namespace: "rss-guid",value: "stable-guid",role: .object)
        let f = try LocalSliceFixture(database: RuntimeDatabase(location: location),initial: [old])
        try f.admit(old,identity: identity); try f.admit(changed,previous: old.id,identity: identity)
        let original = try XCTUnwrap(PublicationStore(database: f.database).card(id: f.initialCardIDs[0]))
        func assertExcluded(_ database: RuntimeDatabase) throws {
            let outcome = try LocalProductionSlice(database: database).run(f.request()) { _ in throw PreparationFailure.refused }
            guard case .advancedWithoutPublication(let progress) = outcome else { return XCTFail("Expected same-origin exclusion") }
            XCTAssertEqual(progress.examinedCount,1); XCTAssertTrue(progress.exhausted); XCTAssertNotNil(progress.nextCursor)
            XCTAssertEqual(try PublicationStore(database: database).card(id: original.id),original)
            XCTAssertEqual(try PublicationStore(database: database).segments(editionID: f.editionID).flatMap(\.cardIDs),[original.id])
        }
        try assertExcluded(f.database)
        let media = try XCTUnwrap(MediaCandidate(id: MediaCandidateID(),originRevisionID: mediaOnly.id,role: .cardVisual,mediaClass: .image,
            remoteURL: URL(string: "https://example.invalid/image.png")!,declaredMimeType: "image/png",declaredPixelWidth: 20,declaredPixelHeight: 30))
        try f.admit(mediaOnly,previous: changed.id,media: [media],identity: identity)
        XCTAssertEqual(try ContentStore(database: f.database).currentRevision(originRecordID: old.originRecordID),mediaOnly)
        try assertExcluded(f.database)
        try assertExcluded(RuntimeDatabase(location: location))
    }

    func test3R5LaterSliceAndHeadReconsiderationSkipEditedPublishedOriginButPublishDistinctOrigin() throws {
        let old = LocalSliceFixture.revision(1), edited = LocalSliceFixture.revision(1,version: 20), distinct = LocalSliceFixture.revision(2)
        let f = try fixture()
        try f.admit(old)
        let (_,first) = try published(LocalProductionSlice(database: f.database).run(f.request(segment: 44001)) { LocalSliceFixture.prepared($0) })
        let store = PublicationStore(database: f.database)
        let original = try XCTUnwrap(store.card(id: first.cardIDs[0]))
        try f.admit(edited,previous: old.id); try f.admit(distinct)
        let (progress,second) = try published(LocalProductionSlice(database: f.database).run(f.request(segment: 44002)) { LocalSliceFixture.prepared($0) })
        XCTAssertEqual(progress.examinedCount,2); XCTAssertTrue(progress.exhausted)
        XCTAssertEqual(second.cardIDs,[LocalSliceFixture.cardID(LocalSliceFixture.candidate(distinct))])
        XCTAssertEqual(try store.card(id: original.id),original)
        XCTAssertEqual(try store.segments(editionID: f.editionID).flatMap(\.cardIDs),f.initialCardIDs + first.cardIDs + second.cardIDs)
        let head = try LocalProductionSlice(database: f.database).run(f.request(segment: 44003)) { _ in throw PreparationFailure.refused }
        guard case .advancedWithoutPublication(let exhausted) = head else { return XCTFail("Expected fully exposed head") }
        XCTAssertEqual(exhausted.examinedCount,2); XCTAssertTrue(exhausted.exhausted)
        XCTAssertEqual(try store.card(id: original.id),original)
    }

    func testPreparationThrowsOrMismatchesWithoutPublishingAndSameCursorCanRunAgain() throws {
        let f = try fixture(), revision = LocalSliceFixture.revision(1)
        try f.admit(revision)
        let slice = LocalProductionSlice(database: f.database), request = f.request()
        XCTAssertThrowsError(try slice.run(request) { _ in throw PreparationFailure.refused })
        try assertOnlyInitial(f)
        XCTAssertThrowsError(try slice.run(request) { selected in LocalPreparedPublication(inputs: [],cardIDs: LocalSliceFixture.prepared(selected).cardIDs) }) { XCTAssertEqual($0 as? PublicationPreparationError,.inputCountMismatch) }
        try assertOnlyInitial(f)
        XCTAssertThrowsError(try slice.run(request) { selected in LocalPreparedPublication(inputs: LocalSliceFixture.prepared(selected).inputs,cardIDs: []) }) { XCTAssertEqual($0 as? PublicationCoordinatorError,.inputCountMismatch) }
        try assertOnlyInitial(f)
        XCTAssertEqual(try published(slice.run(request) { LocalSliceFixture.prepared($0) }).1.cardIDs.count,1)
    }

    func testUnavailableImageRefusesWithoutFallbackThenExplicitTextOnlySucceeds() throws {
        let f = try fixture(), revision = LocalSliceFixture.revision(1)
        try f.admit(revision)
        let media = try XCTUnwrap(MediaCandidate(id: MediaCandidateID(),originRevisionID: revision.id,role: .cardVisual,mediaClass: .image,
            remoteURL: URL(string: "https://definitely.invalid/not-fetched")!,declaredMimeType: nil,declaredPixelWidth: nil,declaredPixelHeight: nil))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let unavailable = try MediaPreparation(assetDirectory: directory).prepare(candidate: media,input: .unavailable)
        let slice = LocalProductionSlice(database: f.database), request = f.request()
        XCTAssertThrowsError(try slice.run(request) { LocalSliceFixture.prepared($0,presentation: .image(unavailable,layout: .hero)) }) { XCTAssertEqual($0 as? PublicationPreparationError,.mediaNotUsable(index: 0)) }
        try assertOnlyInitial(f)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertEqual(try published(slice.run(request) { LocalSliceFixture.prepared($0) }).1.cardIDs.count,1)
    }

    func testConcurrentAppendDuringPreparationRejectsStaleSliceWithoutRetry() throws {
        let f = try fixture(), candidate = LocalSliceFixture.revision(1), winner = LocalSliceFixture.revision(50)
        try f.admit(candidate)
        let calls = LocalPreparationCalls(), slice = LocalProductionSlice(database: f.database), request = f.request()
        XCTAssertThrowsError(try slice.run(request) { selected in
            calls.mark(); try f.externalAppend(winner); return LocalSliceFixture.prepared(selected)
        }) { XCTAssertEqual($0 as? PublicationStoreError,.staleHistoryExpectation) }
        XCTAssertEqual(calls.value,1)
        let store = PublicationStore(database: f.database)
        XCTAssertEqual(try store.segments(editionID: f.editionID).count,2)
        XCTAssertNotNil(try store.card(id: LocalSliceFixture.cardID(LocalSliceFixture.candidate(winner))))
        XCTAssertNil(try store.card(id: LocalSliceFixture.cardID(LocalSliceFixture.candidate(candidate))))
        XCTAssertFalse(try store.segments(editionID: f.editionID).contains { $0.id == request.segmentID })
        XCTAssertEqual(try published(slice.run(request) { LocalSliceFixture.prepared($0) }).1.segmentOrdinal,2)
    }

    func testNonePolicyMissingEditionAndEmptyCanonicalSupplyNeverCreateOrPrepare() throws {
        let f = try fixture(), slice = LocalProductionSlice(database: f.database)
        XCTAssertThrowsError(try slice.run(f.request(exposure: .none)) { _ in throw PreparationFailure.refused }) { XCTAssertEqual($0 as? LocalProductionSliceError,.automaticExposurePolicyRequired) }
        XCTAssertThrowsError(try slice.run(f.request(edition: FeedEditionID())) { _ in throw PreparationFailure.refused }) { XCTAssertEqual($0 as? PublicationStoreError,.missingEdition) }
        let outcome = try slice.run(f.request()) { _ in throw PreparationFailure.refused }
        guard case .advancedWithoutPublication(let progress) = outcome else { return XCTFail("Expected empty exhausted progress") }
        XCTAssertEqual(progress.examinedCount,0); XCTAssertNil(progress.nextCursor); XCTAssertTrue(progress.exhausted)
        try assertOnlyInitial(f)
    }
}
