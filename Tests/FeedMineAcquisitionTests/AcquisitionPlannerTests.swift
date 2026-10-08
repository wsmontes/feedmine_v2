import Foundation
import XCTest
import FeedMineDomain
import FeedMineAcquisition

final class AcquisitionPlannerTests: XCTestCase {
    private let revisionID = EditorialRevisionID()
    private func demand(_ required: Int = 5, ready: Int = 0, logical: Bool = false) -> AcquisitionDemand {
        AcquisitionDemand(contextKey: ContextKey(request: .main),editorialRevisionID: revisionID,
            purpose: .readerContinuation,pressure: logical ? .logicalTailPressure : .coverageDeficit(requiredCards: required),
            localSupply: ExhaustedLocalSupply(readyCards: ready)!)!
    }
    private func target(id: AcquisitionTargetID = AcquisitionTargetID(), generation: UInt64 = 1,
        state: AcquisitionTargetState = .enabled, kind: String = "syndication", revision: UInt64 = 0,
        checkpoint: AcquisitionCheckpoint? = nil) -> AcquisitionTarget {
        AcquisitionTarget(id: id,connectorKind: ConnectorKind(rawValue: kind),generation: generation,state: state,
            checkpointRevision: revision,checkpoint: checkpoint)!
    }
    private func resources(_ targets: Int = 2, batches: Int = 3, observations: Int = 17, bytes: Int = 12345) -> AcquisitionPlanningResources {
        AcquisitionPlanningResources(targetWorkCapacity: targets,batchCapacityPerNewExecution: batches,
            observationCapacityPerBatch: observations,byteCapacityPerBatch: bytes)!
    }
    private func active(_ target: AcquisitionTarget, generation: UInt64? = nil) -> AcquisitionActiveExecution {
        AcquisitionActiveExecution(targetID: target.id,generation: generation ?? target.generation)!
    }
    private var bounds: AcquisitionWorkBounds {
        AcquisitionWorkBounds(batchCapacity: 3,observationCapacityPerBatch: 17,byteCapacityPerBatch: 12345)!
    }
    private func result(_ targets: [AcquisitionTarget], active: [AcquisitionActiveExecution] = [],
        resources: AcquisitionPlanningResources? = nil, demand: AcquisitionDemand? = nil) throws -> AcquisitionPlanningResult {
        try AcquisitionPlanner.plan(demand: demand ?? self.demand(),eligibleTargets: targets,activeExecutions: active,
            resources: resources ?? self.resources())
    }
    private func plan(_ result: AcquisitionPlanningResult, file: StaticString = #filePath, line: UInt = #line) throws -> AcquisitionPlan {
        guard case .planned(let plan) = result else {
            XCTFail("Expected nonempty plan, got \(result)",file: file,line: line)
            throw NSError(domain: "AcquisitionPlannerTests",code: 1)
        }
        XCTAssertFalse(plan.work.isEmpty,file: file,line: line)
        return plan
    }

    func test01BasicOrder() throws {
        let a = target(), b = target(), c = target()
        let plan = try plan(result([a,b,c]))
        XCTAssertEqual(plan.work,[.start(target: a,bounds: bounds),.start(target: b,bounds: bounds)])
        XCTAssertEqual(plan.demand,demand())
    }
    func test02CapacityOne() throws {
        let a = target(), b = target(), c = target()
        XCTAssertEqual(try plan(result([a,b,c],resources: resources(1))).work,[.start(target: a,bounds: bounds)])
    }
    func test03CapacityExceedsTargets() throws {
        let a = target(), b = target()
        XCTAssertEqual(try plan(result([a,b],resources: resources(100))).work,[.start(target: a,bounds: bounds),.start(target: b,bounds: bounds)])
    }
    func test04EmptyEligibility() throws {
        XCTAssertEqual(try result([]),.disposition(.noEligibleTargets))
    }
    func test05RevokedOnly() throws {
        XCTAssertEqual(try result([target(state: .revoked),target(state: .revoked)]),.disposition(.noEligibleTargets))
    }
    func test06MixedRevokedAndEnabledOrder() throws {
        let a = target(state: .revoked), b = target(), c = target()
        XCTAssertEqual(try plan(result([a,b,c])).work,[.start(target: b,bounds: bounds),.start(target: c,bounds: bounds)])
        XCTAssertEqual(try plan(result([a,b,c],active: [active(a)])).work,[.start(target: b,bounds: bounds),.start(target: c,bounds: bounds)])
    }
    func test07TargetCapacityZero() throws {
        let a = target()
        XCTAssertEqual(try result([a],resources: resources(0)),.disposition(.resourceDenied))
        XCTAssertEqual(try result([a],active: [active(a)],resources: resources(0)),.disposition(.resourceDenied))
        XCTAssertEqual(try result([a],active: [active(a,generation: 2)],resources: resources(0)),.disposition(.resourceDenied))
        XCTAssertEqual(try result([],resources: resources(0)),.disposition(.noEligibleTargets))
    }
    func test08EachNewWorkBoundZero() throws {
        for resource in [resources(batches: 0),resources(observations: 0),resources(bytes: 0)] {
            XCTAssertEqual(try result([target()],resources: resource),.disposition(.resourceDenied))
        }
    }
    func test09JoinWithStartBudgetDeniedAndLaterJoinAfterDeniedStart() throws {
        let a = target(), b = target()
        for resource in [resources(1,batches: 0),resources(1,observations: 0),resources(1,bytes: 0),resources(1,batches: 0,observations: 0,bytes: 0)] {
            XCTAssertEqual(try plan(result([b],active: [active(b)],resources: resource)).work,[.joinActive(target: b)])
            XCTAssertEqual(try plan(result([a,b],active: [active(b)],resources: resource)).work,[.joinActive(target: b)])
        }
    }
    func test10SameGenerationJoin() throws {
        let t = target(generation: 4)
        XCTAssertEqual(try plan(result([t],active: [active(t)])).work,[.joinActive(target: t)])
        let a = target(), b = target()
        XCTAssertEqual(try plan(result([a,b],active: [active(a),active(b)],resources: resources(1))).work,[.joinActive(target: a)])
    }
    func test11OldGenerationConflict() throws {
        let t = target(generation: 5)
        XCTAssertEqual(try result([t],active: [active(t,generation: 4)]),.disposition(.activeGenerationConflict))
        // Any different generation blocks, including a supplied higher generation.
        XCTAssertEqual(try result([t],active: [active(t,generation: 6)]),.disposition(.activeGenerationConflict))
    }
    func test12ConflictSkipsToLaterTarget() throws {
        let a = target(generation: 2), b = target()
        XCTAssertEqual(try plan(result([a,b],active: [active(a,generation: 1)])).work,[.start(target: b,bounds: bounds)])
        XCTAssertEqual(try plan(result([b,a],active: [active(a,generation: 1)])).work,[.start(target: b,bounds: bounds)])
    }
    func test13ResourceDenialPrecedence() throws {
        let a = target(), b = target(generation: 2)
        XCTAssertEqual(try result([a,b],active: [active(b,generation: 1)],resources: resources(batches: 0)),.disposition(.resourceDenied))
        XCTAssertEqual(try result([b,a],active: [active(b,generation: 1)],resources: resources(batches: 0)),.disposition(.resourceDenied))
    }
    func test14OrderVsJoin() throws {
        let a = target(), b = target()
        XCTAssertEqual(try plan(result([a,b],active: [active(b)],resources: resources(1))).work,[.start(target: a,bounds: bounds)])
        XCTAssertEqual(try plan(result([a,b],active: [active(b)])).work,[.start(target: a,bounds: bounds),.joinActive(target: b)])
    }
    func test15ExactTargetDuplicate() throws {
        let a = target(), b = target()
        XCTAssertEqual(try plan(result([a,a,b])).work,[.start(target: a,bounds: bounds),.start(target: b,bounds: bounds)])
    }
    func test16InconsistentTargetDuplicate() throws {
        let a = target()
        let checkpoint = AcquisitionCheckpoint(blob: Data([1]),serializationSchema: 1,connectorVersion: "v")!
        for other in [target(id: a.id,generation: 2),target(id: a.id,state: .revoked),target(id: a.id,kind: "other"),
            target(id: a.id,revision: 1),target(id: a.id,checkpoint: checkpoint)] {
            XCTAssertThrowsError(try result([a,other])) { XCTAssertEqual($0 as? AcquisitionPlannerError,.inconsistentEligibleTarget(a.id)) }
        }
        // Validate every input before planning even if capacity would stop at the first target.
        XCTAssertThrowsError(try result([a,a,target(id: a.id,generation: 2)],resources: resources(0))) {
            XCTAssertEqual($0 as? AcquisitionPlannerError,.inconsistentEligibleTarget(a.id))
        }
    }
    func test17ExactActiveDuplicate() throws {
        let t = target()
        XCTAssertEqual(try plan(result([t],active: [active(t),active(t)])).work,[.joinActive(target: t)])
    }
    func test18InconsistentActiveDuplicate() throws {
        let t = target()
        XCTAssertThrowsError(try result([t],active: [active(t),active(t,generation: 2)])) {
            XCTAssertEqual($0 as? AcquisitionPlannerError,.inconsistentActiveExecution(t.id))
        }
        XCTAssertThrowsError(try result([],active: [active(t),active(t,generation: 2)])) {
            XCTAssertEqual($0 as? AcquisitionPlannerError,.inconsistentActiveExecution(t.id))
        }
    }
    func test19UnrelatedActiveFact() throws {
        let a = target(), b = target(), unrelated = target()
        XCTAssertEqual(try result([a,b]),try result([a,b],active: [active(unrelated)]))
    }
    func test20PressureMagnitudeIndependence() throws {
        let a = target(), b = target(), targets = [a,b], executions = [active(b)]
        let small = try plan(result(targets,active: executions,demand: demand(5)))
        let huge = try plan(result(targets,active: executions,demand: demand(5000,ready: 4999)))
        XCTAssertEqual(small.work,huge.work); XCTAssertEqual(small.demand,demand(5)); XCTAssertEqual(huge.demand,demand(5000,ready: 4999))
        XCTAssertNotEqual(small.demand,huge.demand)
    }
    func test21LogicalPressureIndependence() throws {
        let a = target(), b = target(), targets = [a,b], executions = [active(b)]
        XCTAssertEqual(try plan(result(targets,active: executions,demand: demand(logical: true))).work,
            try plan(result(targets,active: executions,demand: demand(5000))).work)
    }
    func test22ExactTargetSnapshotPreservedWithoutCheckpointPriority() throws {
        let checkpoint = AcquisitionCheckpoint(blob: Data([0,255,1]),serializationSchema: 3,connectorVersion: " V ")!
        let a = target(generation: 7,kind: " opaque Kind ",revision: 9,checkpoint: checkpoint), b = target()
        let result = try plan(result([a,b],active: [active(b)]))
        XCTAssertEqual(result.work,[.start(target: a,bounds: bounds),.joinActive(target: b)])
        XCTAssertEqual(try plan(self.result([a],active: [active(a)])).work,[.joinActive(target: a)])
        guard case .start(let supplied,_) = result.work[0] else { return XCTFail("Expected start") }
        XCTAssertEqual(supplied,a); XCTAssertEqual(supplied.checkpoint,checkpoint)
        XCTAssertEqual(supplied.checkpointRevision,9); XCTAssertEqual(supplied.generation,7)
        XCTAssertEqual(supplied.connectorKind.rawValue," opaque Kind ")
    }
    func test23ExactStartBounds() throws {
        let t = target()
        XCTAssertEqual(try plan(result([t],resources: resources(1,batches: 3,observations: 17,bytes: 12345))).work,[.start(target: t,bounds: bounds)])
    }
    func test24PureRepeatable() throws {
        let a = target(), b = target(), targets = [a,b], executions = [active(b)]
        XCTAssertEqual(try result(targets,active: executions),try result(targets,active: executions))
    }
    func testValueValidationForActiveResourcesAndBounds() {
        XCTAssertNil(AcquisitionActiveExecution(targetID: AcquisitionTargetID(),generation: 0))
        XCTAssertNotNil(AcquisitionActiveExecution(targetID: AcquisitionTargetID(),generation: .max))
        XCTAssertNotNil(AcquisitionPlanningResources(targetWorkCapacity: 0,batchCapacityPerNewExecution: 0,observationCapacityPerBatch: 0,byteCapacityPerBatch: 0))
        for values in [(-1,1,1,1),(1,-1,1,1),(1,1,-1,1),(1,1,1,-1)] {
            XCTAssertNil(AcquisitionPlanningResources(targetWorkCapacity: values.0,batchCapacityPerNewExecution: values.1,
                observationCapacityPerBatch: values.2,byteCapacityPerBatch: values.3))
        }
        for values in [(0,1,1),(1,0,1),(1,1,0),(-1,1,1),(1,-1,1),(1,1,-1)] {
            XCTAssertNil(AcquisitionWorkBounds(batchCapacity: values.0,observationCapacityPerBatch: values.1,byteCapacityPerBatch: values.2))
        }
    }
    func testSnapshotDuplicateRequiresByteExactOpaqueFacts() throws {
        let a = target(kind: "é")
        XCTAssertThrowsError(try result([a,target(id: a.id,kind: "e\u{301}")])) {
            XCTAssertEqual($0 as? AcquisitionPlannerError,.inconsistentEligibleTarget(a.id))
        }
        let c1 = AcquisitionCheckpoint(blob: Data([1]),serializationSchema: 1,connectorVersion: "é")!
        let c2 = AcquisitionCheckpoint(blob: Data([1]),serializationSchema: 1,connectorVersion: "e\u{301}")!
        let t = target(checkpoint: c1)
        XCTAssertThrowsError(try result([t,target(id: t.id,checkpoint: c2)])) {
            XCTAssertEqual($0 as? AcquisitionPlannerError,.inconsistentEligibleTarget(t.id))
        }
    }
}
