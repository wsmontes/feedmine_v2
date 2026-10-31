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

    func testProjectionOverflowCannotMarkCheckpointAsSeen() throws {
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
        let lease = try XCTUnwrap(PublicationStore(database: f.database).hiddenTail(editionID: f.editionID))
        XCTAssertEqual(lease.highWaterCardID, f.readyID,
            "A successful ready-text checkpoint can record exposure normally")
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

        // WarmStart and actor restore use this same checkpoint projector.
        _ = try FeedSession.warmStart(
            publicationHistory: f.history, imageDecoder: decoder, bounds: bounds)
        let lease = try XCTUnwrap(PublicationStore(database: f.database).hiddenTail(editionID: f.editionID))
        XCTAssertEqual(lease.highWaterCardID, f.readyID,
            "A durable cursor at a missing hero does not prove it was rendered")
        XCTAssertEqual(try SessionStore(database: f.database).checkpoint(), checkpoint,
            "Do not erase or rewrite the historical cursor to mask an absent bitmap")
    }
}
