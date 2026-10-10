import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineEditorial
import FeedMinePublication
@testable import FeedMineRuntime
import FeedMineUI

@MainActor
final class PresentationProjectionOrderingTests: XCTestCase {
    private struct Fixture {
        let location: RuntimeDatabaseLocation
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
        return .init(location: .init(directory: directory), database: database, session: FeedSession(publicationHistory: history), editionID: editionID, cardIDs: cardIDs)
    }

    private func snapshot(_ f: Fixture, backward: Int = 1, forward: Int = 1) async throws -> FeedPresentationSnapshot {
        let restored = try await f.session.admitPresentation(.restore(.init(backwardCapacity: backward, forwardCapacity: forward)))
        return try XCTUnwrap(restored)
    }


    func testO1O2O14O16O17DelayedAAfterBPreservesEntireStoreAndSession() async throws {
        let f = try fixture(), a = try await snapshot(f)
        let moved = try await f.session.submitViewport(.init(anchor: .init(cardID: f.cardIDs[1], placement: .center)))
        let b = try XCTUnwrap(moved)
        let store = FeedScreenStore { _, _ in XCTFail("No execution") }
        try store.install(.init(presentation: b).reporting(.pending))
        let installed = store.state
        let (gate, continuation) = AsyncStream<Void>.makeStream()
        let delayed = Task { for await _ in gate { break }; return a }
        continuation.yield(()); continuation.finish()
        let arrivedLate = await delayed.value
        XCTAssertEqual(a.provenance.position, 1)
        XCTAssertEqual(b.provenance.position, 2)
        XCTAssertThrowsError(try store.install(.init(presentation: arrivedLate))) {
            XCTAssertEqual($0 as? FeedPresentationStateError, .staleProjection)
        }
        XCTAssertEqual(store.state, installed)
        XCTAssertEqual(store.state.presentation, b)
        try store.install(.init(presentation: b).reporting(.failed(message: "retain chosen failure")))
        let failed = store.state
        XCTAssertThrowsError(try store.install(.init(presentation: a).reporting(.idle))) {
            XCTAssertEqual($0 as? FeedPresentationStateError, .staleProjection)
        }
        XCTAssertEqual(store.state, failed)
        let current = await f.session.currentPresentation()
        XCTAssertEqual(current, b)
    }
    func testO3O11ReverseNavigationOrdersProjectionsNotCards() async throws {
        let f = try fixture(), a = try await snapshot(f, backward: 4, forward: 4)
        let moved = try await f.session.submitViewport(.init(anchor: .init(cardID: f.cardIDs[3], placement: .center)))
        let b = try XCTUnwrap(moved)
        let reversed = try await f.session.submitViewport(.init(anchor: .init(cardID: f.cardIDs[0], placement: .center)))
        let c = try XCTUnwrap(reversed)
        XCTAssertEqual([a.provenance.position, b.provenance.position, c.provenance.position], [1, 2, 3])
        XCTAssertEqual(c.window.anchor.cardID, f.cardIDs[0])
        let store = FeedScreenStore { _, _ in }
        try store.install(.init(presentation: b))
        try store.install(.init(presentation: c))
        XCTAssertEqual(store.state.presentation, c)
    }

    func testO4O9O10O13ReadsNoopsCheckpointsAndWorkDoNotAdvance() async throws {
        let f = try fixture(), a = try await snapshot(f)
        let noop = try await f.session.submitViewport(.init(anchor: a.window.anchor))
        let unknown = try await f.session.submitViewport(.init(anchor: .init(cardID: PublicationCardID(), placement: .top)))
        let read = await f.session.currentPresentation()
        _ = await f.session.currentRunwayScope()
        _ = try await f.session.checkpointCurrentPosition(at: Date())
        let restore = try await f.session.admitPresentation(.restore(.init(backwardCapacity: 1, forwardCapacity: 1)))
        for result in [noop, unknown, read, restore] { XCTAssertEqual(result, a) }
        let store = FeedScreenStore { _, _ in }
        try store.install(.init(presentation: a).reporting(.pending))
        try store.install(.init(presentation: a).reporting(.failed(message: "chosen failure")))
        XCTAssertEqual(store.state.presentation?.provenance, a.provenance)
        try store.install(.init(presentation: nil).reporting(.deferred))
        XCTAssertEqual(store.state.presentation, a)
        XCTAssertEqual(store.state.work, .deferred)
    }

    func testO5EqualOrderDifferentWindowIsIntegrityError() async throws {
        let f = try fixture(), a = try await snapshot(f)
        let moved = try await f.session.submitViewport(.init(anchor: .init(cardID: f.cardIDs[1], placement: .center)))
        let b = try XCTUnwrap(moved)
        let window = try PublicationHistory(database: f.database).window(editionID: f.editionID,
            around: .init(cardID: b.window.anchor.cardID, placement: .center), backwardCapacity: 1, forwardCapacity: 1)
        // Deliberate invalid duplicate of real A provenance; never a fixture authority.
        let conflict = FeedPresentationSnapshot(contextKey: a.contextKey, editionID: a.editionID,
            publishedWindow: window, provenance: a.provenance)
        let store = FeedScreenStore { _, _ in }
        try store.install(.init(presentation: a).reporting(.pending))
        let before = store.state
        XCTAssertThrowsError(try store.install(.init(presentation: conflict))) {
            XCTAssertEqual($0 as? FeedPresentationStateError, .inconsistentProjectionOrder)
        }
        XCTAssertEqual(store.state, before)
    }

    func testO6O7EditorialIdentityFencePrecedesSequenceComparison() async throws {
        let f = try fixture(), a = try await snapshot(f)
        for context in [FeedContext(request: .main), FeedContext(request: .source(SourceID()))] {
            let identity = context.key == a.contextKey ? FeedEditionID() : f.editionID
            let other = try fixture(context: context, editionID: identity), foreign = try await snapshot(other)
            let store = FeedScreenStore { _, _ in }
            try store.install(.init(presentation: a))
            XCTAssertThrowsError(try store.install(.init(presentation: foreign))) {
                XCTAssertEqual($0 as? FeedPresentationStateError, .presentationIdentityMismatch)
            }
            XCTAssertEqual(store.state.presentation, a)
        }
    }

    func testO8IndependentSessionsCannotCompareTheirCounters() async throws {
        let f = try fixture(), a = try await snapshot(f)
        let moved = try await f.session.submitViewport(.init(anchor: .init(cardID: f.cardIDs[1], placement: .center)))
        let b = try XCTUnwrap(moved)
        let other = FeedSession(publicationHistory: .init(database: f.database))
        let restored = try await other.admitPresentation(.restore(.init(backwardCapacity: 1, forwardCapacity: 1)))
        let foreign = try XCTUnwrap(restored)
        XCTAssertEqual(foreign.provenance.position, 1)
        XCTAssertNotEqual(a.provenance.sequenceID, foreign.provenance.sequenceID)
        for first in [a, b] {
            let store = FeedScreenStore { _, _ in }
            try store.install(.init(presentation: first).reporting(.pending))
            let before = store.state
            XCTAssertThrowsError(try store.install(.init(presentation: foreign))) {
                XCTAssertEqual($0 as? FeedPresentationStateError, .projectionSequenceMismatch)
            }
            XCTAssertEqual(store.state, before)
        }
        let explicitlyNewStore = FeedScreenStore { _, _ in }
        try explicitlyNewStore.install(.init(presentation: foreign))
        XCTAssertEqual(explicitlyNewStore.state.presentation, foreign)
    }

    /// The inverse of the removed defect pin: committed publication never advances the admitted list
    /// by itself; a real forward scroll at the boundary admits the ready prefix exactly once.
    func testO12CommittedPublicationWaitsForForwardScrollAdmission() async throws {
        let f = try fixture(), a = try await snapshot(f, backward: 1, forward: 8)
        let history = PublicationHistory(database: f.database)
        let restored = try XCTUnwrap(history.restore(backwardCapacity: 1, forwardCapacity: 8))
        let candidate = Candidate(originRecordID: OriginRecordID(), originRevisionID: OriginRevisionID(), headline: "New committed card",
            summary: "Content", timestamp: .init(value: Date(), kind: .observed), language: nil, providerID: nil)
        let selection = SelectionResult(editorialRevision: restored.edition.editorialRevision,
            orderedCandidates: [candidate], supplyReport: .init(examinedCount: 1, nextCursor: nil, exhausted: true))
        let input = PublicationPreparationInput(origin: .init(originRecordID: candidate.originRecordID,
            originRevisionID: candidate.originRevisionID, sourceID: nil, providerID: nil, sourceDisplayName: nil, providerDisplayName: nil),
            contentEntityID: nil, contentClusterID: nil, primaryAction: nil, presentation: .textOnly)
        _ = try PublicationCoordinator(database: f.database).append(.init(selection: selection,
            drafts: PublicationPreparation.drafts(selection: selection, inputs: [input]), editionID: f.editionID,
            segmentID: FeedSegmentID(), segmentSeed: 1, segmentCreatedAt: Date(), cardIDs: [PublicationCardID()]))
        // The publication exists in history, and the reader is stationary: the admitted list is identical.
        let ready = try history.readyAhead(editionID: f.editionID, anchorCardID: f.cardIDs[3], probeBound: 8)
        guard case .exact(let ahead) = ready.amount else { return XCTFail("Expected an exact ready-ahead count") }
        XCTAssertEqual(ahead, 1)
        let stationary = await f.session.currentPresentation()
        XCTAssertEqual(stationary, a)
        // A real forward scroll at the boundary admits the ready prefix once, appending at the tail.
        let tail = try XCTUnwrap(a.window.items.last)
        let observation = ViewportObservation(anchor: .init(cardID: tail.id, placement: .center))
        // Record the reader's position first (what the driver does), then admit behind it.
        _ = try await f.session.submitViewport(observation)
        let admission = try await f.session.admitPresentation(.forwardScroll(observation))
        let admitted = try XCTUnwrap(admission)
        XCTAssertEqual(admitted.provenance.sequenceID, a.provenance.sequenceID)
        XCTAssertEqual(admitted.window.items.count, a.window.items.count + 1)
        XCTAssertEqual(Array(admitted.window.items.prefix(a.window.items.count)), a.window.items)
        XCTAssertGreaterThan(admitted.provenance.position, a.provenance.position)
        // Nothing new is published now, so a repeat admission adds nothing.
        let again = try await f.session.admitPresentation(.forwardScroll(.init(anchor: .init(cardID: tail.id, placement: .center))))
        XCTAssertEqual(again, admitted)
    }

    private func persistAndClose() async throws -> (RuntimeDatabaseLocation, FeedPresentationSnapshot) {
        let f = try fixture()
        _ = try await snapshot(f)
        let moved = try await f.session.submitViewport(.init(anchor: .init(cardID: f.cardIDs[1], placement: .center)))
        _ = try await f.session.checkpointCurrentPosition(at: Date())
        return (f.location, try XCTUnwrap(moved))
    }

    func testO15ReopenStartsIndependentMemorySequenceAndPreservesHistory() async throws {
        let (location, old) = try await persistAndClose()
        let db = try RuntimeDatabase(location: location)
        let session = FeedSession(publicationHistory: .init(database: db))
        let restored = try await session.admitPresentation(.restore(.init(backwardCapacity: 1, forwardCapacity: 1)))
        let new = try XCTUnwrap(restored)
        // A reopen materializes the checkpoint window; the in-memory admitted list is not durable.
        XCTAssertEqual(new.window.anchor, old.window.anchor)
        XCTAssertEqual(new.window.items.count, old.window.items.count + 1)
        XCTAssertEqual(Array(new.window.items.prefix(old.window.items.count)), old.window.items)
        XCTAssertEqual(new.editionID, old.editionID)
        XCTAssertNotEqual(new.provenance.sequenceID, old.provenance.sequenceID)
        XCTAssertEqual(new.provenance.position, 1)
        XCTAssertEqual(old.provenance.position, 2)
    }

    func testOverflowCannotWrapToAnAcceptedZeroOrder() throws {
        XCTAssertEqual(try FeedProjectionProvenance.nextPosition(after: UInt64.max - 1), UInt64.max)
        XCTAssertThrowsError(try FeedProjectionProvenance.nextPosition(after: UInt64.max)) {
            XCTAssertEqual($0 as? FeedSessionError, .projectionOrderExhausted)
        }
    }

}
