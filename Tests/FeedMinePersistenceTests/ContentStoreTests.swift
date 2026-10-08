import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence

final class ContentStoreTests: XCTestCase {
    private typealias Change = ContentStore.CanonicalChange
    private let time = Date(timeIntervalSince1970: 1_700_000_000)

    private func withLocation(_ body: (RuntimeDatabaseLocation) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(RuntimeDatabaseLocation(directory: root))
    }
    private func identity(_ value: String = " Object É ", role: ExternalIdentityRole = .object,
        connector: String = " Connector A ") -> ExternalIdentity {
        ExternalIdentity(connectorKind: ConnectorKind(rawValue: connector), namespace: " Namespace ", value: value, role: role)
    }
    private func revision(_ origin: OriginRecordID, id: OriginRevisionID = OriginRevisionID(),
        version: ExternalIdentity? = nil, headline: String? = "", authored: Date? = nil,
        observed: Date? = nil, full: Bool = false) -> OriginRevision {
        OriginRevision(id: id, originRecordID: origin, externalVersionIdentity: version,
            headline: headline, summary: full ? "summary é" : nil, bodyText: full ? "body\ntext" : nil,
            authoredAt: authored, modifiedAt: full ? time.addingTimeInterval(5) : nil,
            observedAt: observed ?? time, language: full ? "pt-BR" : nil,
            primaryLink: full ? URL(string: "https://example.test/A%2Fb?q=%C3%A9#Fragment")! : nil,
            searchProjection: full ? "" : nil, providerID: full ? ProviderID() : nil)
    }
    private func change(_ revision: OriginRevision, object: ExternalIdentity? = nil,
        availability: OriginAvailability = .available, observed: Date? = nil,
        expected: ContentStore.CurrentRevisionExpectation = .none,
        update: ContentStore.CurrentRevisionUpdate = .useSuppliedRevision,
        mutations: [ContentStore.MembershipMutation] = []) -> Change {
        Change(recordID: revision.originRecordID, externalObjectIdentity: object ?? identity(), revision: revision,
            availability: availability, observedAt: observed ?? time, expectedCurrent: expected,
            currentUpdate: update, membershipMutations: mutations)
    }
    private func count(_ table: String, _ database: RuntimeDatabase) throws -> Int {
        try database.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table)")! }
    }
    private func assertError(_ expected: ContentStoreError, _ body: () throws -> Void,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertEqual(error as? ContentStoreError, expected, file: file, line: line)
        }
    }
    private struct Supply: Equatable, Sendable {
        let revision: String
        let date: Double
        let basis: String
    }
    private func supply(_ origin: OriginRecordID, _ database: RuntimeDatabase) throws -> Supply? {
        try database.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM selection_supply WHERE origin_record_id = ?",
                arguments: [origin.rawValue.uuidString.lowercased()]).map {
                Supply(revision: $0["origin_revision_id"], date: $0["sort_date"], basis: $0["sort_date_basis"])
            }
        }
    }
    private func assertProjection(_ origin: OriginRecordID, _ database: RuntimeDatabase,
        file: StaticString = #filePath, line: UInt = #line) throws {
        let store = ContentStore(database: database)
        let record = try store.originRecord(id: origin)
        let current = try store.currentRevision(originRecordID: origin)
        let members = try store.memberships(originRecordID: origin)
        let actual = try supply(origin, database)
        let eligible = (record?.availability == .available || record?.availability == .updated)
            && current != nil && !members.isEmpty
        XCTAssertEqual(actual != nil, eligible, file: file, line: line)
        if eligible, let current {
            XCTAssertEqual(actual, Supply(revision: current.id.rawValue.uuidString.lowercased(),
                date: (current.authoredAt ?? current.observedAt).timeIntervalSince1970,
                basis: current.authoredAt == nil ? "observedFallback" : "authored"), file: file, line: line)
        }
    }

    func testFullRoundtripAndOptionalPayloadAfterCloseAndReopen() throws {
        try withLocation { location in
            let origin = OriginRecordID(), source = SourceID()
            let v1 = revision(origin, version: identity("V1", role: .version), authored: time.addingTimeInterval(-50), full: true)
            let v2 = revision(origin, headline: nil, observed: time.addingTimeInterval(10))
            let record = OriginRecord(id: origin, externalObjectIdentity: identity(), currentRevisionID: v1.id,
                availability: .available, firstObservedAt: time, lastObservedAt: time)
            let member = SourceMembership(originRecordID: origin, sourceID: source, kind: .direct, firstObservedAt: time, lastObservedAt: time)
            func verify(_ database: RuntimeDatabase) throws {
                let store = ContentStore(database: database)
                XCTAssertEqual(try store.originRecord(id: origin), record)
                XCTAssertEqual(try store.originRevision(id: v1.id), v1)
                XCTAssertEqual(try store.originRevision(id: v2.id), v2)
                XCTAssertEqual(try store.currentRevision(originRecordID: origin), v1)
                XCTAssertEqual(try store.memberships(originRecordID: origin), [member])
                try assertProjection(origin, database)
            }
            do {
                let database = try RuntimeDatabase(location: location), store = ContentStore(database: database)
                try store.commitCanonicalChange(change(v1, mutations: [.upsert(sourceID: source, kind: .direct, observedAt: time)]))
                try store.commitCanonicalChange(change(v2, expected: .revision(v1.id), update: .unchanged))
                try verify(database)
            }
            try verify(RuntimeDatabase(location: location))
        }
    }

    func testV2SwitchAndExactReplayPreserveV1() throws {
        try withLocation { location in
            let database = try RuntimeDatabase(location: location), store = ContentStore(database: database)
            let origin = OriginRecordID(), source = SourceID(), v1 = revision(origin, authored: time.addingTimeInterval(-100))
            try store.commitCanonicalChange(change(v1, mutations: [.upsert(sourceID: source, kind: .direct, observedAt: time)]))
            let v2 = revision(origin, version: identity("v2", role: .version), observed: time.addingTimeInterval(20), full: true)
            try store.commitCanonicalChange(change(v2, observed: time.addingTimeInterval(-20), expected: .revision(v1.id)))
            XCTAssertEqual(try store.currentRevision(originRecordID: origin), v2)
            XCTAssertEqual(try store.originRevision(id: v1.id), v1)
            XCTAssertEqual(try store.originRevision(id: v2.id), v2)
            XCTAssertEqual(try store.originRecord(id: origin)?.firstObservedAt, time)
            XCTAssertEqual(try store.originRecord(id: origin)?.lastObservedAt, time.addingTimeInterval(-20))
            let replay = change(v2, expected: .revision(v2.id), mutations: [.upsert(sourceID: source, kind: .direct, observedAt: time)])
            try store.commitCanonicalChange(replay)
            try store.commitCanonicalChange(replay)
            XCTAssertEqual(try count("origin_records", database), 1)
            XCTAssertEqual(try count("origin_revisions", database), 2)
            XCTAssertEqual(try count("source_memberships", database), 1)
            XCTAssertEqual(try count("selection_supply", database), 1)
            try assertProjection(origin, database)
        }
    }

    func testAvailabilityMembershipAndClearTransitions() throws {
        try withLocation { location in
            let database = try RuntimeDatabase(location: location), store = ContentStore(database: database)
            let origin = OriginRecordID(), source = SourceID(), v1 = revision(origin)
            try store.commitCanonicalChange(change(v1, mutations: [.upsert(sourceID: source, kind: .direct, observedAt: time)]))
            for availability in [OriginAvailability.updated, .removed, .revoked, .unknown, .available] {
                try store.commitCanonicalChange(change(v1, availability: availability, expected: .revision(v1.id), update: .unchanged))
                XCTAssertEqual(try store.originRecord(id: origin)?.availability, availability)
                try assertProjection(origin, database)
            }
            let next = time.addingTimeInterval(10)
            try store.commitCanonicalChange(change(v1, expected: .revision(v1.id), mutations: [.upsert(sourceID: source, kind: .derived, observedAt: next)]))
            XCTAssertEqual(try store.memberships(originRecordID: origin), [SourceMembership(originRecordID: origin,
                sourceID: source, kind: .derived, firstObservedAt: time, lastObservedAt: next)])
            try store.commitCanonicalChange(change(v1, expected: .revision(v1.id), mutations: [.remove(sourceID: source)]))
            XCTAssertEqual(try store.memberships(originRecordID: origin), [])
            try assertProjection(origin, database)
            XCTAssertEqual(try store.originRevision(id: v1.id), v1)
            let low = SourceID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
            let high = SourceID(rawValue: UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!)
            try store.commitCanonicalChange(change(v1, expected: .revision(v1.id), mutations: [
                .upsert(sourceID: high, kind: .direct, observedAt: next), .upsert(sourceID: low, kind: .derived, observedAt: next), .remove(sourceID: source)]))
            XCTAssertEqual(try store.memberships(originRecordID: origin).map(\.sourceID), [low, high])
            try assertProjection(origin, database)
            try store.commitCanonicalChange(change(v1, expected: .revision(v1.id), update: .clear))
            XCTAssertNil(try store.originRecord(id: origin)?.currentRevisionID)
            XCTAssertNil(try store.currentRevision(originRecordID: origin))
            XCTAssertEqual(try store.originRevision(id: v1.id), v1)
            try assertProjection(origin, database)
        }
    }

    func testStaleExpectationLeavesAllAuthorityAndProjectionUnchanged() throws {
        try withLocation { location in
            let database = try RuntimeDatabase(location: location), store = ContentStore(database: database)
            let origin = OriginRecordID(), source = SourceID(), v1 = revision(origin), wrong = OriginRevisionID()
            try store.commitCanonicalChange(change(v1, mutations: [.upsert(sourceID: source, kind: .direct, observedAt: time)]))
            let before = try store.originRecord(id: origin), members = try store.memberships(originRecordID: origin), projection = try supply(origin, database)
            let v2 = revision(origin)
            assertError(.staleCurrent(expected: wrong, actual: v1.id)) {
                try store.commitCanonicalChange(change(v2, availability: .removed, observed: time.addingTimeInterval(20), expected: .revision(wrong), mutations: [.remove(sourceID: source)]))
            }
            XCTAssertEqual(try store.originRecord(id: origin), before)
            XCTAssertEqual(try store.memberships(originRecordID: origin), members)
            XCTAssertEqual(try supply(origin, database), projection)
            XCTAssertEqual(try count("origin_revisions", database), 1)
            XCTAssertNil(try store.originRevision(id: v2.id))
            let new = revision(OriginRecordID())
            assertError(.staleCurrent(expected: wrong, actual: nil)) {
                try store.commitCanonicalChange(change(new, object: identity("new"), expected: .revision(wrong)))
            }
            XCTAssertNil(try store.originRecord(id: new.originRecordID))
        }
    }

    func testIdentityRevisionAndVersionConflictsRollback() throws {
        try withLocation { location in
            let database = try RuntimeDatabase(location: location), store = ContentStore(database: database)
            let origin = OriginRecordID(), source = SourceID()
            let version = identity("v1", role: .version), v1 = revision(origin, version: version)
            try store.commitCanonicalChange(change(v1, mutations: [.upsert(sourceID: source, kind: .direct, observedAt: time)]))
            let other = revision(OriginRecordID())
            assertError(.originIdentityConflict) { try store.commitCanonicalChange(change(other)) }
            assertError(.originIdentityConflict) { try store.commitCanonicalChange(change(v1, object: identity("different"), expected: .revision(v1.id))) }
            let changed = revision(origin, id: v1.id, version: version, headline: "changed")
            assertError(.revisionConflict) { try store.commitCanonicalChange(change(changed, expected: .revision(v1.id))) }
            let duplicateVersion = revision(origin, version: version)
            assertError(.versionIdentityConflict) { try store.commitCanonicalChange(change(duplicateVersion, expected: .revision(v1.id))) }
            XCTAssertEqual(try store.originRevision(id: v1.id), v1)
            XCTAssertEqual(try count("origin_records", database), 1)
            XCTAssertEqual(try count("origin_revisions", database), 1)
            XCTAssertEqual(try store.memberships(originRecordID: origin).count, 1)
            try assertProjection(origin, database)
        }
    }

    func testInvalidCommandShapesAndNonfiniteDatesLeaveNoRows() throws {
        try withLocation { location in
            let database = try RuntimeDatabase(location: location), store = ContentStore(database: database)
            let origin = OriginRecordID(), source = SourceID(), v1 = revision(origin)
            assertError(.invalidChange("object role")) { try store.commitCanonicalChange(change(v1, object: identity(role: .alias))) }
            let wrongVersion = revision(origin, version: identity("v1", role: .version, connector: "B"))
            assertError(.invalidChange("version role/connector")) { try store.commitCanonicalChange(change(wrongVersion)) }
            let wrongRole = revision(origin, version: identity("v1", role: .object))
            assertError(.invalidChange("version role/connector")) { try store.commitCanonicalChange(change(wrongRole)) }
            let wrongOrigin = Change(recordID: OriginRecordID(), externalObjectIdentity: identity(), revision: v1,
                availability: .available, observedAt: time, expectedCurrent: .none, currentUpdate: .useSuppliedRevision, membershipMutations: [])
            assertError(.invalidChange("revision origin")) { try store.commitCanonicalChange(wrongOrigin) }
            assertError(.invalidChange("duplicate membership mutation")) {
                try store.commitCanonicalChange(change(v1, mutations: [.upsert(sourceID: source, kind: .direct, observedAt: time), .remove(sourceID: source)]))
            }
            assertError(.invalidRepresentation("last_observed_at")) {
                try store.commitCanonicalChange(change(v1, observed: Date(timeIntervalSince1970: .infinity)))
            }
            assertError(.invalidRepresentation("observed_at")) {
                try store.commitCanonicalChange(change(revision(origin, observed: Date(timeIntervalSince1970: .nan))))
            }
            assertError(.invalidRepresentation("authored_at")) {
                try store.commitCanonicalChange(change(revision(origin, authored: Date(timeIntervalSince1970: -.infinity))))
            }
            assertError(.invalidRepresentation("membership.observed_at")) {
                try store.commitCanonicalChange(change(v1, mutations: [.upsert(sourceID: source, kind: .direct, observedAt: Date(timeIntervalSince1970: .infinity))]))
            }
            for table in ["origin_records", "origin_revisions", "source_memberships", "selection_supply"] {
                XCTAssertEqual(try count(table, database), 0)
            }
        }
    }

    func testRealProjectionTriggerFailureRollsBackAfterCloseAndReopen() throws {
        try withLocation { location in
            let origin = OriginRecordID(), v1 = revision(origin), source = SourceID()
            do {
                let database = try RuntimeDatabase(location: location)
                try database.write { db in
                    try db.execute(sql: """
                        CREATE TRIGGER abort_supply BEFORE INSERT ON selection_supply BEGIN
                            SELECT RAISE(ABORT, 'test projection failure');
                        END;
                        """)
                }
                XCTAssertThrowsError(try ContentStore(database: database).commitCanonicalChange(change(v1,
                    mutations: [.upsert(sourceID: source, kind: .direct, observedAt: time)]))) { error in
                    guard case let RuntimeDatabaseError.storage(code, message) = error else { return XCTFail("Expected storage failure: \(error)") }
                    XCTAssertEqual(code & 0xff, 19)
                    XCTAssertTrue(message.contains("test projection failure"))
                }
            }
            let database = try RuntimeDatabase(location: location), store = ContentStore(database: database)
            XCTAssertNil(try store.originRecord(id: origin))
            XCTAssertNil(try store.originRevision(id: v1.id))
            XCTAssertNil(try store.currentRevision(originRecordID: origin))
            XCTAssertEqual(try store.memberships(originRecordID: origin), [])
            for table in ["origin_records", "origin_revisions", "source_memberships", "selection_supply"] {
                XCTAssertEqual(try count(table, database), 0)
            }
        }
    }

    func testMissingReadsAndMalformedStoredRepresentations() throws {
        try withLocation { location in
            let database = try RuntimeDatabase(location: location), store = ContentStore(database: database)
            let origin = OriginRecordID(), v1 = revision(origin), source = SourceID()
            XCTAssertNil(try store.originRecord(id: origin))
            XCTAssertNil(try store.originRevision(id: v1.id))
            XCTAssertNil(try store.currentRevision(originRecordID: origin))
            XCTAssertEqual(try store.memberships(originRecordID: origin), [])
            try store.commitCanonicalChange(change(v1, mutations: [.upsert(sourceID: source, kind: .direct, observedAt: time)]))
            try database.write { db in try db.execute(sql: "UPDATE origin_revisions SET provider_id = 'bad-uuid'") }
            assertError(.corruption("provider_id")) { _ = try store.originRevision(id: v1.id) }
            assertError(.corruption("provider_id")) { _ = try store.currentRevision(originRecordID: origin) }
            try database.write { db in
                try db.execute(sql: "UPDATE origin_revisions SET provider_id = NULL, primary_link = 'https://example.test/a b'")
            }
            assertError(.corruption("primary_link")) { _ = try store.originRevision(id: v1.id) }
            try database.write { db in try db.execute(sql: "UPDATE origin_records SET last_observed_at = 'bad-date'") }
            assertError(.corruption("last_observed_at")) { _ = try store.originRecord(id: origin) }
            try database.write { db in try db.execute(sql: "UPDATE source_memberships SET source_id = 'bad-uuid'") }
            assertError(.corruption("source_id")) { _ = try store.memberships(originRecordID: origin) }
        }
    }

    func testOpaqueUnicodeAndCaseIdentityAreNeverNormalized() throws {
        try withLocation { location in
            let database = try RuntimeDatabase(location: location), store = ContentStore(database: database)
            let origin = OriginRecordID(), v1 = revision(origin, headline: "\u{e9}")
            try store.commitCanonicalChange(change(v1, object: identity("\u{e9}")))
            assertError(.originIdentityConflict) {
                try store.commitCanonicalChange(change(v1, object: identity("e\u{301}"), expected: .revision(v1.id)))
            }
            assertError(.revisionConflict) {
                try store.commitCanonicalChange(change(revision(origin, id: v1.id, headline: "e\u{301}"), object: identity("\u{e9}"), expected: .revision(v1.id)))
            }
            for value in ["e\u{301}", "É", " é "] {
                try store.commitCanonicalChange(change(revision(OriginRecordID()), object: identity(value)))
            }
            XCTAssertEqual(try count("origin_records", database), 4)
        }
    }

    func testMissingOrForeignCurrentPointerIsCorruption() throws {
        try withLocation { location in
            let database = try RuntimeDatabase(location: location), store = ContentStore(database: database)
            let origin = OriginRecordID(), v1 = revision(origin)
            try store.commitCanonicalChange(change(v1))
            try assertProjection(origin, database) // Current without membership is absent.
            let foreign = revision(OriginRecordID())
            try store.commitCanonicalChange(change(foreign, object: identity("foreign")))
            var configuration = Configuration()
            configuration.foreignKeysEnabled = false
            let damagedWriter = try DatabaseQueue(path: location.databaseURL.path, configuration: configuration)
            for pointer in [OriginRevisionID(), foreign.id] {
                try damagedWriter.write { db in
                    try db.execute(sql: "UPDATE origin_records SET current_revision_id = ? WHERE id = ?",
                        arguments: [pointer.rawValue.uuidString.lowercased(), origin.rawValue.uuidString.lowercased()])
                }
                assertError(.corruption("current_revision_id")) { _ = try store.currentRevision(originRecordID: origin) }
            }
        }
    }

    func testProjectionUpdateFailurePreservesExistingStateAfterReopen() throws {
        try withLocation { location in
            let origin = OriginRecordID(), source = SourceID(), v1 = revision(origin), v2 = revision(origin)
            do {
                let database = try RuntimeDatabase(location: location), store = ContentStore(database: database)
                try store.commitCanonicalChange(change(v1, mutations: [.upsert(sourceID: source, kind: .direct, observedAt: time)]))
                try database.write { db in
                    try db.execute(sql: """
                        CREATE TRIGGER abort_supply_update BEFORE UPDATE ON selection_supply BEGIN
                            SELECT RAISE(ABORT, 'test projection update failure');
                        END;
                        """)
                }
                XCTAssertThrowsError(try store.commitCanonicalChange(change(v2, availability: .updated,
                    observed: time.addingTimeInterval(10), expected: .revision(v1.id),
                    mutations: [.upsert(sourceID: source, kind: .derived, observedAt: time.addingTimeInterval(10))]))) { error in
                    guard case let RuntimeDatabaseError.storage(code, message) = error else { return XCTFail("Expected storage failure: \(error)") }
                    XCTAssertEqual(code & 0xff, 19)
                    XCTAssertTrue(message.contains("test projection update failure"))
                }
            }
            let database = try RuntimeDatabase(location: location), store = ContentStore(database: database)
            XCTAssertEqual(try store.currentRevision(originRecordID: origin), v1)
            XCTAssertNil(try store.originRevision(id: v2.id))
            XCTAssertEqual(try store.originRecord(id: origin)?.availability, .available)
            XCTAssertEqual(try store.originRecord(id: origin)?.lastObservedAt, time)
            XCTAssertEqual(try store.memberships(originRecordID: origin), [SourceMembership(originRecordID: origin,
                sourceID: source, kind: .direct, firstObservedAt: time, lastObservedAt: time)])
            try assertProjection(origin, database)
        }
    }

    func testNeutralCodecErrorsRemainIndependentOfStores() {
        XCTAssertThrowsError(try PersistenceValueCoding.uuid("BAD", field: "id")) {
            XCTAssertEqual($0 as? PersistenceValueCodingError, .corruption("id"))
        }
        XCTAssertThrowsError(try PersistenceValueCoding.counter(UInt64.max, field: "count")) {
            XCTAssertEqual($0 as? PersistenceValueCodingError, .invalidRepresentation("count"))
        }
    }
}
