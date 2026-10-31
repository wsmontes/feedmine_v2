import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMinePublication
@testable import FeedMineRuntime

/// P0 / Issue #7: restore must not turn a saved historical cursor into
/// durable reader exposure before the corresponding visual admission exists.
final class RenderReadyCheckpointExposureContractTests: XCTestCase {
    private struct Fixture {
        let database: RuntimeDatabase
        let history: PublicationHistory
        let editionID: FeedEditionID
        let readyID: PublicationCardID
        let heroID: PublicationCardID
    }

    private func fixture(directory: URL, cursorAtMissingHero: Bool) throws -> Fixture {
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let version = PolicyVersion(rawValue: 1)
        let revision = EditorialRevision(
            id: EditorialRevisionID(), contextKey: .init(request: .main),
            catalogGeneration: .init(rawValue: 1),
            userSelectionVersion: version, eligibilityPolicyVersion: version,
            scoringPolicyVersion: version, sequencingPolicyVersion: version,
            exposurePolicyVersion: version, selectionSchemaVersion: .init(rawValue: 1))
        let edition = PublicationStore.EditionRecord(
            id: FeedEditionID(), editorialRevision: revision,
            publicationSchemaVersion: 1, selectionSeed: 1, createdAt: Date())
        let ready = PublicationStore.CardRecord(
            id: PublicationCardID(), originRecordID: OriginRecordID(),
            originRevisionID: OriginRevisionID(), sourceID: nil, providerID: nil,
            sourceDisplayName: nil, providerDisplayName: nil,
            contentEntityID: nil, contentClusterID: nil,
            title: "Ready text", primaryText: "Fully prepared",
            timestampValue: nil, timestampKind: nil,
            mediaKey: nil, mediaPixelWidth: nil, mediaPixelHeight: nil,
            mediaMimeType: nil, renderLayout: "textOnly",
            renderMediaAspectRatio: nil, primaryActionKind: nil,
            primaryActionReference: nil)
        let hero = PublicationStore.CardRecord(
            id: PublicationCardID(), originRecordID: OriginRecordID(),
            originRevisionID: OriginRevisionID(), sourceID: nil, providerID: nil,
            sourceDisplayName: nil, providerDisplayName: nil,
            contentEntityID: nil, contentClusterID: nil,
            title: "Undecodable hero", primaryText: "Saved history",
            timestampValue: nil, timestampKind: nil,
            mediaKey: "sha256:" + String(repeating: "0", count: 64),
            mediaPixelWidth: 600, mediaPixelHeight: 400,
            mediaMimeType: "image/png", renderLayout: "hero",
            renderMediaAspectRatio: 1.5, primaryActionKind: nil,
            primaryActionReference: nil)
        let cursorID = cursorAtMissingHero ? hero.id : ready.id
        try PublicationStore(database: database).createInitialEdition(
            edition,
            firstSegment: .init(id: FeedSegmentID(), editionID: edition.id,
                ordinal: 0, segmentSeed: 1, publicationSchemaVersion: 1,
                createdAt: Date(), cardIDs: [ready.id, hero.id]),
            cards: [ready, hero],
            initialCheckpoint: .init(editionID: edition.id, cardID: cursorID,
                anchorPlacement: "top", updatedAt: Date()))
        return Fixture(database: database, history: .init(database: database),
            editionID: edition.id, readyID: ready.id, heroID: hero.id)
    }

    func testProjectionOverflowCannotMarkCheckpointAsSeen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let f = try fixture(directory: directory, cursorAtMissingHero: false)
        let bounds = FeedPresentationBounds(backwardCapacity: 0, forwardCapacity: 1)
        let checkpoint = try SessionStore(database: f.database).checkpoint()
        XCTAssertNil(try PublicationStore(database: f.database).hiddenTail(editionID: f.editionID),
            "Control: publication exposure must be initially absent")

        XCTAssertThrowsError(try FeedSession.FeedCheckpointProjection.read(
            publicationHistory: f.history, imageDecoder: nil, bounds: bounds,
            sequenceID: UUID(), after: UInt64.max)) {
            XCTAssertEqual($0 as? FeedSessionError, .projectionOrderExhausted)
        }
        XCTAssertNil(try PublicationStore(database: f.database).hiddenTail(editionID: f.editionID),
            "No high-water mark can survive a rejected projection")
        XCTAssertEqual(try SessionStore(database: f.database).checkpoint(), checkpoint,
            "Failed projection must preserve the saved cursor")

        let accepted = try XCTUnwrap(FeedSession.FeedCheckpointProjection.read(
            publicationHistory: f.history, imageDecoder: nil, bounds: bounds,
            sequenceID: UUID(), after: 0))
        XCTAssertEqual(accepted.snapshot.window.anchor.cardID, f.readyID)
        XCTAssertNil(try PublicationStore(database: f.database).hiddenTail(editionID: f.editionID),
            "A decoded/text checkpoint is still only a prepared cursor, not a viewport")
        XCTAssertEqual(try SessionStore(database: f.database).checkpoint(), checkpoint,
            "Successful projection cannot rewrite durable position")

        // Warm launch uses the same projection function, so neither launch
        // path is allowed to synthesize visual exposure before first paint.
        let warm = try XCTUnwrap(FeedSession.warmStart(
            publicationHistory: f.history, imageDecoder: nil, bounds: bounds))
        XCTAssertEqual(warm.snapshot.window.anchor.cardID, f.readyID)
        XCTAssertNil(try PublicationStore(database: f.database).hiddenTail(editionID: f.editionID),
            "A warm-start snapshot alone is not evidence of a drawn cell")

        let session = FeedSession(publicationHistory: f.history)
        let restored = try await session.admitPresentation(.restore(bounds))
        XCTAssertEqual(restored?.window.anchor.cardID, f.readyID)
        XCTAssertNil(try PublicationStore(database: f.database).hiddenTail(editionID: f.editionID))

        // Runtime accepts a synthetic observation as a stand-in for the host's
        // geometry callback. This verifies the exposure transition, NOT that
        // the SwiftUI cell was physically measured on a device.
        let observed = try await session.submitViewport(
            .init(anchor: .init(cardID: f.readyID, placement: .top)))
        XCTAssertEqual(observed?.window.anchor.cardID, f.readyID)
        let lease = try XCTUnwrap(PublicationStore(database: f.database).hiddenTail(editionID: f.editionID))
        XCTAssertEqual(lease.highWaterCardID, f.readyID,
            "Only an admitted viewport observation may record this card as seen")
        XCTAssertEqual(try SessionStore(database: f.database).checkpoint(), checkpoint,
            "Exposure and durable reading cursor are separate operations")
    }

    func testWarmStartCannotMarkUndecodableSavedHeroAsSeen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let f = try fixture(directory: directory, cursorAtMissingHero: true)
        try f.history.markSeen(editionID: f.editionID, cardID: f.readyID)
        let checkpoint = try SessionStore(database: f.database).checkpoint()
        let decoder = try XCTUnwrap(PresentationImageDecoder(
            assetDirectory: directory.appendingPathComponent("Media"),
            heroMaxPixel: 64, thumbnailMaxPixel: 32))
        let bounds = FeedPresentationBounds(backwardCapacity: 1, forwardCapacity: 0)

        // WarmStart and actor restore share this checkpoint projector. The
        // visual plan must preserve the saved missing-image ID without
        // fabricating a physical scroll target or shifting the durable cursor.
        let warm = try XCTUnwrap(FeedSession.warmStart(
            publicationHistory: f.history, imageDecoder: decoder, bounds: bounds))
        let rail = FeedVisualRailIndex(snapshot: warm.snapshot)
        XCTAssertEqual(rail.logicalAnchorIndex, 1)
        XCTAssertNil(rail.visualAnchorID)
        let plan = try XCTUnwrap(FeedVisualWindowPlan(snapshot: warm.snapshot,
            center: 1, backward: 1, forward: 0))
        XCTAssertNil(plan.visualAnchorID)
        XCTAssertEqual(plan.segments, [
            .ready(range: 0..<1, cards: [warm.snapshot.window.items[0]]),
            .deferred(range: 1..<2, ids: [f.heroID])
        ], "A valid ready sibling and an unreadable saved hero are different physical runs")
        XCTAssertEqual(warm.snapshot.window.anchor.cardID, f.heroID)
        let lease = try XCTUnwrap(PublicationStore(database: f.database).hiddenTail(editionID: f.editionID))
        XCTAssertEqual(lease.highWaterCardID, f.readyID,
            "A durable cursor at a missing hero does not prove it was rendered")
        XCTAssertEqual(try SessionStore(database: f.database).checkpoint(), checkpoint,
            "Do not erase or rewrite the historical cursor to mask an absent bitmap")
    }
}
