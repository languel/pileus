// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CloudPurge",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CloudPurge", targets: ["CloudPurgeApp"]),
        .library(name: "CloudPurgeCore", targets: ["CloudPurgeCore"])
    ],
    targets: [
        .target(
            name: "CloudPurgeCore",
            path: "Sources/CloudPurgeCore"
        ),
        .executableTarget(
            name: "CloudPurgeApp",
            dependencies: ["CloudPurgeCore"],
            path: "Sources/CloudPurgeApp"
        ),
        .testTarget(
            name: "CloudPurgeTests",
            dependencies: ["CloudPurgeCore"],
            path: "Tests/CloudPurgeTests"
        )
    ]
)
