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
            ]
        )
    ]
)
