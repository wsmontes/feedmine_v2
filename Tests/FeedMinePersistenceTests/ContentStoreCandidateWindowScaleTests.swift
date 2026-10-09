import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence

final class ContentStoreCandidateWindowScaleTests: XCTestCase {
    private static let baseDate = 1_700_000_000.0
    private static let source = uuid(kind: 3, number: 1)
    private static let sparseSource = uuid(kind: 4, number: 1)

    private static func uuid(kind: Int, number: Int) -> String {
        String(format: "%08x-0000-0000-0000-%012x", kind, number)
    }
    private static func origin(_ number: Int) -> OriginRecordID {
        OriginRecordID(rawValue: UUID(uuidString: uuid(kind: 0, number: number))!)
    }
    private static func date(_ number: Int) -> Date {
        Date(timeIntervalSince1970: baseDate + Double(number / 4))
    }
    private func withFixture(count: Int, sparsePrefix: Int? = nil, extras: Bool = false,
        _ body: (RuntimeDatabase, ContentStore) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
        try database.write { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "PRAGMA foreign_keys"), 1)
            let record = try db.makeStatement(sql: """
                INSERT INTO origin_records (id, object_connector_kind, object_namespace, object_value,
                    object_role, availability, first_observed_at, last_observed_at)
                VALUES (?, 'scale-test', 'objects', ?, 'object', 'available', ?, ?)
                """)
            let revision = try db.makeStatement(sql: """
                INSERT INTO origin_revisions (id, origin_record_id, headline, summary, observed_at)
                VALUES (?, ?, ?, ?, ?)
                """)
            let membership = try db.makeStatement(sql: """
                INSERT INTO source_memberships (origin_record_id, source_id, membership_kind,
                    first_observed_at, last_observed_at) VALUES (?, ?, 'direct', ?, ?)
                """)
            let current = try db.makeStatement(sql: "UPDATE origin_records SET current_revision_id = ? WHERE id = ?")
            let supply = try db.makeStatement(sql: """
                INSERT INTO selection_supply (origin_record_id, origin_revision_id, sort_date, sort_date_basis)
                VALUES (?, ?, ?, 'observedFallback')
                """)
            for index in 1...count {
                let origin = Self.uuid(kind: 0, number: index), version = Self.uuid(kind: 1, number: index)
                let date = Self.date(index).timeIntervalSince1970
                try record.execute(arguments: [origin, String(index), date, date])
                try revision.execute(arguments: [version, origin, "current \(index)", "summary \(index)", date])
                try membership.execute(arguments: [origin, Self.source, date, date])
                try current.execute(arguments: [version, origin])
                try supply.execute(arguments: [origin, version, date])
                if let prefix = sparsePrefix, (count - prefix - 2...count - prefix).contains(index) {
                    try membership.execute(arguments: [origin, Self.sparseSource, date, date])
                }
                if extras && index > count - 5 {
                    for member in 1...512 {
                        try membership.execute(arguments: [origin, Self.uuid(kind: 5, number: member), date, date])
                    }
                }
                if extras && index > count - 12 {
                    for historical in 1...200 {
                        let id = Self.uuid(kind: 2, number: index * 200 + historical)
                        // Historical dates exceed current dates deliberately: history
                        // must not enter the projection walk or change its ordering.
                        try revision.execute(arguments: [id, origin, "historical", nil, date + 1_000_000])
                    }
                }
            }
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM selection_supply"), count)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM origin_records"), count)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM origin_revisions"), count + (extras ? 2_400 : 0))
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM source_memberships"), count + (sparsePrefix == nil ? 0 : 3) + (extras ? 2_560 : 0))
            XCTAssertEqual(try Int.fetchOne(db, sql: "PRAGMA foreign_keys"), 1)
            XCTAssertTrue(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
        }
        try body(database, ContentStore(database: database))
    }

    private func assertWindow(_ result: ContentStore.CandidateWindow, capacity: Int,
        examined: [Int], eligible: [Int], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(result.examinedCount, examined.count, file: file, line: line)
        XCTAssertLessThanOrEqual(result.examinedCount, capacity, file: file, line: line)
        XCTAssertLessThanOrEqual(result.records.count, result.examinedCount, file: file, line: line)
        XCTAssertEqual(result.records.map(\.originRecordID), eligible.map(Self.origin), file: file, line: line)
        XCTAssertEqual(result.records.map { $0.originRevisionID.rawValue.uuidString.lowercased() },
            eligible.map { Self.uuid(kind: 1, number: $0) }, file: file, line: line)
        XCTAssertEqual(result.records.map(\.headline), eligible.map { "current \($0)" }, file: file, line: line)
        XCTAssertEqual(result.records.map(\.sortDate), eligible.map(Self.date), file: file, line: line)
        XCTAssertEqual(result.exhausted, examined.count < capacity, file: file, line: line)
        let expected = examined.last.map { ContentStore.CandidateCursor(sortDate: Self.date($0), originRecordID: Self.origin($0)) }
        XCTAssertEqual(result.nextCursor, expected, file: file, line: line)
    }

    func testTenThousandRowsBoundAndKeysetProgression() throws {
        try withFixture(count: 10_000) { _, store in
            let capacity = 23 // Test-local evidence size, never a product default.
            let first = try store.candidateWindow(sourceID: nil, after: nil, examinedCapacity: capacity)
            let firstIndices = Array(stride(from: 10_000, through: 10_000 - capacity + 1, by: -1))
            assertWindow(first, capacity: capacity, examined: firstIndices, eligible: firstIndices)
            let second = try store.candidateWindow(sourceID: nil, after: first.nextCursor, examinedCapacity: capacity)
            let secondIndices = Array(stride(from: 10_000 - capacity, through: 10_000 - 2 * capacity + 1, by: -1))
            assertWindow(second, capacity: capacity, examined: secondIndices, eligible: secondIndices)
            XCTAssertTrue(Set(first.records.map(\.originRecordID)).isDisjoint(with: second.records.map(\.originRecordID)))
            XCTAssertNotEqual(first.nextCursor, second.nextCursor)
        }
    }

    func testHundredThousandRowsSparseSourceFanoutHistoryPlansAndTail() throws {
        let count = 100_000, capacity = 37, emptyWindows = 8
        let prefix = capacity * emptyWindows
        try withFixture(count: count, sparsePrefix: prefix, extras: true) { database, store in
            let firstIndices = Array(stride(from: count, through: count - capacity + 1, by: -1))
            let first = try store.candidateWindow(sourceID: nil, after: nil, examinedCapacity: capacity)
            assertWindow(first, capacity: capacity, examined: firstIndices, eligible: firstIndices)
            let secondIndices = Array(stride(from: count - capacity, through: count - 2 * capacity + 1, by: -1))
            let second = try store.candidateWindow(sourceID: nil, after: first.nextCursor, examinedCapacity: capacity)
            assertWindow(second, capacity: capacity, examined: secondIndices, eligible: secondIndices)
            // A middle-population seek is independent of prefix size and history.
            let middle = ContentStore.CandidateCursor(sortDate: Self.date(50_001), originRecordID: Self.origin(50_001))
            let middleIndices = Array(stride(from: 50_000, through: 50_000 - capacity + 1, by: -1))
            assertWindow(try store.candidateWindow(sourceID: nil, after: middle, examinedCapacity: capacity),
                capacity: capacity, examined: middleIndices, eligible: middleIndices)

            var cursor: ContentStore.CandidateCursor?
            var examinedOrigins = Set<OriginRecordID>()
            let requested = SourceID(rawValue: UUID(uuidString: Self.sparseSource)!)
            // Exactly nine test windows: no unbounded candidate-count/refill loop.
            for windowIndex in 0...emptyWindows {
                let top = count - windowIndex * capacity
                let indices = Array(stride(from: top, through: top - capacity + 1, by: -1))
                let expectedEligible = indices.filter { (count - prefix - 2...count - prefix).contains($0) }
                let result = try store.candidateWindow(sourceID: requested, after: cursor, examinedCapacity: capacity)
                assertWindow(result, capacity: capacity, examined: indices, eligible: expectedEligible)
                XCTAssertNotEqual(result.nextCursor, cursor)
                // Deterministic ordering + exact final examined cursor establishes
                // each bounded interval; no interval overlaps in this stable supply.
                XCTAssertTrue(examinedOrigins.isDisjoint(with: indices.map(Self.origin)))
                examinedOrigins.formUnion(indices.map(Self.origin))
                if windowIndex < emptyWindows { XCTAssertEqual(result.records, []) }
                else { XCTAssertEqual(result.records.count, 3) }
                cursor = result.nextCursor
            }
            XCTAssertEqual(examinedOrigins.count, capacity * (emptyWindows + 1))

            let nearTail = ContentStore.CandidateCursor(sortDate: Self.date(capacity), originRecordID: Self.origin(capacity))
            let remaining = Array(stride(from: capacity - 1, through: 1, by: -1))
            assertWindow(try store.candidateWindow(sourceID: nil, after: nearTail, examinedCapacity: capacity),
                capacity: capacity, examined: remaining, eligible: remaining)
            let exactTail = ContentStore.CandidateCursor(sortDate: Self.date(capacity + 1), originRecordID: Self.origin(capacity + 1))
            let tailIndices = Array(stride(from: capacity, through: 1, by: -1))
            let fullTail = try store.candidateWindow(sourceID: nil, after: exactTail, examinedCapacity: capacity)
            assertWindow(fullTail, capacity: capacity, examined: tailIndices, eligible: tailIndices)
            assertWindow(try store.candidateWindow(sourceID: nil, after: fullTail.nextCursor, examinedCapacity: capacity),
                capacity: capacity, examined: [], eligible: [])
            for source in [nil, requested] {
                var milliseconds: [Double] = []
                for _ in 0..<50 {
                    let start = ProcessInfo.processInfo.systemUptime
                    let sample = try store.candidateWindow(sourceID: source, after: middle, examinedCapacity: capacity)
                    milliseconds.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                    XCTAssertLessThanOrEqual(sample.examinedCount, capacity)
                }
                milliseconds.sort()
                print("T7 candidateWindow 100k source=\(source == nil ? "main" : "sparse") capacity=\(capacity) p50ms=\(milliseconds[24]) p95ms=\(milliseconds[47])")
            }
            try assertQueryPlans(database, capacity: capacity, middle: middle)
        }
    }

    private func assertQueryPlans(_ database: RuntimeDatabase, capacity: Int, middle: ContentStore.CandidateCursor) throws {
        // SQL mirrors ContentStore's actual first/keyset/existence queries. Assert
        // semantic plan facts, never a complete SQLite-version-dependent string.
        try database.read { db in
            func plan(_ sql: String, arguments: StatementArguments) throws -> [String] {
                try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN " + sql, arguments: arguments).map { $0["detail"] as String }
            }
            let select = "SELECT origin_record_id, origin_revision_id, sort_date, sort_date_basis FROM selection_supply"
            let order = " ORDER BY sort_date DESC, origin_record_id DESC LIMIT ?"
            let first = try plan(select + order, arguments: [capacity])
            XCTAssertTrue(first.contains { $0.contains("selection_supply_order") }, "\(first)")
            XCTAssertFalse(first.contains { $0.uppercased().contains("TEMP B-TREE") }, "\(first)")
            let keyset = try plan(select + " WHERE (sort_date, origin_record_id) < (?, ?)" + order,
                arguments: [middle.sortDate.timeIntervalSince1970, middle.originRecordID.rawValue.uuidString.lowercased(), capacity])
            XCTAssertTrue(keyset.contains { $0.contains("selection_supply_order") }, "\(keyset)")
            XCTAssertTrue(keyset.contains { $0.uppercased().contains("SEARCH") && $0.contains("selection_supply_order") && $0.contains("sort_date") && $0.contains("<") }, "\(keyset)")
            XCTAssertFalse(keyset.contains { $0.uppercased().contains("TEMP B-TREE") }, "\(keyset)")

            let indexRows = try Row.fetchAll(db, sql: "PRAGMA index_list('source_memberships')")
            let primary = try XCTUnwrap(indexRows.first { ($0["origin"] as String) == "pk" })
            let primaryName: String = primary["name"]
            let columns = try Row.fetchAll(db, sql: "SELECT name FROM pragma_index_info(?) ORDER BY seqno", arguments: [primaryName])
                .map { $0["name"] as String }
            XCTAssertEqual(columns, ["origin_record_id", "source_id"])
            let requested = try plan("SELECT EXISTS(SELECT 1 FROM source_memberships WHERE origin_record_id = ? AND source_id = ?)",
                arguments: [Self.uuid(kind: 0, number: 100_000), Self.sparseSource])
            XCTAssertTrue(requested.contains { $0.contains(primaryName) && $0.uppercased().contains("SEARCH") && $0.contains("origin_record_id=?") && $0.contains("source_id=?") }, "\(requested)")
            let any = try plan("SELECT EXISTS(SELECT 1 FROM source_memberships WHERE origin_record_id = ?)",
                arguments: [Self.uuid(kind: 0, number: 100_000)])
            XCTAssertTrue(any.contains { $0.contains(primaryName) && $0.uppercased().contains("SEARCH") && $0.contains("origin_record_id=?") }, "\(any)")
        }
    }

    func testCandidateWindowSQLHasNoOffsetAndMatchesExplainedQueries() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repo.appendingPathComponent("Sources/FeedMinePersistence/ContentStore.swift"), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "    public func candidateWindow("))
        let end = try XCTUnwrap(source.range(of: "    public enum CurrentRevisionExpectation:", range: start.upperBound..<source.endIndex))
        let path = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertFalse(path.uppercased().contains("OFFSET"))
        XCTAssertTrue(path.contains("SELECT origin_record_id, origin_revision_id, sort_date, sort_date_basis FROM selection_supply"))
        XCTAssertTrue(path.contains(#"conditions.append("(sort_date, origin_record_id) < (?, ?)")"#))
        XCTAssertTrue(path.contains("ORDER BY sort_date DESC, origin_record_id DESC LIMIT ?"))
        XCTAssertTrue(path.contains("SELECT EXISTS(SELECT 1 FROM source_memberships WHERE origin_record_id = ?)"))
        XCTAssertTrue(path.contains("SELECT EXISTS(SELECT 1 FROM source_memberships WHERE origin_record_id = ? AND source_id = ?)"))
    }
}
