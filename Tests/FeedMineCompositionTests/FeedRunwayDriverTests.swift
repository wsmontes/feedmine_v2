import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineAcquisition
import FeedMineEditorial
import FeedMinePublication
@testable import FeedMineRuntime
import FeedMineComposition

private final class DriverClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double = 0
    func next() -> RunwayMonotonicTime { lock.withLock { value += 1; return .init(seconds:value)! } }
}
@MainActor
final class FeedRunwayDriverTests: XCTestCase {
    private enum Failure: Error, Equatable { case preparation }
    private struct Fixture {
        let database: RuntimeDatabase
        let plan: FeedPlan
        let policy: ResolvedSelectionPolicy
        let edition: FeedEditionID
        let cards: [PublicationCardID]
        let source: SourceID
        let target: AcquisitionTarget
        let session: FeedSession
        let runway: RunwayController
        let driver: FeedRunwayDriver
        let http: DriverHTTPFixture
        let otherHTTP: DriverHTTPFixture
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
        paused:Bool = false,error:URLError? = nil,context:FeedContext? = nil,driverContext:FeedContext? = nil,
        differentRevision:Bool = false,prepareFailure:Bool = false,cancelPrepare:Bool = false) throws -> Fixture {
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
        let target = try AcquisitionTargetAuthority(database:db).register(id:AcquisitionTargetID(),connectorKind:.syndication)
        if seedLocal {
            let observation = AcquisitionObservation(objectIdentity:.init(connectorKind:.syndication,namespace:"seed",value:"local",role:.object),versionIdentity:nil,
                precedence:.makeCurrent,availability:.available,headline:"local",summary:nil,bodyText:nil,authoredAt:nil,modifiedAt:nil,observedAt:Date(timeIntervalSince1970:4),
                language:nil,primaryLink:nil,searchProjection:nil,providerID:nil,memberships:[.init(sourceID:source,kind:.direct)],mediaCandidates:[])!
            _ = try AdmissionPolicy(database:db).admit(.init(targetID:target.id,targetGeneration:1,expectedCheckpointRevision:0,observations:[observation],nextCheckpoint:nil)!)
        }
        let http = DriverHTTPFixture(paused:paused,error:error)
        addTeardownBlock { http.remove() }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [DriverURLProtocol.self]
        let transport = URLSession(configuration:config); addTeardownBlock { transport.invalidateAndCancel() }
        let binding = SourceBinding(id:SourceBindingID(),sourceID:source,externalPrincipal:.init(connectorKind:.syndication,namespace:"p",value:"p",role:.principal),aliases:[],generation:1,state:.enabled)!
        let otherHTTP = DriverHTTPFixture(paused:false,error:nil)
        addTeardownBlock { otherHTTP.remove() }
        let otherTarget = try AcquisitionTargetAuthority(database:db).register(id:AcquisitionTargetID(),connectorKind:.syndication)
        let otherBinding = SourceBinding(id:SourceBindingID(),sourceID:SourceID(),externalPrincipal:.init(connectorKind:.syndication,namespace:"p",value:"other",role:.principal),aliases:[],generation:1,state:.enabled)!
        let regs = registrations ? [SyndicationTargetRegistration(targetID:target.id,targetGeneration:1,endpoint:http.url,bindings:[binding])!,
            SyndicationTargetRegistration(targetID:otherTarget.id,targetGeneration:1,endpoint:otherHTTP.url,bindings:[otherBinding])!] : []
        let acquisition = try SyndicationAcquisitionSnapshot(database:db,registrations:regs,session:transport,redirectCapacity:0,now:{ Date(timeIntervalSince1970:5) })
        let session = FeedSession(publicationHistory:.init(database:db)),clock = DriverClock()
        let runway = RunwayController(configuration:.init(policyInputs:.init(safetyFactor:1,releaseMarginSeconds:0)!,consumptionSampleLimit:4,replenishmentSampleLimit:4)!)
        let driverPlan = differentRevision ? plan(p.context) : driverContext.map { plan($0) } ?? p
        let driver = try FeedRunwayDriver(session:session,runway:runway,plan:driverPlan,policy:policy(driverPlan),acquisition:acquisition,
            monotonicNow:{ clock.next() },makeSegmentIdentity:{ .init(segmentID:FeedSegmentID(),segmentSeed:2,segmentCreatedAt:Date(timeIntervalSince1970:6))! },prepare:{ selection in
                if cancelPrepare { throw CancellationError() }; if prepareFailure { throw Failure.preparation }; return Self.prepared(selection)
            })
        return .init(database:db,plan:p,policy:pol,edition:edition,cards:prepared.cardIDs,source:source,target:target,session:session,runway:runway,driver:driver,http:http,otherHTTP:otherHTTP)
    }
    private func restore(_ f:Fixture,forward:Int = 4,resources:FeedRunwayDriverResources? = nil) async throws -> FeedPresentationSnapshot {
        let result = try await f.driver.restoreAndActivate(backwardCapacity:1,forwardCapacity:forward,resources:resources ?? self.resources())
        return try XCTUnwrap(result)
    }
    private func tail(_ f:Fixture,_ p:FeedPresentationSnapshot,resources:FeedRunwayDriverResources? = nil) async throws -> FeedPresentationSnapshot? {
        try await f.driver.submitViewport(.init(anchor:p.window.anchor),activity:.explicitTailApproach,resources:resources ?? self.resources())
    }
    func test01SemanticTailFullProductionLoop() async throws {
        let f = try fixture(),store = PublicationStore(database:f.database),before = try store.edition(id:f.edition)
        let p = try await restore(f); let installed = await f.session.currentPresentation()
        XCTAssertEqual(installed,p); XCTAssertEqual(f.http.calls,0)
        let result = try await tail(f,p)
        XCTAssertGreaterThan(f.http.calls,0); XCTAssertEqual(try store.edition(id:f.edition),before)
        XCTAssertEqual(try store.segments(editionID:f.edition).count,2)
        let candidates = try ContentStore(database:f.database).candidateWindow(sourceID:f.source,after:nil,examinedCapacity:8).records
        XCTAssertEqual(candidates.count,1); XCTAssertEqual(result?.editionID,f.edition)
        XCTAssertEqual(result?.window.anchor,p.window.anchor); XCTAssertEqual(result?.window.items.count,2)
        let current = await f.session.currentPresentation(); XCTAssertEqual(current,result)
    }
    func test02LocalPresentationSurvivesSuspendedTailHTTP() async throws {
        let f = try fixture(paused:true),p = try await restore(f); XCTAssertEqual(f.http.calls,0)
        let driver = f.driver,resources = resources(),anchor = p.window.anchor
        let task = Task { try await driver.submitViewport(.init(anchor:anchor),activity:.explicitTailApproach,resources:resources) }
        var started = f.http.started.makeAsyncIterator(); _ = await started.next()
        let pending = await f.session.currentPresentation(); XCTAssertEqual(pending,p)
        f.http.release(); let result = try await task.value; XCTAssertEqual(result?.window.items.count,2)
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
        // Local content is already committed and projected before remote response is available.
        let local = await f.session.currentPresentation()
        XCTAssertEqual(local?.window.items.count,2)
        XCTAssertEqual(try PublicationStore(database:f.database).segments(editionID:f.edition).count,2)
        f.http.release(); let result = try await task.value
        XCTAssertEqual(result?.window.items.count,3)
    }
    func test05HistoryMeasurementIgnoresTinyWindowTail() async throws {
        let f = try fixture(historyCount:50,seedLocal:true,registrations:false),p = try await restore(f,forward:0)
        _ = try await tail(f,p) // real local publication establishes replenishment latency; no external target is eligible
        _ = try await f.session.restoreLocalPresentation(backwardCapacity:1,forwardCapacity:1)
        _ = try await f.driver.submitViewport(.init(anchor:.init(cardID:f.cards[1],placement:.top)),activity:.forward,resources:resources())
        // A real committed forward advance establishes nonzero measured consumption.
        let thin = try await f.session.restoreLocalPresentation(backwardCapacity:0,forwardCapacity:0)
        let current = try XCTUnwrap(thin)
        XCTAssertEqual(current.window.items.last?.id,current.window.anchor.cardID)
        _ = try await tail(f,current)
        let snap = await f.runway.snapshot()
        XCTAssertEqual(snap.readyAhead?.amount,.atLeast(8)); XCTAssertEqual(snap.lastCoverage,.healthy); XCTAssertEqual(f.http.calls,0)
    }
    func test06LocalPublicationRefreshesSession() async throws {
        let f = try fixture(seedLocal:true,registrations:false),p = try await restore(f)
        _ = try await tail(f,p); let current = await f.session.currentPresentation()
        XCTAssertEqual(current?.window.items.count,2); XCTAssertEqual(current?.window.anchor,p.window.anchor)
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
        XCTAssertGreaterThan(f.http.calls,0); XCTAssertEqual(result?.window.items.count,2)
    }
    func test09NoEligibleQuiesces() async throws {
        let f = try fixture(registrations:false),p = try await restore(f); _ = try await tail(f,p)
        let snap = await f.runway.snapshot(); XCTAssertNil(snap.outstandingAcquisition); XCTAssertEqual(f.http.calls,0)
    }
    func test10AcquisitionErrorPropagatesOnce() async throws {
        let f = try fixture(error:URLError(.notConnectedToInternet)),p = try await restore(f)
        do { _ = try await tail(f,p); XCTFail("Expected HTTP failure") } catch { XCTAssertEqual((error as? URLError)?.code,.notConnectedToInternet) }
        XCTAssertEqual(f.http.calls,1)
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
    func test14SearchErrorPreservesPreAckIntent() async throws {
        let f = try fixture(context:.init(request:.search(SearchContext(query:"q")!))),p = try await restore(f)
        // Seed the controller's documented exhausted-local fact to exercise the Acquisition boundary only.
        let scope = await f.session.currentRunwayScope()
        await f.runway.activate(try XCTUnwrap(scope))
        let observation = RunwayObservation(editionID:f.edition,anchorCardID:p.window.anchor.cardID,sampledAt:.init(seconds:1)!,activity:.explicitTailApproach)
        try await f.runway.submitObservation(observation)
        try await f.runway.acceptMeasurement(.init(observation:observation,readyAhead:PublicationHistory(database:f.database).readyAhead(editionID:f.edition,anchorCardID:p.window.anchor.cardID,probeBound:8),advanceFromHighWater:nil))
        guard case .runLocalSlice(let intent) = try await f.runway.reconsider(resources:resources().runway,at:.init(seconds:2)!) else { return XCTFail("Expected local intent") }
        try await f.runway.completeLocalSlice(intent,outcome:.advancedWithoutPublication(.init(examinedCount:0,nextCursor:nil,exhausted:true)),at:.init(seconds:3)!)
        do { _ = try await f.driver.drive(resources:resources()); XCTFail("Expected unavailable search") }
        catch { XCTAssertEqual(error as? SyndicationAcquisitionSnapshotError,.searchContextUnavailable) }
        let snap = await f.runway.snapshot(); XCTAssertNotNil(snap.outstandingAcquisition); XCTAssertEqual(f.http.calls,0)
    }
    func test15SessionContextMismatch() async throws {
        let f = try fixture(driverContext:.init(request:.source(SourceID())))
        do { _ = try await restore(f); XCTFail("Expected context fence") }
        catch { guard case .sessionContextMismatch(_,let actual) = error as? FeedRunwayDriverError else { return XCTFail("Wrong error") }; XCTAssertEqual(actual,f.plan.context.key) }
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
        XCTAssertThrowsError(try FeedRunwayDriver(session:f.session,runway:f.runway,plan:f.plan,policy:policy(plan(.init(request:.source(SourceID())))),acquisition:acquisition,
            monotonicNow:{ .init(seconds:0)! },makeSegmentIdentity:{ .init(segmentID:FeedSegmentID(),segmentSeed:0,segmentCreatedAt:Date(timeIntervalSince1970:0))! },prepare:Self.prepared)) {
            XCTAssertEqual($0 as? FeedRunwayDriverError,.policyContextMismatch)
        }
    }
    func test18UnknownViewportDoesNotEnterRunway() async throws {
        let f = try fixture(),p = try await restore(f),before = await f.runway.snapshot()
        let result = try await f.driver.submitViewport(.init(anchor:.init(cardID:PublicationCardID(),placement:.top)),activity:.explicitTailApproach,resources:resources())
        let after = await f.runway.snapshot(); XCTAssertEqual(after,before); XCTAssertEqual(result,p); XCTAssertEqual(f.http.calls,0)
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
    func test22DeactivatePreservesPresentation() async throws {
        let f = try fixture(),p = try await restore(f); await f.driver.deactivate()
        let snap = await f.runway.snapshot(),current = await f.session.currentPresentation(); XCTAssertNil(snap.scope); XCTAssertEqual(current,p)
    }
    func test23SameEditionOnly() async throws {
        let f = try fixture(),before = try PublicationStore(database:f.database).edition(id:f.edition),p = try await restore(f)
        _ = try await tail(f,p); XCTAssertEqual(try PublicationStore(database:f.database).edition(id:f.edition),before)
        XCTAssertEqual(try PublicationStore(database:f.database).segments(editionID:f.edition).count,2)
    }
    func test24SingleTailOpportunityReachesQuiescence() async throws {
        let f = try fixture(),p = try await restore(f); _ = try await tail(f,p)
        let snap = await f.runway.snapshot(); XCTAssertFalse(snap.localSliceInFlight); XCTAssertNil(snap.outstandingAcquisition)
        XCTAssertEqual(try PublicationStore(database:f.database).segments(editionID:f.edition).count,2)
    }
    func test25SegmentIdentityRequiresFiniteCallerTime() {
        let id = FeedSegmentID(),date = Date(timeIntervalSinceReferenceDate:123.125)
        let value = FeedRunwaySegmentIdentity(segmentID:id,segmentSeed:UInt64.max,segmentCreatedAt:date)
        XCTAssertEqual(value?.segmentID,id); XCTAssertEqual(value?.segmentSeed,UInt64.max); XCTAssertEqual(value?.segmentCreatedAt,date)
        for invalid in [Double.nan,.infinity,-.infinity] {
            XCTAssertNil(FeedRunwaySegmentIdentity(segmentID:id,segmentSeed:0,segmentCreatedAt:Date(timeIntervalSinceReferenceDate:invalid)))
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
    private var released = false
    init(paused:Bool,error:URLError?) {
        self.paused = paused; self.error = error; (started,signal) = AsyncStream.makeStream()
        Self.registryLock.withLock { Self.registry[url.host!] = self }
    }
    static func find(_ url:URL?) -> DriverHTTPFixture? { registryLock.withLock { registry[url?.host ?? ""] } }
    func remove() { _ = Self.registryLock.withLock { Self.registry.removeValue(forKey:url.host!) } }
    var calls:Int { lock.withLock { count } }
    func start(_ loader:DriverURLProtocol) {
        let wait = lock.withLock { count += 1; if paused && !released { pending = loader; return true }; return false }
        signal.yield(()); if !wait { respond(loader) }
    }
    func release() { let loader = lock.withLock { released = true; let value = pending; pending = nil; return value }; if let loader { respond(loader) } }
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
    override func stopLoading() {}
}
