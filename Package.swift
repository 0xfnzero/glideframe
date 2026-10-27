// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GlideFrame",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GlideFrameKit", targets: ["GlideFrameKit"]),
        .library(name: "GlideFrameCaptureBridge", type: .dynamic, targets: ["GlideFrameCaptureBridge"]),
        .executable(name: "GlideFrame", targets: ["GlideFrameApp"]),
        .executable(name: "GlideFrameTauriHelper", targets: ["GlideFrameTauriHelper"]),
        .executable(name: "GlideFrameChecks", targets: ["GlideFrameChecks"])
    ],
    targets: [
        .target(name: "GlideFrameKit", exclude: ["Capture"]),
        .target(name: "GlideFrameCapture", dependencies: ["GlideFrameKit"], path: "Sources/GlideFrameKit/Capture"),
        .target(name: "GlideFrameCaptureBridge", dependencies: ["GlideFrameKit", "GlideFrameCapture"], exclude: ["LICENSE"]),
        .executableTarget(name: "GlideFrameTauriHelper", dependencies: ["GlideFrameCaptureBridge"], exclude: ["LICENSE"]),
        .executableTarget(
            name: "GlideFrameApp",
            dependencies: ["GlideFrameKit", "GlideFrameCapture"],
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
