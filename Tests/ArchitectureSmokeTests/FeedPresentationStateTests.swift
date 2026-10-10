import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineEditorial
import FeedMinePublication
import FeedMineRuntime
import FeedMineUI

@MainActor
final class FeedPresentationStateTests: XCTestCase {
    private struct Fixture {
        let database: RuntimeDatabase
        let session: FeedSession
        let editionID: FeedEditionID
        let cardIDs: [PublicationCardID]
    }

    private func fixture(context: FeedContext = .init(request: .main), editionID: FeedEditionID = FeedEditionID()) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let version = PolicyVersion(rawValue: 1)
        let revision = EditorialRevision(id: EditorialRevisionID(), contextKey: context.key,
            catalogGeneration: .init(rawValue: 1), userSelectionVersion: version, eligibilityPolicyVersion: version,
            scoringPolicyVersion: version, sequencingPolicyVersion: version, exposurePolicyVersion: version,
            selectionSchemaVersion: .init(rawValue: 1))
        let candidates = (0..<4).map { index in
            Candidate(originRecordID: OriginRecordID(), originRevisionID: OriginRevisionID(),
                headline: "Published \(index)", summary: "Local content \(index)",
                timestamp: .init(value: Date(timeIntervalSince1970: Double(index)), kind: .observed), language: nil, providerID: nil)
        }
        let selection = SelectionResult(editorialRevision: revision, orderedCandidates: candidates,
            supplyReport: .init(examinedCount: 4, nextCursor: nil, exhausted: true))
        let inputs = candidates.map { candidate in
            PublicationPreparationInput(origin: .init(originRecordID: candidate.originRecordID,
                originRevisionID: candidate.originRevisionID, sourceID: nil, providerID: nil,
                sourceDisplayName: "Local source", providerDisplayName: nil), contentEntityID: nil,
                contentClusterID: nil, primaryAction: .localContentDetail, presentation: .textOnly)
        }
        let cardIDs = candidates.map { _ in PublicationCardID() }
        _ = try PublicationCoordinator(database: database).createEdition(.init(selection: selection,
            drafts: PublicationPreparation.drafts(selection: selection, inputs: inputs), editionID: editionID,
            publicationSchemaVersion: .init(rawValue: 1), selectionSeed: 1, editionCreatedAt: Date(timeIntervalSince1970: 10),
            segmentID: FeedSegmentID(), segmentSeed: 2, segmentCreatedAt: Date(timeIntervalSince1970: 11), cardIDs: cardIDs))
        let history = PublicationHistory(database: database)
        try history.saveCursor(.init(editionID: editionID, anchor: .init(cardID: cardIDs[0], placement: .top)),
            updatedAt: Date(timeIntervalSince1970: 12))
        return .init(database: database, session: FeedSession(publicationHistory: history), editionID: editionID, cardIDs: cardIDs)
    }

    private func snapshot(_ f: Fixture, backward: Int = 1, forward: Int = 1) async throws -> FeedPresentationSnapshot {
        let restored = try await f.session.admitPresentation(.restore(.init(backwardCapacity: backward, forwardCapacity: forward)))
        return try XCTUnwrap(restored)
    }

    func testT1LocalPresentationAvailableImmediately() async throws {
        let f = try fixture(), published = try await snapshot(f)
        let state = FeedPresentationState(presentation: published)
        XCTAssertEqual(state.presentation, published)
        XCTAssertEqual(state.work, .idle)
        XCTAssertEqual(state.presentation?.window.items.map(\.id), Array(f.cardIDs.prefix(2)))
    }

    func testT2PresentationSurvivesPendingWork() async throws {
        let f = try fixture(), published = try await snapshot(f)
        let ready = FeedPresentationState(presentation: published)
        let pending = ready.reporting(.pending)
        XCTAssertEqual(pending.work, .pending)
        XCTAssertEqual(pending.presentation, ready.presentation)
        XCTAssertEqual(pending.presentation?.editionID, f.editionID)
        XCTAssertEqual(pending.presentation?.window.anchor, published.window.anchor)
        XCTAssertEqual(ready.work, .idle)
    }

    func testT3PresentationSurvivesFailure() async throws {
        let f = try fixture(), published = try await snapshot(f)
        let pending = FeedPresentationState(presentation: published).reporting(.pending)
        let failed = pending.reporting(.failed(message: "Acquisition failed"))
        XCTAssertEqual(failed.work, .failed(message: "Acquisition failed"))
        XCTAssertEqual(failed.presentation, published)
        XCTAssertEqual(failed.reporting(.idle).presentation, published)
    }

    func testT4NoPublishedPresentationAndInitialPreparationRemainDistinct() {
        let absent = FeedPresentationState(presentation: nil)
        XCTAssertNil(absent.presentation); XCTAssertEqual(absent.work, .idle)
        let preparing = absent.reporting(.pending)
        XCTAssertNil(preparing.presentation); XCTAssertEqual(preparing.work, .pending)
        XCTAssertNotEqual(preparing, absent)
        let failed = preparing.reporting(.failed(message: "Preparation failed"))
        XCTAssertNil(failed.presentation); XCTAssertEqual(failed.work, .failed(message: "Preparation failed"))
    }

    func testT5DeferredAndUnavailablePreserveDistinctFacts() async throws {
        let absent = FeedPresentationState(presentation: nil)
        let deferred = absent.reporting(.deferred), unavailable = absent.reporting(.unavailable)
        XCTAssertNil(deferred.presentation); XCTAssertNil(unavailable.presentation)
        XCTAssertNotEqual(deferred, unavailable); XCTAssertNotEqual(deferred, absent); XCTAssertNotEqual(unavailable, absent)
        let f = try fixture(), published = try await snapshot(f)
        let ready = FeedPresentationState(presentation: published)
        XCTAssertEqual(ready.reporting(.deferred).presentation, published)
        XCTAssertEqual(ready.reporting(.unavailable).presentation, published)
        // A subsequent local snapshot is still legal; neither fact means terminal global emptiness.
        let received = try unavailable.receiving(published)
        XCTAssertEqual(received.presentation, published)
        XCTAssertEqual(received.work, .unavailable)
        XCTAssertEqual(received.reporting(.idle).work, .idle)
    }

    func testT6UpdatedWindowUsesExactRuntimeOrderEditionAndAnchor() async throws {
        let f = try fixture(), first = try await snapshot(f)
        let state = FeedPresentationState(presentation: first).reporting(.pending)
        let observation = ViewportObservation(anchor: .init(cardID: f.cardIDs[1], placement: .center))
        let moved = try await f.session.submitViewport(observation)
        let next = try XCTUnwrap(moved)
        let updated = try state.receiving(next)
        XCTAssertEqual(updated.presentation, next)
        XCTAssertEqual(updated.presentation?.editionID, first.editionID)
        // A stationary observation moves the logical anchor; the admitted prefix is unchanged.
        XCTAssertEqual(updated.presentation?.window.items.map(\.id), Array(f.cardIDs.prefix(2)))
        XCTAssertEqual(updated.presentation?.window.anchor, observation.anchor)
        // Receiving a new projection does not claim external work has settled.
        XCTAssertEqual(updated.work, .pending)
        XCTAssertEqual(state.presentation, first)
    }

    func testT7FiniteWindowBoundaryNeverBecomesGlobalExhaustion() async throws {
        let f = try fixture(), first = try await snapshot(f)
        let state = FeedPresentationState(presentation: first)
        let lastMaterialized = try XCTUnwrap(first.window.items.last)
        XCTAssertEqual(lastMaterialized.id, f.cardIDs[1])
        let moved = try await f.session.submitViewport(.init(anchor: .init(cardID: lastMaterialized.id, placement: .top)))
        let next = try XCTUnwrap(moved), updated = try state.receiving(next)
        XCTAssertEqual(state.work, .idle); XCTAssertEqual(updated.work, .idle)
        XCTAssertEqual(updated.presentation?.window.items.last?.id, f.cardIDs[1])
        XCTAssertEqual(updated.presentation?.editionID, first.editionID)
        // A second session is the only way to install different structural bounds (T2).
        let anchorOnlySession = FeedSession(publicationHistory: .init(database: f.database))
        let anchorOnlyValue = try await anchorOnlySession.admitPresentation(
            .restore(.init(backwardCapacity: 0, forwardCapacity: 0)))
        let anchorOnly = try XCTUnwrap(anchorOnlyValue)
        let finite = FeedPresentationState(presentation: anchorOnly)
        XCTAssertEqual(finite.presentation?.window.items.count, 1)
        XCTAssertEqual(finite.work, .idle)
        // Durable history contains more than this disposable materialization.
        XCTAssertEqual(try PublicationStore(database: f.database).segments(editionID: f.editionID).first?.cardIDs.count, 4)
    }

    func testT8StableIdentityComesFromPublishedOccurrenceIDs() async throws {
        let f = try fixture(), published = try await snapshot(f, forward: 4)
        let state = FeedPresentationState(presentation: published)
        XCTAssertEqual(state.presentation?.window.items.map(\.id), f.cardIDs)
        XCTAssertEqual(state.presentation?.window.items.map(\.title), (0..<4).map { "Published \($0)" })
        XCTAssertEqual(state.presentation?.window.anchor.cardID, f.cardIDs[0])
        XCTAssertEqual(state.presentation?.window.items, published.window.items)
    }

    func testT9BoundaryOwnsNoProductionOrExecution() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/FeedMineUI/FeedPresentationState.swift"), encoding: .utf8)
        for forbidden in ["URLSession", "HTTP", "ContentStore", "RuntimeDatabase", "AcquisitionCoordinator",
            "SelectionEngine", "SelectionResult", "CandidateProvider", "PublicationCoordinator", "PublicationStore",
            "FeedEdition(", "FeedSegment(", "PublicationCardID(", "UUID(", "Date(", "Task", "Timer", "sleep",
            "retry", "backoff", "scheduler", "cache", "generation", "exhausted", "[PresentationCard]",
            "import FeedMinePublication", "import FeedMinePersistence", "import FeedMineAcquisition", "import FeedMineEditorial"] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }
    }

    func testReceivingAnotherEditionRejectsImplicitReplacement() async throws {
        let f = try fixture(), other = try fixture()
        let published = try await snapshot(f), replacement = try await snapshot(other)
        var state = FeedPresentationState(presentation: published).reporting(.pending)
        let before = state
        XCTAssertThrowsError(try state.receiving(replacement)) {
            XCTAssertEqual($0 as? FeedPresentationStateError, .presentationIdentityMismatch)
        }
        do { state = try state.receiving(replacement) } catch {}
        XCTAssertEqual(state, before)
    }

    func testReceivingAnotherContextRejectsIdentityMismatch() async throws {
        let f = try fixture()
        let other = try fixture(context: .init(request: .source(SourceID())), editionID: f.editionID)
        let published = try await snapshot(f), replacement = try await snapshot(other)
        let state = FeedPresentationState(presentation: published)
        XCTAssertEqual(replacement.editionID, published.editionID)
        XCTAssertNotEqual(replacement.contextKey, published.contextKey)
        XCTAssertThrowsError(try state.receiving(replacement)) {
            XCTAssertEqual($0 as? FeedPresentationStateError, .presentationIdentityMismatch)
        }
        XCTAssertEqual(state.presentation, published)
    }

    func testFirstSnapshotCanArriveDuringInitialPreparation() async throws {
        let f = try fixture(), published = try await snapshot(f)
        let preparing = FeedPresentationState(presentation: nil).reporting(.pending)
        let available = try preparing.receiving(published)
        XCTAssertEqual(available.presentation, published)
        XCTAssertEqual(available.work, .pending)
        XCTAssertEqual(available.reporting(.idle).presentation, published)
        XCTAssertNil(preparing.presentation)
    }
}
