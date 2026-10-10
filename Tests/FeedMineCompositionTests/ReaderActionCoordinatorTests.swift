import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence
import FeedMineComposition
import FeedMineUI

/// T9: what a card action resolves to. The acceptance this file carries is the plan's own: open, copy and share
/// use **the occurrence's** frozen target even when the article has changed since, and an action a card does not
/// carry is reported as unavailable rather than replaced by an invented fallback.
final class ReaderActionCoordinatorTests: XCTestCase {
    /// The last edition the helper published, so a test can append a later segment to it.
    private var lastEdition = FeedEditionID()

    /// A card record built here, test-only: the same frozen fields the publication pipeline writes.
    private func card(id: PublicationCardID = PublicationCardID(), reference: String?,
        kind: String? = "externalURL", mime: String? = nil, title: String? = "Título",
        originRecordID: OriginRecordID = OriginRecordID(),
        originRevisionID: OriginRevisionID = OriginRevisionID()) -> PublicationStore.CardRecord {
        .init(id: id, originRecordID: originRecordID, originRevisionID: originRevisionID,
            sourceID: nil, providerID: nil, sourceDisplayName: "Fonte", providerDisplayName: nil,
            contentEntityID: nil, contentClusterID: nil, title: title, primaryText: " texto ",
            timestampValue: nil, timestampKind: nil, mediaKey: " ", mediaPixelWidth: 300,
            mediaPixelHeight: 200, mediaMimeType: mime, renderLayout: "hero", renderMediaAspectRatio: 1.0,
            primaryActionKind: kind, primaryActionReference: reference)
    }

    private var editionID: FeedEditionID { lastEdition }

    private func published(_ cards: [PublicationStore.CardRecord]) throws -> (RuntimeDatabase, PublicationStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let database = try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
        let store = PublicationStore(database: database)
        let revision = EditorialRevision(id: EditorialRevisionID(), contextKey: ContextKey(request: .main),
            catalogGeneration: .init(rawValue: 1), userSelectionVersion: PolicyVersion(rawValue: 1),
            eligibilityPolicyVersion: PolicyVersion(rawValue: 2), scoringPolicyVersion: PolicyVersion(rawValue: 1),
            sequencingPolicyVersion: PolicyVersion(rawValue: 2), exposurePolicyVersion: PolicyVersion(rawValue: 2),
            selectionSchemaVersion: .init(rawValue: 1))
        let edition = PublicationStore.EditionRecord(id: FeedEditionID(), editorialRevision: revision,
            publicationSchemaVersion: 1, selectionSeed: UInt64.max, createdAt: Date(timeIntervalSince1970: 1))
        let segment = PublicationStore.SegmentRecord(id: FeedSegmentID(), editionID: edition.id, ordinal: 0,
            segmentSeed: UInt64.max, publicationSchemaVersion: 1, createdAt: Date(timeIntervalSince1970: 2),
            cardIDs: cards.map(\.id))
        try store.createEdition(edition, firstSegment: segment, cards: cards)
        lastEdition = edition.id
        return (database, store)
    }

    /// The occurrence's own target, for open, copy and share alike.
    func testOpenCopyAndShareUseTheOccurrencesFrozenTarget() async throws {
        let card = card(reference: "https://example.com/artigo")
        let (database, _) = try published([card])
        let coordinator = ReaderActionCoordinator(database: database)
        let url = try XCTUnwrap(URL(string: "https://example.com/artigo"))
        let opened = try await coordinator.perform(.open, cardID: card.id)
        XCTAssertEqual(opened, .externalURL(url))
        // "View Source" is the source's page, not the article's: the app resolves it through the catalog, and
        // the coordinator refuses to answer with the article's URL.
        await XCTAssertThrowsActionError(try await coordinator.perform(.viewSource, cardID: card.id))
        let copied = try await coordinator.perform(.copyLink, cardID: card.id)
        XCTAssertEqual(copied, .copiedText("https://example.com/artigo"))
        let share = try await coordinator.perform(.share, cardID: card.id)
        guard case .share(let payload) = share else { return XCTFail("share resolves to a payload") }
        XCTAssertEqual(payload.url, url)
        XCTAssertEqual(payload.title, "Título")
        XCTAssertEqual(payload.text, "https://example.com/artigo", "V1 shared the link itself")
        XCTAssertEqual(payload.subject, "Título · Fonte")
    }

    /// The same card, after the article it came from was edited: the card keeps its own reference.
    func testAnEditedArticleDoesNotChangeWhatACardOpens() async throws {
        let origin = OriginRecordID()
        let first = card(reference: "https://example.com/v1", originRecordID: origin)
        let second = card(reference: "https://example.com/v2", originRecordID: origin)
        let (database, store) = try published([first])
        // A later *edition* publishes the same origin under a new revision and a new target: the canonical
        // article moved on, and the earlier card is still published history.
        let firstEdition = try XCTUnwrap(try store.edition(id: editionID))
        let later = PublicationStore.EditionRecord(id: FeedEditionID(),
            editorialRevision: firstEdition.editorialRevision, publicationSchemaVersion: 1,
            selectionSeed: UInt64.max, createdAt: Date(timeIntervalSince1970: 3))
        let segment = PublicationStore.SegmentRecord(id: FeedSegmentID(), editionID: later.id, ordinal: 0,
            segmentSeed: UInt64.max, publicationSchemaVersion: 1, createdAt: Date(timeIntervalSince1970: 3),
            cardIDs: [second.id])
        try store.createEdition(later, firstSegment: segment, cards: [second])
        let coordinator = ReaderActionCoordinator(database: database)
        let firstTarget = try await coordinator.perform(.open, cardID: first.id)
        XCTAssertEqual(firstTarget, .externalURL(URL(string: "https://example.com/v1")!),
            "the first occurrence opens the target it was published with")
        let secondTarget = try await coordinator.perform(.open, cardID: second.id)
        XCTAssertEqual(secondTarget, .externalURL(URL(string: "https://example.com/v2")!))
    }

    /// No action is ever invented: a card the pipeline published without an external target says so, and an
    /// unusable reference cannot even be published (the store refuses it), so the coordinator never has to
    /// guess about one.
    func testMissingActionsAreReportedAndUnusableOnesCannotBePublished() async throws {
        let withoutTarget = card(reference: nil, kind: nil)
        let (database, store) = try published([withoutTarget])
        let coordinator = ReaderActionCoordinator(database: database)
        await XCTAssertThrowsActionError(try await coordinator.perform(.open, cardID: withoutTarget.id))
        // A card cannot be published claiming an external target and carrying none: the store refuses it, so
        // the coordinator's "unusable reference" branch exists for a card that could not exist.
        let declaredWithoutReference = card(reference: nil, kind: "externalURL")
        let edition = PublicationStore.EditionRecord(id: FeedEditionID(),
            editorialRevision: try XCTUnwrap(try store.edition(id: editionID)).editorialRevision,
            publicationSchemaVersion: 1, selectionSeed: UInt64.max,
            createdAt: Date(timeIntervalSince1970: 9))
        let segment = PublicationStore.SegmentRecord(id: FeedSegmentID(), editionID: edition.id, ordinal: 0,
            segmentSeed: UInt64.max, publicationSchemaVersion: 1, createdAt: Date(timeIntervalSince1970: 9),
            cardIDs: [declaredWithoutReference.id])
        XCTAssertThrowsError(try store.createEdition(edition, firstSegment: segment,
            cards: [declaredWithoutReference])) { error in
            XCTAssertEqual(error as? PublicationStoreError, .invalidRepresentation("action URL"))
        }
        // A card that does not exist is not a card without a target.
        do {
            _ = try await coordinator.perform(.open, cardID: PublicationCardID())
            XCTFail("a missing card is reported")
        } catch {
            XCTAssertEqual(error as? ReaderActionError, .cardNotFound)
        }
        // The two state-changing actions are the host's, and asking this coordinator for them is refused.
        for action in [ReaderCardAction.save, .addSourceToCollection] {
            do {
                _ = try await coordinator.perform(action, cardID: withoutTarget.id)
                XCTFail("\(action) is not a target-producing action")
            } catch {
                XCTAssertEqual(error as? ReaderActionError, .actionUnavailable(action))
            }
        }
    }

    /// Media: the pipeline states a playable card with its own action kind (`mediaPlayback`, validated with a
    /// URL by `PublicationStore`), so the action resolves exactly for the cards marked that way and for no
    /// others. **Recorded gap:** today's syndication keeps image enclosures only, so no real card carries this
    /// kind yet — the action is honest about the card it is given, and the pipeline that produces such a card is
    /// its own delivery (PORT_LOG, T9).
    func testMediaResolvesForTheKindThePipelineMarksAndNoOther() async throws {
        let playable = card(reference: "https://cdn.example/ep.mp3", kind: "mediaPlayback", mime: "audio/mpeg")
        let article = card(reference: "https://example.com/artigo", kind: "externalURL", mime: nil)
        let local = card(reference: nil, kind: "localContentDetail", mime: nil)
        let (database, _) = try published([playable, article, local])
        let coordinator = ReaderActionCoordinator(database: database)
        let resolved = try await coordinator.perform(.openMedia, cardID: playable.id)
        guard case .media(let target) = resolved else { return XCTFail("a playable card resolves its media") }
        XCTAssertEqual(target.url, URL(string: "https://cdn.example/ep.mp3"))
        XCTAssertEqual(target.mimeType, "audio/mpeg")
        XCTAssertEqual(target.title, "Título")
        await XCTAssertThrowsActionError(try await coordinator.perform(.openMedia, cardID: article.id))
        await XCTAssertThrowsActionError(try await coordinator.perform(.openMedia, cardID: local.id))
        // An article's own action is the external one, and a local-content card opens nothing external.
        await XCTAssertThrowsActionError(try await coordinator.perform(.open, cardID: local.id))
        let opened = try await coordinator.perform(.open, cardID: article.id)
        XCTAssertEqual(opened, .externalURL(URL(string: "https://example.com/artigo")!))
    }

    private func XCTAssertThrowsActionError(_ expression: @autoclosure () async throws -> ReaderActionTarget,
        file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await expression()
            XCTFail("expected a reported action error", file: file, line: line)
        } catch let error as ReaderActionError {
            switch error {
            case .actionUnavailable, .unusableReference: break
            case .cardNotFound: XCTFail("a present card is not a missing one", file: file, line: line)
            }
        } catch { XCTFail("unexpected error: \(error)", file: file, line: line) }
    }
}
