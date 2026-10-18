// File: StageBudgetPolicy.swift
// Module: FeedMineComposition
//
// Responsibility:
// R09: map **measured** pressure facts to the explicit resource authorization of one opportunity. The bootstrap
// (48 plan / 8 sockets / 32 examined / 1 MB) is used when nothing was measured; measured pressure may only reduce
// work, never invent capacity and never below one eligible target (fairness).
//
// Does not own: planning, execution, scheduling or editorial quotas. It is a pure function of facts and settings.
import Foundation
import FeedMineAcquisition

/// The pressure facts the platform can state now. Every field is measured or declared; nil is "not measured".
public struct StagePressureFacts: Hashable, Sendable {
    public enum Level: Int, Comparable, Sendable {
        case nominal = 0, fair = 1, serious = 2, critical = 3
        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }
    public let thermal: Level
    public let lowPowerMode: Bool
    public let networkConstrained: Bool
    /// Free capacity for important usage; nil when the volume could not be asked.
    public let freeStorageBytes: Int64?

    public init(thermal: Level, lowPowerMode: Bool, networkConstrained: Bool, freeStorageBytes: Int64?) {
        self.thermal = thermal
        self.lowPowerMode = lowPowerMode
        self.networkConstrained = networkConstrained
        self.freeStorageBytes = freeStorageBytes
    }
}

/// One opportunity's explicit authorization for both stages: network planning and local examination.
public struct StageBudget: Hashable, Sendable {
    public let acquisition: AcquisitionPlanningResources
    public let examinedCandidateCapacity: Int
    /// Local work is never turned off by pressure: a stationary reader under thermal pressure still reads from the
    /// store. The examined capacity shrinks instead, which is the work that can be deferred without starving.
    public let localWorkAllowed: Bool

    public init(acquisition: AcquisitionPlanningResources, examinedCandidateCapacity: Int,
        localWorkAllowed: Bool = true) {
        self.acquisition = acquisition
        self.examinedCandidateCapacity = max(1, examinedCandidateCapacity)
        self.localWorkAllowed = localWorkAllowed
    }
}

public enum StageBudgetPolicy {
    /// The documented bootstrap: `CollectionLaunchSettings.defaultInitialParallelism` (48) planned per opportunity,
    /// `maximumConcurrentTargets` (8) opening at once, 32 examined candidates and 1 MB per pull. No measured pressure
    /// exists, so nothing is adapted.
    public static func bootstrap(_ settings: CollectionLaunchSettings = .init()) -> StageBudget {
        .init(acquisition: .init(targetWorkCapacity: settings.targetWorkCapacity,
            batchCapacityPerNewExecution: 1, observationCapacityPerBatch: 32,
            byteCapacityPerBatch: 1_000_000)!, examinedCandidateCapacity: 32)
    }

    /// Measured pressure may reduce the plan, the examined window and the pull's byte budget. It never exceeds the
    /// bootstrap and never drops the plan below one target: a pressured reader still progresses, one target at a
    /// time. Thresholds are policy, stated here once and tested.
    public static func budget(pressure: StagePressureFacts?, settings: CollectionLaunchSettings = .init()) -> StageBudget {
        let bootstrap = bootstrap(settings)
        guard let pressure else { return bootstrap }
        var capacity = settings.targetWorkCapacity
        var examined = 32
        var bytes = 1_000_000
        switch pressure.thermal {
        case .nominal: break
        case .fair:
            capacity = max(1, capacity / 2)
            examined = 16
        case .serious:
            capacity = max(1, min(capacity, 8))
            examined = 12
            bytes = 500_000
        case .critical:
            capacity = 1
            examined = 8
            bytes = 250_000
        }
        if pressure.lowPowerMode { capacity = max(1, min(capacity, 8)); examined = min(examined, 12) }
        if pressure.networkConstrained { capacity = max(1, capacity / 2); bytes = min(bytes, 500_000) }
        if let free = pressure.freeStorageBytes, free < 100_000_000 { bytes = min(bytes, 500_000) }
        return .init(acquisition: .init(targetWorkCapacity: max(1, capacity),
            batchCapacityPerNewExecution: 1, observationCapacityPerBatch: 32,
            byteCapacityPerBatch: max(1, bytes))!, examinedCandidateCapacity: max(8, examined))
    }
}
