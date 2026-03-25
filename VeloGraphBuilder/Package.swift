// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VeloGraphBuilder",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "VeloGraphBuilder",
            path: "Sources/VeloGraphBuilder",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
