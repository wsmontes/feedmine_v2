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
        let readyOrigin: OriginRecordID
        let heroOrigin: OriginRecordID
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
            editionID: edition.id, readyID: ready.id, heroID: hero.id,
            readyOrigin: ready.originRecordID, heroOrigin: hero.originRecordID)
    }

    /// Confirmed visual exposure through the public exposure facts: a published origin that is no
    /// longer "unseen" was confirmed by a viewport observation, not by a restored cursor.
    private func seenOrigins(_ f: Fixture, _ ids: [OriginRecordID]) throws -> Set<OriginRecordID> {
        let facts = try f.history.exposure(editionID: f.editionID, originIDs: ids)
        return facts.publishedOriginIDs.subtracting(facts.unseenOriginIDs)
    }

    func testProjectionOverflowCannotMarkCheckpointAsSeen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let f = try fixture(directory: directory, cursorAtMissingHero: false)
        let bounds = FeedPresentationBounds(backwardCapacity: 0, forwardCapacity: 1)
        let checkpoint = try SessionStore(database: f.database).checkpoint()
        XCTAssertEqual(try seenOrigins(f, [f.readyOrigin, f.heroOrigin]), [],
            "Control: publication exposure must be initially absent")

        XCTAssertThrowsError(try FeedSession.FeedCheckpointProjection.read(
            publicationHistory: f.history, imageDecoder: nil, bounds: bounds,
            sequenceID: UUID(), after: UInt64.max)) {
            XCTAssertEqual($0 as? FeedSessionError, .projectionOrderExhausted)
        }
        XCTAssertEqual(try seenOrigins(f, [f.readyOrigin, f.heroOrigin]), [],
            "No high-water mark can survive a rejected projection")
        XCTAssertEqual(try SessionStore(database: f.database).checkpoint(), checkpoint,
            "Failed projection must preserve the saved cursor")

        let accepted = try XCTUnwrap(FeedSession.FeedCheckpointProjection.read(
            publicationHistory: f.history, imageDecoder: nil, bounds: bounds,
            sequenceID: UUID(), after: 0))
        XCTAssertEqual(accepted.snapshot.window.anchor.cardID, f.readyID)
        XCTAssertEqual(try seenOrigins(f, [f.readyOrigin, f.heroOrigin]), [],
            "A decoded/text checkpoint is still only a prepared cursor, not a viewport")
        XCTAssertEqual(try SessionStore(database: f.database).checkpoint(), checkpoint,
            "Successful projection cannot rewrite durable position")

        // Warm launch uses the same projection function, so neither launch
        // path is allowed to synthesize visual exposure before first paint.
        let warm = try XCTUnwrap(FeedSession.warmStart(
            publicationHistory: f.history, imageDecoder: nil, bounds: bounds))
        XCTAssertEqual(warm.snapshot.window.anchor.cardID, f.readyID)
        XCTAssertEqual(try seenOrigins(f, [f.readyOrigin, f.heroOrigin]), [],
            "A warm-start snapshot alone is not evidence of a drawn cell")

        let session = FeedSession(publicationHistory: f.history)
        let restored = try await session.admitPresentation(.restore(bounds))
        XCTAssertEqual(restored?.window.anchor.cardID, f.readyID)
        XCTAssertEqual(try seenOrigins(f, [f.readyOrigin, f.heroOrigin]), [],
            "A restored cursor is a position, not confirmed exposure")

        // Runtime accepts a synthetic observation as a stand-in for the host's
        // geometry callback. This verifies the exposure transition, NOT that
        // the SwiftUI cell was physically measured on a device.
        let observed = try await session.submitViewport(
            .init(anchor: .init(cardID: f.readyID, placement: .top)))
        XCTAssertEqual(observed?.window.anchor.cardID, f.readyID)
        XCTAssertEqual(try seenOrigins(f, [f.readyOrigin, f.heroOrigin]), [f.readyOrigin],
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
        // Shipped admission rule: an image card whose local asset cannot be reconstructed does not
        // cross the presentation boundary. The saved card is stated as unavailable instead of being
        // renumbered, and the window opens on the closest ready card.
        XCTAssertEqual(warm.snapshot.window.items.map(\.id), [f.readyID],
            "A hero without pixels is never presented")
        XCTAssertEqual(warm.snapshot.window.anchor.cardID, f.readyID)
        XCTAssertEqual(warm.snapshot.unavailablePositionCardID, f.heroID,
            "The durable card is stated as unavailable, not silently replaced")
        XCTAssertEqual(try seenOrigins(f, [f.readyOrigin, f.heroOrigin]), [f.readyOrigin],
            "A durable cursor at a missing hero does not prove it was rendered")
        XCTAssertEqual(try SessionStore(database: f.database).checkpoint(), checkpoint,
            "Do not erase or rewrite the historical cursor to mask an absent bitmap")
    }
}
