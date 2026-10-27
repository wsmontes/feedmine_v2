import Foundation
import Observation
import XCTest
import FeedMineUI

#if DEBUG
/// The witness's record revision must be **observable by the surface that reads it** and **invisible to the code that
/// states a branch**.
///
/// The second half is the regression this file exists for: `bump()` used to be `value &+= 1`, which *reads* the
/// observed property, and the host calls `note(branch)` from inside its own body — so every view that stated a branch
/// enrolled in the record's observation, the next fact re-rendered it, its body stated the branch again (bumping),
/// and the record spun. Measured 2026-10-27: the main runloop was busy for 30 s and the UI journey could not even
/// match an accessibility snapshot.
@MainActor
final class LaunchWitnessObservationTests: XCTestCase {
    /// `onChange` may be delivered from another context; a lock keeps the flag honest without weakening the test.
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var fired = false
        var value: Bool { lock.lock(); defer { lock.unlock() }; return fired }
        func fire() { lock.lock(); fired = true; lock.unlock() }
    }

    override func setUp() async throws {
        FeedLaunchWitness.reset()
    }

    /// Stating a branch is what the host's body does on every pass. It must not subscribe that body to the record:
    /// otherwise one witness fact invalidates it, and its own next pass bumps again.
    func testStatingABranchDoesNotSubscribeToTheRecordRevision() async {
        FeedLaunchWitness.reset()
        let invalidated = Flag()
        withObservationTracking {
            FeedLaunchWitness.note(.launchProgress)
        } onChange: {
            invalidated.fire()
        }
        // A fact that **always** bumps (`noteWaitSurface` is unconditional): if a guarded fact were used here, a
        // no-op would leave the test green even with the spin present.
        FeedLaunchWitness.note(.launchProgress)
        await Task.yield()
        XCTAssertFalse(invalidated.value,
            "stating a branch enrolled the caller in the record's observation; the next bump would re-run its body")
    }

    /// The surface that actually reads the record must be re-rendered by the facts it reads — that is the whole point
    /// of the revision, and it must not require a timer.
    func testTheRecordRevisionInvalidatesOnARealFact() async {
        FeedLaunchWitness.reset()
        let revision = FeedLaunchWitness.revision
        let before = revision.value
        let invalidated = Flag()
        withObservationTracking {
            _ = revision.value
        } onChange: {
            invalidated.fire()
        }
        // Unconditional bump, so the assertion cannot be satisfied by a guarded no-op.
        FeedLaunchWitness.note(.launchProgress)
        await Task.yield()
        XCTAssertTrue(invalidated.value, "a reader of the record is re-rendered by the fact it is reading")
        XCTAssertEqual(revision.value, before + 1, "one real fact, one version")
    }

    /// The record itself keeps stating the same facts: the version is diagnostics, not the record.
    func testTheRecordStillStatesTheExposureItWasGiven() async {
        FeedLaunchWitness.noteFirstExposure(cardCount: 1, contentBottom: 900, viewportHeight: 800,
            images: 6, providers: 2, ahead: 12, published: 20, reason: .initialLoad)
        let record = FeedLaunchWitness.record
        XCTAssertTrue(record.contains("content_bottom=900"), record)
        XCTAssertTrue(record.contains("reason=initial"), record)
        XCTAssertTrue(record.contains("published=20"), record)
    }
}
#endif
