import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineAcquisition
import FeedMineEditorial
@testable import FeedMinePublication
@testable import FeedMineRuntime
@testable import FeedMineComposition

private final class DriverClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double = 0
    func next() -> RunwayMonotonicTime { lock.withLock { value += 1; return .init(seconds:value)! } }
    /// Moves the clock forward without recording calls: a test that observes the runway itself needs the driver's
    /// later opportunities to stay monotonic over those observations.
    func jump(to seconds: Double) { lock.withLock { value = seconds } }
}
private final class DriverMediaJournal: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    func append(_ value: String) { lock.withLock { entries.append(value) } }
    func reset() { lock.withLock { entries.removeAll() } }
    var values: [String] { lock.withLock { entries } }
}

private final class PrepareGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var entered = false
    private var released = false
    private var enteredHandler: (() -> Void)?

    func onEntered(_ handler: @escaping () -> Void) {
        condition.lock()
        if entered { condition.unlock(); handler(); return }
        enteredHandler = handler
        condition.unlock()
    }

    func wait() {
        condition.lock()
        entered = true
        let handler = enteredHandler
        enteredHandler = nil
        condition.broadcast()
        condition.unlock()
        handler?()
        condition.lock()
        while !released { condition.wait() }
        condition.unlock()
    }

    func release() {
        condition.lock(); released = true; condition.broadcast(); condition.unlock()
    }
}

@MainActor
final class FeedRunwayDriverTests: XCTestCase {
    private enum Failure: Error, Equatable { case preparation }
    private struct Fixture {
        let database: RuntimeDatabase
        let location: RuntimeDatabaseLocation
        let plan: FeedPlan
        let policy: ResolvedSelectionPolicy
        let edition: FeedEditionID
        let cards: [PublicationCardID]
        let source: SourceID
        let target: AcquisitionTarget
        /// The second registered target/source: the one a two-target opportunity keeps unrelated to the first.
        let otherTarget: AcquisitionTarget
        let otherSource: SourceID
        let session: FeedSession
        let runway: RunwayController
        let driver: FeedRunwayDriver
        let acquisition: SyndicationAcquisitionSnapshot
        let coordinator: AcquisitionCoordinator
        let http: DriverHTTPFixture
        let otherHTTP: DriverHTTPFixture
        let clock: DriverClock
        let publications: DriverPublicationLog
    }

    /// R06: the receipts a drain concluded, in the order they were delivered.
    final class DriverPublicationLog: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [PublicationReceipt] = []
        var values: [PublicationReceipt] { lock.lock(); defer { lock.unlock() }; return storage }
        func append(_ receipt: PublicationReceipt) { lock.lock(); storage.append(receipt); lock.unlock() }
    }
    nonisolated private static func prepared(_ selection:SelectionResult) -> LocalPreparedPublication {
        .init(inputs:selection.orderedCandidates.map {
            .init(origin:.init(originRecordID:$0.originRecordID,originRevisionID:$0.originRevisionID,sourceID:nil,
                providerID:$0.providerID,sourceDisplayName:"Source",providerDisplayName:nil),contentEntityID:nil,
                contentClusterID:nil,primaryAction:.localContentDetail,presentation:.textOnly)
        },cardIDs:selection.orderedCandidates.map { _ in PublicationCardID() })
    }
    private func plan(_ context:FeedContext,revisionID:EditorialRevisionID = EditorialRevisionID()) -> FeedPlan {
        let v = PolicyVersion(rawValue:1)
        let r = EditorialRevision(id:revisionID,contextKey:context.key,catalogGeneration:.init(rawValue:1),userSelectionVersion:v,
            eligibilityPolicyVersion:v,scoringPolicyVersion:v,sequencingPolicyVersion:v,exposurePolicyVersion:v,selectionSchemaVersion:.init(rawValue:1))
        return FeedPlan(context:context,revision:r)!
    }
    private func policy(_ plan:FeedPlan) -> ResolvedSelectionPolicy {
        let r = plan.revision
        return .init(contextKey:r.contextKey,userSelectionVersion:r.userSelectionVersion,eligibilityPolicyVersion:r.eligibilityPolicyVersion,
            scoringPolicyVersion:r.scoringPolicyVersion,sequencingPolicyVersion:r.sequencingPolicyVersion,exposurePolicyVersion:r.exposurePolicyVersion,
            selectionSchemaVersion:r.selectionSchemaVersion,eligibility:.structuralOnly,scoring:.equal,sequencing:.recencyDescending,exposure:.excludePublishedRevisions)
    }
    private func resources(targets:Int = 1,local:Bool = true) -> FeedRunwayDriverResources {
        .init(runway:.init(localWorkAllowed:local,examinedCandidateCapacity:8,readyProbeBound:8,readyProbeCeiling:64,forwardAdvanceProbeBound:64)!,
            acquisition:.init(targetWorkCapacity:targets,batchCapacityPerNewExecution:1,observationCapacityPerBatch:8,byteCapacityPerBatch:100_000)!)
    }
    private func fixture(historyCount:Int = 1,checkpoint:Bool = true,seedLocal:Bool = false,registrations:Bool = true,
        paused:Bool = false,otherPaused:Bool = false,error:URLError? = nil,context:FeedContext? = nil,driverContext:FeedContext? = nil,
        differentRevision:Bool = false,prepareFailure:Bool = false,cancelPrepare:Bool = false,
        wordPolicyEnabled: Bool = false, wordChangeDuringPrepare: Bool = false) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at:root) }
        let db = try RuntimeDatabase(location:.init(directory:root))
        let source: SourceID
        if case .source(let id) = context?.request { source = id } else { source = SourceID() }
        let p = plan(context ?? .init(request:.main)),pol = policy(p),edition = FeedEditionID()
        let candidates = (0..<historyCount).map { Candidate(originRecordID:OriginRecordID(),originRevisionID:OriginRevisionID(),headline:"saved-\($0)",
            summary:nil,timestamp:.init(value:Date(timeIntervalSince1970:1),kind:.observed),language:nil,providerID:nil) }
        let selection = SelectionResult(editorialRevision:p.revision,orderedCandidates:candidates,supplyReport:.init(examinedCount:0,nextCursor:nil,exhausted:true))
        let prepared = Self.prepared(selection)
        _ = try PublicationCoordinator(database:db).createEdition(.init(selection:selection,drafts:PublicationPreparation.drafts(selection:selection,inputs:prepared.inputs),
            editionID:edition,publicationSchemaVersion:.init(rawValue:1),selectionSeed:1,editionCreatedAt:Date(timeIntervalSince1970:1),segmentID:FeedSegmentID(),
            segmentSeed:1,segmentCreatedAt:Date(timeIntervalSince1970:2),cardIDs:prepared.cardIDs))
        if checkpoint { try PublicationHistory(database:db).saveCursor(.init(editionID:edition,anchor:.init(cardID:prepared.cardIDs[0],placement:.top)),updatedAt:Date(timeIntervalSince1970:3)) }
        let target = try AcquisitionTargetAuthority(database:db).register(id:AcquisitionTargetID(),connectorKind:.syndication, authorizedSources: [source])
        if seedLocal {
            let observation = AcquisitionObservation(objectIdentity:.init(connectorKind:.syndication,namespace:"seed",value:"local",role:.object),versionIdentity:nil,
                precedence:.makeCurrent,availability:.available,headline:"local",summary:nil,bodyText:nil,authoredAt:nil,modifiedAt:nil,observedAt:Date(timeIntervalSince1970:4),
                language:nil,primaryLink:nil,searchProjection:nil,providerID:nil,memberships:[.init(sourceID:source,kind:.direct)],mediaCandidates:[])!
            _ = try AdmissionPolicy(database:db).admit(.init(targetID:target.id,targetGeneration:1,expectedCheckpointRevision:0,observations:[observation],nextCheckpoint:nil)!)
        }
        let http = DriverHTTPFixture(paused:paused,error:error, readyBeforePull: {
            try PublicationHistory(database: db).readyAhead(editionID: edition, anchorCardID: prepared.cardIDs[0], probeBound: 64).amount
        })
        addTeardownBlock { http.remove() }
        // The controlled transport never answers a cancelled request; without a short timeout the
        // cancellation test waits the default 60 s for the request to end (measured 60.05 s).
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [DriverURLProtocol.self]
        config.timeoutIntervalForRequest = 1
        let transport = URLSession(configuration:config); addTeardownBlock { transport.invalidateAndCancel() }
        let binding = SourceBinding(id:SourceBindingID(),sourceID:source,externalPrincipal:.init(connectorKind:.syndication,namespace:"p",value:"p",role:.principal),aliases:[],generation:1,state:.enabled)!
        let otherHTTP = DriverHTTPFixture(paused:otherPaused,error:nil, readyBeforePull: {
            try PublicationHistory(database: db).readyAhead(editionID: edition, anchorCardID: prepared.cardIDs[0], probeBound: 64).amount
        })
        addTeardownBlock { otherHTTP.remove() }
        let otherSource = SourceID()
        let otherTarget = try AcquisitionTargetAuthority(database:db).register(id:AcquisitionTargetID(),connectorKind:.syndication, authorizedSources: [otherSource])
        let otherBinding = SourceBinding(id:SourceBindingID(),sourceID:otherSource,externalPrincipal:.init(connectorKind:.syndication,namespace:"p",value:"other",role:.principal),aliases:[],generation:1,state:.enabled)!
        let regs = registrations ? [SyndicationTargetRegistration(targetID:target.id,targetGeneration:1,endpoint:http.url,bindings:[binding])!,
            SyndicationTargetRegistration(targetID:otherTarget.id,targetGeneration:1,endpoint:otherHTTP.url,bindings:[otherBinding])!] : []
        let acquisition = try SyndicationAcquisitionSnapshot(database:db,registrations:regs,session:transport,redirectCapacity:0,now:{ Date(timeIntervalSince1970:5) })
        let session = FeedSession(publicationHistory:.init(database:db)),clock = DriverClock()
        let runway = RunwayController(configuration:.init(policyInputs:.init(safetyFactor:1,releaseMarginSeconds:0)!,consumptionSampleLimit:4,replenishmentSampleLimit:4)!)
        let driverPlan = differentRevision ? plan(p.context) : driverContext.map { plan($0) } ?? p
        let coordinator = acquisition.makeCoordinator()
        let publications = DriverPublicationLog()
        let driver = try FeedRunwayDriver(session:session,runway:runway,plan:driverPlan,policy:policy(driverPlan),acquisition:acquisition,coordinator:coordinator,
            monotonicNow:{ clock.next() },makeSegmentIdentity:{ .init(segmentID:FeedSegmentID(),segmentSeed:2,segmentCreatedAt:Date(timeIntervalSince1970:6))! },prepare:{ selection in
                if cancelPrepare { throw CancellationError() }; if prepareFailure { throw Failure.preparation }
                if wordChangeDuringPrepare {
                    let prefs = ReaderPreferencesStore(database: db)
                    var settings = try XCTUnwrap(prefs.load()).settings
                    settings.contentFilterRules = ["late"]
                    _ = try prefs.setSettings(settings)
                }
                return Self.prepared(selection)
            }, onPublication: { receipt in publications.append(receipt) },
            wordPolicy: wordPolicyEnabled ? ReaderWordExclusionPolicy(database: db, templates: []) : nil)
        // The association's close order, in the fixture: stop new starts and the late-opportunity drain, cancel and
        // await every authorized pull, and only then let the registered transport invalidation run. Registered
        // after that block, this teardown runs before it (LIFO), so no escaped task can call
        // `URLSession.bytes` on an invalidated session in the next test.
        addTeardownBlock {
            await driver.deactivate()
            _ = await coordinator.settleInFlight()
        }
        return .init(database:db,location:.init(directory:root),plan:p,policy:pol,edition:edition,cards:prepared.cardIDs,source:source,target:target,otherTarget:otherTarget,otherSource:otherSource,session:session,runway:runway,driver:driver,acquisition:acquisition,coordinator:coordinator,http:http,otherHTTP:otherHTTP,clock:clock,publications:publications)
    }
    private func restore(_ f:Fixture,forward:Int = 4,resources:FeedRunwayDriverResources? = nil) async throws -> FeedPresentationSnapshot {
        let result = try await f.driver.restoreAndActivate(backwardCapacity:1,forwardCapacity:forward,resources:resources ?? self.resources())
        return try XCTUnwrap(result)
    }
    private func tail(_ f:Fixture,_ p:FeedPresentationSnapshot,resources:FeedRunwayDriverResources? = nil) async throws -> FeedPresentationSnapshot? {
        let result = try await f.driver.submitViewport(.init(anchor:p.window.anchor),activity:.explicitTailApproach,resources:resources ?? self.resources())
        return result
    }
    /// Deterministic settlement wait: the coordinator removes an execution from this set only after its durable
    /// result (admission) settled, so an empty set is a state signal — no wall-clock deadline and no sleep. The
    /// yield loop lets the coordinator's task run; the bound only turns a hang into a visible failure.
    private func settleAcquisitions(_ f: Fixture,
        file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200_000 {
            if await f.coordinator.activeExecutions().isEmpty { return }
            await Task.yield()
        }
        XCTFail("acquisition executions did not settle", file: file, line: line)
    }
    /// R06: a durable result is a fact for the publication loop **before the round ends**. The fast target's supply
    /// reaches a receipt and an installation while the slow target is still suspended; the round keeps running and is
    /// only awaited at the end of the opportunity.
    func testFastSourcePublishesWhileSlowSourceIsPending() async throws {
        let f = try fixture(paused: false, otherPaused: true)
        let plan = resources(targets: 2)
        let initial = try await restore(f, resources: plan)
        let opportunity = Task { try await self.tail(f, initial, resources: plan) }
        let deadline = Date().addingTimeInterval(5)
        while f.publications.values.isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(f.publications.values.isEmpty,
            "a fonte rápida tem de publicar com a lenta ainda suspensa")
        XCTAssertEqual(f.otherHTTP.calls, 1, "a fonte lenta foi consultada e está pendente")
        XCTAssertGreaterThanOrEqual(f.http.calls, 1)
        f.otherHTTP.release()
        _ = try await opportunity.value
    }

    private final class TestFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = false
        var value: Bool { lock.lock(); defer { lock.unlock() }; return storage }
        func set() { lock.lock(); storage = true; lock.unlock() }
    }

    /// The deliberate-move decision the anchor protection depends on: a stationary preparation/correction
    /// reconciliation is not a completed move; only an accepted destination (or a real movement) is.
    func testAPreparationReconciliationIsNotADeliberateMove() {
        XCTAssertFalse(FeedRunwayDriver.isDeliberate(activity: .stationary,
            isReconciliation: true, establishesPosition: false),
            "a preparation request must not end a restore's substitution")
        XCTAssertTrue(FeedRunwayDriver.isDeliberate(activity: .stationary,
            isReconciliation: true, establishesPosition: true),
            "an accepted destination establishes the position")
        XCTAssertTrue(FeedRunwayDriver.isDeliberate(activity: .forward,
            isReconciliation: true, establishesPosition: false),
            "a real movement is deliberate on its own")
        XCTAssertTrue(FeedRunwayDriver.isDeliberate(activity: .backward,
            isReconciliation: false, establishesPosition: false))
    }

    /// P02/A1: the second durable source arrives **after** the first opportunity returned. The reader makes no
    /// gesture and no cadence runs; the late fact still has to publish through the same causal executor.
    func testSecondSourcePublishesAfterFirstDrainReturnedWithoutNewInput() async throws {
        let f = try fixture(paused: false, otherPaused: true)
        let plan = resources(targets: 2)
        let initial = try await restore(f, resources: plan)
        let returned = TestFlag()
        let opportunity = Task { () -> FeedPresentationSnapshot? in
            defer { returned.set() }
            return try await self.tail(f, initial, resources: plan)
        }
        let firstDeadline = Date().addingTimeInterval(5)
        while f.publications.values.isEmpty, Date() < firstDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(f.publications.values.count, 1, "a primeira fonte publica durante o drain")
        while !returned.value, Date() < firstDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(returned.value, "a oportunidade tem de retornar com a segunda fonte ainda pendente")
        XCTAssertEqual(f.otherHTTP.calls, 1, "premissa: a segunda fonte foi consultada e está suspensa")
        f.otherHTTP.release()
        let secondDeadline = Date().addingTimeInterval(5)
        while f.publications.values.count < 2, Date() < secondDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(f.publications.values.count, 2,
            "um resultado durável tardio publica sem gesto nem cadência")
        _ = try await opportunity.value
    }

    /// P02/A1: a media-readiness transition is a durable fact too. A card that the first drain left pending must
    /// publish when its readiness decision arrives, while the reader stays still.
    func testLateMediaReadinessPublishesAfterDrainWithoutCadence() async throws {
        let f = try fixture(registrations: false), readiness = MediaReadiness()
        let driver = try FeedRunwayDriver(session: f.session, runway: f.runway, plan: f.plan, policy: f.policy,
            acquisition: f.acquisition, coordinator: f.coordinator,
            monotonicNow: { .init(seconds: ProcessInfo.processInfo.systemUptime)! },
            makeSegmentIdentity: { .init(segmentID: .init(), segmentSeed: 1, segmentCreatedAt: Date())! },
            prepare: Self.prepared, readiness: readiness,
            onPublication: { receipt in f.publications.append(receipt) })
        let initial = try await driver.restoreAndActivate(backwardCapacity: 1, forwardCapacity: 4,
            resources: resources())
        let start = try XCTUnwrap(initial)
        // A real reader intent: the drain walks the (empty) local walk and returns with nothing ready.
        _ = try await driver.submitViewport(.init(anchor: start.window.anchor),
            activity: .explicitTailApproach, resources: resources())
        XCTAssertTrue(f.publications.values.isEmpty, "premissa: nada estava pronto no primeiro drain")
        let revision = try Self.admitLateLocal(f.database, target: f.target.id, source: f.source)
        XCTAssertNil(readiness.presentation(for: revision), "premissa: a decisão de mídia ainda não chegou")
        readiness.record(revision, nil, textDeclared: true)
        await driver.noteMediaReadinessChanged()
        let deadline = Date().addingTimeInterval(5)
        while f.publications.values.isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(f.publications.values.count, 1,
            "a transição de prontidão publica sem uma nova oportunidade do leitor")
        let current = await f.session.currentPresentation()
        XCTAssertEqual(current?.window.anchor, start.window.anchor)
    }

    /// P0 (fiação): a ingestão durável que chega **depois** de o drive ter declarado a caminhada esgotada tem de
    /// reabri-la pelo mesmo vocabulário da prontidão — sem gesto, sem cadência e sem uma segunda oportunidade do
    /// leitor. É o consumidor que faltava: `noteLateDurableFact` sozinho não reinicia a caminhada, porque só agenda o
    /// dreno; a caminhada continua esgotada e `takeLocalSlice` devolve `nil`.
    func testALateDurableSupplyFactReopensAnExhaustedWalkWithoutCadence() async throws {
        let f = try fixture(registrations: false)
        let initial = try await restore(f)
        // Uma oportunidade real do leitor: o dreno percorre o pool vazio e o declara esgotado.
        _ = try await f.driver.submitViewport(.init(anchor: initial.window.anchor),
            activity: .explicitTailApproach, resources: resources())
        let exhausted = await f.runway.snapshot()
        XCTAssertTrue(exhausted.localSupplyExhausted, "premissa: a caminhada local terminou esgotada")
        XCTAssertTrue(f.publications.values.isEmpty, "premissa: o pool estava vazio no primeiro dreno")

        _ = try Self.admitLateLocal(f.database, target: f.target.id, source: f.source)
        await f.driver.noteLocalSupplyFact()
        let deadline = Date().addingTimeInterval(5)
        while f.publications.values.isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(f.publications.values.count, 1,
            "a ingestão durável reabre a caminhada esgotada sem uma nova oportunidade do leitor")
        // A carta publicada é do candidato que a ingestão trouxe: o dreno reaberto andou com dinheiro novo, não com
        // o estado velho. Depois de publicar, a caminhada volta a se declarar esgotada — só havia uma carta.
        XCTAssertEqual(f.publications.values.first?.cardIDs.count, 1)
    }

    /// O fato é de quem o produziu, e é o escopo do driver que o valida. Um produtor cancelado (a pista já
    /// aposentada) não reabre trabalho local: nada publica e nada fica armado.
    func testADurableSupplyFactAfterRetirementStatesNothing() async throws {
        let f = try fixture(registrations: false)
        let initial = try await restore(f)
        _ = try await f.driver.submitViewport(.init(anchor: initial.window.anchor),
            activity: .explicitTailApproach, resources: resources())
        _ = try Self.admitLateLocal(f.database, target: f.target.id, source: f.source)
        await f.driver.deactivate()
        await f.driver.noteLocalSupplyFact()
        let after = await f.runway.snapshot()
        XCTAssertNil(after.scope, "a pista aposentada não é reativada pelo fato")
        XCTAssertFalse(after.localSliceInFlight)
        XCTAssertFalse(after.pendingSupplyReset)
        XCTAssertTrue(f.publications.values.isEmpty, "um produtor cancelado não abre trabalho local")
    }

    /// O mesmo fato vindo de outra revisão editorial não abre trabalho local. A caminhada é posta em `exhausted`
    /// pela própria API do controlador — o driver não pode dirigir este escopo, porque a sessão carrega outra
    /// revisão —, e o discriminante é `localSupplyExhausted` continuar verdadeiro: sem a cerca,
    /// `noteLocalSupplyChanged` zeraria a caminhada e autorizaria uma fatia num contexto que este driver não serve.
    func testADurableSupplyFactFromAnotherEditorialRevisionStatesNothing() async throws {
        let f = try fixture(differentRevision: true)
        let bounds = FeedPresentationBounds(backwardCapacity: 1, forwardCapacity: 4, contextKey: f.plan.context.key)
        let restored = try await f.session.admitPresentation(.restore(bounds))
        let presentation = try XCTUnwrap(restored)
        let currentScope = await f.session.currentRunwayScope()
        let sessionScope = try XCTUnwrap(currentScope)
        // A premissa, medida na mesma cerca que o fato usa: o drive recusa esta revisão antes de ativar a pista.
        do {
            _ = try await f.driver.activateCurrentPresentation(resources: resources())
            return XCTFail("a revisão stale tem de ser recusada pelo drive")
        } catch {
            guard case .sessionEditorialRevisionMismatch(let expected, let actual) = error as? FeedRunwayDriverError else {
                return XCTFail("erro errado: \(error)")
            }
            XCTAssertNotEqual(expected, actual, "premissa: o driver serve outra revisão editorial")
            XCTAssertEqual(actual, sessionScope.editorialRevisionID,
                "premissa: a sessão carrega a revisão que o driver não serve")
        }
        // A caminhada é esgotada pela API do controlador: a única forma de movê-la aqui, já que o drive recusa.
        await f.runway.activate(sessionScope)
        let anchor = presentation.window.anchor.cardID
        let observation = RunwayObservation(editionID: presentation.editionID, anchorCardID: anchor,
            sampledAt: .init(seconds: 1)!, activity: .explicitTailApproach)
        try await f.runway.submitObservation(observation)
        try await f.runway.acceptMeasurement(.init(observation: observation,
            readyAhead: PublicationHistory(database: f.database).readyAhead(editionID: presentation.editionID,
                anchorCardID: anchor, probeBound: 8), advanceFromHighWater: nil))
        guard case .runLocalSlice(let intent) = try await f.runway.reconsider(resources: resources().runway,
            at: .init(seconds: 2)!) else { return XCTFail("premissa: a pista tem de pedir uma fatia local") }
        try await f.runway.completeLocalSlice(intent,
            outcome: .advancedWithoutPublication(.init(examinedCount: 0, nextCursor: nil, exhausted: true)),
            at: .init(seconds: 3)!)
        let exhausted = await f.runway.snapshot()
        XCTAssertTrue(exhausted.localSupplyExhausted, "premissa: a caminhada está esgotada")

        _ = try Self.admitLateLocal(f.database, target: f.target.id, source: f.source)
        await f.driver.noteLocalSupplyFact()
        let after = await f.runway.snapshot()
        XCTAssertTrue(after.localSupplyExhausted,
            "o fato de outra revisão não reinicia a caminhada que ele não serve")
        XCTAssertFalse(after.pendingSupplyReset)
        XCTAssertFalse(after.localSliceInFlight)
        XCTAssertTrue(f.publications.values.isEmpty)
    }

    /// PD-9/F06: the skip persisted by one opportunity must be the revision the production driver asks media to
    /// prepare on a later opportunity, and readiness must then publish it without a new viewport. This is the seam
    /// between the durable store and `nextEditorialRevisions`; the slice tests seeded readiness by hand and could
    /// not see it.
    func testRelaunchPreparationRequestsThePersistedSkipAndPublishesWhenReady() async throws {
        let f = try fixture(seedLocal: true, registrations: false), readiness = MediaReadiness()
        let requested = DriverMediaJournal()
        let reoffer = PendingMediaReconsideration(database: f.database)
        let driver = try FeedRunwayDriver(session: f.session, runway: f.runway, plan: f.plan, policy: f.policy,
            acquisition: f.acquisition, coordinator: f.coordinator,
            monotonicNow: { .init(seconds: ProcessInfo.processInfo.systemUptime)! },
            makeSegmentIdentity: { .init(segmentID: .init(), segmentSeed: 1, segmentCreatedAt: Date())! },
            prepare: Self.prepared, readiness: readiness, reoffer: reoffer,
            makeMediaOpportunity: {
                MediaPreparationOpportunity(waitSeconds: 4, startedAt: 100) { revisions, _ in
                    requested.append(revisions.map { $0.rawValue.uuidString }.joined(separator: ","))
                }
            }, onPublication: { receipt in f.publications.append(receipt) })
        let restored = try await driver.restoreAndActivate(backwardCapacity: 1,
            forwardCapacity: 4, resources: resources())
        let initial = try XCTUnwrap(restored)
        _ = try await driver.submitViewport(.init(anchor: initial.window.anchor), activity: .explicitTailApproach,
            resources: resources())

        let revision = try XCTUnwrap(ContentStore(database: f.database)
            .candidateWindow(sourceID: nil, after: nil, examinedCapacity: 8).records.first?.originRevisionID)
        let durable = try PendingMediaReconsideration(database: f.database)
            .pendingEntries(for: f.edition, limit: 32)
        XCTAssertEqual(durable.map(\.originRevisionID), [revision],
            "the process-equivalent reread finds the skip on disk before any media work")

        // Push the deferred story out of the structural window (capacity 8): nine newer stories sort ahead of it.
        // Without this, the journal could contain the revision merely because the walk re-examined it, and the test
        // would not prove the reoffer wiring.
        for n in 0..<9 {
            _ = try Self.admitLateLocal(f.database, target: f.target.id, source: f.source,
                observedAt: 10 + Double(n))
        }
        let structural = try ContentStore(database: f.database)
            .candidateWindow(sourceID: nil, after: nil, examinedCapacity: 8).records
        XCTAssertFalse(structural.map(\.originRevisionID).contains(revision),
            "the deferred story is outside the structural window this opportunity examines")

        // A later opportunity must prepare that persisted revision through the production driver. The journal is
        // the only readiness source here; readiness is not written by hand until after this assertion.
        requested.reset()
        var requestedRevision = false
        for _ in 0..<4 where !requestedRevision {
            // A later media/supply fact reopens the local walk; this is the opportunity the production driver
            // would receive after a relaunch or a media transition.
            await driver.noteMediaReadinessChanged()
            _ = try await driver.drive(resources: resources())
            let deadline = Date().addingTimeInterval(2)
            while !requestedRevision, Date() < deadline {
                requestedRevision = requested.values.joined().contains(revision.rawValue.uuidString)
                if !requestedRevision { try await Task.sleep(for: .milliseconds(10)) }
            }
        }
        XCTAssertTrue(requestedRevision, "the driver requests the persisted deferred revision for preparation")

        readiness.record(revision, nil, textDeclared: true)
        await driver.noteMediaReadinessChanged()
        let deadline = Date().addingTimeInterval(5)
        while f.publications.values.isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let store = PublicationStore(database: f.database)
        let published = f.publications.values.flatMap(\.cardIDs).compactMap {
            try? store.card(id: $0)?.originRevisionID
        }
        XCTAssertTrue(published.contains(revision),
            "the prepared skip becomes eligible and publishes without a new viewport")
    }

    /// MR-8: with more pending stories than one page (48 persisted, capacity 8), every deferred revision must reach
    /// the production driver's bounded preparation across real opportunities. The deferred stories are the 40 oldest;
    /// eight newer stories occupy the structural window, so the request cannot come from re-examining the walk.
    /// No readiness is seeded: the journal records the preparation requests themselves. A second Edition's
    /// association must survive untouched.
    func testEveryPersistedSkipReachesPreparationWithSmallCapacity() async throws {
        let f = try fixture(seedLocal: false, registrations: false), readiness = MediaReadiness()
        let requested = DriverMediaJournal(), reoffer = PendingMediaReconsideration(database: f.database)
        let driver = try FeedRunwayDriver(session: f.session, runway: f.runway, plan: f.plan, policy: f.policy,
            acquisition: f.acquisition, coordinator: f.coordinator,
            monotonicNow: { .init(seconds: ProcessInfo.processInfo.systemUptime)! },
            makeSegmentIdentity: { .init(segmentID: .init(), segmentSeed: 1, segmentCreatedAt: Date())! },
            prepare: Self.prepared, readiness: readiness, reoffer: reoffer,
            makeMediaOpportunity: {
                MediaPreparationOpportunity(waitSeconds: 4, startedAt: 100) { revisions, _ in
                    requested.append(revisions.map { $0.rawValue.uuidString }.joined(separator: ","))
                }
            }, onPublication: { receipt in f.publications.append(receipt) })

        var deferred: [MediaDeferralRecord] = []
        for n in 0..<40 {
            let (record, _) = try Self.admitLocalDeferral(f.database, target: f.target.id, source: f.source,
                edition: f.edition, observedAt: Double(n))
            deferred.append(record)
        }
        // Newer structural stories, deliberately not deferred: capacity 8 examines these, never the older 40.
        for n in 40..<48 {
            _ = try Self.admitLateLocal(f.database, target: f.target.id, source: f.source, observedAt: Double(n))
        }
        try MediaDeferralStore(database: f.database).record(deferred, at: Date(timeIntervalSince1970: 100))
        let otherEdition = FeedEditionID()
        let foreign = MediaDeferralRecord(editionID: otherEdition,
            originRecordID: deferred[0].originRecordID, originRevisionID: deferred[0].originRevisionID)
        try MediaDeferralStore(database: f.database).record([foreign], at: Date(timeIntervalSince1970: 101))

        let restored = try await driver.restoreAndActivate(backwardCapacity: 0, forwardCapacity: 1,
            resources: resources())
        let initial = try XCTUnwrap(restored)
        _ = try await driver.submitViewport(.init(anchor: initial.window.anchor), activity: .explicitTailApproach,
            resources: resources())
        requested.reset()

        // Each opportunity is the production drive after a supply/media fact. Eight opportunities with capacity 8
        // must expose the whole persisted page; the mutation `reoffer.ceiling` -> `capacity` cannot.
        for _ in 0..<8 {
            await driver.noteMediaReadinessChanged()
            _ = try await driver.drive(resources: resources())
            try await Task.sleep(for: .milliseconds(30))
        }
        let deferredIDs = Set(deferred.map { $0.originRevisionID.rawValue.uuidString })
        let batches = requested.values.map { Set($0.split(separator: ",").map(String.init)) }
        // Request tasks are detached, so batch order is not guaranteed; the largest single batch is the bounded
        // page one opportunity actually handed to preparation. Ceiling is 32; structural capacity is 8.
        let largestBatch = batches.map { $0.intersection(deferredIDs).count }.max() ?? 0
        // One request is structural candidates (at most `capacity`) plus the pending page. Under the mutation
        // `reoffer.ceiling` -> `capacity`, no single request can name more than 2 * capacity deferred revisions;
        // the ceiling page must exceed that, which is what proves the page and not the structural walk supplied it.
        XCTAssertGreaterThan(largestBatch, 2 * resources().runway.examinedCandidateCapacity,
            "one bounded preparation page must carry the deferral page, not only the structural capacity")
        let requestedIDs = batches.reduce(into: Set<String>()) { $0.formUnion($1) }
        for record in deferred {
            XCTAssertTrue(requestedIDs.contains(record.originRevisionID.rawValue.uuidString),
                "deferred revision \(record.originRevisionID) never reached bounded preparation")
        }
        let store = MediaDeferralStore(database: f.database)
        XCTAssertEqual(try store.page(editionID: otherEdition, limit: 32, offerAt: nil), [foreign],
            "preparing Edition A must not consume another Edition's association")
        XCTAssertEqual(try PendingMediaReconsideration(database: f.database)
            .pendingEntries(for: otherEdition, limit: 32).map(\.originRevisionID), [foreign.originRevisionID])
    }

    /// P02: two late facts that arrive together are one publisher pass: no duplicate card, no second loop.
    func testConcurrentLateFactsUseOneCausalPublisher() async throws {
        let f = try fixture(registrations: false), readiness = MediaReadiness()
        let driver = try FeedRunwayDriver(session: f.session, runway: f.runway, plan: f.plan, policy: f.policy,
            acquisition: f.acquisition, coordinator: f.coordinator,
            monotonicNow: { .init(seconds: ProcessInfo.processInfo.systemUptime)! },
            makeSegmentIdentity: { .init(segmentID: .init(), segmentSeed: 1, segmentCreatedAt: Date())! },
            prepare: Self.prepared, readiness: readiness,
            onPublication: { receipt in f.publications.append(receipt) })
        let restoredValue = try await driver.restoreAndActivate(backwardCapacity: 1,
            forwardCapacity: 4, resources: resources())
        let restored = try XCTUnwrap(restoredValue)
        _ = try await driver.submitViewport(.init(anchor: restored.window.anchor),
            activity: .explicitTailApproach, resources: resources())
        let revision = try Self.admitLateLocal(f.database, target: f.target.id, source: f.source)
        readiness.record(revision, nil, textDeclared: true)
        async let a: Void = driver.noteMediaReadinessChanged()
        async let b: Void = driver.noteMediaReadinessChanged()
        _ = await (a, b)
        let deadline = Date().addingTimeInterval(5)
        while f.publications.values.isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(f.publications.values.count, 1, "fatos simultâneos não duplicam a publicação")
    }

    /// P02 setup: a local occurrence admitted after the first drain, with no media candidate of its own.
    nonisolated private static func admitLateLocal(_ database: RuntimeDatabase, target: AcquisitionTargetID,
        source: SourceID, observedAt: TimeInterval = 4, expectedCheckpointRevision: UInt64 = 0) throws -> OriginRevisionID {
        let observation = AcquisitionObservation(
            objectIdentity: .init(connectorKind: .syndication, namespace: "late", value: UUID().uuidString, role: .object),
            versionIdentity: nil, precedence: .makeCurrent, availability: .available, headline: "late", summary: nil,
            bodyText: nil, authoredAt: nil, modifiedAt: nil, observedAt: Date(timeIntervalSince1970: observedAt),
            language: nil, primaryLink: nil, searchProjection: nil, providerID: nil,
            memberships: [.init(sourceID: source, kind: .direct)], mediaCandidates: [])!
        _ = try AdmissionPolicy(database: database).admit(.init(targetID: target, targetGeneration: 1,
            expectedCheckpointRevision: expectedCheckpointRevision, observations: [observation], nextCheckpoint: nil)!)
        let records = try ContentStore(database: database).candidateWindow(sourceID: nil, after: nil,
            examinedCapacity: 8).records
        return try XCTUnwrap(records.first { $0.headline == "late" } ?? records.first).originRevisionID
    }

    /// Admits one local story and returns the deferral record a relaunch would have persisted for it.
    nonisolated private static func admitLocalDeferral(_ database: RuntimeDatabase, target: AcquisitionTargetID,
        source: SourceID, edition: FeedEditionID, observedAt: TimeInterval) throws -> (MediaDeferralRecord, OriginRevisionID) {
        let revision = try admitLateLocal(database, target: target, source: source, observedAt: observedAt)
        let records = try ContentStore(database: database).candidateWindow(sourceID: nil, after: nil,
            examinedCapacity: 64).records
        let origin = try XCTUnwrap(records.first { $0.originRevisionID == revision }?.originRecordID)
        return (.init(editionID: edition, originRecordID: origin, originRevisionID: revision), revision)
    }

    /// R06: a round that is still running when the scope is retired must not publish into the old scope. The
    /// retirement cancels the round; the late durable results still notify nobody, and no new receipt appears.
    func testDurableResultAfterEditionSwitchDoesNotPublishIntoOldScope() async throws {
        let f = try fixture(paused: false, otherPaused: true)
        let plan = resources(targets: 2)
        let initial = try await restore(f, resources: plan)
        let opportunity = Task { try await self.tail(f, initial, resources: plan) }
        let deadline = Date().addingTimeInterval(5)
        while f.publications.values.isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(f.publications.values.isEmpty)
        let before = f.publications.values.count
        // The edition/context is retired while the slow target is still pending.
        await f.driver.deactivate()
        f.otherHTTP.release()
        _ = try? await opportunity.value
        XCTAssertEqual(f.publications.values.count, before,
            "um resultado durável tardio não pode publicar no escopo aposentado")
    }

    private func assertLegitimateSecondTarget(_ f: Fixture, seededLocal: Bool,
        file: StaticString = #filePath, line: UInt = #line) async throws {
        let initialReady = seededLocal ? 1 : 0
        XCTAssertEqual(f.http.calls, 2, file:file, line:line)
        XCTAssertEqual(f.otherHTTP.calls, 1, file:file, line:line)
        XCTAssertEqual(f.http.readyBefore, [.exact(initialReady), .exact(initialReady + 2)], file:file, line:line)
        XCTAssertEqual(f.otherHTTP.readyBefore, [.exact(initialReady + 1)], file:file, line:line)
        let eligible = try f.acquisition.eligibleTargets(for: f.plan.context)
        XCTAssertEqual(eligible.count, 2, file:file, line:line)
        XCTAssertEqual(Set(eligible.map(\.id)).count, 2, file:file, line:line)
        let canonical = try ContentStore(database:f.database).candidateWindow(sourceID:nil, after:nil, examinedCapacity:8).records
        XCTAssertEqual(canonical.count, initialReady + 2, file:file, line:line)
        let own = try ContentStore(database:f.database).candidateWindow(sourceID:f.source, after:nil, examinedCapacity:8).records
        XCTAssertEqual(own.count, initialReady + 1, file:file, line:line)
        let store = PublicationStore(database:f.database), segments = try store.segments(editionID:f.edition)
        let appended = try segments.dropFirst().flatMap { segment in
            try segment.cardIDs.map { try XCTUnwrap(store.card(id:$0), file:file, line:line) }
        }
        XCTAssertEqual(appended.count, canonical.count, file:file, line:line)
        XCTAssertEqual(Set(appended.map(\.originRevisionID)), Set(canonical.map(\.originRevisionID)), file:file, line:line)
        XCTAssertEqual(Set(appended.map(\.originRevisionID)).count, appended.count, file:file, line:line)
        XCTAssertEqual(segments[0].cardIDs, f.cards, file:file, line:line)
        let before = await f.session.currentPresentation()
        _ = try await f.driver.drive(resources:resources())
        let after = await f.session.currentPresentation()
        XCTAssertEqual(after, before, file:file, line:line)
        XCTAssertEqual(f.http.calls, 2, file:file, line:line); XCTAssertEqual(f.otherHTTP.calls, 1, file:file, line:line)
    }
    func testCausalDrainSharesOneMediaDeadlineAcrossLocalSlices() async throws {
        let f = try fixture(seedLocal: true), journal = DriverMediaJournal(), clock = DriverClock()
        let driver = try FeedRunwayDriver(session: f.session, runway: f.runway, plan: f.plan, policy: f.policy,
            acquisition: f.acquisition, coordinator: f.coordinator,
            monotonicNow: { .init(seconds: ProcessInfo.processInfo.systemUptime)! },
            makeSegmentIdentity: { .init(segmentID: .init(), segmentSeed: 1, segmentCreatedAt: Date())! },
            prepare: Self.prepared, makeMediaOpportunity: {
                journal.append("begin")
                return MediaPreparationOpportunity(waitSeconds: 4, startedAt: clock.next().seconds) { _, deadline in
                    _ = clock.next() // Time advances between windows, but their deadline cannot renew.
                    journal.append(String(deadline))
                }
            })
        let initial = try await driver.restoreAndActivate(backwardCapacity: 1, forwardCapacity: 4, resources: resources())
        journal.reset()
        _ = try await driver.submitViewport(.init(anchor: XCTUnwrap(initial).window.anchor),
            activity: .explicitTailApproach, resources: resources())
        XCTAssertEqual(journal.values.filter { $0 == "begin" }.count, 1)
        let deadlines = journal.values.filter { $0 != "begin" }
        XCTAssertGreaterThanOrEqual(deadlines.count, 2, "The opportunity must actually prepare several slices")
        XCTAssertEqual(Set(deadlines).count, 1, "A later slice cannot earn a new media wait")
        _ = try await driver.drive(resources: resources())
        let deadline = Date().addingTimeInterval(2)
        while journal.values.filter({ $0 == "begin" }).count < 2, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(journal.values.filter { $0 == "begin" }.count, 2, "A new caller owns a new budget")
    }

    /// R07: media preparation is a priority request, not a condition of the slice. With the preparation suspended on
    /// an unrelated candidate, the ready supply still publishes — the slice selects what the readiness index says is
    /// ready, and the delay of one decode cannot hold the cards around it.
    func testReadyCandidatePublishesBeforeUnrelatedMediaCompletes() async throws {
        final class MediaGate: @unchecked Sendable {
            private let lock = NSLock()
            private var waiting: [CheckedContinuation<Void, Never>] = []
            private var released = false
            var isReleased: Bool { lock.lock(); defer { lock.unlock() }; return released }
            func wait() async {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    lock.lock()
                    if released { lock.unlock(); continuation.resume() }
                    else { waiting.append(continuation); lock.unlock() }
                }
            }
            func release() {
                lock.lock(); released = true; let parked = waiting; waiting = []; lock.unlock()
                parked.forEach { $0.resume() }
            }
        }
        let f = try fixture(), gate = MediaGate()
        let driver = try FeedRunwayDriver(session: f.session, runway: f.runway, plan: f.plan, policy: f.policy,
            acquisition: f.acquisition, coordinator: f.coordinator,
            monotonicNow: { .init(seconds: ProcessInfo.processInfo.systemUptime)! },
            makeSegmentIdentity: { .init(segmentID: .init(), segmentSeed: 1, segmentCreatedAt: Date())! },
            prepare: Self.prepared, makeMediaOpportunity: {
                MediaPreparationOpportunity(waitSeconds: 10, startedAt: ProcessInfo.processInfo.systemUptime) { _, _ in
                    await gate.wait()
                }
            }, onPublication: { receipt in f.publications.append(receipt) })
        let initial = try await driver.restoreAndActivate(backwardCapacity: 1, forwardCapacity: 4,
            resources: resources())
        let opportunity = Task {
            try await driver.submitViewport(.init(anchor: XCTUnwrap(initial).window.anchor),
                activity: .explicitTailApproach, resources: resources())
        }
        let deadline = Date().addingTimeInterval(2)
        while f.publications.values.isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(f.publications.values.isEmpty,
            "o slice publica com a preparação de mídia ainda suspensa")
        XCTAssertFalse(gate.isReleased, "premissa: a preparação não concluiu")
        gate.release()
        _ = try await opportunity.value
    }

    func test01SemanticTailFullProductionLoop() async throws {
        let f = try fixture(),store = PublicationStore(database:f.database),before = try store.edition(id:f.edition)
        let p = try await restore(f); let installed = await f.session.currentPresentation()
        XCTAssertEqual(installed,p); XCTAssertEqual(f.http.calls,0)
        let result = try await tail(f,p)
        XCTAssertGreaterThan(f.http.calls,0); XCTAssertEqual(try store.edition(id:f.edition),before)
        XCTAssertEqual(try store.segments(editionID:f.edition).count,3)
        let candidates = try ContentStore(database:f.database).candidateWindow(sourceID:f.source,after:nil,examinedCapacity:8).records
        XCTAssertEqual(candidates.count,1); XCTAssertEqual(result?.editionID,f.edition)
        XCTAssertEqual(result?.window.anchor,p.window.anchor)
        // The gesture admitted only what was ready when it happened.
        XCTAssertEqual(result?.window.items.count,1)
        try await assertLegitimateSecondTarget(f, seededLocal: false)
        // The production this gesture started is revealed by the next genuine scroll.
        let extended = try await tail(f, try XCTUnwrap(result))
        XCTAssertEqual(extended?.window.items.count,3)
        let current = await f.session.currentPresentation(); XCTAssertEqual(current,extended)
    }
    func test02LocalPresentationSurvivesSuspendedTailHTTP() async throws {
        let f = try fixture(paused:true),p = try await restore(f); XCTAssertEqual(f.http.calls,0)
        let driver = f.driver,resources = resources(),anchor = p.window.anchor
        let task = Task { try await driver.submitViewport(.init(anchor:anchor),activity:.explicitTailApproach,resources:resources) }
        var started = f.http.started.makeAsyncIterator(); _ = await started.next()
        let pending = await f.session.currentPresentation(); XCTAssertEqual(pending,p)
        f.http.release(); let result = try await task.value
        // Production finished during the suspended gesture; the admitted list still awaits a scroll.
        XCTAssertEqual(result?.window.items.count,1)
        try await assertLegitimateSecondTarget(f, seededLocal: false)
    }
    /// NF-05/NF-01: the measured interval runs from the owner's demand to the **first publication receipt** of the
    /// network card, not to the earlier durable selectable offer. The network item's preparation is held after its
    /// durable result; the driver clock advances while the reader still waits. The receipt must name the network
    /// item, and the policy must become pressured at 32 ready cards. f9cd0ee (offer-only) fails this test.
    func testNetworkReplenishmentLatencyEndsAtThePublishedReceipt() async throws {
        let f = try fixture(seedLocal: true, paused: true)
        let gate = PrepareGate()
        let driver = try FeedRunwayDriver(session: f.session, runway: f.runway, plan: f.plan, policy: f.policy,
            acquisition: f.acquisition, coordinator: f.coordinator,
            monotonicNow: { f.clock.next() },
            makeSegmentIdentity: { .init(segmentID: FeedSegmentID(), segmentSeed: 2,
                segmentCreatedAt: Date(timeIntervalSince1970: 6))! },
            prepare: { selection in
                if selection.orderedCandidates.contains(where: { $0.headline == "Remote" }) { gate.wait() }
                return Self.prepared(selection)
            }, onPublication: { receipt in f.publications.append(receipt) })
        let restored = try await driver.restoreAndActivate(backwardCapacity: 1, forwardCapacity: 4,
            resources: resources())
        let initial = try XCTUnwrap(restored)
        let task = Task { try await driver.submitViewport(.init(anchor: initial.window.anchor),
            activity: .explicitTailApproach, resources: self.resources()) }
        var request = f.http.started.makeAsyncIterator()
        guard await request.next() != nil else { return XCTFail("the network request never started") }
        // The HTTP is held to ~100; the durable offer then waits at preparation. Both delays must be inside the
        // measured demand->publication interval.
        f.clock.jump(to: 100)
        f.http.release()
        let entered = expectation(description: "the network item reaches preparation")
        gate.onEntered { entered.fulfill() }
        await fulfillment(of: [entered], timeout: 5)
        f.clock.jump(to: 300)
        gate.release()
        _ = try await task.value
        let receipt = try XCTUnwrap(f.publications.values.last, "the network publication must produce a receipt")
        let store = PublicationStore(database: f.database)
        let cards = try receipt.cardIDs.compactMap { try store.card(id: $0) }
        XCTAssertTrue(cards.contains { $0.title == "Remote" },
            "the receipt must name the network item's content, not only the durable selectable offer")
        XCTAssertEqual(receipt.editionID, f.edition,
            "the publication that closes the measurement must belong to the demanded edition")
        let snapshot = await f.runway.snapshot()
        let p95 = try XCTUnwrap(snapshot.replenishment.p95Seconds)
        XCTAssertGreaterThanOrEqual(p95, 250,
            "the sample must span the held HTTP (~100) and the held preparation (~200), not only one part")
        let evaluation = RunwayPolicy.evaluate(
            facts: RunwayFacts(consumption: ConsumptionFacts(cardsPerSecond: 1, forwardIntent: true,
                explicitTailApproach: false)!,
                replenishment: ReplenishmentFacts(p95Seconds: p95)!,
                readyAmount: .exact(32), previouslyPressured: false, localSliceInFlight: false,
                unknownBootstrapAvailable: false),
            inputs: RunwayPolicyInputs(safetyFactor: 1, releaseMarginSeconds: 0)!,
            resources: RunwayResourceFacts(localWorkAllowed: true, examinedCandidateCapacity: 8,
                readyProbeBound: 8, readyProbeCeiling: 64, forwardAdvanceProbeBound: 64)!)
        guard case .pressured = evaluation.coverage else {
            return XCTFail("a late publication must make 32 ready cards insufficient: \(evaluation)")
        }
    }

    /// The network request is suspended in scope A; the reader moves to scope B before the durable offer arrives.
    /// The late offer/publication must not enter B's controller.
    func testRetiredAcquisitionLatencyDoesNotEnterANewScope() async throws {
        let f = try fixture(seedLocal: true, paused: true)
        let driver = f.driver
        let restored = try await driver.restoreAndActivate(backwardCapacity: 1, forwardCapacity: 4,
            resources: resources())
        let initial = try XCTUnwrap(restored)
        let task = Task { try await driver.submitViewport(.init(anchor: initial.window.anchor),
            activity: .explicitTailApproach, resources: self.resources()) }
        var started = f.http.started.makeAsyncIterator()
        guard await started.next() != nil else { return XCTFail("the network request never started") }
        let newScope = RunwayScope(editionID: FeedEditionID(), contextKey: .init(request: .main),
            editorialRevisionID: EditorialRevisionID())
        await f.runway.activate(newScope)
        f.clock.jump(to: 100)
        f.http.release()
        _ = try? await task.value
        let snapshot = await f.runway.snapshot()
        XCTAssertEqual(snapshot.scope, newScope)
        XCTAssertNil(snapshot.replenishment.p95Seconds,
            "a result started in the retired scope cannot become the new scope's replenishment latency")
    }

    /// No successful publication means no sample; an empty acquisition must not invent a latency.
    func testEmptyAcquisitionDoesNotRecordReplenishmentLatency() async throws {
        let f = try fixture(registrations: false)
        let initial = try await restore(f)
        _ = try await tail(f, initial)
        let snapshot = await f.runway.snapshot()
        XCTAssertNil(snapshot.replenishment.p95Seconds)
    }

    /// A cancelled preparation publishes nothing; no success sample may be invented.
    func testCancelledPreparationDoesNotRecordReplenishmentLatency() async throws {
        let f = try fixture(seedLocal: true, paused: false, cancelPrepare: true)
        let initial = try await restore(f)
        _ = try? await tail(f, initial)
        let snapshot = await f.runway.snapshot()
        XCTAssertNil(snapshot.replenishment.p95Seconds)
    }

    /// A cancelled network chain must not be closed by an unrelated later local publication.
    func testCancelledNetworkChainIsNotClosedByALaterPublication() async throws {
        let f = try fixture(seedLocal: true, paused: false)
        let readiness = MediaReadiness()
        let driver = try FeedRunwayDriver(session: f.session, runway: f.runway, plan: f.plan, policy: f.policy,
            acquisition: f.acquisition, coordinator: f.coordinator,
            monotonicNow: { f.clock.next() },
            makeSegmentIdentity: { .init(segmentID: FeedSegmentID(), segmentSeed: 2,
                segmentCreatedAt: Date(timeIntervalSince1970: 6))! },
            prepare: { selection in
                if selection.orderedCandidates.contains(where: { $0.headline == "Remote" }) { throw CancellationError() }
                return Self.prepared(selection)
            }, readiness: readiness,
            onPublication: { receipt in f.publications.append(receipt) })
        let restored = try await driver.restoreAndActivate(backwardCapacity: 1, forwardCapacity: 4,
            resources: resources())
        let initial = try XCTUnwrap(restored)
        _ = try? await driver.submitViewport(.init(anchor: initial.window.anchor),
            activity: .explicitTailApproach, resources: self.resources())
        let afterCancelled = f.publications.values.count
        // Move the clock far past the cancelled demand; a later legitimate local publication must not close it.
        f.clock.jump(to: 300)
        let checkpoint = try XCTUnwrap(AcquisitionTargetAuthority(database: f.database).target(id: f.target.id))
            .checkpointRevision
        let revision = try Self.admitLateLocal(f.database, target: f.target.id, source: f.source,
            expectedCheckpointRevision: checkpoint)
        readiness.record(revision, nil, textDeclared: true)
        await driver.noteMediaReadinessChanged()
        let deadline = Date().addingTimeInterval(5)
        while f.publications.values.count <= afterCancelled, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertGreaterThan(f.publications.values.count, afterCancelled, "the later local publication is real")
        let snapshot = await f.runway.snapshot()
        XCTAssertLessThan(snapshot.replenishment.p95Seconds ?? 0, 100,
            "a later publication must not close the cancelled network chain with its old start")
    }

    /// A later round in the same scope must not replace the earlier unsatisfied demand's start; another scope
    /// replaces it because the retired scope's measurement is gone.
    func testANewRoundKeepsTheEarliestSameScopeDemandStart() {
        let scope = RunwayScope(editionID: FeedEditionID(), contextKey: .init(request: .main),
            editorialRevisionID: EditorialRevisionID())
        let other = RunwayScope(editionID: FeedEditionID(), contextKey: .init(request: .main),
            editorialRevisionID: EditorialRevisionID())
        let first = RunwayMonotonicTime(seconds: 10)!, later = RunwayMonotonicTime(seconds: 20)!
        let start = FeedRunwayDriver.nextReplenishmentMeasurement(nil, scope: scope, startedAt: first)
        let sameScope = FeedRunwayDriver.nextReplenishmentMeasurement(start, scope: scope, startedAt: later)
        XCTAssertEqual(sameScope.startedAt, first, "a new round cannot rewind the pending demand's start")
        let changed = FeedRunwayDriver.nextReplenishmentMeasurement(start, scope: other, startedAt: later)
        XCTAssertEqual(changed.scope, other)
        XCTAssertEqual(changed.startedAt, later, "a retired scope does not carry its start into the new scope")
    }

    func test03NoCheckpointNoColdEdition() async throws {
        let f = try fixture(checkpoint:false),before = try PublicationStore(database:f.database).segments(editionID:f.edition)
        let result = try await f.driver.restoreAndActivate(backwardCapacity:0,forwardCapacity:1,resources:resources())
        XCTAssertNil(result); XCTAssertEqual(f.http.calls,0); XCTAssertEqual(try PublicationStore(database:f.database).segments(editionID:f.edition),before)
        let snap = await f.runway.snapshot(); XCTAssertNil(snap.scope)
    }
    func test04LocalSupplyPrecedesNetwork() async throws {
        let f = try fixture(seedLocal:true,paused:true),p = try await restore(f)
        let driver = f.driver,resources = resources(),anchor = p.window.anchor
        let task = Task { try await driver.submitViewport(.init(anchor:anchor),activity:.explicitTailApproach,resources:resources) }
        var started = f.http.started.makeAsyncIterator(); _ = await started.next()
        // Local content is already committed; the admitted list still shows only what the reader
        // was admitted. Production waits for the boundary (T2), so the reserve grows, not the screen.
        let local = await f.session.currentPresentation()
        XCTAssertEqual(local?.window.items.count,1)
        XCTAssertEqual(try PublicationStore(database:f.database).segments(editionID:f.edition).count,2)
        f.http.release(); let result = try await task.value
        // The gesture admitted the single card that was ready; the three it produced wait for the next one.
        XCTAssertEqual(result?.window.items.count,1)
        try await assertLegitimateSecondTarget(f, seededLocal: true)
        let extended = try await tail(f, try XCTUnwrap(result))
        XCTAssertEqual(extended?.window.items.count,4)
    }
    func test05HistoryMeasurementIgnoresTinyWindowTail() async throws {
        // Bounds are frozen per presentation (T2), so a "thin window" is simply a session admitted
        // with no forward capacity: the measurement must still read committed history, not the window.
        let f = try fixture(historyCount:50,seedLocal:true,registrations:false),p = try await restore(f,forward:0)
        _ = try await tail(f,p) // real local publication establishes replenishment latency; no external target is eligible
        // A real committed forward advance establishes nonzero measured consumption.
        _ = try await f.driver.submitViewport(.init(anchor:.init(cardID:f.cards[1],placement:.top)),activity:.forward,resources:resources())
        let thin = await f.session.currentPresentation()
        let current = try XCTUnwrap(thin)
        XCTAssertEqual(current, p); XCTAssertEqual(current.window.items.last?.id,current.window.anchor.cardID)
        _ = try await tail(f,current)
        let snap = await f.runway.snapshot()
        // The subject is the measurement source: committed history, not the materialized window.
        let ready = try XCTUnwrap(snap.readyAhead)
        let ahead: Int
        switch ready.amount {
        case .exact(let count): ahead = count
        case .atLeast(let bound): ahead = bound
        }
        XCTAssertGreaterThanOrEqual(ahead, 8)
        XCTAssertEqual(ready.anchorCardID, current.window.anchor.cardID)
        XCTAssertEqual(f.http.calls,0)
    }
    func test06LocalPublicationExtendsReserveWithoutChangingTheAdmittedList() async throws {
        let f = try fixture(seedLocal:true,registrations:false),p = try await restore(f)
        _ = try await tail(f,p); let current = await f.session.currentPresentation()
        XCTAssertEqual(current, p)
        XCTAssertEqual(current?.window.items.count,1)
        XCTAssertEqual(current?.window.anchor,p.window.anchor)
        XCTAssertGreaterThan(try PublicationStore(database:f.database).segments(editionID:f.edition).count, 1)
    }
    func test07AdvanceWithoutPublicationPreservesPresentation() async throws {
        let f = try fixture(registrations:false),p = try await restore(f)
        _ = try await tail(f,p); let current = await f.session.currentPresentation(); XCTAssertEqual(current,p)
        let snap = await f.runway.snapshot(); XCTAssertTrue(snap.localSupplyExhausted); XCTAssertFalse(snap.localSliceInFlight)
    }
    func test08DeferredExactIntentExplicitlyResumes() async throws {
        let f = try fixture(),p = try await restore(f)
        _ = try await tail(f,p,resources:resources(targets:0))
        let denied = await f.runway.snapshot(); XCTAssertNotNil(denied.outstandingAcquisition); XCTAssertEqual(f.http.calls,0)
        let result = try await f.driver.drive(resources:resources())
        XCTAssertGreaterThan(f.http.calls,0)
        // The resumed opportunity published; it did not install anything into the reader's list.
        XCTAssertEqual(result, p)
        let admitted = await f.session.currentPresentation(); XCTAssertEqual(admitted, p)
        XCTAssertGreaterThan(try PublicationStore(database:f.database).segments(editionID:f.edition).count,1)
        try await assertLegitimateSecondTarget(f, seededLocal: false)
    }
    func test09NoEligibleQuiesces() async throws {
        let f = try fixture(registrations:false),p = try await restore(f); _ = try await tail(f,p)
        let snap = await f.runway.snapshot(); XCTAssertNil(snap.outstandingAcquisition); XCTAssertEqual(f.http.calls,0)
    }
    func test10OperationalFailureSettlesOnceAndPreservesPresentation() async throws {
        let direct = try fixture(error: URLError(.notConnectedToInternet))
        let result = try await direct.coordinator.execute(.start(target: direct.target,
            bounds: .init(batchCapacity: 1, observationCapacityPerBatch: 8, byteCapacityPerBatch: 100_000)!))
        XCTAssertEqual(result.stop, .operationalFailure(.transport))
        XCTAssertEqual(result.targetID, direct.target.id); XCTAssertEqual(result.generation, 1)
        XCTAssertTrue(result.receipts.isEmpty); XCTAssertFalse(result.selectableSupplyChanged)
        XCTAssertEqual(direct.http.calls, 1)
        // Independent real-driver opportunity: settlement remains finite and adds no visual failure.
        let f = try fixture(error: URLError(.notConnectedToInternet)), p = try await restore(f)
        let checkpoint = try SessionStore(database: f.database).checkpoint()
        let after = try await tail(f, p)
        XCTAssertEqual(after, p); XCTAssertEqual(f.http.calls, 1); XCTAssertEqual(f.otherHTTP.calls, 0)
        let again = try await f.driver.drive(resources: resources()); XCTAssertEqual(again, p)
        XCTAssertEqual(f.http.calls, 1); XCTAssertEqual(f.otherHTTP.calls, 0)
        XCTAssertEqual(try SessionStore(database: f.database).checkpoint(), checkpoint)
        let snapshot = await f.runway.snapshot(); XCTAssertNil(snapshot.outstandingAcquisition)
    }
    func test11PreparationFailureRecordsFailed() async throws {
        let f = try fixture(seedLocal:true,prepareFailure:true),p = try await restore(f)
        do { _ = try await tail(f,p); XCTFail("Expected preparation failure") } catch { XCTAssertEqual(error as? Failure,.preparation) }
        let snap = await f.runway.snapshot(); XCTAssertEqual(snap.lastLocalFailure,.failed); XCTAssertEqual(f.http.calls,0)
    }
    func test12CancellationRecordsCancelled() async throws {
        let f = try fixture(seedLocal:true,cancelPrepare:true),p = try await restore(f)
        do { _ = try await tail(f,p); XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        let snap = await f.runway.snapshot(); XCTAssertEqual(snap.lastLocalFailure,.cancelled); XCTAssertEqual(f.http.calls,0)
    }
    func test13SourceContextEligibility() async throws {
        let source = SourceID(),f = try fixture(context:.init(request:.source(source))),p = try await restore(f)
        _ = try await tail(f,p,resources:resources(targets:2))
        XCTAssertGreaterThan(f.http.calls,0); XCTAssertEqual(f.otherHTTP.calls,0)
        XCTAssertEqual(try ContentStore(database:f.database).candidateWindow(sourceID:source,after:nil,examinedCapacity:8).records.count,1)
    }
    func test14LocalSearchSettlesWithoutHTTP() async throws {
        let f = try fixture(context:.init(request:.search(SearchContext(query:"q")!))),p = try await restore(f)
        // Seed the controller's documented exhausted-local fact to exercise the Acquisition boundary only.
        // Deactivation is the explicit reset; re-activating the same scope no longer wipes the scope's state.
        let scope = await f.session.currentRunwayScope()
        await f.runway.deactivate()
        await f.runway.activate(try XCTUnwrap(scope))
        let observation = RunwayObservation(editionID:f.edition,anchorCardID:p.window.anchor.cardID,sampledAt:.init(seconds:1)!,activity:.explicitTailApproach)
        try await f.runway.submitObservation(observation)
        try await f.runway.acceptMeasurement(.init(observation:observation,readyAhead:PublicationHistory(database:f.database).readyAhead(editionID:f.edition,anchorCardID:p.window.anchor.cardID,probeBound:8),advanceFromHighWater:nil))
        guard case .runLocalSlice(let intent) = try await f.runway.reconsider(resources:resources().runway,at:.init(seconds:2)!) else { return XCTFail("Expected local intent") }
        try await f.runway.completeLocalSlice(intent,outcome:.advancedWithoutPublication(.init(examinedCount:0,nextCursor:nil,exhausted:true)),at:.init(seconds:3)!)
        _ = try await f.driver.drive(resources:resources())
        let snap = await f.runway.snapshot(); XCTAssertNil(snap.outstandingAcquisition); XCTAssertEqual(f.http.calls,0)
    }
    func test15SessionContextMismatch() async throws {
        let f = try fixture(driverContext:.init(request:.source(SourceID())))
        // A driver may not restore a checkpoint that does not belong to its own context.
        let restored = try await f.driver.restoreAndActivate(backwardCapacity:1,forwardCapacity:4,resources:resources())
        XCTAssertNil(restored)
        // The fence still rejects a session that holds another context's presentation.
        _ = try await f.session.admitPresentation(.restore(.init(backwardCapacity:1,forwardCapacity:4,
            contextKey: f.plan.context.key)))
        do {
            _ = try await f.driver.activateCurrentPresentation(resources: resources())
            XCTFail("Expected context fence")
        } catch {
            guard case .sessionContextMismatch(_,let actual) = error as? FeedRunwayDriverError else { return XCTFail("Wrong error") }
            XCTAssertEqual(actual,f.plan.context.key)
        }
        XCTAssertEqual(f.http.calls,0)
    }
    func test16EditorialRevisionMismatch() async throws {
        let f = try fixture(differentRevision:true)
        do { _ = try await restore(f); XCTFail("Expected revision fence") }
        catch { guard case .sessionEditorialRevisionMismatch(_,let actual) = error as? FeedRunwayDriverError else { return XCTFail("Wrong error") }; XCTAssertEqual(actual,f.plan.revision.id) }
        XCTAssertEqual(f.http.calls,0)
    }
    func test17PolicyContextMismatchInit() throws {
        let f = try fixture(),db = f.database,config = URLSessionConfiguration.ephemeral,s = URLSession(configuration:config)
        defer { s.invalidateAndCancel() }
        let acquisition = try SyndicationAcquisitionSnapshot(database:db,registrations:[],session:s,redirectCapacity:0)
        XCTAssertThrowsError(try FeedRunwayDriver(session:f.session,runway:f.runway,plan:f.plan,policy:policy(plan(.init(request:.source(SourceID())))),acquisition:acquisition,coordinator:f.coordinator,
            monotonicNow:{ .init(seconds:0)! },makeSegmentIdentity:{ .init(segmentID:FeedSegmentID(),segmentSeed:0,segmentCreatedAt:Date(timeIntervalSince1970:0))! },prepare:Self.prepared)) {
            XCTAssertEqual($0 as? FeedRunwayDriverError,.policyContextMismatch)
        }
    }
    func test18UnknownViewportDoesNotEnterRunway() async throws {
        let f = try fixture(),p = try await restore(f),before = await f.runway.snapshot()
        let result = try await f.driver.submitViewport(.init(anchor:.init(cardID:PublicationCardID(),placement:.top)),activity:.explicitTailApproach,resources:resources())
        let after = await f.runway.snapshot(); XCTAssertEqual(after,before); XCTAssertEqual(result,p); XCTAssertEqual(f.http.calls,0)
    }
    func testRenderedPositionReconciliationDoesNotEnterRunwayOrAcquire() async throws {
        let f = try fixture(historyCount: 4), p = try await restore(f)
        let before = await f.runway.snapshot()
        let observation = ViewportObservation(anchor: .init(cardID: f.cards[2], placement: .top))
        let evidence = try XCTUnwrap(p.evidence(for: observation, reconciliation: true))
        let result = try await f.driver.submitViewport(evidence, activity: .explicitTailApproach, resources: resources())
        let after = await f.runway.snapshot()
        XCTAssertEqual(result?.window.anchor, observation.anchor)
        XCTAssertEqual(after, before, "A local acknowledgement is not reader input to the runway")
        XCTAssertEqual(f.http.calls, 0)
        XCTAssertEqual(f.otherHTTP.calls, 0)
    }

    func test19SameAnchorIsSemanticTailInput() async throws {
        let f = try fixture(registrations:false),p = try await restore(f),before = await f.runway.snapshot()
        _ = try await tail(f,p); let after = await f.runway.snapshot()
        XCTAssertEqual(before.latestObservation?.activity,.stationary); XCTAssertEqual(after.latestObservation?.activity,.explicitTailApproach)
        XCTAssertNotEqual(after.latestObservation,before.latestObservation); XCTAssertEqual(after.latestObservation?.anchorCardID,p.window.anchor.cardID)
    }
    func test20ViewportShiftUsesCommittedAdvance() async throws {
        let f = try fixture(historyCount:4),p = try await restore(f),result = try await f.driver.submitViewport(.init(anchor:.init(cardID:f.cards[2],placement:.top)),activity:.forward,resources:resources(local:false))
        let snap = await f.runway.snapshot(); XCTAssertEqual(snap.consumption.cardsPerSecond,2.0/3.0); XCTAssertNotEqual(result?.window.anchor,p.window.anchor)
    }
    func test21MarkInactivePreservesPresentation() async throws {
        let f = try fixture(),p = try await restore(f); _ = try await tail(f,p,resources:resources(targets:0))
        let before = await f.session.currentPresentation(); await f.driver.markConsumptionInactive()
        let snap = await f.runway.snapshot(),after = await f.session.currentPresentation()
        XCTAssertNil(snap.latestObservation); XCTAssertNil(snap.outstandingAcquisition); XCTAssertEqual(before,after)
        _ = try await f.driver.drive(resources:resources()); XCTAssertEqual(f.http.calls,0)
    }
    /// A reserva de apresentação pronta, como a composição de produção a declara: uma oportunidade que não mede
    /// nada novo (a transição zerou consumo e latência) ainda mantém cartas prontas à frente do leitor.
    private func reservedResources(targets:Int = 1) -> FeedRunwayDriverResources {
        .init(runway:.init(localWorkAllowed:true,examinedCandidateCapacity:8,readyProbeBound:8,
            readyProbeCeiling:64,forwardAdvanceProbeBound:64,reserveCards:4)!,
            acquisition:.init(targetWorkCapacity:targets,batchCapacityPerNewExecution:1,
                observationCapacityPerBatch:8,byteCapacityPerBatch:100_000)!)
    }
    /// INV-04 e a diretiva de execução V2 (linha 86): o runway adquire *antecipando* o consumo, e rolar não é o
    /// que acorda o pipeline. O background zera a observação (`markConsumptionInactive`), e um `drive` depois
    /// disso não tem fato nenhum para agir: era esse o estado que só um gesto do leitor desfazia. O foreground
    /// reativa a apresentação corrente — o mesmo mecanismo do launch/restore — devolvendo ao runway a observação
    /// do leitor na âncora corrente (`.stationary`, nenhum evento de viewport) e a produção acontece.
    func testForegroundReactivationIsAnOpportunityWithoutViewportEvent() async throws {
        let f = try fixture(), store = PublicationStore(database:f.database)
        let p = try await restore(f,resources:reservedResources(targets:0))
        await f.driver.markConsumptionInactive()
        // O mesmo `drive` que o foreground fazia, sem observação: nenhuma oportunidade existe nele.
        _ = try await f.driver.drive(resources:reservedResources(targets:0))
        let empty = await f.runway.snapshot()
        XCTAssertNil(empty.latestObservation)
        XCTAssertNil(empty.outstandingAcquisition)
        let segmentsBefore = try store.segments(editionID:f.edition).count
        let callsBefore = f.http.calls + f.otherHTTP.calls
        // A transição de foreground, sem gesto nenhum.
        let resumed = try await f.driver.activateCurrentPresentation(resources:reservedResources())
        XCTAssertNotNil(resumed)
        let active = await f.runway.snapshot()
        XCTAssertEqual(active.latestObservation?.anchorCardID,p.window.anchor.cardID)
        XCTAssertEqual(active.latestObservation?.activity,.stationary)
        XCTAssertEqual(active.lastCoverage,.pressured(requiredCards:4))
        XCTAssertGreaterThan(try store.segments(editionID:f.edition).count,segmentsBefore,
            "O foreground produziu sem evento de viewport")
        XCTAssertGreaterThan(f.http.calls + f.otherHTTP.calls,callsBefore,
            "A oportunidade do foreground pediu a reposição sem gesto nenhum")
    }
    /// O mesmo tick de foreground, agora com consumo já aprendido. Reativar a apresentação corrente dez segundos
    /// depois não pode apagar a taxa medida — senão a adaptação F05-R2/R3 nunca se aplica em produção — e a medição
    /// preservada continua decidindo: o alvo é `4 cartas/s × 5 s = 20`, não o piso de bootstrap de 4.
    func testForegroundTicksPreserveLearnedConsumptionForTheNextDrive() async throws {
        let f = try fixture(historyCount: 4), p = try await restore(f, resources: reservedResources(targets: 0))
        let activated = await f.runway.snapshot()
        let scope = try XCTUnwrap(activated.scope)
        let sessionScope = await f.session.currentRunwayScope()
        XCTAssertEqual(scope, sessionScope)
        let restored = try XCTUnwrap(activated.latestObservation)
        // The facts a real scroll establishes: a forward advance rates consumption, a publication rates the runway.
        let start = RunwayObservation(editionID: f.edition, anchorCardID: restored.anchorCardID,
            sampledAt: .init(seconds: 200)!, activity: .forward)
        try await f.runway.submitObservation(start)
        try await f.runway.acceptMeasurement(.init(observation: start,
            readyAhead: ReadyAheadFacts(editionID: f.edition, anchorCardID: start.anchorCardID,
                observedTailCardID: start.anchorCardID, amount: .exact(0)),
            advanceFromHighWater: .init(editionID: f.edition, fromCardID: restored.anchorCardID,
                toCardID: start.anchorCardID, advance: .same)))
        let moved = RunwayObservation(editionID: f.edition, anchorCardID: p.window.items[1].id,
            sampledAt: .init(seconds: 202)!, activity: .forward)
        try await f.runway.submitObservation(moved)
        try await f.runway.acceptMeasurement(.init(observation: moved,
            readyAhead: ReadyAheadFacts(editionID: f.edition, anchorCardID: moved.anchorCardID,
                observedTailCardID: moved.anchorCardID, amount: .exact(0)),
            advanceFromHighWater: .init(editionID: f.edition, fromCardID: restored.anchorCardID,
                toCardID: moved.anchorCardID, advance: .forwardExact(8)))) // 8 cards over 2 s = 4 cards/s
        // The restore already exhausted the empty local walk; admitted supply reopens it so the slice can rate the runway.
        try await f.runway.noteLocalSupplyChanged(scope: scope)
        let decision = try await f.runway.reconsider(resources: reservedResources().runway, at: .init(seconds: 212)!)
        guard case .runLocalSlice(let slice) = decision else { return XCTFail("Expected a local slice: \(decision)") }
        try await f.runway.completeLocalSlice(slice, outcome: .published(
            LocalProductionProgress(examinedCount: 8, nextCursor: nil, exhausted: false),
            PublicationReceipt(editionID: f.edition, segmentID: FeedSegmentID(), segmentOrdinal: 1,
                cardIDs: [PublicationCardID()])), at: .init(seconds: 217)!)
        let learned = await f.runway.snapshot()
        XCTAssertEqual(learned.consumption.cardsPerSecond, 4)
        XCTAssertEqual(learned.replenishment.p95Seconds, 5)
        // Two foreground entries, ten seconds apart, and the next opportunity's drive.
        f.clock.jump(to: 1000)
        let first = try await f.driver.activateCurrentPresentation(resources: reservedResources(targets: 0))
        let second = try await f.driver.activateCurrentPresentation(resources: reservedResources(targets: 0))
        XCTAssertEqual(first, second)
        _ = try await f.driver.drive(resources: reservedResources(targets: 0))
        let driven = await f.runway.snapshot()
        XCTAssertEqual(driven.scope, scope)
        XCTAssertEqual(driven.consumption.cardsPerSecond, 4, "A tick is not a scope change")
        XCTAssertEqual(driven.replenishment.p95Seconds, 5, "A tick is not a scope change")
        XCTAssertEqual(driven.lastCoverage, .pressured(requiredCards: 20),
            "The measured target (4 cards/s × 5 s) decided, not the bootstrap reserve of 4")
    }
    func test22DeactivatePreservesPresentation() async throws {
        let f = try fixture(),p = try await restore(f); await f.driver.deactivate()
        let snap = await f.runway.snapshot(),current = await f.session.currentPresentation(); XCTAssertNil(snap.scope); XCTAssertEqual(current,p)
    }
    func test23SameEditionOnly() async throws {
        let f = try fixture(),before = try PublicationStore(database:f.database).edition(id:f.edition),p = try await restore(f)
        _ = try await tail(f,p); XCTAssertEqual(try PublicationStore(database:f.database).edition(id:f.edition),before)
        XCTAssertEqual(try PublicationStore(database:f.database).segments(editionID:f.edition).count,3)
        try await assertLegitimateSecondTarget(f, seededLocal: false)
    }
    /// T3: within one opportunity only a real forward movement at the tail may admit. Backward and
    /// stationary activities deliver their semantic fact to the runway and never extend the list.
    func test25BackwardAndStationaryActivitiesDoNotAdmit() async throws {
        let f = try fixture(), p = try await restore(f)
        _ = try await tail(f, p) // first gesture publishes the second segment and admits nothing new
        let currentValue = await f.session.currentPresentation()
        let current = try XCTUnwrap(currentValue)
        let anchor = ViewportObservation(anchor: .init(cardID: current.window.anchor.cardID, placement: .center))
        for activity in [RunwayActivity.backward, .stationary, .forward] {
            let result = try await f.driver.submitViewport(anchor, activity: activity, resources: resources())
            XCTAssertEqual(result?.window.items.count, current.window.items.count,
                "\(activity) must not admit")
        }
        let extended = try await f.driver.submitViewport(anchor, activity: .explicitTailApproach, resources: resources())
        XCTAssertGreaterThan(extended?.window.items.count ?? 0, current.window.items.count,
            "The explicit tail approach admits the ready prefix")
    }
    func test24SingleTailOpportunityReachesQuiescence() async throws {
        let f = try fixture(),p = try await restore(f); _ = try await tail(f,p)
        let snap = await f.runway.snapshot(); XCTAssertFalse(snap.localSliceInFlight); XCTAssertNil(snap.outstandingAcquisition)
        XCTAssertEqual(try PublicationStore(database:f.database).segments(editionID:f.edition).count,3)
        try await assertLegitimateSecondTarget(f, seededLocal: false)
    }
    func test25SegmentIdentityRequiresFiniteCallerTime() {
        let id = FeedSegmentID(),date = Date(timeIntervalSinceReferenceDate:123.125)
        let value = FeedRunwaySegmentIdentity(segmentID:id,segmentSeed:UInt64.max,segmentCreatedAt:date)
        XCTAssertEqual(value?.segmentID,id); XCTAssertEqual(value?.segmentSeed,UInt64.max); XCTAssertEqual(value?.segmentCreatedAt,date)
        for invalid in [Double.nan,.infinity,-.infinity] {
            XCTAssertNil(FeedRunwaySegmentIdentity(segmentID:id,segmentSeed:0,segmentCreatedAt:Date(timeIntervalSinceReferenceDate:invalid)))
        }
    }

    func testR3NewestViewportDuringHTTPDoesNotStartAnotherCausalExecutor() async throws {
        let f = try fixture(historyCount: 3, paused: true), initial = try await restore(f)
        let first = Task { try await self.tail(f, initial) }
        defer { f.http.release() }
        var started = f.http.started.makeAsyncIterator(); _ = await started.next()
        XCTAssertEqual(f.http.calls, 1); XCTAssertEqual(f.otherHTTP.calls, 0)
        // B changes tail demand while A is still at the external boundary.
        let b = PresentationAnchor(cardID: f.cards[2], placement: .top)
        let (events, signal) = AsyncStream<String>.makeStream()
        f.otherHTTP.onStart { signal.yield("secondGET") }
        let second = Task {
            defer { signal.yield("returned") }
            return try await f.driver.submitViewport(.init(anchor: b), activity: .explicitTailApproach, resources: self.resources())
        }
        var event = events.makeAsyncIterator()
        let boundary = await event.next()
        // Old code starts another target while A is still pending; release it to avoid a hanging reproduction.
        if boundary == "secondGET" { f.http.release() }
        XCTAssertEqual(boundary, "returned", "Concurrent caller must not own another external effect")
        let during = try await second.value
        XCTAssertEqual(during?.window.anchor, b)
        XCTAssertEqual(f.http.calls, 1); XCTAssertEqual(f.otherHTTP.calls, 0)
        let current = await f.session.currentPresentation(); XCTAssertEqual(current, during)
        let observed = await f.runway.snapshot(); XCTAssertEqual(observed.latestObservation?.anchorCardID, b.cardID)
        let c = PresentationAnchor(cardID: f.cards[1], placement: .center)
        let latest = try await f.driver.submitViewport(.init(anchor: c), activity: .explicitTailApproach, resources: resources())
        XCTAssertEqual(latest?.window.anchor, c)
        let pending = await f.runway.snapshot(); XCTAssertNil(pending.readyAhead)
        XCTAssertEqual(pending.latestObservation?.anchorCardID, c.cardID)
        f.http.release()
        let final = try await first.value
        XCTAssertEqual(final?.window.anchor, c)
        let settled = await f.runway.snapshot(); XCTAssertEqual(settled.latestObservation?.anchorCardID, c.cardID)
        XCTAssertEqual(settled.readyAhead?.anchorCardID, c.cardID)
        XCTAssertFalse(settled.localSliceInFlight)
        XCTAssertEqual(try ContentStore(database: f.database).candidateWindow(sourceID: f.source, after: nil, examinedCapacity: 8).records.count, 1)
        let store = PublicationStore(database: f.database)
        let cards = try store.segments(editionID: f.edition).flatMap { segment in
            try segment.cardIDs.map { try XCTUnwrap(store.card(id: $0)) }
        }
        XCTAssertEqual(Set(cards.map(\.originRecordID)).count, cards.count)
        let reopened = try RuntimeDatabase(location: f.location)
        XCTAssertEqual(try PublicationStore(database: reopened).segments(editionID: f.edition), try store.segments(editionID: f.edition))
    }

    func testR1ConcurrentDriveWhileHTTPSuspendedReturnsPresentationWithoutEffects() async throws {
        let f = try fixture(paused: true), p = try await restore(f)
        let first = Task { try await self.tail(f, p) }
        defer { f.http.release() }
        var started = f.http.started.makeAsyncIterator(); _ = await started.next()
        let before = await f.runway.snapshot()
        let other = try await f.driver.drive(resources: resources())
        XCTAssertEqual(other, p); XCTAssertEqual(f.http.calls, 1); XCTAssertEqual(f.otherHTTP.calls, 0)
        let after = await f.runway.snapshot(); XCTAssertEqual(after, before)
        f.http.release(); _ = try await first.value
        try await assertLegitimateSecondTarget(f, seededLocal: false)
    }

    /// P12: while a partially started plan still holds an unattempted target, the end of the opportunity's lease
    /// closes the coordinator's start fence. The pull already authorized keeps running and states its durable
    /// supply (R14), but the next target's transport work must not start after the fence closes — no later
    /// foreground opportunity can be what proves it, because the fence is only reopened there. The foreground
    /// activation (`activateCurrentPresentation`) is the same path launch/restore uses; it reopens the fence and
    /// resumes the work the expired lease withheld.
    ///
    /// The fixture's coordinator runs one target at a time, so the two-target plan is partially started by
    /// construction: the first target is held at the transport boundary and the second has not been authorized.
    /// Release is explicit — nothing here waits for a network timeout to stand in for the fence.
    func testGrantExpiryStopsNewStartsAndForegroundResumes() async throws {
        let f = try fixture(paused: true, otherPaused: false), plan = reservedResources(targets: 2)
        defer { f.http.release() }
        let initial = Task { try await self.restore(f, resources: plan) }
        var started = f.http.started.makeAsyncIterator(); _ = await started.next()
        XCTAssertEqual(f.http.calls, 1, "premissa: o primeiro alvo foi autorizado e está suspenso")
        let active = await f.coordinator.activeExecutions()
        XCTAssertEqual(active.map(\.targetID), [f.target.id],
            "premissa: o plano tem dois alvos; só o primeiro começou")
        XCTAssertEqual(f.otherHTTP.calls, 0, "premissa: o segundo alvo ainda não foi iniciado")
        let beforeExpiryValue = await f.session.currentPresentation()
        let beforeExpiry = try XCTUnwrap(beforeExpiryValue)

        // The lease ends: the driver retires the opportunity — the owner closes the start fence before a transport
        // can be invalidated — while the authorized pull is still in flight.
        await f.driver.deactivate()
        f.http.release()
        _ = try await initial.value
        XCTAssertEqual(f.otherHTTP.calls, 0,
            "o fim da concessão não pode autorizar um novo start depois do fence")
        XCTAssertEqual(f.http.calls, 1, "nenhuma nova aquisição nasceu para repetir bytes já em voo")
        XCTAssertEqual(try ContentStore(database: f.database)
            .candidateWindow(sourceID: f.source, after: nil, examinedCapacity: 8).records.count, 1,
            "a pull já autorizada ainda declara o supply durável que o fence não interrompe")
        let keptValue = await f.session.currentPresentation()
        let kept = try XCTUnwrap(keptValue)
        XCTAssertEqual(kept.editionID, beforeExpiry.editionID, "a edição corrente não muda na expiração")
        XCTAssertEqual(kept.contextKey, beforeExpiry.contextKey, "o contexto corrente não muda na expiração")
        XCTAssertEqual(kept.window.anchor, beforeExpiry.window.anchor,
            "a âncora do leitor não pode ser substituída pela expiração")

        // Attribution window: read the owner's execution state immediately before arming the foreground
        // observation, so a start between that read and the watcher cannot be credited to the foreground.
        let activeBeforeForeground = await f.coordinator.activeExecutions()
        XCTAssertTrue(activeBeforeForeground.isEmpty,
            "a rodada parcialmente iniciada termina sem ter iniciado o segundo alvo")

        // Foreground is a new opportunity through the real activation path: it reopens the fence the expiry closed
        // and the unattempted target finally starts. The start is observed by the transport, not inferred from the
        // driver returning.
        let resumedStart = expectation(description: "foreground starts the target the expired lease withheld")
        let watcher = Task {
            var iterator = f.otherHTTP.started.makeAsyncIterator()
            if await iterator.next() != nil { resumedStart.fulfill() }
        }
        defer { watcher.cancel() }
        let resumed = try await f.driver.activateCurrentPresentation(resources: plan)
        let returned = try XCTUnwrap(resumed, "a ativação de foreground devolve a apresentação corrente")
        XCTAssertEqual(returned.editionID, beforeExpiry.editionID)
        XCTAssertEqual(returned.contextKey, beforeExpiry.contextKey)
        XCTAssertEqual(returned.window.anchor, beforeExpiry.window.anchor,
            "o foreground retoma a mesma apresentação, sem inventar âncora")
        let waited = await XCTWaiter.fulfillment(of: [resumedStart], timeout: 2)
        XCTAssertEqual(waited, .completed, "o foreground retoma o alvo retido pela concessão expirada")

        // The resumed target must have produced durable supply, not merely a transport start: the deadline above
        // proves the start; this waits on coordinator state (inFlight is cleared only after admission) and reads
        // the admitted window of the source the expired lease had withheld.
        await settleAcquisitions(f)
        XCTAssertGreaterThanOrEqual(try ContentStore(database: f.database)
            .candidateWindow(sourceID: f.otherSource, after: nil, examinedCapacity: 8).records.count, 1,
            "o alvo retomado pelo foreground entrega supply durável ao owner")
    }

    /// P12: a context return activates the local presentation while an unrelated source's pull — started by the
    /// previous opportunity — is still suspended at the transport boundary. Completion must come from the local
    /// navigation and from the existing join rule (an execution another owner already runs is not this
    /// opportunity's work), never from the network timing out: the return has to complete with the fixture still
    /// held, and the pending source must be joined rather than fetched again for bytes that are already valid.
    ///
    /// The fixture's first activation publishes the fast target's supply and leaves the second target's pull in
    /// flight. Retirement closes the opportunity without cancelling that authorized pull; the return then opens
    /// the same context again. If the activation awaited the unrelated pull (or re-started it), the bounded wait
    /// below fails while the source is still suspended, and the release afterwards is only cleanup.
    func testContextReturnCompletesWhileUnrelatedSourceIsStillSuspended() async throws {
        let f = try fixture(paused: false, otherPaused: true), plan = reservedResources(targets: 2)
        defer { f.otherHTTP.release() }
        let p = try await restore(f, resources: plan)
        var started = f.otherHTTP.started.makeAsyncIterator(); _ = await started.next()
        XCTAssertEqual(f.otherHTTP.calls, 1, "premissa: a fonte alheia está suspensa")
        let activeBeforeRetirement = await f.coordinator.activeExecutions()
        XCTAssertTrue(activeBeforeRetirement.map(\.targetID).contains(f.otherTarget.id),
            "premissa: a pull alheia está ativa antes da aposentadoria")

        // The reader leaves the context: retirement does not invalidate the authorized pull (R14/R20).
        await f.driver.deactivate()
        let activeAfterRetirement = await f.coordinator.activeExecutions()
        XCTAssertTrue(activeAfterRetirement.map(\.targetID).contains(f.otherTarget.id),
            "a aposentadoria não cancela a pull autorizada")

        let returned = expectation(description: "context return completes while the unrelated source is suspended")
        let httpCallsBeforeReturn = f.http.calls
        let task = Task { () -> FeedPresentationSnapshot? in
            let snapshot = try await f.driver.activateCurrentPresentation(resources: plan)
            returned.fulfill()
            return snapshot
        }
        let waited = await XCTWaiter.fulfillment(of: [returned], timeout: 2)
        XCTAssertEqual(waited, .completed,
            "o retorno tem de concluir antes de liberar a fonte alheia, não pelo timeout da rede")
        XCTAssertEqual(f.otherHTTP.calls, 1, "uma pull pendente válida é unida, não repetida")
        XCTAssertGreaterThan(f.http.calls, httpCallsBeforeReturn,
            "o retorno passou pela oportunidade real de aquisição, não só pela restauração local")
        let activeAfterReturn = await f.coordinator.activeExecutions()
        XCTAssertTrue(activeAfterReturn.map(\.targetID).contains(f.otherTarget.id),
            "o retorno não cancela nem substitui a execução alheia")

        // If the return timed out it is still waiting on the unrelated pull; release only to finish the test. In the
        // contract this assertion passes before the line is reached.
        if waited != .completed { f.otherHTTP.release() }
        let back = try await task.value
        XCTAssertEqual(back?.editionID, p.editionID, "a edição canônica do contexto é reaproveitada")
        XCTAssertEqual(back?.contextKey, p.contextKey, "o contexto do retorno é o mesmo do leitor")
        XCTAssertEqual(back?.window.anchor, p.window.anchor, "a âncora prometida não é inventada")
        let returnedPresentation = await f.session.currentPresentation()
        XCTAssertEqual(returnedPresentation, back)

        // The unrelated source is released only now, after the return has already completed. Its authorized pull
        // must still settle into durable supply through the existing owner, and that cannot install an older
        // projection over the reader's anchor.
        f.otherHTTP.release()
        await settleAcquisitions(f)
        XCTAssertGreaterThanOrEqual(try ContentStore(database: f.database)
            .candidateWindow(sourceID: f.otherSource, after: nil, examinedCapacity: 8).records.count, 1,
            "o supply durável da pull unida chega ao owner")
        let settledValue = await f.session.currentPresentation()
        let settled = try XCTUnwrap(settledValue)
        XCTAssertEqual(settled.editionID, p.editionID)
        XCTAssertEqual(settled.contextKey, p.contextKey)
        XCTAssertEqual(settled.window.anchor, p.window.anchor,
            "a fonte alheia não instala projeção antiga sobre a âncora do leitor")
    }

    func testR14DeactivateDuringHTTPKeepsSupplyWithoutReactivatingOrPublishing() async throws {
        let f = try fixture(paused: true), p = try await restore(f)
        let first = Task { try await self.tail(f, p) }
        defer { f.http.release() }
        var started = f.http.started.makeAsyncIterator(); _ = await started.next()
        await f.driver.deactivate()
        f.http.release(); let result = try await first.value
        XCTAssertEqual(result, p)
        let snapshot = await f.runway.snapshot(); XCTAssertNil(snapshot.scope); XCTAssertNil(snapshot.latestObservation)
        XCTAssertEqual(try ContentStore(database: f.database).candidateWindow(sourceID: f.source, after: nil, examinedCapacity: 8).records.count, 1)
        XCTAssertEqual(try PublicationStore(database: f.database).segments(editionID: f.edition).count, 1)
        XCTAssertEqual(f.http.calls, 1); XCTAssertEqual(f.otherHTTP.calls, 0)
        _ = try await f.driver.activateCurrentPresentation(resources: resources())
        let active = await f.runway.snapshot(); XCTAssertEqual(active.scope?.editionID, f.edition)
    }

    func testR12StructuralFailureReleasesOwnerAndPreservesPresentation() async throws {
        let f = try fixture(paused: true), p = try await restore(f)
        let first = Task { try await self.tail(f, p) }
        defer { f.http.release() }
        var started = f.http.started.makeAsyncIterator(); _ = await started.next()
        _ = try AcquisitionTargetAuthority(database: f.database).reconfigure(id: f.target.id, expectedGeneration: 1,
            connectorKind: .syndication, checkpoint: .preserve, authorizedSources: [f.source])
        f.http.release()
        do { _ = try await first.value; XCTFail("Expected structural fence error") }
        catch { XCTAssertEqual(error as? AcquisitionTargetStoreError, .staleGeneration(expected: 1, actual: 2)) }
        let current = await f.session.currentPresentation(); XCTAssertEqual(current, p)
        let again = try await f.driver.activateCurrentPresentation(resources: resources())
        XCTAssertEqual(again, p)
        let snapshot = await f.runway.snapshot(); XCTAssertNotNil(snapshot.readyAhead)
        let active = await f.coordinator.activeExecutions(); XCTAssertTrue(active.isEmpty)
        XCTAssertEqual(f.http.calls, 1)
    }

    func testR13CancellationDuringHTTPReleasesOwnerAndCoordinator() async throws {
        let f = try fixture(paused: true), p = try await restore(f)
        let first = Task { try await self.tail(f, p) }
        defer { f.http.release() }
        var started = f.http.started.makeAsyncIterator(); _ = await started.next()
        first.cancel()
        do { let result = try await first.value; XCTAssertEqual(result, p) }
        catch { XCTAssertTrue(error is CancellationError) }
        let active = await f.coordinator.activeExecutions(); XCTAssertTrue(active.isEmpty)
        XCTAssertEqual(try AcquisitionTargetAuthority(database: f.database).target(id: f.target.id)?.checkpointRevision, 0)
        XCTAssertEqual(try PublicationStore(database: f.database).segments(editionID: f.edition).count, 1)
        let again = try await f.driver.activateCurrentPresentation(resources: resources())
        XCTAssertEqual(again, p)
        let snapshot = await f.runway.snapshot(); XCTAssertNotNil(snapshot.readyAhead)
        XCTAssertEqual(f.http.calls, 1)
    }

    func testR15ContextAndEditionChangeDuringHTTPPreservesNewPresentation() async throws {
        let f = try fixture(paused: true), p = try await restore(f)
        let first = Task { try await self.tail(f, p) }
        defer { f.http.release() }
        var started = f.http.started.makeAsyncIterator(); _ = await started.next()
        let otherPlan = plan(.init(request: .source(SourceID()))), otherEdition = FeedEditionID()
        let candidate = Candidate(originRecordID: OriginRecordID(), originRevisionID: OriginRevisionID(), headline: "other-context",
            summary: nil, timestamp: .init(value: Date(timeIntervalSince1970: 30), kind: .observed), language: nil, providerID: nil)
        let selection = SelectionResult(editorialRevision: otherPlan.revision, orderedCandidates: [candidate],
            supplyReport: .init(examinedCount: 0, nextCursor: nil, exhausted: true))
        let prepared = Self.prepared(selection)
        _ = try PublicationCoordinator(database: f.database).createEdition(.init(selection: selection,
            drafts: PublicationPreparation.drafts(selection: selection, inputs: prepared.inputs), editionID: otherEdition,
            publicationSchemaVersion: .init(rawValue: 1), selectionSeed: 1, editionCreatedAt: Date(timeIntervalSince1970: 30),
            segmentID: FeedSegmentID(), segmentSeed: 1, segmentCreatedAt: Date(timeIntervalSince1970: 31), cardIDs: prepared.cardIDs))
        try PublicationHistory(database: f.database).saveCursor(.init(editionID: otherEdition,
            anchor: .init(cardID: prepared.cardIDs[0], placement: .center)), updatedAt: Date(timeIntervalSince1970: 32))
        // Another context owns its own association: its own session, edition and checkpoint (T2).
        let otherSession = FeedSession(publicationHistory: .init(database: f.database))
        let otherValue = try await otherSession.admitPresentation(.restore(.init(backwardCapacity: 1,
            forwardCapacity: 4, contextKey: otherPlan.context.key)))
        let otherCurrent = try XCTUnwrap(otherValue)
        XCTAssertEqual(otherCurrent.contextKey, otherPlan.context.key)
        XCTAssertEqual(otherCurrent.editionID, otherEdition)
        f.http.release(); let result = try await first.value
        // The suspended opportunity belongs to the first session and returns exactly its own presentation…
        let final = await f.session.currentPresentation()
        XCTAssertEqual(result, final)
        XCTAssertEqual(final?.contextKey, p.contextKey)
        XCTAssertEqual(final?.editionID, f.edition)
        // …and never touches the other context's presentation, edition or checkpoint.
        let otherFinal = await otherSession.currentPresentation()
        XCTAssertEqual(otherFinal, otherCurrent)
        XCTAssertEqual(try PublicationStore(database: f.database).segments(editionID: otherEdition).count, 1)
        XCTAssertEqual(try SessionStore(database: f.database).checkpoint()?.editionID, otherEdition)
        XCTAssertEqual(try ContentStore(database: f.database).candidateWindow(sourceID: f.source, after: nil, examinedCapacity: 8).records.count, 1)
        // The opportunity did its own acquisition work; what matters is that it produced nothing in
        // the other context's edition (asserted above) and nothing extra in the reader's presentation.
        XCTAssertGreaterThanOrEqual(f.http.calls, 1)
    }

    func testR16NewEditionActivationDuringHTTPGetsReconsideredByOwner() async throws {
        let f = try fixture(paused: true), p = try await restore(f)
        let first = Task { try await self.tail(f, p) }
        defer { f.http.release() }
        var started = f.http.started.makeAsyncIterator(); _ = await started.next()
        let otherPlan = f.plan, otherEdition = FeedEditionID()
        let candidate = Candidate(originRecordID: OriginRecordID(), originRevisionID: OriginRevisionID(), headline: "other-context",
            summary: nil, timestamp: .init(value: Date(timeIntervalSince1970: 30), kind: .observed), language: nil, providerID: nil)
        let selection = SelectionResult(editorialRevision: otherPlan.revision, orderedCandidates: [candidate],
            supplyReport: .init(examinedCount: 0, nextCursor: nil, exhausted: true))
        let prepared = Self.prepared(selection)
        _ = try PublicationCoordinator(database: f.database).createEdition(.init(selection: selection,
            drafts: PublicationPreparation.drafts(selection: selection, inputs: prepared.inputs), editionID: otherEdition,
            publicationSchemaVersion: .init(rawValue: 1), selectionSeed: 1, editionCreatedAt: Date(timeIntervalSince1970: 30),
            segmentID: FeedSegmentID(), segmentSeed: 1, segmentCreatedAt: Date(timeIntervalSince1970: 31), cardIDs: prepared.cardIDs))
        try PublicationHistory(database: f.database).saveCursor(.init(editionID: otherEdition,
            anchor: .init(cardID: prepared.cardIDs[0], placement: .center)), updatedAt: Date(timeIntervalSince1970: 32))
        // Real replacement: a second association/owner is created for B. The old A owner is suspended before its
        // tail releases, so its durable result no longer authorizes publication in A.
        let otherSession = FeedSession(publicationHistory: PublicationHistory(database: f.database))
        let otherRestored = try await otherSession.admitPresentation(.restore(.init(backwardCapacity: 1, forwardCapacity: 4)))
        let b = try XCTUnwrap(otherRestored)
        XCTAssertEqual(b.editionID, otherEdition, "B must assume the presentation before A's tail releases")
        let otherRunway = RunwayController(configuration: .init(policyInputs: .init(safetyFactor: 1, releaseMarginSeconds: 0)!,
            consumptionSampleLimit: 2, replenishmentSampleLimit: 2)!)
        let otherDriver = try FeedRunwayDriver(session: otherSession, runway: otherRunway, plan: f.plan, policy: f.policy,
            acquisition: f.acquisition, coordinator: f.coordinator,
            monotonicNow: { .init(seconds: ProcessInfo.processInfo.systemUptime)! },
            makeSegmentIdentity: { .init(segmentID: .init(), segmentSeed: 1, segmentCreatedAt: Date())! },
            prepare: Self.prepared)
        let activated = try await otherDriver.activateCurrentPresentation(resources: resources())
        XCTAssertEqual(activated?.editionID, otherEdition)
        await f.driver.suspendForBackground()
        f.http.release(); let result = try await first.value
        XCTAssertEqual(result?.editionID, f.edition, "the old tail still states A, not B")
        let final = await otherSession.currentPresentation(); XCTAssertEqual(final, activated)
        XCTAssertEqual(final?.contextKey, otherPlan.context.key)
        XCTAssertEqual(try PublicationStore(database: f.database).segments(editionID: otherEdition).count, 1)
        XCTAssertEqual(try PublicationStore(database: f.database).segments(editionID: f.edition).count, 1,
            "A's old owner loses publication authorization when B assumes the association")
        XCTAssertEqual(try ContentStore(database: f.database).candidateWindow(sourceID: f.source, after: nil, examinedCapacity: 8).records.count, 1)
        XCTAssertEqual(f.http.calls, 1); XCTAssertEqual(f.otherHTTP.calls, 0)
    }

    func testR18IndependentDriversBothEnterHTTPBeforeEitherIsReleased() async throws {
        let a = try fixture(paused: true), b = try fixture(paused: true)
        let pa = try await restore(a), pb = try await restore(b)
        let first = Task { try await self.tail(a, pa) }
        let second = Task { try await self.tail(b, pb) }
        defer { a.http.release(); b.http.release() }
        var sa = a.http.started.makeAsyncIterator(), sb = b.http.started.makeAsyncIterator()
        _ = await sa.next(); _ = await sb.next()
        XCTAssertEqual(a.http.calls, 1); XCTAssertEqual(b.http.calls, 1)
        a.http.release(); b.http.release()
        _ = try await first.value; _ = try await second.value
        try await assertLegitimateSecondTarget(a, seededLocal: false)
        try await assertLegitimateSecondTarget(b, seededLocal: false)
    }

    private func coldIdentity() -> ColdFeedPublicationIdentity {
        .init(editionID: FeedEditionID(), publicationSchemaVersion: .init(rawValue: 1), selectionSeed: 1,
            editionCreatedAt: Date(timeIntervalSince1970: 10), segmentID: FeedSegmentID(), segmentSeed: 2,
            segmentCreatedAt: Date(timeIntervalSince1970: 11), anchorPlacement: .top,
            checkpointedAt: Date(timeIntervalSince1970: 12))!
    }
    private func coldResources() -> ColdFeedBootstrapResources {
        .init(localExaminedCapacity: 8, acquisition: resources().acquisition)!
    }
    func testQ1ColdAndRunwayShareCompositionCoordinatorAndDatabase() async throws {
        let source = SourceID(), f = try fixture(checkpoint: false, paused: true, context: .init(request: .source(source)))
        // fixture.driver and bootstrap receive this one composition-owned instance, over f.database.
        let shared = f.coordinator, id = coldIdentity()
        let bootstrap = try ColdFeedBootstrap(session: f.session, plan: f.plan, policy: f.policy,
            acquisition: f.acquisition, coordinator: shared, prepare: Self.prepared)
        let bounds = coldResources()
        let task = Task { try await bootstrap.run(identity: id, resources: bounds, backwardCapacity: 0, forwardCapacity: 2) }
        defer { f.http.release() }
        var started = f.http.started.makeAsyncIterator(); _ = await started.next()
        let active = await shared.activeExecutions()
        XCTAssertEqual(active, [AcquisitionActiveExecution(targetID: f.target.id, generation: 1)!])
        XCTAssertNil(try SessionStore(database: f.database).checkpoint())
        f.http.release()
        guard case .published(let first) = try await task.value else { return XCTFail("Expected first cold presentation") }
        XCTAssertEqual(first.editionID, id.editionID); XCTAssertEqual(f.http.calls, 1)
        XCTAssertEqual(try ContentStore(database: f.database).candidateWindow(sourceID: source, after: nil, examinedCapacity: 8).records.count, 1)
        let checkpoint = try SessionStore(database: f.database).checkpoint()
        let restored = try await restore(f)
        XCTAssertEqual(restored.editionID, first.editionID)
        let afterTail = try await tail(f, restored)
        XCTAssertEqual(afterTail?.editionID, id.editionID); XCTAssertEqual(f.http.calls, 2)
        XCTAssertEqual(try SessionStore(database: f.database).checkpoint(), checkpoint)
        XCTAssertEqual(try PublicationStore(database: f.database).segments(editionID: id.editionID).count, 1)
        let settled = await shared.activeExecutions(); XCTAssertTrue(settled.isEmpty)
    }
    func testQ2DriverObservesSharedActiveGenerationConflictWithoutReplacement() async throws {
        let source = SourceID(), f = try fixture(paused: true, context: .init(request: .source(source)))
        let shared = f.coordinator
        let work = AcquisitionPlannedWork.start(target: f.target,
            bounds: .init(batchCapacity: 1, observationCapacityPerBatch: 8, byteCapacityPerBatch: 100_000)!)
        let oldExecution = Task { try await shared.execute(work) }
        defer { f.http.release() }
        var started = f.http.started.makeAsyncIterator(); _ = await started.next()
        let oldActive = await shared.activeExecutions()
        XCTAssertEqual(oldActive, [AcquisitionActiveExecution(targetID: f.target.id, generation: 1)!])
        let authority = AcquisitionTargetAuthority(database: f.database)
        let next = try authority.reconfigure(id: f.target.id, expectedGeneration: 1, connectorKind: .syndication, checkpoint: .preserve, authorizedSources: [f.source])
        let binding = SourceBinding(id: SourceBindingID(), sourceID: source,
            externalPrincipal: .init(connectorKind: .syndication, namespace: "p", value: "new-configuration", role: .principal),
            aliases: [], generation: 2, state: .enabled)!
        // Publish the G2 configuration only after its durable fence. Its endpoint responds immediately
        // so a regression that creates a replacement coordinator fails without hanging on paused G1.
        let registration = SyndicationTargetRegistration(targetID: next.id, targetGeneration: next.generation,
            endpoint: f.otherHTTP.url, bindings: [binding])!
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [DriverURLProtocol.self]
        let transport = URLSession(configuration: configuration)
        addTeardownBlock { transport.invalidateAndCancel() }
        let acquisition = try SyndicationAcquisitionSnapshot(database: f.database, registrations: [registration],
            session: transport, redirectCapacity: 0, now: { Date(timeIntervalSince1970: 5) })
        let eligible = try acquisition.eligibleTargets(for: f.plan.context)
        XCTAssertEqual(eligible, [next]); XCTAssertEqual(next.generation, 2)
        let checkpoint = try SessionStore(database: f.database).checkpoint()
        let id = coldIdentity()
        let bootstrap = try ColdFeedBootstrap(session: f.session, plan: f.plan, policy: f.policy,
            acquisition: acquisition, coordinator: shared, prepare: Self.prepared)
        guard case .deferred(let progress, .activeGenerationConflict) = try await bootstrap.run(identity: id,
            resources: coldResources(), backwardCapacity: 0, forwardCapacity: 2) else {
            return XCTFail("Cold consumer must observe the shared G1 execution")
        }
        XCTAssertTrue(progress.exhausted)
        let clock = DriverClock()
        let driver = try FeedRunwayDriver(session: f.session, runway: f.runway, plan: f.plan, policy: f.policy,
            acquisition: acquisition, coordinator: shared, monotonicNow: { clock.next() },
            makeSegmentIdentity: { .init(segmentID: FeedSegmentID(), segmentSeed: 2, segmentCreatedAt: Date(timeIntervalSince1970: 6))! },
            prepare: Self.prepared)
        let restoredValue = try await driver.restoreAndActivate(backwardCapacity: 0, forwardCapacity: 2, resources: resources())
        let restored = try XCTUnwrap(restoredValue)
        let result = try await driver.submitViewport(.init(anchor: restored.window.anchor), activity: .explicitTailApproach, resources: resources())
        XCTAssertEqual(result, restored)
        let pending = await f.runway.snapshot()
        let intent = try XCTUnwrap(pending.outstandingAcquisition)
        XCTAssertEqual(intent.demand.purpose, .readerContinuation)
        XCTAssertTrue(pending.localSupplyExhausted)
        // The existing cycle exposes the precise disposition for the same still-pending intent.
        let start = try await RunwayAcquisitionCycle(runway: f.runway, coordinator: shared).start(intent,
            eligibleTargets: eligible, resources: resources().acquisition)
        guard case .deferred(.activeGenerationConflict) = start else {
            return XCTFail("The still-pending intent must be deferred for the shared active generation")
        }
        let unchanged = await f.runway.snapshot(); XCTAssertEqual(unchanged, pending)
        let stillActive = await shared.activeExecutions(); XCTAssertEqual(stillActive, oldActive)
        XCTAssertEqual(f.http.calls, 1); XCTAssertEqual(f.otherHTTP.calls, 0)
        XCTAssertEqual(try SessionStore(database: f.database).checkpoint(), checkpoint)
        XCTAssertEqual(try PublicationStore(database: f.database).segments(editionID: f.edition).count, 1)
        XCTAssertNil(try PublicationStore(database: f.database).edition(id: id.editionID))
        f.http.release()
        do { _ = try await oldExecution.value; XCTFail("Obsolete G1 Admission must be rejected") }
        catch { XCTAssertEqual(error as? AcquisitionTargetStoreError, .staleGeneration(expected: 1, actual: 2)) }
        XCTAssertTrue(try ContentStore(database: f.database).candidateWindow(sourceID: nil, after: nil, examinedCapacity: 8).records.isEmpty)
        XCTAssertEqual(try authority.target(id: next.id), next)
        XCTAssertEqual(try SessionStore(database: f.database).checkpoint(), checkpoint)
        let settled = await shared.activeExecutions(); XCTAssertTrue(settled.isEmpty)
    }
    func testQ4ConsumersNeverConstructTheirOwnCoordinator() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for file in ["ColdFeedBootstrap.swift", "FeedRunwayDriver.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent("Sources/FeedMineComposition/" + file), encoding: .utf8)
            XCTAssertNil(source.range(of: #"\bmakeCoordinator\s*\("#, options: .regularExpression), file)
            XCTAssertNil(source.range(of: #"\bAcquisitionCoordinator\s*\("#, options: .regularExpression), file)
        }
    }

}
private final class DriverHTTPFixture: @unchecked Sendable {
    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var registry:[String:DriverHTTPFixture] = [:]
    let url = URL(string:"https://driver-"+UUID().uuidString.lowercased()+".test/feed")!
    let paused:Bool
    let error:URLError?
    let started:AsyncStream<Void>
    private let signal:AsyncStream<Void>.Continuation
    private let lock = NSLock()
    private var pending:DriverURLProtocol?
    private var count = 0
    private var readyCounts: [ReadyAheadAmount] = []
    private let readyBeforePull: (@Sendable () throws -> ReadyAheadAmount)?
    private var released = false
    private var startCallback: (@Sendable () -> Void)?
    func onStart(_ callback: @escaping @Sendable () -> Void) { lock.withLock { startCallback = callback } }
    init(paused:Bool,error:URLError?, readyBeforePull: (@Sendable () throws -> ReadyAheadAmount)? = nil) {
        self.readyBeforePull = readyBeforePull
        self.paused = paused; self.error = error; (started,signal) = AsyncStream.makeStream()
        Self.registryLock.withLock { Self.registry[url.host!] = self }
    }
    static func find(_ url:URL?) -> DriverHTTPFixture? { registryLock.withLock { registry[url?.host ?? ""] } }
    func remove() { _ = Self.registryLock.withLock { Self.registry.removeValue(forKey:url.host!) } }
    var calls:Int { lock.withLock { count } }
    var readyBefore: [ReadyAheadAmount] { lock.withLock { readyCounts } }
    func start(_ loader:DriverURLProtocol) {
        let wait = lock.withLock { count += 1; if paused && !released { pending = loader; return true }; return false }
        if let readyBeforePull {
            do { let amount = try readyBeforePull(); lock.withLock { readyCounts.append(amount) } }
            catch { XCTFail("Ready-before-pull evidence failed: \(error)") }
        }
        signal.yield(()); let callback = lock.withLock { startCallback }; callback?(); if !wait { respond(loader) }
    }
    func release() { let loader = lock.withLock { released = true; let value = pending; pending = nil; return value }; if let loader { respond(loader) } }
    /// URLSession calls this when the task is cancelled. Without it the pending loader is never
    /// resumed, so the cancellation only completes when the request timeout fires (measured: 60 s).
    func stop(_ loader:DriverURLProtocol) {
        let stopped = lock.withLock { () -> DriverURLProtocol? in
            guard pending === loader else { return nil }
            let current = pending; pending = nil; return current
        }
        if let stopped { stopped.client?.urlProtocol(stopped, didFailWithError: URLError(.cancelled)) }
    }
    private func respond(_ loader:DriverURLProtocol) {
        if let error { loader.client?.urlProtocol(loader,didFailWithError:error); return }
        let response = HTTPURLResponse(url:url,statusCode:200,httpVersion:"HTTP/1.1",headerFields:["Content-Type":"application/rss+xml"])!
        loader.client?.urlProtocol(loader,didReceive:response,cacheStoragePolicy:.notAllowed)
        loader.client?.urlProtocol(loader,didLoad:Data("<rss version=\"2.0\"><channel><title>Feed</title><item><guid>remote</guid><title>Remote</title></item></channel></rss>".utf8))
        loader.client?.urlProtocolDidFinishLoading(loader)
    }
}
private final class DriverURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request:URLRequest) -> Bool { DriverHTTPFixture.find(request.url) != nil }
    override class func canonicalRequest(for request:URLRequest) -> URLRequest { request }
    override func startLoading() { DriverHTTPFixture.find(request.url)?.start(self) }
    override func stopLoading() { DriverHTTPFixture.find(request.url)?.stop(self) }
}

extension FeedRunwayDriverTests {
    func testSourceRuleRemovalReopensAPassedWalkWithoutReplacingReaderOrDuplicatingHistory() async throws {
        let f = try fixture(registrations: false)
        let prefs = ReaderPreferencesStore(database: f.database)
        _ = try prefs.initialize(sourceKeys: ["source"])
        var settings = try XCTUnwrap(prefs.load()).settings
        settings.contentSourceExclusions = [.init(sourceID: f.source, displayName: "Source")]
        _ = try prefs.setSettings(settings)
        let revision = try Self.admitLateLocal(f.database, target: f.target.id, source: f.source)
        let before = try await restore(f)
        _ = try await tail(f, before)
        _ = try await f.driver.drive(resources: resources())
        let store = PublicationStore(database: f.database)
        let first = try XCTUnwrap(store.card(id: f.cards[0]))
        let checkpoint = try SessionStore(database: f.database).checkpoint()
        XCTAssertEqual(try store.segments(editionID: f.edition).flatMap(\.cardIDs), f.cards)
        for _ in 0..<200_000 {
            let state = await f.runway.snapshot()
            if state.localSupplyExhausted && !state.localSliceInFlight { break }
            await Task.yield()
        }
        let exhausted = await f.runway.snapshot()
        XCTAssertTrue(exhausted.localSupplyExhausted, "premise: the walk passed the excluded origin; state=\(exhausted)")
        guard exhausted.localSupplyExhausted else { return }
        settings.contentSourceExclusions = []
        _ = try prefs.setSettings(settings)
        await f.driver.noteSourceExclusionsChanged()
        _ = try await f.driver.drive(resources: resources())
        // The existing late-fact drain is asynchronous; its receipt is the completion signal.
        for _ in 0..<200_000 {
            if !f.publications.values.isEmpty { break }
            await Task.yield()
        }
        XCTAssertEqual(f.publications.values.count, 1)
        let ids = try store.segments(editionID: f.edition).flatMap(\.cardIDs)
        XCTAssertEqual(ids.count, f.cards.count + 1)
        XCTAssertEqual(try store.card(id: try XCTUnwrap(ids.last))?.originRevisionID, revision)
        XCTAssertEqual(try store.card(id: first.id), first)
        XCTAssertEqual(try SessionStore(database: f.database).checkpoint(), checkpoint)
        let current = await f.session.currentPresentation()
        let after = try XCTUnwrap(current)
        XCTAssertEqual(after.editionID, before.editionID)
        XCTAssertEqual(after.window.anchor, before.window.anchor)
        let state = await f.runway.snapshot()
        await f.driver.noteSourceExclusionsChanged()
        let unchanged = await f.runway.snapshot()
        XCTAssertEqual(unchanged, state, "an empty unchanged rule set is not another reset")
        _ = try await f.driver.drive(resources: resources())
        XCTAssertEqual(try store.segments(editionID: f.edition).flatMap(\.cardIDs), ids)
    }
}

extension FeedRunwayDriverTests {
    func testWordRuleRemovalReopensPassedWalkWithoutReplacingReaderOrDuplicatingHistory() async throws {
        let f = try fixture(registrations: false, wordPolicyEnabled: true)
        let prefs = ReaderPreferencesStore(database: f.database)
        _ = try prefs.initialize(sourceKeys: ["source"])
        var settings = try XCTUnwrap(prefs.load()).settings
        settings.contentFilterRules = ["late"]
        _ = try prefs.setSettings(settings)
        let revision = try Self.admitLateLocal(f.database, target: f.target.id, source: f.source)
        let before = try await restore(f)
        _ = try await tail(f, before)
        _ = try await f.driver.drive(resources: resources())
        let store = PublicationStore(database: f.database)
        let first = try XCTUnwrap(store.card(id: f.cards[0]))
        let checkpoint = try SessionStore(database: f.database).checkpoint()
        XCTAssertEqual(try store.segments(editionID: f.edition).flatMap(\.cardIDs), f.cards)
        for _ in 0..<200_000 {
            let state = await f.runway.snapshot()
            if state.localSupplyExhausted && !state.localSliceInFlight { break }
            await Task.yield()
        }
        let exhausted = await f.runway.snapshot()
        XCTAssertTrue(exhausted.localSupplyExhausted, "premise: the walk passed the excluded origin; state=\(exhausted)")
        guard exhausted.localSupplyExhausted else { return }
        settings.contentFilterRules = []
        _ = try prefs.setSettings(settings)
        await f.driver.noteContentExclusionsChanged()
        _ = try await f.driver.drive(resources: resources())
        // The existing late-fact drain is asynchronous; its receipt is the completion signal.
        for _ in 0..<200_000 {
            if !f.publications.values.isEmpty { break }
            await Task.yield()
        }
        XCTAssertEqual(f.publications.values.count, 1)
        let ids = try store.segments(editionID: f.edition).flatMap(\.cardIDs)
        XCTAssertEqual(ids.count, f.cards.count + 1)
        XCTAssertEqual(try store.card(id: try XCTUnwrap(ids.last))?.originRevisionID, revision)
        XCTAssertEqual(try store.card(id: first.id), first)
        XCTAssertEqual(try SessionStore(database: f.database).checkpoint(), checkpoint)
        let current = await f.session.currentPresentation()
        let after = try XCTUnwrap(current)
        XCTAssertEqual(after.editionID, before.editionID)
        XCTAssertEqual(after.window.anchor, before.window.anchor)
        let state = await f.runway.snapshot()
        await f.driver.noteContentExclusionsChanged()
        let unchanged = await f.runway.snapshot()
        XCTAssertEqual(unchanged, state, "an empty unchanged rule set is not another reset")
        settings.contentFiltersEnabled = false
        settings.contentFilterRules = ["late"]
        settings.contentFilterTemplates = ["missing-but-masked"]
        _ = try prefs.setSettings(settings)
        await f.driver.noteContentExclusionsChanged()
        let equivalent = await f.runway.snapshot()
        XCTAssertEqual(equivalent, state, "masked stored words/templates do not change effective policy")
        _ = try await f.driver.drive(resources: resources())
        XCTAssertEqual(try store.segments(editionID: f.edition).flatMap(\.cardIDs), ids)
    }
}

extension FeedRunwayDriverTests {
    func testWordRaceDuringLivePreparationRejectsStaleCardsAndPreservesReader() async throws {
        let f = try fixture(registrations: false, wordPolicyEnabled: true, wordChangeDuringPrepare: true)
        let prefs = ReaderPreferencesStore(database: f.database)
        _ = try prefs.initialize(sourceKeys: ["source"])
        _ = try Self.admitLateLocal(f.database, target: f.target.id, source: f.source)
        let before = try await restore(f)
        _ = try await tail(f, before)
        _ = try await f.driver.drive(resources: resources())
        let store = PublicationStore(database: f.database)
        XCTAssertEqual(try store.segments(editionID: f.edition).flatMap(\.cardIDs), f.cards)
        XCTAssertTrue(f.publications.values.isEmpty, "stale prepared late card must never commit")
        let current = await f.session.currentPresentation()
        XCTAssertEqual(current?.editionID, before.editionID)
        XCTAssertEqual(current?.window.anchor, before.window.anchor)
        XCTAssertEqual(try prefs.load()?.settings.contentFilterRules, ["late"])
    }
}
