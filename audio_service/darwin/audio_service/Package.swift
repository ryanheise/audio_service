// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "audio_service",
    platforms: [
        .iOS("12.0"),
        .macOS("10.14")
    ],
    products: [
        .library(name: "audio-service", targets: ["audio_service"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "audio_service",
            dependencies: [],
            cSettings: [
                .headerSearchPath("include/audio_service")
            ],
            linkerSettings: [
                // CarPlay is used on iOS 14+ to update CPNowPlayingTemplate buttons
                // when a rating command (like/dislike) is active.
                // The framework is a system framework and does NOT require the CarPlay
                // entitlement — calling updateNowPlayingButtons is a no-op when no
                // CarPlay screen is connected.
                .linkedFramework("CarPlay", .when(platforms: [.iOS]))
            ]
        )
    ]
)
