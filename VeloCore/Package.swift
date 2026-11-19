// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VeloCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "VeloCore", targets: ["VeloCore"]),
    ],
    targets: [
        .target(name: "VeloCore"),
        .testTarget(
            name: "VeloCoreTests",
            dependencies: ["VeloCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
