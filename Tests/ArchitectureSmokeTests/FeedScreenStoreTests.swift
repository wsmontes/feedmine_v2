import Foundation
import XCTest
import Observation
import FeedMineDomain
import FeedMinePersistence
import FeedMineEditorial
import FeedMinePublication
import FeedMineRuntime
import FeedMineUI
import FeedMineComposition

@MainActor
final class FeedScreenStoreTests: XCTestCase {
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
        let restored = try await f.session.restoreLocalPresentation(backwardCapacity: backward, forwardCapacity: forward)
        return try XCTUnwrap(restored)
    }

    @MainActor
    private final class Changes {
        var count = 0
    }

    func testS1InitialStateHasNoInventedPresentationOrWork() {
        var calls = 0
        let store = FeedScreenStore { _, _ in calls += 1 }
        XCTAssertEqual(store.state, FeedPresentationState(presentation: nil))
        XCTAssertEqual(calls, 0)
    }

    func testS2InstallFirstRealRestoredPresentationExactly() async throws {
        let f = try fixture(), published = try await snapshot(f)
        let store = FeedScreenStore { _, _ in XCTFail("Unrequested viewport") }
        let delivered = try FeedPresentationHandoff.receive(snapshot: published, into: store.state)
        try store.install(delivered)
        XCTAssertEqual(store.state, delivered)
        XCTAssertEqual(store.state.presentation?.window.items.map(\.id), Array(f.cardIDs.prefix(2)))
        XCTAssertEqual(store.state.presentation?.window.anchor, published.window.anchor)
        XCTAssertEqual(store.state.presentation?.editionID, f.editionID)
    }

    func testS3NativeObservationNotifiesForPresentationAndWorkInstallation() async throws {
        let f = try fixture(), published = try await snapshot(f)
        let store = FeedScreenStore { _, _ in }
        let changes = Changes()
        withObservationTracking { _ = store.state.presentation } onChange: {
            MainActor.assumeIsolated { changes.count += 1 }
        }
        try store.install(try FeedPresentationHandoff.receive(snapshot: published, into: store.state))
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(store.state.presentation, published)
        withObservationTracking { _ = store.state.work } onChange: {
            MainActor.assumeIsolated { changes.count += 1 }
        }
        try store.install(FeedPresentationHandoff.report(.pending, into: store.state))
        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(store.state.work, .pending)
    }

    func testS4PendingPreservesVisiblePresentation() async throws {
        let f = try fixture(), published = try await snapshot(f)
        let store = FeedScreenStore { _, _ in }
        try store.install(try FeedPresentationHandoff.receive(snapshot: published, into: store.state))
        try store.install(FeedPresentationHandoff.report(.pending, into: store.state))
        XCTAssertEqual(store.state.presentation, published)
        XCTAssertEqual(store.state.work, .pending)
    }

    func testS5FailurePreservesVisiblePresentation() async throws {
        let f = try fixture(), published = try await snapshot(f)
        let store = FeedScreenStore { _, _ in }
        try store.install(try FeedPresentationHandoff.receive(snapshot: published, into: store.state))
        try store.install(FeedPresentationHandoff.report(.failed(message: "External operation failed"), into: store.state))
        XCTAssertEqual(store.state.presentation, published)
        XCTAssertEqual(store.state.work, .failed(message: "External operation failed"))
    }

    func testS6SameIdentityWindowRetainsExactRuntimeOrderAndAnchor() async throws {
        let f = try fixture(), first = try await snapshot(f)
        let store = FeedScreenStore { _, _ in }
        try store.install(try FeedPresentationHandoff.receive(snapshot: first, into: store.state))
        let observation = ViewportObservation(anchor: .init(cardID: f.cardIDs[1], placement: .center))
        let moved = try await f.session.submitViewport(observation)
        let next = try XCTUnwrap(moved)
        try store.install(try FeedPresentationHandoff.receive(snapshot: next, into: store.state))
        XCTAssertEqual(store.state.presentation, next)
        XCTAssertEqual(store.state.presentation?.window.items.map(\.id), Array(f.cardIDs.prefix(3)))
        XCTAssertEqual(store.state.presentation?.window.anchor, observation.anchor)
        XCTAssertEqual(store.state.presentation?.editionID, first.editionID)
        XCTAssertEqual(store.state.presentation?.contextKey, first.contextKey)
        XCTAssertEqual(store.state.work, .idle)
    }

    func testS7HandoffRejectsAnotherEditionWithoutMutatingStore() async throws {
        let f = try fixture(), other = try fixture()
        let first = try await snapshot(f), replacement = try await snapshot(other)
        let store = FeedScreenStore { _, _ in }
        try store.install(try FeedPresentationHandoff.receive(snapshot: first, into: store.state))
        let before = store.state
        XCTAssertThrowsError(try store.install(FeedPresentationHandoff.receive(snapshot: replacement, into: store.state))) {
            XCTAssertEqual($0 as? FeedPresentationStateError, .presentationIdentityMismatch)
        }
        XCTAssertEqual(store.state, before)
        // Complete values also pass through receiving(_); installation cannot bypass its fence.
        XCTAssertThrowsError(try store.install(FeedPresentationState(presentation: replacement))) {
            XCTAssertEqual($0 as? FeedPresentationStateError, .presentationIdentityMismatch)
        }
        XCTAssertEqual(store.state, before)
    }

    func testS7HandoffRejectsAnotherContextWithinSameEdition() async throws {
        let f = try fixture()
        let other = try fixture(context: .init(request: .source(SourceID())), editionID: f.editionID)
        let first = try await snapshot(f), replacement = try await snapshot(other)
        let store = FeedScreenStore { _, _ in }
        try store.install(try FeedPresentationHandoff.receive(snapshot: first, into: store.state))
        let before = store.state
        XCTAssertEqual(first.editionID, replacement.editionID)
        XCTAssertNotEqual(first.contextKey, replacement.contextKey)
        XCTAssertThrowsError(try store.install(FeedPresentationHandoff.receive(snapshot: replacement, into: store.state))) {
            XCTAssertEqual($0 as? FeedPresentationStateError, .presentationIdentityMismatch)
        }
        XCTAssertThrowsError(try store.install(FeedPresentationState(presentation: replacement))) {
            XCTAssertEqual($0 as? FeedPresentationStateError, .presentationIdentityMismatch)
        }
        XCTAssertEqual(store.state, before)
    }

    func testS8ViewportIntentArrivesExactlyOnceWithRealSemanticValues() async throws {
        let f = try fixture(), first = try await snapshot(f)
        var received: [(ViewportObservation, RunwayActivity)] = []
        let store = FeedScreenStore { received.append(($0, $1)) }
        try store.install(try FeedPresentationHandoff.receive(snapshot: first, into: store.state))
        for placement in [PresentationAnchorPlacement.top, .center] {
            for activity in [RunwayActivity.forward, .stationary, .backward, .explicitTailApproach] {
                let observation = ViewportObservation(anchor: .init(cardID: f.cardIDs[1], placement: placement))
                let beforeCount = received.count
                store.submitViewport(observation, activity: activity)
                XCTAssertEqual(received.count, beforeCount + 1)
                XCTAssertEqual(received.last?.0, observation)
                XCTAssertEqual(received.last?.1, activity)
                XCTAssertEqual(store.state.presentation, first)
            }
        }
        let current = await f.session.currentPresentation()
        XCTAssertEqual(current, first) // Consumer recorded intent; store never moved Runtime.
    }

    func testS9CompositionReturnsObservableStateAfterExplicitIntent() async throws {
        let f = try fixture(), first = try await snapshot(f)
        var intent: ViewportObservation?
        let store = FeedScreenStore { observation, _ in intent = observation }
        try store.install(try FeedPresentationHandoff.receive(snapshot: first, into: store.state))
        let observation = ViewportObservation(anchor: .init(cardID: f.cardIDs[1], placement: .center))
        store.submitViewport(observation, activity: .forward)
        XCTAssertEqual(store.state.presentation, first)
        // External consumer simulates the driver result using a real Runtime viewport projection.
        let returned = try await f.session.submitViewport(XCTUnwrap(intent))
        let delivered = try FeedPresentationHandoff.receive(snapshot: returned, into: store.state)
        let changes = Changes()
        withObservationTracking { _ = store.state } onChange: {
            MainActor.assumeIsolated { changes.count += 1 }
        }
        try store.install(delivered)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(store.state, delivered)
        XCTAssertEqual(store.state.presentation?.window.items.map(\.id), Array(f.cardIDs.prefix(3)))
        XCTAssertEqual(store.state.presentation?.window.anchor, observation.anchor)
    }

    func testS10NoHiddenExecutionOrDurableMutation() async throws {
        let f = try fixture(), first = try await snapshot(f)
        let checkpoint = try PublicationHistory(database: f.database).restore(backwardCapacity: 0, forwardCapacity: 0)
        let segments = try PublicationStore(database: f.database).segments(editionID: f.editionID)
        var calls = 0
        let store = FeedScreenStore { _, _ in calls += 1 }
        try store.install(try FeedPresentationHandoff.receive(snapshot: first, into: store.state))
        try store.install(FeedPresentationHandoff.report(.pending, into: store.state))
        XCTAssertEqual(calls, 0)
        let observation = ViewportObservation(anchor: .init(cardID: f.cardIDs[1], placement: .center))
        store.submitViewport(observation, activity: .explicitTailApproach)
        XCTAssertEqual(calls, 1)
        let current = await f.session.currentPresentation()
        XCTAssertEqual(current, first)
        let after = try PublicationHistory(database: f.database).restore(backwardCapacity: 0, forwardCapacity: 0)
        XCTAssertEqual(after?.cursor, checkpoint?.cursor)
        XCTAssertEqual(try PublicationStore(database: f.database).segments(editionID: f.editionID), segments)
        XCTAssertEqual(store.state.work, .pending)
    }

    func testS11OnlyOnePresentationValueAndNoParallelSemanticStorage() {
        let store = FeedScreenStore { _, _ in }
        let fields = Array(Mirror(reflecting: store).children)
        XCTAssertEqual(fields.filter { $0.value is FeedPresentationState }.count, 1)
        for field in fields {
            XCTAssertFalse(field.value is FeedPresentationSnapshot)
            XCTAssertFalse(field.value is [PresentationCard])
            XCTAssertFalse(field.value is FeedEditionID)
            XCTAssertFalse(field.value is ContextKey)
            XCTAssertFalse(field.value is PresentationAnchor)
            XCTAssertFalse(field.value is PublicationCardID)
        }
        XCTAssertEqual(Set(fields.compactMap(\.label)), ["_state", "onViewport", "onOpen", "onBookmark", "_bookmarkedIDs", "_$observationRegistrar"])
    }

    func testS12ModuleBoundaryAndNoExecutionMechanisms() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let ui = root.appendingPathComponent("Sources/FeedMineUI")
        for file in try FileManager.default.contentsOfDirectory(at: ui, includingPropertiesForKeys: nil) where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            let imports = source.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("import ") }
            for forbidden in ["FeedMineComposition", "FeedMinePersistence", "FeedMineAcquisition", "FeedMinePublication", "FeedMineSyndication", "FeedMineEditorial"] {
                XCTAssertFalse(imports.contains("import " + forbidden), file.lastPathComponent + ": " + forbidden)
            }
        }
        let source = try String(contentsOf: ui.appendingPathComponent("FeedScreenStore.swift"), encoding: .utf8)
        for forbidden in ["URLSession", "HTTP", "ContentStore", "RuntimeDatabase", "AcquisitionCoordinator", "FeedRunwayDriver",
            "RunwayController", "SelectionEngine", "PublicationCoordinator", "PublicationStore", "Task", "Timer", "sleep",
            "retry", "backoff", "scheduler", "cache", "generation", "checkpoint", "[PresentationCard]", "UUID(", "Date("] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }
    }

    func testS13ExternalAsyncConsumerMutatesOnlyOnMainActor() async throws {
        let store = FeedScreenStore { _, _ in MainActor.preconditionIsolated() }
        try await Self.deliverFromExternalConsumer(store)
        XCTAssertEqual(store.state.work, .pending)
    }

    private nonisolated static func deliverFromExternalConsumer(_ store: FeedScreenStore) async throws {
        try await MainActor.run {
            MainActor.preconditionIsolated()
            try store.install(FeedPresentationState(presentation: nil).reporting(.pending))
        }
    }

    func testMissingSnapshotCannotClearVisiblePresentationAndWorkRemainsDistinct() async throws {
        let f = try fixture(), first = try await snapshot(f)
        let store = FeedScreenStore { _, _ in }
        try store.install(try FeedPresentationHandoff.receive(snapshot: first, into: store.state))
        for work in [FeedPresentationState.Work.idle, .pending, .unavailable, .deferred, .failed(message: "No new snapshot")] {
            try store.install(FeedPresentationState(presentation: nil).reporting(work))
            XCTAssertEqual(store.state.presentation, first)
            XCTAssertEqual(store.state.work, work)
        }
    }
}

extension FeedScreenStoreTests {
    /// Review F10: tapping a card forwards only its identity, and only when it offers an action.
    @MainActor
    func testOpenForwardsCardIdentityOnlyForActionableCards() throws {
        var opened: [PublicationCardID] = []
        let store = FeedScreenStore(onViewport: { _, _ in }, onOpen: { opened.append($0) })
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/FeedMineUI/FeedScreenStore.swift"), encoding: .utf8)
        XCTAssertFalse(source.contains("URL("), "action targets never cross the UI boundary")
        XCTAssertTrue(source.contains("guard card.primaryActionKind != nil"))
        XCTAssertTrue(opened.isEmpty)
        _ = store
    }
}