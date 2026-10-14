// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "tpapp",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "TPCore", targets: ["TPCore"]),
        .library(name: "TPCloudFeature", targets: ["TPCloudFeature"]),
        .library(name: "TPStoreFeature", targets: ["TPStoreFeature"]),
        .library(name: "TPHomeFeature", targets: ["TPHomeFeature"]),
        .library(name: "TPPhotosFeature", targets: ["TPPhotosFeature"]),
    ],
    targets: [
        .target(name: "TPCore"),
        .target(name: "TPCloudFeature", dependencies: ["TPCore"]),
        .target(name: "TPStoreFeature", dependencies: ["TPCore"]),
        .target(name: "TPHomeFeature", dependencies: ["TPCore"]),
        .target(name: "TPPhotosFeature", dependencies: ["TPCore"]),

        .testTarget(name: "TPCoreTests", dependencies: ["TPCore"]),
        .testTarget(name: "TPCloudFeatureTests", dependencies: ["TPCloudFeature"]),
        .testTarget(name: "TPStoreFeatureTests", dependencies: ["TPStoreFeature"]),
        .testTarget(name: "TPHomeFeatureTests", dependencies: ["TPHomeFeature"]),
        .testTarget(name: "TPPhotosFeatureTests", dependencies: ["TPPhotosFeature"]),
    ]
)
