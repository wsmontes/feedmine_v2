import Foundation
import XCTest
import GRDB
@testable import FeedMinePersistence
@testable import FeedMineComposition
import FeedMineDomain
import FeedMineAcquisition
import FeedMineEditorial
import FeedMinePublication
import FeedMineRuntime

/// F01's core: a profile of interests and languages turns into real sources from the bundled catalogue, without
/// the reader naming a feed. Deterministic, bounded, and derived only from the catalogue's own labels.
private final class SettledCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func set(_ next: Int) { lock.withLock { value = next } }
    var count: Int { lock.withLock { value } }
}

final class ReaderDiscoveryPoolTests: XCTestCase {
    private func catalog() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE catalog_node (id INTEGER PRIMARY KEY, key TEXT NOT NULL UNIQUE, parent_id INTEGER,
                    name TEXT NOT NULL, kind INTEGER NOT NULL, source_count INTEGER NOT NULL DEFAULT 0,
                    child_count INTEGER NOT NULL DEFAULT 0, language TEXT);
                CREATE TABLE catalog_source (id INTEGER PRIMARY KEY, key TEXT NOT NULL UNIQUE, title TEXT NOT NULL,
                    declared_url TEXT NOT NULL, request_url TEXT NOT NULL, display_host TEXT, media_kind TEXT NOT NULL,
                    language TEXT, site_url TEXT, description TEXT, tags TEXT, nature TEXT, activity TEXT,
                    latest_item_at TEXT, quality_score INTEGER, default_enabled INTEGER NOT NULL DEFAULT 1,
                    contact_email TEXT, contact_name TEXT, contact_source TEXT, contact_type TEXT);
                CREATE TABLE catalog_placement (id INTEGER PRIMARY KEY, source_id INTEGER NOT NULL, node_id INTEGER NOT NULL,
                    node_name TEXT NOT NULL, opml_file TEXT NOT NULL, sort_order INTEGER NOT NULL, title_override TEXT,
                    language_override TEXT, media_kind_override TEXT);
                INSERT INTO catalog_node (id, key, parent_id, name, kind) VALUES
                    (1, 'topics', NULL, 'Topics', 0), (2, 'topics/science', 1, 'Science', 0),
                    (3, 'topics/sport', 1, 'Sport', 0);
                INSERT INTO catalog_source (id, key, title, declared_url, request_url, media_kind, language, quality_score) VALUES
                    (10, 'https://science.pt/feed', 'Ciência PT', 'https://science.pt/feed', 'https://science.pt/feed', 'text', 'pt', 90),
                    (11, 'https://science.en/feed', 'Science EN', 'https://science.en/feed', 'https://science.en/feed', 'text', 'en', 70),
                    (12, 'https://science.unknown/feed', 'Sem idioma', 'https://science.unknown/feed', 'https://science.unknown/feed', 'text', NULL, 80),
                    (13, 'https://science.pod/pod', 'Podcast', 'https://science.pod/pod', 'https://science.pod/pod', 'audio', 'pt', 95),
                    (14, 'https://sport.pt/feed', 'Sport PT', 'https://sport.pt/feed', 'https://sport.pt/feed', 'text', 'pt', 60),
                    (15, 'https://science.pt-two/feed', 'Ciência PT 2', 'https://science.pt-two/feed', 'https://science.pt-two/feed', 'text', 'pt-BR', 85),
                    (16, 'https://both.xx/feed', 'Ciência e esporte', 'https://both.xx/feed', 'https://both.xx/feed', 'text', NULL, 50),
                    -- D10: the highest-quality source here is video, in the topic and language every discovery
                    -- profile below names — so "video never enters the automatic pool" is a fact of the pool and
                    -- not of a fixture that simply has none.
                    (17, 'https://science.video/feed', 'Vídeo', 'https://science.video/feed', 'https://science.video/feed', 'video', 'pt', 99);
                INSERT INTO catalog_placement (source_id, node_id, node_name, opml_file, sort_order) VALUES
                    (10, 2, 'Science', 'x.opml', 0), (11, 2, 'Science', 'x.opml', 1),
                    (12, 2, 'Science', 'x.opml', 2), (13, 2, 'Science', 'x.opml', 3),
                    (14, 3, 'Sport', 'y.opml', 0), (15, 2, 'Science', 'x.opml', 4),
                    (16, 2, 'Science', 'x.opml', 5), (16, 3, 'Sport', 'y.opml', 1),
                    (17, 2, 'Science', 'x.opml', 6);
                """)
        }
        return url
    }

    /// Round 9: a profile that names a language admits every regional declaration of it, and a profile stored
    /// with a regional code *is* that profile. Before this rule `pt-BR` matched neither `pt` nor `pt-BR` — the
    /// filter admitted nothing at all.
    func testAProfileAdmitsEveryRegionalDeclarationOfItsLanguage() throws {
        let builder = ReaderDiscoveryBuilder(catalogURL: try catalog())
        func endpoints(_ languages: Set<String>) throws -> Set<String> {
            Set(try builder.pool(for: .init(languages: languages, topicNodeKeys: ["topics/science"]), limit: 50)
                .entries.map(\.endpoint.absoluteString))
        }
        let portuguese = try endpoints(["pt"])
        XCTAssertFalse(portuguese.isEmpty)
        XCTAssertTrue(portuguese.contains { $0.contains("science.pt-two") },
            "the source that declares pt-BR is admitted by a profile that named pt")
        XCTAssertEqual(try endpoints(["pt-BR"]), portuguese, "a regional choice is the language")
        XCTAssertEqual(try endpoints(["PT"]), portuguese, "and case does not make a second choice")
        XCTAssertNotEqual(try endpoints(["en"]), portuguese)
    }

    /// A target discovered from a catalogue entry must carry its declared language into the
    /// materialized registration, not rely on an outer snapshot to filter it a second time.
    /// R13: a subject returned to "Normal" is not an exclusion. The pool includes the persisted topic again, and
    /// the reader's own cycle (more → less → neutral) cannot leave a stale exclusion behind.
    func testNeutralPreferenceDoesNotExcludePersistedTopic() throws {
        let catalogURL = try catalog()
        let builder = ReaderDiscoveryBuilder(catalogURL: catalogURL)
        func pool(_ level: ReaderPreferenceLevel) throws -> [String] {
            let recipe = FeedRecipeDefinition(languages: ["pt"],
                topicPreferences: ["topic:topics/science": level])
            return try builder.pool(for: ReaderDiscoveryProfile(recipe: recipe), limit: 50)
                .entries.map(\.principal)
        }
        XCTAssertTrue(try pool(.neutral).contains("https://science.pt/feed"),
            "neutral não exclui o assunto persistido")
        XCTAssertTrue(try pool(.more).contains("https://science.pt/feed"))
        XCTAssertFalse(try pool(.less).contains("https://science.pt/feed"),
            "menos exclui uma fonte que só está nesse assunto")
        XCTAssertEqual(ReaderPreferenceLevel.more.next(), .less)
        XCTAssertEqual(ReaderPreferenceLevel.less.next(), .neutral)
        XCTAssertTrue(try pool(.less.next()).contains("https://science.pt/feed"),
            "voltar de menos para normal devolve a fonte")
    }

    /// R13: editorial keys (`media:`, `nature:`) are weights in their own namespace; they are not catalogue topic
    /// nodes and must not become topic exclusions. A topic-keyed editorial answer still excludes its topic.
    func testEditorialAndTopicKeysDoNotCollide() {
        let recipe = FeedRecipeDefinition(languages: ["pt"],
            topicPreferences: ["topic:topics/science": .more],
            editorialPreferences: ["media:video": .less, "nature:paywall": .less])
        let profile = ReaderDiscoveryProfile(recipe: recipe)
        XCTAssertEqual(profile.topicNodeKeys, ["topics/science"])
        XCTAssertTrue(profile.excludedTopicNodeKeys.isEmpty,
            "chaves editoriais não viram nós de assunto")
        XCTAssertEqual(recipe.weight(forKey: "media:video"), -1.5,
            "o peso editorial continua valendo na ordenação")
        XCTAssertEqual(recipe.weight(forKey: "nature:paywall"), -1.5)
        let explicit = FeedRecipeDefinition(editorialPreferences: ["topic:topics/science": .less])
        XCTAssertEqual(ReaderDiscoveryProfile(recipe: explicit).excludedTopicNodeKeys, ["topics/science"],
            "uma resposta editorial com chave de assunto ainda exclui aquele assunto")
    }

    func testD2TraversalCarriesEntryLanguageIntoAcquisitionEligibility() throws {
        let catalogURL = try catalog()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let db = try RuntimeDatabase(location: .init(directory: directory))
        let transport = URLSession(configuration: .ephemeral)
        addTeardownBlock { transport.invalidateAndCancel() }
        let context = FeedContext(request: .main, filter: ReaderFilter(languages: ["en"]))
        // Topic-only discovery visits entries in multiple languages; the context itself names English.
        let traversal = ReaderDiscoveryTraversal(builder: ReaderDiscoveryBuilder(catalogURL: catalogURL),
            profile: ReaderDiscoveryProfile(topicNodeKeys: ["topics/science"]), contextKey: context.key)
        let acquisition = try SyndicationAcquisitionSnapshot(database: db, registrations: [],
            session: transport, redirectCapacity: 0, discovery: traversal)
        let page = try XCTUnwrap(acquisition.advanceDiscovery(for: context, examinedCapacity: 100))
        XCTAssertTrue(page.entries.contains { $0.principal == "https://science.pt/feed" },
            "The fixture must actually traverse a known mismatching language")
        XCTAssertTrue(page.entries.contains { $0.principal == "https://science.en/feed" })
        XCTAssertTrue(page.entries.contains { $0.principal == "https://science.unknown/feed" })

        let targets = try traversal.targets(for: context)
        func hasTarget(_ principal: String) -> Bool {
            guard let entry = traversal.entries.first(where: { $0.principal == principal }) else { return false }
            return targets.contains { $0.id == entry.targetID }
        }
        XCTAssertFalse(hasTarget("https://science.pt/feed"), "Known mismatch must be rejected by the materialized page")
        XCTAssertTrue(hasTarget("https://science.en/feed"), "Known matching language must remain eligible")
        XCTAssertTrue(hasTarget("https://science.unknown/feed"), "Unknown catalogue language must not be rejected")
    }

    private struct ProgressiveFixture {
        let database: RuntimeDatabase
        let catalogURL: URL
        let discovery: ReaderDiscoveryTraversal
        let acquisition: SyndicationAcquisitionSnapshot
        let coordinator: AcquisitionCoordinator
        let plan: FeedPlan
        let policy: ResolvedSelectionPolicy
        let edition: FeedEditionID
        let session: FeedSession
        let initial: FeedPresentationSnapshot?
    }

    @MainActor
    private func progressiveFixture(count: Int = 125) async throws -> ProgressiveFixture {
        let url = try catalog(), queue = try DatabaseQueue(path: url.path)
        try await queue.write { db in
            for n in 0..<count {
                let key = String(format: "https://progress%04d.test/feed", n)
                try db.execute(sql: """
                    INSERT INTO catalog_source (id, key, title, declared_url, request_url, media_kind, language, quality_score)
                    VALUES (?, ?, 'Progressive', ?, ?, 'text', 'pt', 80)
                    """, arguments: [1000 + n, key, key, key])
                try db.execute(sql: "INSERT INTO catalog_placement (source_id, node_id, node_name, opml_file, sort_order) VALUES (?, 2, 'Science', 'p', ?)",
                    arguments: [1000 + n, n])
            }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ProgressiveDiscoveryURLProtocol.self]
        let transport = URLSession(configuration: config)
        addTeardownBlock { transport.invalidateAndCancel() }
        let discovery = ReaderDiscoveryTraversal(builder: ReaderDiscoveryBuilder(catalogURL: url),
            profile: .init(languages: ["pt"], topicNodeKeys: ["topics/science"]), contextKey: .init(request: .main))
        let acquisition = try SyndicationAcquisitionSnapshot(database: database, registrations: [], session: transport,
            redirectCapacity: 0, discovery: discovery)
        let coordinator = acquisition.makeCoordinator(concurrentTargetLimit: 2)
        let context = FeedContext(request: .main), v = PolicyVersion(rawValue: 1)
        let revision = EditorialRevision(id: .init(), contextKey: context.key, catalogGeneration: .init(rawValue: 1),
            userSelectionVersion: v, eligibilityPolicyVersion: v, scoringPolicyVersion: v,
            sequencingPolicyVersion: v, exposurePolicyVersion: v, selectionSchemaVersion: .init(rawValue: 1))
        let plan = try XCTUnwrap(FeedPlan(context: context, revision: revision))
        let seedSource = SourceID(), record = OriginRecordID()
        let seed = OriginRevision(id: .init(), originRecordID: record, externalVersionIdentity: nil,
            headline: "Seed", summary: nil, bodyText: nil, authoredAt: nil, modifiedAt: nil,
            observedAt: Date(timeIntervalSince1970: 1), language: nil, primaryLink: nil,
            searchProjection: nil, providerID: nil)
        try ContentStore(database: database).commitCanonicalChange(.init(recordID: record,
            externalObjectIdentity: .init(connectorKind: .syndication, namespace: "seed", value: "seed", role: .object),
            revision: seed, mediaCandidates: [], availability: .available, observedAt: seed.observedAt,
            expectedCurrent: .none, currentUpdate: .useSuppliedRevision,
            membershipMutations: [.upsert(sourceID: seedSource, kind: .direct, observedAt: seed.observedAt)]))
        let policy = ResolvedSelectionPolicy(contextKey: context.key, userSelectionVersion: v, eligibilityPolicyVersion: v,
            scoringPolicyVersion: v, sequencingPolicyVersion: v, exposurePolicyVersion: v,
            selectionSchemaVersion: revision.selectionSchemaVersion, eligibility: .selectedSources([seedSource]),
            scoring: .equal, sequencing: .recencyDescending, exposure: .excludePublishedMaterial)
        let edition = FeedEditionID()
        _ = try InitialProductionSlice(database: database).run(.init(plan: plan, policy: policy, examinedCapacity: 8,
            editionID: edition, publicationSchemaVersion: .init(rawValue: 1), selectionSeed: 1, editionCreatedAt: Date(),
            segmentID: .init(), segmentSeed: 1, segmentCreatedAt: Date(), anchorPlacement: .top, checkpointedAt: Date()),
            prepare: Self.prepareDiscovery)
        let session = FeedSession(publicationHistory: .init(database: database))
        let initial = try await session.admitPresentation(.initial(.init(backwardCapacity: 0, forwardCapacity: 4)))
        return .init(database: database, catalogURL: url, discovery: discovery, acquisition: acquisition,
            coordinator: coordinator, plan: plan, policy: policy, edition: edition, session: session, initial: initial)
    }

    @MainActor
    func testRetainedDiscoveryUsesTheReplacementAssociationsTransport() async throws {
        let f = try await progressiveFixture(count: 1)
        _ = try f.acquisition.advanceDiscovery(for: f.plan.context, examinedCapacity: 8)
        let entries = f.discovery.entries
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineDiscoveryURLProtocol.self]
        let transport = URLSession(configuration: configuration)
        defer { transport.invalidateAndCancel() }
        let replacement = try SyndicationAcquisitionSnapshot(database: f.database, registrations: [],
            session: transport, redirectCapacity: 0, discovery: f.discovery)
        let coordinator = replacement.makeCoordinator()
        let targets = try replacement.eligibleTargets(for: f.plan.context)
        let demand = AcquisitionDemand(selectedSourceCoverageFor: f.plan.context.key,
            editorialRevisionID: f.plan.revision.id)
        let outcome = try await coordinator.selectionOpportunity { position, active, cooling in
            try AcquisitionPlanner.plan(demand: demand, eligibleTargets: targets,
                activeExecutions: active, resources: .init(targetWorkCapacity: 8,
                    batchCapacityPerNewExecution: 1, observationCapacityPerBatch: 8,
                    byteCapacityPerBatch: 100_000)!, selectionAfter: position)
        }
        guard case .planned(let plan) = outcome else { return XCTFail("Retained pages must remain acquirable") }
        _ = try await coordinator.executeConcurrently(plan.work, onResult: { _ in })
        XCTAssertEqual(f.discovery.entries, entries, "Replacement retains traversal progress")
        for entry in entries {
            XCTAssertTrue(try ContentStore(database: f.database).candidateWindow(sourceID: entry.source.id,
                after: nil, examinedCapacity: 8).records.isEmpty,
                "The replacement is offline; an older transport must not supply its sources")
        }
    }

    @MainActor
    func testExistingDriverAndCoordinatorAcquireProgressivePagesBeyond120() async throws {
        let f = try await progressiveFixture()
        let database = f.database, discovery = f.discovery, acquisition = f.acquisition, coordinator = f.coordinator
        let plan = f.plan, policy = f.policy, edition = f.edition, session = f.session, initial = f.initial
        let context = plan.context, revision = plan.revision
        let runway = RunwayController(configuration: .init(policyInputs: .init(safetyFactor: 1, releaseMarginSeconds: 0)!,
            consumptionSampleLimit: 2, replenishmentSampleLimit: 2)!)
        let driver = try FeedRunwayDriver(session: session, runway: runway, plan: plan, policy: policy,
            acquisition: acquisition, coordinator: coordinator,
            monotonicNow: { .init(seconds: ProcessInfo.processInfo.systemUptime)! },
            makeSegmentIdentity: { .init(segmentID: .init(), segmentSeed: 1, segmentCreatedAt: Date())! },
            prepare: Self.prepareDiscovery, selectedSourceCoverage: .init(selectedSourceCoverageFor: context.key,
                editorialRevisionID: revision.id))
        let resources = FeedRunwayDriverResources(runway: .init(localWorkAllowed: true, examinedCandidateCapacity: 32,
            readyProbeBound: 4, readyProbeCeiling: 8, forwardAdvanceProbeBound: 8, reserveCards: 1)!,
            acquisition: .init(targetWorkCapacity: 2, batchCapacityPerNewExecution: 1,
                observationCapacityPerBatch: 8, byteCapacityPerBatch: 100_000)!, discoveryExaminedCapacity: 60)
        _ = try await driver.drive(resources: resources)
        XCTAssertTrue(discovery.entries.isEmpty, "An inactive driver cannot advance discovery")
        _ = try await driver.activateCurrentPresentation(resources: resources)
        for _ in 0..<200 where discovery.entries.count < 59 { try? await Task.sleep(for: .milliseconds(25)) }
        XCTAssertEqual(discovery.entries.count, 59, "One opportunity examines one page, including profile misses")
        let firstCards = try PublicationStore(database: database).segments(editionID: edition).flatMap(\.cardIDs)
        let firstSources = try Set(firstCards.compactMap { try PublicationStore(database: database).card(id: $0)?.sourceID })
        let revoked = try XCTUnwrap(discovery.entries.first {
            !firstSources.contains($0.source.id) && $0.principal != "https://progress0124.test/feed"
        })
        _ = try AcquisitionTargetAuthority(database: database).revoke(id: revoked.targetID, expectedGeneration: 1)
        _ = try await driver.drive(resources: resources)
        for _ in 0..<200 where discovery.entries.count < 119 { try? await Task.sleep(for: .milliseconds(25)) }
        XCTAssertEqual(discovery.entries.count, 119)
        _ = try await driver.drive(resources: resources)
        for _ in 0..<200 where discovery.entries.count < 128 { try? await Task.sleep(for: .milliseconds(25)) }
        // 125 progressive sources plus the three fixture sources the catalogue places in the reader's language as
        // text or audio: the walk reaches every one of them, past the legacy 120 ceiling, and stops there.
        XCTAssertEqual(discovery.entries.count, 128)
        XCTAssertTrue(discovery.exhausted)
        let entries = discovery.entries
        XCTAssertTrue(entries.contains { $0.principal == "https://science.pod/pod" },
            "the walk admits the audio source of the reader's language, not only its text sources")
        let targets = try acquisition.eligibleTargets(for: context)
        XCTAssertEqual(targets.count, 127)
        XCTAssertFalse(targets.contains { $0.id == revoked.targetID })
        XCTAssertTrue(targets.allSatisfy { acquisition.connector(for: $0) != nil })
        let settled = SettledCounter()
        for _ in 0..<800 {
            _ = await coordinator.selectionOpportunity { _, _, _, generations in
                settled.set(generations.count)
                return .disposition(.noEligibleTargets)
            }
            if settled.count >= targets.count { break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(settled.count, targets.count)
        let beyond120 = try XCTUnwrap(entries.first { $0.principal == "https://progress0124.test/feed" })
        for _ in 0..<800 where (try? ContentStore(database: database).candidateWindow(sourceID: beyond120.source.id,
            after: nil, examinedCapacity: 200).records.count) != 1 {
            try? await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(try ContentStore(database: database).candidateWindow(sourceID: beyond120.source.id,
            after: nil, examinedCapacity: 200).records.count, 1)
        // Newly acquired sources are eligible when measured runway pressure requests publication.
        let pressure = FeedRunwayDriverResources(runway: .init(localWorkAllowed: true, examinedCandidateCapacity: 32,
            readyProbeBound: 128, readyProbeCeiling: 256, forwardAdvanceProbeBound: 256, reserveCards: 128)!,
            acquisition: resources.acquisition, discoveryExaminedCapacity: 60)
        _ = try await driver.drive(resources: pressure)
        var cards = try PublicationStore(database: database).segments(editionID: edition).flatMap(\.cardIDs)
        var publishedSources = try Set(cards.compactMap { try PublicationStore(database: database).card(id: $0)?.sourceID })
        for _ in 0..<200 where !publishedSources.contains(beyond120.source.id) {
            try? await Task.sleep(for: .milliseconds(25))
            cards = try PublicationStore(database: database).segments(editionID: edition).flatMap(\.cardIDs)
            publishedSources = try Set(cards.compactMap { try PublicationStore(database: database).card(id: $0)?.sourceID })
        }
        XCTAssertFalse(publishedSources.contains(revoked.source.id), "Revoked discovery sources cannot acquire new occurrences")
        XCTAssertTrue(publishedSources.contains(beyond120.source.id), "New pages extend selected-source eligibility")
        let finalPresentation = await session.currentPresentation()
        XCTAssertEqual(finalPresentation, initial, "Discovery cannot move or admit the reader's position")
        let attempted = try targets.map { try AcquisitionTargetAuthority(database: database).target(id: $0.id)?.checkpointRevision }
        _ = try await driver.drive(resources: resources)
        XCTAssertEqual(try targets.map { try AcquisitionTargetAuthority(database: database).target(id: $0.id)?.checkpointRevision }, attempted)
        XCTAssertEqual(try PublicationStore(database: database).segments(editionID: edition).flatMap(\.cardIDs), cards)
    }

    @MainActor
    func testDiscoveryPolicyPreservesCuratedRankingAndAllBehaviorVersions() async throws {
        let f = try await progressiveFixture(count: 1)
        _ = try f.acquisition.advanceDiscovery(for: f.plan.context, examinedCapacity: 8)
        let source = SourceID(), original = f.policy
        let base = ResolvedSelectionPolicy(contextKey: original.contextKey,
            userSelectionVersion: original.userSelectionVersion, eligibilityPolicyVersion: original.eligibilityPolicyVersion,
            scoringPolicyVersion: original.scoringPolicyVersion, sequencingPolicyVersion: original.sequencingPolicyVersion,
            exposurePolicyVersion: original.exposurePolicyVersion, selectionSchemaVersion: original.selectionSchemaVersion,
            eligibility: .selectedSources([source]), scoring: .weighted([source: 3]),
            sequencing: original.sequencing, exposure: original.exposure)
        let effective = try f.acquisition.policyIncludingDiscovery(base)
        let expected = ResolvedSelectionPolicy(contextKey: base.contextKey,
            userSelectionVersion: base.userSelectionVersion, eligibilityPolicyVersion: base.eligibilityPolicyVersion,
            scoringPolicyVersion: base.scoringPolicyVersion, sequencingPolicyVersion: base.sequencingPolicyVersion,
            exposurePolicyVersion: base.exposurePolicyVersion, selectionSchemaVersion: base.selectionSchemaVersion,
            eligibility: .selectedSources(Set(f.discovery.entries.map { $0.source.id }).union([source])),
            scoring: .weighted([source: 3]), sequencing: base.sequencing, exposure: base.exposure)
        XCTAssertEqual(effective, expected)
        let revoked = try XCTUnwrap(f.discovery.entries.first)
        _ = try AcquisitionTargetAuthority(database: f.database).revoke(id: revoked.targetID, expectedGeneration: 1)
        guard case .selectedSources(let enabled) = try f.acquisition.policyIncludingDiscovery(base).eligibility else {
            return XCTFail("Discovery preserves the selected-source policy")
        }
        XCTAssertTrue(enabled.contains(source), "An explicit choice remains eligible")
        XCTAssertFalse(enabled.contains(revoked.source.id), "Revoked discoveries cannot publish new cards")
    }

    @MainActor
    func testDeactivationDuringMediaBudgetCreationDoesNotAdvanceDiscovery() async throws {
        let f = try await progressiveFixture(count: 5)
        let entered = expectation(description: "Media budget awaits its measurement")
        let (release, signal) = AsyncStream<Void>.makeStream()
        defer { signal.finish() }
        let runway = RunwayController(configuration: .init(policyInputs: .init(safetyFactor: 1, releaseMarginSeconds: 0)!,
            consumptionSampleLimit: 2, replenishmentSampleLimit: 2)!)
        let driver = try FeedRunwayDriver(session: f.session, runway: runway, plan: f.plan, policy: f.policy,
            acquisition: f.acquisition, coordinator: f.coordinator,
            monotonicNow: { .init(seconds: ProcessInfo.processInfo.systemUptime)! },
            makeSegmentIdentity: { .init(segmentID: .init(), segmentSeed: 1, segmentCreatedAt: Date())! },
            prepare: Self.prepareDiscovery, makeMediaOpportunity: {
                entered.fulfill()
                for await _ in release { break }
                return .init(waitSeconds: 4, startedAt: 100) { _, _ in }
            })
        let resources = FeedRunwayDriverResources(runway: .init(localWorkAllowed: true, examinedCandidateCapacity: 8,
            readyProbeBound: 4, readyProbeCeiling: 8, forwardAdvanceProbeBound: 8, reserveCards: 1)!,
            acquisition: .init(targetWorkCapacity: 2, batchCapacityPerNewExecution: 1,
                observationCapacityPerBatch: 8, byteCapacityPerBatch: 100_000)!, discoveryExaminedCapacity: 3)
        let activation = Task { try await driver.activateCurrentPresentation(resources: resources) }
        await fulfillment(of: [entered], timeout: 5)
        await driver.deactivate()
        signal.yield(())
        _ = try await activation.value
        XCTAssertTrue(f.discovery.entries.isEmpty, "An opportunity revoked during budget creation cannot discover a page")
    }

    @MainActor
    func testDiscoveryMetadataSuspensionCoalescesDriveAndDeactivationStopsWork() async throws {
        let f = try await progressiveFixture(count: 5)
        let entered = expectation(description: "Discovery metadata awaits the host")
        let (release, signal) = AsyncStream<Void>.makeStream()
        defer { signal.finish() }
        let runway = RunwayController(configuration: .init(policyInputs: .init(safetyFactor: 1, releaseMarginSeconds: 0)!,
            consumptionSampleLimit: 2, replenishmentSampleLimit: 2)!)
        let driver = try FeedRunwayDriver(session: f.session, runway: runway, plan: f.plan, policy: f.policy,
            acquisition: f.acquisition, coordinator: f.coordinator,
            monotonicNow: { .init(seconds: ProcessInfo.processInfo.systemUptime)! },
            makeSegmentIdentity: { .init(segmentID: .init(), segmentSeed: 1, segmentCreatedAt: Date())! },
            prepare: Self.prepareDiscovery, selectedSourceCoverage: .init(selectedSourceCoverageFor: f.plan.context.key,
                editorialRevisionID: f.plan.revision.id),
            onDiscoveryPage: { _ in entered.fulfill(); for await _ in release { break } })
        let resources = FeedRunwayDriverResources(runway: .init(localWorkAllowed: true, examinedCandidateCapacity: 8,
            readyProbeBound: 4, readyProbeCeiling: 8, forwardAdvanceProbeBound: 8, reserveCards: 1)!,
            acquisition: .init(targetWorkCapacity: 2, batchCapacityPerNewExecution: 1,
                observationCapacityPerBatch: 8, byteCapacityPerBatch: 100_000)!, discoveryExaminedCapacity: 3)
        let activation = Task { try await driver.activateCurrentPresentation(resources: resources) }
        await fulfillment(of: [entered], timeout: 5)
        XCTAssertEqual(f.discovery.entries.count, 2)
        _ = try await driver.drive(resources: resources)
        XCTAssertEqual(f.discovery.entries.count, 2, "A reentrant caller cannot expand another page")
        await driver.deactivate()
        signal.yield(())
        _ = try await activation.value
        _ = try await driver.drive(resources: resources)
        XCTAssertEqual(f.discovery.entries.count, 2, "Deactivation also forbids later catalogue advancement")
        let snapshot = await f.session.currentPresentation()
        XCTAssertEqual(snapshot, f.initial)
        XCTAssertEqual(try PublicationStore(database: f.database).segments(editionID: f.edition).count, 1)
        let targets = try f.acquisition.eligibleTargets(for: f.plan.context)
        XCTAssertTrue(targets.allSatisfy { $0.checkpointRevision == 0 })
    }

    /// PD8-R1: a caller opportunity that coalesces into an in-flight drain still owns one catalogue page — the
    /// page is the caller's fact, never a conclusion the drain may reach by itself. Two opportunities here (the
    /// owning one and the coalesced one) and therefore exactly two pages: the drain passes between them earn none.
    @MainActor
    func testCoalescedCallerOpportunityStillOwnsItsCataloguePage() async throws {
        let f = try await progressiveFixture(count: 5)
        let pages = DiscoveryPageJournal()
        let entered = expectation(description: "The owning call holds its own catalogue page")
        let (release, signal) = AsyncStream<Void>.makeStream()
        defer { signal.finish() }
        let runway = RunwayController(configuration: .init(policyInputs: .init(safetyFactor: 1, releaseMarginSeconds: 0)!,
            consumptionSampleLimit: 2, replenishmentSampleLimit: 2)!)
        let driver = try FeedRunwayDriver(session: f.session, runway: runway, plan: f.plan, policy: f.policy,
            acquisition: f.acquisition, coordinator: f.coordinator,
            monotonicNow: { .init(seconds: ProcessInfo.processInfo.systemUptime)! },
            makeSegmentIdentity: { .init(segmentID: .init(), segmentSeed: 1, segmentCreatedAt: Date())! },
            prepare: Self.prepareDiscovery, onDiscoveryPage: { _ in
                guard pages.record() == 1 else { return }
                entered.fulfill()
                for await _ in release { break }
            })
        let resources = FeedRunwayDriverResources(runway: .init(localWorkAllowed: true, examinedCandidateCapacity: 8,
            readyProbeBound: 4, readyProbeCeiling: 8, forwardAdvanceProbeBound: 8, reserveCards: 1)!,
            acquisition: .init(targetWorkCapacity: 2, batchCapacityPerNewExecution: 1,
                observationCapacityPerBatch: 8, byteCapacityPerBatch: 100_000)!, discoveryExaminedCapacity: 3)
        let activation = Task { try await driver.activateCurrentPresentation(resources: resources) }
        await fulfillment(of: [entered], timeout: 5)
        XCTAssertEqual(pages.served, 1)
        let firstPage = f.discovery.entries.count
        XCTAssertGreaterThan(firstPage, 0, "The fixture must serve a first page")
        // An external opportunity arrives while the owning call is still inside its own page: it coalesces.
        _ = try await driver.drive(resources: resources)
        XCTAssertEqual(pages.served, 1, "A coalesced caller cannot examine a page while another owns the examination")
        signal.yield(())
        _ = try await activation.value
        XCTAssertEqual(pages.served, 2, "The opportunity that coalesced into the drain still owns its page")
        XCTAssertGreaterThan(f.discovery.entries.count, firstPage, "The coalesced opportunity reached the pool")
        let snapshot = await f.session.currentPresentation()
        XCTAssertEqual(snapshot, f.initial, "Discovery cannot move or admit the reader's position")
    }

    @MainActor
    func testStaleCallerBudgetIsNotInstalledIntoTheNextExecution() async throws {
        let f = try await progressiveFixture(count: 5)
        let pages = DiscoveryPageJournal(), media = MediaCallJournal()
        let (ownerRelease, ownerSignal) = AsyncStream<Void>.makeStream()
        defer { ownerSignal.finish() }
        let (staleRelease, staleSignal) = AsyncStream<Void>.makeStream()
        defer { staleSignal.finish() }
        let (pageRelease, pageSignal) = AsyncStream<Void>.makeStream()
        defer { pageSignal.finish() }
        let runway = RunwayController(configuration: .init(policyInputs: .init(safetyFactor: 1, releaseMarginSeconds: 0)!,
            consumptionSampleLimit: 2, replenishmentSampleLimit: 2)!)
        let driver = try FeedRunwayDriver(session: f.session, runway: runway, plan: f.plan, policy: f.policy,
            acquisition: f.acquisition, coordinator: f.coordinator,
            monotonicNow: { .init(seconds: ProcessInfo.processInfo.systemUptime)! },
            makeSegmentIdentity: { .init(segmentID: .init(), segmentSeed: 1, segmentCreatedAt: Date())! },
            prepare: Self.prepareDiscovery, selectedSourceCoverage: .init(selectedSourceCoverageFor: f.plan.context.key,
                editorialRevisionID: f.plan.revision.id),
            onDiscoveryPage: { _ in
                // Pages 1 and 2 belong to the owner; page 3 is the new execution, kept active here.
                if pages.record() == 3 { for await _ in pageRelease { break } }
            },
            makeMediaOpportunity: {
                let call = media.next()
                if call == 1 { for await _ in ownerRelease { break } }
                if call == 2 { for await _ in staleRelease { break } }
                return MediaPreparationOpportunity(waitSeconds: 0, startedAt: 0,
                    prepare: { _, _ in media.prepare(call) })
            })
        let resources = FeedRunwayDriverResources(runway: .init(localWorkAllowed: true, examinedCandidateCapacity: 8,
            readyProbeBound: 4, readyProbeCeiling: 8, forwardAdvanceProbeBound: 8, reserveCards: 1)!,
            acquisition: .init(targetWorkCapacity: 2, batchCapacityPerNewExecution: 1,
                observationCapacityPerBatch: 8, byteCapacityPerBatch: 100_000)!, discoveryExaminedCapacity: 3)

        let owner = Task { try await driver.activateCurrentPresentation(resources: resources) }
        var deadline = Date().addingTimeInterval(5)
        while media.callCount < 1, Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(media.callCount, 1)
        _ = try await driver.drive(resources: resources) // coalesces a caller and its page
        ownerSignal.yield(())
        _ = try await owner.value
        deadline = Date().addingTimeInterval(5)
        while media.callCount < 2, Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(media.callCount, 2, "the coalesced caller's budget is suspended")

        let next = Task { try await driver.drive(resources: resources) }
        deadline = Date().addingTimeInterval(5)
        while media.callCount < 3 || pages.served < 3, Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(media.callCount, 3)
        XCTAssertEqual(pages.served, 3, "the new execution is active on its page")

        // The old budget returns while the new execution owns the scope. Wait until that return is processed.
        let refreshesBefore = await driver.callerMediaRefreshCompletions
        staleSignal.yield(())
        deadline = Date().addingTimeInterval(5)
        while await driver.callerMediaRefreshCompletions == refreshesBefore, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        let refreshesAfter = await driver.callerMediaRefreshCompletions
        XCTAssertEqual(refreshesAfter, refreshesBefore + 1,
            "the stale return was processed by finishCallerMediaRefresh")
        media.clearPrepared()
        await driver.noteMediaReadinessChanged()
        pageSignal.yield(())
        _ = try? await next.value
        deadline = Date().addingTimeInterval(5)
        while media.preparedCalls.isEmpty, Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(media.preparedCalls.contains(2),
            "the stale call 2 budget must never be installed or used by the new execution")
        XCTAssertTrue(media.preparedCalls.contains(3), "the new execution uses its own budget")
    }

    @MainActor
    func testColdDiscoveryResumesAfterAnEmptyProfilePageUsingTheSameCoordinator() async throws {
        let url = try catalog()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ProgressiveDiscoveryURLProtocol.self]
        let transport = URLSession(configuration: config)
        addTeardownBlock { transport.invalidateAndCancel() }
        let context = FeedContext(request: .main), v = PolicyVersion(rawValue: 1)
        let revision = EditorialRevision(id: .init(), contextKey: context.key, catalogGeneration: .init(rawValue: 1),
            userSelectionVersion: v, eligibilityPolicyVersion: v, scoringPolicyVersion: v, sequencingPolicyVersion: v,
            exposurePolicyVersion: v, selectionSchemaVersion: .init(rawValue: 1))
        let plan = try XCTUnwrap(FeedPlan(context: context, revision: revision))
        let policy = ResolvedSelectionPolicy(contextKey: context.key, userSelectionVersion: v, eligibilityPolicyVersion: v,
            scoringPolicyVersion: v, sequencingPolicyVersion: v, exposurePolicyVersion: v,
            selectionSchemaVersion: revision.selectionSchemaVersion, eligibility: .selectedSources([]),
            scoring: .equal, sequencing: .recencyDescending, exposure: .excludePublishedMaterial)
        let discovery = ReaderDiscoveryTraversal(builder: ReaderDiscoveryBuilder(catalogURL: url),
            profile: .init(languages: ["en"], topicNodeKeys: ["topics/science"]), contextKey: context.key)
        let acquisition = try SyndicationAcquisitionSnapshot(database: database, registrations: [], session: transport,
            redirectCapacity: 0, discovery: discovery)
        let coordinator = acquisition.makeCoordinator()
        let session = FeedSession(publicationHistory: .init(database: database))
        let bootstrap = try ColdFeedBootstrap(session: session, plan: plan, policy: policy,
            acquisition: acquisition, coordinator: coordinator, prepare: Self.prepareDiscovery)
        let identity = ColdFeedPublicationIdentity(editionID: .init(), publicationSchemaVersion: .init(rawValue: 1),
            selectionSeed: 1, editionCreatedAt: Date(), segmentID: .init(), segmentSeed: 1,
            segmentCreatedAt: Date(), anchorPlacement: .top, checkpointedAt: Date())!
        let resources = ColdFeedBootstrapResources(localExaminedCapacity: 1,
            acquisition: .init(targetWorkCapacity: 1, batchCapacityPerNewExecution: 1,
                observationCapacityPerBatch: 8, byteCapacityPerBatch: 100_000)!)!
        let first = try await bootstrap.run(identity: identity, resources: resources, backwardCapacity: 0, forwardCapacity: 1)
        guard case .localWorkRemaining = first else { return XCTFail("A filtered page cannot declare the catalogue unavailable") }
        XCTAssertTrue(discovery.entries.isEmpty); XCTAssertFalse(discovery.exhausted)
        XCTAssertNil(try SessionStore(database: database).checkpoint())
        let second = try await bootstrap.run(identity: identity, resources: resources, backwardCapacity: 0, forwardCapacity: 1)
        guard case .published(let snapshot) = second else { return XCTFail("Later page must publish without resetting discovery") }
        XCTAssertEqual(snapshot.window.items.compactMap(\.title), ["Discovered"])
        XCTAssertEqual(discovery.entries.map(\.principal), ["https://science.en/feed"])
        let targets = try acquisition.eligibleTargets(for: context)
        XCTAssertEqual(targets.count, 1); XCTAssertEqual(targets.first?.checkpointRevision, 1)
    }

    func testDiscoveryDoesNotExpandSourceOrSearchScopes() throws {
        let builder = ReaderDiscoveryBuilder(catalogURL: try catalog())
        let discovery = ReaderDiscoveryTraversal(builder: builder, profile: .init(languages: ["pt"]),
            contextKey: .init(request: .main))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let transport = URLSession(configuration: .ephemeral)
        addTeardownBlock { transport.invalidateAndCancel() }
        let snapshot = try SyndicationAcquisitionSnapshot(database: database, registrations: [],
            session: transport, redirectCapacity: 0, discovery: discovery)
        XCTAssertNil(try snapshot.advanceDiscovery(for: FeedContext(request: .source(SourceID())), examinedCapacity: 3))
        XCTAssertNil(try snapshot.advanceDiscovery(for: FeedContext(request: .search(SearchContext(query: "Science")!)), examinedCapacity: 3))
        XCTAssertTrue(discovery.entries.isEmpty)

    }

    /// The pool a launch reads **beside** the walk — for a warm launch, the one it reads behind the reader's own
    /// window — is materialized as supply through the same owner an examined page goes through, and it does not
    /// move the walk's cursor. Two facts are the point: a source the authority revoked is not made supply again by
    /// a preview that names it, and adopting a preview is not evidence that the pages before it were examined.
    @MainActor
    func testAPoolReadBesideTheWalkBecomesSupplyWithoutMovingTheCursor() throws {
        let catalogURL = try catalog()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let transport = URLSession(configuration: .ephemeral)
        addTeardownBlock { transport.invalidateAndCancel() }
        let context = FeedContext(request: .main)
        // No language: the profile is a topic, so the catalogue's own first key is admitted and the walk's next
        // page is observable.
        let profile = ReaderDiscoveryProfile(topicNodeKeys: ["topics/science"])
        let traversal = ReaderDiscoveryTraversal(builder: ReaderDiscoveryBuilder(catalogURL: catalogURL),
            profile: profile, contextKey: context.key)
        let acquisition = try SyndicationAcquisitionSnapshot(database: database, registrations: [],
            session: transport, redirectCapacity: 0, discovery: traversal)

        let pool = try ReaderDiscoveryBuilder(catalogURL: catalogURL).pool(for: profile, limit: 50).entries
        let healthy = try XCTUnwrap(pool.first { $0.principal == "https://science.pt-two/feed" })
        let revoked = try XCTUnwrap(pool.first { $0.principal == "https://science.pt/feed" })
        // The authority revoked one of the two while the read was out.
        let target = try AcquisitionTargetAuthority(database: database).register(id: revoked.targetID,
            connectorKind: .syndication, authorizedSources: [revoked.source.id])
        _ = try AcquisitionTargetAuthority(database: database).revoke(id: target.id, expectedGeneration: target.generation)

        XCTAssertEqual(try acquisition.adoptDiscovered([revoked, healthy]).map(\.principal), [healthy.principal],
            "only what really became supply is reported back")

        let eligible = try acquisition.eligibleTargets(for: context)
        XCTAssertTrue(eligible.contains { $0.id == healthy.targetID },
            "the healthy source of the pool is acquirable without the walk having examined it")
        XCTAssertFalse(eligible.contains { $0.id == revoked.targetID },
            "a revoked source is not made supply again by a pool that names it")
        let base = ResolvedSelectionPolicy(contextKey: context.key, userSelectionVersion: .init(rawValue: 1),
            eligibilityPolicyVersion: .init(rawValue: 1), scoringPolicyVersion: .init(rawValue: 1),
            sequencingPolicyVersion: .init(rawValue: 1), exposurePolicyVersion: .init(rawValue: 1),
            selectionSchemaVersion: .init(rawValue: 1), eligibility: .selectedSources([SourceID()]),
            scoring: .equal, sequencing: .recencyDescending, exposure: .excludePublishedMaterial)
        guard case .selectedSources(let sources) = try acquisition.policyIncludingDiscovery(base).eligibility else {
            return XCTFail("Discovery preserves the selected-source policy")
        }
        XCTAssertTrue(sources.contains(healthy.source.id), "the pool's supply enters the effective policy")
        XCTAssertFalse(sources.contains(revoked.source.id))

        // The walk still examines the catalogue where it was: the first page is the catalogue's **first** records,
        // at positions 0 and 1 — not the ones a quality-ordered pool happens to start with.
        let walk = try XCTUnwrap(acquisition.advanceDiscovery(for: context, examinedCapacity: 2))
        XCTAssertEqual(walk.entries.map(\.principal).sorted(),
            ["https://both.xx/feed", "https://science.en/feed"],
            "adopting a pool is not evidence that the pages in between were examined")
        XCTAssertEqual(Set(traversal.entries.map(\.principal)),
            ["https://both.xx/feed", "https://science.en/feed", healthy.principal],
            "and the adopted page is retained beside the examined one")
    }

    nonisolated private static func prepareDiscovery(_ selection: SelectionResult) -> LocalPreparedPublication {
        .init(inputs: selection.orderedCandidates.map { candidate in
            .init(origin: .init(originRecordID: candidate.originRecordID, originRevisionID: candidate.originRevisionID,
                sourceID: candidate.sourceIDs.first, providerID: nil, sourceDisplayName: nil, providerDisplayName: nil),
                contentEntityID: nil, contentClusterID: nil, primaryAction: .localContentDetail, presentation: .textOnly)
        }, cardIDs: selection.orderedCandidates.map { _ in PublicationCardID() })
    }

    func testProgressivePagesReachBeyond120AndLegacyCeilingsWithoutDuplicates() throws {
        let url = try catalog(), queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            for n in 0..<250 {
                let key = String(format: "https://bulk%04d.test/feed", n)
                try db.execute(sql: """
                    INSERT INTO catalog_source (id, key, title, declared_url, request_url, media_kind, language, quality_score)
                    VALUES (?, ?, 'Bulk', ?, ?, 'text', 'pt', 99)
                    """, arguments: [1000 + n, key, key, key])
                for node in [2, 3] {
                    try db.execute(sql: "INSERT INTO catalog_placement (source_id, node_id, node_name, opml_file, sort_order) VALUES (?, ?, 'Topic', 'bulk', ?)",
                        arguments: [1000 + n, node, n])
                }
            }
        }
        let builder = ReaderDiscoveryBuilder(catalogURL: url, perTopicCeiling: 1, keyCeiling: 1)
        let profile = ReaderDiscoveryProfile(languages: ["pt"], topicNodeKeys: ["topics", "topics/science"])
        var cursor: ReaderDiscoveryCursor?
        var keys: [String] = []
        var examined = 0
        for _ in 0..<20 {
            let page = try builder.page(for: profile, after: cursor, examinedCapacity: 32)
            XCTAssertLessThanOrEqual(page.examinedCount, 32)
            keys += page.entries.map(\.principal)
            examined += page.examinedCount
            if page.exhausted { break }
            XCTAssertNotEqual(page.nextCursor, cursor)
            cursor = page.nextCursor
        }
        // 250 bulk sources plus the four base sources the catalogue places under the profile's topics in Portuguese
        // as text or audio. The English, language-less, other-topic and video rows are misses, not entries; the
        // video row is not even examined, since the pool never reads that kind (D10).
        XCTAssertEqual(keys.count, 254)
        XCTAssertEqual(Set(keys).count, 254, "no source is admitted twice across pages")
        XCTAssertTrue(keys.contains("https://science.pod/pod"),
            "the audio source is walked like any other: discovery is not a text-only internet")
        XCTAssertEqual(examined, 257, "Language and media misses consume examination capacity, not eligibility")
    }

    func testEmptyFilteredPageAdvancesAndCursorCannotCrossProfiles() throws {
        let builder = ReaderDiscoveryBuilder(catalogURL: try catalog())
        let profile = ReaderDiscoveryProfile(languages: ["pt"], topicNodeKeys: ["topics/science"])
        let first = try builder.page(for: profile, after: nil, examinedCapacity: 1)
        XCTAssertTrue(first.entries.isEmpty)
        XCTAssertFalse(first.exhausted)
        let cursor = try XCTUnwrap(first.nextCursor)
        var principals: [String] = []
        var after: ReaderDiscoveryCursor? = cursor
        for _ in 0..<10 {
            let page = try builder.page(for: profile, after: after, examinedCapacity: 1)
            principals += page.entries.map(\.principal)
            if page.exhausted { break }
            after = page.nextCursor
        }
        XCTAssertEqual(Set(principals), ["https://science.pod/pod", "https://science.pt-two/feed",
            "https://science.pt/feed"],
            "one-record pages still reach every candidate of the topic — audio beside text, never video")
        XCTAssertThrowsError(try builder.page(for: .init(languages: ["en"]), after: cursor, examinedCapacity: 1)) {
            XCTAssertEqual($0 as? ReaderDiscoveryError, .cursorScopeMismatch)
        }
        XCTAssertThrowsError(try ReaderDiscoveryBuilder(catalogURL: catalog()).page(for: profile,
            after: cursor, examinedCapacity: 1)) {
            XCTAssertEqual($0 as? ReaderDiscoveryError, .cursorScopeMismatch)
        }
        XCTAssertThrowsError(try builder.page(for: profile, after: nil, examinedCapacity: 0))
    }

    /// A profile of one topic and one language yields that topic's sources, in that language, as text **and**
    /// audio — and only those (D10). A source the catalogue does not define the language for is not discovered by
    /// a language-constrained profile: the pool must not invent relevance. The video source the fixture files in
    /// exactly this topic and language never enters the automatic pool, even though the catalogue rates it above
    /// every admitted source.
    func testAPoolIsTheTopicsSourcesInTheReadersLanguage() throws {
        let builder = ReaderDiscoveryBuilder(catalogURL: try catalog())
        let pool = try builder.pool(for: ReaderDiscoveryProfile(languages: ["pt"],
            topicNodeKeys: ["topics/science"]), limit: 10)
        XCTAssertEqual(pool.entries.map(\.principal),
            ["https://science.pod/pod", "https://science.pt/feed", "https://science.pt-two/feed"],
            "the topic's sources in the reader's language — audio beside text, ordered by the catalogue's own "
                + "quality, with the region form of the language accepted")
        XCTAssertFalse(pool.entries.contains { $0.principal == "https://science.video/feed" },
            "video stays out of the automatic pool even as the catalogue's highest-quality match")
    }

    /// Deterministic: the same profile gives the same pool, in the same order, every time.
    func testTheSameProfileAlwaysYieldsTheSamePool() throws {
        let builder = ReaderDiscoveryBuilder(catalogURL: try catalog())
        let profile = ReaderDiscoveryProfile(languages: ["pt"], topicNodeKeys: ["topics/science"])
        XCTAssertEqual(try builder.pool(for: profile, limit: 10).entries,
            try builder.pool(for: profile, limit: 10).entries)
    }

    /// No interests means no pool: the plain feed stays exactly the reader's own selection.
    func testAProfileThatNamesNothingDiscoversNothing() throws {
        let builder = ReaderDiscoveryBuilder(catalogURL: try catalog())
        XCTAssertTrue(try builder.pool(for: ReaderDiscoveryProfile(), limit: 10).isEmpty)
        // A language alone is a profile the catalogue can answer: every text **and** audio source in it, whatever
        // topic it is filed under — and still nothing the catalogue does not place in that language, nor any video.
        XCTAssertEqual(try builder.pool(for: ReaderDiscoveryProfile(languages: ["pt"], topicNodeKeys: []),
            limit: 10).entries.map(\.principal).sorted(),
            ["https://science.pod/pod", "https://science.pt-two/feed", "https://science.pt/feed",
                "https://sport.pt/feed"],
            "a language-only profile discovers text and audio alike, and never video")
    }

    /// A language the catalogue has nothing for yields an empty pool rather than another language's sources.
    func testALanguageWithNoSourcesYieldsNothing() throws {
        let builder = ReaderDiscoveryBuilder(catalogURL: try catalog())
        XCTAssertTrue(try builder.pool(for: ReaderDiscoveryProfile(languages: ["ja"],
            topicNodeKeys: ["topics/science"]), limit: 10).isEmpty)
    }

    /// The limit is a ceiling on the work, and it keeps the highest-quality sources regardless of kind: the audio
    /// podcast outranks the text source, and the video source the catalogue rates above both is never a candidate
    /// at all (D10).
    func testTheLimitIsRespectedAndKeepsQualityOrder() throws {
        let builder = ReaderDiscoveryBuilder(catalogURL: try catalog())
        let profile = ReaderDiscoveryProfile(languages: ["pt"], topicNodeKeys: ["topics"])
        let pool = try builder.pool(for: profile, limit: 1)
        XCTAssertEqual(pool.entries.map(\.principal), ["https://science.pod/pod"])
        XCTAssertEqual(pool.entries.count, 1, "the limit remains a ceiling")
        XCTAssertEqual(try builder.pool(for: profile, limit: 2).entries.map(\.principal),
            ["https://science.pod/pod", "https://science.pt/feed"],
            "quality orders the pool across kinds instead of exhausting text before audio")
    }

    /// F02's "menos desse assunto": a source the catalogue files **only** under the subject the reader asked for
    /// less of leaves the pool; a source that also covers something they want keeps its place, because one answer
    /// about a subject must not delete a source that serves two.
    func testAnExcludedSubjectLeavesThePoolWithoutTakingAlicesSourcesWithIt() throws {
        let builder = ReaderDiscoveryBuilder(catalogURL: try catalog())
        let wanted = try builder.pool(for: ReaderDiscoveryProfile(topicNodeKeys: ["topics"]), limit: 20)
        XCTAssertTrue(wanted.entries.map(\.principal).contains("https://sport.pt/feed"),
            "the fixture has to contain the source that the exclusion then removes")

        let excluded = try builder.pool(for: ReaderDiscoveryProfile(topicNodeKeys: ["topics"],
            excludedTopicNodeKeys: ["topics/sport"]), limit: 20)
        let principals = Set(excluded.entries.map(\.principal))
        XCTAssertFalse(principals.contains("https://sport.pt/feed"),
            "a source filed only under the subject asked for less of is not discovered")
        XCTAssertTrue(principals.contains("https://both.xx/feed"),
            "a source that is also filed under a wanted subject stays")
    }

    /// **D10**: discovery draws from text **and** audio sources. A pool that admitted only text handed the reader
    /// a text-only internet while the product promises "listen" (measured 2026-10-20: the pool default was
    /// `["text"]` while the shipped catalogue carries 23.446 audio sources). Video sources stay out of the
    /// automatic pool this round; an explicit override still decides its own set.
    func testTheDefaultPoolAdmitsTextAndAudioButNotVideo() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("discovery-kinds-\(UUID().uuidString).sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE catalog_node (id INTEGER PRIMARY KEY, key TEXT NOT NULL UNIQUE, parent_id INTEGER,
                    name TEXT NOT NULL, kind INTEGER NOT NULL, source_count INTEGER NOT NULL DEFAULT 0,
                    child_count INTEGER NOT NULL DEFAULT 0, language TEXT);
                CREATE TABLE catalog_source (id INTEGER PRIMARY KEY, key TEXT NOT NULL UNIQUE, title TEXT NOT NULL,
                    declared_url TEXT NOT NULL, request_url TEXT NOT NULL, display_host TEXT, media_kind TEXT NOT NULL,
                    language TEXT, site_url TEXT, description TEXT, tags TEXT, nature TEXT, activity TEXT,
                    latest_item_at TEXT, quality_score INTEGER, default_enabled INTEGER NOT NULL DEFAULT 1,
                    contact_email TEXT, contact_name TEXT, contact_source TEXT, contact_type TEXT);
                CREATE TABLE catalog_placement (id INTEGER PRIMARY KEY, source_id INTEGER NOT NULL, node_id INTEGER NOT NULL,
                    node_name TEXT NOT NULL, opml_file TEXT NOT NULL, sort_order INTEGER NOT NULL, title_override TEXT,
                    language_override TEXT, media_kind_override TEXT);
                INSERT INTO catalog_node (id, key, parent_id, name, kind) VALUES (1, 'topics', NULL, 'Topics', 0);
                INSERT INTO catalog_source (id, key, title, declared_url, request_url, media_kind, language, quality_score) VALUES
                    (10, 'https://text.pt/feed', 'Texto', 'https://text.pt/feed', 'https://text.pt/feed', 'text', 'pt', 90),
                    (11, 'https://audio.pt/pod', 'Podcast', 'https://audio.pt/pod', 'https://audio.pt/pod', 'audio', 'pt', 95),
                    (12, 'https://video.pt/feed', 'Vídeo', 'https://video.pt/feed', 'https://video.pt/feed', 'video', 'pt', 99);
                INSERT INTO catalog_placement (source_id, node_id, node_name, opml_file, sort_order) VALUES
                    (10, 1, 'Topics', 'x.opml', 0), (11, 1, 'Topics', 'x.opml', 1), (12, 1, 'Topics', 'x.opml', 2);
                """)
        }
        let profile = ReaderDiscoveryProfile(topicNodeKeys: ["topics"])
        let defaulted = try ReaderDiscoveryBuilder(catalogURL: url).pool(for: profile, limit: 20)
        let admitted = Set(defaulted.entries.map(\.principal))
        XCTAssertTrue(admitted.contains("https://text.pt/feed"), "text sources are discovered")
        XCTAssertTrue(admitted.contains("https://audio.pt/pod"),
            "audio sources are discovered: a text-only pool is the defect D10 names")
        XCTAssertFalse(admitted.contains("https://video.pt/feed"),
            "video stays out of the automatic pool this round")

        let explicit = try ReaderDiscoveryBuilder(catalogURL: url, mediaKinds: ["video"])
            .pool(for: profile, limit: 20)
        XCTAssertEqual(Set(explicit.entries.map(\.principal)), ["https://video.pt/feed"],
            "an explicit kind set is honoured as stated")
    }
}

/// Counts the catalogue pages one driver serves, so a test can hold the first one while an external
/// opportunity arrives and then see whether the coalesced opportunity still reaches the pool.
private final class DiscoveryPageJournal: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded = 0
    func record() -> Int { lock.withLock { recorded += 1; return recorded } }
    var served: Int { lock.withLock { recorded } }
}
private final class MediaCallJournal: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var prepared: [Int] = []
    func next() -> Int { lock.withLock { calls += 1; return calls } }
    func prepare(_ call: Int) { lock.withLock { prepared.append(call) } }
    func clearPrepared() { lock.withLock { prepared.removeAll() } }
    var callCount: Int { lock.withLock { calls } }
    var preparedCalls: [Int] { lock.withLock { prepared } }
}

private final class ProgressiveDiscoveryURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/rss+xml", "ETag": "progressive"])!
        let body = Data("<rss version=\"2.0\"><channel><title>Progressive</title><item><guid>\(url.absoluteString)</guid><title>Discovered</title></item></channel></rss>".utf8)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class OfflineDiscoveryURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}
