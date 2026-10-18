import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineAcquisition
import FeedMineComposition

/// A and D, spec "Estabilidade de coleta e UI": the launch's parallelism budget and the composition-side
/// ordering of eligible targets.
final class CollectionLaunchAndOrderingTests: XCTestCase {
    // MARK: - A: launch settings

    func testLaunchSettingsDefaultIsSpecsFortyEightAndConcurrencyIsConservativelyCapped() {
        let defaults = CollectionLaunchSettings()
        XCTAssertEqual(defaults.initialParallelism, 48)
        XCTAssertEqual(defaults.targetWorkCapacity, 48, "the planner may name the spec's initial parallelism")
        XCTAssertEqual(defaults.concurrentTargetLimit, 8,
            "the socket ceiling stays conservative even with a large configured value")

        XCTAssertEqual(CollectionLaunchSettings(initialParallelism: 2).concurrentTargetLimit, 2)
        XCTAssertEqual(CollectionLaunchSettings(initialParallelism: 1).concurrentTargetLimit, 1)
        XCTAssertEqual(CollectionLaunchSettings(initialParallelism: 1_000).concurrentTargetLimit, 8)
        XCTAssertEqual(CollectionLaunchSettings(initialParallelism: -5).initialParallelism, 0)
        XCTAssertEqual(CollectionLaunchSettings(initialParallelism: -5).concurrentTargetLimit, 1)
    }

    // MARK: - D: ordering

    private func target() -> AcquisitionTarget {
        AcquisitionTarget(id: AcquisitionTargetID(), connectorKind: .syndication, generation: 1,
            state: .enabled, checkpointRevision: 0, checkpoint: nil)!
    }

    func testOrderingPutsHighQualitySourceBeforeLowQualityAndKeepsSuppliedOrderWithoutSignals() {
        let low = target(), high = target(), unknown = target()
        let lowSource = SourceID(), highSource = SourceID(), unknownSource = SourceID()
        let sources: [AcquisitionTargetID: [SourceID]] = [
            low.id: [lowSource], high.id: [highSource], unknown.id: [unknownSource],
        ]
        let signals: [SourceID: AcquisitionTargetSignal] = [
            lowSource: .init(catalogueQualityScore: 35, catalogueActivity: "dormant"),
            highSource: .init(catalogueQualityScore: 95, catalogueActivity: "prolific"),
        ]
        let ordered = AcquisitionTargetOrdering.ordered([low, high, unknown],
            sourcesByTarget: sources, signals: signals)
        XCTAssertEqual(ordered.map(\.id), [high.id, low.id, unknown.id],
            "a high-quality prolific source is requested first; a source with no evidence follows")

        // The fallback: no signals at all is exactly the supplied order, never an invented ranking.
        XCTAssertEqual(AcquisitionTargetOrdering.ordered([low, high, unknown],
            sourcesByTarget: sources, signals: [:]).map(\.id), [low.id, high.id, unknown.id])
        XCTAssertEqual(AcquisitionTargetOrdering.ordered([low, high, unknown]).map(\.id),
            [low.id, high.id, unknown.id])
    }

    func testOrderingIsStableForEqualScoresAndCountsMeasuredLatency() {
        let first = target(), second = target(), third = target()
        let a = SourceID(), b = SourceID(), c = SourceID()
        let sources = [first.id: [a], second.id: [b], third.id: [c]]
        let equal = AcquisitionTargetOrdering.ordered([first, second, third],
            sourcesByTarget: sources,
            signals: [a: .init(catalogueQualityScore: 80), b: .init(catalogueQualityScore: 80),
                c: .init(catalogueQualityScore: 80)])
        XCTAssertEqual(equal.map(\.id), [first.id, second.id, third.id], "equal scores keep supplied order")

        let latency = AcquisitionTargetOrdering.ordered([third, first],
            sourcesByTarget: [third.id: [c], first.id: [a]],
            signals: [a: .init(catalogueQualityScore: 80, measuredLatencySeconds: 0.1),
                c: .init(catalogueQualityScore: 80, measuredLatencySeconds: 4)])
        XCTAssertEqual(latency.map(\.id), [first.id, third.id],
            "the same quality with a lower measured latency ranks first")
    }

    // MARK: - D: the wiring, on the real snapshot

    private func registration(_ target: AcquisitionTarget, source: SourceID, endpoint: URL) -> SyndicationTargetRegistration {
        let binding = SourceBinding(id: SourceBindingID(), sourceID: source,
            externalPrincipal: .init(connectorKind: .syndication, namespace: "test",
                value: "principal-\(source.rawValue.uuidString)", role: .principal),
            aliases: [], generation: 1, state: .enabled)!
        return .init(targetID: target.id, targetGeneration: target.generation, endpoint: endpoint,
            bindings: [binding])!
    }

    func testSnapshotOrdersEligibleTargetsByCatalogueSignalsAndFallsBackToRegistrationOrder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let db = try RuntimeDatabase(location: .init(directory: root))
        let authority = AcquisitionTargetAuthority(database: db)
        let lowSource = SourceID(), highSource = SourceID()
        let low = try authority.register(id: AcquisitionTargetID(), connectorKind: .syndication,
            authorizedSources: [lowSource])
        let high = try authority.register(id: AcquisitionTargetID(), connectorKind: .syndication,
            authorizedSources: [highSource])
        // Supplied order: low first. The catalogue says otherwise.
        let registrations = [registration(low, source: lowSource, endpoint: URL(string: "https://low.test/feed")!),
            registration(high, source: highSource, endpoint: URL(string: "https://high.test/feed")!)]
        let context = FeedContext(request: .main)

        func ordered(_ signals: [SourceID: AcquisitionTargetSignal]) throws -> [AcquisitionTargetID] {
            let configuration = URLSessionConfiguration.ephemeral
            let session = URLSession(configuration: configuration)
            addTeardownBlock { session.invalidateAndCancel() }
            let snapshot = try SyndicationAcquisitionSnapshot(database: db, registrations: registrations,
                session: session, redirectCapacity: 0, targetSignals: signals)
            return try snapshot.eligibleTargets(for: context).map(\.id)
        }

        XCTAssertEqual(try ordered([lowSource: .init(catalogueQualityScore: 40, catalogueActivity: "quiet"),
            highSource: .init(catalogueQualityScore: 95, catalogueActivity: "prolific")]), [high.id, low.id],
            "the composition supplies the ordered targets; the planner never reorders")
        XCTAssertEqual(try ordered([:]), [low.id, high.id],
            "no catalogue evidence keeps the registration order")
    }
}
