import XCTest
import Foundation
import FeedMineDomain
import FeedMinePersistence
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

    private func readerKey(root: AppComposition, filter: ReaderFilter) -> ContextKey {
        ContextKey(request: root.currentContextKey.request, preset: .everything, filter: filter,
            searchScope: root.currentContextKey.searchScope)
    }
}
