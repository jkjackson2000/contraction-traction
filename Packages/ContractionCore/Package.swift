// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ContractionCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ContractionCore", targets: ["ContractionCore"]),
    ],
    targets: [
        .target(name: "ContractionCore"),
        .testTarget(name: "ContractionCoreTests", dependencies: ["ContractionCore"]),
    ]
)
