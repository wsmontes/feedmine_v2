import XCTest
import Foundation
import Synchronization
import GRDB
import FeedMineDomain
import FeedMinePersistence
import FeedMineAcquisition
import FeedMineUI
@testable import FeedMinePersistence
@testable import FeedMine

/// Applying a filter is a **confirmation boundary**: the selection is durable before memory changes, the key
/// and its expiry are one write, and a failure after confirmation is distinguishable from a failure before it.
///
/// The failures are real SQLite refusals installed as triggers on the runtime database — no injected seam and
/// no second architecture. Each trigger refuses exactly the write the case names.
@MainActor
final class FilterConfirmationBoundaryTests: XCTestCase {
    private func directory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func root(directory: URL) -> AppComposition {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureTransport.self]
        configuration.timeoutIntervalForRequest = 5
        return AppComposition(directory: directory, feeds: TrustedFeed.development,
            transportConfiguration: configuration)
    }

    /// A launched composition with a published session — the state a reader is in when they open the sheet.
    private func launched() async throws -> (root: AppComposition, session: FeedAssociation, directory: URL) {
        let directory = directory()
        let root = root(directory: directory)
        await root.launch()
        XCTAssertNil(root.startupFailure)
        let session = try XCTUnwrap(root.association)
        XCTAssertNotNil(session.store.state.presentation, "the fixture publishes a real session")
        return (root, session, directory)
    }

    private func install(_ statements: [String], in directory: URL) throws {
        let database = try RuntimeDatabase(location: .init(directory: directory))
        try database.write { db in
            for statement in statements { try db.execute(sql: statement) }
        }
    }

    private func persisted(_ directory: URL) throws -> ReaderPreferencesStore.Record {
        try XCTUnwrap(ReaderPreferencesStore(database: try RuntimeDatabase(location: .init(directory: directory)))
            .load())
    }

    // MARK: - (a) Persistence fails before confirmation

    func testFilterPersistenceFailureLeavesTheKeyTheExpiryAndTheLiveSessionUnchanged() async throws {
        let (root, session, directory) = try await launched()
        let before = root.currentContextKey
        let beforeExpiry = try persisted(directory).filterExpiry
        try install(["""
            CREATE TRIGGER filter_boundary_reject_context
            BEFORE UPDATE ON reader_preferences
            WHEN NEW.active_context IS NOT OLD.active_context
            BEGIN SELECT RAISE(ABORT, 'filter boundary: context write refused'); END;
            """], in: directory)

        do {
            try await root.applyFilter(ReaderFilter(mood: .fun), preset: .everything)
            XCTFail("the refused context write must not be reported as applied")
        } catch {
            let failure = error as? ReaderFilterFailure
            XCTAssertEqual(failure?.selectionIsSaved, false,
                "a failure before confirmation must be reported as not saved: \(error)")
        }

        XCTAssertEqual(root.currentContextKey, before,
            "a persistence failure before confirmation must not change the in-memory selection")
        XCTAssertEqual(root.currentFilter, before.filter)
        XCTAssertEqual(try persisted(directory).activeContextKey, before,
            "the durable selection is still the previous one")
        XCTAssertEqual(try persisted(directory).filterExpiry, beforeExpiry,
            "a failed apply does not renew the expiry either")
        XCTAssertTrue(root.association === session, "the live session is the previous one")
        XCTAssertTrue(session.active, "the previous session stays live")
        XCTAssertEqual(root.association?.contextKey, session.contextKey)
        await root.association?.close()
    }

    // MARK: - (b) A partial write is not a reachable state

    func testFilterExpiryFailureCannotLeaveANewKeyWithTheOldExpiry() async throws {
        let (root, session, directory) = try await launched()
        let before = root.currentContextKey
        let beforeRecord = try persisted(directory)
        XCTAssertNil(beforeRecord.filterExpiry.startsAt, "the fixture has no pending overlay window")
        try install(["""
            CREATE TRIGGER filter_boundary_reject_expiry
            BEFORE UPDATE ON reader_preferences
            WHEN NEW.filter_set_at IS NOT OLD.filter_set_at
            BEGIN SELECT RAISE(ABORT, 'filter boundary: expiry write refused'); END;
            """], in: directory)

        do {
            try await root.applyFilter(ReaderFilter(mood: .fun), preset: .everything)
            XCTFail("the refused expiry write must not be reported as applied")
        } catch {
            let failure = error as? ReaderFilterFailure
            XCTAssertEqual(failure?.selectionIsSaved, false,
                "a refused combined write is a persistence failure, not a presentation one: \(error)")
        }

        let after = try persisted(directory)
        XCTAssertEqual(after.activeContextKey, before,
            "a refused apply leaves no new key behind: key and expiry are one durable fact")
        XCTAssertEqual(after.filterExpiry, beforeRecord.filterExpiry,
            "the previous expiry is untouched too — a new key with an old expiry is not a reachable state")
        XCTAssertEqual(root.currentContextKey, before,
            "memory still states the previous selection")
        XCTAssertTrue(root.association === session)
        XCTAssertTrue(session.active)
        await root.association?.close()
    }

    // MARK: - (c) Persistence succeeds, presentation fails

    func testFilterPresentationFailureKeepsTheSelectionConfirmedAndRecoverable() async throws {
        let (root, session, directory) = try await launched()
        let filter = ReaderFilter(languages: ["pt"], mood: .fun)
        try install(["""
            CREATE TRIGGER filter_boundary_reject_checkpoint_insert
            BEFORE INSERT ON session_checkpoint
            BEGIN SELECT RAISE(ABORT, 'filter boundary: checkpoint write refused'); END;
            """, """
            CREATE TRIGGER filter_boundary_reject_checkpoint_update
            BEFORE UPDATE ON session_checkpoint
            BEGIN SELECT RAISE(ABORT, 'filter boundary: checkpoint write refused'); END;
            """], in: directory)

        do {
            try await root.applyFilter(filter, preset: .everything)
            XCTFail("a presentation failure after confirmation must be reported, never hidden")
        } catch {
            XCTAssertTrue(error is ReaderFilterFailure, "the failure is a domain outcome, not a raw storage error")
            let failure = error as? ReaderFilterFailure
            XCTAssertEqual(failure?.selectionIsSaved, true,
                "the reader must be told the selection was saved — nothing was rolled back")
        }

        let confirmed = readerKey(root: root, filter: filter)
        XCTAssertEqual(root.currentContextKey, confirmed,
            "the confirmed selection is what memory states")
        let durable = try persisted(directory)
        XCTAssertEqual(durable.activeContextKey, confirmed,
            "the confirmed selection is durable and identifiable")
        XCTAssertNotNil(durable.filterExpiry.startsAt, "the confirmed overlay window was renewed")
        XCTAssertTrue(root.association === session, "the previous session is preserved while presentation fails")
        XCTAssertTrue(session.active)

        // Recoverable: the same transition, retried, presents the confirmed selection.
        try install(["DROP TRIGGER filter_boundary_reject_checkpoint_insert",
            "DROP TRIGGER filter_boundary_reject_checkpoint_update"], in: directory)
        try await root.applyFilter(filter, preset: .everything)
        let presented = try XCTUnwrap(root.association)
        XCTAssertFalse(presented === session, "the retry rebuilds the session")
        XCTAssertFalse(session.active, "the previous session is retired by the successful rebuild")
        XCTAssertEqual(presented.contextKey.filter.languages, ["pt"])
        XCTAssertEqual(presented.contextKey.filter.mood, .fun)
        XCTAssertEqual(try persisted(directory).activeContextKey, confirmed)
        await presented.close()

        // R11: the confirmed selection survives a relaunch — it was durable before the failed activation, so a new
        // composition on the same directory presents the same context and the same filter.
        let relaunched = self.root(directory: directory)
        await relaunched.launch()
        XCTAssertEqual(relaunched.currentContextKey, confirmed,
            "o contexto confirmado antes da falha é o que a nova execução apresenta")
        let reopened = try XCTUnwrap(relaunched.association)
        XCTAssertEqual(reopened.contextKey.filter.languages, ["pt"])
        XCTAssertEqual(reopened.contextKey.filter.mood, .fun)
        XCTAssertTrue(reopened.active, "a nova execução aplica a seleção confirmada")
        await reopened.close()
    }

    // MARK: - (d) All succeed

    func testFilterApplicationPersistsKeyAndExpiryAndActivatesTheSession() async throws {
        let (root, session, directory) = try await launched()
        let filter = ReaderFilter(languages: ["pt"], mood: .fun)
        let started = Date()
        try await root.applyFilter(filter, preset: .everything)

        let confirmed = readerKey(root: root, filter: filter)
        XCTAssertEqual(root.currentContextKey, confirmed)
        let durable = try persisted(directory)
        XCTAssertEqual(durable.activeContextKey, confirmed, "the selection is durable")
        let renewed = try XCTUnwrap(durable.filterExpiry.startsAt, "the overlay window is renewed")
        XCTAssertEqual(renewed.timeIntervalSince1970, started.timeIntervalSince1970, accuracy: 30)
        let presented = try XCTUnwrap(root.association)
        XCTAssertFalse(presented === session, "the session is rebuilt around the new identity")
        XCTAssertFalse(session.active)
        XCTAssertEqual(presented.contextKey.filter.languages, ["pt"])
        XCTAssertEqual(presented.contextKey.filter.mood, .fun)
        await presented.close()
    }

    // MARK: - (e) NF-03 RED/GREEN: the sheet callback returns after the durable write

    /// The production callback behind Done must return once the selection and expiry are durable, without waiting
    /// for the held launch. On the old path this assertion fails because `applyFilter` awaits `next.launch`.
    func testSheetCallbackReturnsAfterDurableCommitBeforeSuspendedActivationReleases() async throws {
        let (root, session, directory) = try await launched()
        FixtureTransport.holdingAll.withLock { $0 = true }
        FixtureTransport.allEntered.withLock { $0 = 0 }
        defer { FixtureTransport.releaseAll() }
        // Quiet window: no unrelated in-flight request may be mistaken for the replacement launch.
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(FixtureTransport.allEntered.withLock { $0 }, 0,
            "the gate is quiet before the activation starts")
        let priorFilter = session.contextKey.filter
        let filter = ReaderFilter(languages: ["pt"], mood: .fun)
        let confirmed = readerKey(root: root, filter: filter)
        let finished = Mutex(false)
        let callback = Task { @MainActor in
            defer { finished.withLock { $0 = true } }
            try await root.applyFilterFromSheet(filter, preset: .everything) {}
        }

        let deadline = Date().addingTimeInterval(5)
        var durable = false
        while Date() < deadline {
            if (try? persisted(directory).activeContextKey) == confirmed {
                durable = true
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(durable, "the durable selection is written before the callback returns")
        // Wait for the actual held Network boundary, not a fixed sleep: the activation must have entered it.
        let enteredDeadline = Date().addingTimeInterval(10)
        while Date() < enteredDeadline,
            FixtureTransport.allEntered.withLock({ $0 }) == 0 {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThan(FixtureTransport.allEntered.withLock { $0 }, 0,
            "the suspended activation really reached the Network request gate")
        XCTAssertTrue(finished.withLock { $0 },
            "Done must not wait for the acquisition/launch it can no longer help")
        XCTAssertTrue(root.association === session,
            "the previous feed stays the reader's screen until the replacement is valid")
        XCTAssertEqual(root.association?.contextKey.filter, priorFilter,
            "the previous feed is identified as prior, not as the confirmed new filter")

        FixtureTransport.releaseAll()
        try await callback.value
        let activationDeadline = Date().addingTimeInterval(10)
        while Date() < activationDeadline {
            if root.association?.contextKey == confirmed { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(root.association?.contextKey, confirmed)
        await root.association?.close()
    }

    /// NF-03: the durable write is off the MainActor. A held SQLite writer must not freeze a MainActor probe,
    /// and the real stored selection appears only after the writer is released.
    func testConfirmationKeepsMainActorResponsiveWhileTheSQLiteWriterIsHeld() async throws {
        let (root, _, directory) = try await launched()
        let db = try XCTUnwrap(root.association?.database)
        let filter = ReaderFilter(mood: .fun)
        let confirmed = readerKey(root: root, filter: filter)

        let holdStarted = Mutex(false)
        let releaseHold = Mutex(false)
        let holder = Task {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    try? db.write { _ in
                        holdStarted.withLock { $0 = true }
                        while !releaseHold.withLock({ $0 }) { Thread.sleep(forTimeInterval: 0.01) }
                    }
                    continuation.resume()
                }
            }
        }
        let startedDeadline = Date().addingTimeInterval(5)
        while Date() < startedDeadline, !holdStarted.withLock({ $0 }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(holdStarted.withLock { $0 }, "the SQLite writer is actually held")

        let finished = Mutex(false)
        let started = Mutex(false)
        let confirm = Task { @MainActor in
            defer { finished.withLock { $0 = true } }
            started.withLock { $0 = true }
            _ = try await root.confirmFilter(filter, preset: .everything)
        }
        // Safety release so an old synchronous MainActor write fails the probe instead of deadlocking the suite.
        let safety = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            releaseHold.withLock { $0 = true }
        }
        defer { safety.cancel(); releaseHold.withLock { $0 = true } }
        // The task sets `started` immediately before entering confirmFilter; observing it means the write was
        // attempted and the task is now suspended on the held writer (or already finished on an old sync path).
        while !started.withLock({ $0 }) { await Task.yield() }
        var ticks = 0
        for _ in 0..<6 where !finished.withLock({ $0 }) {
            ticks += 1
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTAssertGreaterThan(ticks, 0, "the MainActor kept running while SQLite was held")
        XCTAssertFalse(finished.withLock { $0 }, "the confirmation is still awaiting the real durable commit")
        XCTAssertNotEqual(try ReaderPreferencesStore(database: db).load()?.activeContextKey, confirmed,
            "nothing is declared saved while the writer is held")

        releaseHold.withLock { $0 = true }
        try await confirm.value
        await holder.value
        XCTAssertEqual(try persisted(directory).activeContextKey, confirmed)
        await root.association?.close()
    }

    /// NF-03: A-held → B → A. Activation of A is blocked on the network; B and then A are confirmed. Only the
    /// final A may install, no stale failure may reach the reader, and the durable key is A.
    func testHeldAActivationThenBThenALeavesTheLatestSelectionAndAssociation() async throws {
        let (root, _, directory) = try await launched()
        FixtureTransport.holdingAll.withLock { $0 = true }
        FixtureTransport.allEntered.withLock { $0 = 0 }
        defer { FixtureTransport.releaseAll() }
        let a = ReaderFilter(mood: .fun)
        let b = ReaderFilter(mood: .serious)
        let aKey = readerKey(root: root, filter: a)
        let bKey = readerKey(root: root, filter: b)
        let failures = Mutex(0)

        let firstA = Task { @MainActor in
            try await root.applyFilterFromSheet(a, preset: .everything) {
                failures.withLock { $0 += 1 }
            }
        }
        let enteredDeadline = Date().addingTimeInterval(10)
        while Date() < enteredDeadline,
            FixtureTransport.allEntered.withLock({ $0 }) == 0 {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThan(FixtureTransport.allEntered.withLock { $0 }, 0)

        let thenB = Task { @MainActor in
            try await root.applyFilterFromSheet(b, preset: .everything) {
                failures.withLock { $0 += 1 }
            }
        }
        try await thenB.value
        XCTAssertEqual(try persisted(directory).activeContextKey, bKey)
        let lastA = Task { @MainActor in
            try await root.applyFilterFromSheet(a, preset: .everything) {
                failures.withLock { $0 += 1 }
            }
        }
        try await lastA.value
        XCTAssertEqual(try persisted(directory).activeContextKey, aKey)

        FixtureTransport.releaseAll()
        try await firstA.value
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, root.association?.contextKey != aKey {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(root.association?.contextKey, aKey,
            "the final persisted A is the association on screen")
        XCTAssertEqual(try persisted(directory).activeContextKey, aKey)
        XCTAssertEqual(failures.withLock { $0 }, 0,
            "a superseded activation is not reported as a reader-visible failure")
        await root.association?.close()
    }

    /// The sheet store's write refusal: the applied selection, draft and isApplying all survive, so the sheet
    /// stays with the reader's edits and no success is declared.
    func testFilterStoreRefusalKeepsDraftAppliedAndNotApplying() async throws {
        enum Refusal: Error { case write }
        let store = ReaderFilterStore(onApply: { _, _ in throw Refusal.write })
        store.select(mood: .fun)
        do {
            _ = try await store.apply()
            XCTFail("a refused onApply must be reported")
        } catch {}
        XCTAssertEqual(store.applied, .unrestricted, "the applied selection is unchanged")
        XCTAssertTrue(store.isDirty, "the draft still carries the reader's edit")
        XCTAssertFalse(store.isApplying)
    }

    /// Post-commit failure is saved-but-not-presented; the existing activation owner retries successfully after
    /// the real checkpoint refusal is removed. The callback returns before that activation finishes.
    func testPostCommitFailureIsRetriedByTheExistingActivationOwner() async throws {
        let (root, session, directory) = try await launched()
        try install(["""
            CREATE TRIGGER filter_boundary_reject_checkpoint_insert
            BEFORE INSERT ON session_checkpoint
            BEGIN SELECT RAISE(ABORT, 'filter boundary: checkpoint write refused'); END;
            """, """
            CREATE TRIGGER filter_boundary_reject_checkpoint_update
            BEFORE UPDATE ON session_checkpoint
            BEGIN SELECT RAISE(ABORT, 'filter boundary: checkpoint write refused'); END;
            """], in: directory)
        FixtureTransport.holdingAll.withLock { $0 = true }
        FixtureTransport.allEntered.withLock { $0 = 0 }
        defer { FixtureTransport.releaseAll() }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(FixtureTransport.allEntered.withLock { $0 }, 0)
        let filter = ReaderFilter(languages: ["pt"], mood: .fun)
        let confirmed = readerKey(root: root, filter: filter)
        let failures = Mutex(0)
        try await root.applyFilterFromSheet(filter, preset: .everything) {
            failures.withLock { $0 += 1 }
        }
        XCTAssertEqual(try persisted(directory).activeContextKey, confirmed,
            "the selection is durable even when presentation fails")
        XCTAssertTrue(root.association === session, "the previous feed stays")

        let enteredDeadline = Date().addingTimeInterval(10)
        while Date() < enteredDeadline, FixtureTransport.allEntered.withLock({ $0 }) == 0 {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThan(FixtureTransport.allEntered.withLock { $0 }, 0)
        // Release the launch successfully while the checkpoint trigger is still installed: the failure happens
        // at the real durable checkpoint, not at the transport.
        FixtureTransport.releaseAll()
        let failureDeadline = Date().addingTimeInterval(10)
        while Date() < failureDeadline, failures.withLock({ $0 }) == 0 {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(failures.withLock { $0 }, 1, "the host is told saved-but-not-presented")
        XCTAssertTrue(root.association === session)

        try install(["DROP TRIGGER filter_boundary_reject_checkpoint_insert",
            "DROP TRIGGER filter_boundary_reject_checkpoint_update"], in: directory)
        try await root.activateConfirmedFilter()
        XCTAssertEqual(root.association?.contextKey, confirmed)
        XCTAssertFalse(root.association === session)
        await root.association?.close()
    }

    /// A-held → B → A where the held A launch reaches a real checkpoint refusal: the obsolete attempt must not
    /// consume the pending latest. Both the retry attempt counter and the later recovery prove the latest key was
    /// rebuilt, and the only error reported belongs to the current saved-not-presented selection.
    func testHeldAFailureAfterBAndALeavesNoObsoleteErrorAndInstallsLatest() async throws {
        let (root, session, directory) = try await launched()
        try install(["""
            CREATE TRIGGER nf03_reject_checkpoint_insert
            BEFORE INSERT ON session_checkpoint
            BEGIN SELECT RAISE(ABORT, 'nf03 checkpoint refused'); END;
            """, """
            CREATE TRIGGER nf03_reject_checkpoint_update
            BEFORE UPDATE ON session_checkpoint
            BEGIN SELECT RAISE(ABORT, 'nf03 checkpoint refused'); END;
            """], in: directory)
        let constructionsBefore = root.sessionConstructions
        FixtureTransport.holdingAll.withLock { $0 = true }
        FixtureTransport.allEntered.withLock { $0 = 0 }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(FixtureTransport.allEntered.withLock { $0 }, 0)
        let a = ReaderFilter(mood: .fun)
        let b = ReaderFilter(mood: .serious)
        let aKey = readerKey(root: root, filter: a)
        let failures = Mutex(0)

        let firstA = Task { @MainActor in
            try await root.applyFilterFromSheet(a, preset: .everything) {
                failures.withLock { $0 += 1 }
            }
        }
        let enteredDeadline = Date().addingTimeInterval(10)
        while Date() < enteredDeadline, FixtureTransport.allEntered.withLock({ $0 }) == 0 {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThan(FixtureTransport.allEntered.withLock { $0 }, 0)

        try await root.applyFilterFromSheet(b, preset: .everything) {
            failures.withLock { $0 += 1 }
        }
        try await root.applyFilterFromSheet(a, preset: .everything) {
            failures.withLock { $0 += 1 }
        }
        // The held launch finishes successfully; the refusal is the real checkpoint write.
        FixtureTransport.releaseAll()
        try await firstA.value
        defer { FixtureTransport.releaseAll() }

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, failures.withLock({ $0 }) == 0 {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(failures.withLock { $0 }, 1,
            "the current saved-not-presented selection is reported once")
        XCTAssertTrue(root.association === session, "no obsolete association installed")
        XCTAssertEqual(try persisted(directory).activeContextKey, aKey)
        XCTAssertGreaterThanOrEqual(root.sessionConstructions - constructionsBefore, 2,
            "the latest A was constructed again after the obsolete first A failed")

        try install(["DROP TRIGGER nf03_reject_checkpoint_insert",
            "DROP TRIGGER nf03_reject_checkpoint_update"], in: directory)
        try await root.activateConfirmedFilter()
        XCTAssertEqual(root.association?.contextKey, aKey)
        await root.association?.close()
    }

    /// The screen belongs to the valid latest association before the captured old one is closed. The fixture
    /// keeps a real request of the old session at the transport gate, so `retired.close()` reaches its actual
    /// `settleInFlight` wait. At that instant the installed key — not just the final key — must already be the
    /// confirmed selection; retiring first left the old association on screen while the replacement was ready.
    func testValidLatestIsInstalledBeforeTheCapturedOldCloseSettles() async throws {
        let (root, old, directory) = try await launched()
        FixtureTransport.holdingAll.withLock { $0 = true }
        FixtureTransport.allEntered.withLock { $0 = 0 }
        defer { FixtureTransport.releaseAll() }
        let feed = try XCTUnwrap(old.feeds.first)
        let target = try XCTUnwrap(AcquisitionTargetAuthority(database: old.database)
            .target(id: feed.targetID))
        let bounds = try XCTUnwrap(AcquisitionWorkBounds(batchCapacity: 1,
            observationCapacityPerBatch: 12, byteCapacityPerBatch: 8_000_000))
        let refresh = Task {
            try? await old.coordinator.execute(.start(target: target, bounds: bounds))
        }
        let enteredDeadline = Date().addingTimeInterval(5)
        while Date() < enteredDeadline, FixtureTransport.allEntered.withLock({ $0 }) == 0 {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThan(FixtureTransport.allEntered.withLock { $0 }, 0,
            "the old session really has a request in flight")
        // New requests answer normally from here; the held old one stays at the gate for the retirement.
        FixtureTransport.holdingAll.withLock { $0 = false }

        let filter = ReaderFilter(mood: .fun)
        let confirmed = readerKey(root: root, filter: filter)
        let activation = Task { @MainActor in
            try await root.applyFilter(filter, preset: .everything)
        }
        let retiredDeadline = Date().addingTimeInterval(10)
        while Date() < retiredDeadline, old.active {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(old.active, "the captured old association really began retiring")
        XCTAssertEqual(root.association?.contextKey, confirmed,
            "the valid latest owns the screen before the captured old close settles")
        XCTAssertFalse(root.association === old, "the old association is not what the screen presents")

        FixtureTransport.releaseAll()
        try await activation.value
        XCTAssertEqual(root.association?.contextKey, confirmed)
        await root.association?.close()
        await refresh.value
    }

    /// The production lens model must describe the presented association, not the confirmed key, while the
    /// replacement is held; after the handoff it follows the new selection.
    func testLensSelectionDescribesThePriorFeedUntilTheHandoff() async throws {
        let (root, session, _) = try await launched()
        FixtureTransport.holdingAll.withLock { $0 = true }
        FixtureTransport.allEntered.withLock { $0 = 0 }
        defer { FixtureTransport.releaseAll() }
        try await Task.sleep(for: .milliseconds(150))
        let prior = session.contextKey
        let filter = ReaderFilter(languages: ["pt"], mood: .fun)
        let confirmed = readerKey(root: root, filter: filter)
        let failures = Mutex(0)
        try await root.applyFilterFromSheet(filter, preset: .everything) {
            failures.withLock { $0 += 1 }
        }
        let enteredDeadline = Date().addingTimeInterval(10)
        while Date() < enteredDeadline, FixtureTransport.allEntered.withLock({ $0 }) == 0 {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThan(FixtureTransport.allEntered.withLock { $0 }, 0)
        let pending = root.filterSelectionForLens()
        XCTAssertTrue(pending.isPending)
        XCTAssertEqual(pending.filter, prior.filter, "the lens states the prior feed's criteria")
        XCTAssertEqual(pending.preset, prior.preset, "the lens states the prior preset")
        XCTAssertNotEqual(pending.filter, confirmed.filter)

        FixtureTransport.releaseAll()
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, root.association?.contextKey != confirmed {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(failures.withLock { $0 }, 0)
        let presented = root.filterSelectionForLens()
        XCTAssertFalse(presented.isPending)
        XCTAssertEqual(presented.filter, confirmed.filter)
        XCTAssertEqual(presented.preset, confirmed.preset)
        await root.association?.close()
    }

    /// A held onApply: isApplying is visible, duplicate apply is refused, and an edit attempted during the
    /// commit is rejected by the existing store owner (not silently applied and then reset).
    func testHeldApplyExposesPendingAndRejectsLaterEdits() async throws {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let store = ReaderFilterStore(onApply: { _, _ in
            var iterator = stream.makeAsyncIterator()
            _ = await iterator.next()
        })
        store.select(mood: .fun)
        let applyTask = Task { try await store.apply() }
        let startedDeadline = Date().addingTimeInterval(2)
        while Date() < startedDeadline, !store.isApplying { await Task.yield() }
        XCTAssertTrue(store.isApplying, "the existing pending state is visible during the durable write")
        let draftBefore = store.draft
        store.select(mood: .serious)
        XCTAssertEqual(store.draft, draftBefore, "a later edit is rejected while the commit is pending")
        let duplicate = try await store.apply()
        XCTAssertFalse(duplicate, "a duplicate apply does not start a second writer")
        XCTAssertTrue(store.isApplying)

        continuation.yield(())
        continuation.finish()
        try await applyTask.value
        XCTAssertFalse(store.isApplying)
        XCTAssertEqual(store.applied.mood, .fun, "the captured confirmation is the durable one")
        XCTAssertEqual(store.draft.mood, .fun)
    }

    private func readerKey(root: AppComposition, filter: ReaderFilter) -> ContextKey {
        ContextKey(request: root.currentContextKey.request, preset: .everything, filter: filter,
            searchScope: root.currentContextKey.searchScope)
    }
}
