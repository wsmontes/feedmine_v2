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
        constrained: Bool = false, free: Int64? = nil, useful: Double? = nil) -> StagePressureFacts {
        .init(thermal: thermal, lowPowerMode: lowPower, networkConstrained: constrained, freeStorageBytes: free,
            usefulCardsPerSecond: useful)
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

    /// P05/A6: zero is a denial, not "disabled twice". No pressure combination may invent one target out of it.
    func testExplicitZeroAuthorizationRemainsZeroUnderEveryPressure() throws {
        let levels: [StagePressureFacts.Level] = [.nominal, .fair, .serious, .critical]
        for thermal in levels {
            for lowPower in [false, true] {
                for constrained in [false, true] {
                    for free in [nil, 10_000_000] as [Int64?] {
                        let pressure = facts(thermal: thermal, lowPower: lowPower, constrained: constrained,
                            free: free, useful: 0.2)
                        let budget = StageBudgetPolicy.budget(pressure: pressure,
                            settings: CollectionLaunchSettings(initialParallelism: 0))
                        XCTAssertEqual(budget.acquisition.targetWorkCapacity, 0,
                            "thermal=\(thermal) lowPower=\(lowPower) constrained=\(constrained) free=\(String(describing: free))")
                        XCTAssertEqual(try plannedTargets(budget), 0)
                    }
                }
            }
        }
        let nominal = StageBudgetPolicy.budget(pressure: facts(), settings: CollectionLaunchSettings(initialParallelism: 0))
        XCTAssertEqual(nominal.acquisition.targetWorkCapacity, 0)
    }

    /// P05: under the **same** settings, measured useful yield changes the examination budget. This is the
    /// adaptation the old test (1 vs 8 configured targets) never proved.
    func testMeasuredUsefulCapacityChangesBudgetUnderSameSettings() {
        let settings = CollectionLaunchSettings()
        let starved = StageBudgetPolicy.budget(pressure: facts(useful: 0.4), settings: settings)
        let everyday = StageBudgetPolicy.budget(pressure: facts(useful: 1.5), settings: settings)
        let burst = StageBudgetPolicy.budget(pressure: facts(useful: 3.5), settings: settings)
        XCTAssertEqual(starved.examinedCandidateCapacity, 8)
        XCTAssertEqual(everyday.examinedCandidateCapacity, 16)
        XCTAssertEqual(burst.examinedCandidateCapacity, 32)
        XCTAssertEqual(starved.acquisition.targetWorkCapacity, burst.acquisition.targetWorkCapacity,
            "a mesma configuração autoriza o mesmo plano; só o trabalho medido se ajusta")
        let unknown = StageBudgetPolicy.budget(pressure: facts(), settings: settings)
        XCTAssertEqual(unknown.examinedCandidateCapacity, 32, "ausência de medida não é rendimento zero")
    }

    /// P05: computing a budget is a snapshot read. The volume is sampled off the MainActor at a lifecycle moment,
    /// so the getter cannot block the UI on filesystem I/O.
    @MainActor
    func testResourceReadNeverPerformsFilesystemIOOnMainActor() async {
        final class Probe: @unchecked Sendable {
            private let lock = NSLock()
            private var reads = 0
            private var onMainThread: [Bool] = []
            func record() { lock.lock(); reads += 1; onMainThread.append(Thread.isMainThread); lock.unlock() }
            var count: Int { lock.lock(); defer { lock.unlock() }; return reads }
            var mainThreadReads: Int { lock.lock(); defer { lock.unlock() }; return onMainThread.filter { $0 }.count }
        }
        let probe = Probe()
        let capacity = StageStorageCapacity { probe.record(); return 512_000_000 }
        XCTAssertTrue(Thread.isMainThread)
        _ = StageBudgetPolicy.budget(pressure: facts(free: capacity.current), settings: .init())
        XCTAssertEqual(probe.count, 0, "ler o snapshot não lê o disco")
        await capacity.refresh()
        XCTAssertEqual(probe.count, 1)
        XCTAssertEqual(probe.mainThreadReads, 0, "a amostra do volume corre fora do MainActor")
        XCTAssertEqual(capacity.current, 512_000_000)
        _ = StageBudgetPolicy.budget(pressure: facts(free: capacity.current), settings: .init())
        XCTAssertEqual(probe.count, 1, "o orçamento reutiliza o snapshot; não amostra por leitura")
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

    /// R22/P14: sustained **useful** headroom at the plan's declared demand. 1.000 sources (100 independent
    /// targets × 10), 10.000 candidates, one serial writer. Each stage is measured where it runs: admission,
    /// examination and publication; the reference consumption is 1 card/s and the plan's 10× target is asserted on
    /// published/sec. Failing the target here is a finding, not a reason to lower it.
    func testUsefulStageHeadroomAtDeclaredDemand() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let context = FeedContext(request: .main), version = PolicyVersion(rawValue: 1)
        let revision = EditorialRevision(id: EditorialRevisionID(), contextKey: context.key,
            catalogGeneration: .init(rawValue: 1), userSelectionVersion: version,
            eligibilityPolicyVersion: version, scoringPolicyVersion: version,
            sequencingPolicyVersion: version, exposurePolicyVersion: version,
            selectionSchemaVersion: .init(rawValue: 1))
        let plan = try XCTUnwrap(FeedPlan(context: context, revision: revision))
        let authority = AcquisitionTargetAuthority(database: database)
        let admission = AdmissionPolicy(database: database)
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        // 100 independent targets, 10 sources each, 10 observations per source.
        var batches: [(AcquisitionTargetID, AcquisitionBatch)] = []
        for targetIndex in 0..<100 {
            let sources = (0..<10).map { _ in SourceID() }
            let target = try authority.register(id: AcquisitionTargetID(), connectorKind: .syndication,
                authorizedSources: Set(sources))
            let observations = sources.flatMap { source in
                (0..<10).map { item in
                    AcquisitionObservation(objectIdentity: .init(connectorKind: .syndication, namespace: "load",
                            value: "\(targetIndex)-\(source.rawValue)-\(item)", role: .object),
                        versionIdentity: nil, precedence: .makeCurrent, availability: .available,
                        headline: "Story \(targetIndex)/\(item)", summary: "summary", bodyText: nil,
                        authoredAt: date, modifiedAt: nil, observedAt: date.addingTimeInterval(Double(item)),
                        language: nil, primaryLink: nil, searchProjection: nil, providerID: nil,
                        memberships: [.init(sourceID: source, kind: .direct)], mediaCandidates: [])!
                }
            }
            let batch = try XCTUnwrap(AcquisitionBatch(targetID: target.id, targetGeneration: 1,
                expectedCheckpointRevision: 0, observations: observations, nextCheckpoint: nil))
            batches.append((target.id, batch))
        }

        let admissionStart = ProcessInfo.processInfo.systemUptime
        var admitted = 0
        for (_, batch) in batches {
            let receipt = try admission.admit(batch)
            admitted += batch.observations.count - receipt.rejectedObservations.count
        }
        let admissionSeconds = ProcessInfo.processInfo.systemUptime - admissionStart

        let examineStart = ProcessInfo.processInfo.systemUptime
        let window = try CandidateProvider(contentStore: ContentStore(database: database))
            .candidates(for: plan, after: nil, examinedCapacity: 10_000)
        let examineSeconds = ProcessInfo.processInfo.systemUptime - examineStart

        let publicationStart = ProcessInfo.processInfo.systemUptime
        let candidates = window.candidates
        XCTAssertEqual(admitted, 10_000)
        XCTAssertEqual(candidates.count, 10_000)
        var segmentSeconds: [Double] = []
        let editionID = FeedEditionID(), coordinator = PublicationCoordinator(database: database)
        for segment in 0..<10 {
            let slice = Array(candidates[(segment * 1_000)..<((segment + 1) * 1_000)])
            let selection = SelectionResult(editorialRevision: revision, orderedCandidates: slice,
                supplyReport: .init(examinedCount: slice.count, nextCursor: nil, exhausted: true))
            let prepared = LocalPreparedPublication(
                inputs: slice.map { candidate in
                    PublicationPreparationInput(origin: PublishedOrigin(originRecordID: candidate.originRecordID,
                        originRevisionID: candidate.originRevisionID, sourceID: nil, providerID: nil,
                        sourceDisplayName: "Load", providerDisplayName: nil),
                        contentEntityID: nil, contentClusterID: nil, primaryAction: .localContentDetail,
                        presentation: .textOnly)
                }, cardIDs: slice.map { _ in PublicationCardID() })
            let drafts = try PublicationPreparation.drafts(selection: selection, inputs: prepared.inputs)
            let started = ProcessInfo.processInfo.systemUptime
            if segment == 0 {
                _ = try coordinator.createEdition(.init(selection: selection, drafts: drafts, editionID: editionID,
                    publicationSchemaVersion: .init(rawValue: 1), selectionSeed: 1, editionCreatedAt: date,
                    segmentID: FeedSegmentID(), segmentSeed: 1, segmentCreatedAt: date,
                    cardIDs: prepared.cardIDs))
            } else {
                _ = try coordinator.append(.init(selection: selection, drafts: drafts, editionID: editionID,
                    segmentID: FeedSegmentID(), segmentSeed: UInt64(segment + 1), segmentCreatedAt: date,
                    cardIDs: prepared.cardIDs))
            }
            segmentSeconds.append(ProcessInfo.processInfo.systemUptime - started)
        }
        let publicationSeconds = ProcessInfo.processInfo.systemUptime - publicationStart
        let sortedSegments = segmentSeconds.sorted()
        let p95 = sortedSegments[max(0, Int(ceil(0.95 * Double(sortedSegments.count))) - 1)]
        let admittedPerSecond = Double(admitted) / admissionSeconds
        let examinedPerSecond = Double(window.examinedCount) / examineSeconds
        let publishedPerSecond = 10_000 / publicationSeconds
        print("R22 headroom sources=1000 targets=100 candidates=10000 admitted/s=\(admittedPerSecond) "
            + "examined/s=\(examinedPerSecond) published/s=\(publishedPerSecond) p95_segment=\(p95)")

        // The plan's target is useful cards, not raw examined rows: 10× the 1 card/s everyday demand, measured as
        // published cards per second. Admission and examination rates are recorded as measured, not redefined.
        XCTAssertEqual(admitted, 10_000)
        XCTAssertEqual(window.examinedCount, 10_000)
        XCTAssertGreaterThanOrEqual(publishedPerSecond, 10,
            "10× a demanda cotidiana de 1 carta/s, medida em cartas publicadas por segundo "
                + "(admitted/s \(admittedPerSecond), examined/s \(examinedPerSecond), p95 \(p95) s)")
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
