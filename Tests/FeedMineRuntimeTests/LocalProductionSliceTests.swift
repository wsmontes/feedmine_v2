import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineEditorial
import FeedMinePublication
import FeedMineMedia
@testable import FeedMineRuntime

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
    static func candidate(_ r: OriginRevision, sources: [SourceID] = []) -> Candidate {
        Candidate(originRecordID: r.originRecordID,originRevisionID: r.id,headline: r.headline,summary: r.summary,
            timestamp: CandidateTimestamp(value: r.authoredAt ?? r.observedAt,kind: r.authoredAt == nil ? .observed : .authored),language: r.language,providerID: r.providerID,
            sourceIDs: Set(sources))
    }
    static func cardID(_ candidate: Candidate) -> PublicationCardID {
        let n = Int(candidate.originRevisionID.rawValue.uuidString.suffix(12),radix: 16)!
        return PublicationCardID(rawValue: uuid(10000+n))
    }
    static func prepared(_ selection: SelectionResult, presentation: PublicationPresentation = .textOnly,
        sourceID: SourceID? = nil) -> LocalPreparedPublication {
        LocalPreparedPublication(inputs: selection.orderedCandidates.map { c in
            PublicationPreparationInput(origin: PublishedOrigin(originRecordID: c.originRecordID,originRevisionID: c.originRevisionID,
                sourceID: sourceID,providerID: c.providerID,sourceDisplayName: "Caller Source",providerDisplayName: nil),
                contentEntityID: nil,contentClusterID: nil,primaryAction: .localContentDetail,presentation: presentation)
        },cardIDs: selection.orderedCandidates.map(cardID))
    }
    init(database: RuntimeDatabase, initial: [OriginRevision], initialSource: SourceID? = nil) throws {
        self.database = database
        let context = FeedContext(request: .main), version = PolicyVersion(rawValue: 1)
        plan = try XCTUnwrap(FeedPlan(context: context,revision: EditorialRevision(id: EditorialRevisionID(rawValue: Self.uuid(40000)),contextKey: context.key,
            catalogGeneration: CatalogGeneration(rawValue: 1),userSelectionVersion: version,eligibilityPolicyVersion: version,scoringPolicyVersion: version,
            sequencingPolicyVersion: version,exposurePolicyVersion: version,selectionSchemaVersion: SelectionSchemaVersion(rawValue: 1))))
        editionID = FeedEditionID(rawValue: Self.uuid(41000))
        let selected = SelectionResult(editorialRevision: plan.revision,orderedCandidates: initial.map {
            Self.candidate($0, sources: initialSource.map { [$0] } ?? [])
        },supplyReport: SelectionSupplyReport(examinedCount: 0,nextCursor: nil,exhausted: true))
        let prepared = Self.prepared(selected, sourceID: initialSource)
        initialCardIDs = prepared.cardIDs
        _ = try PublicationCoordinator(database: database).createEdition(.init(selection: selected,
            drafts: PublicationPreparation.drafts(selection: selected,inputs: prepared.inputs),editionID: editionID,
            publicationSchemaVersion: PublicationSchemaVersion(rawValue: 1),selectionSeed: 7,editionCreatedAt: Date(timeIntervalSince1970: 10),
            segmentID: FeedSegmentID(rawValue: Self.uuid(42000)),segmentSeed: 8,segmentCreatedAt: Date(timeIntervalSince1970: 11),cardIDs: prepared.cardIDs))
    }
    func policy(_ exposure: ResolvedSelectionPolicy.ExposureBehavior = .excludePublishedRevisions,
        sequencing: ResolvedSelectionPolicy.SequencingBehavior = .recencyDescending) -> ResolvedSelectionPolicy {
        let r = plan.revision
        return ResolvedSelectionPolicy(contextKey: r.contextKey,userSelectionVersion: r.userSelectionVersion,eligibilityPolicyVersion: r.eligibilityPolicyVersion,
            scoringPolicyVersion: r.scoringPolicyVersion,sequencingPolicyVersion: r.sequencingPolicyVersion,exposurePolicyVersion: r.exposurePolicyVersion,
            selectionSchemaVersion: r.selectionSchemaVersion,eligibility: .structuralOnly,scoring: .equal,sequencing: sequencing,exposure: exposure)
    }
    func admit(_ revision: OriginRevision, previous: OriginRevisionID? = nil, media: [MediaCandidate] = [], identity: ExternalIdentity? = nil,
        source: SourceID = SourceID(rawValue: LocalSliceFixture.uuid(43000))) throws {
        try ContentStore(database: database).commitCanonicalChange(.init(recordID: revision.originRecordID,
            externalObjectIdentity: identity ?? ExternalIdentity(connectorKind: ConnectorKind(rawValue: "test"),namespace: "objects",value: revision.originRecordID.rawValue.uuidString,role: .object),
            revision: revision,mediaCandidates: media,availability: .available,observedAt: revision.observedAt,
            expectedCurrent: previous.map { .revision($0) } ?? .none,currentUpdate: .useSuppliedRevision,
            membershipMutations: [.upsert(sourceID: source,kind: .direct,observedAt: revision.observedAt)]))
    }
    func request(capacity: Int = 10, after: CandidateSupplyCursor? = nil, exposure: ResolvedSelectionPolicy.ExposureBehavior = .excludePublishedRevisions,
        edition: FeedEditionID? = nil, segment: Int = 44000,
        sequencing: ResolvedSelectionPolicy.SequencingBehavior = .recencyDescending) -> LocalProductionSlice.Request {
        .init(plan: plan,policy: policy(exposure, sequencing: sequencing),editionID: edition ?? editionID,after: after,examinedCapacity: capacity,
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

/// What the slice said through the host's trace port, in order.
private final class PublicationTrace: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [(event: String, fields: [String: String])] = []
    var trace: ReplenishmentTrace { ReplenishmentTrace { [self] event, fields in
        lock.lock(); storage.append((event, fields)); lock.unlock()
    } }
    func fields(_ event: String) -> [[String: String]] {
        lock.lock(); defer { lock.unlock() }
        return storage.filter { $0.event == event }.map(\.fields)
    }
}

final class LocalProductionSliceTests: XCTestCase {
    private enum PreparationFailure: Error { case refused }
    private func fixture(initial: [OriginRevision] = [LocalSliceFixture.revision(900)],
        initialSource: SourceID? = nil) throws -> LocalSliceFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try LocalSliceFixture(database: RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root)),initial: initial,
            initialSource: initialSource)
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
        XCTAssertThrowsError(try slice.run(request) { selected in LocalPreparedPublication(inputs: LocalSliceFixture.prepared(selected).inputs,cardIDs: []) }) { XCTAssertEqual($0 as? PublicationPreparationError,.inputCountMismatch) }
        try assertOnlyInitial(f)
        XCTAssertEqual(try published(slice.run(request) { LocalSliceFixture.prepared($0) }).1.cardIDs.count,1)
    }

    func testUnavailableImageIsNotPublishedAndExplicitTextOnlySucceeds() throws {
        let f = try fixture(), revision = LocalSliceFixture.revision(1)
        try f.admit(revision)
        let media = try XCTUnwrap(MediaCandidate(id: MediaCandidateID(),originRevisionID: revision.id,role: .cardVisual,mediaClass: .image,
            remoteURL: URL(string: "https://definitely.invalid/not-fetched")!,declaredMimeType: nil,declaredPixelWidth: nil,declaredPixelHeight: nil))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let unavailable = try MediaPreparation(assetDirectory: directory).prepare(candidate: media,input: .unavailable)
        let slice = LocalProductionSlice(database: f.database), request = f.request()
        let outcome = try slice.run(request) {
            LocalSliceFixture.prepared($0,presentation: .image(unavailable,layout: .hero))
        }
        guard case .advancedWithoutPublication = outcome else {
            return XCTFail("an image without prepared media must not publish as text")
        }
        try assertOnlyInitial(f)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertNil(try PublicationStore(database: f.database).card(id: LocalSliceFixture.cardID(LocalSliceFixture.candidate(revision))))
        XCTAssertEqual(try published(slice.run(request) { LocalSliceFixture.prepared($0) }).1.cardIDs.count,1)
    }

    /// INV-17: the unprepared image leaves this opportunity; the ready text candidate next to it publishes.
    func testUnpreparedImageLeavesThePublishedSetAndTheTextNeighbourPublishes() throws {
        let f = try fixture()
        let image = LocalSliceFixture.revision(1), text = LocalSliceFixture.revision(2)
        try f.admit(image)
        try f.admit(text)
        let media = try XCTUnwrap(MediaCandidate(id: MediaCandidateID(), originRevisionID: image.id,
            role: .cardVisual, mediaClass: .image,
            remoteURL: URL(string: "https://definitely.invalid/not-fetched")!, declaredMimeType: nil,
            declaredPixelWidth: nil, declaredPixelHeight: nil))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let unavailable = try MediaPreparation(assetDirectory: directory).prepare(candidate: media, input: .unavailable)
        let slice = LocalProductionSlice(database: f.database), request = f.request()
        let outcome = try slice.run(request) { selected in
            let inputs = selected.orderedCandidates.map { candidate -> PublicationPreparationInput in
                let presentation: PublicationPresentation = candidate.originRevisionID == image.id
                    ? .image(unavailable, layout: .hero) : .textOnly
                return PublicationPreparationInput(
                    origin: PublishedOrigin(originRecordID: candidate.originRecordID,
                        originRevisionID: candidate.originRevisionID, sourceID: nil, providerID: candidate.providerID,
                        sourceDisplayName: nil, providerDisplayName: nil),
                    contentEntityID: nil, contentClusterID: nil, primaryAction: .localContentDetail,
                    presentation: presentation)
            }
            return LocalPreparedPublication(inputs: inputs,
                cardIDs: selected.orderedCandidates.map(LocalSliceFixture.cardID))
        }
        let (progress, receipt) = try published(outcome)
        XCTAssertEqual(progress.examinedCount, 2, "both candidates were examined")
        XCTAssertEqual(receipt.cardIDs,
            [LocalSliceFixture.cardID(LocalSliceFixture.candidate(text))],
            "only the ready text candidate is in the published set")
        let store = PublicationStore(database: f.database)
        XCTAssertNil(try store.card(id: LocalSliceFixture.cardID(LocalSliceFixture.candidate(image))),
            "the unprepared image resolves no occurrence in its place")
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

    /// The publication half of the evidence: each card that reaches history states the revision it froze, what
    /// that revision's feed declared and whether the card carries media. The text card's declaration is `false`
    /// and its media `none`; the image card's are `true` and `image`.
    func testPublishedCardsRecordTheirDeclaredImageAndCarriedMedia() throws {
        let f = try fixture()
        let image = LocalSliceFixture.revision(1), text = LocalSliceFixture.revision(2)
        let media = try XCTUnwrap(MediaCandidate(id: MediaCandidateID(), originRevisionID: image.id,
            role: .cardVisual, mediaClass: .image, remoteURL: URL(string: "https://example.test/card.png")!,
            declaredMimeType: "image/png", declaredPixelWidth: 2, declaredPixelHeight: 3))
        try f.admit(image, media: [media])
        try f.admit(text)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAEElEQVR4nGP4z8AARAwoFABE0AX7pM/egAAAAABJRU5ErkJggg==")!
        let result = try MediaPreparation(assetDirectory: directory).prepare(candidate: media, input: .bytes(png))
        guard case .usable = result.state else { return XCTFail("the fixture image must prepare") }
        let recorder = PublicationTrace()
        let slice = LocalProductionSlice(database: f.database, trace: recorder.trace)
        let base = f.request(capacity: 2)
        let request = LocalProductionSlice.Request(plan: base.plan, policy: base.policy,
            editionID: base.editionID, after: base.after, examinedCapacity: base.examinedCapacity,
            segmentID: base.segmentID, segmentSeed: base.segmentSeed,
            segmentCreatedAt: base.segmentCreatedAt, readerAnchorCardID: base.readerAnchorCardID,
            operation: FeedReplenishmentOperationID())
        let (_, receipt) = try published(slice.run(request) { selection in
            let inputs = selection.orderedCandidates.map { candidate -> PublicationPreparationInput in
                let presentation: PublicationPresentation = candidate.originRevisionID == image.id
                    ? .image(result, layout: .hero) : .textOnly
                return PublicationPreparationInput(
                    origin: PublishedOrigin(originRecordID: candidate.originRecordID,
                        originRevisionID: candidate.originRevisionID, sourceID: nil,
                        providerID: candidate.providerID, sourceDisplayName: nil, providerDisplayName: nil),
                    contentEntityID: nil, contentClusterID: nil, primaryAction: .localContentDetail,
                    presentation: presentation)
            }
            return LocalPreparedPublication(inputs: inputs,
                cardIDs: selection.orderedCandidates.map(LocalSliceFixture.cardID))
        })
        XCTAssertEqual(receipt.cardIDs.count, 2)
        let lines = recorder.fields(ReplenishmentEvent.mediaPublished)
        XCTAssertEqual(lines.count, 2, "one line per published card")
        let byRevision = Dictionary(uniqueKeysWithValues: lines.map { ($0["revision"] ?? "", $0) })
        XCTAssertEqual(byRevision[image.id.rawValue.uuidString]?["declared_image"], "true")
        XCTAssertEqual(byRevision[image.id.rawValue.uuidString]?["media"], "image")
        XCTAssertEqual(byRevision[image.id.rawValue.uuidString]?["layout"], "hero")
        XCTAssertEqual(byRevision[text.id.rawValue.uuidString]?["declared_image"], "false")
        XCTAssertEqual(byRevision[text.id.rawValue.uuidString]?["media"], "none")
    }
}

extension LocalProductionSliceTests {
    private actor HeldImage {
        private var released = false
        private var waiter: CheckedContinuation<Void, Never>?
        func wait() async {
            if released { return }
            await withCheckedContinuation { waiter = $0 }
        }
        func release() { released = true; waiter?.resume(); waiter = nil }
    }

    private static func mediaPolicy() -> MediaPolicy? {
        guard let conditions = MediaDeviceConditions(heroSlotPointWidth: 2, thumbnailSlotPointWidth: 1,
            screenScale: 1, network: .unconstrained, measuredBytesPerSecond: nil, waitBudgetSeconds: nil,
            freeStorageBytes: nil, lowPowerMode: false, thermal: .nominal),
            let ceilings = MediaSafetyCeilings(maximumDownloadBytes: 1_000_000,
                maximumPixelSide: 10_000, maximumPixelCount: 10_000_000) else { return nil }
        return MediaPolicy(conditions: conditions, ceilings: ceilings)
    }

    /// Catches pending-to-text fallback, cursor rewinds, reserved occurrences, missing head
    /// reconsideration and mutation of previously published/admitted cards.
    @MainActor
    func testF06PendingHeadAdvancesAcrossWindowsAndRecoversThroughExistingRunway() async throws {
        let f = try fixture(), held = HeldImage(), pending = LocalSliceFixture.revision(6)
        addTeardownBlock { await held.release() }
        let a = SourceID(rawValue: LocalSliceFixture.uuid(43001))
        let b = SourceID(rawValue: LocalSliceFixture.uuid(43002))
        let c = SourceID(rawValue: LocalSliceFixture.uuid(43003))
        let image = try XCTUnwrap(MediaCandidate(id: MediaCandidateID(), originRevisionID: pending.id,
            role: .cardVisual, mediaClass: .image, remoteURL: URL(string: "https://example.test/held.png")!,
            declaredMimeType: "image/png", declaredPixelWidth: 2, declaredPixelHeight: 3))
        try f.admit(pending, media: [image], source: a)
        for n in 1...5 { try f.admit(LocalSliceFixture.revision(n), source: n.isMultiple(of: 2) ? c : b) }
        let assets = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: assets) }
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAEElEQVR4nGP4z8AARAwoFABE0AX7pM/egAAAAABJRU5ErkJggg==")!
        let history = PublicationHistory(database: f.database), store = PublicationStore(database: f.database)
        let session = FeedSession(publicationHistory: history)
        try history.saveCursor(.init(editionID: f.editionID,
            anchor: .init(cardID: f.initialCardIDs[0], placement: .center)), updatedAt: Date())
        let admitted = try await session.admitPresentation(.initial(.init(backwardCapacity: 0, forwardCapacity: 10)))
        let scope = RunwayScope(editionID: f.editionID, contextKey: f.plan.context.key, editorialRevisionID: f.plan.revision.id)
        let runway = RunwayController(configuration: .init(policyInputs: .init(safetyFactor: 1, releaseMarginSeconds: 0)!,
            consumptionSampleLimit: 2, replenishmentSampleLimit: 2)!)
        await runway.activate(scope)
        let observation = RunwayObservation(editionID: f.editionID, anchorCardID: f.initialCardIDs[0],
            sampledAt: .init(seconds: 0)!, activity: .stationary)
        try await runway.submitObservation(observation)
        let recovered = expectation(description: "Held image became presentation-ready")
        let media = MediaPrefetcher(database: f.database, assetDirectory: assets, concurrentDownloadLimit: 2,
            fetch: { _, _ in await held.wait(); return png }, conditions: { _ in Self.mediaPolicy() },
            onReadinessChanged: { revision in
                if revision == pending.id {
                    try? await runway.noteLocalSupplyChanged(scope: scope)
                    recovered.fulfill()
                }
            })
        // The deadline relinquishes waiting immediately; no time budget can degrade this image.
        await media.prefetch([pending.id], deadline: ProcessInfo.processInfo.systemUptime - 1)
        await media.prefetch((1...5).reversed().map { LocalSliceFixture.revision($0).id })
        let slice = LocalProductionSlice(database: f.database, readiness: media.readiness)
        let resources = RunwayResourceFacts(localWorkAllowed: true, examinedCandidateCapacity: 2,
            readyProbeBound: 10, readyProbeCeiling: 10, forwardAdvanceProbeBound: 10, reserveCards: 10)!
        func measure() async throws {
            try await runway.acceptMeasurement(.init(observation: observation,
                readyAhead: history.readyAhead(editionID: f.editionID, anchorCardID: f.initialCardIDs[0], probeBound: 10),
                advanceFromHighWater: nil))
        }
        func next(_ at: Double) async throws -> RunwayLocalSliceIntent {
            try await measure()
            guard case .runLocalSlice(let intent) = try await runway.reconsider(resources: resources, at: .init(seconds: at)!) else {
                throw PreparationFailure.refused
            }
            return intent
        }
        let prepare: @Sendable (SelectionResult) throws -> LocalPreparedPublication = { selection in
            let inputs = try selection.orderedCandidates.map { candidate in
                PublicationPreparationInput(origin: .init(originRecordID: candidate.originRecordID,
                    originRevisionID: candidate.originRevisionID, sourceID: candidate.sourceIDs.first,
                    providerID: candidate.providerID, sourceDisplayName: nil, providerDisplayName: nil),
                    contentEntityID: nil, contentClusterID: nil, primaryAction: .localContentDetail,
                    presentation: try XCTUnwrap(media.readiness.presentation(for: candidate.originRevisionID)))
            }
            return .init(inputs: inputs, cardIDs: selection.orderedCandidates.map(LocalSliceFixture.cardID))
        }
        var priorCursor: CandidateSupplyCursor?
        for (index, wanted) in [[5], [4, 3], [2, 1]].enumerated() {
            let at = Double(index * 2 + 1), intent = try await next(at)
            XCTAssertEqual(intent.after, priorCursor)
            let outcome = try slice.run(f.request(capacity: 2, after: intent.after, exposure: .excludePublishedMaterial, segment: 46000 + index,
                sequencing: .recencyAlternatingSources), prepare: prepare)
            let (progress, receipt) = try published(outcome)
            XCTAssertEqual(try receipt.cardIDs.map { try XCTUnwrap(store.card(id: $0)).originRevisionID },
                wanted.map { LocalSliceFixture.revision($0).id })
            XCTAssertEqual(receipt.segmentOrdinal, UInt64(index + 1))
            XCTAssertEqual(progress.examinedCount, 2)
            XCTAssertEqual(progress.nextCursor?.originRecordID, LocalSliceFixture.revision(wanted.last!).originRecordID)
            priorCursor = progress.nextCursor
            try await runway.completeLocalSlice(intent, outcome: outcome, at: .init(seconds: at + 1)!)
            XCTAssertNil(media.readiness.presentation(for: pending.id))
            XCTAssertNil(try store.card(id: LocalSliceFixture.cardID(LocalSliceFixture.candidate(pending))))
            XCTAssertEqual(try ContentStore(database: f.database).currentRevision(originRecordID: pending.originRecordID), pending)
        }
        // A full bounded page does not prove exhaustion; the following empty page does.
        let lastIntent = try await next(7)
        XCTAssertEqual(lastIntent.after, priorCursor)
        let lastOutcome = try slice.run(f.request(capacity: 2, after: lastIntent.after, exposure: .excludePublishedMaterial, segment: 46009,
            sequencing: .recencyAlternatingSources), prepare: prepare)
        guard case .advancedWithoutPublication(let lastProgress) = lastOutcome else {
            throw PreparationFailure.refused
        }
        XCTAssertEqual(lastProgress.examinedCount, 0)
        XCTAssertTrue(lastProgress.exhausted)
        try await runway.completeLocalSlice(lastIntent, outcome: lastOutcome, at: .init(seconds: 8)!)
        let exhausted = await runway.snapshot()
        XCTAssertTrue(exhausted.localSupplyExhausted)
        let oldIDs = try store.segments(editionID: f.editionID).flatMap(\.cardIDs)
        let oldCards = try oldIDs.map { try XCTUnwrap(store.card(id: $0)) }
        let stillAdmitted = await session.currentPresentation()
        XCTAssertEqual(stillAdmitted, admitted)
        // No readiness transition: exhaustion causes no repeated publication opportunity.
        try await measure()
        if case .runLocalSlice = try await runway.reconsider(resources: resources, at: .init(seconds: 9)!) {
            await held.release()
            XCTFail("Unready head must not spin")
            throw PreparationFailure.refused
        }
        await held.release()
        await fulfillment(of: [recovered], timeout: 2)
        let intent = try await next(10)
        XCTAssertNil(intent.after, "Readiness reopens the existing head reconsideration mechanism")
        let outcome = try slice.run(f.request(capacity: 2, after: intent.after, exposure: .excludePublishedMaterial, segment: 46003,
            sequencing: .recencyAlternatingSources), prepare: prepare)
        let (_, receipt) = try published(outcome)
        XCTAssertEqual(receipt.segmentOrdinal, 4)
        XCTAssertEqual(receipt.cardIDs.count, 1)
        let returned = try XCTUnwrap(store.card(id: receipt.cardIDs[0]))
        XCTAssertEqual(returned.originRevisionID, pending.id)
        XCTAssertEqual(returned.renderLayout, "thumbnail")
        XCTAssertNotNil(returned.mediaKey)
        XCTAssertEqual(try store.segments(editionID: f.editionID).flatMap(\.cardIDs), oldIDs + receipt.cardIDs)
        XCTAssertEqual(try oldIDs.map { try XCTUnwrap(store.card(id: $0)) }, oldCards)
        let after = await session.currentPresentation()
        XCTAssertEqual(after, admitted, "Media recovery and publication cannot admit or move the reader")
        try await runway.completeLocalSlice(intent, outcome: outcome, at: .init(seconds: 11)!)
        let again = try slice.run(f.request(exposure: .excludePublishedMaterial, segment: 46004, sequencing: .recencyAlternatingSources), prepare: prepare)
        guard case .advancedWithoutPublication = again else { return XCTFail("Recovered origin published twice") }
        XCTAssertEqual(try store.segments(editionID: f.editionID).count, 5)
    }

    /// B/H(b), spec "Estabilidade de coleta e UI": a media readiness transition is the local-supply fact that
    /// reopens the runway's existing drive opportunity, and pending media is never published before it.
    @MainActor
    func testReadinessTransitionSchedulesTheDriveThatPublishesPendingMedia() async throws {
        let f = try fixture(), held = HeldImage(), pending = LocalSliceFixture.revision(6)
        addTeardownBlock { await held.release() }
        let image = try XCTUnwrap(MediaCandidate(id: MediaCandidateID(), originRevisionID: pending.id,
            role: .cardVisual, mediaClass: .image, remoteURL: URL(string: "https://example.test/pending.png")!,
            declaredMimeType: "image/png", declaredPixelWidth: 2, declaredPixelHeight: 3))
        try f.admit(pending, media: [image])
        let assets = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: assets) }
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAEElEQVR4nGP4z8AARAwoFABE0AX7pM/egAAAAABJRU5ErkJggg==")!
        let pendingCardID = LocalSliceFixture.cardID(LocalSliceFixture.candidate(pending))

        // The reader's position and the runway are the real ones: no fake scheduler stands in for the
        // notification `RunwayController` already owns.
        let history = PublicationHistory(database: f.database)
        try history.saveCursor(.init(editionID: f.editionID,
            anchor: .init(cardID: f.initialCardIDs[0], placement: .center)), updatedAt: Date())
        let scope = RunwayScope(editionID: f.editionID, contextKey: f.plan.context.key,
            editorialRevisionID: f.plan.revision.id)
        let runway = RunwayController(configuration: .init(
            policyInputs: .init(safetyFactor: 1, releaseMarginSeconds: 0)!,
            consumptionSampleLimit: 2, replenishmentSampleLimit: 2)!)
        _ = try await FeedSession(publicationHistory: history)
            .admitPresentation(.initial(.init(backwardCapacity: 0, forwardCapacity: 10)))
        await runway.activate(scope)
        let observation = RunwayObservation(editionID: f.editionID, anchorCardID: f.initialCardIDs[0],
            sampledAt: .init(seconds: 0)!, activity: .stationary)
        try await runway.submitObservation(observation)

        let scheduled = expectation(description: "readiness scheduled the existing drive opportunity")
        let media = MediaPrefetcher(database: f.database, assetDirectory: assets, concurrentDownloadLimit: 1,
            fetch: { _, _ in await held.wait(); return png }, conditions: { _ in Self.mediaPolicy() },
            onReadinessChanged: { revision in
                guard revision == pending.id else { return }
                try? await runway.noteLocalSupplyChanged(scope: scope)
                scheduled.fulfill()
            })
        let readiness = media.readiness
        await media.prefetch([pending.id], deadline: ProcessInfo.processInfo.systemUptime - 1)
        XCTAssertNil(readiness.presentation(for: pending.id), "pending media has no presentation to publish")
        XCTAssertNil(try PublicationStore(database: f.database).card(id: pendingCardID),
            "pending media is never published before its readiness transition")

        let sliceResources = RunwayResourceFacts(localWorkAllowed: true, examinedCandidateCapacity: 4,
            readyProbeBound: 10, readyProbeCeiling: 10, forwardAdvanceProbeBound: 10, reserveCards: 10)!
        let slice = LocalProductionSlice(database: f.database, readiness: readiness)
        func measure() async throws {
            try await runway.acceptMeasurement(.init(observation: observation,
                readyAhead: history.readyAhead(editionID: f.editionID,
                    anchorCardID: f.initialCardIDs[0], probeBound: 10),
                advanceFromHighWater: nil))
        }

        // Before any transition: the pending head is suspended, and the bounded page proves exhaustion.
        try await measure()
        let firstIntent: RunwayLocalSliceIntent
        guard case .runLocalSlice(let first) = try await runway.reconsider(resources: sliceResources,
            at: .init(seconds: 1)!) else { return XCTFail("a fresh runway must offer its first local slice") }
        firstIntent = first
        let firstOutcome = try slice.run(f.request(capacity: 10, exposure: .excludePublishedMaterial, segment: 47_000)) { _ in
            throw PreparationFailure.refused
        }
        guard case .advancedWithoutPublication(let progress) = firstOutcome else {
            return XCTFail("unready media must suspend, never fall back to a text-only card")
        }
        XCTAssertTrue(progress.exhausted)
        try await runway.completeLocalSlice(firstIntent, outcome: firstOutcome, at: .init(seconds: 2)!)
        let exhaustedRunway = await runway.snapshot()
        XCTAssertTrue(exhaustedRunway.localSupplyExhausted)
        XCTAssertEqual(try PublicationStore(database: f.database).segments(editionID: f.editionID).flatMap(\.cardIDs),
            f.initialCardIDs, "only the fixture's own card is published")
        // Exhaustion alone is not a supply fact: the suspended head must not spin.
        try await measure()
        if case .runLocalSlice = try await runway.reconsider(resources: sliceResources, at: .init(seconds: 2.5)!) {
            return XCTFail("exhaustion without a supply change must not schedule another drive")
        }

        // The transition: the held download settles, and the callback schedules the drive.
        await held.release()
        await fulfillment(of: [scheduled], timeout: 2)
        XCTAssertNotNil(readiness.presentation(for: pending.id))
        let reopened = await runway.snapshot()
        XCTAssertFalse(reopened.localSupplyExhausted,
            "readiness reopens the existing local-supply opportunity")

        try await measure()
        let intent: RunwayLocalSliceIntent
        guard case .runLocalSlice(let next) = try await runway.reconsider(resources: sliceResources,
            at: .init(seconds: 3)!) else { return XCTFail("the scheduled opportunity must run") }
        intent = next
        XCTAssertNil(intent.after)
        let outcome = try slice.run(f.request(capacity: 10, exposure: .excludePublishedMaterial, segment: 47_001)) { selection in
            LocalPreparedPublication(inputs: try selection.orderedCandidates.map { candidate in
                PublicationPreparationInput(origin: .init(originRecordID: candidate.originRecordID,
                    originRevisionID: candidate.originRevisionID, sourceID: nil, providerID: candidate.providerID,
                    sourceDisplayName: "Caller Source", providerDisplayName: nil),
                    contentEntityID: nil, contentClusterID: nil, primaryAction: .localContentDetail,
                    presentation: try XCTUnwrap(readiness.presentation(for: candidate.originRevisionID)))
            }, cardIDs: selection.orderedCandidates.map(LocalSliceFixture.cardID))
        }
        guard case .published(_, let receipt) = outcome else {
            return XCTFail("the drive the transition scheduled must publish the pending card")
        }
        XCTAssertEqual(receipt.cardIDs, [pendingCardID])
        XCTAssertNotNil(try PublicationStore(database: f.database).card(id: pendingCardID)?.mediaKey)
    }

    func testF06AllPendingWindowAdvancesWithoutCallingPreparationOrReservingSegment() async throws {
        let f = try fixture(), pending = LocalSliceFixture.revision(2), ready = LocalSliceFixture.revision(1)
        try f.admit(pending); try f.admit(ready)
        let assets = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: assets) }
        let media = MediaPrefetcher(database: f.database, assetDirectory: assets, concurrentDownloadLimit: 1,
            fetch: { _, _ in throw PreparationFailure.refused }, conditions: { _ in Self.mediaPolicy() })
        await media.prefetch([ready.id]) // A legitimate no-image story; the head remains undecided.
        let slice = LocalProductionSlice(database: f.database, readiness: media.readiness)
        let request = f.request(capacity: 1)
        let outcome = try slice.run(request) { _ in throw PreparationFailure.refused }
        guard case .advancedWithoutPublication(let progress) = outcome else { return XCTFail("Expected suspension") }
        XCTAssertEqual(progress.examinedCount, 1)
        XCTAssertEqual(progress.nextCursor?.originRecordID, pending.originRecordID)
        XCTAssertFalse(progress.exhausted)
        try assertOnlyInitial(f)
        XCTAssertFalse(try PublicationStore(database: f.database).segments(editionID: f.editionID).contains { $0.id == request.segmentID })
        let (_, receipt) = try published(slice.run(f.request(capacity: 1, after: progress.nextCursor)) {
            LocalSliceFixture.prepared($0)
        })
        XCTAssertEqual(receipt.segmentOrdinal, 1, "An empty ready opportunity reserves no ordinal")
        XCTAssertEqual(receipt.segmentID, request.segmentID, "The skipped segment identity is still reusable")
        XCTAssertEqual(receipt.cardIDs, [LocalSliceFixture.cardID(LocalSliceFixture.candidate(ready))])
        XCTAssertNil(try PublicationStore(database: f.database).card(id: LocalSliceFixture.cardID(LocalSliceFixture.candidate(pending))))
    }

    /// If readiness is filtered after alternation, removing B joins A/A and violates PD-4.
    func testF06ReadinessRestrictsBeforeAlternationAndKeepsStructuralCursorFacts() throws {
        let f = try fixture(), a = SourceID(), b = SourceID(), c = SourceID()
        for (n, source) in [(4, a), (3, b), (2, a), (1, c)] {
            try f.admit(LocalSliceFixture.revision(n), source: source)
        }
        let window = try CandidateProvider(contentStore: ContentStore(database: f.database)).candidates(for: f.plan,
            after: nil, examinedCapacity: 4)
        let facts = try XCTUnwrap(SelectionReadinessSnapshot(requestedRevisionIDs: window.candidates.map(\.originRevisionID),
            readyRevisionIDs: Set([4, 2, 1].map { LocalSliceFixture.revision($0).id })))
        let exposure = try XCTUnwrap(SelectionExposureSnapshot(requestedOriginIDs: window.candidates.map(\.originRecordID), publishedOriginIDs: []))
        let selection = try SelectionEngine().select(plan: f.plan, policy: f.policy(sequencing: .recencyAlternatingSources),
            window: window, exposure: exposure, after: nil, readiness: facts)
        XCTAssertEqual(selection.orderedCandidates.map(\.originRevisionID), [4, 1, 2].map { LocalSliceFixture.revision($0).id })
        XCTAssertEqual(selection.supplyReport.examinedCount, 4)
        XCTAssertEqual(selection.supplyReport.nextCursor, window.nextCursor)
        XCTAssertEqual(selection.supplyReport.exhausted, window.exhausted)
    }

    func testGroupedSupplyContributesTwentySourcesToFirstThreeHundredCards() throws {
        let f = try fixture(), slice = LocalProductionSlice(database: f.database)
        for n in 1...800 {
            try f.admit(LocalSliceFixture.revision(n),
                source: SourceID(rawValue: LocalSliceFixture.uuid(50000 + (n - 1) / 20)))
        }
        var cursor: CandidateSupplyCursor?
        var contributions: [SourceID] = []
        let store = ContentStore(database: f.database)
        for opportunity in 0..<45 {
            let outcome = try slice.run(f.request(capacity: 32, after: cursor,
                exposure: .excludePublishedMaterial, segment: 60000 + opportunity,
                sequencing: .recencyAlternatingSourcesBySupplyShare)) { LocalSliceFixture.prepared($0) }
            let progress: LocalProductionProgress
            switch outcome {
            case .published(let value, let receipt):
                progress = value
                for id in receipt.cardIDs {
                    let card = try XCTUnwrap(PublicationStore(database: f.database).card(id: id))
                    contributions.append(try XCTUnwrap(store.memberships(originRecordID: card.originRecordID).first?.sourceID))
                }
            case .advancedWithoutPublication(let value): progress = value
            }
            cursor = progress.nextCursor
            if contributions.count >= 300 || progress.exhausted { break }
        }
        XCTAssertGreaterThanOrEqual(contributions.count, 300)
        XCTAssertGreaterThanOrEqual(Set(contributions.prefix(300)).count, 20)
    }

    func testInitialExaminationAdvancesPastAlternationHeldCandidates() throws {
        let f = try fixture(), source = SourceID()
        for n in 1...4 { try f.admit(LocalSliceFixture.revision(n), source: source) }
        let request = InitialProductionSlice.Request(plan: f.plan,
            policy: f.policy(.excludePublishedMaterial, sequencing: .recencyAlternatingSources),
            examinedCapacity: 4, editionID: FeedEditionID(), publicationSchemaVersion: .init(rawValue: 1),
            selectionSeed: 1, editionCreatedAt: Date(), segmentID: FeedSegmentID(), segmentSeed: 1,
            segmentCreatedAt: Date(), anchorPlacement: .top, checkpointedAt: Date())
        let outcome = try InitialProductionSlice(database: f.database).run(request) { LocalSliceFixture.prepared($0) }
        guard case .published(let progress, let receipt) = outcome else { return XCTFail("Expected first publication") }
        XCTAssertEqual(receipt.cardIDs.count, 1)
        XCTAssertEqual(progress.nextCursor?.originRecordID, LocalSliceFixture.revision(1).originRecordID)
        XCTAssertEqual(progress.examinedCount, 4)
    }

    func testExaminationAdvancesPastAlternationHeldCandidatesAcrossOpportunities() throws {
        let f = try fixture(), a = SourceID(), b = SourceID()
        for n in 1...8 {
            try f.admit(LocalSliceFixture.revision(n), source: n >= 5 ? a : b)
        }
        let slice = LocalProductionSlice(database: f.database)
        let first = try published(slice.run(f.request(capacity: 4, exposure: .excludePublishedMaterial,
            sequencing: .recencyAlternatingSources)) { LocalSliceFixture.prepared($0) })
        XCTAssertEqual(first.1.cardIDs.count, 1, "Alternation holds the remaining same-source stories")
        XCTAssertEqual(first.0.examinedCount, 4)
        XCTAssertEqual(first.0.nextCursor?.originRecordID, LocalSliceFixture.revision(5).originRecordID)
        XCTAssertFalse(first.0.exhausted)
        let second = try published(slice.run(f.request(capacity: 4, after: first.0.nextCursor,
            exposure: .excludePublishedMaterial, segment: 44001,
            sequencing: .recencyAlternatingSources)) { LocalSliceFixture.prepared($0) })
        XCTAssertEqual(second.1.cardIDs, [LocalSliceFixture.cardID(LocalSliceFixture.candidate(LocalSliceFixture.revision(4)))])
        XCTAssertEqual(second.1.segmentOrdinal, 2)
        XCTAssertEqual(second.0.nextCursor?.originRecordID, LocalSliceFixture.revision(1).originRecordID)
        // Returning to the head still consults PD-1, with no duplicate occurrence or reserved position.
        let replay = try slice.run(f.request(capacity: 1, exposure: .excludePublishedMaterial, segment: 44002,
            sequencing: .recencyAlternatingSources)) { _ in throw PreparationFailure.refused }
        guard case .advancedWithoutPublication = replay else { return XCTFail("Published head recurred") }
        XCTAssertEqual(try PublicationStore(database: f.database).segments(editionID: f.editionID).count, 3)
    }


    /// PD-4 must not let a new supply membership rewrite an already-published segment boundary.
    func testPublishedTailAlternationIsUnaffectedByLaterMemberships() throws {
        let tailRevision = LocalSliceFixture.revision(900)
        let nextRevision = LocalSliceFixture.revision(901)
        let frozen = SourceID(rawValue: LocalSliceFixture.uuid(56001))
        let later = SourceID(rawValue: LocalSliceFixture.uuid(56002))
        let unchanged = try fixture(initial: [tailRevision], initialSource: frozen)
        let changed = try fixture(initial: [tailRevision], initialSource: frozen)
        for instance in [unchanged, changed] {
            try instance.admit(nextRevision, source: later)
        }
        // The tail card was already published with its frozen SourceID when this membership arrived.
        try changed.admit(tailRevision, source: later)
        XCTAssertEqual(try ContentStore(database: changed.database)
            .memberships(originRecordID: tailRevision.originRecordID).map(\.sourceID), [later])
        let tail = try PublicationHistory(database: changed.database).window(
            editionID: changed.editionID, around: .init(cardID: changed.initialCardIDs[0], placement: .top),
            backwardCapacity: 0, forwardCapacity: 0)
        XCTAssertEqual(tail.cards.first?.origin.sourceID, frozen)
        for instance in [unchanged, changed] {
            let (_, receipt) = try published(LocalProductionSlice(database: instance.database).run(
                instance.request(sequencing: .recencyAlternatingSources)
            ) { LocalSliceFixture.prepared($0) })
            XCTAssertEqual(receipt.cardIDs, [LocalSliceFixture.cardID(LocalSliceFixture.candidate(nextRevision))])
        }
    }

    func testF06ReadinessFactsCannotAuthorizeAnotherWindowOrUnknownRevisions() throws {
        let f = try fixture(), revision = LocalSliceFixture.revision(1), other = LocalSliceFixture.revision(2)
        try f.admit(revision)
        XCTAssertNil(SelectionReadinessSnapshot(requestedRevisionIDs: [revision.id], readyRevisionIDs: [other.id]))
        XCTAssertNil(SelectionReadinessSnapshot(requestedRevisionIDs: [revision.id, revision.id], readyRevisionIDs: [revision.id]))
        let window = try CandidateProvider(contentStore: ContentStore(database: f.database)).candidates(for: f.plan,
            after: nil, examinedCapacity: 10)
        let exposure = try XCTUnwrap(SelectionExposureSnapshot(requestedOriginIDs: [revision.originRecordID], publishedOriginIDs: []))
        let stale = try XCTUnwrap(SelectionReadinessSnapshot(requestedRevisionIDs: [other.id], readyRevisionIDs: [other.id]))
        XCTAssertThrowsError(try SelectionEngine().select(plan: f.plan, policy: f.policy(), window: window,
            exposure: exposure, after: nil, readiness: stale)) {
            XCTAssertEqual($0 as? SelectionError, .readinessCoverageMismatch)
        }
    }

    /// P10/R17 (E07): the diversity facts the publication froze are read back from a **restored** database and the
    /// engine's order follows them. The engine tests build the context by hand, and the store tests prove only the
    /// row; this is the seam between the two — the gap the plan named as "falta comparação fim a fim entre
    /// bancos/restaurações".
    func testPersistedDiversityFactsSurviveRestorationAndDriveTheEngineOrder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let sourceA = SourceID(), sourceB = SourceID()
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let f = try LocalSliceFixture(database: database, initial: [LocalSliceFixture.revision(900)],
            initialSource: sourceA)
        let live = try PublicationStore(database: database).recentDiversity(editionID: f.editionID, limit: 16)
        XCTAssertFalse(live.isEmpty, "the publication froze the source fact")
        XCTAssertTrue(live.contains { $0.sourceIDs.contains(sourceA) }, "the fact names the published source")
        let restoredDatabase = try RuntimeDatabase(location: .init(directory: directory))
        let restored = try PublicationStore(database: restoredDatabase).recentDiversity(editionID: f.editionID,
            limit: 16)
        XCTAssertEqual(restored, live, "uma restauração lê exatamente os fatos congelados")

        let repeated = LocalSliceFixture.revision(7)
        let fresh = LocalSliceFixture.revision(6)
        try f.admit(repeated, source: sourceA)
        try f.admit(fresh, source: sourceB)
        let window = try CandidateProvider(contentStore: ContentStore(database: database)).candidates(for: f.plan,
            after: nil, examinedCapacity: 10)
        XCTAssertEqual(window.candidates.map(\.originRecordID),
            [repeated.originRecordID, fresh.originRecordID], "the window is the newest first, before diversity")
        let context = FeedContext(request: .main), v = PolicyVersion(rawValue: 1)
        let revision = EditorialRevision(id: EditorialRevisionID(), contextKey: context.key,
            catalogGeneration: CatalogGeneration(rawValue: 1), userSelectionVersion: v,
            eligibilityPolicyVersion: v, scoringPolicyVersion: v,
            sequencingPolicyVersion: PolicyVersion(rawValue: 5), exposurePolicyVersion: v,
            selectionSchemaVersion: SelectionSchemaVersion(rawValue: 1))
        let plan = try XCTUnwrap(FeedPlan(context: context, revision: revision))
        let policy = ResolvedSelectionPolicy(contextKey: revision.contextKey,
            userSelectionVersion: revision.userSelectionVersion,
            eligibilityPolicyVersion: revision.eligibilityPolicyVersion,
            scoringPolicyVersion: revision.scoringPolicyVersion,
            sequencingPolicyVersion: revision.sequencingPolicyVersion,
            exposurePolicyVersion: revision.exposurePolicyVersion,
            selectionSchemaVersion: revision.selectionSchemaVersion, eligibility: .structuralOnly, scoring: .equal,
            sequencing: .recencyDescending, exposure: .none)
        let varied = try SelectionEngine().select(plan: plan, policy: policy, window: window, exposure: nil,
            after: nil, diversity: try XCTUnwrap(SelectionDiversityContext(recent: restored)))
            .orderedCandidates.map(\.originRecordID)
        XCTAssertEqual(varied, [fresh.originRecordID, repeated.originRecordID],
            "o fato restaurado da fonte recente cede lugar à fonte nova")
        let plain = try SelectionEngine().select(plan: plan, policy: policy, window: window, exposure: nil,
            after: nil, diversity: nil).orderedCandidates.map(\.originRecordID)
        XCTAssertEqual(plain, [repeated.originRecordID, fresh.originRecordID],
            "sem os fatos, a ordem é a recência — o contexto restaurado é o que muda a ordem")
    }

    /// P09/R17 (E07): the same restored facts that reorder under version 5 leave an older Edition (version 4) exactly
    /// in recency order. The comparison is the plan's "v5 e versões antigas" clause end to end: the facts come from
    /// a restored database, not from a hand-built context.
    func testRestoredDiversityFactsLeaveAnOlderSequencingEditionInRecencyOrder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let sourceA = SourceID(), sourceB = SourceID()
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let f = try LocalSliceFixture(database: database, initial: [LocalSliceFixture.revision(900)],
            initialSource: sourceA)
        let restoredDatabase = try RuntimeDatabase(location: .init(directory: directory))
        let restored = try PublicationStore(database: restoredDatabase).recentDiversity(editionID: f.editionID,
            limit: 16)
        XCTAssertTrue(restored.contains { $0.sourceIDs.contains(sourceA) },
            "the restored fact names the published source")

        let repeated = LocalSliceFixture.revision(9)
        let fresh = LocalSliceFixture.revision(8)
        try f.admit(repeated, source: sourceA)
        try f.admit(fresh, source: sourceB)
        let window = try CandidateProvider(contentStore: ContentStore(database: database)).candidates(for: f.plan,
            after: nil, examinedCapacity: 10)
        XCTAssertEqual(window.candidates.map(\.originRecordID),
            [repeated.originRecordID, fresh.originRecordID], "the window is the newest first, before diversity")
        let diversity = try XCTUnwrap(SelectionDiversityContext(recent: restored))

        func order(sequenceVersion: UInt64) throws -> [OriginRecordID] {
            let context = FeedContext(request: .main), v = PolicyVersion(rawValue: 1)
            let revision = EditorialRevision(id: EditorialRevisionID(), contextKey: context.key,
                catalogGeneration: CatalogGeneration(rawValue: 1), userSelectionVersion: v,
                eligibilityPolicyVersion: v, scoringPolicyVersion: v,
                sequencingPolicyVersion: PolicyVersion(rawValue: sequenceVersion), exposurePolicyVersion: v,
                selectionSchemaVersion: SelectionSchemaVersion(rawValue: 1))
            let plan = try XCTUnwrap(FeedPlan(context: context, revision: revision))
            let policy = ResolvedSelectionPolicy(contextKey: revision.contextKey,
                userSelectionVersion: revision.userSelectionVersion,
                eligibilityPolicyVersion: revision.eligibilityPolicyVersion,
                scoringPolicyVersion: revision.scoringPolicyVersion,
                sequencingPolicyVersion: revision.sequencingPolicyVersion,
                exposurePolicyVersion: revision.exposurePolicyVersion,
                selectionSchemaVersion: revision.selectionSchemaVersion, eligibility: .structuralOnly,
                scoring: .equal, sequencing: .recencyDescending, exposure: .none)
            return try SelectionEngine().select(plan: plan, policy: policy, window: window, exposure: nil,
                after: nil, diversity: diversity).orderedCandidates.map(\.originRecordID)
        }

        XCTAssertEqual(try order(sequenceVersion: 4), [repeated.originRecordID, fresh.originRecordID],
            "a versão 4 ignora os fatos congelados e mantém a recência")
        XCTAssertEqual(try order(sequenceVersion: 5), [fresh.originRecordID, repeated.originRecordID],
            "a versão 5 usa o fato restaurado e cede lugar à fonte nova")
    }
}

extension LocalProductionSliceTests {
    /// The measured production failure, stated as a difference of one fact: the walk is one-way, so a story skipped
    /// while its media was pending never returns. The same supply and the same later opportunity run twice — once
    /// with the bounded re-offer queue and once without it (the HEAD behaviour) — and only the queue publishes the
    /// skipped story. No published card is rewritten either way.
    func testSkippedPendingStoryBecomesReachableByALaterOpportunityWithoutMovingTheWalk() throws {
        let skipped = LocalSliceFixture.revision(6)
        let skippedCard = LocalSliceFixture.cardID(LocalSliceFixture.candidate(skipped))

        func admitSupply(_ f: LocalSliceFixture) throws {
            for n in [6, 4, 3, 2] { try f.admit(LocalSliceFixture.revision(n)) }
        }
        func recordReady(_ readiness: MediaReadiness, _ revisions: [Int]) {
            for n in revisions {
                readiness.record(LocalSliceFixture.revision(n).id, nil, textDeclared: true)
            }
        }

        // HEAD: the walk passes the pending story and the cursor never comes back to it.
        let head = try fixture(initial: [LocalSliceFixture.revision(1)])
        try admitSupply(head)
        let headReadiness = MediaReadiness()
        recordReady(headReadiness, [1, 2, 3, 4])
        let headSlice = LocalProductionSlice(database: head.database, readiness: headReadiness)
        let headFirst = try published(headSlice.run(head.request(capacity: 2)) { LocalSliceFixture.prepared($0) })
        XCTAssertEqual(headFirst.1.cardIDs,
            [LocalSliceFixture.cardID(LocalSliceFixture.candidate(LocalSliceFixture.revision(4)))])
        headReadiness.record(skipped.id, nil, textDeclared: true)
        let headStore = PublicationStore(database: head.database)
        let headLater = try published(headSlice.run(
            head.request(capacity: 2, after: headFirst.0.nextCursor, segment: 44001)) { LocalSliceFixture.prepared($0) })
        XCTAssertEqual(try headLater.1.cardIDs.map { try XCTUnwrap(headStore.card(id: $0)).originRevisionID },
            [3, 2].map { LocalSliceFixture.revision($0).id })
        XCTAssertNil(try headStore.card(id: skippedCard),
            "HEAD behaviour: readiness cannot bring back a story the one-way walk already passed")

        // With the queue: the same skip, the same cursor, and the story is published by the later opportunity.
        let queued = try fixture(initial: [LocalSliceFixture.revision(1)])
        try admitSupply(queued)
        let readiness = MediaReadiness()
        recordReady(readiness, [1, 2, 3, 4])
        let reoffer = PendingMediaReconsideration()
        let slice = LocalProductionSlice(database: queued.database, readiness: readiness, reoffer: reoffer)
        let first = try published(slice.run(queued.request(capacity: 2)) { LocalSliceFixture.prepared($0) })
        XCTAssertEqual(first.1.cardIDs,
            [LocalSliceFixture.cardID(LocalSliceFixture.candidate(LocalSliceFixture.revision(4)))])
        XCTAssertNil(try PublicationStore(database: queued.database).card(id: skippedCard))
        XCTAssertEqual(reoffer.count, 1, "the skip is remembered instead of being lost with the cursor")
        let store = PublicationStore(database: queued.database)
        let beforeIDs = try store.segments(editionID: queued.editionID).flatMap(\.cardIDs)
        let beforeCards = try beforeIDs.map { try XCTUnwrap(store.card(id: $0)) }

        // The transition: the media fact the queue was waiting for.
        readiness.record(skipped.id, nil, textDeclared: true)
        let cursor = first.0.nextCursor
        let window = try CandidateProvider(contentStore: ContentStore(database: queued.database))
            .candidates(for: queued.plan, after: cursor, examinedCapacity: 2)
        let later = try published(slice.run(
            queued.request(capacity: 2, after: cursor, segment: 44001)) { LocalSliceFixture.prepared($0) })
        XCTAssertEqual(later.0, LocalProductionProgress(examinedCount: window.examinedCount,
            nextCursor: window.nextCursor, exhausted: window.exhausted),
            "the reconsidered story never moves the structural cursor")
        XCTAssertEqual(try later.1.cardIDs.map { try XCTUnwrap(store.card(id: $0)).originRevisionID },
            [6, 3, 2].map { LocalSliceFixture.revision($0).id },
            "the skipped story is published by a later opportunity")
        XCTAssertEqual(try store.segments(editionID: queued.editionID).flatMap(\.cardIDs),
            beforeIDs + later.1.cardIDs, "publication only extends the Edition")
        XCTAssertEqual(try beforeIDs.map { try XCTUnwrap(store.card(id: $0)) }, beforeCards,
            "an already-published card is never rewritten")
        XCTAssertEqual(reoffer.count, 0, "the opportunity settled the skip")
    }

    /// PD-1 and the queue's own contract: finite, and an entry that can no longer be published leaves the queue
    /// instead of being carried into every later opportunity.
    func testReofferQueueIsBoundedAndDropsPublishedExpiredAndForeignEditionEntries() throws {
        // Bound, stated by the value itself: the oldest skip is the one the ceiling gives up.
        let queue = PendingMediaReconsideration(ceiling: 3)
        let editionA = FeedEditionID(), editionB = FeedEditionID()
        for n in 1...4 {
            let revision = LocalSliceFixture.revision(n)
            queue.remember(.init(editionID: editionA, originRecordID: revision.originRecordID,
                originRevisionID: revision.id))
        }
        XCTAssertEqual(queue.count, 3)
        XCTAssertEqual(queue.entries(for: editionA).map(\.originRevisionID),
            [2, 3, 4].map { LocalSliceFixture.revision($0).id })
        // An Edition whose walk this process no longer serves cannot publish its entries.
        let foreign = LocalSliceFixture.revision(5)
        queue.remember(.init(editionID: editionB, originRecordID: foreign.originRecordID,
            originRevisionID: foreign.id))
        XCTAssertEqual(queue.count, 1, "the previous Edition's entries are dead weight, not a second bound")
        XCTAssertEqual(queue.entries(for: editionB).map(\.originRevisionID), [foreign.id])
        XCTAssertTrue(queue.entries(for: editionA).isEmpty,
            "another Edition's entries are discarded, never offered")

        // Published and expired, through the slice that owns the offer.
        let f = try fixture(initial: [LocalSliceFixture.revision(1)])
        let publishedElsewhere = LocalSliceFixture.revision(6)
        let expired = LocalSliceFixture.revision(7)
        try f.admit(expired); try f.admit(publishedElsewhere)
        let readiness = MediaReadiness()
        readiness.record(LocalSliceFixture.revision(1).id, nil, textDeclared: true)
        let reoffer = PendingMediaReconsideration()
        let slice = LocalProductionSlice(database: f.database, readiness: readiness, reoffer: reoffer)
        let first = try slice.run(f.request(capacity: 2)) { _ in throw PreparationFailure.refused }
        guard case .advancedWithoutPublication = first else {
            return XCTFail("both stories are pending, so nothing can be published")
        }
        XCTAssertEqual(reoffer.count, 2)

        // 6 is published by another owner of this Edition; 7's revision is replaced, so the queued revision (and the
        // readiness fact about it) can never become a card.
        try f.externalAppend(publishedElsewhere)
        let expiredCard = LocalSliceFixture.cardID(LocalSliceFixture.candidate(expired))
        let replacement = OriginRevision(id: OriginRevisionID(),
            originRecordID: expired.originRecordID, externalVersionIdentity: nil, headline: "Replaced",
            summary: "Replaced", bodyText: nil, authoredAt: expired.authoredAt, modifiedAt: nil,
            observedAt: expired.observedAt, language: nil, primaryLink: nil, searchProjection: nil,
            providerID: nil)
        try f.admit(replacement, previous: expired.id)
        readiness.record(publishedElsewhere.id, nil, textDeclared: true)
        readiness.record(expired.id, nil, textDeclared: true)

        let store = PublicationStore(database: f.database)
        let beforeIDs = try store.segments(editionID: f.editionID).flatMap(\.cardIDs)
        // The queue is the only supply of this opportunity: the cursor is past every story in it.
        let past = CandidateSupplyCursor(sortDate: Date(timeIntervalSince1970: 0), originRecordID: OriginRecordID())
        let outcome = try slice.run(f.request(capacity: 2, after: past, segment: 44002)) {
            LocalSliceFixture.prepared($0)
        }
        guard case .advancedWithoutPublication = outcome else {
            return XCTFail("neither a published nor a superseded skip may become a card")
        }
        XCTAssertEqual(reoffer.count, 0, "published and expired skips are dropped")
        XCTAssertEqual(try store.segments(editionID: f.editionID).flatMap(\.cardIDs), beforeIDs)
        XCTAssertNil(try store.card(id: expiredCard))
        XCTAssertEqual(try store.card(id: LocalSliceFixture.cardID(
            LocalSliceFixture.candidate(publishedElsewhere)))?.originRevisionID, publishedElsewhere.id,
            "the published card is the one another owner froze, not a second occurrence")
    }
}
