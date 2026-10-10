import Foundation
import XCTest
import FeedMineDomain
@testable import FeedMinePersistence
@testable import FeedMinePublication
import FeedMineRuntime

@MainActor
final class FeedSessionRunwayTests: XCTestCase {
    private struct Fixture {
        let database: RuntimeDatabase
        let edition: FeedEdition
        let cards: [PublishedCard]
        let session: FeedSession
        func append() throws {
            let segment = FeedSegment(id:FeedSegmentID(),editionID:edition.id,ordinal:1,segmentSeed:2,
                publicationSchemaVersion:edition.publicationSchemaVersion,createdAt:edition.createdAt,cardIDs:[cards[2].id,cards[3].id])!
            let values = try PublicationPersistenceMapping.records(segment:segment,cards:Array(cards[2...3]))
            try PublicationStore(database:database).appendSegment(values.0,cards:values.1)
        }
    }
    private func fixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at:root) }
        let database = try RuntimeDatabase(location:.init(directory:root)),edition = WarmPresentationFixture.edition()
        let cards = try (0..<4).map { try WarmPresentationFixture.card(layout:.textOnly,action:nil,title:"card-\($0)") }
        let segment = FeedSegment(id:FeedSegmentID(),editionID:edition.id,ordinal:0,segmentSeed:1,
            publicationSchemaVersion:edition.publicationSchemaVersion,createdAt:edition.createdAt,cardIDs:Array(cards[0...1]).map(\.id))!
        let values = try PublicationPersistenceMapping.records(segment:segment,cards:Array(cards[0...1]))
        try PublicationStore(database:database).createEdition(PublicationPersistenceMapping.record(edition),firstSegment:values.0,cards:values.1)
        try PublicationHistory(database:database).saveCursor(.init(editionID:edition.id,anchor:.init(cardID:cards[1].id,placement:.center)),updatedAt:Date(timeIntervalSince1970:20))
        return .init(database:database,edition:edition,cards:cards,session:FeedSession(publicationHistory:.init(database:database)))
    }
    func test01CurrentScopeAfterRestore() async throws {
        let f = try fixture(); _ = try await f.session.admitPresentation(.restore(.init(backwardCapacity: 1, forwardCapacity: 2)))
        let scope = await f.session.currentRunwayScope()
        XCTAssertEqual(scope,.init(editionID:f.edition.id,contextKey:f.edition.contextKey,editorialRevisionID:f.edition.editorialRevision.id))
    }
    func test02ViewportPreservesRevisionFact() async throws {
        let f = try fixture(); _ = try await f.session.admitPresentation(.restore(.init(backwardCapacity: 1, forwardCapacity: 2)))
        _ = try await f.session.submitViewport(.init(anchor:.init(cardID:f.cards[0].id,placement:.top)))
        let scope = await f.session.currentRunwayScope()
        XCTAssertEqual(scope,.init(editionID:f.edition.id,contextKey:f.edition.contextKey,editorialRevisionID:f.edition.editorialRevision.id))
    }
    func test03StationaryPreparationKeepsAdmittedListAndGrowsReserve() async throws {
        let f = try fixture()
        let bounds = FeedPresentationBounds(backwardCapacity: 1, forwardCapacity: 1)
        let before = try await f.session.admitPresentation(.initial(bounds))
        let reservedBefore = try readyAhead(f)
        try f.append()
        // Production extends the reserve. The reader did not move, so the admitted list is untouched:
        // this is the defect the plan removes (analysis §2).
        let stale = await f.session.currentPresentation(); XCTAssertEqual(stale, before)
        XCTAssertGreaterThan(try readyAhead(f), reservedBefore)
        let scope = await f.session.currentRunwayScope(); XCTAssertEqual(scope?.editorialRevisionID, f.edition.editorialRevision.id)
    }
    func test04StationaryViewportObservationChangesNeitherListNorCheckpoint() async throws {
        let f = try fixture(), store = SessionStore(database: f.database)
        let bounds = FeedPresentationBounds(backwardCapacity: 1, forwardCapacity: 2)
        let admitted = try await f.session.admitPresentation(.initial(bounds))
        let before = try store.checkpoint()
        let current = try await f.session.submitViewport(.init(anchor: .init(cardID: f.cards[0].id, placement: .top)))
        XCTAssertEqual(current?.window.items, admitted?.window.items)
        try f.append()
        let afterProduction = await f.session.currentPresentation()
        XCTAssertEqual(afterProduction?.window.items, admitted?.window.items)
        XCTAssertEqual(try store.checkpoint(), before)
        XCTAssertEqual(afterProduction?.window.anchor.cardID, f.cards[0].id)
    }
    func test05RecoveryInstallsTheCheckpointForASessionWithoutPresentation() async throws {
        let f = try fixture(), scope = await f.session.currentRunwayScope()
        // No presentation is active, so recovery is the only path that may install one.
        XCTAssertNil(scope)
        let presentation = try await f.session.admitPresentation(.restore(
            .init(backwardCapacity: 1, forwardCapacity: 1)))
        XCTAssertEqual(presentation?.window.anchor.cardID, f.cards[1].id)
        let admittedScope = await f.session.currentRunwayScope()
        XCTAssertNotNil(admittedScope)
    }

    /// Committed cards after the anchor, as an integer for comparisons.
    private func readyAhead(_ f: Fixture, anchor: PublicationCardID? = nil) throws -> Int {
        let anchorCard = anchor ?? f.cards[1].id
        let facts = try PublicationHistory(database: f.database).readyAhead(editionID: f.edition.id,
            anchorCardID: anchorCard, probeBound: 64)
        switch facts.amount {
        case .exact(let count): return count
        case .atLeast(let bound): return bound
        }
    }
}
