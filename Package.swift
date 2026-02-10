// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ExoSentry",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ExoSentryCore",
            targets: ["ExoSentryCore"]
        ),
        .library(
            name: "ExoSentryXPC",
            targets: ["ExoSentryXPC"]
        ),
        .executable(
            name: "ExoSentryHelper",
            targets: ["ExoSentryHelper"]
        ),
        .executable(
            name: "ExoSentryApp",
            targets: ["ExoSentryApp"]
        )
    ],
    targets: [
        .target(
            name: "ExoSentryCore"
        ),
        .target(
            name: "ExoSentryXPC",
            dependencies: ["ExoSentryCore"]
        ),
        .executableTarget(
            name: "ExoSentryHelper"
        ),
        .executableTarget(
            name: "ExoSentryApp",
            dependencies: ["ExoSentryCore", "ExoSentryXPC"]
        ),
        .testTarget(
            name: "ExoSentryCoreTests",
            dependencies: ["ExoSentryCore"]
        ),
        .testTarget(
            name: "ExoSentryXPCTests",
            dependencies: ["ExoSentryXPC", "ExoSentryCore", "ExoSentryHelper"]
        )
    ]
)
