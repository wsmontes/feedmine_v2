import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
@testable import FeedMinePublication

final class PublicationRunwayFactsTests: XCTestCase {
    private func location() -> RuntimeDatabaseLocation {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return RuntimeDatabaseLocation(directory: root)
    }

    private func persist(_ edition: FeedEdition, _ cards: [PublishedCard], in db: RuntimeDatabase) throws {
        let store = PublicationStore(database: db)
        let firstCards = Array(cards.prefix(2)), lastCards = Array(cards.dropFirst(2))
        let first = try PublicationPersistenceMapping.records(segment: RestoreFixture.segment(edition, cards: firstCards, ordinal: 0), cards: firstCards)
        try store.createEdition(PublicationPersistenceMapping.record(edition), firstSegment: first.0, cards: first.1)
        let second = try PublicationPersistenceMapping.records(segment: RestoreFixture.segment(edition, cards: lastCards, ordinal: 1), cards: lastCards)
        try store.appendSegment(second.0, cards: second.1)
    }

    func testSemanticReadyAndAdvancePreserveCommittedFactsAfterReopen() throws {
        let loc = location(), edition = RestoreFixture.edition()
        let c = try (0..<5).map { try RestoreFixture.card(index: $0) }
        weak var closed: RuntimeDatabase?
        do {
            let db = try RuntimeDatabase(location: loc); closed = db
            try persist(edition, c, in: db)
        }
        XCTAssertNil(closed)
        for _ in 0..<2 {
            let history = PublicationHistory(database: try RuntimeDatabase(location: loc))
            let exact = try history.readyAhead(editionID: edition.id, anchorCardID: c[1].id, probeBound: 3)
            XCTAssertEqual(exact.editionID, edition.id); XCTAssertEqual(exact.anchorCardID, c[1].id)
            XCTAssertEqual(exact.observedTailCardID, c[4].id); XCTAssertEqual(exact.amount, .exact(3))
            XCTAssertEqual(try history.readyAhead(editionID: edition.id, anchorCardID: c[1].id, probeBound: 2).amount, .atLeast(2))
            XCTAssertEqual(try history.readyAhead(editionID: edition.id, anchorCardID: c[4].id, probeBound: 1).amount, .exact(0))
            for (from,to,bound,want) in [(0,0,1,PublicationAdvance.same), (3,1,1,.backward), (1,2,1,.forwardExact(1)), (0,4,4,.forwardExact(4)), (0,4,2,.forwardBeyondProbe(2))] {
                let result = try history.forwardAdvance(editionID: edition.id, fromCardID: c[from].id, toCardID: c[to].id, probeBound: bound)
                XCTAssertEqual(result.editionID, edition.id); XCTAssertEqual(result.fromCardID, c[from].id)
                XCTAssertEqual(result.toCardID, c[to].id); XCTAssertEqual(result.advance, want)
            }
            XCTAssertThrowsError(try history.readyAhead(editionID: edition.id, anchorCardID: c[0].id, probeBound: 0)) { XCTAssertEqual($0 as? PublicationStoreError, .invalidCapacity) }
            XCTAssertThrowsError(try history.forwardAdvance(editionID: edition.id, fromCardID: c[0].id, toCardID: c[1].id, probeBound: Int.max)) { XCTAssertEqual($0 as? PublicationStoreError, .invalidCapacity) }
        }
    }

    func testHeadReconsiderationExposurePreservesRequestAndExactSubsetAfterCloseReopen() throws {
        let loc = location(), edition = RestoreFixture.edition()
        let c = try (0..<4).map { try RestoreFixture.card(index: $0) }
        let a = c[0].origin.originRevisionID, b = c[1].origin.originRevisionID, n = OriginRevisionID()
        let request = [n,a,b]
        do {
            let db = try RuntimeDatabase(location: loc)
            try persist(edition, c, in: db)
            let facts = try PublicationHistory(database: db).exposure(editionID: edition.id, revisionIDs: request)
            XCTAssertEqual(facts.observedTailCardID, c[3].id); XCTAssertEqual(facts.requestedRevisionIDs, request); XCTAssertEqual(facts.publishedRevisionIDs, [a,b])
        }
        let history = PublicationHistory(database: try RuntimeDatabase(location: loc))
        let facts = try history.exposure(editionID: edition.id, revisionIDs: request)
        XCTAssertEqual(facts.editionID, edition.id); XCTAssertEqual(facts.requestedRevisionIDs, request)
        XCTAssertEqual(facts.publishedRevisionIDs, [a,b]); XCTAssertFalse(facts.publishedRevisionIDs.contains(n))
        XCTAssertTrue(facts.publishedRevisionIDs.isSubset(of: Set(facts.requestedRevisionIDs)))
        XCTAssertThrowsError(try history.exposure(editionID: edition.id, revisionIDs: [a,a])) { XCTAssertEqual($0 as? PublicationHistoryError, .invalidExposureRequest) }
        let empty = try history.exposure(editionID: edition.id, revisionIDs: [])
        XCTAssertEqual(empty.observedTailCardID, c[3].id); XCTAssertEqual(empty.requestedRevisionIDs, []); XCTAssertEqual(empty.publishedRevisionIDs, [])
        XCTAssertThrowsError(try history.exposure(editionID: FeedEditionID(), revisionIDs: [])) { XCTAssertEqual($0 as? PublicationStoreError, .missingEdition) }
    }
    func testSemanticExposureTailChangesOnlyInNewSnapshotAfterAppend() throws {
        let loc = location(), edition = RestoreFixture.edition()
        let c = try (0..<4).map { try RestoreFixture.card(index: $0) }
        let db = try RuntimeDatabase(location: loc)
        try persist(edition,c,in: db)
        let history = PublicationHistory(database: db), old = try history.exposure(editionID: edition.id,revisionIDs: [])
        let next = try RestoreFixture.card(index: 0)
        let records = try PublicationPersistenceMapping.records(segment: RestoreFixture.segment(edition,cards: [next],ordinal: 2),cards: [next])
        try PublicationStore(database: db).appendSegment(records.0,cards: records.1)
        XCTAssertEqual(old.observedTailCardID,c[3].id)
        XCTAssertEqual(try history.exposure(editionID: edition.id,revisionIDs: []).observedTailCardID,next.id)
    }

}
