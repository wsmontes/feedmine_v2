import Foundation
import XCTest
import FeedMineDomain
@testable import FeedMineMedia
@testable import FeedMineRuntime

/// The first publication's one waiting primitive: bounded, event-driven, exactly-once, and honest about what an
/// image target means. These tests pin the four failure modes a naive implementation has — a read outside the lock,
/// a cancellation that lands before registration, an "image" that is really a text-only decision, and a waiter left
/// behind after the wait ends.

/// A deadline a test can state without capturing the test case: `Task {}` closures in a Swift 6 test must not
/// send the non-Sendable XCTestCase across isolation domains.
private func deadline(in seconds: Double) -> ContinuousClock.Instant { ContinuousClock.now + .seconds(seconds) }

/// Waits, bounded, until `expected` waits are registered. A single `Task.yield()` does not promise that every child
/// task has run to its registration point, so a count read after one yield races the scheduler (measured: 1 of 3).
/// This waits for the fact the test is about to assert, and fails the test if it never arrives — it never loosens the
/// exact-count assertion that follows.
private func waitForRegisteredWaiters(_ readiness: MediaReadiness, _ expected: Int,
    timeout: Duration = .seconds(5)) async -> Bool {
    let clock = ContinuousClock()
    let bound = clock.now + timeout
    while clock.now < bound {
        if readiness.outstandingWaiterCount == expected { return true }
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(2))
    }
    return readiness.outstandingWaiterCount == expected
}

final class MediaReadinessWaitTests: XCTestCase {
    private let png = LocalImageAsset(
        key: PublishedMediaKey(rawValue: "media/wait/\(UUID().uuidString)")!, pixelWidth: 1200, pixelHeight: 800,
        mimeType: "image/png")

    private func ready(_ fit: MediaSlotFit = .hero) -> MediaReadiness.Ready {
        MediaReadiness.Ready(result: MediaPreparationResult(candidateID: MediaCandidateID(),
            originRevisionID: OriginRevisionID(), state: .usable(png)),
            fit: fit, byteCount: 1024)
    }


    /// The target counts usable images, and the wait returns as soon as they exist — not at the deadline.
    func testWaitReturnsWhenTheImageTargetIsReached() async throws {
        let readiness = MediaReadiness()
        let one = OriginRevisionID(), two = OriginRevisionID(), three = OriginRevisionID()
        let wait = Task { await readiness.waitForPrepared([one, two, three], atLeast: 2,
            until: deadline(in: 5)) }
        let registered = await waitForRegisteredWaiters(readiness, 1)
        XCTAssertTrue(registered, "the wait is registered before the count")
        XCTAssertEqual(readiness.outstandingWaiterCount, 1, "the wait is registered, not polling")
        readiness.record(one, ready(), textDeclared: false)
        readiness.record(two, ready(.thumbnail), textDeclared: false)
        let reached = await wait.value
        XCTAssertEqual(reached, 2)
        XCTAssertEqual(readiness.outstandingWaiterCount, 0, "a satisfied wait leaves nothing registered")
    }

    /// A revision settled as **text by design** is decided, but it is not an image: it can end a wait only through
    /// "nothing more can arrive", never by satisfying an image target.
    func testTextOnlySettlementEndsTheWaitWithoutCountingAsAnImage() async throws {
        let readiness = MediaReadiness()
        let text = OriginRevisionID(), image = OriginRevisionID()
        let wait = Task { await readiness.waitForPrepared([text, image], atLeast: 1,
            until: deadline(in: 5)) }
        let registered = await waitForRegisteredWaiters(readiness, 1)
        XCTAssertTrue(registered, "the wait is registered before the decision")
        readiness.record(text, nil, textDeclared: true)
        XCTAssertEqual(readiness.outstandingWaiterCount, 1, "one text decision is not one image")
        readiness.record(image, ready(), textDeclared: false)
        let count = await wait.value
        XCTAssertEqual(count, 1)
        XCTAssertEqual(readiness.outstandingWaiterCount, 0)
    }

    /// A bitmap that cannot serve the slot (`unsuitable`) is a text presentation: it must not satisfy the image
    /// target either.
    func testUnsuitableBitmapIsNotAnImage() async throws {
        let readiness = MediaReadiness()
        let unsuitable = OriginRevisionID()
        let wait = Task { await readiness.waitForPrepared([unsuitable], atLeast: 1,
            until: deadline(in: 0.4)) }
        await Task.yield()
        readiness.record(unsuitable, ready(.unsuitable), textDeclared: false)
        let count = await wait.value
        XCTAssertEqual(count, 0, "unsuitable is textOnly for presentation; it is not a prepared image")
        XCTAssertEqual(readiness.outstandingWaiterCount, 0)
    }

    /// When every watched revision is decided, waiting further cannot produce anything: the wait ends early
    /// instead of spending the budget.
    func testAllSettledEndsTheWaitEarly() async throws {
        let readiness = MediaReadiness()
        let a = OriginRevisionID(), b = OriginRevisionID()
        let started = ContinuousClock.now
        let wait = Task { await readiness.waitForPrepared([a, b], atLeast: 2,
            until: deadline(in: 30)) }
        await Task.yield()
        readiness.record(a, nil, textDeclared: false) // declared image that failed: settled, no presentation
        readiness.record(b, nil, textDeclared: true)
        let count = await wait.value
        let elapsed = ContinuousClock.now - started
        XCTAssertEqual(count, 0)
        XCTAssertLessThan(elapsed, .seconds(5), "nothing can arrive; the wait must not sit on its deadline")
        XCTAssertEqual(readiness.outstandingWaiterCount, 0)
    }

    /// The deadline is the outer bound and returns the count reached so far.
    func testDeadlineReturnsTheCountReachedSoFar() async throws {
        let readiness = MediaReadiness()
        let a = OriginRevisionID(), b = OriginRevisionID()
        let wait = Task { await readiness.waitForPrepared([a, b], atLeast: 2,
            until: deadline(in: 0.3)) }
        await Task.yield()
        readiness.record(a, ready(), textDeclared: false)
        let count = await wait.value
        XCTAssertEqual(count, 1)
        XCTAssertEqual(readiness.outstandingWaiterCount, 0, "the deadline racer unregisters")
    }

    /// Cancelling **before** the task body runs must not leave a waiter registered until the deadline.
    func testCancellationBeforeRegistrationLeavesNoWaiter() async throws {
        let readiness = MediaReadiness()
        let revisions = [OriginRevisionID(), OriginRevisionID()]
        for _ in 0..<40 {
            let task = Task { await readiness.waitForPrepared(revisions, atLeast: 2,
                until: deadline(in: 10)) }
            task.cancel()
            _ = await task.value
            XCTAssertEqual(readiness.outstandingWaiterCount, 0)
        }
    }

    /// Cancelling **during** the wait (after registration) resumes it and unregisters in the same step.
    func testCancellationDuringWaitResumesAndUnregisters() async throws {
        let readiness = MediaReadiness()
        let revisions = [OriginRevisionID(), OriginRevisionID()]
        let task = Task { await readiness.waitForPrepared(revisions, atLeast: 2,
            until: deadline(in: 10)) }
        let registered = await waitForRegisteredWaiters(readiness, 1)
        XCTAssertTrue(registered, "the wait is registered before the count")
        XCTAssertEqual(readiness.outstandingWaiterCount, 1)
        task.cancel()
        let count = await task.value
        XCTAssertEqual(count, 0)
        XCTAssertEqual(readiness.outstandingWaiterCount, 0)
    }

    /// Records that arrive while several waits are live wake exactly the ones whose condition they satisfied, and a
    /// later record cannot resume an already-finished continuation (the exactly-once rule).
    func testSeveralWaitsAndLaterRecordsDoNotDoubleResume() async throws {
        let readiness = MediaReadiness()
        let a = OriginRevisionID(), b = OriginRevisionID(), c = OriginRevisionID()
        let first = Task { await readiness.waitForPrepared([a, b, c], atLeast: 3,
            until: deadline(in: 10)) }
        let second = Task { await readiness.waitForPrepared([a, b, c], atLeast: 1,
            until: deadline(in: 10)) }
        let third = Task { await readiness.waitForPrepared([c], atLeast: 1,
            until: deadline(in: 10)) }
        let registered = await waitForRegisteredWaiters(readiness, 3)
        XCTAssertTrue(registered, "all three waits are registered before the count")
        XCTAssertEqual(readiness.outstandingWaiterCount, 3)
        readiness.record(a, ready(), textDeclared: false)
        let secondCount = await second.value
        XCTAssertEqual(secondCount, 1, "the one-image wait is satisfied first")
        XCTAssertEqual(readiness.outstandingWaiterCount, 2)
        readiness.record(b, ready(), textDeclared: false)
        readiness.record(c, ready(), textDeclared: false)
        let firstCount = await first.value
        let thirdCount = await third.value
        XCTAssertEqual(firstCount, 3)
        XCTAssertEqual(thirdCount, 1)
        XCTAssertEqual(readiness.outstandingWaiterCount, 0)
        // A further decision must not touch the finished continuations.
        readiness.record(OriginRevisionID(), ready(), textDeclared: false)
        XCTAssertEqual(readiness.outstandingWaiterCount, 0)
    }

    /// A duplicate revision in the watched list is one candidate, not two images.
    func testDuplicateRevisionsCountOnce() async throws {
        let readiness = MediaReadiness()
        let a = OriginRevisionID()
        let wait = Task { await readiness.waitForPrepared([a, a, a], atLeast: 2,
            until: deadline(in: 0.4)) }
        await Task.yield()
        readiness.record(a, ready(), textDeclared: false)
        let count = await wait.value
        XCTAssertEqual(count, 1, "one revision cannot satisfy a two-image target")
    }

    /// The preview API hands back prepared pixels only, and skips a decision that has none.
    func testPreviewImagesSkipsSettledRevisionsWithoutPixels() throws {
        let readiness = MediaReadiness()
        let withImage = OriginRevisionID(), withoutImage = OriginRevisionID()
        readiness.record(withoutImage, nil, textDeclared: true)
        readiness.record(withImage, ready(), textDeclared: false)
        let decoder = try XCTUnwrap(PresentationImageDecoder(assetDirectory: FileManager.default.temporaryDirectory,
            heroMaxPixel: 64, thumbnailMaxPixel: 32))
        // The asset does not exist on disk, so decoding yields nothing — the decision is what this asserts: only
        // revisions that carry a prepared, usable image are even considered.
        XCTAssertTrue(readiness.previewImages(for: [withoutImage, withImage], limit: 6, decoder: decoder).isEmpty)
    }
}
