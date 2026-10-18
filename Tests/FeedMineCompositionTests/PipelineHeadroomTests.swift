import Foundation
import XCTest
import FeedMineDomain
import FeedMineAcquisition
import FeedMineEditorial
@testable import FeedMinePersistence
@testable import FeedMinePublication
@testable import FeedMineComposition
import FeedMineRuntime

/// R09: the stage budgets are an explicit function of **measured** pressure. The bootstrap keeps the documented
/// 48 plan / 8 sockets / 32 examined / 1 MB; pressure may only reduce work, never below one eligible target, and
/// never turns local reading off. Fairness is asserted as progress of an eligible target, not as created tasks.
final class PipelineHeadroomTests: XCTestCase {
    private func demand() -> AcquisitionDemand {
        AcquisitionDemand(contextKey: ContextKey(request: .main), editorialRevisionID: EditorialRevisionID(),
            purpose: .readerContinuation, pressure: .coverageDeficit(requiredCards: 20),
            localSupply: ExhaustedLocalSupply(readyCards: 0)!)!
    }
    private func target() -> AcquisitionTarget {
        AcquisitionTarget(id: AcquisitionTargetID(), connectorKind: ConnectorKind(rawValue: "syndication"),
            generation: 1, state: .enabled, checkpointRevision: 0, checkpoint: nil)!
    }
    private func facts(thermal: StagePressureFacts.Level = .nominal, lowPower: Bool = false,
        constrained: Bool = false, free: Int64? = nil) -> StagePressureFacts {
        .init(thermal: thermal, lowPowerMode: lowPower, networkConstrained: constrained, freeStorageBytes: free)
    }
    private func plannedTargets(_ budget: StageBudget) throws -> Int {
        let result = try AcquisitionPlanner.plan(demand: demand(),
            eligibleTargets: (0..<10).map { _ in target() }, activeExecutions: [],
            resources: budget.acquisition)
        guard case .planned(let plan) = result else { return 0 }
        return plan.work.count
    }

    /// More measured resources authorize more useful starts over the same demand.
    func testAvailableResourcesIncreaseUsefulWork() throws {
        let small = StageBudgetPolicy.bootstrap(CollectionLaunchSettings(initialParallelism: 1))
        let large = StageBudgetPolicy.bootstrap(CollectionLaunchSettings(initialParallelism: 8))
        XCTAssertEqual(try plannedTargets(small), 1)
        XCTAssertEqual(try plannedTargets(large), 8)
        XCTAssertGreaterThan(try plannedTargets(large), try plannedTargets(small))
    }

    /// Measured pressure reduces the plan and the examined window but an eligible target still progresses.
    func testPressureReducesWorkWithoutStarvingEligibleTargets() throws {
        let nominal = StageBudgetPolicy.budget(pressure: facts(), settings: .init())
        let serious = StageBudgetPolicy.budget(pressure: facts(thermal: .serious), settings: .init())
        let critical = StageBudgetPolicy.budget(pressure: facts(thermal: .critical, lowPower: true,
            constrained: true, free: 50_000_000), settings: .init())
        XCTAssertLessThan(serious.acquisition.targetWorkCapacity, nominal.acquisition.targetWorkCapacity)
        XCTAssertLessThan(critical.acquisition.targetWorkCapacity, serious.acquisition.targetWorkCapacity)
        XCTAssertGreaterThanOrEqual(critical.acquisition.targetWorkCapacity, 1,
            "a pressão não zera a autorização: um elegível ainda progride")
        XCTAssertGreaterThanOrEqual(critical.examinedCandidateCapacity, 8)
        XCTAssertTrue(critical.localWorkAllowed, "pressão não desliga a leitura local")
        XCTAssertGreaterThanOrEqual(try plannedTargets(critical), 1)
        XCTAssertLessThanOrEqual(nominal.acquisition.targetWorkCapacity,
            CollectionLaunchSettings.defaultInitialParallelism)
        XCTAssertLessThanOrEqual(critical.acquisition.byteCapacityPerBatch,
            nominal.acquisition.byteCapacityPerBatch)
    }

    /// No new facts means no invented work: the empty offer keeps its disposition across opportunities; the same
    /// budget authorizes work the moment eligibility facts exist.
    func testExhaustedSupplyWaitsForNewFacts() throws {
        let budget = StageBudgetPolicy.budget(pressure: facts(thermal: .serious), settings: .init())
        for _ in 0..<3 {
            XCTAssertEqual(try AcquisitionPlanner.plan(demand: demand(), eligibleTargets: [],
                activeExecutions: [], resources: budget.acquisition), .disposition(.noEligibleTargets))
        }
        XCTAssertGreaterThan(try plannedTargets(budget), 0)
    }

    /// R10: admission and publication remain atomic while they contend for the one serial writer. The stage
    /// durations are **measured and printed** (the register records them); the assertion is only the operational
    /// guard that neither stage holds the writer indefinitely, plus the durable consistency of both results.
    func testConcurrentDurableStagesPreserveWriterConsistency() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let v = PolicyVersion(rawValue: 1)
        let revision = EditorialRevision(id: EditorialRevisionID(), contextKey: .init(request: .main),
            catalogGeneration: .init(rawValue: 1), userSelectionVersion: v, eligibilityPolicyVersion: v,
            scoringPolicyVersion: v, sequencingPolicyVersion: v, exposurePolicyVersion: v,
            selectionSchemaVersion: .init(rawValue: 1))
        let edition = PublicationStore.EditionRecord(id: FeedEditionID(), editorialRevision: revision,
            publicationSchemaVersion: 1, selectionSeed: 1, createdAt: Date())
        func card(_ title: String) -> PublicationStore.CardRecord {
            .init(id: PublicationCardID(), originRecordID: OriginRecordID(), originRevisionID: OriginRevisionID(),
                sourceID: nil, providerID: nil, sourceDisplayName: "Local", providerDisplayName: nil,
                contentEntityID: nil, contentClusterID: nil, title: title, primaryText: "text",
                timestampValue: nil, timestampKind: nil, mediaKey: nil, mediaPixelWidth: nil,
                mediaPixelHeight: nil, mediaMimeType: nil, renderLayout: "textOnly",
                renderMediaAspectRatio: nil, primaryActionKind: nil, primaryActionReference: nil)
        }
        let first = card("first"), second = card("second")
        let store = PublicationStore(database: database)
        try store.createInitialEdition(edition,
            firstSegment: .init(id: FeedSegmentID(), editionID: edition.id, ordinal: 0, segmentSeed: 1,
                publicationSchemaVersion: 1, createdAt: Date(), cardIDs: [first.id]),
            cards: [first],
            initialCheckpoint: .init(editionID: edition.id, cardID: first.id, anchorPlacement: "top",
                updatedAt: Date()))
        let source = SourceID()
        let target = try AcquisitionTargetAuthority(database: database).register(id: AcquisitionTargetID(),
            connectorKind: .syndication, authorizedSources: [source])
        let observation = AcquisitionObservation(
            objectIdentity: .init(connectorKind: .syndication, namespace: "r10", value: "one", role: .object),
            versionIdentity: nil, precedence: .makeCurrent, availability: .available, headline: "admitted",
            summary: nil, bodyText: nil, authoredAt: nil, modifiedAt: nil, observedAt: Date(),
            language: nil, primaryLink: nil, searchProjection: nil, providerID: nil,
            memberships: [.init(sourceID: source, kind: .direct)], mediaCandidates: [])!

        let started = ProcessInfo.processInfo.systemUptime
        async let appended = Task.detached {
            try store.appendSegment(.init(id: FeedSegmentID(), editionID: edition.id, ordinal: 1,
                segmentSeed: 2, publicationSchemaVersion: 1, createdAt: Date(), cardIDs: [second.id]),
                cards: [second], expectingTailCardID: first.id)
        }.value
        async let admitted = Task.detached {
            try AdmissionPolicy(database: database).admit(.init(targetID: target.id, targetGeneration: 1,
                expectedCheckpointRevision: 0, observations: [observation], nextCheckpoint: nil)!)
        }.value
        let (_, admission) = try await (appended, admitted)
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        print("R10 durable stages under contention: append+admission in \(elapsed) s")

        // Both durable outcomes exist and neither is partial.
        XCTAssertEqual(try PublicationStore(database: database).segments(editionID: edition.id).count, 2,
            "a publicação concorrente deixa o segmento inteiro")
        XCTAssertNotNil(try PublicationStore(database: database).card(id: second.id))
        XCTAssertEqual(admission.rejectedObservations.count, 0)
        XCTAssertEqual(try ContentStore(database: database)
            .candidateWindow(sourceID: source, after: nil, examinedCapacity: 10).records.count, 1,
            "a admissão concorrente deixa o supply inteiro")
        XCTAssertLessThan(elapsed, 5,
            "guarda operacional: nenhum estágio durável pode segurar o escritor indefinidamente")
    }

    /// The two operational bounds the plan keeps are still the documented ones, and the bootstrap still states 48.
    func testForegroundCadenceAndCardGuardRemainOperationalBounds() {
        XCTAssertEqual(ForegroundDriveCadence.interval, 10, "a oportunidade foreground é ≥ 10 s")
        XCTAssertEqual(FeedSession.maxAdmittedItems, 2000, "o teto de cartas é uma guarda de memória")
        XCTAssertEqual(CollectionLaunchSettings.defaultInitialParallelism, 48)
        XCTAssertEqual(CollectionLaunchSettings.maximumConcurrentTargets, 8)
        let bootstrap = StageBudgetPolicy.bootstrap()
        XCTAssertEqual(bootstrap.acquisition.targetWorkCapacity, 48)
        XCTAssertEqual(StageBudgetPolicy.budget(pressure: nil).acquisition.targetWorkCapacity, 48,
            "sem fatos medidos, o bootstrap documentado vale")
    }
}
