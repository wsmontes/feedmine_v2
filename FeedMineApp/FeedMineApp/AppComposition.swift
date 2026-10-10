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
    private(set) var feeds: [TrustedFeed]
    @ObservationIgnored private var preferences: ReaderPreferencesStore?
    private(set) var currentContext: FeedContextRequest = .main
    private var selectionVersion: UInt64 = 2
    private(set) var sourceOptions: [FeedSourceOption] = []
    @ObservationIgnored private var sourceSearchID = UUID()
    @ObservationIgnored private var sourceChoices: [SourceID: TrustedFeed] = [:]
    private let transportConfiguration: URLSessionConfiguration

    init(directory: URL? = nil, feeds: [TrustedFeed] = TrustedFeed.catalogOrDevelopment(limit: 64),
        transportConfiguration: URLSessionConfiguration? = nil) {
        let support = RuntimeDatabaseLocation.applicationSupport(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]).directory
        #if DEBUG
        let namespace = ProcessInfo.processInfo.environment["FEEDMINE_RUNTIME_NAMESPACE"].flatMap(UUID.init(uuidString:))
        self.directory = directory ?? namespace.map { support.appendingPathComponent($0.uuidString) } ?? support
        #else
        self.directory = directory ?? support
        #endif
        self.feeds = feeds
        let config = transportConfiguration ?? .ephemeral
        if transportConfiguration == nil { config.timeoutIntervalForRequest = 20 }
        #if DEBUG
        // Real transport fault configuration for a network-blocked relaunch; no mock connector.
        if ProcessInfo.processInfo.environment["FEEDMINE_BLOCK_RSS_NETWORK"] == "1" {
            DevelopmentNetworkBlock.apply(to: config)
        }
        #endif
        self.transportConfiguration = config
        if feeds.isEmpty { startupFailure = "Não foi possível carregar o catálogo local de fontes." }
        else {
            do {
                let database = try RuntimeDatabase(location: .init(directory: self.directory))
                let preferences = ReaderPreferencesStore(database: database)
                // OMP C1: the repair path (toggleSource) needs preferences even if resolution fails.
                self.preferences = preferences
                var saved = try preferences.initialize(sourceKeys: feeds.map(\.principal))
                var resolved = try TrustedFeed.resolveAvailable(keys: saved.sourceKeys, fallback: feeds)
                if resolved.isEmpty { resolved = feeds }
                if resolved.map(\.principal) != saved.sourceKeys { saved = try preferences.updateSources(resolved.map(\.principal)) }
                if case .source(let id) = saved.activeContext, !resolved.contains(where: { $0.sourceID == id }) {
                    saved = try preferences.setContext(.main)
                }
                self.feeds = resolved
                currentContext = saved.activeContext
                selectionVersion = saved.selectionVersion
            } catch { startupFailure = "Não foi possível carregar a seleção de fontes: \(error)" }
        }
    }

    func launch() async {
        guard !replacingSession, association == nil, startupFailure == nil else { return }
        let current: FeedAssociation
        do {
            current = try FeedAssociation(directory: directory, feeds: feeds, configuration: transportConfiguration, contextRequest: currentContext, selectionVersion: selectionVersion)
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

    func searchSources(_ query: String) async throws {
        let searchID = UUID()
        sourceSearchID = searchID
        var choices = feeds
        if let url = Bundle.main.url(forResource: "catalog", withExtension: "sqlite") {
            let records = try await Task.detached {
                try LegacyCatalogReader(catalogURL: url).matchingSources(query: query, limit: 50)
            }.value
            choices += records.compactMap { record in
                guard let entry = LegacyCatalogImport.entry(record) else { return nil }
                return TrustedFeed(targetID: entry.targetID, sourceID: entry.source.id, bindingID: entry.bindingID,
                    principal: entry.principal, endpoint: entry.endpoint, displayName: entry.source.displayName)
            }
        }
        guard searchID == sourceSearchID else { return }
        sourceChoices = Dictionary(choices.map { ($0.sourceID, $0) }, uniquingKeysWith: { first, _ in first })
        let selected = Set(feeds.map(\.sourceID))
        sourceOptions = sourceChoices.values.map { .init(id: $0.sourceID, name: $0.displayName, selected: selected.contains($0.sourceID)) }
            .sorted { left, right in left.selected != right.selected ? left.selected : left.name.localizedStandardCompare(right.name) == .orderedAscending }
    }

    func toggleSource(_ sourceID: SourceID) async throws {
        guard !replacingSession else { return }
        replacingSession = true
        defer { replacingSession = false }
        guard let choice = sourceChoices[sourceID], let preferences else { throw ReaderPreferencesError.invalidSelection }
        var next = feeds
        if let index = next.firstIndex(where: { $0.sourceID == sourceID }) { next.remove(at: index) }
        else { next.append(choice) }
        guard !next.isEmpty else { throw ReaderPreferencesError.invalidSelection }
        if let retired = association {
            _ = try await retired.session.checkpointCurrentPosition(at: Date())
            await retired.close()
        }
        association = nil
        let saved = try preferences.updateSources(next.map(\.principal))
        feeds = next
        selectionVersion = saved.selectionVersion
        let request: FeedContextRequest = next.count == 1 ? .source(next[0].sourceID) : .main
        _ = try preferences.setContext(request)
        currentContext = request
        let nextAssociation = try FeedAssociation(directory: directory, feeds: feeds, configuration: transportConfiguration,
            contextRequest: request, selectionVersion: selectionVersion)
        association = nextAssociation
        startupFailure = nil
        try await nextAssociation.launch()
        try await searchSources("")
    }

    func selectContext(_ request: FeedContextRequest) async throws {
        if case .source(let sourceID) = request, !feeds.contains(where: { $0.sourceID == sourceID }) {
            throw ReaderPreferencesError.invalidSelection
        }
        guard !replacingSession else { return }
        if request == currentContext, association != nil { return }
        replacingSession = true
        defer { replacingSession = false }
        if let retired = association {
            _ = try await retired.session.checkpointCurrentPosition(at: Date())
            await retired.close()
        }
        association = nil
        _ = try preferences?.setContext(request)
        currentContext = request
        let next = try FeedAssociation(directory: directory, feeds: feeds, configuration: transportConfiguration,
            contextRequest: request, selectionVersion: selectionVersion)
        association = next
        startupFailure = nil
        try await next.launch()
    }

    /// Explicit session replacement; no replacement occurs during normal feed opportunities.
    func replaceSession() async throws {
        guard !replacingSession else { return }
        replacingSession = true
        defer { replacingSession = false }
        let retired = association
        association = nil
        if let retired {
            _ = try await retired.session.checkpointCurrentPosition(at: Date())
            await retired.close()
        }
        let next = try FeedAssociation(directory: directory, feeds: feeds, configuration: transportConfiguration, contextRequest: currentContext, selectionVersion: selectionVersion)
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
    @ObservationIgnored private let maintainTail: @Sendable (PublicationStore.HiddenTailLease) async throws -> PublicationStore.TailSuccessionResult
    private let cold: ColdFeedBootstrap
    @ObservationIgnored private let relay: EvidenceRelay
    @ObservationIgnored private var preparation: PreparationProgress?
    @ObservationIgnored private let targetNames: [AcquisitionTargetID: String]
    @ObservationIgnored private let admittedHeadlines: @Sendable () -> [String]
    private let transport: URLSession
    private(set) var active = true
    private var launching = false
    @ObservationIgnored
    lazy var store: FeedScreenStore = FeedScreenStore(onViewport: { [weak self] observation, activity in
        guard let self else { return }
        Task { await self.viewport(observation, activity: activity) }
    }, onOpen: { [weak self] cardID in
        self?.open(cardID)
    }, onBookmark: { [weak self] cardID in
        guard let self, self.active else { return }
        do {
            let publication = PublicationStore(database: self.database)
            try publication.toggleBookmark(cardID: cardID, at: Date())
            self.store.installBookmarks(try publication.bookmarkedCardIDs())
        } catch { self.reportFailure(error) }
    })

    /// Review F10: resolve the frozen action target from published history and open it.
    /// The URL never crosses the UI boundary; only the card identity does.
    private func open(_ cardID: PublicationCardID) {
        guard active, visible, store.state.presentation?.window.items.contains(where: { $0.id == cardID }) == true else { return }
        guard let card = try? PublicationStore(database: database).card(id: cardID),
            card.primaryActionKind == "externalURL", let reference = card.primaryActionReference,
            let url = URL(string: reference) else { return }
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
        Self.log("opened card=\(cardID.rawValue)")
    }

    #if DEBUG
    private(set) var viewportReceived = 0
    private(set) var viewportCompleted = 0
    private(set) var backwardCompleted = 0
    #endif

    static var resources: FeedRunwayDriverResources {
        .init(runway: .init(localWorkAllowed: true, examinedCandidateCapacity: 32,
            readyProbeBound: 32, readyProbeCeiling: 256, forwardAdvanceProbeBound: 256,
            // F01: the session materializes 16 cards ahead; keep at least that much published.
            reserveCards: 16)!,
            acquisition: .init(targetWorkCapacity: 2, batchCapacityPerNewExecution: 1,
                observationCapacityPerBatch: 32, byteCapacityPerBatch: 1_000_000)!)
    }

    init(directory: URL, feeds: [TrustedFeed], configuration: URLSessionConfiguration,
        contextRequest: FeedContextRequest = .main, selectionVersion: UInt64 = 2) throws {
        let db = try RuntimeDatabase(location: .init(directory: directory))
        database = db
        let history = PublicationHistory(database: db)
        let context = FeedContext(request: contextRequest)
        let checkpoints = SessionStore(database: db)
        try checkpoints.activateContext(contextRequest)
        if let active = try checkpoints.checkpoint() {
            try PublicationStore(database: db).setVisibility(editionID: active.editionID, visible: true)
        }
        var saved = try history.restore(backwardCapacity: 8, forwardCapacity: 16, contextKey: context.key)
        if let restored = saved, restored.edition.editorialRevision.userSelectionVersion != PolicyVersion(rawValue: selectionVersion)
            || restored.edition.editorialRevision.eligibilityPolicyVersion != PolicyVersion(rawValue: 2) {
            try checkpoints.clearActiveCheckpoint()
            saved = nil
        }
        let v = PolicyVersion(rawValue: 1)
        // Sequencing v2 = PD-4 source alternation; exposure v2 = PD-1 edited articles reappear.
        // A behavior change is a new EditorialRevision; a restored Edition keeps its own behavior.
        let alternating = PolicyVersion(rawValue: 2)
        let revision = try saved?.edition.editorialRevision ?? EditorialRevision(
            id: .init(rawValue: LegacyCatalogImport.stableUUID(namespace: "feedmine.editorial.context",
                key: try JSONEncoder().encode(contextRequest).base64EncodedString() + "|" + String(selectionVersion))),
            contextKey: context.key, catalogGeneration: .init(rawValue: 1), userSelectionVersion: PolicyVersion(rawValue: selectionVersion),
            eligibilityPolicyVersion: alternating, scoringPolicyVersion: v, sequencingPolicyVersion: alternating,
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
            eligibility: .selectedSources(Set(feeds.map(\.sourceID))), scoring: .equal, sequencing: sequencing,
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
        }, usage: { try PublicationStore(database: db).mediaUsage() })
        tidyWaitSeconds = configuration.timeoutIntervalForRequest / 4
        coldRetryFallbackSeconds = configuration.timeoutIntervalForRequest
        let session = FeedSession(publicationHistory: history, imageDecoder: PresentationImageDecoder(
            assetDirectory: assetDirectory, heroMaxPixel: device.heroPixelWidth, thumbnailMaxPixel: device.thumbnailPixelWidth))
        self.session = session
        let names = Dictionary(uniqueKeysWithValues: feeds.map { ($0.sourceID, $0.displayName) })
        let prepare: @Sendable (SelectionResult) -> LocalPreparedPublication = { Self.prepare($0, readiness: readiness, names: names) }
        // Bounded wait for media of the supply head: what the runway can afford (one request timeout).
        let mediaWait = configuration.timeoutIntervalForRequest / 4
        maintainTail = { lease in
            try await HiddenTailMaintenance(database: db).run(plan: plan, policy: policy, lease: lease, examinedCapacity: 256,
                prefetch: { revisions in await media.prefetch(revisions, deadline: ProcessInfo.processInfo.systemUptime + mediaWait) },
                prepare: prepare)
        }
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
            prepare: prepare, prepareMedia: prepareRunwayMedia,
            selectedSourceCoverage: .init(selectedSourceCoverageFor: plan.context.key, editorialRevisionID: plan.revision.id))
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
                contentEntityID: nil, contentClusterID: nil,
                // F10: the card opens its article.
                primaryAction: candidate.primaryLink.map { .externalURL($0) },
                presentation: readiness.presentation(for: candidate.originRevisionID))
        }, cardIDs: selection.orderedCandidates.map { _ in PublicationCardID() })
    }

    func install(_ received: FeedPresentationState) throws {
        guard active else { throw FeedPresentationStateError.projectionSequenceMismatch }
        try store.install(received)
        store.installBookmarks(try PublicationStore(database: database).bookmarkedCardIDs())
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
            if case .published = outcome {} else {
                // Review F16: no first Edition yet. Recover without a gesture at the earliest fact-based
                // time: a cooling feed's expiry, else one request timeout (what one attempt may cost).
                coldRetryAt = await coordinator.nextCoolingExpiry()
                    ?? ProcessInfo.processInfo.systemUptime + coldRetryFallbackSeconds
                await scheduleLocalRetryIfNeeded()
                return
            }
            coldRetryAt = nil
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
    /// F16: when the next cold attempt may run if no first Edition exists yet.
    @ObservationIgnored private var coldRetryAt: Double?
    @ObservationIgnored private var coldRetryFallbackSeconds: Double = 20
    private func scheduleLocalRetryIfNeeded() async {
        retryTask?.cancel()
        retryTask = nil
        let local = await driver.localRetryEligibleAt()?.seconds
        let acquisition = await driver.acquisitionResumeAt()?.seconds
        let cold = await session.currentPresentation() == nil ? coldRetryAt : nil
        // One opportunity at the earliest fact-derived time: a local retry or a feed leaving cooldown.
        guard active, visible, let at = [local, acquisition, cold].compactMap({ $0 }).min() else { return }
        let eligible = RunwayMonotonicTime(seconds: at) ?? RunwayMonotonicTime(seconds: 0)!
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
        case .published(let snapshot):
            progress = progress.applying(.prepared(cards: snapshot.window.items.count), at: now)
            // F06: show the first Edition now; slower feeds keep answering behind the badge.
            do { try install(FeedPresentationHandoff.receive(snapshot: snapshot, into: store.state)) }
            catch { Self.log("early publication rejected") }
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
            if let edition = store.state.presentation?.editionID {
                try PublicationStore(database: database).setVisibility(editionID: edition, visible: true)
            }
            guard active, !launching else { return }
            if let refreshed = try await session.refreshCurrentPresentation() {
                try install(FeedPresentationHandoff.receive(snapshot: refreshed, into: store.state))
            }
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
            let lease = try store.state.presentation.map { try PublicationStore(database: database).hiddenTail(editionID: $0.editionID) } ?? nil
            // PD-5: the screen is not visible now, so the house can be tidied: complete media for
            // the next cards and bring local media under the device-derived budget. Seen and visible
            // cards are never changed.
            let visible = Set(store.state.presentation?.window.items.compactMap { $0.image?.key } ?? [])
            let report = await tidy.run(visibleKeys: visible, supplyHeadLimit: 32,
                deadline: ProcessInfo.processInfo.systemUptime + tidyWaitSeconds)
            Self.log("tidy evicted=\(report.evictedAssets) reclaimed=\(report.reclaimedBytes) budget=\(report.budgetBytes)")
            if active, !self.visible, let lease {
                let result = try await maintainTail(lease)
                Self.log("hidden tail \(result)")
            }
        } catch { reportFailure(error) }
    }

    func close() async {
        cold.cancel()
        if let edition = store.state.presentation?.editionID {
            try? PublicationStore(database: database).setVisibility(editionID: edition, visible: true)
        }
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