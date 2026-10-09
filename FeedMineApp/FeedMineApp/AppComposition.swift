import Foundation
import Observation
import OSLog
import Network
import FeedMineMedia
#if canImport(UIKit)
import UIKit
#endif
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

    init(directory: URL? = nil, feeds: [TrustedFeed] = TrustedFeed.catalogOrDevelopment(limit: 64),
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
    let media: MediaPrefetcher
    @ObservationIgnored private let tidy: MediaTidy
    @ObservationIgnored private let tidyWaitSeconds: Double
    let acquisition: SyndicationAcquisitionSnapshot
    private let cold: ColdFeedBootstrap
    @ObservationIgnored private let relay: EvidenceRelay
    @ObservationIgnored private var preparation: PreparationProgress?
    @ObservationIgnored private let targetNames: [AcquisitionTargetID: String]
    @ObservationIgnored private let admittedHeadlines: @Sendable () -> [String]
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
        // Sequencing v2 = PD-4 source alternation; exposure v2 = PD-1 edited articles reappear.
        // A behavior change is a new EditorialRevision; a restored Edition keeps its own behavior.
        let alternating = PolicyVersion(rawValue: 2)
        let revision = saved?.edition.editorialRevision ?? EditorialRevision(
            id: .init(rawValue: UUID(uuidString: "70000000-0000-4000-8000-000000000003")!),
            contextKey: context.key, catalogGeneration: .init(rawValue: 1), userSelectionVersion: v,
            eligibilityPolicyVersion: v, scoringPolicyVersion: v, sequencingPolicyVersion: alternating,
            exposurePolicyVersion: alternating, selectionSchemaVersion: .init(rawValue: 1))
        guard let plan = FeedPlan(context: context, revision: revision) else {
            throw FeedRunwayDriverError.policyContextMismatch
        }
        let sequencing: ResolvedSelectionPolicy.SequencingBehavior =
            revision.sequencingPolicyVersion >= alternating ? .recencyAlternatingSources : .recencyDescending
        let policy = ResolvedSelectionPolicy(contextKey: revision.contextKey,
            userSelectionVersion: revision.userSelectionVersion, eligibilityPolicyVersion: revision.eligibilityPolicyVersion,
            scoringPolicyVersion: revision.scoringPolicyVersion, sequencingPolicyVersion: revision.sequencingPolicyVersion,
            exposurePolicyVersion: revision.exposurePolicyVersion, selectionSchemaVersion: revision.selectionSchemaVersion,
            eligibility: .structuralOnly, scoring: .equal, sequencing: sequencing,
            exposure: revision.exposurePolicyVersion >= alternating ? .excludePublishedMaterial : .excludePublishedRevisions)
        let authority = AcquisitionTargetAuthority(database: db)
        let registrations = try feeds.map { feed in
            let existing = try authority.target(id: feed.targetID)
            let target = try existing ?? authority.register(id: feed.targetID,
                connectorKind: .syndication, authorizedSources: [feed.sourceID])
            let binding = SourceBinding(id: feed.bindingID, sourceID: feed.sourceID,
                externalPrincipal: .init(connectorKind: .syndication,
                    namespace: feed.principal.hasPrefix("http") ? LegacyCatalogImport.principalNamespace : "feedmine-development-rss",
                    value: feed.principal, role: .principal), aliases: [], generation: 1, state: .enabled)!
            return SyndicationTargetRegistration(targetID: target.id, targetGeneration: target.generation,
                endpoint: feed.endpoint, bindings: [binding])!
        }
        let transport = URLSession(configuration: configuration)
        self.transport = transport
        let acquisition = try SyndicationAcquisitionSnapshot(database: db, registrations: registrations,
            session: transport, redirectCapacity: 4)
        self.acquisition = acquisition
        // H2: a feed that keeps failing cools down for a doubling window that starts at what one
        // failed attempt may already cost (the request timeout) and is capped by the resource
        // timeout. Targets run through a sliding window sized by this device's cores.
        let backoff = AcquisitionBackoffPolicy(baseSeconds: configuration.timeoutIntervalForRequest,
            ceilingSeconds: max(configuration.timeoutIntervalForRequest, configuration.timeoutIntervalForResource))
        let coordinator = acquisition.makeCoordinator(backoff: backoff,
            concurrentTargetLimit: max(2, ProcessInfo.processInfo.activeProcessorCount))
        self.coordinator = coordinator
        // PD-5/PD-6 media pipeline: one download owner, device-measured policy, slot-sized decoding.
        let assetDirectory = directory.appendingPathComponent("Media", isDirectory: true)
        let device = DeviceMediaConditions.current()
        let readiness = MediaReadiness()
        let fetcher = MediaHTTPFetcher(session: transport)
        let media = MediaPrefetcher(database: db, assetDirectory: assetDirectory, readiness: readiness,
            concurrentDownloadLimit: max(2, ProcessInfo.processInfo.activeProcessorCount / 2),
            fetch: { try await fetcher.fetch($0, byteCeiling: $1) },
            conditions: { rate in DeviceMediaConditions.policy(device: device, measuredBytesPerSecond: rate,
                assetDirectory: assetDirectory) })
        self.media = media
        tidy = MediaTidy(assetDirectory: assetDirectory, prefetcher: media, freeStorageBytes: {
            try? FileManager.default.temporaryDirectory
                .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
        })
        tidyWaitSeconds = configuration.timeoutIntervalForRequest / 4
        let session = FeedSession(publicationHistory: history, imageDecoder: PresentationImageDecoder(
            assetDirectory: assetDirectory, heroMaxPixel: device.heroPixelWidth, thumbnailMaxPixel: device.thumbnailPixelWidth))
        self.session = session
        let names = Dictionary(uniqueKeysWithValues: feeds.map { ($0.sourceID, $0.displayName) })
        let prepare: @Sendable (SelectionResult) -> LocalPreparedPublication = { Self.prepare($0, readiness: readiness, names: names) }
        // Bounded wait for media of the supply head: what the runway can afford (one request timeout).
        let mediaWait = configuration.timeoutIntervalForRequest / 4
        let headProvider = CandidateProvider(contentStore: ContentStore(database: db))
        // Runway: the driver supplies the next editorial candidates for the active context (F05).
        let prepareRunwayMedia: @Sendable ([OriginRevisionID]) async -> Void = { revisions in
            await media.prefetch(revisions, deadline: ProcessInfo.processInfo.systemUptime + mediaWait)
        }
        // First Edition: nothing is published yet, so the context head is exactly what the slice selects.
        let prepareMedia: @Sendable () async -> Void = {
            let head = (try? headProvider.candidates(for: plan, after: nil, examinedCapacity: 32))?.candidates.map(\.originRevisionID) ?? []
            await media.prefetch(head, deadline: ProcessInfo.processInfo.systemUptime + mediaWait)
        }
        let runway = RunwayController(configuration: .init(policyInputs: .init(safetyFactor: 1.2,
            releaseMarginSeconds: 2)!, consumptionSampleLimit: 8, replenishmentSampleLimit: 8,
            // M7: first retry after a failed local slice one second later, doubling per failure.
            localRetryBaseSeconds: 1)!)
        driver = try FeedRunwayDriver(session: session, runway: runway, plan: plan, policy: policy,
            acquisition: acquisition, coordinator: coordinator,
            monotonicNow: { .init(seconds: ProcessInfo.processInfo.systemUptime)! },
            makeSegmentIdentity: { .init(segmentID: FeedSegmentID(), segmentSeed: 1, segmentCreatedAt: Date())! },
            prepare: prepare, prepareMedia: prepareRunwayMedia)
        let relay = EvidenceRelay()
        self.relay = relay
        cold = try ColdFeedBootstrap(session: session, plan: plan, policy: policy,
            acquisition: acquisition, coordinator: coordinator, prepare: prepare, prepareMedia: prepareMedia,
            evidence: { await relay.deliver($0) })
        targetNames = Dictionary(uniqueKeysWithValues: feeds.map { ($0.targetID, $0.displayName) })
        let provider = CandidateProvider(contentStore: ContentStore(database: db))
        admittedHeadlines = { (try? provider.candidates(for: plan, after: nil, examinedCapacity: 12))?.candidates.compactMap(\.headline) ?? [] }
    }

    /// PD-5: each card is drawn with a prepared image or designed text-only — never "missing" one.
    /// Attribution (source id/name) is frozen into the card, which also feeds PD-4 adjacency.
    nonisolated private static func prepare(_ selection: SelectionResult, readiness: MediaReadiness,
        names: [SourceID: String]) -> LocalPreparedPublication {
        .init(inputs: selection.orderedCandidates.map { candidate in
            let source = candidate.sourceIDs.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }.first { names[$0] != nil }
                ?? candidate.sourceIDs.first
            return .init(origin: .init(originRecordID: candidate.originRecordID, originRevisionID: candidate.originRevisionID,
                sourceID: source, providerID: candidate.providerID, sourceDisplayName: source.flatMap { names[$0] },
                providerDisplayName: nil),
                contentEntityID: nil, contentClusterID: nil, primaryAction: nil,
                presentation: readiness.presentation(for: candidate.originRevisionID))
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
            // PD-3: show real evidence of content arriving while the first Edition is prepared.
            let started = PreparationProgress(startedAt: ProcessInfo.processInfo.systemUptime)
            preparation = started
            try install(store.state.reporting(.preparing(started)))
            relay.receive = { [weak self] in self?.receive($0) }
            defer { relay.receive = nil; preparation = nil }
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
        await scheduleLocalRetryIfNeeded()
    }

    /// Review M7: a stationary reader produces no new observation, so a failed local slice would
    /// otherwise never be retried. One opportunity is scheduled at the controller's eligibility time.
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    /// Review F09: only a visible association may drive the feed. Background and close revoke it.
    @ObservationIgnored private var visible = true
    private func scheduleLocalRetryIfNeeded() async {
        retryTask?.cancel()
        retryTask = nil
        guard active, visible, let eligible = await driver.localRetryEligibleAt() else { return }
        let wait = max(0, eligible.seconds - ProcessInfo.processInfo.systemUptime)
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.scheduledOpportunity()
        }
    }

    /// A timed opportunity runs only if the app is still visible when it fires.
    private func scheduledOpportunity() async {
        guard active, visible, !launching else { return }
        await foreground()
    }

    /// PD-3: reduce pipeline evidence into the preparation screen value.
    private func receive(_ evidence: ColdFeedEvidence) {
        guard active, var progress = preparation else { return }
        let now = ProcessInfo.processInfo.systemUptime
        switch evidence {
        case .contacting(let targets):
            for target in targets {
                progress = progress.applying(.contacting(id: target.rawValue.uuidString,
                    name: targetNames[target] ?? "Fonte"), at: now)
            }
        case .settled(let target, let stop, let changed):
            let reachable: Bool
            if case .operationalFailure = stop { reachable = false } else { reachable = true }
            progress = progress.applying(.settled(id: target.rawValue.uuidString, contributed: changed, reachable: reachable), at: now)
            if changed { progress = progress.applying(.admitted(headlines: admittedHeadlines()), at: now) }
        case .preparingMedia:
            break
        }
        preparation = progress
        do { try install(store.state.reporting(.preparing(progress))) } catch { Self.log("preparation update rejected") }
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
            await scheduleLocalRetryIfNeeded()
            #if DEBUG
            viewportCompleted += 1
            if activity == .backward { backwardCompleted += 1 }
            #endif
            Self.log("Runway opportunity completed activity=\(activity)")
        } catch { reportFailure(error); await scheduleLocalRetryIfNeeded() }
    }

    func foreground() async {
        visible = true
        do {
            guard active, !launching else { return }
            if await session.currentPresentation() == nil {
                try await launch() // A new explicit foreground opportunity, without replacing the session/store.
                return
            }
            let snapshot = try await driver.drive(resources: Self.resources)
            try install(FeedPresentationHandoff.receive(snapshot: snapshot, into: store.state))
            await scheduleLocalRetryIfNeeded()
        } catch { reportFailure(error); await scheduleLocalRetryIfNeeded() }
    }

    func background() async {
        visible = false
        retryTask?.cancel()
        retryTask = nil
        guard active else { return }
        do {
            _ = try await session.checkpointCurrentPosition(at: Date())
            await driver.markConsumptionInactive()
            Self.log("lifecycle checkpoint")
            // PD-5: the screen is not visible now, so the house can be tidied: complete media for
            // the next cards and bring local media under the device-derived budget. Seen and visible
            // cards are never changed.
            let visible = Set(store.state.presentation?.window.items.compactMap { $0.image?.key } ?? [])
            let report = await tidy.run(visibleKeys: visible, supplyHeadLimit: 32,
                deadline: ProcessInfo.processInfo.systemUptime + tidyWaitSeconds)
            Self.log("tidy evicted=\(report.evictedAssets) reclaimed=\(report.reclaimedBytes) budget=\(report.budgetBytes)")
        } catch { reportFailure(error) }
    }

    func close() async {
        active = false
        visible = false
        retryTask?.cancel()
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

/// PD-6: media conditions measured on this device. Slot widths follow the feed layout
/// (FeedCardView: full-width hero, 88 pt thumbnail) on the actual screen; network path, Low Power
/// Mode, thermal state and free space are sampled whenever a policy is requested.
struct DeviceMediaConditions: Sendable {
    let heroPointWidth: Double
    let thumbnailPointWidth: Double
    let scale: Double
    var heroPixelWidth: Int { Int((heroPointWidth * scale).rounded(.up)) }
    var thumbnailPixelWidth: Int { Int((thumbnailPointWidth * scale).rounded(.up)) }

    @MainActor static func currentOnMain() -> DeviceMediaConditions {
        #if canImport(UIKit)
        let screen = UIScreen.main
        // Feed cards are inset by 16 pt outer padding and 16 pt card padding on each side.
        return .init(heroPointWidth: max(1, screen.bounds.width - 64), thumbnailPointWidth: 88, scale: screen.scale)
        #else
        return .init(heroPointWidth: 600, thumbnailPointWidth: 88, scale: 2)
        #endif
    }

    static func current() -> DeviceMediaConditions {
        if Thread.isMainThread { return MainActor.assumeIsolated { currentOnMain() } }
        return DispatchQueue.main.sync { MainActor.assumeIsolated { currentOnMain() } }
    }

    static func policy(device: DeviceMediaConditions, measuredBytesPerSecond: Double?, assetDirectory: URL) -> MediaPolicy? {
        let info = ProcessInfo.processInfo
        let thermal: MediaThermalPressure
        switch info.thermalState {
        case .nominal: thermal = .nominal
        case .fair: thermal = .fair
        case .serious: thermal = .serious
        case .critical: thermal = .critical
        @unknown default: thermal = .serious
        }
        let free = try? FileManager.default.temporaryDirectory
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
        guard let conditions = MediaDeviceConditions(heroSlotPointWidth: device.heroPointWidth,
            thumbnailSlotPointWidth: device.thumbnailPointWidth, screenScale: device.scale,
            network: NetworkPathObserver.shared.current, measuredBytesPerSecond: measuredBytesPerSecond,
            // The wait budget for one image is what the runway already tolerates for one feed request.
            waitBudgetSeconds: 5, freeStorageBytes: free, lowPowerMode: info.isLowPowerModeEnabled, thermal: thermal),
            // Decode-bomb and stream safety ceilings (v1 hardened: 12 MB, 12k px side, 50 MP).
            let ceilings = MediaSafetyCeilings(maximumDownloadBytes: 12_000_000, maximumPixelSide: 12_000,
                maximumPixelCount: 50_000_000) else { return nil }
        return MediaPolicy(conditions: conditions, ceilings: ceilings)
    }
}

/// Current network path for media decisions (constrained / expensive / unavailable).
final class NetworkPathObserver: @unchecked Sendable {
    static let shared = NetworkPathObserver()
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var path: MediaNetworkPath = .unconstrained

    private init() {
        monitor.pathUpdateHandler = { [weak self] update in
            let value: MediaNetworkPath
            if update.status != .satisfied { value = .unavailable }
            else if update.isConstrained { value = .constrained }
            else if update.isExpensive { value = .expensive }
            else { value = .unconstrained }
            self?.lock.lock(); self?.path = value; self?.lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "feedmine.network-path"))
    }

    var current: MediaNetworkPath {
        lock.lock(); defer { lock.unlock() }
        return path
    }
}

/// Delivers cold-bootstrap evidence to the main-actor association after it is constructed.
@MainActor
final class EvidenceRelay {
    var receive: ((ColdFeedEvidence) -> Void)?
    func deliver(_ evidence: ColdFeedEvidence) { receive?(evidence) }
}