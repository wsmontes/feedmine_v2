import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineAcquisition

final class AcquisitionTargetTests: XCTestCase {
    private func location() -> RuntimeDatabaseLocation {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return RuntimeDatabaseLocation(directory: root)
    }

    func testSemanticRegisterCheckpointStateConfigurationAndReopen() throws {
        let location = location(), id = AcquisitionTargetID()
        let checkpoint = AcquisitionCheckpoint(blob: Data(),serializationSchema: 2,connectorVersion: " fake-1 ")!
        let final: AcquisitionTarget
        do {
            let authority = AcquisitionTargetAuthority(database: try RuntimeDatabase(location: location))
            let initial = try authority.register(id: id,connectorKind: ConnectorKind(rawValue: " fake "))
            XCTAssertEqual(initial.id,id); XCTAssertEqual(initial.connectorKind.rawValue," fake ")
            XCTAssertEqual(initial.state,.enabled); XCTAssertEqual(initial.generation,1)
            XCTAssertEqual(initial.checkpointRevision,0); XCTAssertNil(initial.checkpoint)
            let installed = try authority.compareAndSwapCheckpoint(id: id,expectedGeneration: 1,expectedCheckpointRevision: 0,next: checkpoint)
            XCTAssertEqual(installed.checkpoint,checkpoint); XCTAssertEqual(installed.checkpointRevision,1)
            let revoked = try authority.revoke(id: id,expectedGeneration: 1)
            XCTAssertEqual(revoked.state,.revoked); XCTAssertEqual(revoked.generation,2)
            let configured = try authority.reconfigure(id: id,expectedGeneration: 2,connectorKind: ConnectorKind(rawValue: "other"),checkpoint: .preserve)
            XCTAssertEqual(configured.id,id); XCTAssertEqual(configured.generation,3); XCTAssertEqual(configured.state,.revoked)
            XCTAssertEqual(configured.checkpoint,checkpoint)
            let enabled = try authority.enable(id: id,expectedGeneration: 3)
            XCTAssertEqual(enabled.state,.enabled); XCTAssertEqual(enabled.generation,4)
            let record = AcquisitionTargetStore.CheckpointRecord(blob: Data([1]),serializationSchema: 3,connectorVersion: "next")!
            let replaced = try authority.reconfigure(id: id,expectedGeneration: 4,connectorKind: .syndication,checkpoint: .replace(record))
            XCTAssertEqual(replaced.checkpoint?.blob,Data([1])); XCTAssertEqual(replaced.checkpointRevision,2)
            final = try authority.reconfigure(id: id,expectedGeneration: 5,connectorKind: .syndication,checkpoint: .clear)
            XCTAssertNil(final.checkpoint); XCTAssertEqual(final.checkpointRevision,3)
        }
        let reopened = AcquisitionTargetAuthority(database: try RuntimeDatabase(location: location))
        XCTAssertEqual(try reopened.target(id: id),final)
        XCTAssertNil(try reopened.target(id: AcquisitionTargetID()))
    }

    func testExplicitEmptyCheckpointSurvivesReopenDistinctFromAbsent() throws {
        let location = location(), id = AcquisitionTargetID()
        do {
            let authority = AcquisitionTargetAuthority(database: try RuntimeDatabase(location: location))
            _ = try authority.register(id: id,connectorKind: .syndication)
            _ = try authority.compareAndSwapCheckpoint(id: id,expectedGeneration: 1,expectedCheckpointRevision: 0,
                next: AcquisitionCheckpoint(blob: Data(),serializationSchema: 1,connectorVersion: "fake")!)
        }
        let target = try AcquisitionTargetAuthority(database: RuntimeDatabase(location: location)).target(id: id)
        XCTAssertEqual(target?.checkpoint?.blob,Data()); XCTAssertNotNil(target?.checkpoint)
    }

    func testInvalidValuesAndExactStrings() throws {
        XCTAssertNil(AcquisitionCheckpoint(blob: Data(),serializationSchema: 0,connectorVersion: "v"))
        XCTAssertNil(AcquisitionCheckpoint(blob: Data(),serializationSchema: 1,connectorVersion: ""))
        XCTAssertNotNil(AcquisitionCheckpoint(blob: Data(),serializationSchema: 1,connectorVersion: " "))
        func value(_ kind: String, _ generation: UInt64) -> AcquisitionTarget? {
            AcquisitionTarget(id: AcquisitionTargetID(),connectorKind: ConnectorKind(rawValue: kind),generation: generation,
                state: .enabled,checkpointRevision: .max,checkpoint: nil)
        }
        XCTAssertNil(value("",1)); XCTAssertNil(value("fake",0)); XCTAssertNotNil(value(" ",1))
        let authority = AcquisitionTargetAuthority(database: try RuntimeDatabase(location: location()))
        let id = AcquisitionTargetID(); _ = try authority.register(id: id,connectorKind: .syndication)
        XCTAssertThrowsError(try authority.register(id: id,connectorKind: .syndication)) {
            XCTAssertEqual($0 as? AcquisitionTargetStoreError,.targetAlreadyExists(id))
        }
    }
    func testNominalIdentityCodingAndBaselineReenableFence() throws {
        let id = AcquisitionTargetID(rawValue: UUID())
        XCTAssertEqual(try JSONDecoder().decode(AcquisitionTargetID.self,from: JSONEncoder().encode(id)),id)
        XCTAssertEqual(id.description,id.rawValue.uuidString)
        let authority = AcquisitionTargetAuthority(database: try RuntimeDatabase(location: location()))
        _ = try authority.register(id: id,connectorKind: .syndication)
        let revoked = try authority.revoke(id: id,expectedGeneration: 1)
        XCTAssertEqual(revoked.generation,2)
        let enabled = try authority.enable(id: id,expectedGeneration: 2)
        XCTAssertEqual(enabled.id,id); XCTAssertEqual(enabled.generation,3); XCTAssertEqual(enabled.state,.enabled)
    }

}
