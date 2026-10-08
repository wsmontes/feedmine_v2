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
        let f = try fixture(); _ = try await f.session.restoreLocalPresentation(backwardCapacity:1,forwardCapacity:2)
        let scope = await f.session.currentRunwayScope()
        XCTAssertEqual(scope,.init(editionID:f.edition.id,contextKey:f.edition.contextKey,editorialRevisionID:f.edition.editorialRevision.id))
    }
    func test02ViewportPreservesRevisionFact() async throws {
        let f = try fixture(); _ = try await f.session.restoreLocalPresentation(backwardCapacity:1,forwardCapacity:2)
        _ = try await f.session.submitViewport(.init(anchor:.init(cardID:f.cards[0].id,placement:.top)))
        let scope = await f.session.currentRunwayScope()
        XCTAssertEqual(scope,.init(editionID:f.edition.id,contextKey:f.edition.contextKey,editorialRevisionID:f.edition.editorialRevision.id))
    }
    func test03RefreshAppendsLocalViewPreservingAnchorAndCapacities() async throws {
        let f = try fixture(),before = try await f.session.restoreLocalPresentation(backwardCapacity:1,forwardCapacity:1)
        try f.append()
        let stale = await f.session.currentPresentation(); XCTAssertEqual(stale,before)
        let after = try await f.session.refreshCurrentPresentation()
        XCTAssertEqual(after?.editionID,before?.editionID); XCTAssertEqual(after?.contextKey,before?.contextKey)
        XCTAssertEqual(after?.window.anchor,before?.window.anchor)
        XCTAssertEqual(after?.window.items.map(\.id),Array(f.cards[0...2]).map(\.id))
        let scope = await f.session.currentRunwayScope(); XCTAssertEqual(scope?.editorialRevisionID,f.edition.editorialRevision.id)
    }
    func test04RefreshDoesNotCheckpointEvenAfterMemoryLocalViewport() async throws {
        let f = try fixture(),store = SessionStore(database:f.database)
        _ = try await f.session.restoreLocalPresentation(backwardCapacity:1,forwardCapacity:2)
        let before = try store.checkpoint()
        _ = try await f.session.submitViewport(.init(anchor:.init(cardID:f.cards[0].id,placement:.top)))
        try f.append(); _ = try await f.session.refreshCurrentPresentation()
        XCTAssertEqual(try store.checkpoint(),before)
        let current = await f.session.currentPresentation(); XCTAssertEqual(current?.window.anchor.cardID,f.cards[0].id)
    }
    func test05UnrestoredScopeAndRefreshAreNil() async throws {
        let f = try fixture(),scope = await f.session.currentRunwayScope(),presentation = try await f.session.refreshCurrentPresentation()
        XCTAssertNil(scope); XCTAssertNil(presentation)
    }
}
