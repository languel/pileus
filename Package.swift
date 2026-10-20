// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pileus",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Pileus", targets: ["PileusApp"]),
        .library(name: "PileusCore", targets: ["PileusCore"])
    ],
    targets: [
        .target(
            name: "PileusCore",
            path: "Sources/PileusCore"
        ),
        .executableTarget(
            name: "PileusApp",
            dependencies: ["PileusCore"],
            path: "Sources/PileusApp"
        ),
        .testTarget(
            name: "PileusTests",
            dependencies: ["PileusCore"],
            path: "Tests/PileusTests"
        )
    ]
)
