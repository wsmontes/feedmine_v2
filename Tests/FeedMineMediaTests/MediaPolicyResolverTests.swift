import Foundation
import XCTest
import FeedMineDomain
import FeedMineMedia

/// PD-6: media choice and budget are derived from measured device facts.
final class MediaPolicyResolverTests: XCTestCase {
    private func conditions(hero: Double = 360, thumb: Double = 100, scale: Double = 3,
        network: MediaNetworkPath = .unconstrained, rate: Double? = nil, wait: Double? = nil,
        lowPower: Bool = false, thermal: MediaThermalPressure = .nominal) throws -> MediaDeviceConditions {
        try XCTUnwrap(MediaDeviceConditions(heroSlotPointWidth: hero, thumbnailSlotPointWidth: thumb, screenScale: scale,
            network: network, measuredBytesPerSecond: rate, waitBudgetSeconds: wait, freeStorageBytes: nil,
            lowPowerMode: lowPower, thermal: thermal))
    }
    private func policy(_ conditions: MediaDeviceConditions) throws -> MediaPolicy {
        MediaPolicy(conditions: conditions, ceilings: try XCTUnwrap(MediaSafetyCeilings(maximumDownloadBytes: 12_000_000,
            maximumPixelSide: 12_000, maximumPixelCount: 50_000_000)))
    }
    private let revision = OriginRevisionID()
    private func candidate(_ name: String, _ width: Int? = nil, _ height: Int? = nil, mime: String? = nil) throws -> MediaCandidate {
        try XCTUnwrap(MediaCandidate(id: MediaCandidateID(), originRevisionID: revision, role: .cardVisual, mediaClass: .image,
            remoteURL: URL(string: "https://example.test/\(name)")!, declaredMimeType: mime,
            declaredPixelWidth: width, declaredPixelHeight: width == nil ? nil : (height ?? width)))
    }
    private func chosen(_ resolution: MediaResolution) -> [String] {
        guard case .prepare(let first, let rest) = resolution else { return [] }
        return ([first] + rest).map(\.remoteURL.lastPathComponent)
    }

    func testDerivedPixelTargetsComeFromSlotAndScale() throws {
        let p = try policy(conditions(hero: 360, thumb: 100, scale: 3))
        XCTAssertEqual(p.idealHeroPixelWidth, 1080); XCTAssertEqual(p.acceptableHeroPixelWidth, 360)
        XCTAssertEqual(p.idealThumbnailPixelWidth, 300); XCTAssertEqual(p.acceptableThumbnailPixelWidth, 100)
    }
    func testInvalidConditionsAreRefused() {
        XCTAssertNil(MediaDeviceConditions(heroSlotPointWidth: 0, thumbnailSlotPointWidth: 1, screenScale: 2, network: .unconstrained,
            measuredBytesPerSecond: nil, waitBudgetSeconds: nil, freeStorageBytes: nil, lowPowerMode: false, thermal: .nominal))
        XCTAssertNil(MediaDeviceConditions(heroSlotPointWidth: 1, thumbnailSlotPointWidth: 1, screenScale: 0.5, network: .unconstrained,
            measuredBytesPerSecond: nil, waitBudgetSeconds: nil, freeStorageBytes: nil, lowPowerMode: false, thermal: .nominal))
        XCTAssertNil(MediaDeviceConditions(heroSlotPointWidth: 1, thumbnailSlotPointWidth: 1, screenScale: 2, network: .unconstrained,
            measuredBytesPerSecond: -1, waitBudgetSeconds: nil, freeStorageBytes: nil, lowPowerMode: false, thermal: .nominal))
    }
    func testPrefersSmallestCandidateThatFillsTheSlotNeverOversize() throws {
        let p = try policy(conditions())
        let resolution = MediaResolver.resolve([try candidate("huge", 4000), try candidate("exact", 1200), try candidate("unknown"),
            try candidate("small", 600), try candidate("logo", 64)], policy: p)
        XCTAssertEqual(chosen(resolution), ["exact", "huge", "unknown", "small"])
    }
    func testEconomyConditionsSettleForOnePixelPerPoint() throws {
        for c in [try conditions(network: .expensive), try conditions(lowPower: true), try conditions(thermal: .serious),
            try conditions(network: .constrained)] {
            let p = try policy(c)
            XCTAssertTrue(p.prefersEconomy)
            XCTAssertEqual(chosen(MediaResolver.resolve([try candidate("big", 1200), try candidate("enough", 400)], policy: p)),
                ["enough", "big"])
        }
    }
    func testConditionsCanForbidRemoteMediaAndCardBecomesTextOnly() throws {
        XCTAssertEqual(MediaResolver.resolve([try candidate("a", 1200)], policy: try policy(conditions(network: .unavailable))),
            .textOnly(.conditionsForbidRemoteMedia))
        XCTAssertEqual(MediaResolver.resolve([try candidate("a", 1200)], policy: try policy(conditions(thermal: .critical))),
            .textOnly(.conditionsForbidRemoteMedia))
        XCTAssertEqual(MediaResolver.resolve([], policy: try policy(conditions())), .textOnly(.noCandidates))
    }
    func testSvgNonImageTinyAndOverCeilingCandidatesAreNotViable() throws {
        let resolution = MediaResolver.resolve([try candidate("vector", mime: "image/svg+xml"), try candidate("clip", mime: "video/mp4"),
            try candidate("icon", 32), try candidate("bomb", 20_000)], policy: try policy(conditions()))
        XCTAssertEqual(resolution, .textOnly(.noViableCandidate))
    }
    func testDownloadBudgetFollowsMeasuredThroughputAndWait() throws {
        XCTAssertEqual(try policy(conditions(rate: 200_000, wait: 2)).downloadByteBudget, 400_000)
        XCTAssertEqual(try policy(conditions(rate: 50_000_000, wait: 10)).downloadByteBudget, 12_000_000)
        XCTAssertEqual(try policy(conditions()).downloadByteBudget, 12_000_000)
        XCTAssertEqual(try policy(conditions(rate: 1, wait: 0)).downloadByteBudget, 0)
    }
    func testMeasuredFitDecidesHeroThumbnailOrUnsuitable() throws {
        let p = try policy(conditions(hero: 360, thumb: 100, scale: 3))
        XCTAssertEqual(p.fit(measuredPixelWidth: 1080, height: 608), .hero)
        XCTAssertEqual(p.fit(measuredPixelWidth: 360, height: 360), .hero)
        XCTAssertEqual(p.fit(measuredPixelWidth: 800, height: 1200), .thumbnail)
        XCTAssertEqual(p.fit(measuredPixelWidth: 200, height: 150), .thumbnail)
        XCTAssertEqual(p.fit(measuredPixelWidth: 64, height: 64), .unsuitable)
        XCTAssertEqual(p.fit(measuredPixelWidth: 13_000, height: 100), .unsuitable)
        XCTAssertEqual(p.fit(measuredPixelWidth: 10_000, height: 10_000), .unsuitable)
    }
    func testRetentionBudgetShrinksAsDiskFills() {
        XCTAssertEqual(MediaRetention.budgetBytes(freeStorageBytes: 0, currentUsageBytes: 0), 0)
        let roomy = MediaRetention.budgetBytes(freeStorageBytes: 100_000, currentUsageBytes: 0)
        let tight = MediaRetention.budgetBytes(freeStorageBytes: 1_000, currentUsageBytes: 0)
        XCTAssertEqual(roomy, 50_000); XCTAssertLessThan(tight, roomy)
        // Media already on disk counts as reclaimable, but a full disk still pushes the budget down.
        XCTAssertLessThan(MediaRetention.budgetBytes(freeStorageBytes: 10, currentUsageBytes: 10_000), 10_000)
    }
    func testEvictionOrderNeverTouchesBookmarks() throws {
        func asset(_ name: String, _ size: Int64, _ retention: MediaRetentionClass, _ time: Double) throws -> RetainedMediaAsset {
            try XCTUnwrap(RetainedMediaAsset(key: try XCTUnwrap(PublishedMediaKey(rawValue: name)), byteCount: size,
                retention: retention, lastRelevantAt: Date(timeIntervalSince1970: time)))
        }
        let assets = [try asset("bookmark", 500, .bookmarked, 0), try asset("near", 100, .nearFutureUnseen, 0),
            try asset("seen-new", 100, .seenRecently, 9), try asset("seen-old", 100, .seenLongAgo, 1),
            try asset("far-b", 100, .farFutureUnseen, 5), try asset("far-a", 100, .farFutureUnseen, 2)]
        XCTAssertEqual(MediaRetention.evictions(assets, budgetBytes: 2_000), [])
        XCTAssertEqual(MediaRetention.evictions(assets, budgetBytes: 800).map(\.rawValue), ["far-a", "far-b"])
        XCTAssertEqual(MediaRetention.evictions(assets, budgetBytes: 0).map(\.rawValue),
            ["far-a", "far-b", "seen-old", "seen-new", "near"])
    }
}
