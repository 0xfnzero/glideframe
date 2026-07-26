// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GlideFrame",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GlideFrameKit", targets: ["GlideFrameKit"]),
        .executable(name: "GlideFrame", targets: ["GlideFrameApp"]),
        .executable(name: "GlideFrameChecks", targets: ["GlideFrameChecks"])
    ],
    targets: [
        .target(name: "GlideFrameKit"),
        .executableTarget(
            name: "GlideFrameApp",
            dependencies: ["GlideFrameKit"],
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AVKit"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("VideoToolbox")
            ]
        ),
        .executableTarget(name: "GlideFrameChecks", dependencies: ["GlideFrameKit"]),
        .testTarget(name: "GlideFrameKitTests", dependencies: ["GlideFrameKit"])
    ]
)
