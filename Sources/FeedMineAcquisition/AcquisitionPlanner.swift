// Owns: a pure finite acquisition decision over explicit eligibility, active facts and physical resources.
// Does not own: eligibility discovery, execution, freshness policy or persistent planning state.
import FeedMineDomain

public struct AcquisitionActiveExecution: Hashable, Sendable {
    public let targetID: AcquisitionTargetID
    public let generation: UInt64

    public init?(targetID: AcquisitionTargetID, generation: UInt64) {
        guard generation > 0 else { return nil }
        self.targetID = targetID
        self.generation = generation
    }
}

public struct AcquisitionPlanningResources: Hashable, Sendable {
    public let targetWorkCapacity: Int
    public let batchCapacityPerNewExecution: Int
    public let observationCapacityPerBatch: Int
    public let byteCapacityPerBatch: Int

    public init?(targetWorkCapacity: Int, batchCapacityPerNewExecution: Int,
        observationCapacityPerBatch: Int, byteCapacityPerBatch: Int) {
        guard targetWorkCapacity >= 0, batchCapacityPerNewExecution >= 0,
            observationCapacityPerBatch >= 0, byteCapacityPerBatch >= 0 else { return nil }
        self.targetWorkCapacity = targetWorkCapacity
        self.batchCapacityPerNewExecution = batchCapacityPerNewExecution
        self.observationCapacityPerBatch = observationCapacityPerBatch
        self.byteCapacityPerBatch = byteCapacityPerBatch
    }
}

public struct AcquisitionWorkBounds: Hashable, Sendable {
    public let batchCapacity: Int
    public let observationCapacityPerBatch: Int
    public let byteCapacityPerBatch: Int

    public init?(batchCapacity: Int, observationCapacityPerBatch: Int, byteCapacityPerBatch: Int) {
        guard batchCapacity > 0, observationCapacityPerBatch > 0, byteCapacityPerBatch > 0 else { return nil }
        self.batchCapacity = batchCapacity
        self.observationCapacityPerBatch = observationCapacityPerBatch
        self.byteCapacityPerBatch = byteCapacityPerBatch
    }
}

public enum AcquisitionPlannedWork: Hashable, Sendable {
    case start(target: AcquisitionTarget, bounds: AcquisitionWorkBounds)
    case joinActive(target: AcquisitionTarget)
}

public struct AcquisitionPlan: Hashable, Sendable {
    public let demand: AcquisitionDemand
    public let work: [AcquisitionPlannedWork]

    fileprivate init(demand: AcquisitionDemand, work: [AcquisitionPlannedWork]) {
        precondition(!work.isEmpty)
        self.demand = demand
        self.work = work
    }
}

public enum AcquisitionPlanningDisposition: Hashable, Sendable {
    case noEligibleTargets
    case resourceDenied
    case activeGenerationConflict
}

public enum AcquisitionPlanningResult: Hashable, Sendable {
    case planned(AcquisitionPlan)
    case disposition(AcquisitionPlanningDisposition)
}

public enum AcquisitionPlannerError: Error, Equatable, Sendable {
    case inconsistentEligibleTarget(AcquisitionTargetID)
    case inconsistentActiveExecution(AcquisitionTargetID)
}

public enum AcquisitionPlanner {
    public static func plan(demand: AcquisitionDemand, eligibleTargets: [AcquisitionTarget],
        activeExecutions: [AcquisitionActiveExecution], resources: AcquisitionPlanningResources, selectionAfter: AcquisitionTargetID? = nil) throws -> AcquisitionPlanningResult {
        // Normalize all caller facts before filtering or applying capacity limits.
        var byID: [AcquisitionTargetID: AcquisitionTarget] = [:]
        var orderedTargets: [AcquisitionTarget] = []
        for target in eligibleTargets {
            if let previous = byID[target.id] {
                guard sameSnapshot(previous, target) else {
                    throw AcquisitionPlannerError.inconsistentEligibleTarget(target.id)
                }
            } else {
                byID[target.id] = target
                orderedTargets.append(target)
            }
        }
        var activeGenerations: [AcquisitionTargetID: UInt64] = [:]
        for execution in activeExecutions {
            if let previous = activeGenerations[execution.targetID], previous != execution.generation {
                throw AcquisitionPlannerError.inconsistentActiveExecution(execution.targetID)
            }
            activeGenerations[execution.targetID] = execution.generation
        }
        var enabled = orderedTargets.filter { $0.state == .enabled }
        if let selectionAfter {
            // Identity order is a mechanical ring, not an editorial or freshness priority.
            // A removed/revoked marker still identifies a boundary in that ring.
            enabled.sort { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
            let next = enabled.firstIndex { $0.id.rawValue.uuidString > selectionAfter.rawValue.uuidString } ?? 0
            enabled = Array(enabled[next...]) + Array(enabled[..<next])
        }
        guard !enabled.isEmpty else { return .disposition(.noEligibleTargets) }
        guard resources.targetWorkCapacity > 0 else { return .disposition(.resourceDenied) }

        let bounds = AcquisitionWorkBounds(batchCapacity: resources.batchCapacityPerNewExecution,
            observationCapacityPerBatch: resources.observationCapacityPerBatch, byteCapacityPerBatch: resources.byteCapacityPerBatch)
        var work: [AcquisitionPlannedWork] = []
        var generationConflict = false
        var startDeniedByResources = false
        for target in enabled {
            guard work.count < resources.targetWorkCapacity else { break }
            if let generation = activeGenerations[target.id] {
                if generation == target.generation {
                    work.append(.joinActive(target: target))
                } else {
                    generationConflict = true
                }
            } else if let bounds {
                work.append(.start(target: target, bounds: bounds))
            } else {
                // Continue: a later target may be joinable without a new-execution budget.
                startDeniedByResources = true
            }
        }
        if !work.isEmpty { return .planned(AcquisitionPlan(demand: demand, work: work)) }
        if startDeniedByResources { return .disposition(.resourceDenied) }
        if generationConflict { return .disposition(.activeGenerationConflict) }
        return .disposition(.noEligibleTargets)
    }

    private static func sameSnapshot(_ a: AcquisitionTarget, _ b: AcquisitionTarget) -> Bool {
        guard a.id == b.id, a.generation == b.generation, a.state == b.state,
            a.checkpointRevision == b.checkpointRevision,
            a.connectorKind.rawValue.utf8.elementsEqual(b.connectorKind.rawValue.utf8) else { return false }
        switch (a.checkpoint, b.checkpoint) {
        case (nil, nil): return true
        case (.some(let a), .some(let b)):
            return a.blob == b.blob && a.serializationSchema == b.serializationSchema
                && a.connectorVersion.utf8.elementsEqual(b.connectorVersion.utf8)
        default: return false
        }
    }
}
