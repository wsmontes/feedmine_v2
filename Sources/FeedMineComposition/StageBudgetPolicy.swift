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
    /// P05: the useful production actually measured for this configuration — cards the reader can use per second.
    /// nil means "not measured", never zero. The reference rates are the plan's 1 card/s everyday consumption and
    /// its 3 cards/s bursts; more examination than those rates justify is not authorized.
    public let usefulCardsPerSecond: Double?

    public init(thermal: Level, lowPowerMode: Bool, networkConstrained: Bool, freeStorageBytes: Int64?,
        usefulCardsPerSecond: Double? = nil) {
        self.thermal = thermal
        self.lowPowerMode = lowPowerMode
        self.networkConstrained = networkConstrained
        self.freeStorageBytes = freeStorageBytes
        self.usefulCardsPerSecond = usefulCardsPerSecond
    }
}

/// P05: the one volume read a stage budget needs. It is sampled **off the caller** at causal lifecycle moments and
/// read afterwards as a snapshot, so computing a budget never performs filesystem I/O on the MainActor.
public final class StageStorageCapacity: @unchecked Sendable {
    public typealias Read = @Sendable () -> Int64?
    private let lock = NSLock()
    private var value: Int64?
    private var samples = 0
    private let read: Read

    public init(read: @escaping Read) { self.read = read }

    public var current: Int64? { lock.lock(); defer { lock.unlock() }; return value }
    public var sampleCount: Int { lock.lock(); defer { lock.unlock() }; return samples }

    /// Runs the read on a cooperative background executor. Absence stays absence (`nil`), never a guess.
    public func refresh() async {
        let sampled = await Task.detached(priority: .utility) { self.read() }.value
        store(sampled)
    }

    private func store(_ sampled: Int64?) {
        lock.lock(); value = sampled; samples += 1; lock.unlock()
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
        let authorized = settings.targetWorkCapacity
        var capacity = authorized
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
        // P05: measured useful yield sizes the examination window. The thresholds are the plan's own reference
        // rates: below 1 card/s the stage is not even sustaining everyday consumption, between 1 and 3 it may
        // sustain it, and at 3 (the burst) the bootstrap window is justified. Absent stays unknown.
        if let yield = pressure.usefulCardsPerSecond, yield.isFinite, yield >= 0 {
            let justified: Int
            if yield >= 3 { justified = 32 }
            else if yield >= 1 { justified = 16 }
            else { justified = 8 }
            examined = min(examined, justified)
        }
        // Fairness applies **between authorized targets**: an explicit zero is a denial of the resource and stays
        // zero under every pressure combination. Pressure may only lower a positive authorization.
        let finalCapacity = authorized == 0 ? 0 : max(1, min(capacity, authorized))
        return .init(acquisition: .init(targetWorkCapacity: finalCapacity,
            batchCapacityPerNewExecution: 1, observationCapacityPerBatch: 32,
            byteCapacityPerBatch: max(1, bytes))!, examinedCandidateCapacity: max(8, examined))
    }
}
