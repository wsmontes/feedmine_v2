import Foundation
import Observation
import OSLog
import FeedMineDomain
import FeedMinePersistence
import FeedMineAcquisition
import FeedMineEditorial
import FeedMinePublication
import FeedMineRuntime
import FeedMineUI
import FeedMineComposition

@MainActor
@Observable
final class AppComposition {
    private(set) var association: FeedAssociation?
    private(set) var startupFailure: String?
    private var replacingSession = false
    private let directory: URL
    private let feeds: [TrustedFeed]
    private let transportConfiguration: URLSessionConfiguration

    init(directory: URL? = nil, feeds: [TrustedFeed] = TrustedFeed.development,
        transportConfiguration: URLSessionConfiguration? = nil) {
        self.directory = directory ?? RuntimeDatabaseLocation.applicationSupport(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]).directory
        self.feeds = feeds
        let config = transportConfiguration ?? .ephemeral
        config.timeoutIntervalForRequest = 20
        #if DEBUG
        // Real transport fault configuration for a network-blocked relaunch; no mock connector.
        if ProcessInfo.processInfo.environment["FEEDMINE_BLOCK_RSS_NETWORK"] == "1" {
            DevelopmentNetworkBlock.apply(to: config)
        }
        #endif
        self.transportConfiguration = config
    }

    func launch() async {
        guard !replacingSession, association == nil, startupFailure == nil else { return }
        let current: FeedAssociation
        do {
            current = try FeedAssociation(directory: directory, feeds: feeds, configuration: transportConfiguration)
        } catch {
            startupFailure = "Não foi possível abrir o feed local: \(String(describing: error))"
            return
        }
        association = current
        do {
            try await current.launch()
        } catch {
            // An old launch may settle after explicit replacement. Its error belongs to that association.
            guard association === current, current.active else { return }
            startupFailure = "Não foi possível abrir o feed local: \(String(describing: error))"
            current.reportFailure(error)
        }
    }

    func foreground() async {
        guard let association else { return }
        await association.foreground()
    }

    func background() async {
        guard let association else { return }
        await association.background()
    }

    /// Explicit session replacement; no replacement occurs during normal feed opportunities.
    func replaceSession() async throws {
        guard !replacingSession else { return }
        replacingSession = true
        defer { replacingSession = false }
        let retired = association
        association = nil
        if let retired { await retired.close() }
        let next = try FeedAssociation(directory: directory, feeds: feeds, configuration: transportConfiguration)
        association = next
        startupFailure = nil
        try await next.launch()
    }
}

@MainActor
@Observable
final class FeedAssociation {
    let database: RuntimeDatabase
    let session: FeedSession
    let driver: FeedRunwayDriver
    let coordinator: AcquisitionCoordinator
    let acquisition: SyndicationAcquisitionSnapshot
    private let cold: ColdFeedBootstrap
    private let transport: URLSession
    private(set) var active = true
    private var launching = false
    @ObservationIgnored
    lazy var store = FeedScreenStore { [weak self] observation, activity in
        guard let self else { return }
        Task { await self.viewport(observation, activity: activity) }
    }

    #if DEBUG
    private(set) var viewportReceived = 0
    private(set) var viewportCompleted = 0
    private(set) var backwardCompleted = 0
    #endif

    static var resources: FeedRunwayDriverResources {
        .init(runway: .init(localWorkAllowed: true, examinedCandidateCapacity: 32,
            readyProbeBound: 32, readyProbeCeiling: 256, forwardAdvanceProbeBound: 256)!,
            acquisition: .init(targetWorkCapacity: 2, batchCapacityPerNewExecution: 1,
                observationCapacityPerBatch: 32, byteCapacityPerBatch: 1_000_000)!)
    }

    init(directory: URL, feeds: [TrustedFeed], configuration: URLSessionConfiguration) throws {
        let db = try RuntimeDatabase(location: .init(directory: directory))
        database = db
        let history = PublicationHistory(database: db)
        let context = FeedContext(request: .main)
        let saved = try history.restore(backwardCapacity: 8, forwardCapacity: 16)
        let v = PolicyVersion(rawValue: 1)
        let revision = saved?.edition.editorialRevision ?? EditorialRevision(
            id: .init(rawValue: UUID(uuidString: "70000000-0000-4000-8000-000000000001")!),
            contextKey: context.key, catalogGeneration: .init(rawValue: 1), userSelectionVersion: v,
            eligibilityPolicyVersion: v, scoringPolicyVersion: v, sequencingPolicyVersion: v,
            exposurePolicyVersion: v, selectionSchemaVersion: .init(rawValue: 1))
        guard let plan = FeedPlan(context: context, revision: revision) else {
            throw FeedRunwayDriverError.policyContextMismatch
        }
        let policy = ResolvedSelectionPolicy(contextKey: revision.contextKey,
            userSelectionVersion: revision.userSelectionVersion, eligibilityPolicyVersion: revision.eligibilityPolicyVersion,
            scoringPolicyVersion: revision.scoringPolicyVersion, sequencingPolicyVersion: revision.sequencingPolicyVersion,
            exposurePolicyVersion: revision.exposurePolicyVersion, selectionSchemaVersion: revision.selectionSchemaVersion,
            eligibility: .structuralOnly, scoring: .equal, sequencing: .recencyDescending, exposure: .excludePublishedRevisions)
        let authority = AcquisitionTargetAuthority(database: db)
        let registrations = try feeds.map { feed in
            let existing = try authority.target(id: feed.targetID)
            let target = try existing ?? authority.register(id: feed.targetID,
                connectorKind: .syndication, authorizedSources: [feed.sourceID])
            let binding = SourceBinding(id: feed.bindingID, sourceID: feed.sourceID,
                externalPrincipal: .init(connectorKind: .syndication, namespace: "feedmine-development-rss",
                    value: feed.principal, role: .principal), aliases: [], generation: 1, state: .enabled)!
            return SyndicationTargetRegistration(targetID: target.id, targetGeneration: target.generation,
                endpoint: feed.endpoint, bindings: [binding])!
        }
        let transport = URLSession(configuration: configuration)
        self.transport = transport
        let acquisition = try SyndicationAcquisitionSnapshot(database: db, registrations: registrations,
            session: transport, redirectCapacity: 4)
        self.acquisition = acquisition
        let coordinator = acquisition.makeCoordinator()
        self.coordinator = coordinator
        let session = FeedSession(publicationHistory: history)
        self.session = session
        let runway = RunwayController(configuration: .init(policyInputs: .init(safetyFactor: 1.2,
            releaseMarginSeconds: 2)!, consumptionSampleLimit: 8, replenishmentSampleLimit: 8)!)
        driver = try FeedRunwayDriver(session: session, runway: runway, plan: plan, policy: policy,
            acquisition: acquisition, coordinator: coordinator,
            monotonicNow: { .init(seconds: ProcessInfo.processInfo.systemUptime)! },
            makeSegmentIdentity: { .init(segmentID: FeedSegmentID(), segmentSeed: 1, segmentCreatedAt: Date())! },
            prepare: { Self.prepare($0) })
        cold = try ColdFeedBootstrap(session: session, plan: plan, policy: policy,
            acquisition: acquisition, coordinator: coordinator, prepare: { Self.prepare($0) })
    }

    nonisolated private static func prepare(_ selection: SelectionResult) -> LocalPreparedPublication {
        .init(inputs: selection.orderedCandidates.map {
            .init(origin: .init(originRecordID: $0.originRecordID, originRevisionID: $0.originRevisionID,
                sourceID: nil, providerID: $0.providerID, sourceDisplayName: nil, providerDisplayName: nil),
                contentEntityID: nil, contentClusterID: nil, primaryAction: nil, presentation: .textOnly)
        }, cardIDs: selection.orderedCandidates.map { _ in PublicationCardID() })
    }

    func install(_ received: FeedPresentationState) throws {
        guard active else { throw FeedPresentationStateError.projectionSequenceMismatch }
        try store.install(received)
        if let snapshot = store.state.presentation {
            Self.log("installed cards=\(snapshot.window.items.count) edition=\(snapshot.editionID.rawValue) sequence=\(snapshot.provenance.sequenceID) order=\(snapshot.provenance.position)")
        }
    }

    func launch() async throws {
        guard active, !launching else { return }
        launching = true
        defer { launching = false }
        let restored = try await session.restoreLocalPresentation(backwardCapacity: 8, forwardCapacity: 16)
        if let restored {
            try install(FeedPresentationHandoff.receive(snapshot: restored, into: store.state))
            Self.log("local restore before HTTP")
        } else {
            try install(store.state.reporting(.pending))
            Self.log("cold bootstrap started")
            let now = Date()
            let outcome = try await cold.run(identity: .init(editionID: FeedEditionID(), publicationSchemaVersion: .init(rawValue: 1),
                selectionSeed: 1, editionCreatedAt: now, segmentID: FeedSegmentID(), segmentSeed: 1,
                segmentCreatedAt: now, anchorPlacement: .top, checkpointedAt: now)!,
                resources: .init(localExaminedCapacity: 32, acquisition: Self.resources.acquisition)!,
                backwardCapacity: 8, forwardCapacity: 16)
            try install(FeedPresentationHandoff.receive(coldOutcome: outcome, into: store.state))
            Self.log("cold bootstrap settled")
        }
        let snapshot = try await driver.activateCurrentPresentation(resources: Self.resources)
        try install(FeedPresentationHandoff.receive(snapshot: snapshot, into: store.state))
    }

    func viewport(_ observation: ViewportObservation, activity: RunwayActivity) async {
        do {
            guard active else { throw FeedPresentationStateError.projectionSequenceMismatch }
            #if DEBUG
            viewportReceived += 1
            #endif
            Self.log("viewport forwarded activity=\(activity) anchor=\(observation.anchor.cardID)")
            Self.log("viewport opportunity sent to driver")
            let received = try await FeedPresentationHandoff.submitViewport(observation, activity: activity,
                resources: Self.resources, driver: driver, into: store.state)
            try install(received)
            #if DEBUG
            viewportCompleted += 1
            if activity == .backward { backwardCompleted += 1 }
            #endif
            Self.log("Runway opportunity completed activity=\(activity)")
        } catch { reportFailure(error) }
    }

    func foreground() async {
        do {
            guard active, !launching else { return }
            if await session.currentPresentation() == nil {
                try await launch() // A new explicit foreground opportunity, without replacing the session/store.
                return
            }
            let snapshot = try await driver.drive(resources: Self.resources)
            try install(FeedPresentationHandoff.receive(snapshot: snapshot, into: store.state))
        } catch { reportFailure(error) }
    }

    func background() async {
        guard active else { return }
        do {
            _ = try await session.checkpointCurrentPosition(at: Date())
            await driver.markConsumptionInactive()
            Self.log("lifecycle checkpoint")
        } catch { reportFailure(error) }
    }

    func close() async {
        active = false
        await driver.deactivate()
        transport.invalidateAndCancel()
    }

    func reportFailure(_ error: any Error) {
        if let rejection = error as? FeedPresentationStateError {
            Self.log("projection rejected \(rejection)")
            return // typed structural rejection is logged; never install an alternative result/work.
        }
        guard active else { return }
        Self.log("execution failure \(String(describing: error))")
        do { try install(store.state.reporting(.failed(message: "Falha ao atualizar o feed"))) }
        catch { Self.log("failure reporting rejected \(String(describing: error))") }
    }

    nonisolated private static func log(_ value: String) {
        #if DEBUG
        Logger(subsystem: "com.feedmine.development", category: "composition").info("\(value, privacy: .public)")
        #endif
    }
}
