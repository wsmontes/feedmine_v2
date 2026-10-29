import Foundation
import XCTest
import GRDB
import FeedMineDomain
import FeedMineEditorial
import FeedMineMedia
@testable import FeedMinePersistence
@testable import FeedMinePublication

final class PublicationCoordinatorTests: XCTestCase {
    private typealias Create = PublicationCoordinator.CreateRequest
    private typealias Append = PublicationCoordinator.AppendRequest
    private let editionDate = Date(timeIntervalSince1970: 123.25)
    private let segmentDate = Date(timeIntervalSince1970: 124.5)
    private func uuid(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", number))!
    }
    private func withLocation(_ body: (RuntimeDatabaseLocation) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(RuntimeDatabaseLocation(directory: root))
    }
    private func revision(policy: UInt64 = 1) -> EditorialRevision {
        EditorialRevision(id: EditorialRevisionID(rawValue: uuid(800)), contextKey: ContextKey(request: .main),
            catalogGeneration: CatalogGeneration(rawValue: 2), userSelectionVersion: PolicyVersion(rawValue: policy),
            eligibilityPolicyVersion: PolicyVersion(rawValue: 3), scoringPolicyVersion: PolicyVersion(rawValue: 4),
            sequencingPolicyVersion: PolicyVersion(rawValue: 5), exposurePolicyVersion: PolicyVersion(rawValue: 6),
            selectionSchemaVersion: SelectionSchemaVersion(rawValue: 7))
    }
    private func candidate(_ index: Int) -> Candidate {
        Candidate(originRecordID: OriginRecordID(rawValue: uuid(index)), originRevisionID: OriginRevisionID(rawValue: uuid(100 + index)),
            headline: index == 1 ? nil : index == 2 ? "" : "Title \(index)", summary: "summary \(index)",
            timestamp: CandidateTimestamp(value: Date(timeIntervalSince1970: Double(100 + index)), kind: index % 2 == 0 ? .observed : .authored),
            language: "pt-BR", providerID: ProviderID(rawValue: uuid(500 + index)))
    }
    private func selection(_ candidates: [Candidate], revision: EditorialRevision? = nil,
        report: SelectionSupplyReport? = nil) -> SelectionResult {
        SelectionResult(editorialRevision: revision ?? self.revision(), orderedCandidates: candidates,
            supplyReport: report ?? SelectionSupplyReport(examinedCount: 53,
                nextCursor: CandidateSupplyCursor(sortDate: segmentDate, originRecordID: OriginRecordID(rawValue: uuid(99))), exhausted: false))
    }
    private func draft(_ candidate: Candidate, sourceName: String = "Frozen Source",
        providerName: String? = "Frozen Provider", action: PublishedPrimaryAction? = nil,
        mismatch: String? = nil) throws -> PublicationCardDraft {
        try XCTUnwrap(PublicationCardDraft(origin: PublishedOrigin(
            originRecordID: mismatch == "origin" ? OriginRecordID(rawValue: uuid(999)) : candidate.originRecordID,
            originRevisionID: mismatch == "revision" ? OriginRevisionID(rawValue: uuid(999)) : candidate.originRevisionID,
            sourceID: SourceID(rawValue: uuid(400)),
            providerID: mismatch == "provider" ? ProviderID(rawValue: uuid(999)) : candidate.providerID,
            sourceDisplayName: sourceName, providerDisplayName: providerName),
            contentEntityID: ContentEntityID(rawValue: uuid(600)), contentClusterID: ContentClusterID(rawValue: uuid(700)),
            text: PublishedText(title: mismatch == "title" ? "" : candidate.headline,
                primaryText: mismatch == "summary" ? nil : candidate.summary),
            timestamp: mismatch == "nilTime" ? nil : PublishedTimestamp(
                value: mismatch == "time" ? candidate.timestamp.value.addingTimeInterval(1) : candidate.timestamp.value,
                kind: mismatch == "kind" ? .authored : candidate.timestamp.kind == .authored ? .authored : .observed),
            media: .none, renderContract: XCTUnwrap(RenderContract(layout: .textOnly, mediaAspectRatio: nil)), primaryAction: action))
    }
    private func create(_ candidates: [Candidate], drafts: [PublicationCardDraft]? = nil,
        ids: [PublicationCardID]? = nil, edition: Int = 900, segment: Int = 1000,
        report: SelectionSupplyReport? = nil, expectedSourceExclusions: ReaderSourceExclusionSnapshot? = nil,
        expectedWordExclusions: ReaderWordExclusionSnapshot? = nil,
        bindingPublication: PublicationStore.BindingPublicationExpectation? = nil) throws -> Create {
        Create(selection: selection(candidates, report: report), drafts: try drafts ?? candidates.map { try draft($0) },
            editionID: FeedEditionID(rawValue: uuid(edition)), publicationSchemaVersion: PublicationSchemaVersion(rawValue: 17),
            selectionSeed: UInt64.max, editionCreatedAt: editionDate, segmentID: FeedSegmentID(rawValue: uuid(segment)),
            segmentSeed: 42, segmentCreatedAt: segmentDate,
            cardIDs: ids ?? candidates.indices.map { PublicationCardID(rawValue: uuid(2000 + $0)) },
            expectedSourceExclusions: expectedSourceExclusions, expectedWordExclusions: expectedWordExclusions, bindingPublication: bindingPublication)
    }
    private func append(_ candidates: [Candidate], target: FeedEditionID, segment: Int,
        ids: [PublicationCardID], drafts: [PublicationCardDraft]? = nil, revision: EditorialRevision? = nil,
        expectedSourceExclusions: ReaderSourceExclusionSnapshot? = nil,
        expectedWordExclusions: ReaderWordExclusionSnapshot? = nil,
        bindingActivation: SessionStore.BindingActivation? = nil) throws -> Append {
        Append(selection: selection(candidates, revision: revision), drafts: try drafts ?? candidates.map { try draft($0) },
            editionID: target, segmentID: FeedSegmentID(rawValue: uuid(segment)), segmentSeed: 77,
            segmentCreatedAt: segmentDate.addingTimeInterval(1), cardIDs: ids,
            expectedSourceExclusions: expectedSourceExclusions, expectedWordExclusions: expectedWordExclusions, bindingActivation: bindingActivation)
    }
    private func frozen(_ draft: PublicationCardDraft, id: PublicationCardID) throws -> PublishedCard {
        try XCTUnwrap(PublishedCard(id: id, origin: draft.origin, contentEntityID: draft.contentEntityID,
            contentClusterID: draft.contentClusterID, text: draft.text, timestamp: draft.timestamp,
            media: draft.media, renderContract: draft.renderContract, primaryAction: draft.primaryAction))
    }
    private func receipt(_ outcome: PublicationOutcome) throws -> PublicationReceipt {
        let value: PublicationReceipt?
        switch outcome { case .published(let receipt): value = receipt; case .nothingToPublish: value = nil }
        return try XCTUnwrap(value)
    }
    private func counts(_ database: RuntimeDatabase) throws -> [Int] {
        try database.read { db in
            try ["feed_editions", "feed_segments", "published_cards"].map {
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \($0)")!
            }
        }
    }
    private func assertError(_ expected: PublicationCoordinatorError, _ body: () throws -> PublicationOutcome,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { XCTAssertEqual($0 as? PublicationCoordinatorError, expected, file: file, line: line) }
    }

    func testCreatePreservesExplicitMaterialOrderAndTextOnlyPayloadExactly() throws {
        try withLocation { location in
            let db = try RuntimeDatabase(location: location), store = PublicationStore(database: db)
            let input = try create([candidate(3), candidate(1), candidate(2)]) // Preserve intent, never sort.
            let r = try receipt(PublicationCoordinator(database: db).createEdition(input))
            XCTAssertEqual(r.editionID, input.editionID)
            XCTAssertEqual(r.segmentID, input.segmentID)
            XCTAssertEqual(r.segmentOrdinal, 0)
            XCTAssertEqual(r.cardIDs, input.cardIDs)
            let expectedEdition = FeedEdition(id: input.editionID, editorialRevision: input.selection.editorialRevision,
                publicationSchemaVersion: input.publicationSchemaVersion, selectionSeed: input.selectionSeed, createdAt: input.editionCreatedAt)
            XCTAssertEqual(try PublicationPersistenceMapping.edition(XCTUnwrap(store.edition(id: input.editionID))), expectedEdition)
            let expectedSegment = try XCTUnwrap(FeedSegment(id: input.segmentID, editionID: input.editionID, ordinal: 0,
                segmentSeed: input.segmentSeed, publicationSchemaVersion: input.publicationSchemaVersion,
                createdAt: input.segmentCreatedAt, cardIDs: input.cardIDs))
            XCTAssertEqual(try store.segments(editionID: input.editionID).map(PublicationPersistenceMapping.segment), [expectedSegment])
            for i in input.cardIDs.indices {
                XCTAssertEqual(try PublicationPersistenceMapping.card(XCTUnwrap(store.card(id: input.cardIDs[i]))), try frozen(input.drafts[i], id: input.cardIDs[i]))
            }
            XCTAssertEqual(try counts(db), [1, 1, 3])
        }
    }

    func testDraftRejectsTextOnlyWithPrimaryMedia() throws {
        let c = candidate(1), prepared = try draft(c)
        let reference = try XCTUnwrap(PublishedMediaRef(key: XCTUnwrap(PublishedMediaKey(rawValue: "durable-key")), pixelWidth: 10, pixelHeight: 10, mimeType: nil))
        XCTAssertNil(PublicationCardDraft(origin: prepared.origin, contentEntityID: nil, contentClusterID: nil,
            text: prepared.text, timestamp: prepared.timestamp, media: PublishedMediaSet(primary: reference),
            renderContract: prepared.renderContract, primaryAction: nil))
    }

    func testEmptyCreateAndAppendWriteNothingEvenForMissingTarget() throws {
        try withLocation { location in
            let db = try RuntimeDatabase(location: location), coordinator = PublicationCoordinator(database: db)
            XCTAssertEqual(try coordinator.createEdition(create([])), .nothingToPublish)
            XCTAssertEqual(try coordinator.append(append([], target: FeedEditionID(rawValue: uuid(900)), segment: 1000, ids: [])), .nothingToPublish)
            XCTAssertEqual(try counts(db), [0, 0, 0])
        }
    }

    func testShortSelectionPublishesExactlyOne() throws {
        try withLocation { location in
            let db = try RuntimeDatabase(location: location)
            let r = try receipt(PublicationCoordinator(database: db).createEdition(create([candidate(1)])))
            XCTAssertEqual(r.cardIDs.count, 1)
            XCTAssertEqual(try counts(db), [1, 1, 1])
        }
    }

    func testCountsAndDuplicateCardIDsRejectedBeforeWrites() throws {
        try withLocation { location in
            let db = try RuntimeDatabase(location: location), coordinator = PublicationCoordinator(database: db)
            let candidates = [candidate(1), candidate(2)]
            for request in [try create(candidates, drafts: []), try create(candidates, ids: []), try create([], drafts: [draft(candidate(1))])] {
                assertError(.inputCountMismatch) { try coordinator.createEdition(request) }
            }
            let id = PublicationCardID(rawValue: uuid(2000))
            assertError(.duplicatePublicationCardID) { try coordinator.createEdition(create(candidates, ids: [id, id])) }
            assertError(.inputCountMismatch) { try coordinator.append(append(candidates, target: FeedEditionID(rawValue: uuid(900)), segment: 1000, ids: [])) }
            XCTAssertEqual(try counts(db), [0, 0, 0])
        }
    }

    func testPositionalOriginRevisionTextProviderAndTimestampMismatchRejectsWrites() throws {
        try withLocation { location in
            let db = try RuntimeDatabase(location: location), coordinator = PublicationCoordinator(database: db)
            for mismatch in ["origin", "revision", "title", "summary", "provider", "kind", "time", "nilTime"] {
                let c = candidate(mismatch == "kind" ? 2 : 1)
                let bad = try draft(c, mismatch: mismatch)
                assertError(.draftCandidateMismatch(index: 1)) {
                    try coordinator.createEdition(create([candidate(3), c], drafts: [draft(candidate(3)), bad]))
                }
            }
            XCTAssertEqual(try counts(db), [0, 0, 0])
        }
    }

    func testLateCardCollisionRollsBackNewEditionSegmentAndEarlierInsertedCard() throws {
        try withLocation { location in
            let db = try RuntimeDatabase(location: location), store = PublicationStore(database: db), coordinator = PublicationCoordinator(database: db)
            let first = try create([candidate(1)])
            _ = try coordinator.createEdition(first)
            let x = try XCTUnwrap(store.card(id: first.cardIDs[0]))
            let y = PublicationCardID(rawValue: uuid(2500))
            let second = try create([candidate(2), candidate(1)], ids: [y, first.cardIDs[0]], edition: 901, segment: 1001)
            XCTAssertThrowsError(try coordinator.createEdition(second)) { error in
                guard case RuntimeDatabaseError.storage = error else { return XCTFail("Expected factual storage failure: \(error)") }
            }
            XCTAssertNil(try store.edition(id: second.editionID))
            XCTAssertNil(try store.card(id: y))
            XCTAssertEqual(try store.card(id: first.cardIDs[0]), x)
            XCTAssertEqual(try store.edition(id: first.editionID), PublicationPersistenceMapping.record(
                FeedEdition(id: first.editionID, editorialRevision: first.selection.editorialRevision,
                    publicationSchemaVersion: first.publicationSchemaVersion, selectionSeed: first.selectionSeed, createdAt: first.editionCreatedAt)))
            XCTAssertEqual(try counts(db), [1, 1, 1])
        }
    }

    func testAppendOrdinalsSchemaOrderAndReopenExactHistory() throws {
        try withLocation { location in
            let first = try create([candidate(3), candidate(1)])
            let second = try append([candidate(2), candidate(4)], target: first.editionID, segment: 1001,
                ids: [PublicationCardID(rawValue: uuid(2100)), PublicationCardID(rawValue: uuid(2101))])
            let third = try append([candidate(5)], target: first.editionID, segment: 1002, ids: [PublicationCardID(rawValue: uuid(2200))])
            do {
                let db = try RuntimeDatabase(location: location), coordinator = PublicationCoordinator(database: db)
                _ = try coordinator.createEdition(first)
                XCTAssertEqual(try receipt(coordinator.append(second)).segmentOrdinal, 1)
                XCTAssertEqual(try receipt(coordinator.append(third)).segmentOrdinal, 2)
            }
            let db = try RuntimeDatabase(location: location), store = PublicationStore(database: db)
            let edition = try PublicationPersistenceMapping.edition(XCTUnwrap(store.edition(id: first.editionID)))
            XCTAssertEqual(edition, FeedEdition(id: first.editionID, editorialRevision: first.selection.editorialRevision,
                publicationSchemaVersion: first.publicationSchemaVersion, selectionSeed: first.selectionSeed, createdAt: first.editionCreatedAt))
            let segments = try store.segments(editionID: first.editionID).map(PublicationPersistenceMapping.segment)
            XCTAssertEqual(segments.map(\.ordinal), [0, 1, 2])
            XCTAssertEqual(segments.map(\.publicationSchemaVersion), Array(repeating: first.publicationSchemaVersion, count: 3))
            XCTAssertEqual(segments.map(\.cardIDs), [first.cardIDs, second.cardIDs, third.cardIDs])
            XCTAssertEqual(segments.map(\.id), [first.segmentID, second.segmentID, third.segmentID])
            XCTAssertEqual(segments.map(\.segmentSeed), [42, 77, 77])
            XCTAssertEqual(segments.map(\.createdAt), [first.segmentCreatedAt, second.segmentCreatedAt, third.segmentCreatedAt])
            let drafts = first.drafts + second.drafts + third.drafts, ids = first.cardIDs + second.cardIDs + third.cardIDs
            for i in ids.indices {
                XCTAssertEqual(try PublicationPersistenceMapping.card(XCTUnwrap(store.card(id: ids[i]))), try frozen(drafts[i], id: ids[i]))
            }
            XCTAssertEqual(try counts(db), [1, 3, 5])
        }
    }

    func testAppendRevisionMismatchAndMissingTargetDoNotWrite() throws {
        try withLocation { location in
            let db = try RuntimeDatabase(location: location), store = PublicationStore(database: db), coordinator = PublicationCoordinator(database: db)
            let first = try create([candidate(1)]), id = PublicationCardID(rawValue: uuid(2100))
            _ = try coordinator.createEdition(first)
            assertError(.editorialRevisionMismatch) {
                try coordinator.append(append([candidate(2)], target: first.editionID, segment: 1001, ids: [id], revision: revision(policy: 99)))
            }
            assertError(.missingEdition) {
                try coordinator.append(append([candidate(2)], target: FeedEditionID(rawValue: uuid(999)), segment: 1001, ids: [id]))
            }
            XCTAssertEqual(try store.tail(editionID: first.editionID).ordinal, 0)
            XCTAssertNil(try store.card(id: id))
            XCTAssertEqual(try counts(db), [1, 1, 1])
        }
    }

    func testAnotherEditionChangesEnrichmentWithoutMutatingOldCard() throws {
        try withLocation { location in
            let db = try RuntimeDatabase(location: location), store = PublicationStore(database: db), coordinator = PublicationCoordinator(database: db)
            let c = candidate(1), first = try create([c])
            _ = try coordinator.createEdition(first)
            let old = try PublicationPersistenceMapping.card(XCTUnwrap(store.card(id: first.cardIDs[0])))
            let later = try draft(c, sourceName: "New source name", providerName: "New provider name", action: .localContentDetail)
            let id = PublicationCardID(rawValue: uuid(2100))
            let second = try create([c], drafts: [later], ids: [id], edition: 901, segment: 1001)
            _ = try coordinator.createEdition(second)
            XCTAssertNotEqual(first.editionID, second.editionID)
            XCTAssertEqual(try store.segments(editionID: first.editionID).flatMap(\.cardIDs).count, 1)
            XCTAssertEqual(try store.segments(editionID: second.editionID).flatMap(\.cardIDs).count, 1)
            XCTAssertEqual(try PublicationPersistenceMapping.card(XCTUnwrap(store.card(id: first.cardIDs[0]))), old)
            let new = try PublicationPersistenceMapping.card(XCTUnwrap(store.card(id: id)))
            XCTAssertEqual(new, try frozen(later, id: id))
            XCTAssertNotEqual(new, old)
        }
    }

    func testSupplyReportDoesNotAffectFrozenHistory() throws {
        let candidates = [candidate(1), candidate(2)], first = try create(candidates)
        let changed = try create(candidates, report: SelectionSupplyReport(examinedCount: 2, nextCursor: nil, exhausted: true))
        var baseline: [PublicationStore.CardRecord] = []
        try withLocation { location in
            let db = try RuntimeDatabase(location: location), store = PublicationStore(database: db)
            _ = try PublicationCoordinator(database: db).createEdition(first)
            baseline = try first.cardIDs.map { try XCTUnwrap(store.card(id: $0)) }
        }
        try withLocation { location in
            let db = try RuntimeDatabase(location: location), store = PublicationStore(database: db)
            _ = try PublicationCoordinator(database: db).createEdition(changed)
            XCTAssertEqual(try changed.cardIDs.map { try XCTUnwrap(store.card(id: $0)) }, baseline)
        }
    }
    func testExpectedTailAppendSuccessAndStaleRefusalPropagatesWithoutRetry() throws {
        try withLocation { location in
            let db = try RuntimeDatabase(location: location), coordinator = PublicationCoordinator(database: db)
            let initial = try create([candidate(1)])
            let first = try receipt(coordinator.createEdition(initial))
            let b = PublicationCardID(rawValue: uuid(3001)), c = PublicationCardID(rawValue: uuid(3002))
            let second = try receipt(coordinator.append(append([candidate(2)],target: initial.editionID,segment: 1001,ids: [b]),expectingTailCardID: first.cardIDs[0]))
            XCTAssertEqual(second.segmentOrdinal,1)
            let stale = try append([candidate(3)],target: initial.editionID,segment: 1002,ids: [c])
            XCTAssertThrowsError(try coordinator.append(stale,expectingTailCardID: first.cardIDs[0])) { XCTAssertEqual($0 as? PublicationStoreError,.staleHistoryExpectation) }
            let store = PublicationStore(database: db)
            XCTAssertNil(try store.card(id: c)); XCTAssertNotNil(try store.card(id: b))
            XCTAssertEqual(try store.tail(editionID: initial.editionID).ordinal,1)
            XCTAssertFalse(try store.segments(editionID: initial.editionID).contains { $0.id == stale.segmentID })
        }
    }

}

extension PublicationCoordinatorTests {
    func test3R5DelayedConcurrentAppendMustNotRepublishSameOrigin() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try RuntimeDatabase(location: .init(directory: root))
        let coordinator = PublicationCoordinator(database: database)
        let initial = try create([candidate(3)])
        _ = try coordinator.createEdition(initial)
        let first = candidate(1)
        let edited = Candidate(originRecordID: first.originRecordID, originRevisionID: OriginRevisionID(),
            headline: "Edited", summary: first.summary, timestamp: first.timestamp,
            language: first.language, providerID: first.providerID)
        // Both callers observe no exposure before either publishes this origin.
        let facts = try PublicationHistory(database: database).exposure(editionID: initial.editionID,
            originIDs: [first.originRecordID])
        XCTAssertTrue(facts.publishedOriginIDs.isEmpty)
        let requestA = try append([first], target: initial.editionID, segment: 1101,
            ids: [PublicationCardID(rawValue: uuid(2101))])
        let requestB = try append([edited], target: initial.editionID, segment: 1102,
            ids: [PublicationCardID(rawValue: uuid(2102))])
        let (ready, announce) = AsyncStream<Void>.makeStream()
        let (release, resume) = AsyncStream<Void>.makeStream()
        let delayed = Task {
            announce.yield(())
            for await _ in release { break }
            // This public overload has no expectation tied to B's original exposure.
            return try coordinator.append(requestB)
        }
        for await _ in ready { break }
        _ = try coordinator.append(requestA)
        resume.yield(())
        do { _ = try await delayed.value; XCTFail("Delayed duplicate must be rejected") }
        catch { XCTAssertEqual(error as? PublicationStoreError, .duplicateOriginInEdition) }
        let count = try database.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM published_cards c JOIN feed_segments s ON s.id = c.segment_id
                WHERE s.edition_id = ? AND c.origin_record_id = ?
                """, arguments: [initial.editionID.rawValue.uuidString.lowercased(), first.originRecordID.rawValue.uuidString.lowercased()])!
        }
        print("3R5 P15: occurrencesForSameOrigin=\(count), segments=\(try PublicationStore(database: database).segments(editionID: initial.editionID).count)")
        XCTAssertEqual(count, 1, "Publication authority must reject the delayed duplicate origin regardless of revision")
    }
}


extension PublicationCoordinatorTests {
    func testSourceExclusionExpectationReachesEveryWriter() throws {
        for initial in [false, true] {
            try withLocation { location in
                let db = try RuntimeDatabase(location: location)
                let prefs = ReaderPreferencesStore(database: db)
                _ = try prefs.initialize(sourceKeys: ["a"])
                let expected = try prefs.sourceExclusionSnapshot()
                let request = try create([candidate(3)], expectedSourceExclusions: expected)
                var settings = try XCTUnwrap(prefs.load()).settings
                settings.contentSourceExclusions = [.init(sourceID: SourceID(), displayName: "Blocked")]
                _ = try prefs.setSettings(settings)
                let coordinator = PublicationCoordinator(database: db)
                XCTAssertThrowsError(try {
                    if initial {
                        return try coordinator.createInitialEdition(.init(publication: request,
                            anchorPlacement: .top, checkpointedAt: self.segmentDate))
                    }
                    return try coordinator.createEdition(request)
                }()) { XCTAssertEqual($0 as? PublicationStoreError, .staleSourceExclusions) }
                XCTAssertNil(try PublicationStore(database: db).edition(id: request.editionID))
                XCTAssertNil(try SessionStore(database: db).checkpoint())
            }
        }
        try withLocation { location in
            let db = try RuntimeDatabase(location: location)
            let prefs = ReaderPreferencesStore(database: db)
            _ = try prefs.initialize(sourceKeys: ["a"])
            let coordinator = PublicationCoordinator(database: db)
            let first = try create([candidate(3)])
            _ = try coordinator.createEdition(first)
            let nextID = PublicationCardID()
            let next = try append([candidate(4)], target: first.editionID, segment: 1100, ids: [nextID],
                expectedSourceExclusions: prefs.sourceExclusionSnapshot())
            var settings = try XCTUnwrap(prefs.load()).settings
            settings.contentSourceExclusions = [.init(sourceID: SourceID(), displayName: "Blocked")]
            _ = try prefs.setSettings(settings)
            XCTAssertThrowsError(try coordinator.append(next)) {
                XCTAssertEqual($0 as? PublicationStoreError, .staleSourceExclusions)
            }
            XCTAssertThrowsError(try coordinator.append(next, expectingTailCardID: first.cardIDs[0])) {
                XCTAssertEqual($0 as? PublicationStoreError, .staleSourceExclusions)
            }
            XCTAssertEqual(try PublicationStore(database: db).segments(editionID: first.editionID).count, 1)
            XCTAssertNil(try PublicationStore(database: db).card(id: nextID))
        }
    }
}

extension PublicationCoordinatorTests {
    func testWordExclusionExpectationReachesEveryWriter() throws {
        for initial in [false, true] {
            try withLocation { location in
                let db = try RuntimeDatabase(location: location)
                let prefs = ReaderPreferencesStore(database: db)
                _ = try prefs.initialize(sourceKeys: ["a"])
                let expected = try prefs.wordExclusionSnapshot(templates: [])
                let request = try create([candidate(3)], expectedWordExclusions: expected)
                var settings = try XCTUnwrap(prefs.load()).settings
                settings.contentFilterRules = ["blocked"]
                _ = try prefs.setSettings(settings)
                let coordinator = PublicationCoordinator(database: db)
                XCTAssertThrowsError(try {
                    if initial {
                        return try coordinator.createInitialEdition(.init(publication: request,
                            anchorPlacement: .top, checkpointedAt: self.segmentDate))
                    }
                    return try coordinator.createEdition(request)
                }()) { XCTAssertEqual($0 as? PublicationStoreError, .staleWordExclusions) }
                XCTAssertNil(try PublicationStore(database: db).edition(id: request.editionID))
                XCTAssertNil(try SessionStore(database: db).checkpoint())
            }
        }
        try withLocation { location in
            let db = try RuntimeDatabase(location: location)
            let prefs = ReaderPreferencesStore(database: db)
            _ = try prefs.initialize(sourceKeys: ["a"])
            let coordinator = PublicationCoordinator(database: db)
            let first = try create([candidate(3)])
            _ = try coordinator.createEdition(first)
            let nextID = PublicationCardID()
            let next = try append([candidate(4)], target: first.editionID, segment: 1100, ids: [nextID],
                expectedWordExclusions: prefs.wordExclusionSnapshot(templates: []))
            var settings = try XCTUnwrap(prefs.load()).settings
            settings.contentFilterRules = ["blocked"]
            _ = try prefs.setSettings(settings)
            XCTAssertThrowsError(try coordinator.append(next)) {
                XCTAssertEqual($0 as? PublicationStoreError, .staleWordExclusions)
            }
            XCTAssertThrowsError(try coordinator.append(next, expectingTailCardID: first.cardIDs[0])) {
                XCTAssertEqual($0 as? PublicationStoreError, .staleWordExclusions)
            }
            XCTAssertEqual(try PublicationStore(database: db).segments(editionID: first.editionID).count, 1)
            XCTAssertNil(try PublicationStore(database: db).card(id: nextID))
        }
    }
}

extension PublicationCoordinatorTests {
    func testOwnedExpectationReachesFirstAndInitialWritersWithoutRetakingActivation() throws {
        for initial in [false, true] {
            for stale in [false, true] {
                try withLocation { location in
                    let db = try RuntimeDatabase(location: location), session = SessionStore(database: db)
                    let bindings = ReaderHistoryBindingStore(database: db), key = ContextKey(request: .main)
                    let binding = try bindings.resolve(logicalKey: key), activation = try session.activateBinding(binding.id)
                    let request = try create([candidate(3)], bindingPublication: .init(activation: activation))
                    if stale { _ = try session.activateBinding(binding.id) }
                    let coordinator = PublicationCoordinator(database: db)
                    let publish = {
                        if initial { return try coordinator.createInitialEdition(.init(publication: request,
                            anchorPlacement: .top, checkpointedAt: self.segmentDate)) }
                        return try coordinator.createEdition(request)
                    }
                    if stale {
                        XCTAssertThrowsError(try publish()) {
                            XCTAssertEqual($0 as? SessionStoreError, .staleHistoryBinding)
                        }
                        XCTAssertNil(try PublicationStore(database: db).edition(id: request.editionID))
                        XCTAssertNil(try bindings.binding(for: key)?.activeEditionID)
                    } else {
                        XCTAssertEqual(try receipt(publish()).editionID, request.editionID)
                        XCTAssertEqual(try bindings.binding(for: key)?.activeEditionID, request.editionID)
                        XCTAssertEqual(try session.checkpoint(bindingID: binding.id)?.editionID,
                            initial ? request.editionID : nil)
                    }
                }
            }
        }
    }

    func testOwnedActivationReachesBothAppendWritersAndRejectsRetiredRequests() throws {
        for tailChecked in [false, true] {
            try withLocation { location in
                let db = try RuntimeDatabase(location: location), session = SessionStore(database: db)
                let binding = try ReaderHistoryBindingStore(database: db).resolve(logicalKey: ContextKey(request: .main))
                let old = try session.activateBinding(binding.id), coordinator = PublicationCoordinator(database: db)
                let first = try create([candidate(3)], bindingPublication: .init(activation: old))
                _ = try coordinator.createInitialEdition(.init(publication: first, anchorPlacement: .top, checkpointedAt: segmentDate))
                let checkpoint = try session.checkpoint(), current = try session.activateBinding(binding.id)
                let nextID = PublicationCardID()
                let stale = try append([candidate(4)], target: first.editionID, segment: 1100,
                    ids: [nextID], bindingActivation: old)
                let publish = { (request: Append) in
                    if tailChecked { return try coordinator.append(request, expectingTailCardID: first.cardIDs[0]) }
                    return try coordinator.append(request)
                }
                XCTAssertThrowsError(try publish(stale)) { XCTAssertEqual($0 as? SessionStoreError, .staleHistoryBinding) }
                XCTAssertNil(try PublicationStore(database: db).card(id: nextID))
                let fresh = try append([candidate(4)], target: first.editionID, segment: 1100,
                    ids: [nextID], bindingActivation: current)
                _ = try receipt(publish(fresh))
                XCTAssertEqual(try PublicationStore(database: db).segments(editionID: first.editionID).count, 2)
                XCTAssertEqual(try session.checkpoint(), checkpoint)
            }
        }
    }
}
