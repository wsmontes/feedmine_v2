import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineAcquisition
import FeedMineEditorial
import FeedMinePublication
import FeedMineRuntime
import FeedMineComposition

private final class CoverageJournal: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [AcquisitionTargetID] = []
    private var terminals: [AcquisitionTargetID] = []
    func enter(_ id: AcquisitionTargetID) { lock.withLock { entries.append(id) } }
    func settle(_ id: AcquisitionTargetID) { lock.withLock { terminals.append(id) } }
    var pulls: [AcquisitionTargetID] { lock.withLock { entries } }
    var outcomes: [AcquisitionTargetID] { lock.withLock { terminals } }
}
private struct CoverageConnector: FeedConnector {
    let journal: CoverageJournal
    let sources: [SourceID]
    func pull(_ request: FeedConnectorPull) async throws -> FeedConnectorEvent {
        journal.enter(request.targetID)
        defer { journal.settle(request.targetID) }
        let observations = (0..<20).map { index in
            AcquisitionObservation(objectIdentity: .init(connectorKind: .syndication, namespace: request.targetID.rawValue.uuidString,
                value: "item-\(index)", role: .object), versionIdentity: nil, precedence: .makeCurrent,
                availability: .available, headline: "Item \(index)", summary: nil, bodyText: nil,
                authoredAt: Date(timeIntervalSince1970: Double(100 - index)), modifiedAt: nil,
                observedAt: Date(timeIntervalSince1970: 100), language: nil, primaryLink: nil,
                searchProjection: nil, providerID: nil, memberships: sources.map { .init(sourceID: $0, kind: .direct) }, mediaCandidates: [])!
        }
        return .batch(.init(targetID: request.targetID, targetGeneration: request.targetGeneration,
            expectedCheckpointRevision: request.checkpointRevision, observations: observations, nextCheckpoint: nil)!, transportByteCount: 100)
    }
}
@MainActor
final class SelectedSourceCoverageTests: XCTestCase {
    private struct Fixture {
        let database: RuntimeDatabase
        let plan: FeedPlan
        let policy: ResolvedSelectionPolicy
        let session: FeedSession
        let snapshot: SyndicationAcquisitionSnapshot
        let coordinator: AcquisitionCoordinator
        let journal: CoverageJournal
        let targets: [AcquisitionTarget]
    }
    private func fixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let context = FeedContext(request: .main), v = PolicyVersion(rawValue: 1)
        let revision = EditorialRevision(id: EditorialRevisionID(), contextKey: context.key,
            catalogGeneration: .init(rawValue: 1), userSelectionVersion: v, eligibilityPolicyVersion: v,
            scoringPolicyVersion: v, sequencingPolicyVersion: v, exposurePolicyVersion: v, selectionSchemaVersion: .init(rawValue: 1))
        let plan = FeedPlan(context: context, revision: revision)!
        let policy = ResolvedSelectionPolicy(contextKey: context.key, userSelectionVersion: v, eligibilityPolicyVersion: v,
            scoringPolicyVersion: v, sequencingPolicyVersion: v, exposurePolicyVersion: v, selectionSchemaVersion: revision.selectionSchemaVersion,
            eligibility: .structuralOnly, scoring: .equal, sequencing: .recencyDescending, exposure: .excludePublishedRevisions)
        let sources = (0..<4).map { _ in SourceID() }
        let targets = try (0..<4).map { index in
            try AcquisitionTargetAuthority(database: database).register(id: .init(rawValue: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!),
                connectorKind: .syndication, authorizedSources: [sources[index]])
        }
        let registrations = targets.enumerated().map { index, target in
            let binding = SourceBinding(id: SourceBindingID(), sourceID: sources[index],
                externalPrincipal: .init(connectorKind: .syndication, namespace: "coverage", value: "source-\(index)", role: .principal),
                aliases: [], generation: 1, state: .enabled)!
            return SyndicationTargetRegistration(targetID: target.id, targetGeneration: 1,
                endpoint: URL(string: "https://coverage.test/\(index)")!, bindings: [binding])!
        }
        let transport = URLSession(configuration: .ephemeral)
        addTeardownBlock { transport.invalidateAndCancel() }
        let snapshot = try SyndicationAcquisitionSnapshot(database: database, registrations: registrations, session: transport, redirectCapacity: 0)
        let journal = CoverageJournal()
        let byTarget = Dictionary(uniqueKeysWithValues: zip(targets.map(\.id), sources))
        let coordinator = AcquisitionCoordinator(database: database, connectorForTarget: { target in
            CoverageConnector(journal: journal, sources: [byTarget[target.id]!])
        }, concurrentTargetLimit: 2)
        return .init(database: database, plan: plan, policy: policy, session: FeedSession(publicationHistory: .init(database: database)),
            snapshot: snapshot, coordinator: coordinator, journal: journal, targets: targets)
    }
    nonisolated private static func prepare(_ selection: SelectionResult) -> LocalPreparedPublication {
        .init(inputs: selection.orderedCandidates.map { candidate in
            .init(origin: .init(originRecordID: candidate.originRecordID, originRevisionID: candidate.originRevisionID,
                sourceID: candidate.sourceIDs.first, providerID: nil, sourceDisplayName: "Fixture", providerDisplayName: nil),
                contentEntityID: nil, contentClusterID: nil, primaryAction: .localContentDetail, presentation: .textOnly)
        }, cardIDs: selection.orderedCandidates.map { _ in PublicationCardID() })
    }
    private func resources(targetCapacity: Int = 2) -> FeedRunwayDriverResources {
        .init(runway: .init(localWorkAllowed: true, examinedCandidateCapacity: 100, readyProbeBound: 64,
            readyProbeCeiling: 128, forwardAdvanceProbeBound: 64, reserveCards: 16)!,
            acquisition: .init(targetWorkCapacity: targetCapacity, batchCapacityPerNewExecution: 1,
                observationCapacityPerBatch: 100, byteCapacityPerBatch: 100_000)!)
    }
    private func cold(_ f: Fixture) async throws -> FeedPresentationSnapshot {
        let cold = try ColdFeedBootstrap(session: f.session, plan: f.plan, policy: f.policy, acquisition: f.snapshot,
            coordinator: f.coordinator, prepare: Self.prepare)
        let identity = ColdFeedPublicationIdentity(editionID: FeedEditionID(), publicationSchemaVersion: .init(rawValue: 1),
            selectionSeed: 1, editionCreatedAt: Date(timeIntervalSince1970: 200), segmentID: FeedSegmentID(), segmentSeed: 1,
            segmentCreatedAt: Date(timeIntervalSince1970: 201), anchorPlacement: .top, checkpointedAt: Date(timeIntervalSince1970: 202))!
        guard case .published(let snapshot) = try await cold.run(identity: identity,
            resources: .init(localExaminedCapacity: 100, acquisition: resources().acquisition)!, backwardCapacity: 0, forwardCapacity: 64)
        else { throw NSError(domain: "Expected publication", code: 1) }
        return snapshot
    }
    private func driver(_ f: Fixture) throws -> (FeedRunwayDriver, RunwayController) {
        let runway = RunwayController(configuration: .init(policyInputs: .init(safetyFactor: 1, releaseMarginSeconds: 0)!,
            consumptionSampleLimit: 4, replenishmentSampleLimit: 4)!)
        return (try FeedRunwayDriver(session: f.session, runway: runway, plan: f.plan, policy: f.policy,
            acquisition: f.snapshot, coordinator: f.coordinator, monotonicNow: { .init(seconds: 1)! },
            makeSegmentIdentity: { .init(segmentID: FeedSegmentID(), segmentSeed: 2, segmentCreatedAt: Date(timeIntervalSince1970: 203))! },
            prepare: Self.prepare,
            selectedSourceCoverage: .init(selectedSourceCoverageFor: f.plan.context.key, editorialRevisionID: f.plan.revision.id)), runway)
    }
    func testP1StationaryHealthyRunwayStillExecutesRemainingSelectedTargets() async throws {
        let f = try fixture(), first = try await cold(f)
        XCTAssertEqual(Set(f.journal.pulls), Set(f.targets.prefix(2).map(\.id)))
        XCTAssertEqual(f.journal.outcomes.count, 2)
        let (driver, runway) = try driver(f)
        _ = try await driver.activateCurrentPresentation(resources: resources())
        try await runway.submitObservation(.init(editionID: first.editionID, anchorCardID: first.window.anchor.cardID,
            sampledAt: .init(seconds: 2)!, activity: .stationary))
        _ = try await driver.drive(resources: resources())
        let state = await runway.snapshot()
        XCTAssertEqual(state.lastCoverage, .healthy)
        let ready = try PublicationHistory(database: f.database).readyAhead(editionID: first.editionID,
            anchorCardID: first.window.anchor.cardID, probeBound: 64)
        if case .exact(let count) = ready.amount { XCTAssertGreaterThanOrEqual(count, 16) }
        else { XCTFail("Expected exact runway") }
        XCTAssertEqual(Set(f.journal.pulls), Set(f.targets.map(\.id)), "Healthy depth must not starve the other selected targets")
        XCTAssertEqual(f.journal.pulls.count, 4)
        XCTAssertEqual(f.journal.outcomes.count, 4)
    }
}
