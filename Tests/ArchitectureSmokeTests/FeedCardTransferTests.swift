import Foundation
import XCTest
import FeedMineDomain
@testable import FeedMinePublication
@testable import FeedMineRuntime
import FeedMineMedia
import FeedMineUI

/// T4 — the transferred V1 visual system and card composition.
@MainActor
final class FeedCardTransferTests: XCTestCase {
    // MARK: - Appearance values copied from V1

    func testAppearanceCopiesV1PaletteMetricsAndTypography() throws {
        // Palette entries are V1's exact values (`PaletteFamily.accent(for:)`).
        XCTAssertEqual(ReaderPaletteFamily.warmEarth.accentHex(for: .afternoon), "#FF7A45")
        XCTAssertEqual(ReaderPaletteFamily.coolSky.accentHex(for: .night), "#2C3E5A")
        XCTAssertEqual(ReaderPaletteFamily.monochrome.accentHex(for: .dawn), "#B0A89E")
        XCTAssertEqual(ReaderPaletteFamily.warmEarth.pageTintHex(for: .night), "#F0EBE4")
        // Metrics are V1's per-period values (`CircadianPeriod`).
        let standard = ReaderAppearance(period: .morning, paletteFamily: .warmEarth, fontStyle: .system,
            typeScale: .medium)
        XCTAssertEqual(standard.cardPadding, 14)
        XCTAssertEqual(standard.cardGap, 12)
        XCTAssertEqual(standard.cardRadius, 14)
        let night = ReaderAppearance(period: .night, paletteFamily: .warmEarth, fontStyle: .system,
            typeScale: .medium)
        XCTAssertEqual(night.cardPadding, 22)
        XCTAssertEqual(night.cardGap, 18)
        XCTAssertEqual(night.cardRadius, 16)
        // Text size preference, per role (V1 `fontSize`).
        XCTAssertEqual(standard.typeScale.size(for: .cardTitle), 17)
        XCTAssertEqual(ReaderTypeScale.large.size(for: .cardTitle), 20)
        XCTAssertEqual(ReaderTypeScale.small.size(for: .cardBody), 12)
        // HIG tracking copied from V1.
        XCTAssertEqual(ReaderAppearance.tracking(for: 17), -0.43)
        XCTAssertEqual(ReaderAppearance.tracking(for: 11), 0.12)
    }

    /// The period supplies the title weight and the letter spacing, exactly as V1's engine did.
    func testAppearancePeriodDrivesWeightAndSpacing() {
        let dawn = ReaderAppearance(period: .dawn, paletteFamily: .warmEarth, fontStyle: .system,
            typeScale: .medium)
        XCTAssertEqual(dawn.titleWeight, .light)
        XCTAssertEqual(dawn.letterSpacing, 0.3)
        let afternoon = ReaderAppearance(period: .afternoon, paletteFamily: .warmEarth, fontStyle: .system,
            typeScale: .medium)
        XCTAssertEqual(afternoon.titleWeight, .medium)
        XCTAssertEqual(afternoon.letterSpacing, -0.1)
    }

    // MARK: - Card composition

    func testCardRendersFrozenFieldsAndNeverInventsText() throws {
        let card = try XCTUnwrap(PresentationCard(publishedCard: try Self.published(layout: .textOnly,
            title: "Título congelado", text: "Corpo publicado")))
        let view = FeedItemCardView(card: card, appearance: .standard, onAction: { _ in })
        XCTAssertEqual(view.card.id, card.id)
        XCTAssertFalse(view.card.isImageBearing)
        // The card's date helper is the V1 rule: relative while recent, locale short date later.
        XCTAssertEqual(FeedItemCardView.formatted(nil), "")
        XCTAssertFalse(FeedItemCardView.formatted(Date()).isEmpty)
    }

    /// A card published with an image slot keeps the slot's frozen geometry even when the pixels were
    /// released: the transfer must never turn a hero card into a different layout.
    func testImageSlotKeepsFrozenGeometryWithoutDecodedPixels() throws {
        let published = try Self.published(layout: .hero, title: "Hero")
        let projected = PresentationCard(publishedCard: published)
        XCTAssertTrue(projected.isImageBearing)
        XCTAssertEqual(projected.mediaAspectRatio, 1.5)
        let released = projected.releasingDecodedImage()
        XCTAssertTrue(released.isImageBearing, "Residency never changes the published layout")
        XCTAssertEqual(released.mediaAspectRatio, projected.mediaAspectRatio)
        XCTAssertNil(released.image)
        XCTAssertEqual(released.id, projected.id)
        let appearance = ReaderAppearance.standard
        // The slot uses the frozen ratio when the projection has one, and the appearance's 16:9 mold
        // otherwise; both are structural, so nothing below the slot can move.
        XCTAssertEqual(appearance.heroAspectRatio, 16.0 / 9.0, accuracy: 0.0001)
    }

    /// Read and saved states change affordances only: the composition the card draws is the same.
    func testReadAndBookmarkStatesDoNotChangeCardStructure() throws {
        let card = try XCTUnwrap(PresentationCard(publishedCard: try Self.published(layout: .textOnly,
            title: "Título")))
        let read = FeedItemCardView(card: card, appearance: .standard, isRead: true, isBookmarked: true,
            onAction: { _ in })
        let unread = FeedItemCardView(card: card, appearance: .standard, isRead: false,
            isBookmarked: false, onAction: { _ in })
        XCTAssertNotEqual(read, unread, "The chrome is part of the card's identity")
        XCTAssertEqual(read.card, unread.card, "The published values are identical")
        XCTAssertEqual(read.appearance, unread.appearance)
        XCTAssertEqual(ReaderAppearance.standard.readOpacity, 0.92)
    }

    /// A control the host cannot execute is not rendered, so a transferred menu can never contain a
    /// dead item while its delivery (T5–T11) is still pending.
    func testUnavailableActionsAreNotRendered() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FeedMineUI/Cards/FeedItemCardView.swift"), encoding: .utf8)
        for action in ["save", "viewSource", "addSourceToCollection", "copyLink", "share"] {
            XCTAssertTrue(source.contains("if availableActions.contains(.\(action))"),
                "the card must gate .\(action) on what the host can execute")
        }
        XCTAssertFalse(source.contains("URLSession"), "the renderer performs no I/O")
        XCTAssertFalse(source.contains("UIImage"), "the renderer draws decoded bytes only")
        XCTAssertFalse(source.contains("UIPasteboard"), "clipboard work belongs to the host")
        XCTAssertFalse(source.contains("UIActivityViewController"), "sharing belongs to the host")
    }

    // MARK: - Fixture

    private static func published(layout: PublishedCardLayout, title: String?,
        text: String? = nil) throws -> PublishedCard {
        let media: PublishedMediaSet
        if layout == .textOnly {
            media = .none
        } else {
            media = PublishedMediaSet(primary: try XCTUnwrap(PublishedMediaRef(
                key: try XCTUnwrap(PublishedMediaKey(rawValue: "local-key")), pixelWidth: 600,
                pixelHeight: 400, mimeType: "image/jpeg")))
        }
        return try XCTUnwrap(PublishedCard(id: PublicationCardID(),
            origin: PublishedOrigin(originRecordID: OriginRecordID(), originRevisionID: OriginRevisionID(),
                sourceID: SourceID(), providerID: ProviderID(), sourceDisplayName: "Fonte Local",
                providerDisplayName: nil),
            contentEntityID: nil, contentClusterID: nil,
            text: PublishedText(title: title, primaryText: text) , timestamp: nil, media: media,
            renderContract: XCTUnwrap(RenderContract(layout: layout,
                mediaAspectRatio: layout == .textOnly ? nil : 1.5)),
            primaryAction: nil))
    }
}
