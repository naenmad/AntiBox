// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AntiBox",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AntiBox", targets: ["AntiBox"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "AntiBox",
            path: "Sources"
        ),
        .testTarget(
            name: "AntiBoxTests",
            dependencies: ["AntiBox"],
            path: "Tests"
        )
    ]
)
