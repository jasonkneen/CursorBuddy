// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Pucks",
    platforms: [
        .macOS(.v26)  // Requires macOS 26 for Liquid Glass
    ],
    products: [
        .executable(
            name: "Pucks",
            targets: ["Pucks"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
        .package(url: "https://github.com/PostHog/posthog-ios", from: "3.0.0"),
        .package(url: "https://github.com/microsoft/plcrashreporter", from: "1.11.0"),
    ],
    targets: [
        .executableTarget(
            name: "Pucks",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "PostHog", package: "posthog-ios"),
                .product(name: "CrashReporter", package: "plcrashreporter"),
            ],
            path: "Pucks",
            exclude: [
                "Info.plist",
                "Pucks.entitlements",
            ],
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
