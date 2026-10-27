import CoreGraphics
import Foundation
import ImageIO
import XCTest
import FeedMineDomain
import FeedMineMedia
import FeedMineRuntime

/// The player's own values, proved without a sound card: an admitted cover survives as immutable pixels, a
/// scrubber commits only its own item's finite draft, and the only scale a progress bar may state is a length the
/// player measured.
final class ReaderMediaArtworkTests: XCTestCase {
    private func png(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.9, green: 0.1, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func image(key: String, pixels: Int = 10) throws -> PresentationImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return PresentationImage.decoded(key: key, cgImage: try XCTUnwrap(context.makeImage()))
    }

    func testADecodedImageKeepsItsIdentityAndPixels() throws {
        let cover = try image(key: "cover-a", pixels: 12)
        XCTAssertEqual(cover.key, "cover-a")
        XCTAssertEqual(cover.cgImage.width, 12)
        XCTAssertEqual(cover, try image(key: "cover-a", pixels: 12), "the same key and size is the same value")
    }

    /// The player reads the bytes the media pipeline already materialized — never a URL, never a second download.
    /// A key whose bytes are not on disk is nil, which the surfaces state as V1's waveform rather than a cover.
    func testTheArtworkDecoderReadsOnlyPersistedBytesAndBoundsThePixels() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let assets = root.appendingPathComponent("Media", isDirectory: true)
        let materializer = ImageMaterializer(assetDirectory: assets)
        let stored = try materializer.materialize(try png(width: 900, height: 450))

        let decoder = try XCTUnwrap(ReaderMediaArtworkDecoder(assetDirectory: assets, maxPixel: 200))
        let cover = try XCTUnwrap(decoder.artwork(forMediaKey: stored.key.rawValue))
        XCTAssertEqual(cover.key, stored.key.rawValue)
        XCTAssertLessThanOrEqual(max(cover.cgImage.width, cover.cgImage.height), 200)
        XCTAssertEqual(cover.cgImage.width / 2, cover.cgImage.height, "the slot's 2:1 shape is preserved")

        XCTAssertNil(decoder.artwork(forMediaKey: "not-a-stored-key"))
        XCTAssertNil(decoder.artwork(forMediaKey: ""), "an empty key is not a media identity")
        XCTAssertNil(ReaderMediaArtworkDecoder(assetDirectory: assets, maxPixel: 0),
            "a decoder with no pixel bound cannot produce a slot image")
    }

    /// The scrubber's rule: a draft commits only for the card still playing, is finite, and the player's own
    /// duration bounds it. Anything else is discarded instead of seeking.
    func testAScrubCommitsOnlyItsOwnItemsFiniteBoundedDraft() {
        let first = PublicationCardID(), second = PublicationCardID()
        XCTAssertNil(ReaderMediaScrub.target(draft: nil, draftedCard: first, playingCard: first, duration: 100))
        XCTAssertEqual(ReaderMediaScrub.target(draft: 42.4, draftedCard: first, playingCard: first,
            duration: 100), 42.4)
        XCTAssertEqual(ReaderMediaScrub.target(draft: 140, draftedCard: first, playingCard: first,
            duration: 100), 100, "a drag past the end commits the end, never a position the item does not have")
        XCTAssertEqual(ReaderMediaScrub.target(draft: -8, draftedCard: first, playingCard: first,
            duration: 100), 0)
        XCTAssertNil(ReaderMediaScrub.target(draft: 30, draftedCard: first, playingCard: second, duration: 100),
            "the reader changed episode while dragging: the old timeline has no target")
        XCTAssertNil(ReaderMediaScrub.target(draft: .nan, draftedCard: first, playingCard: first, duration: 100))
        XCTAssertNil(ReaderMediaScrub.target(draft: .infinity, draftedCard: first, playingCard: first,
            duration: 100))
        XCTAssertNil(ReaderMediaScrub.target(draft: 30, draftedCard: nil, playingCard: first, duration: 100))
        XCTAssertEqual(ReaderMediaScrub.target(draft: 30, draftedCard: first, playingCard: first,
            duration: nil), 30, "an unknown length cannot bound the reader's own position")
    }

    /// A progress fraction exists only when the player proved a finite length; zero or NaN is not a fraction.
    func testProgressUsesOnlyAFinitePlayerLength() {
        let item = ReaderMediaItem(cardID: PublicationCardID(),
            url: URL(string: "https://example.test/episode.mp3")!, title: "Episódio", mimeType: "audio/mpeg")
        func state(position: Double, duration: Double?) -> ReaderMediaState {
            ReaderMediaState(item: item, isPlaying: true, position: position, duration: duration, error: nil)
        }
        XCTAssertNil(state(position: 10, duration: nil).progress)
        XCTAssertNil(state(position: 10, duration: 0).progress)
        XCTAssertNil(state(position: 10, duration: .nan).progress)
        XCTAssertNil(state(position: .nan, duration: 60).progress)
        XCTAssertEqual(state(position: 15, duration: 60).progress, 0.25)
        XCTAssertEqual(state(position: 90, duration: 60).progress, 1, "the bar clamps, it never exceeds its track")
    }
}
