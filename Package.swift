// swift-tools-version: 6.0

// File: Package.swift
// Module: FeedMine package manifest
//
// Responsibility:
//   Declare compiler-enforced module boundaries and architecture/domain test targets.
//
// Owns:
//   Package products and target dependency graph.
//
// Does not own:
//   Production behavior or application object composition.
//
// Allowed dependencies:
//   PackageDescription only; GRDB 7.11.1 is the only external package dependency; confined to Persistence and its tests.
//
// Architectural invariants:
//   INV-12, INV-15; ten production modules and architecture/domain/persistence/publication test targets.
//
// Planned public surface:
//   The ten FeedMine library modules; no runtime API is declared here.
//
// Status:
//   Architecture scaffold only. Production behavior is intentionally absent.
//

import PackageDescription

let package = Package(
    name: "FeedMine",
    platforms: [
        .iOS(.v18),
        .macOS(.v14)
    ],
    products: [
        .library(name: "FeedMineDomain", targets: ["FeedMineDomain"]),
        .library(name: "FeedMinePersistence", targets: ["FeedMinePersistence"]),
        .library(name: "FeedMineAcquisition", targets: ["FeedMineAcquisition"]),
        .library(name: "FeedMineSyndication", targets: ["FeedMineSyndication"]),
        .library(name: "FeedMineEditorial", targets: ["FeedMineEditorial"]),
        .library(name: "FeedMineMedia", targets: ["FeedMineMedia"]),
        .library(name: "FeedMinePublication", targets: ["FeedMinePublication"]),
        .library(name: "FeedMineRuntime", targets: ["FeedMineRuntime"]),
        .library(name: "FeedMineUI", targets: ["FeedMineUI"]),
        .library(name: "FeedMineComposition", targets: ["FeedMineComposition"]),
    ],
    dependencies: [.package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1")],
    targets: [
        .target(name: "FeedMineDomain", dependencies: []),
        .target(name: "FeedMinePersistence", dependencies: ["FeedMineDomain", .product(name: "GRDB", package: "GRDB.swift")]),
        .target(name: "FeedMineAcquisition", dependencies: ["FeedMineDomain", "FeedMinePersistence"]),
        .target(name: "FeedMineSyndication", dependencies: ["FeedMineDomain", "FeedMineAcquisition"]),
        .target(name: "FeedMineEditorial", dependencies: ["FeedMineDomain", "FeedMinePersistence"]),
        .target(name: "FeedMineMedia", dependencies: ["FeedMineDomain", "FeedMinePersistence"]),
        .target(name: "FeedMinePublication", dependencies: ["FeedMineDomain", "FeedMinePersistence", "FeedMineEditorial", "FeedMineMedia"]),
        .target(name: "FeedMineRuntime", dependencies: ["FeedMineDomain", "FeedMinePersistence", "FeedMineAcquisition", "FeedMineEditorial", "FeedMineMedia", "FeedMinePublication"]),
        .target(name: "FeedMineUI", dependencies: ["FeedMineDomain", "FeedMineRuntime"]),
        .target(name: "FeedMineComposition", dependencies: ["FeedMineDomain", "FeedMinePersistence", "FeedMineAcquisition", "FeedMineSyndication", "FeedMineEditorial", "FeedMineMedia", "FeedMinePublication", "FeedMineRuntime", "FeedMineUI"]),
        .testTarget(name: "FeedMinePersistenceTests", dependencies: ["FeedMinePersistence", "FeedMineDomain", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "FeedMineDomainTests", dependencies: ["FeedMineDomain"]),
        .testTarget(name: "FeedMinePublicationTests", dependencies: ["FeedMinePublication", "FeedMineDomain", "FeedMineMedia", "FeedMinePersistence"]),
        .testTarget(name: "FeedMineRuntimeTests", dependencies: ["FeedMineRuntime", "FeedMineDomain", "FeedMinePublication", "FeedMinePersistence", "FeedMineMedia"]),
        .testTarget(
            name: "ArchitectureSmokeTests",
            dependencies: ["FeedMineDomain", "FeedMinePersistence", "FeedMineAcquisition", "FeedMineSyndication", "FeedMineEditorial", "FeedMineMedia", "FeedMinePublication", "FeedMineRuntime", "FeedMineUI", "FeedMineComposition"]
        ),
    ]
)
