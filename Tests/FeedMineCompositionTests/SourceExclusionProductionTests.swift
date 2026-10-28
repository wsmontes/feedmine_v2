import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineEditorial
import FeedMinePublication
@testable import FeedMineRuntime
import FeedMineComposition

private struct ExclusionProductionFixture: Sendable {
    let database: RuntimeDatabase
    let directory: URL
    let a = SourceID(), b = SourceID()
    let editionID = FeedEditionID()
    let plan: FeedPlan
    let policy: ResolvedSelectionPolicy

    init(_ test: XCTestCase, sequencingVersion: UInt64 = 1,
        sequencing: ResolvedSelectionPolicy.SequencingBehavior = .recencyDescending,
        filter: ReaderFilter = .unrestricted) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = directory
        test.addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        database = try RuntimeDatabase(location: .init(directory: directory))
        _ = try ReaderPreferencesStore(database: database).initialize(sourceKeys: ["a", "b"])
        let context = FeedContext(key: ContextKey(request: .main, filter: filter)), version = PolicyVersion(rawValue: 1)
        let revision = EditorialRevision(id: EditorialRevisionID(), contextKey: context.key,
            catalogGeneration: .init(rawValue: 1), userSelectionVersion: version,
            eligibilityPolicyVersion: version, scoringPolicyVersion: version, sequencingPolicyVersion: .init(rawValue: sequencingVersion),
            exposurePolicyVersion: version, selectionSchemaVersion: .init(rawValue: 1))
        plan = FeedPlan(context: context, revision: revision)!
        policy = ResolvedSelectionPolicy(contextKey: context.key, userSelectionVersion: version,
            eligibilityPolicyVersion: version, scoringPolicyVersion: version, sequencingPolicyVersion: .init(rawValue: sequencingVersion),
            exposurePolicyVersion: version, selectionSchemaVersion: revision.selectionSchemaVersion,
            eligibility: .structuralOnly, scoring: .equal, sequencing: sequencing,
            exposure: .excludePublishedRevisions)
    }

    func exclude(_ ids: [SourceID]) throws {
        let prefs = ReaderPreferencesStore(database: database)
        var settings = try XCTUnwrap(prefs.load()).settings
        settings.contentSourceExclusions = ids.map { .init(sourceID: $0, displayName: "Source") }
        _ = try prefs.setSettings(settings)
    }

    @discardableResult
    func admit(_ source: SourceID, number: Int, language: String = "en") throws -> OriginRevision {
        let origin = OriginRecordID(), time = Date(timeIntervalSince1970: Double(100 + number))
        let revision = OriginRevision(id: OriginRevisionID(), originRecordID: origin,
            externalVersionIdentity: nil, headline: "Story \(number)", summary: "Summary",
            bodyText: nil, authoredAt: time, modifiedAt: nil, observedAt: time, language: language,
            primaryLink: URL(string: "https://example.test/\(number)"), searchProjection: nil, providerID: nil)
        try ContentStore(database: database).commitCanonicalChange(.init(recordID: origin,
            externalObjectIdentity: .init(connectorKind: .syndication, namespace: "source-exclusion",
                value: origin.rawValue.uuidString, role: .object), revision: revision, mediaCandidates: [],
            availability: .available, observedAt: time, expectedCurrent: .none, currentUpdate: .useSuppliedRevision,
            membershipMutations: [.upsert(sourceID: source, kind: .direct, observedAt: time)]))
        return revision
    }

    func initial() throws -> InitialProductionSlice.Request {
        var request = InitialProductionSlice.Request(plan: plan, policy: policy, examinedCapacity: 10,
            editionID: editionID, publicationSchemaVersion: .init(rawValue: 1), selectionSeed: 1,
            editionCreatedAt: Date(), segmentID: FeedSegmentID(), segmentSeed: 1, segmentCreatedAt: Date(),
            anchorPlacement: .top, checkpointedAt: Date())
        request.sourceExclusions = try ReaderSourceExclusionPolicy.capture(in: database)
        return request
    }

    func local(after: CandidateSupplyCursor? = nil) throws -> LocalProductionSlice.Request {
        var request = LocalProductionSlice.Request(plan: plan, policy: policy, editionID: editionID,
            after: after, examinedCapacity: 10, segmentID: FeedSegmentID(), segmentSeed: 1,
            segmentCreatedAt: Date())
        request.sourceExclusions = try ReaderSourceExclusionPolicy.capture(in: database)
        return request
    }

    static func prepared(_ selection: SelectionResult) -> LocalPreparedPublication {
        .init(inputs: selection.orderedCandidates.map { candidate in
            PublicationPreparationInput(origin: PublishedOrigin(originRecordID: candidate.originRecordID,
                originRevisionID: candidate.originRevisionID,
                sourceID: candidate.sourceIDs.sorted { $0.description < $1.description }.first,
                providerID: candidate.providerID, sourceDisplayName: "Source", providerDisplayName: nil),
                contentEntityID: nil, contentClusterID: nil, primaryAction: .localContentDetail,
                presentation: .textOnly)
        }, cardIDs: selection.orderedCandidates.map { _ in PublicationCardID() })
    }
}

final class SourceExclusionProductionTests: XCTestCase {
    func testInitialAndAppendUseThePolicyAndRemovingItCanReofferUnpublishedSupply() throws {
        let f = try ExclusionProductionFixture(self)
        let a = try f.admit(f.a, number: 1), b = try f.admit(f.b, number: 2)
        try f.exclude([f.a])
        let initial = InitialProductionSlice(database: f.database)
        let request = try f.initial()
        XCTAssertEqual(try initial.revisionsToPrepare(for: request), [b.id])
        guard case .published(_, let first) = try initial.run(request, prepare: ExclusionProductionFixture.prepared)
        else { return XCTFail("B should publish") }
        let store = PublicationStore(database: f.database)
        let frozen = try XCTUnwrap(store.card(id: first.cardIDs[0]))
        XCTAssertEqual(frozen.originRecordID, b.originRecordID)
        let checkpoint = try SessionStore(database: f.database).checkpoint()
        try f.exclude([])
        let local = LocalProductionSlice(database: f.database)
        guard case .published(_, let next) = try local.run(f.local(), prepare: ExclusionProductionFixture.prepared)
        else { return XCTFail("A should become eligible after removal") }
        XCTAssertEqual(try store.card(id: next.cardIDs[0])?.originRecordID, a.originRecordID)
        XCTAssertEqual(try store.card(id: first.cardIDs[0]), frozen)
        XCTAssertEqual(try SessionStore(database: f.database).checkpoint(), checkpoint)
        for _ in 0..<2 {
            guard case .advancedWithoutPublication = try local.run(f.local(), prepare: ExclusionProductionFixture.prepared)
            else { return XCTFail("published material must not recur") }
        }
        XCTAssertEqual(try store.segments(editionID: f.editionID).flatMap(\.cardIDs).count, 2)
    }

    func testPolicyChangeDuringPreparationRejectsFirstAndAppendWithoutLosingHistoryOrSave() throws {
        for isInitial in [true, false] {
            let f = try ExclusionProductionFixture(self)
            _ = try f.admit(f.a, number: 1)
            _ = try f.admit(f.b, number: 2)
            let store = PublicationStore(database: f.database)
            var frozen: [PublicationStore.CardRecord] = []
            var savedCardID: PublicationCardID?
            if !isInitial {
                _ = try InitialProductionSlice(database: f.database).run(f.initial(), prepare: ExclusionProductionFixture.prepared)
                frozen = try store.segments(editionID: f.editionID).flatMap(\.cardIDs).map { try XCTUnwrap(store.card(id: $0)) }
                let saved = try XCTUnwrap(frozen.first { $0.sourceID == f.a })
                savedCardID = saved.id
                try store.toggleBookmark(cardID: saved.id, at: Date())
                _ = try f.admit(f.a, number: 3)
            }
            let checkpoint = try SessionStore(database: f.database).checkpoint()
            let segments: [PublicationStore.SegmentRecord]
            if isInitial { segments = [] }
            else { segments = try store.segments(editionID: f.editionID) }
            let initial = try f.initial(), local = try f.local()
            XCTAssertThrowsError(try {
                if isInitial {
                    _ = try InitialProductionSlice(database: f.database).run(initial) { selection in
                        try f.exclude([f.a])
                        return ExclusionProductionFixture.prepared(selection)
                    }
                } else {
                    _ = try LocalProductionSlice(database: f.database).run(local) { selection in
                        try f.exclude([f.a])
                        return ExclusionProductionFixture.prepared(selection)
                    }
                }
            }()) { error in
                if isInitial { XCTAssertEqual(error as? InitialProductionSliceError, .staleSourceExclusions) }
                else { XCTAssertEqual(error as? LocalProductionSliceError, .staleSourceExclusions) }
            }
            if !isInitial { XCTAssertEqual(try store.segments(editionID: f.editionID), segments) }
            XCTAssertEqual(try SessionStore(database: f.database).checkpoint(), checkpoint)
            if isInitial { XCTAssertNil(try store.edition(id: f.editionID)) }
            for card in frozen { XCTAssertEqual(try store.card(id: card.id), card) }
            if !isInitial {
                let reopened = try RuntimeDatabase(location: .init(directory: f.directory))
                XCTAssertEqual(try PublicationStore(database: reopened).bookmarkedCardIDs(), [try XCTUnwrap(savedCardID)])
                XCTAssertEqual(try SessionStore(database: reopened).checkpoint(), checkpoint)
                XCTAssertNotNil(try PublicationHistory(database: reopened).restore(backwardCapacity: 8, forwardCapacity: 16))
            }
            if isInitial {
                guard case .published(_, let receipt) = try InitialProductionSlice(database: f.database)
                    .run(f.initial(), prepare: ExclusionProductionFixture.prepared)
                else { return XCTFail("a fresh first opportunity must still publish B") }
                XCTAssertEqual(receipt.cardIDs.count, 1)
                XCTAssertEqual(try store.card(id: receipt.cardIDs[0])?.sourceID, f.b)
            } else {
                let nextB = try f.admit(f.b, number: 4)
                guard case .published(_, let receipt) = try LocalProductionSlice(database: f.database)
                    .run(f.local(), prepare: ExclusionProductionFixture.prepared)
                else { return XCTFail("a fresh append must still publish B") }
                XCTAssertEqual(receipt.cardIDs.count, 1)
                XCTAssertEqual(try store.card(id: receipt.cardIDs[0])?.originRevisionID, nextB.id)
                for card in frozen { XCTAssertEqual(try store.card(id: card.id), card) }
                XCTAssertEqual(try store.bookmarkedCardIDs(), [try XCTUnwrap(savedCardID)])
            }
        }
    }

    func testBlockedMediaReofferWaitsAndCanPublishAfterUnblocking() throws {
        let f = try ExclusionProductionFixture(self)
        let a = try f.admit(f.a, number: 1), b = try f.admit(f.b, number: 2)
        let readiness = MediaReadiness(), reoffer = PendingMediaReconsideration(database: f.database)
        _ = readiness.record(b.id, nil, textDeclared: true)
        let outcome = try InitialProductionSlice(database: f.database, readiness: readiness, reoffer: reoffer)
            .run(f.initial(), prepare: ExclusionProductionFixture.prepared)
        guard case .published(let progress, _) = outcome else { return XCTFail("B publishes while A media is pending") }
        XCTAssertEqual(reoffer.count, 1)
        _ = readiness.record(a.id, nil, textDeclared: true)
        try f.exclude([f.a])
        let local = LocalProductionSlice(database: f.database, readiness: readiness, reoffer: reoffer)
        guard case .advancedWithoutPublication = try local.run(f.local(after: progress.nextCursor), prepare: ExclusionProductionFixture.prepared)
        else { return XCTFail("a ready reoffer cannot bypass source exclusion") }
        XCTAssertEqual(reoffer.count, 1, "a reversible source rule does not definitively settle a media skip")
        try f.exclude([])
        guard case .published(_, let receipt) = try local.run(f.local(after: progress.nextCursor), prepare: ExclusionProductionFixture.prepared)
        else { return XCTFail("the same queued story becomes eligible after rule removal") }
        XCTAssertEqual(try PublicationStore(database: f.database).card(id: receipt.cardIDs[0])?.originRecordID, a.originRecordID)
        XCTAssertEqual(reoffer.count, 0)
    }
}

extension SourceExclusionProductionTests {
    func testReopenedDatabaseRestoresPublishedAndSavedHistoryWhileRulesOnlyGateNewSupply() throws {
        let f = try ExclusionProductionFixture(self)
        _ = try f.admit(f.a, number: 1)
        _ = try f.admit(f.b, number: 2)
        guard case .published(_, let initial) = try InitialProductionSlice(database: f.database)
            .run(f.initial(), prepare: ExclusionProductionFixture.prepared)
        else { return XCTFail("the proof starts with A and B published") }
        let original = PublicationStore(database: f.database)
        let a = try XCTUnwrap(initial.cardIDs.first { try original.card(id: $0)?.sourceID == f.a })
        try original.toggleBookmark(cardID: a, at: Date(timeIntervalSince1970: 200))
        let checkpoint = SessionStore.CheckpointRecord(editionID: f.editionID, cardID: a,
            anchorPlacement: "center", updatedAt: Date(timeIntervalSince1970: 201), topDelta: 12, cardHeight: 300)
        try SessionStore(database: f.database).saveCheckpoint(checkpoint)
        let cards = try initial.cardIDs.map { try XCTUnwrap(original.card(id: $0)) }
        let segments = try original.segments(editionID: f.editionID)
        let before = try XCTUnwrap(PublicationHistory(database: f.database)
            .restore(backwardCapacity: 8, forwardCapacity: 16))
        try f.exclude([f.a])

        // A fresh connection and fresh production owners read the durable rule; this is not an app relaunch.
        let reopened = try RuntimeDatabase(location: .init(directory: f.directory))
        let store = PublicationStore(database: reopened)
        let restored = try XCTUnwrap(PublicationHistory(database: reopened)
            .restore(backwardCapacity: 8, forwardCapacity: 16))
        XCTAssertEqual(restored, before)
        XCTAssertEqual(try store.segments(editionID: f.editionID), segments)
        XCTAssertEqual(try store.bookmarkedCardIDs(), [a])
        XCTAssertEqual(try store.card(id: a), cards.first { $0.id == a })
        let blocked = try ReaderSourceExclusionPolicy.capture(in: reopened)
        XCTAssertEqual(blocked.sourceIDs, [f.a])
        let newA = try f.admit(f.a, number: 3), newB = try f.admit(f.b, number: 4)
        var request = try f.local()
        request.sourceExclusions = blocked
        let local = LocalProductionSlice(database: reopened)
        guard case .published(_, let allowed) = try local.run(request, prepare: ExclusionProductionFixture.prepared)
        else { return XCTFail("a new opportunity publishes B while A remains excluded") }
        XCTAssertEqual(allowed.cardIDs.count, 1)
        XCTAssertEqual(try store.card(id: allowed.cardIDs[0])?.originRevisionID, newB.id)
        XCTAssertEqual(try SessionStore(database: reopened).checkpoint(), checkpoint)
        for card in cards { XCTAssertEqual(try store.card(id: card.id), card) }

        try f.exclude([])
        var unrestricted = try f.local()
        unrestricted.sourceExclusions = try ReaderSourceExclusionPolicy.capture(in: reopened)
        guard case .published(_, let recovered) = try local.run(unrestricted, prepare: ExclusionProductionFixture.prepared)
        else { return XCTFail("removing the durable rule permits unpublished A") }
        XCTAssertEqual(recovered.cardIDs.count, 1)
        XCTAssertEqual(try store.card(id: recovered.cardIDs[0])?.originRevisionID, newA.id)
        for _ in 0..<2 {
            guard case .advancedWithoutPublication = try local.run(unrestricted, prepare: ExclusionProductionFixture.prepared)
            else { return XCTFail("neither historical nor newly published material may recur") }
        }
        let all = try store.segments(editionID: f.editionID).flatMap(\.cardIDs)
        XCTAssertEqual(Array(all.prefix(initial.cardIDs.count)), initial.cardIDs)
        XCTAssertEqual(all.count, 4)
        XCTAssertEqual(Set(all).count, all.count)
        XCTAssertEqual(try store.bookmarkedCardIDs(), [a])
        XCTAssertEqual(try SessionStore(database: reopened).checkpoint(), checkpoint)
        for card in cards { XCTAssertEqual(try store.card(id: card.id), card) }
    }
}

extension SourceExclusionProductionTests {
    func testSourceExclusionPreservesPD4HoldAndPublishesWhenThePredecessorIsCompatible() throws {
        for excludeTail in [false, true] {
            let f = try ExclusionProductionFixture(self, sequencingVersion: 6, sequencing: .maximumDistance)
            _ = try f.admit(f.a, number: 1)
            _ = try f.admit(f.b, number: 2)
            guard case .published(_, let first) = try InitialProductionSlice(database: f.database)
                .run(f.initial(), prepare: ExclusionProductionFixture.prepared)
            else { return XCTFail("initial A/B publication") }
            let store = PublicationStore(database: f.database)
            let old = try first.cardIDs.map { try XCTUnwrap(store.card(id: $0)) }
            let tailSource = try XCTUnwrap(old.last?.sourceID)
            let other = tailSource == f.a ? f.b : f.a
            let excluded = excludeTail ? tailSource : other
            let allowed = excludeTail ? other : tailSource
            let blocked = try f.admit(excluded, number: 3)
            let offered = try f.admit(allowed, number: 4)
            try f.exclude([excluded])
            let local = LocalProductionSlice(database: f.database)
            let outcome = try local.run(f.local(), prepare: ExclusionProductionFixture.prepared)
            if excludeTail {
                guard case .published(_, let receipt) = outcome else { return XCTFail("compatible B must publish") }
                XCTAssertEqual(receipt.cardIDs.count, 1)
                XCTAssertEqual(try store.card(id: receipt.cardIDs[0])?.originRevisionID, offered.id)
            } else {
                guard case .advancedWithoutPublication = outcome else { return XCTFail("F13 must not bypass PD-4") }
                XCTAssertEqual(try store.segments(editionID: f.editionID).flatMap(\.cardIDs), first.cardIDs)
            }
            for card in old { XCTAssertEqual(try store.card(id: card.id), card) }
            try f.exclude([])
            guard case .published(_, _) = try local.run(f.local(), prepare: ExclusionProductionFixture.prepared)
            else { return XCTFail("removal allows the opposite source to unlock alternation") }
            let ids = try store.segments(editionID: f.editionID).flatMap(\.cardIDs)
            let revisions = try ids.map { try XCTUnwrap(store.card(id: $0)).originRevisionID }
            XCTAssertEqual(revisions.filter { $0 == offered.id }.count, 1)
            XCTAssertEqual(revisions.filter { $0 == blocked.id }.count, 1)
            XCTAssertEqual(ids.count, 4)
            for card in old { XCTAssertEqual(try store.card(id: card.id), card) }
        }
    }
}

private extension ExclusionProductionFixture {
    func words(_ words: [String]) throws {
        let prefs = ReaderPreferencesStore(database: database)
        var settings = try XCTUnwrap(prefs.load()).settings
        settings.contentFilterRules = words
        _ = try prefs.setSettings(settings)
    }
    func wordInitial() throws -> InitialProductionSlice.Request {
        var request = try initial()
        request.wordExclusions = try ReaderPreferencesStore(database: database).wordExclusionSnapshot(templates: [])
        return request
    }
    func wordLocal(after: CandidateSupplyCursor? = nil) throws -> LocalProductionSlice.Request {
        var request = try local(after: after)
        request.wordExclusions = try ReaderPreferencesStore(database: database).wordExclusionSnapshot(templates: [])
        return request
    }
}

extension SourceExclusionProductionTests {
    func testWordSnapshotGatesPreparationAndPublicationThenRemovalReoffersSupply() throws {
        let f = try ExclusionProductionFixture(self)
        let a = try f.admit(f.a, number: 1), b = try f.admit(f.b, number: 2)
        try f.words(["story 1"])
        let initial = InitialProductionSlice(database: f.database)
        XCTAssertEqual(try initial.revisionsToPrepare(for: f.wordInitial()), [b.id])
        guard case .published(_, let first) = try initial.run(f.wordInitial(), prepare: ExclusionProductionFixture.prepared)
        else { return XCTFail("only B should publish") }
        let store = PublicationStore(database: f.database)
        let frozen = try XCTUnwrap(store.card(id: first.cardIDs[0]))
        XCTAssertEqual(frozen.originRecordID, b.originRecordID)
        let checkpoint = try SessionStore(database: f.database).checkpoint()
        try f.words([])
        guard case .published(_, let next) = try LocalProductionSlice(database: f.database)
            .run(f.wordLocal(), prepare: ExclusionProductionFixture.prepared)
        else { return XCTFail("removing the word should reoffer A") }
        XCTAssertEqual(try store.card(id: next.cardIDs[0])?.originRecordID, a.originRecordID)
        XCTAssertEqual(try store.card(id: first.cardIDs[0]), frozen)
        XCTAssertEqual(try SessionStore(database: f.database).checkpoint(), checkpoint)
    }

    func testWordChangeDuringPreparationRejectsInitialAndAppendAtomically() throws {
        for initial in [true, false] {
            let f = try ExclusionProductionFixture(self)
            _ = try f.admit(f.a, number: 1)
            if !initial {
                _ = try InitialProductionSlice(database: f.database).run(f.wordInitial(), prepare: ExclusionProductionFixture.prepared)
                _ = try f.admit(f.b, number: 2)
            }
            let store = PublicationStore(database: f.database)
            let before = initial ? [] : try store.segments(editionID: f.editionID)
            let checkpoint = try SessionStore(database: f.database).checkpoint()
            XCTAssertThrowsError(try {
                if initial {
                    _ = try InitialProductionSlice(database: f.database).run(f.wordInitial()) { selection in
                        try f.words(["story"])
                        return ExclusionProductionFixture.prepared(selection)
                    }
                } else {
                    _ = try LocalProductionSlice(database: f.database).run(f.wordLocal()) { selection in
                        try f.words(["story"])
                        return ExclusionProductionFixture.prepared(selection)
                    }
                }
            }()) {
                if initial { XCTAssertEqual($0 as? InitialProductionSliceError, .staleWordExclusions) }
                else { XCTAssertEqual($0 as? LocalProductionSliceError, .staleWordExclusions) }
            }
            if initial { XCTAssertNil(try store.edition(id: f.editionID)) }
            else { XCTAssertEqual(try store.segments(editionID: f.editionID), before) }
            XCTAssertEqual(try SessionStore(database: f.database).checkpoint(), checkpoint)
        }
    }

    func testExplicitWordSnapshotOverridesFrozenWordsWithoutChangingContextIdentity() throws {
        let f = try ExclusionProductionFixture(self,
            filter: ReaderFilter(languages: ["en"], exclusions: .init(isEnabled: true, rules: ["story"])))
        let a = try f.admit(f.a, number: 1)
        _ = try f.admit(f.b, number: 2, language: "pt")
        let initial = InitialProductionSlice(database: f.database)
        XCTAssertTrue(try initial.revisionsToPrepare(for: f.initial()).isEmpty, "nil preserves frozen criteria")
        var contextual = try f.wordInitial()
        contextual.wordExclusions = try ReaderPreferencesStore(database: f.database)
            .wordExclusionSnapshot(templates: [], context: f.plan.context.key.filter.exclusions)
        XCTAssertTrue(try initial.revisionsToPrepare(for: contextual).isEmpty,
            "an explicit snapshot retains true contextual words when supplied by the caller")
        XCTAssertEqual(try initial.revisionsToPrepare(for: f.wordInitial()), [a.id])
        guard case .published = try initial.run(f.wordInitial(), prepare: ExclusionProductionFixture.prepared)
        else { return XCTFail("effective word policy should admit A") }
        XCTAssertEqual(try PublicationStore(database: f.database).edition(id: f.editionID)?.editorialRevision.contextKey, f.plan.context.key)
    }

    func testWordMaskedReadyMediaSkipWaitsAndPublishesAfterRemoval() throws {
        let f = try ExclusionProductionFixture(self)
        let a = try f.admit(f.a, number: 1), b = try f.admit(f.b, number: 2)
        let readiness = MediaReadiness(), reoffer = PendingMediaReconsideration(database: f.database)
        _ = readiness.record(b.id, nil, textDeclared: true)
        guard case .published(let progress, _) = try InitialProductionSlice(database: f.database,
            readiness: readiness, reoffer: reoffer).run(f.wordInitial(), prepare: ExclusionProductionFixture.prepared)
        else { return XCTFail("B publishes while A waits for media") }
        XCTAssertEqual(reoffer.count, 1)
        _ = readiness.record(a.id, nil, textDeclared: true)
        try f.words(["story 1"])
        let local = LocalProductionSlice(database: f.database, readiness: readiness, reoffer: reoffer)
        guard case .advancedWithoutPublication = try local.run(f.wordLocal(after: progress.nextCursor),
            prepare: ExclusionProductionFixture.prepared) else { return XCTFail("word must mask the ready skip") }
        XCTAssertEqual(reoffer.count, 1, "a reversible word mask must retain the queued candidate")
        try f.words([])
        guard case .published(_, let receipt) = try local.run(f.wordLocal(after: progress.nextCursor),
            prepare: ExclusionProductionFixture.prepared) else { return XCTFail("unmasked ready skip should publish") }
        XCTAssertEqual(try PublicationStore(database: f.database).card(id: receipt.cardIDs[0])?.originRecordID, a.originRecordID)
        XCTAssertEqual(reoffer.count, 0)
    }
}
