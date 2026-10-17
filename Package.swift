// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "tpapp",
    platforms: [
        .iOS(.v27),
        .macOS(.v27),
    ],
    products: [
        .library(name: "TPCore", targets: ["TPCore"]),
        .library(name: "TPUI", targets: ["TPUI"]),
        .library(name: "TPCloudFeature", targets: ["TPCloudFeature"]),
        .library(name: "TPStoreFeature", targets: ["TPStoreFeature"]),
        .library(name: "TPHomeFeature", targets: ["TPHomeFeature"]),
        .library(name: "TPPhotosFeature", targets: ["TPPhotosFeature"]),
        .library(name: "TPAdminFeature", targets: ["TPAdminFeature"]),
    ],
    targets: [
        .target(name: "TPCore"),
        // Shared SwiftUI building blocks (badges, error alerts, cached remote images) so every
        // feature draws from one visual vocabulary instead of its own copy of a theme.
        .target(name: "TPUI", dependencies: ["TPCore"]),
        .target(name: "TPCloudFeature", dependencies: ["TPCore", "TPUI"]),
        .target(name: "TPStoreFeature", dependencies: ["TPCore", "TPUI"]),
        .target(name: "TPHomeFeature", dependencies: ["TPCore", "TPUI"]),
        .target(name: "TPPhotosFeature", dependencies: ["TPCore", "TPUI"]),
        .target(name: "TPAdminFeature", dependencies: ["TPCore", "TPUI"]),

        .testTarget(name: "TPCoreTests", dependencies: ["TPCore"]),
        .testTarget(name: "TPCloudFeatureTests", dependencies: ["TPCloudFeature"]),
        .testTarget(name: "TPStoreFeatureTests", dependencies: ["TPStoreFeature"]),
        .testTarget(name: "TPHomeFeatureTests", dependencies: ["TPHomeFeature"]),
        .testTarget(name: "TPPhotosFeatureTests", dependencies: ["TPPhotosFeature"]),
        .testTarget(name: "TPAdminFeatureTests", dependencies: ["TPAdminFeature"]),
    ]
)
