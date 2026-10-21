// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuadrantLauncher",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(name: "QuadrantCore"),
        .target(
            name: "QuadrantSystem",
            dependencies: ["QuadrantCore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(name: "QuadrantUI", dependencies: ["QuadrantCore"]),
        .executableTarget(
            name: "QuadrantApp",
            dependencies: ["QuadrantCore", "QuadrantSystem", "QuadrantUI"]
        ),
        .executableTarget(name: "PanelSpike"),
        .testTarget(name: "QuadrantCoreTests", dependencies: ["QuadrantCore"]),
        .testTarget(name: "QuadrantSystemTests", dependencies: ["QuadrantSystem"]),
    ]
)
