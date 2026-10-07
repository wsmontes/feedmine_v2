// swift-tools-version: 6.0

// File: Package.swift
// Module: FeedMine package manifest
//
// Responsibility:
//   Declare compiler-enforced module boundaries and the architecture smoke test.
//
// Owns:
//   Package products and target dependency graph.
//
// Does not own:
//   Production behavior or application object composition.
//
// Allowed dependencies:
//   PackageDescription only; no external package dependencies.
//
// Architectural invariants:
//   INV-12, INV-15; ten production modules and one test target.
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
    dependencies: [],
    targets: [
        .target(name: "FeedMineDomain", dependencies: []),
        .target(name: "FeedMinePersistence", dependencies: ["FeedMineDomain"]),
        .target(name: "FeedMineAcquisition", dependencies: ["FeedMineDomain", "FeedMinePersistence"]),
        .target(name: "FeedMineSyndication", dependencies: ["FeedMineDomain", "FeedMineAcquisition"]),
        .target(name: "FeedMineEditorial", dependencies: ["FeedMineDomain", "FeedMinePersistence"]),
        .target(name: "FeedMineMedia", dependencies: ["FeedMineDomain", "FeedMinePersistence"]),
        .target(name: "FeedMinePublication", dependencies: ["FeedMineDomain", "FeedMinePersistence", "FeedMineEditorial", "FeedMineMedia"]),
        .target(name: "FeedMineRuntime", dependencies: ["FeedMineDomain", "FeedMinePersistence", "FeedMineAcquisition", "FeedMineEditorial", "FeedMineMedia", "FeedMinePublication"]),
        .target(name: "FeedMineUI", dependencies: ["FeedMineDomain", "FeedMineRuntime"]),
        .target(name: "FeedMineComposition", dependencies: ["FeedMineDomain", "FeedMinePersistence", "FeedMineAcquisition", "FeedMineSyndication", "FeedMineEditorial", "FeedMineMedia", "FeedMinePublication", "FeedMineRuntime", "FeedMineUI"]),
        .testTarget(
            name: "ArchitectureSmokeTests",
            dependencies: ["FeedMineDomain", "FeedMinePersistence", "FeedMineAcquisition", "FeedMineSyndication", "FeedMineEditorial", "FeedMineMedia", "FeedMinePublication", "FeedMineRuntime", "FeedMineUI", "FeedMineComposition"]
        ),
    ]
)
