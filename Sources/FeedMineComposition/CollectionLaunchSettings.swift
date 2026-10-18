// File: CollectionLaunchSettings.swift
// Module: FeedMineComposition
//
// Responsibility:
//   State how much acquisition work one launch may plan at once, and the operational ceiling that actually
//   opens sockets.
//
// Owns:
//   The product's initial parallelism (spec item A) and its conservative socket cap.
//
// Does not own:
//   Planning or execution. `AcquisitionPlanningResources` stays caller-supplied with no defaults, and the
//   planner still walks exactly the order it is given.
//
// Status:
//   Spec "Estabilidade de coleta e UI", item A: V1 opened up to 48 initial fetches; V2's launch planned two.

import Foundation

/// The launch's parallelism budget, supplied by the composition that builds the association.
///
/// `initialParallelism` is the **plan** budget: how many targets one acquisition opportunity may name. The
/// operational ceiling is deliberately smaller (`maximumConcurrentTargets`) and is what bounds simultaneous
/// target executions: a large or mistaken configuration can plan more work, never open more sockets.
public struct CollectionLaunchSettings: Hashable, Sendable {
    /// V1's initial parallelism, and the spec's proposed default.
    public static let defaultInitialParallelism = 48
    /// Conservative operational ceiling on simultaneous target executions. The coordinator refills its
    /// sliding window as targets settle; a larger plan never starts all 48 targets at once.
    public static let maximumConcurrentTargets = 8

    /// How many targets one acquisition opportunity may plan. Negative input is not "disabled twice": it is
    /// clamped to zero, which the planner already refuses as `.resourceDenied`.
    public let initialParallelism: Int

    /// - Parameter initialParallelism: caller-supplied plan budget; the only default in the product lives here,
    ///   never in `AcquisitionPlanningResources`.
    public init(initialParallelism: Int = Self.defaultInitialParallelism) {
        self.initialParallelism = max(0, initialParallelism)
    }

    /// What `AcquisitionPlanningResources.targetWorkCapacity` receives.
    public var targetWorkCapacity: Int { initialParallelism }

    /// What `AcquisitionCoordinator` receives: the configured value, capped. At least one execution can run
    /// whenever the planner admits work.
    public var concurrentTargetLimit: Int {
        max(1, min(initialParallelism, Self.maximumConcurrentTargets))
    }
}
